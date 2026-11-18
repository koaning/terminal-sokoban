-- the art: Kenney's Micro Roguelike tiles (assets/micro-roguelike.png, CC0, www.kenney.nl), 8x8 pixels each, 16 to a row
-- a tile is named by its index in the sheet, counted from 0 at the top left, row by row
--
-- the sheet has no transparency, the background is one dark colour: it is made see-through when the sheet is loaded,
-- and a coloured square is drawn under every tile instead (the floor, or the mortar under a wall)
--
-- the pack is a dark dungeon in cold greys; when the sheet is loaded its greys are swapped for warm sandstone (see
-- tiles.palette), so the castle looks sunny, the other colours stay as they are
--
-- walls are drawn a quarter at a time, each quarter copied from one of Kenney's thick wall pieces 144-153 depending on
-- the walls next to it (see tiles.wallQuarters), so every wall joins up with its neighbours
--
-- two rows are added below the sheet when it is loaded (see tiles.load); the second has a few tiles of our own, made
-- from the colours of the sheet: the top of a wall, the gates in the doors, the cliff edges of the island, solid white
-- to colour in, the player seen from the back and the side, and a crate
--
-- everything above tiles.load is plain Lua, so check.lua can use it without a window

local tiles = {}

tiles.size = 8
tiles.columns = 16

local function rgb(r, g, b) return {r/255, g/255, b/255} end

-- the background of the sheet, which becomes see-through
tiles.background = rgb(34, 35, 35)

-- the colours swapped when the sheet is loaded: Kenney's cold greys become warm sandstone, lightest first
tiles.palette = {
    {rgb(194, 194, 209), rgb(246, 232, 200)},
    {rgb(126, 126, 143), rgb(204, 168, 120)},
    {rgb(96, 96, 112), rgb(160, 118, 86)},
    {rgb(67, 67, 79), rgb(118, 82, 64)},
}

-- the ring around a goal is drawn darker instead, so it shows on the light floor
local goalPalette = {
    {tiles.palette[1][1], tiles.palette[3][2]},
    {tiles.palette[2][1], tiles.palette[4][2]},
}

-- the colours of the walls, after the swap
local light, mid = tiles.palette[1][2], tiles.palette[2][2]

-- what is drawn under the tiles: the floor of the castle in a faint checkerboard of two sands, and the mortar
-- between the bricks of a wall
tiles.floor = rgb(226, 200, 152)
tiles.floorAlt = rgb(216, 189, 141)
tiles.mortar = rgb(122, 84, 66)

-- the tiles that are used, by name
tiles.units = {4, 7, 15}
tiles.crate = 189       -- a wooden crate of our own, see below: the pack has none
tiles.goal = 128
tiles.arch = 146          -- an open doorway in a wall that runs left to right
tiles.archGate = 152      -- the same doorway with a portcullis in it
tiles.sideDoor = 149      -- an opening in a wall that runs up and down
tiles.speckle = 68        -- a few grey dots, for the corridors and the paths
tiles.sprigs = 69         -- a few blades of grass
tiles.trees = {84, 85, 86}
tiles.pillar = 29
tiles.bridge = 91
tiles.frame = 103         -- a square outline, for the cursor and the highlighted squares on the island
tiles.stone = 61

-- the tiles of our own, see the top of this file
tiles.wallTop = 176       -- the top of a wall and nothing else, for the middle of a thick wall
tiles.gate = 177          -- the portcullis of an archway on its own: archGate without arch
tiles.sideGate = 178      -- a gate seen from above, in a wall that runs up and down
tiles.cliff = 179         -- the face of a ledge, in the top half of the tile below it
tiles.edgeLeft = 180      -- the side of a higher tile to the left
tiles.edgeRight = 181     -- the side of a higher tile to the right
tiles.white = 182         -- solid white, for light and flashes

