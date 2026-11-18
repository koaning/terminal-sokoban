-- sokoban: push every crate onto a goal, which opens the door out of the room, then walk through it
-- this file has the rules and the level reader, without any drawing, so levels can be checked and solved without a window

local sokoban = {}

-- the materials that sokoban levels are built from, in the same format as level.lua
sokoban.palette = {
    g = {top = "grass", side = "dirt", sideTop = "grassSide", walkable = true},
    t = {top = "grass", side = "dirt", sideTop = "grassSide", walkable = false, tree = true},
    -- inside is the floor of the room itself, where the puzzle is played
    d = {top = "path", side = "dirt", walkable = true, inside = true},
    x = {top = "goal", side = "dirt", walkable = true, goal = true, inside = true},
    ["@"] = {top = "path", side = "dirt", walkable = true, start = true, inside = true},
    ["+"] = {top = "goal", side = "dirt", walkable = true, goal = true, start = true, inside = true},
    -- the doors in the outer wall: crates never go through them
    -- the way out only opens once every crate is on a goal, the way in is always open
    [">"] = {top = "teleporter", side = "brick", walkable = true, door = "exit"},
    ["<"] = {top = "path", side = "brick", walkable = true, door = "entry"},
    W = {top = "stone", side = "brick", walkable = false},
}

-- walls are only half a unit tall, so they don't hide the puzzle, they block because they aren't walkable
local floorHeight, wallHeight = "2", "3"

