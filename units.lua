-- units on a tactics board: pick one to select it, then pick a square next to it to move it there
-- picking is done with the mouse, or with a tile cursor moved by the d-pad / arrow keys
-- every unit is a Player from player.lua, so it walks, hops on ledges and faces the same way; draw2d.lua draws them,
-- each as a different character

local Player = require "player"
local camera = require "camera"

local lg = love.graphics

local Units = {}
Units.__index = Units

local directions = {{1,0}, {-1,0}, {0,1}, {0,-1}}

-- starts is a list of {x, z}
function Units.new(tiles, starts)
    local self = setmetatable({tiles = tiles, list = {}}, Units)
    for i,start in ipairs(starts) do
        self.list[i] = Player:new(tiles, start[1], start[2])
    end
    self.cursorX, self.cursorZ = starts[1][1], starts[1][2]
    -- what the camera looks at: the last selected unit, or the cursor when it was moved with the d-pad
    self.cameraTarget = self.list[1].position
    return self
end

-- the unit standing on a tile, or walking onto it
function Units:at(x, z)
    for _,unit in ipairs(self.list) do
        if unit.x == x and unit.z == z then return unit end
    end
end

-- the squares a unit can move to: one step away, reachable, and nobody standing there
function Units:targets(unit)
    local list = {}
    for _,d in ipairs(directions) do
        local x, z = unit.x + d[1], unit.z + d[2]
        if self.tiles:canStep(unit.x, unit.z, x, z) and not self:at(x, z) then
            list[#list+1] = {x, z}
        end
    end
    return list
end

function Units:isTarget(x, z)
    if not self.selected then return false end
    for _,t in ipairs(self:targets(self.selected)) do
        if t[1] == x and t[2] == z then return true end
    end
    return false
end

function Units:select(unit)
    self.selected = unit
    if unit then self.cameraTarget = unit.position end
end

-- put the cursor on a tile, without moving the camera, like when the mouse moves over it
function Units:setCursor(x, z)
    if self.tiles:tile(x, z) then self.cursorX, self.cursorZ = x, z end
end

-- move the cursor one tile, the camera follows it so it never goes off screen
function Units:moveCursor(dx, dz)
    local x, z = self.cursorX + dx, self.cursorZ + dz
    if not self.tiles:tile(x, z) then return end
    self.cursorX, self.cursorZ = x, z
    self.cameraTarget = {x, self.tiles:height(x, z), z}
end

-- pick a tile (and the unit on it, if given): selects a unit, or moves the selected unit there
function Units:pick(x, z, unit)
    unit = unit or self:at(x, z)
    if unit then
        self:select(unit ~= self.selected and unit or nil)
    elseif self:isTarget(x, z) then
        self:moveSelected(x - self.selected.x, z - self.selected.z)
    else
        self:select(nil)
    end
end

-- pick the tile under the cursor
function Units:confirm()
    self:pick(self.cursorX, self.cursorZ)
end

-- move the selected unit one square, ignored while it is still walking or when the square is not free
function Units:moveSelected(dx, dz)
    local unit = self.selected
    if not unit or unit:isWalking() then return false end
    unit:face(dx, dz)
    local x, z = unit.x + dx, unit.z + dz
    if not self:isTarget(x, z) then return false end
    unit:walkTo(x, z)
    return true
end

-- handle a click at window pixel mx, my, left button selects and moves, right button deselects
function Units:click(mx, my, button)
    if button ~= 1 then
        self:select(nil)
        return
    end
    local x, z = camera.toTile(mx, my, lg.getDimensions())
    if not self.tiles:tile(x, z) then
        self:select(nil)
        return
    end
    self:setCursor(x, z)
    self:pick(x, z)
end

function Units:update(dt)
    for _,unit in ipairs(self.list) do unit:update(dt) end
end

return Units
