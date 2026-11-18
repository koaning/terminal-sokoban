-- the game in a terminal: run with `luajit term.lua` or `make term`
--
-- this hosts the whole game (main.lua) the way LÖVE does, on top of softlove.lua, a small stand-in for LÖVE that
-- draws in software; Tab switches between the ways it can look:
--   pictures  every frame sent as images (kitty graphics protocol: Ghostty, kitty, WezTerm), HUD, menu and all
--   blocks    the art in character cells, two pixels a cell (▀), with the HUD, the menu and the map as text
--   octants   the art in character cells, eight dots a cell (Unicode 16 octants), so a room takes a quarter of the space
--   small     like blocks, with every pixel the average of four: as small as octants, but blurrier
--   text      the castle in coloured text, two characters a tile, without the menu, the map or the island
-- it starts with pictures where the terminal can show them, blocks otherwise (see termcells.lua for the cells)
--
--   luajit term.lua                play; progress is saved in the same place as the LÖVE game's
--   luajit term.lua --look <look>  start with this look: pictures, blocks, octants, small or text
--   luajit term.lua --text         the same as --look text
--   luajit term.lua --kitty        images, in a terminal that isn't recognised but can show them
--   luajit term.lua --fresh        start with nothing solved, and don't save
--   luajit term.lua --demo <keys>  types the keys by itself, one every 0.2s, then quits: for screenshots
--   luajit term.lua --log <file>   what the game prints goes into this file
--
-- when stdin isn't a terminal it plays the keys from the pipe and prints the last frame as text, or with --png <file>
-- saves it as a picture of a 1280x720 window (--size WxH for another size), so it can be scripted:
--   printf 'dddaaww' | luajit term.lua --fresh --png room2.png

local ffi = require "ffi"

ffi.cdef[[
struct winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
struct pollfd { int fd; short events; short revents; };
struct timespec { long tv_sec; long tv_nsec; };
int ioctl(int fd, unsigned long request, ...);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
long read(int fd, void *buf, size_t count);
int clock_gettime(int clock, struct timespec *tp);
int chdir(const char *path);
int isatty(int fd);
int memcmp(const void *a, const void *b, size_t n);
]]

-- run from the folder of this file, wherever it's started from: the game loads its files from there
local here = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$")
if here then
    ffi.C.chdir(here)
    package.path = "./?.lua;" .. package.path
end

local options = {}
do
    local i = 1
    while arg[i] do
        local name = arg[i]:match("^%-%-(.+)$")
        if name == "png" or name == "demo" or name == "log" or name == "size" or name == "pixel-scale"
            or name == "look" then
            options[name] = arg[i + 1]
            i = i + 1
        elseif name then
            options[name] = true
        end
        i = i + 1
    end
end

-- what the game prints would scribble over the picture: it goes into the log instead, if there is one
local logFile = options.log and io.open(options.log, "w")
print = function(...)
    if not logFile then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    logFile:write(table.concat(parts, "\t"), "\n")
    logFile:flush()
end

local CLOCK_MONOTONIC = jit.os == "OSX" and 6 or 1
local function now()
    local t = ffi.new("struct timespec")
    ffi.C.clock_gettime(CLOCK_MONOTONIC, t)
    return tonumber(t.tv_sec) + tonumber(t.tv_nsec)/1e9
end

----------------------------------------------------------------------------------------------------
-- the host: what softlove asks about the keyboard, the mouse and the clock
----------------------------------------------------------------------------------------------------

