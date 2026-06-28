#!/usr/bin/env python3
"""Generate Atlas brand assets from the source logo (the titan shouldering the
celestial sphere) into Atlas/Assets.xcassets.

Produces three sets:
  * AppIcon       — warm-dark rounded macOS tile with the orange figure centered
  * AtlasMark     — transparent line-art figure for in-app use (sidebar, sign-in)
  * AtlasMenuBar  — bolded silhouette template for the menu-bar item (reads at 18px)

The near-black background of the source JPEG is knocked out to transparency via an
auto-thresholded max-RGB mask (pure PIL, no numpy).

Usage:  python3 tools/gen_brand_assets.py [path/to/source.jpg]
"""

import os
import sys
import json
from PIL import Image, ImageChops, ImageFilter, ImageDraw, ImageOps

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "Atlas", "Assets.xcassets")
DEFAULT_SRC = os.path.expanduser("~/Downloads/ATLASLM LOGO.jpg")

# Uniform, bright brand orange. The source JPEG's strokes fade to a near-black
# brown toward the legs, which vanishes on the dark tile — so we drop the source
# pixels entirely and refill the figure's shape with this gradient (bright at the
# sphere, still bright at the feet) so the whole figure reads on a dark tile.
BRAND_TOP = "#F4A658"
BRAND_BOT = "#E37D2C"


def hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vgrad(w, h, top_hex, bottom_hex):
    top = Image.new("RGB", (w, h), hex2rgb(top_hex))
    bot = Image.new("RGB", (w, h), hex2rgb(bottom_hex))
    ramp = Image.new("L", (1, h))
    for y in range(h):
        ramp.putpixel((0, y), int(255 * y / max(1, h - 1)))
    return Image.composite(bot, top, ramp.resize((w, h)))


def rounded_mask(w, h, radius, ss=4):
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * ss - 1, h * ss - 1],
                                        radius=radius * ss, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def extract_figure(path):
    """Tight RGBA crop of the orange figure with the near-black bg made transparent."""
    src = Image.open(path).convert("RGBA")
    W, H = src.size
    src = src.crop((3, 3, W - 3, H - 3))
    W, H = src.size
    r, g, b, _ = src.split()
    maxrgb = ImageChops.lighter(ImageChops.lighter(r, g), b)
    bg = max(maxrgb.getpixel(p) for p in [(2, 2), (W - 3, 2), (2, H - 3), (W - 3, H - 3)])
    low, high = bg + 14, bg + 48
    span = max(1, high - low)
    alpha = maxrgb.point(lambda p: 0 if p <= low else (255 if p >= high else int((p - low) * 255 / span)))
    alpha = alpha.filter(ImageFilter.MedianFilter(3))
    fig = src.copy()
    fig.putalpha(alpha)
    bbox = alpha.getbbox()
    return fig.crop(bbox) if bbox else fig


def figure_alpha(figure):
    return figure.split()[3]


def recolor(alpha, top_hex=BRAND_TOP, bottom_hex=BRAND_BOT):
    """Paint a shape (given by its alpha) with a uniform bright-orange vertical
    gradient, keeping the supplied anti-aliased alpha as edges."""
    w, h = alpha.size
    grad = vgrad(w, h, top_hex, bottom_hex).convert("RGBA")
    grad.putalpha(alpha)
    return grad


def recolor_figure(figure, top_hex=BRAND_TOP, bottom_hex=BRAND_BOT):
    return recolor(figure.split()[3], top_hex, bottom_hex)


def thicken(alpha, passes):
    """Dilate strokes by `passes` pixels each side, then soften the new edges so
    the bolder small-size figure doesn't look jagged."""
    a = alpha
    for _ in range(max(0, passes)):
        a = a.filter(ImageFilter.MaxFilter(3))
    return a.filter(ImageFilter.GaussianBlur(0.5)) if passes > 0 else a


def fit_h(img, th):
    w, h = img.size
    return img.resize((max(1, round(w * th / h)), th), Image.LANCZOS)


def fit_within(img, max_w, max_h):
    """Scale to fit inside a box on BOTH axes (preserves aspect). Prevents a wide
    figure from overflowing the icon tile and getting cropped at the edges."""
    w, h = img.size
    scale = min(max_w / w, max_h / h)
    return img.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)


