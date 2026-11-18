-- the 2D camera: it frames a box of tiles, like the room you're in, as big as it fits at a whole number of screen
-- pixels per pixel of the art, so the pixel art stays sharp
-- the world is drawn with north up: tile x, z has its top left corner at pixel (x*8, -z*8) of the art
--
-- camera.fit is plain Lua, so check.lua can use it without a window

local tiles = require "tiles"

local camera = {
    focus = nil,  -- the point in the middle of the screen, in pixels of the art; eases towards the framing
    scale = 2,    -- screen pixels per pixel of the art
    zoom = 0,     -- added to the scale that frames the box: the mouse wheel and X/Y
    minZoom = -2,
    maxZoom = 4,
}

-- tiles of space kept around the box
camera.margin = 1.5
-- the smallest scale anything is drawn at
camera.minScale = 1
-- a small room isn't blown up any further than this many tiles across and down, so it doesn't get huge on a big screen
camera.minCols, camera.minRows = 18, 14

-- the biggest whole number scale at which the box, with the margin around it, fits a screen of w by h pixels
function camera.fit(box, w, h)
    local S = tiles.size
    local cols = math.max(box.maxX - box.minX + 1 + 2*camera.margin, camera.minCols)
    local rows = math.max(box.maxZ - box.minZ + 1 + 2*camera.margin, camera.minRows)
    local scale = math.floor(math.min(w/(cols*S), h/(rows*S)))
    return math.max(scale, camera.minScale)
end

-- the middle of a box, in pixels of the art
local function middle(box)
    return {(box.minX + box.maxX + 1)/2*tiles.size, (-box.maxZ - box.minZ + 1)/2*tiles.size}
end

-- along one axis: the middle of the box when it fits on the screen, otherwise the point to follow, kept far enough in
-- that the screen doesn't go past the edge of the box (with its margin)
local function settle(centre, follow, lo, hi, half)
    if hi - lo <= 2*half or not follow then return centre end
    return math.max(lo + half, math.min(follow, hi - half))
end

-- frames view.box on a screen of w by h; view.follow is a tile {x, z} to keep in view when the box is too big to fit,
-- like the player when zoomed in
-- cut jumps straight there instead of gliding, like after a jump on the map
function camera.update(dt, view, w, h, cut)
    local box, S = view.box, tiles.size
    local fitted = camera.fit(box, w, h)
    local scale = math.max(fitted + camera.zoom, camera.minScale)

    local target = middle(box)
    local follow = view.follow and {view.follow[1]*S + S/2, -view.follow[2]*S + S/2}
    local m = camera.margin*S
    target[1] = settle(target[1], follow and follow[1], box.minX*S - m, (box.maxX + 1)*S + m, w/scale/2)
    target[2] = settle(target[2], follow and follow[2], -box.maxZ*S - m, (-box.minZ + 1)*S + m, h/scale/2)

    if not camera.focus or cut then
        camera.focus, camera.scale = target, scale
        return
    end
    local k = math.min(dt*8, 1)
    local f = camera.focus
    f[1], f[2] = f[1] + (target[1] - f[1])*k, f[2] + (target[2] - f[2])*k
    -- a smaller scale straight away, so the next room is in view while gliding to it; a bigger one once it's there
    local far = math.abs(target[1] - f[1]) + math.abs(target[2] - f[2])
    if scale < camera.scale or far < S/4 then camera.scale = scale end
end

-- the screen offset of pixel 0, 0 of the art, in whole screen pixels, so every tile lands on the pixel grid
function camera.offset(w, h)
    local s = camera.scale
    return math.floor(w/2 - camera.focus[1]*s + 0.5), math.floor(h/2 - camera.focus[2]*s + 0.5)
end

-- sets up love.graphics to draw in pixels of the art
function camera.apply(w, h)
    local ox, oy = camera.offset(w, h)
    love.graphics.translate(ox, oy)
    love.graphics.scale(camera.scale)
end

-- the screen position of the middle of tile x, z
function camera.toScreen(x, z, w, h)
    local ox, oy = camera.offset(w, h)
    local S, s = tiles.size, camera.scale
    return ox + (x*S + S/2)*s, oy + (-z*S + S/2)*s
end

-- the tile under screen position sx, sy
function camera.toTile(sx, sy, w, h)
    local ox, oy = camera.offset(w, h)
    local S, s = tiles.size, camera.scale
    return math.floor((sx - ox)/s/S), -math.floor((sy - oy)/s/S)
end

function camera.zoomBy(steps)
    camera.zoom = math.max(camera.minZoom, math.min(camera.zoom + steps, camera.maxZoom))
end

return camera
