-- drawing the castle and the island in 2D, top down with north up, in Kenney's Micro Roguelike tiles (see tiles.lua)
-- everything is drawn in pixels of the art, camera.apply scales it up to the screen
--
-- what doesn't move (floors, walls, goals, doorways) is put in one sprite batch per room and per corridor when the
-- castle is laid out, so drawing a room is one draw call; crates, gates, scrape marks and the player are drawn on top
-- every frame, all from the same texture, so LÖVE batches those too
--
-- only the room you're in is lit: the rooms next to it are dimmed, so you can see where the doors lead, the corridors
-- to them are lit as part of the way out, and the rest of the castle isn't drawn

local tiles = require "tiles"

local lg = love.graphics

local draw2d = {}

local S = tiles.size

-- the light of an open way out, the same as on the map
draw2d.doorLight = {0.45, 0.95, 1.0}
-- what's outside the castle and around the island: a warm dusky stone, the castle is carved out of it
draw2d.void = {0.42, 0.32, 0.34}

-- how bright the room you're in is drawn, and the rooms next to it
local litLevel, dimLevel = 1, 0.75
-- how long the light takes to move over when you walk into another room
local lightFade = 0.35
-- how far a gate sinks into the floor when it opens, in pixels
local gateDrop = 6

-- the top left corner of tile x, z in pixels of the art
local function corner(x, z)
    return x*S, -z*S
end

-- a sprite batch with a coloured square under every tile, then the tiles that go on top of it
local function newBatch(count)
    return lg.newSpriteBatch(tiles.image, count, "static")
end

local function addTile(batch, index, x, z)
    local px, py = corner(x, z)
    batch:add(tiles.quads[index], px, py)
end

local function addFill(batch, x, z, color)
    batch:setColor(color[1], color[2], color[3], 1)
    addTile(batch, tiles.white, x, z)
    batch:setColor(1, 1, 1, 1)
end

----------------------------------------------------------------------------------------------------
-- the castle
----------------------------------------------------------------------------------------------------

local function isWallish(tile)
    return tile and (tile.kind == "wall" or tile.kind == "door") or false
end

-- whether a door is in a wall that runs left to right, so it gets an archway; otherwise it's in a wall that runs up
-- and down
local function isAcross(w, x, z)
    return isWallish(w:tile(x - 1, z)) and isWallish(w:tile(x + 1, z))
end

-- the tiles on top of the floor of one tile of the castle
local function addCastleTile(batch, w, x, z)
    local tile = w:tile(x, z)
    if tile.kind == "wall" then
        addFill(batch, x, z, tiles.mortar)
    else
        addFill(batch, x, z, (x + z) % 2 == 0 and tiles.floor or tiles.floorAlt)
    end
    if tile.kind == "wall" then
        -- a quarter at a time, see tiles.wallQuarters
        local mask = tiles.mask(function(dx, dz) return isWallish(w:tile(x + dx, z + dz)) end, true)
        local px, py = corner(x, z)
        for _,q in ipairs(tiles.wallQuarters(mask)) do
            batch:add(tiles.quarter(q[1], q[2], q[3]), px + q[2], py + q[3])
        end
    elseif tile.kind == "door" then
        addTile(batch, isAcross(w, x, z) and tiles.arch or tiles.sideDoor, x, z)
    elseif tile.material.goal then
        addTile(batch, tiles.goal, x, z)
    elseif tile.kind == "corridor" or tiles.hash(x, z) < 0.06 then
        -- faint, a little dust on the floor
        batch:setColor(1, 1, 1, 0.4)
        addTile(batch, tiles.speckle, x, z)
        batch:setColor(1, 1, 1, 1)
    end
end

