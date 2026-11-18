io.stdout:setvbuf("no")

-- LÖVE's error screen only closes with Esc, which a handheld doesn't have: any gamepad button closes it too
-- this is set before anything else is loaded, so it also catches errors while loading, like a shader that doesn't compile
local defaultErrorHandler = love.errorhandler or love.errhand -- LÖVE 11 calls its own one errhand
function love.errorhandler(message)
    local errorLoop = defaultErrorHandler(message)
    local buttons = {"a", "b", "x", "y", "start", "back", "guide"}
    local openedAt = love.timer.getTime() -- wait a moment, so a button that is already held doesn't close it straight away
    return function()
        local result = errorLoop()
        if result then return result end
        if love.timer.getTime() - openedAt < 0.5 then return end
        for _,joystick in ipairs(love.joystick and love.joystick.getJoysticks() or {}) do
            if joystick:isGamepad() and joystick:isGamepadDown(unpack(buttons)) then return 1 end
        end
    end
end

-- `love . --screenshot <dir>` plays a little tour, see the end of this file
local isScreenshotTour = false
for _,v in ipairs(arg) do
    if v == "--screenshot" then isScreenshotTour = true end
end

local lg = love.graphics
lg.setDefaultFilter("nearest")

local game = require "game"
local menu = require "menu"
local picker = require "picker"
local progress = require "progress"
local camera = require "camera"
local draw2d = require "draw2d"

-- the camera (see camera.lua) frames the whole room you're in, top down with north up, as big as it fits at a whole
-- number of screen pixels per pixel of the art: small rooms are shown bigger

-- loading runs a step at a time between frames, so a loading screen can show what it's doing: on a handheld it takes a
-- few seconds; nil once everything is loaded
local loading

-- the map of the world, which is also fast travel: it loads the room that gets picked
local function openPicker()
    local p = game.isPuzzle() and game.player.position
    picker.open(game.index, game.load, {map = game.map, world = game.world, player = p and {p[1], p[3]},
        canTravel = game.canTravel})
end

-- the menu and the picker pause the game, and take the keys and the mouse while they are open
local function isPaused()
    return menu.isOpen or picker.isOpen
end

-- the items of the pause menu, most of them do the same as a key on the keyboard
local gameKey -- below love.keypressed
local function setUpMenu()
    local function key(k) return function() gameKey(k) end end
    menu.setItems{
        {label = "Resume", action = function() end},
        {label = "Restart level", action = key("r")},
        {label = "Map", action = openPicker},
        {label = "Next level", action = key("]")},
        {label = "Previous level", action = key("[")},
        {label = "New game", confirm = "Press again to erase all", action = game.newGame},
        {label = "Quit game", action = function() love.event.push("quit") end},
    }
end

