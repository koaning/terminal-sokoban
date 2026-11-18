-- the sokoban game: the castle of puzzle rooms, moving the player and the crates, undo, and the HUD
-- all the crates of the castle are in one list, and undo goes back through every move, whichever room it was in;
-- R goes back to how things were when you walked into the room you're in
-- the free-roam island after the last puzzle is loaded on its own, with units to move instead of the player
-- the drawing of the castle and the island is in draw2d.lua: only the room you're in is lit, the rooms next to it are
-- dimmed, so you can see where the doors lead, and the rest of the castle isn't drawn

local grid = require "grid"
local sokoban = require "sokoban"
local levels = require "levels"
local Player = require "player"
local Units = require "units"
local progress = require "progress"
local world = require "world"
local map = require "map"
local draw2d = require "draw2d"
local camera = require "camera"
local tiles = require "tiles"

local lg = love.graphics

local game = {}

local fonts

-- how long a door takes to sink into the floor, or come back up
local gateTime = 0.35

----------------------------------------------------------------------------------------------------
-- the rooms, and the crates of the whole castle
----------------------------------------------------------------------------------------------------

local function crateKey(x, z) return x*65536 + z end

-- where every crate is, so finding the crate on a tile is quick
local function indexCrates()
    game.crateIndex = {}
    for _,crate in ipairs(game.state.crates) do game.crateIndex[crateKey(crate.x, crate.z)] = crate end
end

local function crateOn(x, z) return game.crateIndex[crateKey(x, z)] end

-- whether every goal of a room has a crate on it
local function goalsCovered(room)
    for _,goal in ipairs(room.goals) do
        if not crateOn(goal[1], goal[2]) then return false end
    end
    return true
end

-- a room's ways out are open once every goal has a crate, and stay open for good once the room has been solved
local function isOpen(room)
    return room.solved or goalsCovered(room)
end

-- the world asks the game whether a door can be walked through, see sokoban.doorOpen
-- ways in are always open, ways out once the room is solved (all of them: a fork lets you choose)
local function isDoorOpen(_, tile)
    if tile.material.door == "entry" then return true end
    return isOpen(game.world.rooms[tile.room])
end

-- the map needs painting again when a room is visited or solved, or a door opens or shuts
local function refreshMap()
    game.map:refresh(function(room) return room.visited end, isOpen)
    game.mapState = {}
    for i,room in ipairs(game.world.rooms) do game.mapState[i] = isOpen(room) end
end

local function mapChanged()
    for i,room in ipairs(game.world.rooms) do
        if isOpen(room) ~= game.mapState[i] then return true end
    end
    return false
end

local function newCrate(x, z, home)
    return {x = x, z = z, fromX = x, fromZ = z, progress = 1, home = home}
end

-- puts a room's crates back where the room starts, or on its goals, the way a solved room is left
local function resetCrates(room, solvedLayout)
    local positions = solvedLayout and world.solvedCrates(room) or room.startCrates
    for i,crate in ipairs(room.crates) do
        crate.x, crate.z = positions[i].x, positions[i].z
        crate.fromX, crate.fromZ, crate.progress = crate.x, crate.z, 1
    end
    -- a room left solved has nothing to record: walking out of it isn't a new solve, and certainly not a new best
    room.moves, room.pushes, room.recorded = 0, 0, solvedLayout and true or false
end

-- walking into a room: R goes back to how things were at this moment
local function enterRoom(room)
    game.room, game.index, game.level = room, room.index, room.level
    draw2d.light(game.world, room)
    room.checkpoint = #game.history
    room.enteredAt = {game.state.x, game.state.z}
    if not room.visited then
        room.visited = true
        progress.visit(room.level.name)
        refreshMap()
    end
end

----------------------------------------------------------------------------------------------------
-- loading
----------------------------------------------------------------------------------------------------

-- the tiles, the fonts and the saved progress, then the castle: loading is done in steps, see main.lua
function game.initArt()
    tiles.load()
    game.clock = 0
    fonts = {small = lg.newFont(14), big = lg.newFont(30)}
    progress.load()