def make_icon(figure, px):
    """Render the icon natively at `px` (rather than downscaling one master) so the
    figure's strokes can be thickened proportionally — keeping the fine line-art at
    1024 while preventing the figure from collapsing to a smudge at 16–64px.

    The dark tile is FULL-BLEED (fills the whole icon, only the rounded corners are
    cut off) so it matches neighbouring macOS Dock icons edge-to-edge. An inset tile
    leaves transparent padding, through which the translucent Dock shows whatever is
    behind it (e.g. a light window) as a grey "border" — full-bleed kills that."""
    img = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    body = px
    radius = round(body * 0.2237)
    tile = vgrad(body, body, "#241a11", "#0d0a07").convert("RGBA")
    img.paste(tile, (0, 0), rounded_mask(body, body, radius))
    border = Image.new("RGBA", (body, body), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        [0, 0, body - 1, body - 1], radius=radius,
        outline=(255, 140, 66, 60), width=max(2, body // 256))
    img.paste(border, (0, 0), border)
    # Fit the figure inside a centered box on BOTH axes so a wide figure can't
    # overflow horizontally; ~0.80 leaves a little dark tile around it (not grey).
    fig_alpha = fit_within(figure, round(body * 0.82), round(body * 0.80)).split()[3]
    # Aim for a ~2px stroke at every size: source strokes are ~6px at 1024, so they
    # scale to ~0.006*px and need topping up with dilation passes at small sizes.
    passes = max(0, round(2 - px * 0.006))
    fig = recolor(thicken(fig_alpha, passes))
    img.paste(fig, ((body - fig.width) // 2, (body - fig.height) // 2), fig)
    return img


def menubar_glyph(alpha, dil=9):
    """Bolden the line art (keeping the OPEN sphere) so it survives at 18px."""
    big = alpha.point(lambda p: 255 if p > 40 else 0)
    for _ in range(dil):
        big = big.filter(ImageFilter.MaxFilter(3))
    return big.filter(ImageFilter.GaussianBlur(0.6))


def write_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=2)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    figure = extract_figure(src)
    alpha = figure_alpha(figure)
    os.makedirs(ASSETS, exist_ok=True)
    write_json(os.path.join(ASSETS, "Contents.json"), {"info": {"author": "xcode", "version": 1}})

    # AppIcon — rendered natively per size so small sizes get bolder strokes
    appicon = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(appicon, exist_ok=True)
    for s in (16, 32, 64, 128, 256, 512, 1024):
        make_icon(figure, s).save(os.path.join(appicon, f"icon_{s}.png"))
    images = [{"size": f"{b}x{b}", "idiom": "mac", "filename": f"icon_{b * sc}.png", "scale": f"{sc}x"}
              for b in (16, 32, 128, 256, 512) for sc in (1, 2)]
    write_json(os.path.join(appicon, "Contents.json"), {"images": images, "info": {"author": "xcode", "version": 1}})

    # AtlasMark (in-app) — same uniform bright orange so the legs don't fade out
    mark = os.path.join(ASSETS, "AtlasMark.imageset")
    os.makedirs(mark, exist_ok=True)
    mark_fig = recolor_figure(figure)
    for th, name in ((128, "mark.png"), (256, "mark@2x.png"), (384, "mark@3x.png")):
        fit_h(mark_fig, th).save(os.path.join(mark, name))
    write_json(os.path.join(mark, "Contents.json"), {
        "images": [{"idiom": "universal", "filename": n, "scale": s}
                   for n, s in (("mark.png", "1x"), ("mark@2x.png", "2x"), ("mark@3x.png", "3x"))],
        "info": {"author": "xcode", "version": 1}})

    # AtlasMenuBar (template silhouette)
    mb = os.path.join(ASSETS, "AtlasMenuBar.imageset")
    os.makedirs(mb, exist_ok=True)
    glyph = menubar_glyph(alpha)
    for th, name in ((18, "menubar.png"), (36, "menubar@2x.png"), (54, "menubar@3x.png")):
        g = fit_h(glyph, th)
        img = Image.new("RGBA", g.size, (0, 0, 0, 255))
        img.putalpha(g)
        img.save(os.path.join(mb, name))
    write_json(os.path.join(mb, "Contents.json"), {
        "images": [{"idiom": "universal", "filename": n, "scale": s}
                   for n, s in (("menubar.png", "1x"), ("menubar@2x.png", "2x"), ("menubar@3x.png", "3x"))],
        "info": {"author": "xcode", "version": 1},
        "properties": {"template-rendering-intent": "template"}})

    print("Generated AppIcon, AtlasMark, AtlasMenuBar into", ASSETS)


if __name__ == "__main__":
    main()
