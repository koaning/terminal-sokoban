-- checks every level in levels.lua without opening a window: run with `luajit check.lua` or `make check`
-- puzzles must have as many goals as crates, a way out (unless they are a dead end) and (after the first) a way in, and
-- must be solvable: every crate on a goal and the player in a way out, both from the start and when walking in through
-- any way in
-- every other level must be fully walkable; the rooms must fit together into one world (see world.lua), and every room
-- must be shown big enough on a handheld

local grid = require "grid"
local sokoban = require "sokoban"
local levels = require "levels"
local world = require "world"
local camera = require "camera"
local tiles = require "tiles"

local failed = false
local function fail(message)
    print("  FAIL: " .. message)
    failed = true
end

-- flood fill from the start tile, ignoring crates
local function reachableTiles(tiles)
    local reachable = {[tiles.start[1] .. "," .. tiles.start[2]] = true}
    local queue = {tiles.start}
    while #queue > 0 do
        local x, z = unpack(table.remove(queue))
        for _,d in ipairs{{1,0}, {-1,0}, {0,1}, {0,-1}} do
            local nx, nz = x + d[1], z + d[2]
            if not reachable[nx .. "," .. nz] and tiles:canStep(x, z, nx, nz) then
                reachable[nx .. "," .. nz] = true
                queue[#queue+1] = {nx, nz}
            end
        end
    end
    return reachable
end

for i,level in ipairs(levels) do
    local tiles = grid.new(level)
    io.write(("%d. %s (%dx%d)"):format(i, level.name, tiles.width, tiles.depth))

    if #level.crates > 0 then
        local goals = 0
        for x = tiles.minX, tiles.maxX do
            for z = tiles.minZ, tiles.maxZ do
                if sokoban.isGoal(tiles, x, z) then goals = goals + 1 end
            end
        end
        local moves, states = sokoban.solve(tiles, level.crates)
        -- walking in through any of the ways in has to start a puzzle that can be solved too
        local fromEntries = {}
        for k,entry in ipairs(tiles.entries) do
            local n, count = sokoban.solve(tiles, level.crates, nil, entry)
            fromEntries[#fromEntries+1] = n and tostring(n) or "none"
            if not n then fail(("no solution from way in %d found after %d states"):format(k, count)) end
        end
        print(moves and (": solvable in %d moves%s"):format(moves,
            #fromEntries > 0 and (", from the way%s in: %s"):format(#fromEntries > 1 and "s" or "",
                table.concat(fromEntries, ", ")) or "") or "")
        if goals ~= #level.crates then fail(("%d crates but %d goals"):format(#level.crates, goals)) end
        -- a dead end leads nowhere and has no way out, the last room leads nowhere too but its way out goes to the island
        local lastRoom = not (levels[i + 1] and #levels[i + 1].crates > 0)
        local deadEnd = #(level.to or {}) == 0 and not lastRoom
        if #tiles.exits == 0 and not deadEnd then fail("no way out, every puzzle needs one: > in levels.lua") end
        if #tiles.entries == 0 and i > 1 then fail("no way in, every puzzle after the first needs one: < in levels.lua") end
        if not moves then fail(("no solution found after %d states"):format(states)) end
        -- once a room is solved its ways out stay open, and it has to be possible to walk through it from every door to
        -- every other door, starting with every crate on a goal: crates may be pushed out of the way
        local doors = {}
        for _,door in ipairs(tiles.exits) do doors[#doors+1] = door end
        for _,door in ipairs(tiles.entries) do doors[#doors+1] = door end
        local solved = {}
        for x = tiles.minX, tiles.maxX do
            for z = tiles.minZ, tiles.maxZ do
                if sokoban.isGoal(tiles, x, z) then solved[#solved+1] = {x = x, z = z} end
            end
        end
        local open = setmetatable({isDoorOpen = function() return true end}, {__index = tiles})
        for _,from in ipairs(doors) do
            for _,to in ipairs(doors) do
                if from ~= to then
                    local start = sokoban.newState(tiles, solved, from)
                    local found = sokoban.search(open, start, function(state)
                        return state.x == to[1] and state.z == to[2]
                    end, 200000, true)
                    if not found then
                        fail(("once solved, there is no way through it from the door at %d,%d to the one at %d,%d"):format(
                            from[1], from[2], to[1], to[2]))
                    end
                end
            end
        end
    else
        local reachable = reachableTiles(tiles)
        local unreachable = 0
        for x = tiles.minX, tiles.maxX do
            for z = tiles.minZ, tiles.maxZ do
                if tiles:tile(x, z).material.walkable and not reachable[x .. "," .. z] then
                    unreachable = unreachable + 1
                end
            end
        end
        print(": free roam")
        if unreachable > 0 then fail(unreachable .. " walkable tiles can't be reached from the start") end
        -- the units must start on different walkable tiles
        local taken = {}
        for j,start in ipairs(level.units or {}) do
            local tile, key = tiles:tile(start[1], start[2]), start[1] .. "," .. start[2]
            if not (tile and tile.material.walkable) then fail(("unit %d starts on %s, which isn't walkable"):format(j, key)) end
            if taken[key] then fail(("units %d and %d both start on %s"):format(taken[key], j, key)) end
            taken[key] = j
        end
    end
end

-- the rooms packed into one castle
local ok, castle = pcall(world.new, levels)
if not ok then
    fail("the rooms don't fit together: " .. tostring(castle))
else
    local forks, joins = 0, 0
    for _,room in ipairs(castle.rooms) do
        if #room.exits > 1 then forks = forks + 1 end
        if #room.entries > 1 then joins = joins + 1 end
    end
    local corridorTiles, longest = 0, nil
    for _,link in ipairs(castle.corridors) do
        corridorTiles = corridorTiles + #link.cells
        if not longest or #link.cells > #longest.cells then longest = link end
    end
    print(("castle: %d rooms, %d forks, %d joins, %d corridor tiles (longest %d), %dx%d tiles"):format(#castle.rooms,
        forks, joins, corridorTiles, longest and #longest.cells or 0, castle.width, castle.depth))
    -- rooms share doorways, a corridor is only a short link where that doesn't fit: no long hallways
    for _,link in ipairs(castle.corridors) do
        if #link.cells > 6 then
            fail(("the corridor from %s to %s is %d tiles long, at most 6: a join, or rooms that don't fit together"):format(
                castle.rooms[link.from].name, castle.rooms[link.to].name, #link.cells))
        end
    end

    -- walking around the castle with every door open and the crates of the rooms left out: every room has to be
    -- reachable from the first one
    local start = castle.rooms[1].start
    local seen, queue = {[start[1] .. "," .. start[2]] = true}, {start}
    while #queue > 0 do
        local x, z = unpack(table.remove(queue))
        for _,d in ipairs{{1,0}, {-1,0}, {0,1}, {0,-1}} do
            local nx, nz = x + d[1], z + d[2]
            local k = nx .. "," .. nz
            if not seen[k] and castle:canStep(x, z, nx, nz) then
                seen[k] = true
                queue[#queue+1] = {nx, nz}
            end
        end
    end
    for _,room in ipairs(castle.rooms) do
        if not seen[room.start[1] .. "," .. room.start[2]] then
            fail(room.level.name .. " can't be reached from the first room")
        end
    end

    -- every room has to fit the screen of a 640x480 handheld at 4 screen pixels per pixel of the art, so an 8 pixel
    -- tile is 32 pixels, and the smallest window at 2
    local screens = {{"640x480 handheld", 640, 480, 4}, {"640x360 window", 640, 360, 2}}
    for _,screen in ipairs(screens) do
        local worst
        for _,room in ipairs(castle.rooms) do
            local scale = camera.fit(room.box, screen[2], screen[3])
            if not worst or scale < worst[2] then worst = {room, scale} end
        end
        local b = worst[1].box
        print(("framing on a %s: at least %dx (%s, %dx%d tiles)"):format(screen[1], worst[2], worst[1].name,
            b.maxX - b.minX + 1, b.maxZ - b.minZ + 1))
        if worst[2] < screen[4] then
            fail(("%s is drawn at %dx on a %s, at least %dx is needed"):format(worst[1].name, worst[2], screen[1], screen[4]))
        end
    end
end

-- the wall tiles: every combination of walls around a wall, corners included, is put together from quarters of
-- Kenney's wall pieces, or the plain top of a wall in the middle of a thick one
local wallPieces = {[144] = true, [145] = true, [147] = true, [148] = true, [150] = true, [153] = true,
    [tiles.wallTop] = true}
for mask = 0, 255 do
    local quarters = tiles.wallQuarters(mask)
    if #quarters ~= 4 then fail(("wall %d has %d quarters"):format(mask, #quarters)) end
    for _,q in ipairs(quarters) do
        if not wallPieces[q[1]] then fail(("wall %d takes a quarter from tile %s"):format(mask, tostring(q[1]))) end
    end
end

-- the tiles drawn as text, the poses of the player and the crate: 8 rows of 8, in the colours of the sheet
for index,rows in pairs(tiles.pixelTiles) do
    local ok = #rows == 8
    for _,row in ipairs(rows) do
        if #row ~= 8 or row:find("[^ABCL%.]") then ok = false end
    end
    if not ok then fail(("drawn tile %d isn't 8 rows of 8 of A, B, C, L or ."):format(index)) end
end

if failed then os.exit(1) end
print("all levels ok")
