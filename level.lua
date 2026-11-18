-- the map, as two ascii grids of the same size
-- the top row is the far side of the map when the game starts, the bottom row is closest to the camera
--
-- heights: one character per tile, 0-9 then a, b, c for 10-12
--          every level is half a unit tall, you can walk up or down one level at a time
--
-- materials: one character per tile, see the materials table below
--            @ is where the player starts, on a path tile

local level = {}

level.heights = {
    "8c8888c8876544444444",
    "88888888876544444444",
    "88888888876544444444",
    "8c8888c8876544444444",
    "66666654444444444444",
    "66666654444444444444",
    "66666654444433444444",
    "22222222222222222222",
    "00000000022000000000",
    "00000000022000000000",
    "22222222222222222222",
    "22222222222222223333",
    "22222222222222234444",
    "22222222222222234554",
    "22222222222222234444",
    "22222222222222223333",
}

level.materials = {
    "sSssssSsssssgggggtgg",
    "ssssssssssssgggggggg",
    "ssssssssssssggtggggg",
    "sSssssSsssssgggggggg",
    "ggtgggsggggggggggtgg",
    "gggggtsggggggggggggg",
    "ggggggsgggggssgggggg",
    "gggggggggdddddgggggg",
    "wwwwwwwwwbbwwwwwwwww",
    "wwwwwwwwwbbwwwwwwwww",
    "gggggggggddggggggggg",
    "gtgggggggddggggggggg",
    "ggggggggdddgggggtggg",
    "gggtgggddggggggggggg",
    "gggggggdggggtggggggg",
    "ggggggg@gggggggggggg",
}

-- draw2d.lua draws a tile by its letter: grass with a tree on it, water with a bridge over it, and so on
-- top, side, sideTop and thickness are left over from the 3D version of the game
level.palette = {
    g = {top = "grass", side = "dirt", sideTop = "grassSide", walkable = true},
    t = {top = "grass", side = "dirt", sideTop = "grassSide", walkable = false, tree = true},
    d = {top = "path", side = "dirt", walkable = true},
    ["@"] = {top = "path", side = "dirt", walkable = true, start = true},
    s = {top = "stone", side = "brick", walkable = true},
    S = {top = "stone", side = "brick", walkable = false}, -- pillar
    w = {top = "water", side = "water", walkable = false, sink = 0.2},
    b = {top = "wood", side = "wood", walkable = true, thickness = 0.25, water = true}, -- bridge, with water under it
}

-- where the units start, as {x, z}: x counts from the left, z from the bottom row
-- the first one is the @ tile
level.units = {{7, 0}, {4, 0}, {10, 1}}

-- how far below height 0 the floating island ends
level.bottom = 1.5

return level
