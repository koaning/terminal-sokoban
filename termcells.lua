-- the game drawn with characters instead of pictures, for term.lua: every character cell shows a few pixels of the
-- art, in 24-bit colour, so it's all text and costs little to send (only the cells that changed go to the terminal)
--
-- three ways to fit pixels into a cell:
--   blocks   ▀ with a colour for the top and one for the bottom: 1x2 pixels a cell, a tile is 8x4 cells
--   octants  the 2x4 dots of Unicode 16's octant characters, in two colours: 2x4 pixels a cell, a tile is 4x2 cells,
--            the dots of a cell that have a third colour get the nearer of the two (Ghostty and kitty draw these
--            characters themselves; in other terminals it depends on the font)
--   small    blocks again, but every pixel is the average of 2x2 pixels of the art: a tile is 4x2 cells too
--
-- a screen is a grid of cells, {char, fg, bg} with colours as 0xRRGGBB; text and panels go on top of the pixels

local ffi = require "ffi"

local cells = {}

local floor, min, max = math.floor, math.min, math.max

-- how many pixels of the art go into a cell across and down
cells.pixels = {blocks = {1, 2}, octants = {2, 4}, small = {2, 4}}

----------------------------------------------------------------------------------------------------
-- the octant characters: one for each pattern of the 8 dots, numbered 1 2 / 3 4 / 5 6 / 7 8 from the top left
-- Unicode has 230 of them in a row from U+1CD00, in the order of the patterns (dot 1 the lowest bit); the other 26
-- patterns are older characters, like the half blocks and the quadrants
----------------------------------------------------------------------------------------------------

local function utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + floor(cp/64), 0x80 + cp % 64) end
    if cp < 0x10000 then return string.char(0xE0 + floor(cp/4096), 0x80 + floor(cp/64) % 64, 0x80 + cp % 64) end
    return string.char(0xF0 + floor(cp/262144), 0x80 + floor(cp/4096) % 64, 0x80 + floor(cp/64) % 64, 0x80 + cp % 64)
end

local octants = {}
do
    local function dots(list)
        local mask = 0
        for _,d in ipairs(list) do mask = mask + 2^(d - 1) end
        return mask
    end
    local older = {
        [" "] = {}, ["█"] = {1, 2, 3, 4, 5, 6, 7, 8}, ["▀"] = {1, 2, 3, 4}, ["▄"] = {5, 6, 7, 8},
        ["▌"] = {1, 3, 5, 7}, ["▐"] = {2, 4, 6, 8}, ["▘"] = {1, 3}, ["▝"] = {2, 4}, ["▖"] = {5, 7}, ["▗"] = {6, 8},
        ["▚"] = {1, 3, 6, 8}, ["▞"] = {2, 4, 5, 7}, ["▙"] = {1, 3, 5, 6, 7, 8}, ["▛"] = {1, 2, 3, 4, 5, 7},
        ["▜"] = {1, 2, 3, 4, 6, 8}, ["▟"] = {2, 4, 5, 6, 7, 8}, ["▂"] = {7, 8}, ["▆"] = {3, 4, 5, 6, 7, 8},
        [utf8(0x1FB82)] = {1, 2}, [utf8(0x1FB85)] = {1, 2, 3, 4, 5, 6},
        [utf8(0x1CEA8)] = {1}, [utf8(0x1CEAB)] = {2}, [utf8(0x1CEA3)] = {7}, [utf8(0x1CEA0)] = {8},
        [utf8(0x1FBE6)] = {3, 5}, [utf8(0x1FBE7)] = {4, 6},
    }
    for ch,list in pairs(older) do octants[dots(list)] = ch end
    local next = 0x1CD00
    for mask = 0, 255 do
        if not octants[mask] then
            octants[mask] = utf8(next)
            next = next + 1
        end
    end
    assert(next == 0x1CD00 + 230, "the octant table is off")
end

----------------------------------------------------------------------------------------------------
-- screens
----------------------------------------------------------------------------------------------------

function cells.newScreen(cols, rows)
    local screen = {cols = cols, rows = rows, ch = {}, fg = {}, bg = {}}
    for i = 1, cols*rows do screen.ch[i], screen.fg[i], screen.bg[i] = " ", -1, -1 end
    return screen
end

local function set(screen, col, row, ch, fg, bg)
    if col < 1 or row < 1 or col > screen.cols or row > screen.rows then return end
    local i = (row - 1)*screen.cols + col
    screen.ch[i], screen.fg[i], screen.bg[i] = ch, fg, bg
end
cells.set = set

-- the pixels of a canvas (softlove) as bytes, 0xRRGGBB
local function pixelAt(p, w, x, y)
    local i = (y*w + x)*3
    return floor(min(1, max(0, p[i]))*255 + 0.5)*65536 + floor(min(1, max(0, p[i + 1]))*255 + 0.5)*256
        + floor(min(1, max(0, p[i + 2]))*255 + 0.5)
end

local function channels(c) return floor(c/65536), floor(c/256) % 256, c % 256 end

local function distance(a, b)
    local r1, g1, b1 = channels(a)
    local r2, g2, b2 = channels(b)
    return (r1 - r2)^2 + (g1 - g2)^2 + (b1 - b2)^2
end