-- reads a level in the usual sokoban text format, plus doors in the outer wall:
--   # wall   $ crate   . goal   * crate on a goal   @ player   + player on a goal   > the way out   < the way in
-- the floor that the player can reach becomes a path, everything outside the walls becomes grass
-- trees only go on the corners of the island, anywhere else they would hide part of the puzzle
-- returns a level in the same format as level.lua, plus a list of crate positions
function sokoban.parse(text, name)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line:find("%S") then lines[#lines+1] = line end
    end

    -- one tile of grass around the whole level
    local width, depth = 0, #lines + 2
    for _,line in ipairs(lines) do width = math.max(width, #line + 2) end
    local function charAt(row, col)
        local line = lines[row - 1]
        return line and line:sub(col - 1, col - 1) or " "
    end

    -- find the inside of the level by flood filling from the player
    local startRow, startCol
    for row = 1, depth do
        for col = 1, width do
            local c = charAt(row, col)
            if c == "@" or c == "+" then startRow, startCol = row, col end
        end
    end
    assert(startRow, "level " .. tostring(name) .. " has no player")
    assert(not text:find("^", 1, true), "level " .. tostring(name) .. " has a teleporter (^), puzzles have doors now: > and <")
    -- doors are part of the wall, the flood fill doesn't go through them
    local function isWall(c) return c == "#" or c == ">" or c == "<" end
    local inside = {[startRow .. "," .. startCol] = true}
    local queue = {{startRow, startCol}}
    while #queue > 0 do
        local row, col = unpack(table.remove(queue))
        for _,d in ipairs{{1,0}, {-1,0}, {0,1}, {0,-1}} do
            local r, c = row + d[1], col + d[2]
            if r >= 1 and r <= depth and c >= 1 and c <= width and not inside[r .. "," .. c] and not isWall(charAt(r, c)) then
                inside[r .. "," .. c] = true
                queue[#queue+1] = {r, c}
            end
        end
    end

    local level = {name = name, heights = {}, materials = {}, palette = sokoban.palette, bottom = 1.5, crates = {}}
    for row = 1, depth do
        local heights, materials = {}, {}
        for col = 1, width do
            local c = charAt(row, col)
            local x, z = col - 1, depth - row
            local material
            if c == "#" then
                material = "W"
            elseif c == ">" or c == "<" then
                material = c
            elseif inside[row .. "," .. col] then
                material = (c == "@" or c == "+") and c or (c == "." or c == "*") and "x" or "d"
                if c == "$" or c == "*" then level.crates[#level.crates+1] = {x = x, z = z} end
            else
                local corner = (row == 1 or row == depth) and (col == 1 or col == width)
                material = corner and "t" or "g"
            end
            heights[col] = c == "#" and wallHeight or floorHeight
            materials[col] = material
        end
        level.heights[row] = table.concat(heights)
        level.materials[row] = table.concat(materials)
    end
    return level
end

----------------------------------------------------------------------------------------------------
-- the rules
----------------------------------------------------------------------------------------------------

-- the state of a puzzle is where the player and the crates are
-- the player starts on the start tile, or on start ({x, z}) when given
function sokoban.newState(tiles, crates, start)
    start = start or tiles.start
    local state = {x = start[1], z = start[2], crates = {}}
    for i,crate in ipairs(crates or {}) do
        state.crates[i] = {x = crate.x, z = crate.z}
    end
    return state
end

function sokoban.crateAt(state, x, z)
    for _,crate in ipairs(state.crates) do
        if crate.x == x and crate.z == z then return crate end
    end
end

-- crates slide over flat walkable ground only, they can't be pushed up or down stairs, or through a door
local function crateCanEnter(state, tiles, fromX, fromZ, toX, toZ)
    local from, to = tiles:tile(fromX, fromZ), tiles:tile(toX, toZ)
    return to and to.material.walkable and not to.material.door and to.height == from.height
        and not sokoban.crateAt(state, toX, toZ)
end

-- whether the player can walk onto a tile: anything that isn't a door, or a door that is open
-- a grid can decide that itself with grid:isDoorOpen(tile, state), like the world does (see world.lua)
-- otherwise the way out opens once every crate is on a goal, and the way in stays shut, so the solver stays in the room
function sokoban.doorOpen(state, tiles, x, z)
    local tile = tiles:tile(x, z)
    if not (tile and tile.material.door) then return true end
    if tiles.isDoorOpen then return tiles:isDoorOpen(tile, state) end
    return tile.material.door == "exit" and sokoban.cratesPlaced(state, tiles)
end

-- tries to walk the player one tile, pushing a crate if there's one in the way
-- returns nil if the move isn't possible, otherwise true and the crate that got pushed, if any
function sokoban.move(state, tiles, dx, dz)
    local toX, toZ = state.x + dx, state.z + dz
    local crate = sokoban.crateAt(state, toX, toZ)
    if crate then
        if not crateCanEnter(state, tiles, toX, toZ, toX + dx, toZ + dz) then return nil end
        crate.x, crate.z = toX + dx, toZ + dz
    elseif not tiles:canStep(state.x, state.z, toX, toZ) or not sokoban.doorOpen(state, tiles, toX, toZ) then
        return nil
    end
    state.x, state.z = toX, toZ
    return true, crate
end

function sokoban.isGoal(tiles, x, z)
    local tile = tiles:tile(x, z)
    return tile and tile.material.goal or false
end

-- true when every crate is on a goal, which opens the way out
-- a level without crates isn't a puzzle
function sokoban.cratesPlaced(state, tiles)
    if #state.crates == 0 then return false end
    for _,crate in ipairs(state.crates) do
        if not sokoban.isGoal(tiles, crate.x, crate.z) then return false end
    end
    return true
end

-- solved when every crate is on a goal and the player stands in a way out, if the level has any
function sokoban.isSolved(state, tiles)
    if not sokoban.cratesPlaced(state, tiles) then return false end
    if not tiles.exits or #tiles.exits == 0 then return true end
    local tile = tiles:tile(state.x, state.z)
    return tile.material.door == "exit"
end

-- a copy of just the positions, for undo and for the solver
function sokoban.snapshot(state)
    local copy = {x = state.x, z = state.z, crates = {}}
    for i,crate in ipairs(state.crates) do
        copy.crates[i] = {x = crate.x, z = crate.z}
    end
    return copy
end

-- a string that is the same for two states with the player and the crates in the same places
function sokoban.key(state)
    local crates = {}
    for i,crate in ipairs(state.crates) do crates[i] = crate.x .. "," .. crate.z end
    table.sort(crates)
    return state.x .. "," .. state.z .. "|" .. table.concat(crates, ";")
end

-- the squares a crate can never be pushed out of again: corners that aren't goals
-- a crate can't go onto a neighbour that isn't walkable or isn't at the same height, so those count as walls
local function deadSquares(tiles)
    local dead = {}
    local function blocked(x, z, nx, nz)
        local from, to = tiles:tile(x, z), tiles:tile(nx, nz)
        return not (to and to.material.walkable and not to.material.door and to.height == from.height)
    end
    for x = tiles.minX, tiles.maxX do
        for z = tiles.minZ, tiles.maxZ do
            local tile = tiles:tile(x, z)
            if tile.material.walkable and not tile.material.goal then
                local alongX = blocked(x, z, x - 1, z) or blocked(x, z, x + 1, z)
                local alongZ = blocked(x, z, x, z - 1) or blocked(x, z, x, z + 1)
                if alongX and alongZ then dead[x .. "," .. z] = true end
            end
        end
    end
    return dead
end

-- a breadth first search over where the player and the crates are, for the fewest moves to a state where done(state)
-- is true; it skips pushing a crate into a corner unless keepCorners is true, which is plenty for small levels
-- returns the number of moves, or nil if no state like that can be reached, and how many states it looked at
function sokoban.search(tiles, start, done, maxStates, keepCorners)
    maxStates = maxStates or 2000000
    local dead = keepCorners and {} or deadSquares(tiles)
    local seen = {[sokoban.key(start)] = true}
    local frontier, moves, count = {start}, 0, 1
    while #frontier > 0 do
        local nextFrontier = {}
        for _,state in ipairs(frontier) do
            if done(state) then return moves, count end
            for _,d in ipairs{{1,0}, {-1,0}, {0,1}, {0,-1}} do
                local copy = sokoban.snapshot(state)
                local moved, crate = sokoban.move(copy, tiles, d[1], d[2])
                if moved and not (crate and dead[crate.x .. "," .. crate.z]) then
                    local key = sokoban.key(copy)
                    if not seen[key] then
                        seen[key] = true
                        count = count + 1
                        nextFrontier[#nextFrontier+1] = copy
                        if count > maxStates then return nil, count end
                    end
                end
            end
        end
        frontier = nextFrontier
        moves = moves + 1
    end
    return nil, count
end

-- finds the smallest number of moves that solves a puzzle, or nil if it can't be solved
-- the player starts on the start tile, or on from ({x, z}) when given
function sokoban.solve(tiles, crates, maxStates, from)
    local start = sokoban.newState(tiles, crates, from)
    return sokoban.search(tiles, start, function(state) return sokoban.isSolved(state, tiles) end, maxStates)
end

return sokoban
