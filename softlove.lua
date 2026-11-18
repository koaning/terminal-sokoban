-- just enough of LÖVE, in plain LuaJIT, to run the whole game (main.lua) without a window: image data that reads
-- PNG files, a software renderer that draws into a pixel buffer (images, sprite batches, rectangles, text), the save
-- folder, and the keyboard and the mouse as the host says they are; term.lua is the host, it runs the game in a
-- terminal and shows the pixels there
--
-- only what the game uses is here; anything else stops with an error that names it, so it's clear what to add
-- text is drawn with a bitmap of DejaVu Sans (assets/term-font.png, made by tools/make_term_font.py), the font LÖVE
-- 11's default font grew into, at the sizes the game uses

local ffi = require "ffi"

ffi.cdef[[
unsigned long compressBound(unsigned long sourceLen);
int compress2(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen, int level);
int uncompress(uint8_t *dest, unsigned long *destLen, const uint8_t *source, unsigned long sourceLen);
unsigned long crc32(unsigned long crc, const uint8_t *buf, unsigned int len);
]]

local function loadZlib()
    for _,name in ipairs{"z", "libz.so.1", "libz.so", "libz.1.dylib"} do
        local ok, lib = pcall(ffi.load, name)
        if ok then return lib end
    end
    error("softlove needs zlib (libz), which wasn't found")
end
local zlib = loadZlib()

local softlove = {}

local floor, min, max, sqrt = math.floor, math.min, math.max, math.sqrt

-- zlib-compresses a string, or a buffer of size bytes
function softlove.compress(data, size, level)
    size = size or #data
    local bound = zlib.compressBound(size)
    local out = ffi.new("uint8_t[?]", bound)
    local outLen = ffi.new("unsigned long[1]", bound)
    assert(zlib.compress2(out, outLen, ffi.cast("const uint8_t *", data), size, level or 6) == 0, "zlib compress failed")
    return ffi.string(out, outLen[0])
end

----------------------------------------------------------------------------------------------------
-- PNG files: reading (8-bit, any colour type, not interlaced) and writing (RGB)
----------------------------------------------------------------------------------------------------

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a*256 + b)*256 + c)*256 + d
end

local function be32(n)
    return string.char(floor(n/16777216) % 256, floor(n/65536) % 256, floor(n/256) % 256, n % 256)
end

