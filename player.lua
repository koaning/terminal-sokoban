-- the player, walking from tile to tile on a grid
-- this only animates the player, the game decides where it is allowed to go, and draw2d.lua draws it: a hop on every
-- step, a bigger one up or down a ledge, and a lean into a crate that is being pushed

local Player = {}
Player.__index = Player

Player.stepTime = 0.16  -- seconds it takes to walk one tile
local bumpTime = 0.25 -- how long the player strains against a crate that won't move

function Player:new(grid, x, z)
    local self = setmetatable({}, Player)
    self.grid = grid
    self.x, self.z = x, z
    self.fromX, self.fromZ = x, z
    self.progress = 1
    self.steps = 0 -- how many steps it took, so the legs can take turns
    -- where it is drawn, x and z, while walking somewhere between two tiles (y is unused in 2D)
    self.position = {x, 0, z}
    self.facingX, self.facingZ = 0, -1 -- start out looking down, at you
    self.time = 0
    self.push, self.pushHold, self.bumpLeft = 0, 0, 0
    return self
end

function Player:face(dx, dz)
    self.facingX, self.facingZ = dx, dz
end

-- start walking to a neighbouring tile, pushing a crate along if pushing is true
function Player:walkTo(x, z, pushing)
    self.fromX, self.fromZ = self.x, self.z
    self.x, self.z = x, z
    self.progress = 0
    self.steps = self.steps + 1
    -- keep the push pose a moment after the step, so holding the key keeps pushing without dropping the arms
    self.pushHold = pushing and Player.stepTime + 0.1 or 0
end

-- strain against a crate that won't budge, a short lean in
function Player:bump()
    if self.bumpLeft <= 0 then self.bumpLeft = bumpTime end
end

-- jump straight to a tile without walking, like when undoing a move
function Player:placeAt(x, z)
    self.x, self.z = x, z
    self.fromX, self.fromZ = x, z
    self.progress = 1
    self.push, self.pushHold, self.bumpLeft = 0, 0, 0
end

function Player:isWalking()
    return self.progress < 1
end

function Player:update(dt)
    self.time = self.time + dt
    if self.progress < 1 then
        self.progress = math.min(self.progress + dt/Player.stepTime, 1)
    end

    local t = self.progress
    self.position[1] = self.fromX + (self.x - self.fromX)*t
    self.position[3] = self.fromZ + (self.z - self.fromZ)*t

    -- ease in and out of the push pose
    self.pushHold = self.pushHold - dt
    self.bumpLeft = math.max(self.bumpLeft - dt, 0)
    local pushTarget = self.pushHold > 0 and 1 or 0
    if self.bumpLeft > 0 then
        pushTarget = math.max(pushTarget, math.sin(math.pi*(1 - self.bumpLeft/bumpTime))*0.8)
    end
    self.push = self.push + (pushTarget - self.push)*math.min(dt*30, 1)
end

return Player
