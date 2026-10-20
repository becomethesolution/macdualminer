#!/usr/bin/env python3
"""Draws Resources/AppIcon.png (1024x1024): a split chip – CPU half / GPU half – with a coin."""
import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# macOS squircle-ish background with vertical gradient
bg = Image.new("RGBA", (S, S))
d = ImageDraw.Draw(bg)
for y in range(S):
    t = y / S
    c = (int(22 + 18 * t), int(26 + 10 * t), int(46 + 30 * t), 255)
    d.line([(0, y), (S, y)], fill=c)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([100, 100, S - 100, S - 100], radius=185, fill=255)
img.paste(bg, (0, 0), mask)

d = ImageDraw.Draw(img)
# chip body
cx0, cy0, cx1, cy1 = 300, 300, 724, 724
pin = (120, 130, 150, 255)
for i in range(6):
    p = cx0 + 40 + i * 64
    for (x0, y0, x1, y1) in [(p, cy0 - 50, p + 26, cy0), (p, cy1, p + 26, cy1 + 50),
                             (cx0 - 50, p, cx0, p + 26), (cx1, p, cx1 + 50, p + 26)]:
        d.rounded_rectangle([x0, y0, x1, y1], radius=6, fill=pin)
d.rounded_rectangle([cx0, cy0, cx1, cy1], radius=48, fill=(46, 52, 72, 255), outline=(150, 160, 190, 255), width=8)
# left half (CPU, orange) / right half (GPU, teal)
d.rounded_rectangle([cx0 + 40, cy0 + 40, 506, cy1 - 40], radius=26, fill=(242, 104, 34, 255))   # Monero orange
d.rounded_rectangle([518, cy0 + 40, cx1 - 40, cy1 - 40], radius=26, fill=(56, 120, 230, 255))   # Ravencoin blue
# coin
coin = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cd = ImageDraw.Draw(coin)
cd.ellipse([600, 600, 860, 860], fill=(0, 0, 0, 120))
coin = coin.filter(ImageFilter.GaussianBlur(14))
img.alpha_composite(coin)
d = ImageDraw.Draw(img)
d.ellipse([590, 585, 850, 845], fill=(250, 196, 54, 255), outline=(200, 140, 20, 255), width=10)
d.ellipse([635, 630, 805, 800], outline=(205, 145, 25, 255), width=8)
# "$" drawn with strokes so no font is needed
d.line([(720, 650), (720, 780)], fill=(150, 95, 10, 255), width=14)
d.arc([672, 660, 768, 718], start=150, end=360, fill=(150, 95, 10, 255), width=14)
d.arc([672, 712, 768, 770], start=-30, end=180, fill=(150, 95, 10, 255), width=14)
d.line([(679, 700), (761, 732)], fill=(150, 95, 10, 255), width=14)
img.save(out)
print("wrote", out)
