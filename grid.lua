-- the walkable tile grid, read from the ascii map in level.lua
-- tiles are 1x1 and centred on whole numbers: x goes left to right, z goes from the bottom row to the top row

local grid = {}
grid.__index = grid

-- how tall one height level is
grid.levelHeight = 0.5

function grid.new(level)
    local self = setmetatable({level = level, tiles = {}, trees = {}, exits = {}, entries = {}}, grid)
    self.width, self.depth = #level.heights[1], #level.heights
    self.minX, self.maxX = 0, self.width - 1
    self.minZ, self.maxZ = 0, self.depth - 1

    assert(#level.materials == self.depth, "level.heights and level.materials need the same number of rows")
    for row = 1, self.depth do
        local heights, materials = level.heights[row], level.materials[row]
        assert(#heights == self.width and #materials == self.width, "row " .. row .. " of the level has the wrong length")
        local z = self.depth - row
        for col = 1, self.width do
            local x = col - 1
            local height = tonumber(heights:sub(col, col), 36)
            local material = level.palette[materials:sub(col, col)]
            assert(height and material, ("unknown tile at row %d, column %d"):format(row, col))

            self.tiles[x] = self.tiles[x] or {}
            self.tiles[x][z] = {height = height, material = material}
            if material.tree then self.trees[#self.trees+1] = {x, z} end
            if material.start then self.start = {x, z} end
            -- the ways out of a puzzle room, and the ways in
            if material.door == "exit" then self.exits[#self.exits+1] = {x, z} end
            if material.door == "entry" then self.entries[#self.entries+1] = {x, z} end
        end
    end
    assert(self.start, "the level needs a start tile")

    return self
end

function grid:tile(x, z)
    return self.tiles[x] and self.tiles[x][z]
end

-- the y position of the surface of a tile, or nil if the tile is outside the map
function grid:height(x, z)
    local tile = self:tile(x, z)
    return tile and -tile.height*grid.levelHeight + (tile.material.sink or 0)
end

function grid:canStep(fromX, fromZ, toX, toZ)
    local from, to = self:tile(fromX, fromZ), self:tile(toX, toZ)
    return from and to and to.material.walkable and math.abs(from.height - to.height) <= 1 or false
end

-- true when walking between these tiles goes up or down a level
function grid:isStair(fromX, fromZ, toX, toZ)
    local from, to = self:tile(fromX, fromZ), self:tile(toX, toZ)
    return from and to and from.height ~= to.height or false
end

return grid