-- a batch for a list of cells {x, z}
local function castleBatch(w, cells)
    local batch = newBatch(#cells*5)
    for _,c in ipairs(cells) do addCastleTile(batch, w, c[1], c[2]) end
    return batch
end

-- the batches of every room and every corridor: a corridor is its cells and the walls around them
function draw2d.buildCastle(w)
    draw2d.parts = {}
    for _,room in ipairs(w.rooms) do
        draw2d.parts["r" .. room.index] = {batch = castleBatch(w, room.cells), light = 0, target = 0}
    end
    for i,link in ipairs(w.corridors) do
        if #link.cells > 0 then
            local cells, seen = {}, {}
            for _,c in ipairs(link.cells) do
                for dx = -1, 1 do
                    for dz = -1, 1 do
                        local x, z = c[1] + dx, c[2] + dz
                        local k = x .. "," .. z
                        local tile = w:tile(x, z)
                        if not seen[k] and tile and ((dx == 0 and dz == 0) or tile.kind == "wall") then
                            seen[k] = true
                            cells[#cells+1] = {x, z}
                        end
                    end
                end
            end
            draw2d.parts["c" .. i] = {batch = castleBatch(w, cells), light = 0, target = 0}
        end
    end
    -- the doors of every room, which way they face
    for _,room in ipairs(w.rooms) do
        for _,exit in ipairs(room.exits) do exit.across = isAcross(w, exit.pos[1], exit.pos[2]) end
    end
end

-- lights up a room: it's lit, and so are the corridors out of it; the rooms next to it are dimmed, and everything else
-- goes dark; the light fades over, unless instant is true
function draw2d.light(w, room, instant)
    for _,part in pairs(draw2d.parts) do part.target = 0 end
    for i,link in ipairs(w.corridors) do
        if link.from == room.index or link.to == room.index then
            local part = draw2d.parts["c" .. i]
            if part then part.target = litLevel end
            local other = link.from == room.index and link.to or link.from
            draw2d.parts["r" .. other].target = dimLevel
        end
    end
    draw2d.parts["r" .. room.index].target = litLevel
    if instant then
        for _,part in pairs(draw2d.parts) do part.light = part.target end
    end
end

function draw2d.update(dt)
    for _,part in pairs(draw2d.parts or {}) do
        if part.light < part.target then part.light = math.min(part.light + dt/lightFade, part.target) end
        if part.light > part.target then part.light = math.max(part.light - dt/lightFade, part.target) end
    end
end

-- how bright a room is drawn
local function roomLight(room)
    return draw2d.parts["r" .. room.index].light
end

-- the scrape marks, each from the middle of the tile a crate was pushed from to where the crate is now: two faint
-- brown lines under the edges of the crate; they are see-through, so a path that crates slid over again and again shows more
local function drawTracks(tracks)
    for _,track in ipairs(tracks) do
        local light = roomLight(track.crate.home)
        if light > 0 then
            -- only the newest mark of a crate can still be growing
            local length = track.crate.track == track and track.crate.progress or 1
            local x0, y0 = corner(track.x, track.z)
            x0, y0 = x0 + S/2, y0 + S/2
            local dx, dy = track.dx, -track.dz
            local reach = math.floor(length*S + 0.5)
            lg.setColor(0.45*light, 0.30*light, 0.20*light, 0.22)
            for _,side in ipairs{-3, 2} do
                if dx ~= 0 then
                    local x = dx > 0 and x0 or x0 - reach
                    lg.rectangle("fill", x, y0 + side, reach, 1)
                else
                    local y = dy > 0 and y0 or y0 - reach
                    lg.rectangle("fill", x0 + side, y, 1, reach)
                end
            end
        end
    end
end

-- every crate of a room that is drawn; a crate on a goal glows gold
local function drawCrates(game)
    for _,crate in ipairs(game.state.crates) do
        local light = roomLight(crate.home)
        if light > 0 then
            local t = crate.progress
            local x = crate.fromX + (crate.x - crate.fromX)*t
            local z = crate.fromZ + (crate.z - crate.fromZ)*t
            local px, py = math.floor(x*S + 0.5), math.floor(-z*S + 0.5)
            lg.setColor(light, light, light)
            tiles.draw(tiles.crate, px, py)
            if t >= 1 and game.isGoal(crate.x, crate.z) then
                lg.setBlendMode("add")
                lg.setColor(0.45*light, 0.32*light, 0.05*light)
                tiles.draw(tiles.crate, px, py)
                lg.setBlendMode("alpha")
            end
        end
    end
end

-- the gates in the ways out of a room, sunk into the floor as far as they are open
local function drawGates(room, light)
    if room.gate >= 1 then return end
    -- ease in and out, so it starts and stops softly
    local t = room.gate*room.gate*(3 - 2*room.gate)
    for _,exit in ipairs(room.exits) do
        local px, py = corner(exit.pos[1], exit.pos[2])
        if exit.across then
            lg.setColor(light, light, light)
            tiles.drawSunk(tiles.gate, px, py, math.floor(t*gateDrop + 0.5))
        else
            lg.setColor(light, light, light, 1 - t)
            tiles.draw(tiles.sideGate, px, py)
        end
    end
end

-- an open way out glows, and flashes for a moment when it opens
local function drawDoorLight(game, room, light)
    if room.gate <= 0 then return end
    local pulse = 0.5 + 0.5*math.sin(game.clock*5)
    local flare = math.max(0, 1 - (game.clock - (room.openedAt or -10))/0.8)
    local c = draw2d.doorLight
    -- painted over the light floor rather than added to it, which would wash out to white
    local a = room.gate*light*(0.3 + 0.15*pulse + 0.45*flare)
    lg.setColor(c[1], c[2], c[3], a)
    for _,exit in ipairs(room.exits) do
        local px, py = corner(exit.pos[1], exit.pos[2])
        if exit.across then
            lg.rectangle("fill", px + 2, py + 3, S - 4, S - 3)
        else
            lg.rectangle("fill", px, py + 2, S, S - 4)
        end
    end
end

-- the pose of the player for the way it faces: from the back walking up, from the side walking left or right (mirrored
-- for left), from the front walking down; halfway through a step a leg is lifted, the other leg on the next step
-- (mirroring the symmetric front and back), and from the side the arms reach out while pushing
-- returns the tile and whether to mirror it
local function playerPose(p)
    local poses = tiles.playerPoses
    local stepping = p.progress < 0.5
    if p.facingX ~= 0 then
        if p.push > 0.5 then return poses.sidePush, p.facingX < 0 end
        return stepping and poses.sideStep or poses.side, p.facingX < 0
    end
    local back = p.facingZ > 0
    if stepping then
        return back and poses.backStep or poses.frontStep, p.steps % 2 == 1
    end
    return back and poses.back or poses.front, false
end

-- a character walking from tile to tile (a Player from player.lua): it hops a little on every step, more on a ledge,
-- and leans into a crate it pushes; index is its tile, or nil for the player, who turns to face where it goes
local function drawWalker(p, index)
    local x, z = p.position[1], p.position[3]
    local px, py = x*S, -z*S
    if p.progress < 1 then
        local stair = p.grid:isStair(p.fromX, p.fromZ, p.x, p.z)
        py = py - math.sin(p.progress*math.pi)*(stair and 3 or 1.5)
    end
    if p.push > 0.5 then
        px, py = px + p.facingX, py - p.facingZ
    end
    local flip = p.facingX < 0
    if not index then index, flip = playerPose(p) end
    tiles.draw(index, math.floor(px + 0.5), math.floor(py + 0.5), flip)
end

function draw2d.drawCastle(game)
    -- dimmest first, so where two rooms share a wall the lit one is drawn last
    local list = {}
    for _,part in pairs(draw2d.parts) do
        if part.light > 0 then list[#list+1] = part end
    end
    table.sort(list, function(a, b) return a.light < b.light end)
    for _,part in ipairs(list) do
        lg.setColor(part.light, part.light, part.light)
        lg.draw(part.batch)
    end

    drawTracks(game.tracks)
    drawCrates(game)
    for _,room in ipairs(game.world.rooms) do
        local light = roomLight(room)
        if light > 0 then drawGates(room, light) end
    end
    lg.setColor(1, 1, 1)
    drawWalker(game.player)
    for _,room in ipairs(game.world.rooms) do
        local light = roomLight(room)
        if light > 0 then drawDoorLight(game, room, light) end
    end
    lg.setColor(1, 1, 1)
end

----------------------------------------------------------------------------------------------------
-- the island
----------------------------------------------------------------------------------------------------

-- the ground of the island, out in the sun: grass, a sandy path and stone, a little lighter the higher it is
local groundColors = {
    g = {0.45, 0.68, 0.36}, t = {0.45, 0.68, 0.36}, -- grass
    d = {0.80, 0.68, 0.48}, ["@"] = {0.80, 0.68, 0.48}, -- path, and where the units start
    s = {0.66, 0.60, 0.56}, S = {0.66, 0.60, 0.56},  -- stone
}

local function groundColor(material, height)
    local c = groundColors[material] or groundColors.g
    local up = 0.012*height
    return {c[1] + up, c[2] + up, c[3] + up}
end

-- the island, which is one batch
function draw2d.buildIsland(grid)
    local level = grid.level
    local batch = newBatch(grid.width*grid.depth*3)
    local function material(x, z)
        local row = level.materials[grid.depth - z]
        local m = row and row:sub(x + 1, x + 1)
        return m ~= "" and m or nil
    end
    local function isWater(x, z)
        local m = material(x, z)
        -- off the edge of the map the water goes on
        return m == nil or m == "w" or m == "b"
    end
    for x = grid.minX, grid.maxX do
        for z = grid.minZ, grid.maxZ do
            local tile, m = grid:tile(x, z), material(x, z)
            local h, roll = tile.height, tiles.hash(x, z)
            if m == "w" or m == "b" then
                local shore = tiles.mask(function(dx, dz) return not isWater(x + dx, z + dz) end)
                addTile(batch, tiles.waterIndex(shore), x, z)
                if m == "b" then addTile(batch, tiles.bridge, x, z) end
            else
                addFill(batch, x, z, groundColor(m, h))
                -- the side of a higher tile next to this one, where it's too high to step up
                local function higher(dx, dz)
                    local other = grid:tile(x + dx, z + dz)
                    return other and other.height - h >= 2
                end
                if higher(0, 1) then addTile(batch, tiles.cliff, x, z) end
                if higher(-1, 0) then addTile(batch, tiles.edgeLeft, x, z) end
                if higher(1, 0) then addTile(batch, tiles.edgeRight, x, z) end
                if m == "t" then
                    addTile(batch, tiles.trees[math.floor(roll*#tiles.trees) + 1], x, z)
                elseif m == "S" then
                    addTile(batch, tiles.pillar, x, z)
                elseif m == "s" and roll < 0.5 then
                    addTile(batch, tiles.stone, x, z)
                elseif (m == "d" or m == "@") and roll < 0.6 then
                    addTile(batch, tiles.speckle, x, z)
                elseif m == "g" and roll < 0.15 then
                    addTile(batch, tiles.sprigs, x, z)
                end
            end
        end
    end
    draw2d.island = batch
end

local highlightColors = {
    selected = {1, 0.85, 0.2},
    target = {0.4, 0.65, 1},
    cursor = {1, 1, 1},
}

local function drawFrame(x, z, color, alpha)
    lg.setColor(color[1], color[2], color[3], alpha or 1)
    local px, py = corner(x, z)
    tiles.draw(tiles.frame, px, py)
end

function draw2d.drawIsland(game)
    lg.setColor(1, 1, 1)
    lg.draw(draw2d.island)
    local units = game.units
    local unit = units.selected
    if unit and not unit:isWalking() then
        drawFrame(unit.x, unit.z, highlightColors.selected)
        for _,t in ipairs(units:targets(unit)) do drawFrame(t[1], t[2], highlightColors.target) end
    end
    -- the cursor blinks, and goes on top, so it shows on a blue square too
    drawFrame(units.cursorX, units.cursorZ, highlightColors.cursor, 0.6 + 0.4*math.sin(game.clock*6))
    lg.setColor(1, 1, 1)
    for i,u in ipairs(units.list) do drawWalker(u, tiles.units[(i - 1) % #tiles.units + 1]) end
end

return draw2d
