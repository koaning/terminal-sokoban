-- the level picker: the map of the whole world (see map.lua), and fast travel: it takes you to the start of a room
-- you have been in before (view.canTravel says which), those are numbered; solved rooms are gold
-- the d-pad / arrow keys go to the nearest of those that way, A / Enter goes there, B / Esc closes the picker,
-- or click a room; the island hangs off the way out of the last room
-- it opens from the pause menu, and with M

local levels = require "levels"
local progress = require "progress"
local map = require "map"

local lg = love.graphics

local picker = {isOpen = false, index = 1}

local fonts
local rects = {} -- where every room was drawn last, for the mouse

-- onChoose(index) is called with the level that was picked
-- view has the map and the world to show, where the player is, and which levels you can go to:
-- {map =, world =, player = {x, z}, canTravel = function(index)}
function picker.open(index, onChoose, view)
    picker.isOpen, picker.index, picker.onChoose, picker.view = true, index or 1, onChoose, view
    picker.current = picker.index
end

function picker.close()
    picker.isOpen = false
end

-- whether the picker can take you to a level: anywhere you have been, and always the room you are in
local function canGo(index)
    local canTravel = picker.view and picker.view.canTravel
    return index == picker.current or not canTravel or canTravel(index)
end

local function choose(index)
    if not canGo(index) then return end
    picker.close()
    if picker.onChoose then picker.onChoose(index) end
end

local function isPuzzle(index)
    return #levels[index].crates > 0
end

-- where a level is on the map, in world tiles: the middle of a room, and the island in its own place next to the last room
local function position(index)
    local world = picker.view.world
    local room = world.rooms[index]
    if room then return room.centre[1], room.centre[2] end
    return world.island[1], world.island[2]
end

-- goes to the closest level you can go to in a direction on the map: dx to the right, dz up
local function step(dx, dz)
    local x, z = position(picker.index)
    local best, bestScore
    for i = 1, #levels do
        if i ~= picker.index and canGo(i) then
            local ox, oz = position(i)
            local along = (ox - x)*dx + (oz - z)*dz
            local across = math.abs((ox - x)*dz - (oz - z)*dx)
            -- only levels that are more that way than sideways
            if along > 0 and across <= along*1.5 then
                local score = along + across*2
                if not bestScore or score < bestScore then best, bestScore = i, score end
            end
        end
    end
    picker.index = best or picker.index
end

-- the previous or next level in order that you can go to
local function nextLevel(direction)
    local i = picker.index + direction
    while levels[i] and not canGo(i) do i = i + direction end
    return levels[i] and i or picker.index
end

function picker.keypressed(k)
    if k == "escape" or k == "backspace" or k == "z" or k == "m" then
        picker.close()
    elseif k == "left" or k == "a" then
        step(-1, 0)
    elseif k == "right" or k == "d" then
        step(1, 0)
    elseif k == "up" or k == "w" then
        step(0, 1)
    elseif k == "down" or k == "s" then
        step(0, -1)
    elseif k == "[" or k == "q" then
        picker.index = nextLevel(-1)
    elseif k == "]" or k == "e" then
        picker.index = nextLevel(1)
    elseif k == "return" or k == "space" then
        choose(picker.index)
    end
end

local function levelUnder(x, y)
    for i,r in pairs(rects) do
        if canGo(i) and x >= r[1] and x < r[1] + r[3] and y >= r[2] and y < r[2] + r[4] then return i end
    end
end

function picker.mousemoved(x, y)
    picker.index = levelUnder(x, y) or picker.index
end

function picker.mousepressed(x, y, button)
    local i = levelUnder(x, y)
    if button == 1 and i then choose(i) end
end

local function solvedCount()
    local solved, puzzles = 0, 0
    for i,level in ipairs(levels) do
        if isPuzzle(i) then
            puzzles = puzzles + 1
            if progress.isSolved(level.name) then solved = solved + 1 end
        end
    end
    return solved, puzzles
end

