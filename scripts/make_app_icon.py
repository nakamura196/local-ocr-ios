#!/usr/bin/env python3
"""Draw the Local OCR app icon (light, dark, tinted) into the AppIcon set.

Design: the same layout as KotenOCR's icon (scan-frame corners in 朱 around one
heavy mincho character, faint letters behind), so the two read as siblings.
They are told apart by the ground (藍 here, washi for KotenOCR), the character
(読 here, 典 there) and the faint letters (several scripts here, kana there).
The macOS app (~/git/toyo/local-ocr) should use the same design.

Requires Google Chrome (headless) and Pillow. Font: Noto Serif JP Black and
Noto Serif from Google Fonts (SIL Open Font License 1.1).

    python3 scripts/make_app_icon.py
"""
import pathlib
import subprocess
import tempfile

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "LocalOCR/Assets.xcassets/AppIcon.appiconset"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
GOOGLE = ('<link href="https://fonts.googleapis.com/css2?family=Noto+Serif+JP:wght@900'
          '&family=Noto+Serif:wght@600&display=block" rel="stylesheet">')
CHAR = "読"


def svg(mode):
    if mode == "light":
        bg = ('<defs><radialGradient id="g" cx="35%" cy="25%" r="95%"><stop offset="0" stop-color="#2f5a8c"/>'
              '<stop offset="1" stop-color="#1b3557"/></radialGradient></defs>'
              '<rect width="1024" height="1024" fill="url(#g)"/>')
        ink, shu, ghost = "#f3ebdc", "#e2603f", 0.10
    elif mode == "dark":
        bg = '<rect width="1024" height="1024" fill="#141a24"/>'
        ink, shu, ghost = "#e9eef6", "#e0684c", 0.10
    else:  # tinted: greyscale; iOS applies the tint colour
        bg = '<rect width="1024" height="1024" fill="#141414"/>'
        ink, shu, ghost = "#e9e9e9", "#e9e9e9", 0
    ghosts = "" if not ghost else f'''<g font-family="'Noto Serif JP','Noto Serif',serif" font-size="150" fill="{ink}" opacity="{ghost}">
<text x="610" y="150">文</text><text x="880" y="140">A</text><text x="30" y="590">字</text>
<text x="870" y="420">g</text><text x="40" y="960">書</text><text x="880" y="960">R</text></g>'''
    corners = f'''<g fill="none" stroke="{shu}" stroke-width="34" stroke-linecap="round" stroke-linejoin="round">
<path d="M190 330 V230 Q190 185 235 185 H335"/><path d="M689 185 H789 Q834 185 834 230 V330"/>
<path d="M190 694 V794 Q190 839 235 839 H335"/><path d="M689 839 H789 Q834 839 834 794 V694"/></g>'''
    text = (f'<text x="512" y="530" text-anchor="middle" dominant-baseline="central" '
            f"font-family=\"'Noto Serif JP',serif\" font-weight=\"900\" font-size=\"430\" fill=\"{ink}\">{CHAR}</text>")
    return f'<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">{bg}{ghosts}{corners}{text}</svg>'


def render(mode, png):
    html = (f'<!doctype html><html><head><meta charset="utf-8">{GOOGLE}<style>html,body{{margin:0;'
            f'width:1024px;height:1024px;overflow:hidden}}svg{{display:block;width:1024px;height:1024px}}'
            f'</style></head><body>{svg(mode)}</body></html>')
    page = png.with_suffix(".html")
    page.write_text(html, encoding="utf-8")
    subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--force-device-scale-factor=1",
                    "--window-size=1024,1024", "--virtual-time-budget=15000", f"--screenshot={png}",
                    page.as_uri()], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for mode in ("light", "dark", "tinted"):
            render(mode, tmp / f"{mode}.png")
        Image.open(tmp / "light.png").convert("RGB").save(OUT / "AppIcon.png", optimize=True)
        Image.open(tmp / "dark.png").convert("RGB").save(OUT / "AppIcon-dark.png", optimize=True)
        Image.open(tmp / "tinted.png").convert("L").convert("RGB").save(OUT / "AppIcon-tinted.png", optimize=True)
    print("icons written to", OUT)


if __name__ == "__main__":
    main()