local function average(list)
    local r, g, b = 0, 0, 0
    for _,c in ipairs(list) do
        local cr, cg, cb = channels(c)
        r, g, b = r + cr, g + cg, b + cb
    end
    local n = #list
    return floor(r/n + 0.5)*65536 + floor(g/n + 0.5)*256 + floor(b/n + 0.5)
end

-- puts the pixels of canvas into the screen's cells from row top, for rows rows
function cells.fromCanvas(screen, canvas, style, top, rows)
    local p, w = canvas.pixels, canvas.width
    for row = 0, rows - 1 do
        for col = 0, screen.cols - 1 do
            if style == "blocks" then
                local a, b = pixelAt(p, w, col, row*2), pixelAt(p, w, col, row*2 + 1)
                if a == b then set(screen, col + 1, top + row, " ", -1, a)
                else set(screen, col + 1, top + row, "▀", a, b) end
            elseif style == "small" then
                local x, y = col*2, row*4
                local a = average{pixelAt(p, w, x, y), pixelAt(p, w, x + 1, y), pixelAt(p, w, x, y + 1),
                    pixelAt(p, w, x + 1, y + 1)}
                local b = average{pixelAt(p, w, x, y + 2), pixelAt(p, w, x + 1, y + 2), pixelAt(p, w, x, y + 3),
                    pixelAt(p, w, x + 1, y + 3)}
                if a == b then set(screen, col + 1, top + row, " ", -1, a)
                else set(screen, col + 1, top + row, "▀", a, b) end
            else
                -- octants: the two colours furthest apart, each dot takes the nearer one, then each colour becomes
                -- the average of its dots
                local x, y = col*2, row*4
                local dots = {}
                for k = 0, 7 do dots[k + 1] = pixelAt(p, w, x + k % 2, y + floor(k/2)) end
                local a, b, far = dots[1], dots[1], 0
                for i = 1, 8 do
                    for j = i + 1, 8 do
                        local d = distance(dots[i], dots[j])
                        if d > far then a, b, far = dots[i], dots[j], d end
                    end
                end
                if far == 0 then
                    set(screen, col + 1, top + row, " ", -1, a)
                else
                    local mask, ofA, ofB = 0, {}, {}
                    for k = 1, 8 do
                        if distance(dots[k], a) <= distance(dots[k], b) then
                            mask = mask + 2^(k - 1)
                            ofA[#ofA+1] = dots[k]
                        else
                            ofB[#ofB+1] = dots[k]
                        end
                    end
                    set(screen, col + 1, top + row, octants[mask], average(ofA), average(ofB))
                end
            end
        end
    end
end

-- text, from col, row, cut off at the edge
function cells.text(screen, col, row, text, fg, bg)
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        set(screen, col, row, ch, fg, bg)
        col = col + 1
    end
end

-- a panel like the game's: nearly black, with a rounded light border
function cells.panel(screen, col, row, w, h, bg)
    bg = bg or 0x08080f
    local edge = 0xf4f4ea
    for r = row, row + h - 1 do
        for c = col, col + w - 1 do
            local ch = " "
            local top, bottom, left, right = r == row, r == row + h - 1, c == col, c == col + w - 1
            if top and left then ch = "╭" elseif top and right then ch = "╮"
            elseif bottom and left then ch = "╰" elseif bottom and right then ch = "╯"
            elseif top or bottom then ch = "─" elseif left or right then ch = "│" end
            set(screen, c, r, ch, edge, bg)
        end
    end
end

-- the text centred in a line from col, w wide
function cells.centred(screen, col, row, w, text, fg, bg)
    local length = 0
    for _ in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do length = length + 1 end
    cells.text(screen, col + floor((w - length)/2), row, text, fg, bg)
end

----------------------------------------------------------------------------------------------------
-- to the terminal: only the cells that changed since the last screen, in one go
----------------------------------------------------------------------------------------------------

local function sgr(fg, bg)
    local parts = {}
    if fg < 0 then parts[#parts+1] = "39" else
        parts[#parts+1] = ("38;2;%d;%d;%d"):format(channels(fg)) end
    if bg < 0 then parts[#parts+1] = "49" else
        parts[#parts+1] = ("48;2;%d;%d;%d"):format(channels(bg)) end
    return "\27[" .. table.concat(parts, ";") .. "m"
end

-- the escape codes that turn the last screen into this one (all of it when there's no last one)
function cells.diff(screen, last)
    local out = {"\27[?2026h"}
    local curFg, curBg, cursor = nil, nil, nil
    local cols = screen.cols
    for row = 1, screen.rows do
        for col = 1, cols do
            local i = (row - 1)*cols + col
            local ch, fg, bg = screen.ch[i], screen.fg[i], screen.bg[i]
            -- a space doesn't show its foreground colour, so it doesn't matter what it is
            if ch == " " then fg = curFg or -1 end
            if not last or ch ~= last.ch[i] or bg ~= last.bg[i] or (ch ~= " " and fg ~= last.fg[i]) then
                if cursor ~= i then out[#out+1] = ("\27[%d;%dH"):format(row, col) end
                if fg ~= curFg or bg ~= curBg then
                    out[#out+1] = sgr(fg, bg)
                    curFg, curBg = fg, bg
                end
                out[#out+1] = ch
                cursor = i + 1
                -- the cursor doesn't wrap onto the next row by itself, reliably
                if col == cols then cursor = nil end
            end
        end
    end
    out[#out+1] = "\27[0m\27[?2026l"
    if #out == 2 then return "" end
    return table.concat(out)
end

return cells