function picker.draw(panel)
    fonts = fonts or {title = lg.newFont(18), number = lg.newFont(12), small = lg.newFont(14)}
    local previousFont = lg.getFont()
    local view = picker.view
    local world = view.world

    -- the map, as big as fits in whole pixels per tile, with room for the island to the side
    local w, h = lg.getDimensions()
    local margin = 16
    local islandX, islandZ = position(#levels)
    local minX, maxX = math.min(world.minX, islandX - 3), math.max(world.maxX, islandX + 3)
    local minZ, maxZ = math.min(world.minZ, islandZ - 3), math.max(world.maxZ, islandZ + 3)
    local tilesW, tilesH = maxX - minX + 1, maxZ - minZ + 1
    local fitW, fitH = w - 2*margin - 24, h - 2*margin - 120
    local scale = math.max(1, math.floor(math.min(fitW/tilesW, fitH/tilesH)))
    local mapW, mapH = tilesW*scale, tilesH*scale
    local bw, bh = math.max(mapW + 24, 320), mapH + 120
    local bx, by = math.floor((w - bw)/2), math.floor((h - bh)/2)
    -- darker than the other panels, so the world behind doesn't get in the way of the map
    lg.setColor(0.03, 0.02, 0.07, 0.85)
    lg.rectangle("fill", bx, by, bw, bh)
    panel(bx, by, bw, bh)

    lg.setFont(fonts.title)
    lg.printf("Map", bx, by + 10, bw, "center")
    lg.setFont(fonts.small)
    local solved, puzzles = solvedCount()
    lg.setColor(1, 1, 1, 0.7)
    lg.printf(("%d of %d rooms solved"):format(solved, puzzles), bx, by + 32, bw, "center")

    -- screen position of a world tile
    local ox, oy = math.floor(bx + (bw - mapW)/2), by + 56
    local function toScreen(x, z)
        return ox + (x - minX + 0.5)*scale, oy + (maxZ - z + 0.5)*scale
    end

    lg.setColor(1, 1, 1)
    local sx, sy = toScreen(world.minX, world.maxZ)
    view.map:drawAt(world.minX, world.maxZ, sx, sy, scale)

    -- the island: a green square past the last room, with a dotted line to it
    local ix, iy = toScreen(islandX, islandZ)
    local ex, ey = toScreen(world.finalExit.pos[1], world.finalExit.pos[2])
    lg.setColor(map.colors.bridge)
    for t = 0.2, 0.75, 0.15 do
        lg.rectangle("fill", math.floor(ex + (ix - ex)*t - scale/2), math.floor(ey + (iy - ey)*t - scale/2), scale, scale)
    end
    local size = 5*scale
    rects[#levels] = {ix - size/2, iy - size/2, size, size}
    if canGo(#levels) then lg.setColor(0.18, 0.52, 0.30) else lg.setColor(0.10, 0.20, 0.16) end
    lg.rectangle("fill", ix - size/2, iy - size/2, size, size)

    -- every room's number, and the outline around the one that is selected
    lg.setFont(fonts.number)
    for _,room in ipairs(world.rooms) do
        local x1, y1 = toScreen(room.ox, room.oz + room.tiles.maxZ)
        local x2, y2 = toScreen(room.ox + room.tiles.maxX, room.oz)
        rects[room.index] = {x1 - scale/2, y1 - scale/2, x2 - x1 + scale, y2 - y1 + scale}
        if scale >= 2 and canGo(room.index) then
            local cx, cy = toScreen(position(room.index))
            local label = tostring(room.index)
            local tw, th = fonts.number:getWidth(label), fonts.number:getHeight()
            lg.setColor(0, 0, 0, 0.55)
            lg.rectangle("fill", math.floor(cx - tw/2 - 2), math.floor(cy - th/2), tw + 4, th)
            lg.setColor(1, 1, 1)
            lg.print(label, math.floor(cx - tw/2), math.floor(cy - th/2))
        end
    end
    local r = rects[picker.index]
    if r then
        lg.setColor(1, 1, 1, 0.6 + 0.4*math.sin(love.timer.getTime()*6))
        lg.setLineWidth(2)
        lg.rectangle("line", r[1] - 2, r[2] - 2, r[3] + 4, r[4] + 4)
        lg.setLineWidth(1)
    end

    -- where the player is
    if view.player then
        local px, py = toScreen(view.player[1], view.player[2])
        map.drawPlayer(px, py, math.max(3, scale + 1), love.timer.getTime())
    end

    -- the name and best result of the selected level
    local level = levels[picker.index]
    local best = progress.best(level.name)
    local info
    if picker.index == picker.current and isPuzzle(picker.index) then
        info = "You are here: back to the start of this room"
    elseif not isPuzzle(picker.index) then
        info = "Free roam: move the units around"
    elseif best then
        info = ("Best: %d moves, %d pushes"):format(best.moves, best.pushes)
    else
        info = "Not solved yet"
    end
    local iy2 = oy + mapH + 10
    lg.setColor(1, 1, 1)
    lg.setFont(fonts.title)
    local title = isPuzzle(picker.index) and ("%d. %s"):format(picker.index, level.name) or level.name
    lg.printf(title, bx, iy2, bw, "center")
    lg.setFont(fonts.small)
    lg.setColor(1, 1, 1, 0.7)
    lg.printf(info, bx, iy2 + 24, bw, "center")

    lg.setColor(1, 1, 1)
    lg.setFont(previousFont)
end

return picker