function love.load()
    -- goes into the log, handy when the game runs on other hardware like a handheld
    local major, minor = love.getVersion()
    print(("LÖVE %d.%d on %s, renderer: %s %s (%s, %s)"):format(major, minor, love._os, lg.getRendererInfo()))
    print(("window %dx%d, %d gamepad(s)"):format(lg.getWidth(), lg.getHeight(), love.joystick.getJoystickCount()))
    lg.setBackgroundColor(draw2d.void)

    -- how long each step of loading takes, also for the log
    local started = love.timer.getTime()
    local steps = {
        {"Loading the tiles", game.initArt},
        {"Laying out the castle", game.initWorld},
        {"Opening the first room", function()
            setUpMenu()
            -- the screenshot tour doesn't save what it solves
            if isScreenshotTour then
                progress.enabled, progress.results, progress.visited = false, {}, {}
                game.forgetProgress()
            end
            -- every session starts at the start of the first room, the map takes you further
            game.load(1)
        end},
    }
    loading = {label = steps[1][1], done = 0, total = #steps}
    loading.co = coroutine.create(function()
        for i,step in ipairs(steps) do
            loading.label, loading.done = step[1], i - 1
            -- wait a frame, so the loading screen shows this step before it starts
            coroutine.yield()
            local t = love.timer.getTime()
            step[2]()
            print(("loaded %s in %.2fs"):format(step[1]:lower(), love.timer.getTime() - t))
        end
        print(("loading took %.2fs"):format(love.timer.getTime() - started))
    end)
end

-- carries on loading, and when it's done, the game starts
local function continueLoading()
    local ok, message = coroutine.resume(loading.co)
    if not ok then error(message, 0) end
    if coroutine.status(loading.co) == "dead" then loading = nil end
end

-- the loading screen: the name of the game, what it's doing, and how far along it is
local function drawLoading()
    local w, h = lg.getDimensions()
    lg.clear(0.03, 0.02, 0.07)
    local font = lg.getFont()
    local scale = math.max(1, math.floor(h/240))
    local bw, bh = math.floor(w*0.5), 6*scale
    local bx, by = math.floor((w - bw)/2), math.floor(h*0.55)
    lg.setColor(0.95, 0.75, 0.22)
    lg.printf("PS1 Sokoban", 0, by - 40*scale, w/(2*scale), "center", 0, 2*scale, 2*scale)
    lg.setColor(1, 1, 1, 0.8)
    lg.printf(loading.label .. "...", 0, by - 14*scale, w/scale, "center", 0, scale, scale)
    lg.setColor(1, 1, 1, 0.25)
    lg.rectangle("fill", bx, by, bw, bh)
    lg.setColor(0.45, 0.95, 1.0)
    -- the step that's running counts for half, so the bar keeps moving
    lg.rectangle("fill", bx, by, math.floor(bw*(loading.done + 0.5)/loading.total), bh)
    lg.setColor(1, 1, 1)
    lg.setFont(font)
end

-- the camera frames what game.view() says: the room you're in, and when you walk into the next room it glides over
-- to frame that one
local function updateCamera(dt)
    local w, h = lg.getDimensions()
    camera.update(dt, game.view(), w, h, game.cameraCut)
    game.cameraCut = false
end

-- every few seconds the frame rate goes into the log, with how long updating and drawing took on the CPU per frame
-- (when the frame takes much longer than those two, the GPU is what's slow)
local fpsLogEvery, fpsLogTimer, framesLogged = 10, 0, 0
local updateTime, drawTime, drawCalls = 0, 0, 0
local function logFrameRate(dt, updated)
    fpsLogTimer, framesLogged, updateTime = fpsLogTimer + dt, framesLogged + 1, updateTime + updated
    if fpsLogTimer >= fpsLogEvery then
        print(("%d fps, level %d: %.1f ms frame, %.1f ms update, %.1f ms draw, %d draw calls"):format(
            framesLogged/fpsLogTimer + 0.5, game.index, fpsLogTimer*1000/framesLogged, updateTime*1000/framesLogged,
            drawTime*1000/framesLogged, drawCalls))
        fpsLogTimer, framesLogged, updateTime, drawTime = 0, 0, 0, 0
    end
end
local function logDrawTime(t)
    drawTime, drawCalls = drawTime + t, lg.getStats().drawcalls
end

-- turns up/down and right/left into a grid direction: north is up on the screen
local function toGridDirection(up, right)
    if up ~= 0 then right = 0 end -- no diagonal steps on a grid
    return right, up
end

-- gamepads, like on handhelds: every button stands in for a key, so the game only has to handle keys
-- the d-pad and the left stick are the arrow keys
local stickDeadzone = 0.5
local padKeys = {
    dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
    a = "return",            -- confirm, next level once solved
    start = "escape",        -- the pause menu
    b = "backspace",         -- undo, or cancel on the island
    back = "r",              -- select: restart
    leftshoulder = "[", rightshoulder = "]", -- the previous and the next room
}

local function padDown(...)
    for _,joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:isGamepad() and joystick:isGamepadDown(...) then return true end
    end
    return false
end

-- the left stick as -1, 0 or 1 on both axes
local function stickDirection()
    local x, y = 0, 0
    for _,joystick in ipairs(love.joystick.getJoysticks()) do
        if joystick:isGamepad() then
            local sx, sy = joystick:getGamepadAxis("leftx"), joystick:getGamepadAxis("lefty")
            if math.abs(sx) > stickDeadzone then x = sx > 0 and 1 or -1 end
            if math.abs(sy) > stickDeadzone then y = sy > 0 and 1 or -1 end
        end
    end
    return x, y
end

-- the direction of the arrow keys / WASD / d-pad / stick that are held down
local function getInputDirection()
    local sx, sy = stickDirection()
    local up = love.keyboard.isDown("w", "up") or padDown("dpup") or sy < 0
    local down = love.keyboard.isDown("s", "down") or padDown("dpdown") or sy > 0
    local right = love.keyboard.isDown("d", "right") or padDown("dpright") or sx > 0
    local left = love.keyboard.isDown("a", "left") or padDown("dpleft") or sx < 0
    return toGridDirection((up and 1 or 0) - (down and 1 or 0), (right and 1 or 0) - (left and 1 or 0))
end

local moveKeys = {
    w = {1, 0}, up = {1, 0},
    s = {-1, 0}, down = {-1, 0},
    d = {0, 1}, right = {0, 1},
    a = {0, -1}, left = {0, -1},
}

function love.update(dt)
    if loading then
        continueLoading()
        -- the frame after loading is drawn straight away, so the camera has to be on the first room by then
        if not loading then updateCamera(0) end
        return
    end
    local started = love.timer.getTime()
    if not isPaused() then game.update(dt, getInputDirection()) end
    updateCamera(dt)
    logFrameRate(dt, love.timer.getTime() - started)
end

function love.mousepressed(x, y, button)
    if loading then return end
    if picker.isOpen then return picker.mousepressed(x, y, button) end
    if not menu.isOpen then game.mousepressed(x, y, button) end
end

function love.mousemoved(x, y)
    if loading then return end
    if picker.isOpen then return picker.mousemoved(x, y) end
    if not menu.isOpen then game.mousemoved(x, y) end
end

-- zoom with the mouse wheel, a whole step at a time so the pixel art stays sharp
function love.wheelmoved(x, y)
    if loading or y == 0 then return end
    camera.zoomBy(y > 0 and 1 or -1)
end

function love.gamepadpressed(joystick, button)
    if loading then return end
    -- start and select together quit, like on most handhelds
    local other = button == "start" and "back" or button == "back" and "start"
    if other and joystick and joystick:isGamepadDown(other) then
        love.event.push("quit")
        return
    end
    if button == "x" then camera.zoomBy(1) end
    if button == "y" then camera.zoomBy(-1) end
    if padKeys[button] then love.keypressed(padKeys[button]) end
end

-- the triggers are axes, not buttons: pressing either one in opens the map, or closes it again
-- pushing the stick works like tapping the d-pad, so a quick flick isn't lost
local axisKeys = {
    triggerleft = {nil, "m"}, triggerright = {nil, "m"},
    leftx = {"left", "right"}, lefty = {"up", "down"},
}
local axisState = {}
function love.gamepadaxis(joystick, axis, value)
    if loading then return end
    local keys = axisKeys[axis]
    if not keys then return end
    local side = math.abs(value) > stickDeadzone and (value > 0 and 2 or 1) or nil
    local id = joystick:getID() .. axis
    if side and side ~= axisState[id] and keys[side] then love.keypressed(keys[side]) end
    axisState[id] = side
end

function love.keypressed(k)
    if loading then return end
    if picker.isOpen then return picker.keypressed(k) end
    if menu.isOpen then return menu.keypressed(k) end
    if k == "escape" then return menu.open() end
    if k == "m" then return openPicker() end
    gameKey(k)
end

-- every key that does something in the game, the pause menu uses these too
function gameKey(k)
    if moveKeys[k] then game.queue(toGridDirection(moveKeys[k][1], moveKeys[k][2])) end
    game.keypressed(k)
end

-- the controls in the help bar, for a gamepad when one is plugged in
local function helpText()
    local pad = #love.joystick.getJoysticks() > 0
    if picker.isOpen then
        return pad and "[D-pad] choose a room  [A] go there  [B] or [L2/R2] back" or "[arrows] or [click] choose a room  [Enter] go there  [Esc] or [M] back"
    elseif pad and game.isPuzzle() then
        return "[Start] menu  [L2/R2] map  [D-pad] move  [B] undo  [Select] restart  [X/Y] zoom"
    elseif pad then
        return "[Start] menu  [L2/R2] map  [D-pad] cursor  [A] select/move  [B] cancel  [X/Y] zoom"
    elseif game.isPuzzle() then
        return "[Esc] menu  [M] map  [WASD] move  [Z] undo  [R] restart  [wheel] zoom"
    end
    return "[Esc] menu  [click] or [WASD]+[Enter] select/move  [Z] cancel  [R] restart  [wheel] zoom"
end

function love.draw()
    if loading then return drawLoading() end
    local started = love.timer.getTime()
    game.draw()
    lg.setColor(1, 1, 1)
    local helpHeight = game.drawHelp(helpText())
    game.drawHud(helpHeight)
    if menu.isOpen then menu.draw(game.panel) end
    if picker.isOpen then picker.draw(game.panel) end
    logDrawTime(love.timer.getTime() - started)
end

-- `love . --screenshot <dir>` plays a little, saves screenshots into <dir>, then quits
local screenshotDir
for i,v in ipairs(arg) do
    if v == "--screenshot" then screenshotDir = arg[i+1] end
end

if screenshotDir then
    local function save(name)
        lg.captureScreenshot(function(imageData)
            local file = io.open(screenshotDir .. "/" .. name, "wb")
            file:write(imageData:encode("png"):getString())
            file:close()
        end)
    end

    -- pretend a key is held down for a while
    local isDown = love.keyboard.isDown
    local held
    function love.keyboard.isDown(...)
        for _,k in ipairs{...} do
            if k == held then return true end
        end
        return isDown(...)
    end

    -- levels are looked up by name, so adding levels doesn't change what the tour visits
    local function levelIndex(name)
        for i,level in ipairs(require("levels")) do
            if level.name == name then return i end
        end
    end
    local dock = levelIndex("Loading dock")

    local tour = {
        [30] = function() save("1_level1.png") end,
        [31] = function() held = "d" end,                       -- push the crate onto the goal
        [46] = function() save("1b_pushing.png") end,           -- halfway through the first push
        [70] = function() held = nil end,
        [74] = function() save("2_door_opening.png") end,       -- the door sinks into the floor
        [90] = function()
            save("2_door_open.png")
            print(("tracks: %d scrape marks after solving level 1"):format(#game.tracks))
        end,
        -- walk back to the door, through it and into the next room
        [91] = function() love.keypressed("a") end,
        [100] = function() love.keypressed("a") end,
        [110] = function() held = "w" end,
        [140] = function() save("3_through_the_door.png") end,
        [330] = function()
            held = nil
            save("3_level2.png")
            print(("world: in room %d, %s, solved room 1: %s"):format(game.room.index, game.room.level.name,
                tostring(game.world.rooms[1].solved)))
        end,
        -- and back into the first room, through its door, which stays open now that it's solved
        [331] = function() held = "s" end,
        [560] = function()
            held = nil
            save("3b_walked_back.png")
            print(("world: walked back into room %d"):format(game.room.index))
        end,
        [571] = function() for _ = 1, dock - game.index do love.keypressed("]") end end,
        [600] = function() save("4_loading_dock.png") end,
        [601] = function() held = "w" end,                      -- walk up a bit
        [615] = function() held = nil end,
        [640] = function() save("5_walked.png") end,
        -- resize the window to a small handheld shape, a tall shape and a wide shape
        [641] = function() love.window.updateMode(640, 480) end,
        [680] = function() save("6_handheld_640x480.png") end,
        [681] = function() love.window.updateMode(800, 700) end,
        [710] = function() save("8_resized_tall.png") end,
        [711] = function() love.window.updateMode(1500, 500) end,
        [730] = function() save("9_resized_wide.png") end,
        -- zoomed in, the camera follows the player around the room
        [731] = function()
            love.window.updateMode(1280, 720)
            game.load(dock)
            love.wheelmoved(0, 2)
        end,
        [770] = function() save("close_zoomed.png") end,
        -- select a unit on the island by clicking where it is on screen, then click a square next to it
        [796] = function()
            camera.zoom = 0 -- back to the normal zoom
            game.load(#require("levels"))
        end,
        [830] = function()
            local unit = game.units.list[2]
            local x, y = camera.toScreen(unit.x, unit.z, lg.getDimensions())
            local tx, tz = camera.toTile(x, y, lg.getDimensions())
            print(("picking: unit on %d,%d, picked tile %s,%s"):format(unit.x, unit.z, tostring(tx), tostring(tz)))
            love.mousepressed(x, y, 1)
            print("picking: unit selected: " .. tostring(game.units.selected == unit))
        end,
        [860] = function() save("unit_selected.png") end,
        [861] = function()
            local unit = game.units.selected
            local target = unit and game.units:targets(unit)[1]
            if not target then print("picking: no unit selected or nowhere to go") return end
            local x, y = camera.toScreen(target[1], target[2], lg.getDimensions())
            love.mousepressed(x, y, 1)
            print(("picking: moved to %d,%d, wanted %d,%d"):format(unit.x, unit.z, target[1], target[2]))
        end,
        [890] = function() save("unit_moved.png") end,
        -- the same with gamepad buttons: cancel, select the unit under the cursor, move the cursor and confirm
        [891] = function()
            love.gamepadpressed(nil, "b")
            love.gamepadpressed(nil, "a")
            print("gamepad: unit selected: " .. tostring(game.units.selected ~= nil))
            love.gamepadpressed(nil, "dpup")
        end,
        [895] = function()
            local units = game.units
            print(("gamepad: cursor on %d,%d, a blue square: %s"):format(units.cursorX, units.cursorZ,
                tostring(units:isTarget(units.cursorX, units.cursorZ))))
            love.gamepadpressed(nil, "a")
        end,
        [925] = function()
            local unit = game.units.selected
            print(("gamepad: unit now on %s"):format(unit and unit.x .. "," .. unit.z or "nothing selected"))
            save("pad_moved.png")
            love.gamepadpressed(nil, "start")
            love.gamepadpressed(nil, "dpdown")
        end,
        [928] = function() save("menu.png") end,
        -- choose a level from the picker, opened from the pause menu
        [929] = function()
            love.keypressed("down")
            love.keypressed("return")
            print("picker: open: " .. tostring(picker.isOpen))
            love.keypressed("right")
            love.keypressed("down")
        end,
        [932] = function() save("picker.png") end,
        [933] = function()
            love.keypressed("return")
            print(("picker: loaded level %d, %s"):format(game.index, game.level.name))
        end,
        [960] = function() save("picked.png") end,
        -- two of the later puzzles: a small one, and the widest one
        [961] = function() game.load(levelIndex("Well")) end,
        [990] = function() save("level_well.png") end,
        [991] = function() game.load(levelIndex("Mask")) end,
        [1020] = function() save("level_mask.png") end,
        -- M opens the map; it only takes you to rooms you have been in, so an unvisited room can't be picked
        [1021] = function()
            love.keypressed("m")
            print("map key: open: " .. tostring(picker.isOpen))
        end,
        [1030] = function() save("map_key.png") end,
        [1031] = function()
            local alcoves = levelIndex("Alcoves")
            picker.index = alcoves
            love.keypressed("return")
            print(("fast travel: can go to Alcoves: %s, still open: %s, in %s"):format(
                tostring(game.canTravel(alcoves)), tostring(picker.isOpen), game.level.name))
            picker.index = levelIndex("Well")
            love.keypressed("return")
            print(("fast travel: went back to %s, map closed: %s"):format(game.level.name, tostring(not picker.isOpen)))
        end,
        [1060] = function() save("fast_travel.png") end,
        -- a dead end: the end of a side path, with no way out
        [1061] = function()
            game.load(levelIndex("Bookshelf"))
            print(("dead end: %s has %d ways out"):format(game.room.level.name, #game.room.exits))
        end,
        [1090] = function() save("dead_end.png") end,
        -- on a gamepad, either trigger opens the map, and closes it again
        [1091] = function()
            local pad = {getID = function() return 1 end}
            love.gamepadaxis(pad, "triggerright", 1)
            local opened = picker.isOpen
            love.gamepadaxis(pad, "triggerright", 0)
            love.gamepadaxis(pad, "triggerleft", 1)
            love.gamepadaxis(pad, "triggerleft", 0)
            print(("gamepad map: R2 opens it: %s, L2 closes it: %s"):format(tostring(opened), tostring(not picker.isOpen)))
        end,
        [1092] = function() love.event.push("quit") end,
    }
    local frame = 0
    local update = love.update
    function love.update(dt)
        -- the tour counts frames from when the game has loaded
        if loading then return update(dt) end
        update(dt)
        frame = frame + 1
        if tour[frame] then tour[frame]() end
    end
end