-- the player, in every direction: Kenney's tile 4 from the front, and from the back and the side (facing right, mirrored
-- for left) redrawn in its three colours; a step frame lifts a leg, and from the side the arms reach out to push
tiles.playerPoses = {
    front = 4, frontStep = 183,
    back = 184, backStep = 185,
    side = 186, sideStep = 187, sidePush = 188,
}

-- the player wears a blue suit: on the tiles of the player, Kenney's red clothes and plum details are swapped for blue
-- (the crate is drawn in the same colours, so this is only done on the player's tiles)
local playerPalette = {
    {rgb(186, 97, 86), rgb(72, 120, 216)},
    {rgb(140, 63, 93), rgb(44, 54, 112)},
}

-- the tiles that get colours of their own instead of tiles.palette
local tilePalettes = {[tiles.goal] = goalPalette}
for _,index in pairs(tiles.playerPoses) do tilePalettes[index] = playerPalette end

-- the tiles we draw ourselves, as text, in the colours of the sheet: the poses of the player, and a crate
-- A skin, B clothes (blue once swapped, see playerPalette) and wood, C dark details, L light wood, . see-through
local pixelColors = {A = {255/255, 181/255, 112/255}, B = {186/255, 97/255, 86/255}, C = {140/255, 63/255, 93/255},
    L = {242/255, 166/255, 94/255}}
local pixelTiles = {
    [183] = {"...AA...", "...AA...", ".BBAABB.", "BBBBBBBB", "B.CBBC.B", "A.BBBB.A", "..C..C..", ".....C.."},
    [184] = {"...CC...", "...CC...", ".BBAABB.", "BBBBBBBB", "B.BBBB.B", "A.BBBB.A", "..C..C..", "..C..C.."},
    [185] = {"...CC...", "...CC...", ".BBAABB.", "BBBBBBBB", "B.BBBB.B", "A.BBBB.A", "..C..C..", ".....C.."},
    [186] = {"...CA...", "...CAA..", "...BAB..", "..BBBB..", "..BCBB..", "..BABB..", "...C.C..", "...C.C.."},
    [187] = {"...CA...", "...CAA..", "...BAB..", "..BBBB..", "..BCBB..", "..BABB..", "..C...C.", "..C...C."},
    [188] = {"...CA...", "...CAA..", "...BAB..", "..BBBBBA", "..BBBB..", "..BBBB..", "..C..C..", ".C....C."},
    -- the crate: planks in a dark frame, braced corner to corner
    [189] = {"CCCCCCCC", "CLBBBBLC", "CBLBBLBC", "CBBLLBBC", "CBBLLBBC", "CBLBBLBC", "CLBBBBLC", "CCCCCCCC"},
}
tiles.pixelTiles = pixelTiles

-- the bits of a mask: which neighbours are walls, the four sides and then the four corners
tiles.N, tiles.E, tiles.S, tiles.W = 1, 2, 4, 8
tiles.NE, tiles.SE, tiles.SW, tiles.NW = 16, 32, 64, 128

local function has(mask, bit) return math.floor(mask/bit) % 2 == 1 end

-- every quarter of a wall tile only depends on the walls on its side: the neighbour beside it, the one above or below
-- it, and the one in its corner; Kenney's thick wall pieces have every case, the quarter is copied from the same
-- quarter of one of them: neither neighbour is a wall, only the one beside it, only the one above or below it, both
-- when both are, the corner decides: if it's a wall too, the quarter is in the middle of a thick wall and is just the
-- top of the wall; otherwise the walls turn around the floor in the corner
local quarterSources = {
    -- {column, row} of the quarter in pixels, the neighbour beside it, above or below it, in its corner, the sources
    {0, 0, tiles.W, tiles.N, tiles.NW, {144, 145, 148, 153}}, -- top left
    {4, 0, tiles.E, tiles.N, tiles.NE, {147, 145, 148, 150}}, -- top right
    {0, 4, tiles.W, tiles.S, tiles.SW, {150, 145, 148, 147}}, -- bottom left
    {4, 4, tiles.E, tiles.S, tiles.SE, {153, 145, 148, 144}}, -- bottom right
}

-- the source tile of each quarter of the wall with this mask, as {tile, x, y} with x, y the corner of the quarter
function tiles.wallQuarters(mask)
    local list = {}
    for i,q in ipairs(quarterSources) do
        local beside, along = has(mask, q[3]), has(mask, q[4])
        local pick = (beside and 1 or 0) + (along and 2 or 0) + 1
        local source = q[6][pick]
        if beside and along and has(mask, q[5]) then source = tiles.wallTop end
        list[i] = {source, q[1], q[2]}
    end
    return list
end

-- the mask of a tile: isWall(dx, dz) says whether the neighbour that way is a wall; north is up on the screen
-- corners adds the four corners
function tiles.mask(isWall, corners)
    local mask = (isWall(0, 1) and tiles.N or 0) + (isWall(1, 0) and tiles.E or 0)
        + (isWall(0, -1) and tiles.S or 0) + (isWall(-1, 0) and tiles.W or 0)
    if corners then
        mask = mask + (isWall(1, 1) and tiles.NE or 0) + (isWall(1, -1) and tiles.SE or 0)
            + (isWall(-1, -1) and tiles.SW or 0) + (isWall(-1, 1) and tiles.NW or 0)
    end
    return mask
end

-- Kenney's pond: the shore follows the sides that aren't water
local water = {
    [0] = 140, -- no shore
    [tiles.N] = 124, [tiles.S] = 156, [tiles.E] = 141, [tiles.W] = 139,
    [tiles.N + tiles.W] = 123, [tiles.N + tiles.E] = 125, [tiles.S + tiles.W] = 155, [tiles.S + tiles.E] = 157,
    [tiles.N + tiles.S] = 108, [tiles.E + tiles.W] = 109,
}

-- shore is the mask of the sides that are land
function tiles.waterIndex(shore)
    return water[shore] or 140
end

-- a number from 0 to 1 that is always the same for a tile, to pick a tree or sprinkle some grass without flickering
function tiles.hash(x, z)
    local n = math.sin(x*12.9898 + z*78.233)*43758.5453
    return n - math.floor(n)
end

----------------------------------------------------------------------------------------------------
-- loading, this part needs LÖVE
----------------------------------------------------------------------------------------------------

local function sameColor(r, g, b, color)
    return math.abs(r - color[1]) < 0.01 and math.abs(g - color[2]) < 0.01 and math.abs(b - color[3]) < 0.01
end

-- the sheet with the two extra rows, and a quad for every tile
function tiles.load()
    local S = tiles.size
    local sheet = love.image.newImageData("assets/micro-roguelike.png")
    local w, h = sheet:getWidth(), sheet:getHeight()
    local data = love.image.newImageData(w, h + 2*S)
    data:paste(sheet, 0, 0, 0, 0, w, h)

    local function corner(index)
        return (index % tiles.columns)*S, math.floor(index/tiles.columns)*S
    end
    local function set(index, x, y, color, alpha)
        local cx, cy = corner(index)
        data:setPixel(cx + x, cy + y, color[1], color[2], color[3], alpha or 1)
    end

    -- solid white, to fill in a tile with any colour, and the top of a wall
    for x = 0, S - 1 do
        for y = 0, S - 1 do
            set(tiles.white, x, y, {1, 1, 1})
            set(tiles.wallTop, x, y, light)
        end
    end

    -- the tiles we draw ourselves
    for index,rows in pairs(pixelTiles) do
        for y,row in ipairs(rows) do
            for x = 1, #row do
                local color = pixelColors[row:sub(x, x)]
                if color then set(index, x - 1, y - 1, color) end
            end
        end
    end

    -- the portcullis: the pixels where the archway with a gate differs from the open one
    local ax, ay = corner(tiles.arch)
    local gx, gy = corner(tiles.archGate)
    for x = 0, S - 1 do
        for y = 0, S - 1 do
            local r, g, b = sheet:getPixel(gx + x, gy + y)
            local r2, g2, b2 = sheet:getPixel(ax + x, ay + y)
            if r ~= r2 or g ~= g2 or b ~= b2 then set(tiles.gate, x, y, {r, g, b}) end
        end
    end

    -- a gate in a wall that runs up and down, seen from above: a bar across the opening
    for y = 0, S - 1 do
        set(tiles.sideGate, 3, y, mid)
        set(tiles.sideGate, 4, y, y % 2 == 0 and light or mid)
    end

    -- the face of a ledge: the bricks under the top of Kenney's wall, moved up into the top half of the tile
    local fx, fy = corner(145)
    local cx, cy = corner(tiles.cliff)
    data:paste(sheet, cx, cy, fx, fy + 4, S, 4)
    -- the sides of a higher tile: the outline and shade of the side of a wall
    for y = 0, S - 1 do
        set(tiles.edgeLeft, 0, y, light)
        set(tiles.edgeLeft, 1, y, mid)
        set(tiles.edgeRight, S - 1, y, light)
        set(tiles.edgeRight, S - 2, y, mid)
    end

    -- the background of the sheet becomes see-through, so tiles can go on top of each other, and the greys become
    -- sandstone, except on the tiles with colours of their own (see tilePalettes); the tiles of our own are drawn in
    -- the colours of the sheet, so they are swapped too
    data:mapPixel(function(x, y, r, g, b, a)
        if sameColor(r, g, b, tiles.background) then return r, g, b, 0 end
        local index = math.floor(y/S)*tiles.columns + math.floor(x/S)
        for _,swap in ipairs(tilePalettes[index] or tiles.palette) do
            local to = swap[2]
            if sameColor(r, g, b, swap[1]) then return to[1], to[2], to[3], a end
        end
        return r, g, b, a
    end)

    tiles.image = love.graphics.newImage(data)
    tiles.image:setFilter("nearest", "nearest")
    tiles.quads = {}
    local iw, ih = data:getWidth(), data:getHeight()
    for index = 0, (iw/S)*(ih/S) - 1 do
        local x, y = corner(index)
        tiles.quads[index] = love.graphics.newQuad(x, y, S, S, iw, ih)
    end
    -- a quad that is moved around, to draw part of a tile (see tiles.drawPart)
    tiles.partQuad = love.graphics.newQuad(0, 0, S, S, iw, ih)
    -- a quad for every quarter of a tile, made when it is first needed (see tiles.quarter)
    tiles.quarters = {}
end

-- the quad of the quarter of a tile with its corner at x, y in the tile (0 or 4)
function tiles.quarter(index, x, y)
    local key = index*16 + x*2 + y/4
    local quad = tiles.quarters[key]
    if not quad then
        local S = tiles.size
        local iw, ih = tiles.image:getDimensions()
        quad = love.graphics.newQuad((index % tiles.columns)*S + x, math.floor(index/tiles.columns)*S + y, S/2, S/2, iw, ih)
        tiles.quarters[key] = quad
    end
    return quad
end

-- draws a tile with its top left corner at x, y (in pixels of the art); flip mirrors it left to right
function tiles.draw(index, x, y, flip)
    if flip then
        love.graphics.draw(tiles.image, tiles.quads[index], x + tiles.size, y, 0, -1, 1)
    else
        love.graphics.draw(tiles.image, tiles.quads[index], x, y)
    end
end

-- draws the top rows of a tile, lowered by drop pixels, so it looks like it sinks into the floor
function tiles.drawSunk(index, x, y, drop)
    local S = tiles.size
    if drop >= S then return end
    local cx, cy = (index % tiles.columns)*S, math.floor(index/tiles.columns)*S
    tiles.partQuad:setViewport(cx, cy, S, S - drop)
    love.graphics.draw(tiles.image, tiles.partQuad, x, y + drop)
end

return tiles