end

-- the castle, every room's crates, and the map; game.load then goes to a room
function game.initWorld()
    game.world = world.new(levels)
    game.world.isDoorOpen = isDoorOpen
    -- every crate of the castle is in one list, each crate knows its room (crate.home)
    game.state = {x = 0, z = 0, crates = {}}
    for _,room in ipairs(game.world.rooms) do
        room.startCrates = room.crates
        room.crates = {}
        for i,crate in ipairs(room.startCrates) do
            room.crates[i] = newCrate(crate.x, crate.z, room)
            game.state.crates[#game.state.crates+1] = room.crates[i]
        end
        room.solved = progress.isSolved(room.level.name)
        room.visited = room.solved or progress.isVisited(room.level.name)
        resetCrates(room, room.solved)
        room.checkpoint = 0
    end
    indexCrates()
    for _,room in ipairs(game.world.rooms) do room.gate = isOpen(room) and 1 or 0 end

    draw2d.buildCastle(game.world)
    game.map = map.new(game.world)
    refreshMap()
    game.history, game.tracks = {}, {}
end

-- forgets which rooms are solved and visited, for this session only (the screenshot tour starts from nothing)
function game.forgetProgress()
    for _,room in ipairs(game.world.rooms) do
        room.solved, room.visited = false, false
        resetCrates(room, false)
        room.gate, room.checkpoint = 0, 0
    end
    indexCrates()
    refreshMap()
end

-- a new game: erases the saved progress too, and goes back to the start of the first room
function game.newGame()
    progress.reset()
    game.forgetProgress()
    game.load(1, true)
end

-- fast travel: the map can take you to the start of any room you have been in, and to the island once the last
-- room is solved, since its way out leads there
function game.canTravel(index)
    local room = game.world.rooms[index]
    if room then return room.visited end
    return game.world.rooms[game.world.finalExit.room].solved
end

-- goes to a level: the start of a puzzle room, or the island
-- a room you solved has its crates on their goals, so its open door makes sense; fresh puts them back where the room
-- starts instead, to play it again
function game.load(index, fresh)
    game.index = index
    game.level = levels[index]
    game.queued, game.toast = nil, nil
    -- the camera jumps straight to the new place, see main.lua
    game.cameraCut = true
    if #game.level.crates > 0 then
        local room = game.world.rooms[index]
        game.tiles, game.units = game.world, nil
        resetCrates(room, room.solved and not fresh)
        indexCrates()
        -- undo doesn't go back past a jump on the map
        game.history = {}
        for i = #game.tracks, 1, -1 do game.tracks[i] = nil end
        game.state.x, game.state.z = room.start[1], room.start[2]
        game.player = Player:new(game.tiles, room.start[1], room.start[2])
        enterRoom(room)
        draw2d.light(game.world, room, true)
    else
        game.room = nil
        game.tiles = grid.new(game.level)
        draw2d.buildIsland(game.tiles)
        game.player = Player:new(game.tiles, game.tiles.start[1], game.tiles.start[2])
        -- the free-roam island is a tactics board: units to select and move instead of the player
        game.units = Units.new(game.tiles, game.level.units)
    end
    refreshMap()
end

function game.undo()
    local last = table.remove(game.history)
    if not last then return end
    game.state.x, game.state.z = last.x, last.z
    if last.crate then
        local crate = last.crate
        crate.x, crate.z = last.crateX, last.crateZ
        crate.fromX, crate.fromZ, crate.progress = crate.x, crate.z, 1
    end
    indexCrates()
    local room = game.world.rooms[last.room]
    room.moves, room.pushes, room.recorded = last.moves, last.pushes, last.recorded
    for i = #game.tracks, last.trackCount + 1, -1 do game.tracks[i] = nil end
    if room ~= game.room then
        game.room, game.index, game.level = room, room.index, room.level
        draw2d.light(game.world, room)
    end
    game.player:placeAt(game.state.x, game.state.z)
    game.player:face(last.facingX, last.facingZ)
    game.queued = nil
end

-- back to how things were when you walked into this room, or back to its start on the island
function game.restart()
    if game.units then return game.load(game.index) end
    local room = game.room
    if #game.history <= room.checkpoint then return game.load(room.index, true) end
    while #game.history > room.checkpoint do game.undo() end
    game.toast = nil
end

function game.isPuzzle()
    return game.room ~= nil
end

-- true while standing in the open way out of the last room, which leads to the island
function game.atTheEnd()
    local exit = game.world.finalExit
    return game.room and game.room.index == exit.room and isOpen(game.room)
        and game.state.x == exit.pos[1] and game.state.z == exit.pos[2] or false
end

----------------------------------------------------------------------------------------------------
-- moving
----------------------------------------------------------------------------------------------------

-- the player walked into a way out with every goal covered, or covered the last goal of a dead end: the room is solved
local function solveRoom(room)
    room.recorded = true
    local first = not room.solved
    room.solved = true
    game.newBest = progress.record(room.level.name, room.moves, room.pushes)
    local text = ("Solved! %d moves, %d pushes"):format(room.moves, room.pushes)
    if game.newBest and not first then text = text .. ", a new best!" end
    game.toast = {text = text, at = game.clock}
    -- there's no way on from a dead end: say how to get back
    if #room.exits == 0 then
        local pad = #love.joystick.getJoysticks() > 0
        game.toast.hint = ("A dead end: the map (%s) takes you back"):format(pad and "L2/R2" or "M")
    end
    refreshMap()
end

local function tryMove(dx, dz)
    game.player:face(dx, dz)
    local fromX, fromZ = game.state.x, game.state.z
    local pushed = crateOn(fromX + dx, fromZ + dz)
    local crateX, crateZ = pushed and pushed.x, pushed and pushed.z
    local moved, crate = sokoban.move(game.state, game.tiles, dx, dz)
    if not moved then
        -- leaning into a crate that won't move
        if pushed then game.player:bump() end
        return
    end

    local room = game.room
    game.history[#game.history+1] = {x = fromX, z = fromZ, crate = crate, crateX = crateX, crateZ = crateZ,
        room = room.index, moves = room.moves, pushes = room.pushes, recorded = room.recorded,
        trackCount = #game.tracks, facingX = dx, facingZ = dz}
    -- only steps on the floor of the room count, not walking in from the corridor
    local from = game.tiles:tile(fromX, fromZ)
    if from.room == room.index and from.material.inside then room.moves = room.moves + 1 end

    if crate then
        indexCrates()
        if from.room == room.index then room.pushes = room.pushes + 1 end
        crate.fromX, crate.fromZ, crate.progress = crate.x - dx, crate.z - dz, 0
        crate.track = {x = crate.fromX, z = crate.fromZ, dx = dx, dz = dz, crate = crate}
        game.tracks[#game.tracks+1] = crate.track
    end
    game.player:walkTo(game.state.x, game.state.z, crate ~= nil)

    -- walked through a doorway into another room
    local tile = game.tiles:tile(game.state.x, game.state.z)
    if tile.room and tile.room ~= room.index and tile.material.inside then
        enterRoom(game.world.rooms[tile.room])
    elseif not room.recorded and room.moves > 0 and goalsCovered(room)
        and (#room.exits == 0 or world.exitAt(room, game.state.x, game.state.z)) then
        -- a dead end has no way out, so it is solved as soon as the last crate is on its goal
        solveRoom(room)
    end
end

-- remember a direction that was tapped while the player was still walking, so quick taps aren't lost
function game.queue(dx, dz)
    game.queued = {dx, dz}
end

-- on the island a held direction moves the cursor again after a short wait, then keeps repeating
local cursorDelay, cursorRepeat = 0.3, 0.1
local cursorTimer = 0

local function updateUnits(dt, dx, dz)
    game.units:update(dt)
    if game.queued then
        game.units:moveCursor(game.queued[1], game.queued[2])
        game.queued = nil
        cursorTimer = cursorDelay
    elseif dx ~= 0 or dz ~= 0 then
        cursorTimer = cursorTimer - dt
        if cursorTimer <= 0 then
            game.units:moveCursor(dx, dz)
            cursorTimer = cursorRepeat
        end
    else
        cursorTimer = cursorDelay
    end
end

-- dx and dz is the direction being held, one of them should be 0
function game.update(dt, dx, dz)
    game.clock = game.clock + dt
    if game.units then return updateUnits(dt, dx, dz) end

    game.player:update(dt)
    draw2d.update(dt)
    for _,crate in ipairs(game.state.crates) do
        if crate.progress < 1 then crate.progress = math.min(crate.progress + dt/Player.stepTime, 1) end
    end
    -- doors sink into the floor when they open, and come back up when a crate is pushed off a goal
    for _,room in ipairs(game.world.rooms) do
        local open = isOpen(room)
        if open and room.gate == 0 then room.openedAt = game.clock end
        local target = open and 1 or 0
        if room.gate < target then room.gate = math.min(room.gate + dt/gateTime, 1) end
        if room.gate > target then room.gate = math.max(room.gate - dt/gateTime, 0) end
    end
    if mapChanged() then refreshMap() end

    if game.player:isWalking() then return end
    if game.queued then
        dx, dz = game.queued[1], game.queued[2]
        game.queued = nil
    end
    if dx ~= 0 or dz ~= 0 then
        tryMove(dx, dz)
    end
end

function game.mousepressed(x, y, button)
    if game.units then game.units:click(x, y, button) end
end

-- the cursor follows the mouse
function game.mousemoved(x, y)
    if not game.units then return end
    game.units:setCursor(camera.toTile(x, y, lg.getDimensions()))
end

-- what the camera frames (see camera.lua): the box of tiles of the room you're in, or on the island the whole island,
-- with the tile to keep in view when it doesn't fit, like when zoomed in
function game.view()
    if game.units then
        local t, target = game.tiles, game.units.cameraTarget
        return {box = {minX = t.minX, maxX = t.maxX, minZ = t.minZ, maxZ = t.maxZ}, follow = {target[1], target[3]}}
    end
    local p = game.player.position
    return {box = game.room.box, follow = {p[1], p[3]}}
end

-- whether a crate on this tile is on a goal
function game.isGoal(x, z)
    return sokoban.isGoal(game.tiles, x, z)
end

function game.keypressed(k)
    if game.units then
        -- confirm picks the tile under the cursor, cancel deselects
        if k == "space" or k == "return" then game.units:confirm() end
        if k == "z" or k == "backspace" then game.units:select(nil) end
    end
    if (k == "z" or k == "backspace") and not game.units then game.undo() end
    if k == "r" then game.restart() end
    if (k == "space" or k == "return") and game.atTheEnd() then game.load(game.index + 1) end
    if k == "]" and levels[game.index + 1] then game.load(game.index + 1) end
    if k == "[" and levels[game.index - 1] then game.load(game.index - 1) end
end

----------------------------------------------------------------------------------------------------
-- drawing
----------------------------------------------------------------------------------------------------

-- the castle or the island, framed by the camera
function game.draw()
    local w, h = lg.getDimensions()
    lg.push()
    camera.apply(w, h)
    if game.units then draw2d.drawIsland(game) else draw2d.drawCastle(game) end
    lg.pop()
end

-- the box behind the HUD, the menu and the level picker: nearly black, with a rounded white and grey double border,
-- like the text boxes of old adventure games
function game.panel(x, y, w, h)
    lg.setColor(0.02, 0.02, 0.06, 0.88)
    lg.rectangle("fill", x, y, w, h, 6, 6)
    lg.setLineWidth(2)
    lg.setColor(0.96, 0.96, 0.92)
    lg.rectangle("line", x + 1, y + 1, w - 2, h - 2, 6, 6)
    lg.setLineWidth(1)
    lg.setColor(0.50, 0.50, 0.56)
    lg.rectangle("line", x + 4.5, y + 4.5, w - 9, h - 9, 3, 3)
    lg.setColor(1, 1, 1)
end

-- the bar at the top of the screen with the controls, wrapped onto more lines when the window is narrow; returns how
-- tall it is, so the minimap can go under it
function game.drawHelp(text)
    local font = lg.getFont()
    local _, lines = font:getWrap(text, lg.getWidth() - 12)
    local height = 8 + #lines*font:getHeight()
    lg.setColor(0, 0, 0, 0.5)
    lg.rectangle("fill", 0, 0, lg.getWidth(), height)
    lg.setColor(1, 1, 1)
    lg.printf(text, 6, 4, lg.getWidth() - 12)
    return height
end

-- the minimap in the top right corner, under the help bar, around the player
local function drawMinimap(w, top)
    local scale = w >= 900 and 4 or 3
    local mw, mh = 46*scale, 30*scale
    local mx, my = w - mw - 12, top + 10
    game.panel(mx - 4, my - 4, mw + 8, mh + 8)
    lg.setColor(0.03, 0.02, 0.07, 0.8)
    lg.rectangle("fill", mx, my, mw, mh)
    lg.setColor(1, 1, 1)
    local p = game.player.position
    game.map:drawMini(mx, my, mw, mh, scale, p[1], p[3], game.clock)
end

-- top is how far down the help bar at the top of the screen reaches
function game.drawHud(top)
    local previousFont = lg.getFont()
    local w, h = lg.getDimensions()
    local puzzles = #game.world.rooms

    lg.setFont(fonts.small)
    game.panel(12, h - 70, 340, 58)
    if game.isPuzzle() then
        local room = game.room
        lg.print(("Room %d/%d  %s"):format(room.index, puzzles, room.level.name), 22, h - 62)
        local best = progress.best(room.level.name)
        local bestText = best and ("   Best %d"):format(best.moves) or ""
        lg.print(("Moves %d   Pushes %d%s"):format(room.moves, room.pushes, bestText), 22, h - 40)
        drawMinimap(w, top or 0)
    else
        lg.print("Pick a unit, then a blue square to move it", 22, h - 62)
        lg.print("Cancel to deselect, previous level for the puzzles", 22, h - 40)
    end

    -- a hint above the panel while the open way out waits for the player
    local room = game.room
    if room and not room.recorded and not room.solved and goalsCovered(room) then
        local r, g, b = unpack(draw2d.doorLight)
        game.panel(12, h - 102, 260, 26)
        lg.setColor(r, g, b, 0.75 + 0.25*math.sin(game.clock*5))
        lg.print("The door is open: walk through it", 22, h - 97)
        lg.setColor(1, 1, 1)
    end

    if game.atTheEnd() then
        local bw, bh = 520, 130
        local bx, by = (w - bw)/2, 50 -- near the top, so the solved puzzle stays in view
        game.panel(bx, by, bw, bh)
        lg.setFont(fonts.big)
        lg.printf("Every puzzle solved!", bx, by + 18, bw, "center")
        lg.setFont(fonts.small)
        local result = ("%d moves, %d pushes"):format(room.moves, room.pushes)
        lg.printf(result .. (game.newBest and ", a new best!" or ""), bx, by + 62, bw, "center")
        lg.printf("Space to visit the island   Z to undo", bx, by + 88, bw, "center")
    elseif game.toast and game.clock - game.toast.at < 3 then
        -- a short note at the top when a room is solved, it fades out while you walk on
        local alpha = math.min(1, 3 - (game.clock - game.toast.at))
        local bw, bh = 360, game.toast.hint and 56 or 34
        local bx, by = math.floor((w - bw)/2), (top or 0) + 10
        lg.setColor(1, 1, 1, alpha)
        game.panel(bx, by, bw, bh)
        lg.setColor(1, 1, 1, alpha)
        lg.printf(game.toast.text, bx, by + 9, bw, "center")
        if game.toast.hint then
            lg.setColor(1, 1, 1, alpha*0.75)
            lg.printf(game.toast.hint, bx, by + 31, bw, "center")
        end
        lg.setColor(1, 1, 1)
    end
    lg.setFont(previousFont)
end

return game
