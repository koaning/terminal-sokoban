"""Makes the font that softlove.lua draws text with, since it can't read TTF files: every glyph of DejaVu Sans
(the font LÖVE 11's default font, Vera Sans, grew into) at the sizes the game uses, packed into one greyscale PNG,
plus a Lua file with where each glyph is and how wide it is.

    python3 tools/make_term_font.py path/to/DejaVuSans.ttf

writes assets/term-font.png and assets/term-font.lua. Needs Pillow. DejaVu's license is in assets/dejavu-LICENSE.txt.
"""
import sys
from PIL import Image, ImageDraw, ImageFont

SIZES = [12, 14, 18, 30]
CHARS = [chr(c) for c in range(32, 127)] + [chr(c) for c in range(160, 256)] + list("…’‘“”—–•·×")
WIDTH = 1024

ttf = sys.argv[1]
glyphs, rows = {}, []
x = y = row_height = 0
for size in SIZES:
    font = ImageFont.truetype(ttf, size)
    ascent, descent = font.getmetrics()
    glyphs[size] = {"height": ascent + descent, "chars": {}}
    for ch in CHARS:
        advance = round(font.getlength(ch))
        x0, y0, x1, y1 = font.getbbox(ch, anchor="la")
        w, h = max(0, x1 - x0), max(0, y1 - y0)
        if x + w + 1 > WIDTH:
            x, y, row_height = 0, y + row_height + 1, 0
        glyphs[size]["chars"][ord(ch)] = (x, y, w, h, x0, y0, advance, ch)
        x += w + 1
        row_height = max(row_height, h)
height = y + row_height + 1

atlas = Image.new("L", (WIDTH, height), 0)
draw = ImageDraw.Draw(atlas)
for size in SIZES:
    font = ImageFont.truetype(ttf, size)
    for code, (gx, gy, w, h, ox, oy, advance, ch) in glyphs[size]["chars"].items():
        if w and h:
            draw.text((gx - ox, gy - oy), ch, font=font, fill=255, anchor="la")
atlas.save("assets/term-font.png", optimize=True)

with open("assets/term-font.lua", "w") as f:
    f.write("-- made by tools/make_term_font.py from DejaVu Sans, see assets/dejavu-LICENSE.txt\n")
    f.write("-- per size: the line height, and per character (by code point) {x, y, w, h, offsetX, offsetY, advance}\n")
    f.write("-- of its glyph in term-font.png\n")
    f.write("return {\n")
    for size in SIZES:
        f.write("    [%d] = {height = %d, chars = {\n" % (size, glyphs[size]["height"]))
        for code, (gx, gy, w, h, ox, oy, advance, ch) in sorted(glyphs[size]["chars"].items()):
            f.write("        [%d] = {%d, %d, %d, %d, %d, %d, %d},\n" % (code, gx, gy, w, h, ox, oy, advance))
        f.write("    }},\n")
    f.write("}\n")
print("wrote assets/term-font.png (%dx%d) and assets/term-font.lua" % (WIDTH, height))