-- returns width, height and the pixels as a uint8_t buffer of RGBA
function softlove.readPNG(path)
    local file = assert(io.open(path, "rb"))
    local s = file:read("*a")
    file:close()
    assert(s:sub(1, 8) == "\137PNG\r\n\26\n", path .. " isn't a PNG file")
    local i, idat = 9, {}
    local width, height, depth, colorType, interlace, palette, trns
    while i <= #s do
        local length, kind = u32(s, i), s:sub(i + 4, i + 7)
        local body = s:sub(i + 8, i + 7 + length)
        if kind == "IHDR" then
            width, height = u32(body, 1), u32(body, 5)
            depth, colorType, interlace = body:byte(9), body:byte(10), body:byte(13)
        elseif kind == "PLTE" then
            palette = body
        elseif kind == "tRNS" then
            trns = body
        elseif kind == "IDAT" then
            idat[#idat+1] = body
        end
        i = i + 12 + length
    end
    assert(depth == 8 and interlace == 0, path .. ": only 8-bit PNG files without interlacing can be read")
    local channels = ({[0] = 1, [2] = 3, [3] = 1, [4] = 2, [6] = 4})[colorType]
    local stride = width*channels
    local compressed = table.concat(idat)
    local rawLen = height*(stride + 1)
    local raw = ffi.new("uint8_t[?]", rawLen)
    local len = ffi.new("unsigned long[1]", rawLen)
    assert(zlib.uncompress(raw, len, compressed, #compressed) == 0, path .. ": couldn't decompress")

    -- undo the filters, row by row
    local rows = ffi.new("uint8_t[?]", height*stride)
    for y = 0, height - 1 do
        local filter = raw[y*(stride + 1)]
        local src, row, prev = y*(stride + 1) + 1, y*stride, (y - 1)*stride
        for x = 0, stride - 1 do
            local v = raw[src + x]
            local a = x >= channels and rows[row + x - channels] or 0
            local b = y > 0 and rows[prev + x] or 0
            local c = (x >= channels and y > 0) and rows[prev + x - channels] or 0
            if filter == 1 then v = v + a
            elseif filter == 2 then v = v + b
            elseif filter == 3 then v = v + floor((a + b)/2)
            elseif filter == 4 then
                local p = a + b - c
                local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
                v = v + ((pa <= pb and pa <= pc) and a or (pb <= pc) and b or c)
            end
            rows[row + x] = v % 256
        end
    end

    local pixels = ffi.new("uint8_t[?]", width*height*4)
    for p = 0, width*height - 1 do
        local r, g, b, a
        if colorType == 3 then
            local index = rows[p]
            r, g, b = palette:byte(index*3 + 1, index*3 + 3)
            a = trns and trns:byte(index + 1) or 255
        elseif colorType == 0 then
            r = rows[p]; g, b, a = r, r, 255
        elseif colorType == 4 then
            r = rows[p*2]; g, b, a = r, r, rows[p*2 + 1]
        elseif colorType == 2 then
            r, g, b, a = rows[p*3], rows[p*3 + 1], rows[p*3 + 2], 255
        else
            r, g, b, a = rows[p*4], rows[p*4 + 1], rows[p*4 + 2], rows[p*4 + 3]
        end
        pixels[p*4], pixels[p*4 + 1], pixels[p*4 + 2], pixels[p*4 + 3] = r, g, b, a
    end
    return width, height, pixels
end

local function chunk(kind, body)
    local crc = zlib.crc32(0, ffi.cast("const uint8_t *", kind .. body), #kind + #body)
    return be32(#body) .. kind .. body .. be32(tonumber(crc))
end

-- writes an RGB buffer (3 bytes a pixel, rows top to bottom) as a PNG file
function softlove.writePNG(path, width, height, rgb)
    local stride = width*3
    local raw = ffi.new("uint8_t[?]", height*(stride + 1))
    for y = 0, height - 1 do
        raw[y*(stride + 1)] = 0
        ffi.copy(raw + y*(stride + 1) + 1, rgb + y*stride, stride)
    end
    local header = be32(width) .. be32(height) .. string.char(8, 2, 0, 0, 0)
    local file = assert(io.open(path, "wb"))
    file:write("\137PNG\r\n\26\n", chunk("IHDR", header),
        chunk("IDAT", softlove.compress(raw, height*(stride + 1), 9)), chunk("IEND", ""))
    file:close()
end

----------------------------------------------------------------------------------------------------
-- image data, like love.image.newImageData: colours are numbers from 0 to 1
----------------------------------------------------------------------------------------------------

local ImageData = {}
ImageData.__index = ImageData

local function newImageData(width, height)
    if type(width) == "string" then
        local w, h, pixels = softlove.readPNG(width)
        return setmetatable({width = w, height = h, pixels = pixels}, ImageData)
    end
    local pixels = ffi.new("uint8_t[?]", width*height*4)
    return setmetatable({width = width, height = height, pixels = pixels}, ImageData)
end

function ImageData:getWidth() return self.width end
function ImageData:getHeight() return self.height end
function ImageData:getDimensions() return self.width, self.height end

function ImageData:getPixel(x, y)
    local p = self.pixels + (y*self.width + x)*4
    return p[0]/255, p[1]/255, p[2]/255, p[3]/255
end

local function byte(v) return max(0, min(255, floor(v*255 + 0.5))) end

function ImageData:setPixel(x, y, r, g, b, a)
    local p = self.pixels + (y*self.width + x)*4
    p[0], p[1], p[2], p[3] = byte(r), byte(g), byte(b), byte(a or 1)
end

function ImageData:mapPixel(fn)
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            self:setPixel(x, y, fn(x, y, self:getPixel(x, y)))
        end
    end
end

function ImageData:paste(source, dx, dy, sx, sy, sw, sh)
    for y = 0, sh - 1 do
        for x = 0, sw - 1 do
            local from = source.pixels + ((sy + y)*source.width + sx + x)*4
            local to = self.pixels + ((dy + y)*self.width + dx + x)*4
            to[0], to[1], to[2], to[3] = from[0], from[1], from[2], from[3]
        end
    end
end

----------------------------------------------------------------------------------------------------
-- the screen: an RGB buffer of floats, the size of the window the game thinks it has
----------------------------------------------------------------------------------------------------

local Canvas = {}
Canvas.__index = Canvas

local function newCanvas(width, height)
    local self = setmetatable({width = width, height = height}, Canvas)
    self.pixels = ffi.new("float[?]", width*height*3)
    return self
end

function Canvas:clear(r, g, b)
    local p = self.pixels
    for i = 0, self.width*self.height - 1 do
        p[i*3], p[i*3 + 1], p[i*3 + 2] = r, g, b
    end
end

-- the screen as bytes, every pixel blown up to a square of scale x scale
function Canvas:toRGB(scale)
    scale = scale or 1
    local w, h = self.width*scale, self.height*scale
    local out = ffi.new("uint8_t[?]", w*h*3)
    local stride = w*3
    local src = self.pixels
    for y = 0, self.height - 1 do
        local row = out + y*scale*stride
        for x = 0, self.width - 1 do
            local p = (y*self.width + x)*3
            local r, g, b = byte(src[p]), byte(src[p + 1]), byte(src[p + 2])
            for k = 0, scale - 1 do
                local q = (x*scale + k)*3
                row[q], row[q + 1], row[q + 2] = r, g, b
            end
        end
        for k = 1, scale - 1 do ffi.copy(row + k*stride, row, stride) end
    end
    return out, w, h
end

----------------------------------------------------------------------------------------------------
-- drawing: everything ends up in fill(), which blends a colour over a box of pixels
----------------------------------------------------------------------------------------------------

local screen -- the canvas being drawn on
local cr, cg, cb, ca = 1, 1, 1, 1 -- the colour
local blendAdd = false
local tx, ty, scale = 0, 0, 1 -- the transform: screen = point*scale + t
local stack = {}
local clipX0, clipY0, clipX1, clipY1 = 0, 0, 0, 0 -- the scissor, or the whole screen
local scissor
local lineWidth = 1
local background = {0, 0, 0}

local function resetClip()
    if scissor then
        clipX0, clipY0 = max(0, scissor[1]), max(0, scissor[2])
        clipX1, clipY1 = min(screen.width, scissor[1] + scissor[3]), min(screen.height, scissor[2] + scissor[4])
    else
        clipX0, clipY0, clipX1, clipY1 = 0, 0, screen.width, screen.height
    end
end

-- blends r, g, b with alpha a over the pixels from x0, y0 up to (not including) x1, y1
local function fill(x0, y0, x1, y1, r, g, b, a)
    if a <= 0 then return end
    if x0 < clipX0 then x0 = clipX0 end
    if y0 < clipY0 then y0 = clipY0 end
    if x1 > clipX1 then x1 = clipX1 end
    if y1 > clipY1 then y1 = clipY1 end
    if x0 >= x1 or y0 >= y1 then return end
    local pixels, w = screen.pixels, screen.width
    if blendAdd then
        for y = y0, y1 - 1 do
            local p = (y*w + x0)*3
            for _ = x0, x1 - 1 do
                pixels[p] = min(1, pixels[p] + r*a)
                pixels[p + 1] = min(1, pixels[p + 1] + g*a)
                pixels[p + 2] = min(1, pixels[p + 2] + b*a)
                p = p + 3
            end
        end
    elseif a >= 1 then
        for y = y0, y1 - 1 do
            local p = (y*w + x0)*3
            for _ = x0, x1 - 1 do
                pixels[p], pixels[p + 1], pixels[p + 2] = r, g, b
                p = p + 3
            end
        end
    else
        local k = 1 - a
        r, g, b = r*a, g*a, b*a
        for y = y0, y1 - 1 do
            local p = (y*w + x0)*3
            for _ = x0, x1 - 1 do
                pixels[p] = pixels[p]*k + r
                pixels[p + 1] = pixels[p + 1]*k + g
                pixels[p + 2] = pixels[p + 2]*k + b
                p = p + 3
            end
        end
    end
end

local function toScreen(x, y)
    return floor(x*scale + tx + 0.5), floor(y*scale + ty + 0.5)
end

-- draws pixels qx, qy, qw, qh of an image (RGBA bytes, imageWidth wide) at x, y, scaled by sx, sy (negative mirrors)
-- tinted by r, g, b, a; coverage = true reads only the red channel, as how much of the pixel is covered (for text)
local function blit(pixels, imageWidth, qx, qy, qw, qh, x, y, sx, sy, r, g, b, a, coverage)
    local s = scale
    local ox, oy = x*s + tx, y*s + ty
    local stepX, stepY = sx*s, sy*s
    -- off the screen: nothing to do
    local left, right = ox, ox + qw*stepX
    if left > right then left, right = right, left end
    local top, bottom = oy, oy + qh*stepY
    if top > bottom then top, bottom = bottom, top end
    if right < clipX0 or left >= clipX1 or bottom < clipY0 or top >= clipY1 then return end
    for v = 0, qh - 1 do
        local y0, y1 = floor(oy + v*stepY + 0.5), floor(oy + (v + 1)*stepY + 0.5)
        if y0 > y1 then y0, y1 = y1, y0 end
        if y1 > clipY0 and y0 < clipY1 then
            local row = pixels + ((qy + v)*imageWidth + qx)*4
            for u = 0, qw - 1 do
                local p = row + u*4
                local alpha = coverage and p[0] or p[3]
                if alpha > 0 then
                    local x0, x1 = floor(ox + u*stepX + 0.5), floor(ox + (u + 1)*stepX + 0.5)
                    if x0 > x1 then x0, x1 = x1, x0 end
                    if coverage then
                        fill(x0, y0, x1, y1, r, g, b, alpha/255*a)
                    else
                        fill(x0, y0, x1, y1, p[0]/255*r, p[1]/255*g, p[2]/255*b, alpha/255*a)
                    end
                end
            end
        end
    end
end

-- the signed distance from the middle of pixel px, py to the edge of a box (cx, cy its middle, hw, hh half its size)
-- with corners rounded by radius: below 0 inside
local function boxDistance(px, py, cx, cy, hw, hh, radius)
    local qx, qy = math.abs(px - cx) - (hw - radius), math.abs(py - cy) - (hh - radius)
    local outside = sqrt(max(qx, 0)^2 + max(qy, 0)^2)
    return outside + min(max(qx, qy), 0) - radius
end

----------------------------------------------------------------------------------------------------
-- the objects: images, quads, sprite batches, fonts
----------------------------------------------------------------------------------------------------

local Image = {}
Image.__index = Image
function Image:setFilter() end
function Image:getDimensions() return self.data.width, self.data.height end
function Image:getWidth() return self.data.width end
function Image:getHeight() return self.data.height end
function Image:replacePixels(data) self.data = data end

local Quad = {}
Quad.__index = Quad
function Quad:setViewport(x, y, w, h) self.x, self.y, self.w, self.h = x, y, w, h end

local SpriteBatch = {}
SpriteBatch.__index = SpriteBatch
function SpriteBatch:setColor(r, g, b, a) self.color = {r, g, b, a or 1} end
function SpriteBatch:add(quad, x, y)
    self.sprites[#self.sprites+1] = {quad = quad, x = x, y = y, color = self.color}
end

local fontData, fontAtlas
local Font = {}
Font.__index = Font

local function newFont(size)
    size = size or 12
    if not fontData then
        fontData = dofile("assets/term-font.lua")
        fontAtlas = newImageData("assets/term-font.png")
    end
    -- the nearest size there is
    local best
    for s in pairs(fontData) do
        if not best or math.abs(s - size) < math.abs(best - size) then best = s end
    end
    local data = fontData[best]
    return setmetatable({size = best, height = data.height, chars = data.chars}, Font)
end

-- the code points of a UTF-8 string
local function codepoints(text)
    local list = {}
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local c = ch:byte(1)
        if c >= 240 then c = (c - 240)*262144 + (ch:byte(2) - 128)*4096 + (ch:byte(3) - 128)*64 + ch:byte(4) - 128
        elseif c >= 224 then c = (c - 224)*4096 + (ch:byte(2) - 128)*64 + ch:byte(3) - 128
        elseif c >= 192 then c = (c - 192)*64 + ch:byte(2) - 128 end
        list[#list+1] = c
    end
    return list
end

function Font:getHeight() return self.height end

function Font:getWidth(text)
    local width = 0
    for _,c in ipairs(codepoints(text)) do
        local glyph = self.chars[c] or self.chars[63]
        width = width + glyph[7]
    end
    return width
end

-- the lines of text wrapped to a width of limit, at spaces, and at line breaks
function Font:getWrap(text, limit)
    local lines, widest = {}, 0
    for paragraph in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            local candidate = line == "" and word or line .. " " .. word
            if line ~= "" and self:getWidth(candidate) > limit then
                lines[#lines+1] = line
                line = word
            else
                line = candidate
            end
        end
        lines[#lines+1] = line
    end
    for _,line in ipairs(lines) do widest = max(widest, self:getWidth(line)) end
    return widest, lines
end

local font

local function drawLine(text, x, y, sx, sy)
    for _,c in ipairs(codepoints(text)) do
        local g = font.chars[c] or font.chars[63]
        if g[3] > 0 and g[4] > 0 then
            blit(fontAtlas.pixels, fontAtlas.width, g[1], g[2], g[3], g[4], x + g[5]*sx, y + g[6]*sy, sx, sy,
                cr, cg, cb, ca, true)
        end
        x = x + g[7]*sx
    end
end

----------------------------------------------------------------------------------------------------
-- love.graphics
----------------------------------------------------------------------------------------------------

local graphics = {}

function graphics.newImage(data)
    if type(data) == "string" then data = newImageData(data) end
    return setmetatable({data = data}, Image)
end
function graphics.newQuad(x, y, w, h) return setmetatable({x = x, y = y, w = w, h = h}, Quad) end
function graphics.newSpriteBatch(image)
    return setmetatable({image = image, sprites = {}, color = {1, 1, 1, 1}}, SpriteBatch)
end
function graphics.newFont(size) return newFont(size) end
function graphics.getFont()
    font = font or newFont(12)
    return font
end
function graphics.setFont(f) font = f end
function graphics.setDefaultFilter() end
function graphics.setLineWidth(w) lineWidth = w end
function graphics.setBackgroundColor(r, g, b)
    if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
    background = {r, g, b}
end
function graphics.getBackgroundColor() return unpack(background) end

function graphics.setScissor(x, y, w, h)
    scissor = x and {floor(x), floor(y), floor(w), floor(h)} or nil
    resetClip()
end

function graphics.setColor(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
    cr, cg, cb, ca = r, g, b, a or 1
end
function graphics.getColor() return cr, cg, cb, ca end
function graphics.setBlendMode(mode) blendAdd = mode == "add" end

function graphics.push() stack[#stack+1] = {tx, ty, scale} end
function graphics.pop() tx, ty, scale = unpack(table.remove(stack)) end
function graphics.origin() tx, ty, scale = 0, 0, 1 end
function graphics.translate(x, y) tx, ty = tx + x*scale, ty + y*scale end
function graphics.scale(s) scale = scale*s end

function graphics.getDimensions() return screen.width, screen.height end
function graphics.getWidth() return screen.width end
function graphics.getHeight() return screen.height end
function graphics.getStats() return {drawcalls = 0} end
function graphics.getRendererInfo() return "softlove", "1", "software", "terminal" end

function graphics.clear(r, g, b)
    if type(r) == "table" then r, g, b = r[1], r[2], r[3] end
    screen:clear(r or 0, g or 0, b or 0)
end

-- lg.draw(batch), lg.draw(image, quad, x, y, r, sx, sy) or lg.draw(image, x, y, r, sx, sy); no rotation
function graphics.draw(drawable, a1, a2, a3, a4, a5, a6)
    local mt = getmetatable(drawable)
    if mt == SpriteBatch then
        local data = drawable.image.data
        for _,sprite in ipairs(drawable.sprites) do
            local q, c = sprite.quad, sprite.color
            blit(data.pixels, data.width, q.x, q.y, q.w, q.h, sprite.x, sprite.y, 1, 1,
                c[1]*cr, c[2]*cg, c[3]*cb, (c[4] or 1)*ca)
        end
    elseif mt == Image then
        local data = drawable.data
        local q, x, y, sx, sy
        if getmetatable(a1) == Quad then
            q, x, y, sx, sy = a1, a2, a3, a5, a6
        else
            q, x, y, sx, sy = {x = 0, y = 0, w = data.width, h = data.height}, a1, a2, a4, a5
        end
        sx = sx or 1
        blit(data.pixels, data.width, q.x, q.y, q.w, q.h, x or 0, y or 0, sx, sy or sx, cr, cg, cb, ca)
    else
        error("softlove can only draw images and sprite batches")
    end
end

function graphics.rectangle(mode, x, y, w, h, rx)
    local x0, y0 = toScreen(x, y)
    local x1, y1 = toScreen(x + w, y + h)
    local radius = (rx or 0)*scale
    if mode == "fill" and radius <= 0 then
        return fill(x0, y0, x1, y1, cr, cg, cb, ca)
    end
    -- rounded, or an outline: pixel by pixel, by how far each one is from the edge
    local lw = lineWidth*scale
    local pad = mode == "line" and math.ceil(lw/2) or 0
    local cx, cy = (x*scale + tx) + w*scale/2, (y*scale + ty) + h*scale/2
    local hw, hh = w*scale/2, h*scale/2
    radius = min(radius, hw, hh)
    for py = y0 - pad, y1 + pad - 1 do
        for px = x0 - pad, x1 + pad - 1 do
            local d = boxDistance(px + 0.5, py + 0.5, cx, cy, hw, hh, radius)
            if (mode == "fill" and d <= 0) or (mode == "line" and math.abs(d) <= lw/2) then
                fill(px, py, px + 1, py + 1, cr, cg, cb, ca)
            end
        end
    end
end

function graphics.print(text, x, y, _, sx, sy)
    font = font or newFont(12)
    sx = sx or 1
    sy = sy or sx
    local i = 0
    for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        drawLine(line, x, y + i*font.height*sy, sx, sy)
        i = i + 1
    end
end

function graphics.printf(text, x, y, limit, align, _, sx, sy)
    font = font or newFont(12)
    sx = sx or 1
    sy = sy or sx
    local _, lines = font:getWrap(text, limit)
    for i,line in ipairs(lines) do
        local width = font:getWidth(line)
        local offset = align == "center" and floor((limit - width)/2) or align == "right" and limit - width or 0
        drawLine(line, x + offset*sx, y + (i - 1)*font.height*sy, sx, sy)
    end
end

----------------------------------------------------------------------------------------------------
-- love itself
----------------------------------------------------------------------------------------------------

-- the save folder: the same one LÖVE uses (conf.lua gives the name), so progress is shared with the LÖVE game
local function saveFolder(identity)
    local home = os.getenv("HOME") or "."
    if jit.os == "OSX" then return home .. "/Library/Application Support/LOVE/" .. identity end
    local data = os.getenv("XDG_DATA_HOME") or home .. "/.local/share"
    return data .. "/love/" .. identity
end

-- any function that isn't here stops with an error that says which one it was
local function strict(name, t)
    return setmetatable(t, {__index = function(_, key)
        error(("softlove doesn't have %s.%s"):format(name, key), 2)
    end})
end

local clockStart
local function now()
    return os.clock() -- replaced by the host with a real clock, see softlove.install
end

-- installs the global love table, with a window of width x height
-- host gives the clock (host.time()), the keys held down (host.isDown(key)), and is told about quitting (host.quit())
function softlove.install(host)
    now = host.time
    clockStart = now()
    local folder = "."
    love = {
        _os = jit.os == "OSX" and "OS X" or jit.os,
        getVersion = function() return 11, 5, 0, "softlove" end,
        graphics = strict("love.graphics", graphics),
        image = strict("love.image", {newImageData = newImageData}),
        joystick = strict("love.joystick", {
            getJoysticks = function() return {} end,
            getJoystickCount = function() return 0 end,
        }),
        keyboard = strict("love.keyboard", {isDown = function(...)
            for _,k in ipairs{...} do
                if host.isDown(k) then return true end
            end
            return false
        end}),
        mouse = strict("love.mouse", {getPosition = function() return host.mouseX or 0, host.mouseY or 0 end}),
        timer = strict("love.timer", {getTime = function() return now() - clockStart end}),
        event = strict("love.event", {push = function(name) if name == "quit" then host.quit() end end}),
        window = strict("love.window", {
            updateMode = function() end,
            getMode = function() return screen.width, screen.height, {} end,
        }),
        filesystem = strict("love.filesystem", {
            getSaveDirectory = function() return folder end,
            getInfo = function(name)
                local file = io.open(folder .. "/" .. name, "r")
                if not file then return nil end
                file:close()
                return {type = "file"}
            end,
            lines = function(name) return io.lines(folder .. "/" .. name) end,
            write = function(name, text)
                os.execute(("mkdir -p '%s'"):format(folder:gsub("'", "'\\''")))
                local file, message = io.open(folder .. "/" .. name, "w")
                if not file then return false, message end
                file:write(text)
                file:close()
                return true
            end,
        }),
    }
    -- conf.lua: the name of the save folder
    local ok, conf = pcall(dofile, "conf.lua")
    if ok and love.conf then
        local t = {window = {}, modules = {}, audio = {}}
        love.conf(t)
        if t.identity then folder = saveFolder(t.identity) end
    end
    return love
end

-- starts drawing a frame of width x height, cleared to the background colour
function softlove.beginFrame(width, height)
    if not screen or screen.width ~= width or screen.height ~= height then screen = newCanvas(width, height) end
    scissor, stack = nil, {}
    resetClip()
    tx, ty, scale = 0, 0, 1
    cr, cg, cb, ca, blendAdd = 1, 1, 1, 1, false
    screen:clear(background[1], background[2], background[3])
    return screen
end

function softlove.screen() return screen end

return softlove