local host = {time = now, quitting = false, mouseX = 0, mouseY = 0}
-- the keys held down; without key releases from the terminal, a key counts as held for a moment after each press
-- (and each repeat while it's held), see keyHeld
local held, heldUntil = {}, {}
local keyHeld = 0.1

function host.isDown(k)
    return held[k] or (heldUntil[k] or 0) > now()
end

function host.quit() host.quitting = true end

local softlove = require "softlove"
softlove.install(host)

local progress = require "progress"
if options.fresh then
    -- like the screenshot tour of the LÖVE game: nothing solved, nothing saved
    progress.enabled = false
    progress.load = function() progress.results, progress.visited = {}, {} end
end

-- main.lua defines love.load, love.update, love.draw and the input callbacks, like it does in LÖVE
dofile("main.lua")
local game = require "game"
local levels = require "levels"
local sokoban = require "sokoban"
local menu = require "menu"
local picker = require "picker"
local termcells = require "termcells"

-- the ways the game can look, switched with Tab: pictures (kitty graphics protocol), the art in character cells
-- three ways (see termcells.lua), and the castle as coloured text
local looks = {"pictures", "blocks", "octants", "small", "text"}
local look -- the one in use

----------------------------------------------------------------------------------------------------
-- keys
----------------------------------------------------------------------------------------------------

-- LÖVE's name for a key, from its code point
local keyNames = {[13] = "return", [27] = "escape", [127] = "backspace", [8] = "backspace", [9] = "tab",
    [32] = "space", [57414] = "return"}
local arrowNames = {A = "up", B = "down", C = "right", D = "left", H = "home", F = "end"}

local function keyName(code)
    if keyNames[code] then return keyNames[code] end
    if code >= 65 and code <= 90 then code = code + 32 end
    if code < 32 or code > 126 then return nil end
    return string.char(code)
end

-- what was typed, as a list of events: {kind = "press" / "repeat" / "release", key = name, ctrl = true} for keys, and
-- {kind = "mouse", button, x, y, release} for the mouse (SGR mouse reports)
-- understands the kitty keyboard protocol (which also says when a key is let go) as well as plain bytes
local function parseInput(bytes)
    local events, i = {}, 1
    while i <= #bytes do
        local c = bytes:byte(i)
        if c == 27 and bytes:sub(i + 1, i + 1) == "[" then
            local body, final = bytes:match("^\27%[([%d;:<?]*)([%a~])", i)
            if not body then
                events[#events+1] = {kind = "press", key = "escape"}
                i = i + 1
            else
                i = i + 2 + #body + 1
                if body:sub(1, 1) == "?" and final == "u" then
                    -- the answer to asking whether the terminal does the kitty keyboard protocol
                    events[#events+1] = {kind = "protocol"}
                elseif body:sub(1, 1) == "<" then
                    -- a mouse report: button;x;y, M when pressed or moved, m when let go
                    local b, x, y = body:match("^<(%d+);(%d+);(%d+)$")
                    if b then
                        events[#events+1] = {kind = "mouse", button = tonumber(b), x = tonumber(x), y = tonumber(y),
                            release = final == "m"}
                    end
                else
                    local fields = {}
                    for field in (body .. ";"):gmatch("([^;]*);") do fields[#fields+1] = field end
                    local mods, kind = (fields[2] or ""):match("^(%d*):?(%d*)$")
                    mods = tonumber(mods) or 1
                    kind = ({["2"] = "repeat", ["3"] = "release"})[kind] or "press"
                    local name
                    if final == "u" then
                        name = keyName(tonumber((fields[1] or ""):match("^%d+")) or 0)
                    else
                        name = arrowNames[final]
                    end
                    if name then
                        events[#events+1] = {kind = kind, key = name, ctrl = (mods - 1) % 8 >= 4}
                    end
                end
            end
        elseif c == 27 and bytes:sub(i + 1, i + 1) == "O" and i + 2 <= #bytes then
            local name = arrowNames[bytes:sub(i + 2, i + 2)]
            if name then events[#events+1] = {kind = "press", key = name} end
            i = i + 3
        elseif c == 3 then
            events[#events+1] = {kind = "press", key = "c", ctrl = true}
            i = i + 1
        else
            local name = c == 27 and "escape" or c == 10 and "return" or keyName(c)
            if name then events[#events+1] = {kind = "press", key = name} end
            i = i + 1
        end
    end
    return events
end

local switchLook -- below

-- hands a key to the game; returns false to quit
local function sendKey(event)
    local k = event.key
    local textMode = look == "text"
    if event.ctrl and k == "c" then return false end
    if event.kind == "release" then
        held[k] = nil
        if love.keyreleased then love.keyreleased(k) end
        return true
    end
    if event.exact then held[k] = true else heldUntil[k] = now() + keyHeld end
    if event.kind == "repeat" then return true end
    if k == "tab" then
        switchLook()
        return true
    end
    if textMode then
        -- the text version is only the castle: no menu, no map, no island
        if k == "q" or k == "escape" then return false end
        if k == "m" then return true end
        if (k == "space" or k == "return") and game.atTheEnd() then return true end
        local nextLevel = levels[game.index + 1]
        if k == "]" and not (nextLevel and #nextLevel.crates > 0) then return true end
    end
    love.keypressed(k, k, false)
    return true
end

----------------------------------------------------------------------------------------------------
-- the terminal
----------------------------------------------------------------------------------------------------

local TIOCGWINSZ = jit.os == "OSX" and 0x40087468 or 0x5413

-- what the terminal said about itself when asked, see probeTerminal
local terminal = {}

-- columns, rows, and the size of a character cell in pixels, in whole pixels (nil when the terminal doesn't say)
-- the cell size the terminal gave when asked is the exact one; the window size from the kernel can include padding
local function terminalSize()
    local ws = ffi.new("struct winsize")
    if ffi.C.ioctl(1, TIOCGWINSZ, ws) ~= 0 or ws.ws_col == 0 then return 80, 24 end
    local cols, rows = ws.ws_col, ws.ws_row
    if terminal.cellW then return cols, rows, terminal.cellW, terminal.cellH end
    if ws.ws_xpixel == 0 then return cols, rows end
    return cols, rows, math.floor(ws.ws_xpixel/cols), math.floor(ws.ws_ypixel/rows)
end

-- the bytes waiting on stdin, waiting at most timeout seconds for them (forever when timeout is nil); nil at the end
local inputBuffer = ffi.new("uint8_t[4096]")
local function readInput(timeout)
    local fds = ffi.new("struct pollfd[1]")
    fds[0].fd, fds[0].events = 0, 1
    local ready = ffi.C.poll(fds, 1, timeout and math.max(0, math.floor(timeout*1000)) or -1)
    if ready <= 0 then return "" end
    local n = ffi.C.read(0, inputBuffer, 4096)
    if n <= 0 then return nil end
    return ffi.string(inputBuffer, n)
end

-- asks the terminal whether it shows images (kitty graphics protocol), how big a cell is in pixels, and whether it
-- says when keys are let go (kitty keyboard protocol); every terminal answers the last question, \27[c, so once that
-- answer is in, every answer that's coming has come; this works over ssh too, where environment variables like
-- TERM_PROGRAM don't get through
-- returns what was typed in the meantime, so no key is lost
local function probeTerminal()
    io.write("\27_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\27\\\27[16t\27[?u\27[c")
    io.flush()
    local answer, deadline = "", now() + 1.5
    while not answer:find("\27%[%?[%d;]*c") and now() < deadline do
        answer = answer .. (readInput(deadline - now()) or "")
    end
    terminal.images = answer:find("\27_Gi=31;OK") ~= nil
    terminal.keys = answer:find("\27%[%?%d*u") ~= nil
    local h, w = answer:match("\27%[6;(%d+);(%d+)t")
    if h and tonumber(w) > 0 then terminal.cellW, terminal.cellH = tonumber(w), tonumber(h) end
    -- whatever is left is keys that were pressed
    answer = answer:gsub("\27_G[^\27]*\27\\", ""):gsub("\27%[6;%d+;%d+t", ""):gsub("\27%[%?%d*u", "")
    return (answer:gsub("\27%[%?[%d;]*c", ""))
end

local base64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local base64lookup = {}
for i = 0, 63 do base64lookup[i] = base64chars:sub(i + 1, i + 1) end

local function base64(s)
    local out, n = {}, #s
    for i = 1, n, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a*65536 + (b or 0)*256 + (c or 0)
        out[#out+1] = base64lookup[math.floor(v/262144) % 64] .. base64lookup[math.floor(v/4096) % 64]
            .. (b and base64lookup[math.floor(v/64) % 64] or "=") .. (c and base64lookup[v % 64] or "=")
    end
    return table.concat(out)
end

----------------------------------------------------------------------------------------------------
-- pictures: the game draws a frame (love.draw), it goes to the terminal as an image
----------------------------------------------------------------------------------------------------

-- the window the game gets: the terminal in pixels, divided by how many terminal pixels make one pixel of the game,
-- so on a high resolution screen the game looks like it does in a window there
-- returns the game's width and height, that factor, and the terminal's size in cells and in pixels per cell
local function windowSize()
    local cols, rows, cellW, cellH = terminalSize()
    cellW, cellH = cellW or 10, cellH or 20
    local pw, ph = cols*cellW, rows*cellH
    local factor = tonumber(options["pixel-scale"]) or math.max(1, math.floor(cellH/18 + 0.5))
    while factor > 1 and (pw/factor < 640 or ph/factor < 360) do factor = factor - 1 end
    return math.ceil(pw/factor), math.ceil(ph/factor), factor, cols, rows, cellW, cellH
end

local function drawFrame(w, h)
    local screen = softlove.beginFrame(w, h)
    love.draw()
    return screen
end

-- the screen is sent as a grid of images, each this many cells, and after the first frame only the ones that changed
-- are sent again: walking around changes a few of them, so little has to go to the terminal, which matters over ssh
local blockCols, blockRows = 8, 4

local shown -- what's on screen: the pixels of the last frame, and the size of everything it was drawn for

-- sends the pixels of one block: x, y, w, h in pixels of rgb (stride bytes a row), at a cell of the terminal
local function sendBlock(out, rgb, stride, x, y, w, h, id, col, row, cells, lines)
    local block = ffi.new("uint8_t[?]", w*h*3)
    for line = 0, h - 1 do ffi.copy(block + line*w*3, rgb + (y + line)*stride + x*3, w*3) end
    local data = base64(softlove.compress(block, w*h*3, 6))
    out[#out+1] = ("\27[%d;%dH"):format(row, col)
    for i = 1, #data, 4096 do
        local piece = data:sub(i, i + 4095)
        local more = i + 4096 <= #data and 1 or 0
        if i == 1 then
            -- c and r: the image covers exactly these cells, whatever the terminal thinks of its size in pixels
            out[#out+1] = ("\27_Ga=T,f=24,o=z,s=%d,v=%d,i=%d,p=1,c=%d,r=%d,C=1,q=2,m=%d;%s\27\\"):format(
                w, h, id, cells, lines, more, piece)
        else
            out[#out+1] = ("\27_Gm=%d;%s\27\\"):format(more, piece)
        end
    end
end

local function presentKitty()
    local w, h, factor, cols, rows, cellW, cellH = windowSize()
    local rgb, rw = drawFrame(w, h):toRGB(factor)
    local stride = rw*3
    local key = table.concat({w, h, factor, cols, rows, cellW, cellH}, ",")
    local full = not shown or shown.key ~= key
    local out = {}
    if full then out[#out+1] = "\27_Ga=d,d=A,q=2\27\\\27[2J" end
    for by = 0, math.ceil(rows/blockRows) - 1 do
        for bx = 0, math.ceil(cols/blockCols) - 1 do
            local cells, lines = math.min(blockCols, cols - bx*blockCols), math.min(blockRows, rows - by*blockRows)
            local x, y, bw, bh = bx*blockCols*cellW, by*blockRows*cellH, cells*cellW, lines*cellH
            local changed = full
            if not changed then
                for line = y, y + bh - 1 do
                    if ffi.C.memcmp(rgb + line*stride + x*3, shown.rgb + line*stride + x*3, bw*3) ~= 0 then
                        changed = true
                        break
                    end
                end
            end
            if changed then
                sendBlock(out, rgb, stride, x, y, bw, bh, by*1000 + bx + 1, bx*blockCols + 1, by*blockRows + 1,
                    cells, lines)
            end
        end
    end
    shown = {key = key, rgb = rgb, factor = factor}
    if #out > 0 then
        io.write(table.concat(out))
        io.flush()
    end
end

-- the mouse, from terminal pixels to the game's window
local function sendMouse(event)
    local factor = shown and shown.factor or 1
    local x, y = math.floor((event.x - 1)/factor), math.floor((event.y - 1)/factor)
    host.mouseX, host.mouseY = x, y
    local b = event.button
    local buttons = {[0] = 1, [1] = 3, [2] = 2}
    if b >= 64 then
        if not event.release and love.wheelmoved then love.wheelmoved(0, b % 2 == 0 and 1 or -1) end
    elseif b >= 32 then
        if love.mousemoved then love.mousemoved(x, y, 0, 0) end
    elseif not event.release then
        if buttons[b % 4] and love.mousepressed then love.mousepressed(x, y, buttons[b % 4]) end
    elseif love.mousereleased then
        love.mousereleased(x, y, buttons[b % 4] or 1)
    end
end

----------------------------------------------------------------------------------------------------
-- coloured text, for every other terminal: the castle, two characters a tile, in 256 colours
----------------------------------------------------------------------------------------------------

-- fg and bg for the room you're in, dimFg and dimBg for the rooms around it; plain is the text without colour
local tileLooks = {
    wall = {text = "██", fg = 223, dimFg = 101},
    floor = {text = "  ", bg = 180, dimBg = 95},
    goal = {text = "()", fg = 124, bg = 180, dimFg = 88, dimBg = 95},
    crate = {text = "[]", fg = 223, bg = 130, dimFg = 180, dimBg = 58},
    placed = {text = "[]", fg = 94, bg = 178, dimFg = 58, dimBg = 136, plain = "{}"},
    player = {text = "@@", fg = 18, bg = 180, bold = true},
    playerOnGoal = {text = "@@", fg = 18, bg = 174, bold = true},
    shut = {text = "##", fg = 203, bg = 52, dimFg = 131, dimBg = 52},
    open = {text = "  ", bg = 37, dimBg = 23, plain = ".."},
}

local colour = false

local function paint(look, dim)
    if not colour then return look.plain or look.text end
    local fg = dim and look.dimFg or look.fg
    local bg = dim and look.dimBg or look.bg
    local codes = {}
    if look.bold and not dim then codes[#codes+1] = "1" end
    if fg then codes[#codes+1] = "38;5;" .. fg end
    if bg then codes[#codes+1] = "48;5;" .. bg end
    return "\27[" .. table.concat(codes, ";") .. "m" .. look.text .. "\27[0m"
end

-- whether a tile is part of the room you're in: its floor and doors, and the walls touching them
local function lit(x, z)
    local index = game.room.index
    for dx = -1, 1 do
        for dz = -1, 1 do
            local tile = game.world:tile(x + dx, z + dz)
            if tile and tile.room == index and (tile.material.inside or (dx == 0 and dz == 0)) then return true end
        end
    end
    return false
end

local function tileLook(x, z)
    local tile = game.world:tile(x, z)
    if not tile then return nil end
    local goal = tile.material.goal
    if game.state.x == x and game.state.z == z then return goal and tileLooks.playerOnGoal or tileLooks.player end
    if sokoban.crateAt(game.state, x, z) then return goal and tileLooks.placed or tileLooks.crate end
    if goal then return tileLooks.goal end
    if tile.material.door == "exit" then
        return sokoban.doorOpen(game.state, game.world, x, z) and tileLooks.open or tileLooks.shut
    end
    if tile.material.walkable then return tileLooks.floor end
    return tileLooks.wall
end

local function goalsCovered(room)
    for _,goal in ipairs(room.goals) do
        if not sokoban.crateAt(game.state, goal[1], goal[2]) then return false end
    end
    return true
end

local function textFrame()
    local room = game.room
    if not room then return game.units and "On the island\n" or "Loading...\n" end
    local lines = {}
    local box = room.box
    for z = box.maxZ + 2, box.minZ - 2, -1 do
        local row = {}
        for x = box.minX - 2, box.maxX + 2 do
            local look = tileLook(x, z)
            row[#row+1] = look and paint(look, not lit(x, z)) or "  "
        end
        lines[#lines+1] = table.concat(row)
    end
    lines[#lines+1] = ""
    local best = progress.best(room.level.name)
    lines[#lines+1] = ("Room %d/%d  %s"):format(room.index, #game.world.rooms, room.level.name)
    lines[#lines+1] = ("Moves %d   Pushes %d%s"):format(room.moves, room.pushes,
        best and ("   Best %d"):format(best.moves) or "")
    if game.atTheEnd() then
        lines[#lines+1] = "Every puzzle solved! The island is in the picture version, and in LÖVE"
    elseif game.toast and game.clock - game.toast.at < 3 then
        lines[#lines+1] = game.toast.text
    elseif not room.recorded and not room.solved and goalsCovered(room) then
        lines[#lines+1] = "The door is open: walk through it"
    else
        lines[#lines+1] = ""
    end
    lines[#lines+1] = ""
    lines[#lines+1] = "arrows/WASD move   z undo   r restart   [ ] previous/next room   q quit"
    return table.concat(lines, "\n") .. "\n"
end

local lastText
local function presentText()
    local text = textFrame()
    if text == lastText then return end
    lastText = text
    -- drawn over the last frame rather than after clearing the screen, so it doesn't flicker
    io.write("\27[H" .. text:gsub("\n", "\27[K\n") .. "\27[J")
    io.flush()
end

----------------------------------------------------------------------------------------------------
-- running
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
-- the art in character cells (termcells.lua): the game draws the world (game.draw) at one pixel of the art per
-- dot, and the bars, the messages, the pause menu and the map go on top as text
----------------------------------------------------------------------------------------------------

local bar, barText, dimText, gold = 0x1c1824, 0xe8e6ee, 0x9a96a6, 0xf2c14e
local lastCells

-- the map of the castle, one dot per tile (or more, when there's room), with the room that's picked blinking
local function drawPickerPixels(canvas)
    local lg = love.graphics
    local world, image = game.world, game.map.image
    local s = math.max(1, math.floor(math.min(canvas.width/world.width, canvas.height/world.depth)))
    local room = world.rooms[picker.index]
    local box = room and room.box
        or {minX = world.island[1] - 2, maxX = world.island[1] + 2, minZ = world.island[2] - 2, maxZ = world.island[2] + 2}
    -- centred, or when the castle doesn't fit, as near the middle as it goes with the picked room in view
    local function place(size, mapSize, middle)
        if mapSize <= size then return math.floor((size - mapSize)/2) end
        return math.max(size - mapSize, math.min(0, math.floor(size/2 - middle)))
    end
    local ox = place(canvas.width, world.width*s, ((box.minX + box.maxX + 1)/2 - world.minX)*s)
    local oy = place(canvas.height, world.depth*s, (world.maxZ - (box.minZ + box.maxZ - 1)/2)*s)
    lg.setColor(1, 1, 1)
    lg.draw(image, ox, oy, 0, s, s)
    local x0, y0 = ox + (box.minX - world.minX)*s - 1, oy + (world.maxZ - box.maxZ)*s - 1
    local x1, y1 = ox + (box.maxX - world.minX + 1)*s, oy + (world.maxZ - box.minZ + 1)*s
    local blink = 0.55 + 0.45*math.sin(love.timer.getTime()*6)
    lg.setColor(1, 0.85, 0.3, blink)
    lg.rectangle("fill", x0, y0, x1 - x0 + 1, 1)
    lg.rectangle("fill", x0, y1, x1 - x0 + 1, 1)
    lg.rectangle("fill", x0, y0, 1, y1 - y0 + 1)
    lg.rectangle("fill", x1, y0, 1, y1 - y0 + 1)
    lg.setColor(1, 1, 1)
end

local function menuLabel(item, i)
    if item.confirm and menu.confirming == i then return item.confirm end
    return type(item.label) == "function" and item.label() or item.label
end

-- the bar at the top, the two lines at the bottom, and the menu or the map's captions on top of the pixels
local function overlay(screen)
    local cols, rows = screen.cols, screen.rows
    local function fillRow(row)
        for c = 1, cols do termcells.set(screen, c, row, " ", barText, bar) end
    end
    fillRow(1)
    fillRow(rows - 1)
    fillRow(rows)
    local help = picker.isOpen and "[arrows] choose a room  [Enter] go there  [Esc] back"
        or game.units and "[Esc] menu  [WASD] cursor  [Enter] select/move  [Z] cancel"
        or "[Esc] menu  [M] map  [WASD] move  [Z] undo  [R] restart  [wheel] zoom"
    termcells.text(screen, 2, 1, help, barText, bar)
    local switch = "[Tab] look: " .. look
    termcells.text(screen, cols - #switch, 1, switch, gold, bar)

    if not game.player then
        termcells.centred(screen, 1, math.floor(rows/2), cols, "Loading...", barText, -1)
        return
    end
    local room = game.room
    if picker.isOpen then
        local solved = 0
        for _,r in ipairs(game.world.rooms) do if r.solved then solved = solved + 1 end end
        local i = picker.index
        local name = levels[i] and levels[i].name or ""
        termcells.text(screen, 2, rows - 1, ("Map: %d of %d rooms solved"):format(solved, #game.world.rooms),
            barText, bar)
        termcells.text(screen, 2, rows, ("%d. %s"):format(i, name), gold, bar)
    elseif room then
        local best = progress.best(room.level.name)
        termcells.text(screen, 2, rows - 1, ("Room %d/%d  %s"):format(room.index, #game.world.rooms, room.level.name),
            barText, bar)
        local stats = ("Moves %d   Pushes %d%s"):format(room.moves, room.pushes,
            best and ("   Best %d"):format(best.moves) or "")
        termcells.text(screen, cols - #stats, rows - 1, stats, dimText, bar)
        local message, colour = nil, barText
        if game.atTheEnd() then
            message, colour = "Every puzzle solved!  Space to visit the island", gold
        elseif game.toast and game.clock - game.toast.at < 3 then
            message, colour = game.toast.text .. (game.toast.hint and ". " .. game.toast.hint or ""), gold
        elseif not room.recorded and not room.solved and goalsCovered(room) then
            message, colour = "The door is open: walk through it", 0x73f2ff
        end
        if message then termcells.text(screen, 2, rows, message, colour, bar) end
    else
        termcells.text(screen, 2, rows - 1, "Pick a unit, then a blue square to move it", barText, bar)
        termcells.text(screen, 2, rows, "Cancel to deselect, previous level for the puzzles", dimText, bar)
    end

    if menu.isOpen then
        local w, h = 30, #menu.items + 4
        local col, row = math.floor((cols - w)/2) + 1, math.max(2, math.floor((rows - h)/2) + 1)
        termcells.panel(screen, col, row, w, h)
        termcells.centred(screen, col, row + 1, w, "Paused", barText, 0x08080f)
        for i,item in ipairs(menu.items) do
            local selected = i == menu.index
            local bg = selected and 0x5a4a1e or 0x08080f
            if selected then
                for c = col + 2, col + w - 3 do termcells.set(screen, c, row + 2 + i, " ", barText, bg) end
            end
            termcells.centred(screen, col, row + 2 + i, w, menuLabel(item, i), barText, bg)
        end
    end
end

local function presentCells(style)
    local cols, rows = terminalSize()
    local viewRows = math.max(1, rows - 3)
    local px = termcells.pixels[style]
    local canvas = softlove.beginFrame(cols*px[1], viewRows*px[2])
    if game.player then
        if picker.isOpen then drawPickerPixels(canvas) else game.draw() end
    end
    local screen = termcells.newScreen(cols, rows)
    termcells.fromCanvas(screen, canvas, style, 2, viewRows)
    overlay(screen)
    local same = lastCells and lastCells.cols == cols and lastCells.rows == rows
    local out = termcells.diff(screen, same and lastCells or nil)
    lastCells = screen
    if out ~= "" then
        io.write(out)
        io.flush()
    end
    return screen
end

----------------------------------------------------------------------------------------------------
-- running
----------------------------------------------------------------------------------------------------

local frameTime = 1/30
local canShowPictures = false

-- Tab: the next look this terminal can show, from a clean screen
function switchLook()
    local index = 1
    for i,l in ipairs(looks) do if l == look then index = i end end
    repeat
        index = index % #looks + 1
    until looks[index] ~= "pictures" or canShowPictures
    if look == "pictures" then io.write("\27_Ga=d,d=A,q=2\27\\") end
    look = looks[index]
    shown, lastCells, lastText = nil, nil, nil
    io.write("\27[0m\27[2J")
    io.flush()
end

local function present()
    if look == "pictures" then presentKitty()
    elseif look == "text" then presentText()
    else presentCells(look) end
end

-- scripted: every character from the pipe is a key, then the last frame is printed or saved
-- with --look blocks, octants or small it prints that frame instead, on a terminal of --size COLSxROWS (120x40)
local function runScripted()
    -- the game's time runs much faster than the real time here: keys are tapped, never held
    keyHeld = 0
    look = options.look or "text"
    local cellLook = termcells.pixels[look] ~= nil
    local w, h = (options.size or (cellLook and "120x40" or "1280x720")):match("^(%d+)x(%d+)$")
    w, h = tonumber(w), tonumber(h)
    if cellLook then
        terminalSize = function() return w, h end
        local px = termcells.pixels[look]
        softlove.beginFrame(w*px[1], (h - 3)*px[2])
    else
        softlove.beginFrame(w, h)
    end
    love.load()
    for _ = 1, 10 do love.update(frameTime) end
    for _,event in ipairs(parseInput(io.read("*a") or "")) do
        if event.key then
            if look == "text" and options.png then look = "pictures" end
            if not sendKey(event) or host.quitting then break end
            -- long enough for a step, and for a door to open
            for _ = 1, 15 do love.update(frameTime) end
        end
    end
    if cellLook then
        presentCells(look)
        io.write("\n")
        return
    end
    if options.png then
        local rgb = drawFrame(w, h):toRGB(1)
        softlove.writePNG(options.png, w, h, rgb)
    end
    colour = ffi.C.isatty(1) == 1
    io.write(textFrame())
end

local function runInteractive()
    colour = true
    local saved = io.popen("stty -g"):read("*l")
    -- no line buffering, no echo, and Ctrl-C arrives as a key, so the terminal is always put back
    os.execute("stty -icanon -echo -isig min 1")
    local typed = probeTerminal()
    canShowPictures = options.kitty or terminal.images
    look = options.look or (options.text and "text") or (canShowPictures and "pictures" or "blocks")
    local exactKeys = terminal.keys
    -- the alternate screen, so the terminal looks like it did before once the game quits; no cursor
    io.write("\27[?1049h\27[?25l\27[2J")
    -- every key as an escape code that also says when it's let go, and the mouse (in pixels, for the pictures)
    if exactKeys then io.write("\27[>11u") end
    if canShowPictures then io.write("\27[?1000h\27[?1003h\27[?1006h\27[?1016h") end
    io.flush()

    local ok, err = xpcall(function()
        local w, h = windowSize()
        softlove.beginFrame(w, h)
        love.load()
        local last, busyUntil = now(), now() + 3
        local demo, demoAt = options.demo and parseInput(options.demo), now() + 2
        while not host.quitting do
            -- a frame every 30th of a second for a few seconds after a key, slower when nothing is happening
            local bytes = readInput(now() < busyUntil and frameTime or 0.1)
            if bytes == nil then break end
            bytes, typed = typed .. bytes, ""

            if demo and now() >= demoAt then
                -- the next key of the demo, and once they're all typed, a moment to look before quitting
                if #demo == 0 then break end
                if not sendKey(table.remove(demo, 1)) then break end
                demoAt = now() + (#demo == 0 and 2.5 or 0.2)
                busyUntil = now() + 3
            end
            local quit = false
            for _,event in ipairs(parseInput(bytes)) do
                if event.kind == "protocol" then
                    -- an answer about the keyboard protocol, nothing to do
                elseif event.kind == "mouse" then
                    -- clicks only line up with the pictures; the wheel zooms in every look
                    if look == "pictures" or event.button >= 64 then sendMouse(event) end
                else
                    event.exact = exactKeys
                    if not sendKey(event) then quit = true end
                end
            end
            if quit then break end
            if #bytes > 0 then busyUntil = now() + 3 end
            local t = now()
            love.update(math.min(t - last, 0.1))
            last = t
            present()
        end
    end, debug.traceback)

    if exactKeys then io.write("\27[<u") end
    if canShowPictures then io.write("\27[?1016l\27[?1006l\27[?1003l\27[?1000l\27_Ga=d,d=A,q=2\27\\") end
    io.write("\27[0m\27[?25h\27[?1049l")
    io.flush()
    os.execute("stty " .. saved)
    if not ok then
        io.stderr:write(err, "\n")
        os.exit(1)
    end
end

if ffi.C.isatty(0) == 1 then runInteractive() else runScripted() end
