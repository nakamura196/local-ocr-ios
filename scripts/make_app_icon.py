#!/usr/bin/env python3
"""Draw the Local OCR app icon (light, dark, tinted) into the AppIcon set.

Design: the 読 seal from LocalOCR/Theme/LOStyle.swift (LOSeal) on 藍 paper.
KotenOCR's icon is cream paper with 朱 brackets and a black 典, so the two
are told apart by the ground colour first, then by the seal shape.

    python3 scripts/make_app_icon.py
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "LocalOCR/Assets.xcassets/AppIcon.appiconset"
FONT = "/System/Library/Fonts/ヒラギノ明朝 ProN.ttc"
W6, W3 = 2, 0  # face indices in the collection
S = 2048       # draw at 2x, then downscale to 1024


def rgb(t):
    return tuple(round(c * 255) for c in t)


# Colours from LOColor
WASHI = rgb((0.953, 0.922, 0.863))
WASHI_DARK = rgb((0.114, 0.102, 0.090))
CARD_DARK = rgb((0.165, 0.149, 0.133))
AI = rgb((0.149, 0.302, 0.502))
AI_DARK = rgb((0.525, 0.671, 0.878))

# Faint background letters: several scripts, because the engines read print in many.
GHOSTS = [("文", 0.13, 0.15, 190, -8), ("A", 0.86, 0.14, 180, 6),
          ("字", 0.86, 0.86, 190, 7), ("g", 0.14, 0.84, 190, -5),
          ("書", 0.08, 0.50, 140, -4), ("R", 0.92, 0.50, 140, 4)]


def ground(top, bottom):
    """Vertical gradient with a soft light from the upper left."""
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([-S * 0.3, -S * 0.3, S * 0.7, S * 0.7], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.18))
    light = Image.new("RGB", (S, S), tuple(min(255, c + 28) for c in top))
    return Image.composite(light, img, glow.point(lambda v: v * 0.55))


def ghosts(img, colour, alpha):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    for ch, x, y, size, rot in GHOSTS:
        f = ImageFont.truetype(FONT, size * 2, index=W3)
        tile = Image.new("RGBA", (size * 3, size * 3), (0, 0, 0, 0))
        ImageDraw.Draw(tile).text((size * 1.5, size * 1.5), ch, font=f, fill=colour + (alpha,), anchor="mm")
        tile = tile.rotate(rot, resample=Image.BICUBIC)
        layer.alpha_composite(tile, (round(x * S - tile.width / 2), round(y * S - tile.height / 2)))
    img.paste(layer, (0, 0), layer)


def seal(fill, ink, shadow_alpha, rim=False):
    """LOSeal: rounded square, thick outer rule, thin inner rule, 読 in W6. Rotated -3 deg."""
    size = round(S * 0.62)
    pad = round(size * 0.2)
    canvas = size + pad * 2
    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = [pad, pad, pad + size, pad + size]
    border = size * 0.06
    if rim:  # washi edge so the 藍 rule does not melt into the 藍 ground
        r = border * 0.7
        d.rounded_rectangle([box[0] - r, box[1] - r, box[2] + r, box[3] + r], radius=size * 0.1 + r, fill=WASHI + (255,))
    d.rounded_rectangle(box, radius=size * 0.1, fill=fill + (255,))
    d.rounded_rectangle(box, radius=size * 0.1, outline=ink + (255,), width=round(border))
    g = border * 1.6
    d.rounded_rectangle([box[0] + g, box[1] + g, box[2] - g, box[3] - g],
                        radius=size * 0.06, outline=ink + (255,), width=round(border * 0.4))
    f = ImageFont.truetype(FONT, round(size * 0.52), index=W6)
    d.text((pad + size / 2, pad + size / 2), "読", font=f, fill=ink + (255,), anchor="mm")
    layer = layer.rotate(3, resample=Image.BICUBIC)  # PIL rotates counter-clockwise; SwiftUI -2 deg is the same sense

    if shadow_alpha:
        sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        sh.putalpha(layer.getchannel("A").point(lambda v: v * shadow_alpha // 255))
        sh = sh.filter(ImageFilter.GaussianBlur(S * 0.02))
        out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        out.alpha_composite(sh, (0, round(S * 0.018)))
        out.alpha_composite(layer)
        layer = out
    return layer


def compose(bg, seal_layer):
    bg = bg.convert("RGBA")
    bg.alpha_composite(seal_layer, ((S - seal_layer.width) // 2, (S - seal_layer.height) // 2))
    return bg.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)

    # Light: 藍 ground, washi seal with 藍 ink (the seal as it appears in the app)
    bg = ground((52, 90, 140), (28, 58, 98))
    ghosts(bg, (210, 222, 240), 22)
    compose(bg, seal(WASHI, AI, 110, rim=True)).save(OUT / "AppIcon.png")

    # Dark: dark washi ground, dark card seal with the lighter 藍
    bg = ground(tuple(c + 6 for c in WASHI_DARK), WASHI_DARK)
    ghosts(bg, (120, 140, 170), 30)
    compose(bg, seal(CARD_DARK, AI_DARK, 0)).save(OUT / "AppIcon-dark.png")

    # Tinted: grayscale; the system colours it by luminance
    bg = ground((22, 22, 22), (10, 10, 10))
    ghosts(bg, (255, 255, 255), 22)
    compose(bg, seal((40, 40, 40), (235, 235, 235), 0)).save(OUT / "AppIcon-tinted.png")

    (OUT.parent / "Contents.json").write_text('{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    (OUT / "Contents.json").write_text(CONTENTS)
    print("wrote", OUT)


CONTENTS = """{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "filename" : "AppIcon-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
      "filename" : "AppIcon-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""

if __name__ == "__main__":
    main()
