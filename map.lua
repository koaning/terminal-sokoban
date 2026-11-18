-- the map of the world, like the map screen of a Metroid game: one pixel per tile, north at the top
-- rooms are coloured by how far along they are: not visited yet, visited, solved; doors show whether they are open
-- the same picture is used for the minimap in the corner of the screen and for the level picker (see picker.lua)

local lg = love.graphics

local map = {}
map.__index = map

local colors = {
    wall = {0.86, 0.84, 0.92},
    unvisited = {0.16, 0.15, 0.26},
    visited = {0.34, 0.28, 0.62},
    solved = {0.86, 0.64, 0.18},
    bridge = {0.58, 0.40, 0.22},
    corridor = {0.24, 0.22, 0.34},
    exitOpen = {0.45, 0.95, 1.0},
    exitShut = {0.85, 0.25, 0.25},
    entry = {0.95, 0.95, 0.95},
}
map.colors = colors

-- world is the world from world.lua
function map.new(world)
    local self = setmetatable({world = world}, map)
    self.data = love.image.newImageData(world.width, world.depth)
    self.image = lg.newImage(self.data)
    self.image:setFilter("nearest", "nearest")
    return self
end

-- the pixel of a world tile
function map:pixel(x, z)
    return x - self.world.minX, self.world.maxZ - z
end

-- paints every tile again; visited(room) and isOpen(room) say how far along a room is and whether its ways out are
-- open
function map:refresh(visited, isOpen)
    local world, data = self.world, self.data
    data:mapPixel(function() return 0, 0, 0, 0 end)
    local floors = {}
    for i,room in ipairs(world.rooms) do
        floors[i] = room.solved and colors.solved or visited(room) and colors.visited or colors.unvisited
    end
    for x,column in pairs(world.tiles) do
        for z,tile in pairs(column) do
            local m, color = tile.material, nil
            if m.door == "exit" then
                color = isOpen(world.rooms[tile.room]) and colors.exitOpen or colors.exitShut
            elseif m.door == "entry" then
                color = colors.entry
            elseif tile.kind == "corridor" then
                color = colors.corridor
            elseif tile.kind == "wall" then
                color = colors.wall
            elseif tile.room then
                color = floors[tile.room]
            end
            if color then
                local px, py = self:pixel(x, z)
                data:setPixel(px, py, color[1], color[2], color[3], 1)
            end
        end
    end
    self.image:replacePixels(data)
end

-- draws the map at scale pixels per tile, so that world tile (x, z) is at screen position (sx, sy)
function map:drawAt(x, z, sx, sy, scale)
    local px, py = self:pixel(x, z)
    lg.draw(self.image, sx - (px + 0.5)*scale, sy - (py + 0.5)*scale, 0, scale, scale)
end

-- a blinking dot for the player, with a dark edge so it shows up on every colour
function map.drawPlayer(sx, sy, size, clock)
    local on = math.floor(clock*3) % 2 == 0
    local x, y = math.floor(sx - size/2), math.floor(sy - size/2)
    lg.setColor(0, 0, 0)
    lg.rectangle("fill", x - 1, y - 1, size + 2, size + 2)
    if on then lg.setColor(1, 1, 1) else lg.setColor(0.45, 0.95, 1.0) end
    lg.rectangle("fill", x, y, size, size)
    lg.setColor(1, 1, 1)
end

-- the minimap: a box around the player, the player in the middle
function map:drawMini(bx, by, bw, bh, scale, x, z, clock)
    lg.setScissor(bx, by, bw, bh)
    lg.setColor(1, 1, 1, 0.9)
    self:drawAt(x, z, bx + bw/2, by + bh/2, scale)
    map.drawPlayer(bx + bw/2, by + bh/2, scale + 1, clock)
    lg.setScissor()
end

return map
