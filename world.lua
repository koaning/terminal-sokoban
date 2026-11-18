-- the world: every puzzle room is part of one castle floating in the sky, like the rooms of a Metroidvania map
-- levels.lua says which rooms each room leads to (level.to); rooms are packed together so their walls touch: the way
-- out (>) of one room is the way in (<) of the next, a doorway in the wall they share; where two paths join, a room is
-- reached from the second room by a walled corridor instead, which is usually long, so check.lua doesn't allow it
-- the rooms are laid out automatically, in order: each room goes against the room that leads to it, turned or mirrored
-- (which doesn't change the puzzle) so its doors line up, roughly where level.at says on the map
-- this file has no drawing, so the layout can be checked without a window (see check.lua)
--
-- the world is also a grid (see grid.lua) that the player walks around on, in world coordinates:
-- every floor tile of a room knows which room it belongs to (tile.room); corridors belong to no room

local grid = require "grid"
local sokoban = require "sokoban"

local world = setmetatable({}, {__index = grid})
world.__index = world

local directions = {{1,0}, {-1,0}, {0,1}, {0,-1}}
local around8 = {{1,0}, {-1,0}, {0,1}, {0,-1}, {1,1}, {1,-1}, {-1,1}, {-1,-1}}

-- the floor of corridors and the walls around them, the same as the rooms'
world.corridorMaterial = {top = "path", side = "dirt", walkable = true, corridor = true}
world.wallMaterial = sokoban.palette.W
local floorHeight, wallHeight = 2, 3

-- the direction a door faces, out of the room: the side where the room isn't
-- returns nil when the door isn't in the outer wall, with the floor of the room on one side and the outside on the other
function world.doorDirection(tiles, x, z)
    for _,d in ipairs(directions) do
        local outside, inside = tiles:tile(x + d[1], z + d[2]), tiles:tile(x - d[1], z - d[2])
        if outside and outside.material.walkable and not outside.material.inside and not outside.material.door
            and inside and inside.material.inside then
            return d
        end
    end
end

-- a level's text turned a quarter turn clockwise `turns` times, after mirroring it left to right if mirror is true
function world.transform(text, turns, mirror)
    local rows = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line:find("%S") then rows[#rows+1] = line end
    end
    local width = 0
    for _,row in ipairs(rows) do width = math.max(width, #row) end
    local cells = {}
    for r,row in ipairs(rows) do
        cells[r] = {}
        for c = 1, width do
            local ch = row:sub(c, c)
            cells[r][mirror and width - c + 1 or c] = ch == "" and " " or ch
        end
    end
    for _ = 1, turns do
        local h, w, turned = #cells, #cells[1], {}
        for r = 1, w do
            turned[r] = {}
            for c = 1, h do turned[r][c] = cells[h - c + 1][r] end
        end
        cells = turned
    end
    local lines = {}
    for r,row in ipairs(cells) do lines[r] = table.concat(row) end
    return table.concat(lines, "\n")
end

-- the 8 ways a room can lie: 4 turns, mirrored or not, each with its doors and the cells it takes up:
-- its walls, its floor and its doors, but not the grass around it
local function variants(level)
    local list = {}
    for i = 0, 7 do
        local text = world.transform(level.text, i % 4, i >= 4)
        local parsed = sokoban.parse(text, level.name)
        local tiles = grid.new(parsed)
        local v = {level = parsed, tiles = tiles, exits = {}, entries = {}, cells = {}}
        for _,kind in ipairs{"exits", "entries"} do
            for _,pos in ipairs(tiles[kind]) do
                local dir = world.doorDirection(tiles, pos[1], pos[2])
                assert(dir, ("%s: a door isn't in the outer wall"):format(level.name))
                v[kind][#v[kind]+1] = {pos = pos, dir = dir}
            end
        end
        for x = tiles.minX, tiles.maxX do
            for z = tiles.minZ, tiles.maxZ do
                local tile = tiles:tile(x, z)
                local m = tile.material
                local kind = m.door and "door" or m.inside and "floor" or (not m.walkable and not m.tree) and "wall"
                if kind then v.cells[#v.cells+1] = {x, z, kind, tile} end
            end
        end
        local cx, cz = 0, 0
        for _,c in ipairs(v.cells) do cx, cz = cx + c[1], cz + c[2] end
        v.centre = {cx/#v.cells, cz/#v.cells}
        list[#list+1] = v
    end
    return list
end

local function key(x, z) return (x + 30000)*65536 + (z + 30000) end

-- every order of the numbers 1 to n
local function permutations(n)
    if n == 0 then return {{}} end
    local result = {}
    for _,p in ipairs(permutations(n - 1)) do
        for i = 1, n do
            local q = {unpack(p)}
            table.insert(q, i, n)
            result[#result+1] = q
        end
    end
    return result
end

----------------------------------------------------------------------------------------------------
-- the castle being built: what every cell is, and which cells must stay empty because a door opens onto them
----------------------------------------------------------------------------------------------------

local Castle = {}
Castle.__index = Castle

local function newCastle()
    return setmetatable({cells = {}, reserved = {}, log = {}}, Castle)
end

function Castle:get(x, z) return self.cells[key(x, z)] end

-- every change is logged, so a room that was tried and didn't work out can be taken away again
function Castle:set(x, z, cell)
    local k = key(x, z)
    self.log[#self.log+1] = {self.cells, k, self.cells[k]}
    self.cells[k] = cell
end

function Castle:reserve(x, z, value)
    local k = key(x, z)
    self.log[#self.log+1] = {self.reserved, k, self.reserved[k]}
    self.reserved[k] = value
end

-- keeps the space in front of a door free (value true) or not any more (nil): two tiles straight out, and the
-- tiles beside the second one, so there's room for what it leads to
function Castle:reserveDoor(door, value)
    local d = door.dir
    local x1, z1 = door.pos[1] + d[1], door.pos[2] + d[2]
    local x2, z2 = x1 + d[1], z1 + d[2]
    for _,c in ipairs{{x1, z1}, {x2, z2}, {x2 - d[2], z2 + d[1]}, {x2 + d[2], z2 - d[1]}} do
        self:reserve(c[1], c[2], value)
    end
end

function Castle:mark() return #self.log end

function Castle:rollback(mark)
    for i = #self.log, mark + 1, -1 do
        local entry = self.log[i]
        entry[1][entry[2]] = entry[3]
        self.log[i] = nil
    end
end

local function isFloor(cell) return cell and cell.kind ~= "wall" end

-- walls around cells, wherever there is nothing yet
function Castle:wallAround(list)
    for _,c in ipairs(list) do
        for _,d in ipairs(around8) do
            local x, z = c[1] + d[1], c[2] + d[2]
            if not self:get(x, z) and not self.reserved[key(x, z)] then
                self:set(x, z, {kind = "wall", material = world.wallMaterial, height = wallHeight})
            end
        end
    end
end

-- whether a corridor can go through a cell: empty, no door opens onto it, and no floor next to it but the doors
-- in allowed
function Castle:corridorFree(x, z, allowed)
    if self:get(x, z) or self.reserved[key(x, z)] then return false end
    for _,d in ipairs(around8) do
        local nx, nz = x + d[1], z + d[2]
        local nk = key(nx, nz)
        -- nor right next to a cell a door opens onto, or that would open the corridor up to it
        if self.reserved[nk] and not allowed[nk] then return false end
        if d[1] == 0 or d[2] == 0 then
            if isFloor(self:get(nx, nz)) and not allowed[nk] then return false end
        end
    end
    return true
end

-- the shortest corridor from cell `from` to cell `to`, both just outside a door, as a list of cells, or nil
-- a breadth first search in a box around both ends; when there are several shortest ways, it keeps going straight
function Castle:findCorridor(from, to, fromDoor, toDoor)
    local allowed = {[key(fromDoor[1], fromDoor[2])] = true, [key(toDoor[1], toDoor[2])] = true}
    local margin = 12
    local minX, maxX = math.min(from[1], to[1]) - margin, math.max(from[1], to[1]) + margin
    local minZ, maxZ = math.min(from[2], to[2]) - margin, math.max(from[2], to[2]) + margin
    local function ok(x, z)
        if x < minX or x > maxX or z < minZ or z > maxZ then return false end
        return self:corridorFree(x, z, allowed)
    end
    if not ok(from[1], from[2]) or not ok(to[1], to[2]) then return nil end
    local dist = {[key(to[1], to[2])] = 1}
    local queue, head = {to}, 1
    local fromKey = key(from[1], from[2])
    while head <= #queue and not dist[fromKey] do
        local cell = queue[head]
        head = head + 1
        for _,d in ipairs(directions) do
            local x, z = cell[1] + d[1], cell[2] + d[2]
            if not dist[key(x, z)] and ok(x, z) then
                dist[key(x, z)] = dist[key(cell[1], cell[2])] + 1
                queue[#queue+1] = {x, z}
            end
        end
    end
    if not dist[fromKey] then return nil end
    local path = {from}
    local x, z, last = from[1], from[2], nil
    while not (x == to[1] and z == to[2]) do
        local best
        for _,d in ipairs(directions) do
            local n = dist[key(x + d[1], z + d[2])]
            if n and n == dist[key(x, z)] - 1 then
                if not best or (last and d == last) then best = d end
            end
        end
        x, z, last = x + best[1], z + best[2], best
        path[#path+1] = {x, z}
    end
    return path
end

-- lays a corridor along path, with walls around it
function Castle:layCorridor(path)
    for _,c in ipairs(path) do
        self:set(c[1], c[2], {kind = "corridor", material = world.corridorMaterial, height = floorHeight})
    end
    self:wallAround(path)
end

----------------------------------------------------------------------------------------------------
-- placing the rooms
----------------------------------------------------------------------------------------------------

-- the direction from one point to another, one unit long
local function towards(a, b)
    local dx, dz = b[1] - a[1], b[2] - a[2]
    local length = math.sqrt(dx*dx + dz*dz)
    if length == 0 then return {0, 0} end
    return {dx/length, dz/length}
end

-- whether a room (variant v at offset ox, oz) fits into the castle: its walls may go on walls that are there already,
-- nothing else may overlap, except sharedDoor, the doorway it shares with the room before; freeDoors are its doors that
-- aren't joined up yet, which need nothing in front of them
local function fits(castle, v, ox, oz, sharedDoor, freeDoors)
    for _,c in ipairs(v.cells) do
        local x, z = c[1] + ox, c[2] + oz
        local existing = castle:get(x, z)
        if sharedDoor and x == sharedDoor[1] and z == sharedDoor[2] then
            -- the doorway both rooms have
        elseif existing then
            if not (existing.kind == "wall" and c[3] == "wall") then return false end
        elseif castle.reserved[key(x, z)] then
            return false
        end
    end
    for _,door in ipairs(freeDoors) do
        for k = 1, 2 do
            local x, z = door.pos[1] + ox + door.dir[1]*k, door.pos[2] + oz + door.dir[2]*k
            if castle:get(x, z) or castle.reserved[key(x, z)] then return false end
        end
    end
    return true
end

local function stampRoom(castle, j, v, ox, oz, sharedDoor)
    for _,c in ipairs(v.cells) do
        local x, z = c[1] + ox, c[2] + oz
        if not (sharedDoor and x == sharedDoor[1] and z == sharedDoor[2]) then
            local tile = c[4]
            castle:set(x, z, {kind = c[3], material = tile.material, height = tile.height,
                room = c[3] ~= "wall" and j or nil})
        end
    end
end

----------------------------------------------------------------------------------------------------
-- building the world
----------------------------------------------------------------------------------------------------

local function count(text, char)
    local n = 0
    for _ in text:gmatch(char) do n = n + 1 end
    return n
end

-- builds the world from the puzzles in levels (every level with crates)
function world.new(levels)
    local self = setmetatable({tiles = {}, rooms = {}, corridors = {},
        level = {bottom = 1.5, palette = {}}}, world)
    local castle = newCastle()

    local byName, puzzles = {}, {}
    for _,level in ipairs(levels) do
        if #level.crates > 0 then
            puzzles[#puzzles+1] = level
            byName[level.name] = #puzzles
        end
    end

    -- the rooms that lead to each room, in order
    local incoming, finalRoom = {}, nil
    for i = 1, #puzzles do incoming[i] = {} end
    for i,level in ipairs(puzzles) do
        local exits, to = count(level.text, ">"), level.to or {}
        for _,name in ipairs(to) do
            local j = byName[name]
            assert(j, ("%s leads to %s, which isn't a puzzle"):format(level.name, name))
            assert(j > i, ("%s leads to %s, which comes before it: links go to later rooms"):format(level.name, name))
            table.insert(incoming[j], i)
        end
        if i == #puzzles then
            -- the last room: its one way out leads to the island
            assert(#to == 0, level.name .. " is the last room, its way out leads to the island: to = {}")
            assert(exits == 1, level.name .. " is the last room: it needs exactly one way out (>), to the island")
            finalRoom = i
        elseif #to == 0 then
            -- a dead end: the map takes you back, so there's no way out
            assert(exits == 0, level.name .. " leads nowhere, so it's a dead end: it can't have a way out (>)")
        else
            assert(exits == #to, ("%s leads to %d rooms, so it needs %d ways out (>), not %d"):format(
                level.name, #to, #to, exits))
        end
    end

    -- the way out of room i that leads to room j
    local function exitTo(i, j)
        local room = self.rooms[i]
        for k,name in ipairs(room.level.to) do
            if byName[name] == j then return room.exits[k] end
        end
    end

    for j,level in ipairs(puzzles) do
        local entries = count(level.text, "<")
        assert(entries == #incoming[j], ("%d rooms lead to %s, so it needs %d ways in (<), not %d"):format(
            #incoming[j], level.name, #incoming[j], entries))
        assert(j == 1 or #incoming[j] > 0, level.name .. " can't be reached: no room leads to it")
        local list = variants(level)

        -- every way to put the room against the first room that leads to it, best first: sharing a doorway, or at
        -- the end of a short straight corridor
        local options, routedOptions = {}, nil
        if j == 1 then
            options[1] = {v = list[1], ox = 0, oz = 0, entryOrder = {}, corridor = {}, length = 0, score = 0}
        else
            local source = incoming[j][1]
            local exit = exitTo(source, j)
            local wanted = towards(puzzles[source].at or {0, 0}, level.at or {0, 0})
            for _,v in ipairs(list) do
                for _,order in ipairs(permutations(#v.entries)) do
                    local entry = v.entries[order[1]]
                    if entry.dir[1] == -exit.dir[1] and entry.dir[2] == -exit.dir[2] then
                        for length = 0, 6 do
                            local door = {exit.pos[1] + exit.dir[1]*length, exit.pos[2] + exit.dir[2]*length}
                            if length > 0 then door = {door[1] + exit.dir[1], door[2] + exit.dir[2]} end
                            local ox, oz = door[1] - entry.pos[1], door[2] - entry.pos[2]
                            local corridor = {}
                            for k = 1, length do
                                corridor[k] = {exit.pos[1] + exit.dir[1]*k, exit.pos[2] + exit.dir[2]*k}
                            end
                            -- best roughly where the map says the room goes, and with a short corridor or none
                            local centre = {v.centre[1] + ox, v.centre[2] + oz}
                            local d = towards(self.rooms[source].centre, centre)
                            local score = 4*(d[1]*wanted[1] + d[2]*wanted[2]) - length*1.5
                            options[#options+1] = {v = v, ox = ox, oz = oz, entryOrder = order, corridor = corridor,
                                score = score, length = length, n = #options}
                        end
                    end
                end
            end
            table.sort(options, function(a, b)
                if math.abs(a.score - b.score) > 1e-9 then return a.score > b.score end
                return a.n < b.n
            end)
            -- when none of those fit: anywhere near, with a corridor that bends its way there, nearest first
            -- there are thousands of these, so they're only worked out when the ways above don't give enough options
            routedOptions = function()
                local routed = {}
                local front = {exit.pos[1] + exit.dir[1], exit.pos[2] + exit.dir[2]}
                for _,v in ipairs(list) do
                    for _,order in ipairs(permutations(#v.entries)) do
                        local entry = v.entries[order[1]]
                        for dx = -14, 14 do
                            for dz = -14, 14 do
                                -- the cell in front of the way in goes at front + (dx, dz)
                                local tx, tz = front[1] + dx, front[2] + dz
                                local ox, oz = tx - entry.dir[1] - entry.pos[1], tz - entry.dir[2] - entry.pos[2]
                                local centre = {v.centre[1] + ox, v.centre[2] + oz}
                                local d = towards(self.rooms[source].centre, centre)
                                local score = 4*(d[1]*wanted[1] + d[2]*wanted[2]) - (math.abs(dx) + math.abs(dz))*1.5
                                routed[#routed+1] = {v = v, ox = ox, oz = oz, entryOrder = order, corridor = {}, routed = true,
                                    score = score, length = 1, n = #routed}
                            end
                        end
                    end
                end
                -- best score first, and in the order they were made where scores are the same; sorted as plain numbers,
                -- which is much quicker than with a compare function (it adds up on a handheld)
                local keys, byKey = {}, {}
                for i,option in ipairs(routed) do
                    local k = -math.floor(option.score*1e6 + 0.5)*16384 + option.n
                    keys[i], byKey[k] = k, option
                end
                table.sort(keys)
                for i,k in ipairs(keys) do routed[i] = byKey[k] end
                return routed
            end
        end

        -- puts the room in the castle the way option says, with its corridors; returns how good
        -- that is (higher is better: short corridors, and space in front of its doors that aren't joined up yet),
        -- or nil if it doesn't work out; keeps it when commit is true, takes it away again otherwise
        local function attempt(option, commit)
            local mark = castle:mark()
            local v, ox, oz = option.v, option.ox, option.oz
            local fine = true
            local exitDoor = j > 1 and exitTo(incoming[j][1], j) or nil
            -- the cell in front of the way out it is joined to isn't kept free any more
            if exitDoor then castle:reserveDoor(exitDoor, nil) end
            local sharedDoor = exitDoor and option.length == 0 and exitDoor.pos or nil
            -- a straight corridor has to be empty, with no floor next to it but the two doors
            if #option.corridor > 0 then
                local entry = v.entries[option.entryOrder[1]]
                local allowed = {[key(exitDoor.pos[1], exitDoor.pos[2])] = true,
                    [key(entry.pos[1] + ox, entry.pos[2] + oz)] = true}
                for _,c in ipairs(option.corridor) do
                    if not castle:corridorFree(c[1], c[2], allowed) then fine = false end
                end
            end
            local freeDoors = {}
            for _,door in ipairs(v.exits) do freeDoors[#freeDoors+1] = door end
            for n = 2, #v.entries do freeDoors[#freeDoors+1] = v.entries[option.entryOrder[n]] end
            if fine and fits(castle, v, ox, oz, sharedDoor, freeDoors) then
                local room = {index = j, name = level.name, level = v.level, tiles = v.tiles, ox = ox, oz = oz,
                    centre = {v.centre[1] + ox, v.centre[2] + oz}, exits = {}, entries = {}}
                room.level.to, room.level.at = level.to, level.at
                for k,door in ipairs(v.exits) do
                    room.exits[k] = {pos = {door.pos[1] + ox, door.pos[2] + oz}, dir = door.dir, room = j}
                end
                for n,k in ipairs(option.entryOrder) do
                    local door = v.entries[k]
                    room.entries[n] = {pos = {door.pos[1] + ox, door.pos[2] + oz}, dir = door.dir, room = j}
                end
                stampRoom(castle, j, v, ox, oz, sharedDoor)
                -- every cell of the room in world coordinates, its walls included (a wall it shares with another room
                -- is in both), and the box around them, which the camera frames (see camera.lua)
                room.cells = {}
                local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
                for _,c in ipairs(v.cells) do
                    local x, z = c[1] + ox, c[2] + oz
                    room.cells[#room.cells+1] = {x, z}
                    minX, maxX, minZ, maxZ = math.min(minX, x), math.max(maxX, x), math.min(minZ, z), math.max(maxZ, z)
                end
                room.box = {minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ}
                local links = {}
                if j > 1 then
                    local corridor = option.corridor
                    if option.routed then
                        local entry = room.entries[1]
                        local from = {exitDoor.pos[1] + exitDoor.dir[1], exitDoor.pos[2] + exitDoor.dir[2]}
                        local to = {entry.pos[1] + entry.dir[1], entry.pos[2] + entry.dir[2]}
                        corridor = castle:findCorridor(from, to, exitDoor.pos, entry.pos)
                        if not corridor then fine = false end
                    end
                    if fine and #corridor > 0 then castle:layCorridor(corridor) end
                    links[1] = {from = incoming[j][1], to = j, exit = exitDoor, entry = room.entries[1],
                        cells = corridor or {}}
                end
                -- every door not joined up yet keeps the cell in front of it free
                for _,door in ipairs(room.exits) do castle:reserveDoor(door, true) end
                for n = 2, #room.entries do castle:reserveDoor(room.entries[n], true) end
                self.rooms[j] = room

                -- the other rooms that lead here, by corridors
                for n = 2, fine and #incoming[j] or 0 do
                    local source = incoming[j][n]
                    local exit, entry = exitTo(source, j), room.entries[n]
                    local from = {exit.pos[1] + exit.dir[1], exit.pos[2] + exit.dir[2]}
                    local to = {entry.pos[1] + entry.dir[1], entry.pos[2] + entry.dir[2]}
                    castle:reserveDoor(exit, nil)
                    castle:reserveDoor(entry, nil)
                    local path = castle:findCorridor(from, to, exit.pos, entry.pos)
                    if not path then fine = false break end
                    castle:layCorridor(path)
                    links[#links+1] = {from = source, to = j, exit = exit, entry = entry, cells = path}
                end
                local quality
                if fine then
                    quality = option.score
                    for _,link in ipairs(links) do quality = quality - 0.4*#link.cells end
                    local doors = {}
                    for _,door in ipairs(room.exits) do doors[#doors+1] = door end
                    for n = 2, #room.entries do if n > #incoming[j] then doors[#doors+1] = room.entries[n] end end
                    for _,door in ipairs(doors) do
                        local cx, cz = door.pos[1] + door.dir[1]*5, door.pos[2] + door.dir[2]*5
                        for dx = -3, 3 do
                            for dz = -3, 3 do
                                if not castle:get(cx + dx, cz + dz) then quality = quality + 0.15 end
                            end
                        end
                    end
                end
                if fine and commit then
                    for _,link in ipairs(links) do
                        link.exit.link, link.entry.link = link, link
                        self.corridors[#self.corridors+1] = link
                    end
                    return quality
                end
                self.rooms[j] = nil
                castle:rollback(mark)
                return quality
            end
            castle:rollback(mark)
        end

        -- the best of the first few ways that work out
        local best, bestQuality, tried = nil, nil, 0
        local function try(list)
            for _,option in ipairs(list) do
                local quality = attempt(option, false)
                if quality then
                    tried = tried + 1
                    if not bestQuality or quality > bestQuality then best, bestQuality = option, quality end
                    if tried >= 30 then return end
                end
            end
        end
        try(options)
        if tried < 30 and routedOptions then try(routedOptions()) end
        local done = best and attempt(best, true)
        assert(done, ("there's no room for %s against the rooms that lead to it"):format(level.name))
    end

    -- the way out of the last room leads off the edge of the castle, to the island
    self.finalExit = self.rooms[finalRoom].exits[1]
    self.island = {self.finalExit.pos[1] + self.finalExit.dir[1]*8, self.finalExit.pos[2] + self.finalExit.dir[2]*8}

    -- one big grid in world coordinates
    local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
    for k,cell in pairs(castle.cells) do
        local x, z = math.floor(k/65536) - 30000, k % 65536 - 30000
        self.tiles[x] = self.tiles[x] or {}
        self.tiles[x][z] = {height = cell.height, material = cell.material, room = cell.room, kind = cell.kind}
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
    end
    self.minX, self.maxX, self.minZ, self.maxZ = minX, maxX, minZ, maxZ
    self.width, self.depth = maxX - minX + 1, maxZ - minZ + 1

    for _,room in ipairs(self.rooms) do
        local tiles = room.tiles
        room.start = {tiles.start[1] + room.ox, tiles.start[2] + room.oz}
        room.crates = {}
        for i,crate in ipairs(room.level.crates) do
            room.crates[i] = {x = crate.x + room.ox, z = crate.z + room.oz}
        end
        room.goals = {}
        for x = tiles.minX, tiles.maxX do
            for z = tiles.minZ, tiles.maxZ do
                if tiles:tile(x, z).material.goal then room.goals[#room.goals+1] = {x + room.ox, z + room.oz} end
            end
        end
    end
    return self
end

-- the room a tile belongs to, or nil in a corridor, in a wall or off the map
function world:roomAt(x, z)
    local tile = self:tile(x, z)
    return tile and tile.room and self.rooms[tile.room]
end

-- the rooms next to a room: the ones its ways out lead to, and the ones that lead to it, each with the link between
-- them ({room =, link =}); a link with cells has a corridor
function world:neighbours(room)
    local list = {}
    for _,link in ipairs(self.corridors) do
        if link.from == room.index then list[#list+1] = {room = self.rooms[link.to], link = link} end
        if link.to == room.index then list[#list+1] = {room = self.rooms[link.from], link = link} end
    end
    return list
end

-- the way out of a room at a world position, or nil
function world.exitAt(room, x, z)
    for _,door in ipairs(room.exits) do
        if door.pos[1] == x and door.pos[2] == z then return door end
    end
end

-- the state of a room that is solved: every crate on a goal
function world.solvedCrates(room)
    local crates = {}
    for i,goal in ipairs(room.goals) do crates[i] = {x = goal[1], z = goal[2]} end
    return crates
end

return world
