#!/usr/bin/env python3
"""Prepare the launch-screen art from the source images in tools/launch_src/.

- Removes plain or gradient backgrounds (edge-connected regions close to the background colour).
- Splits the Razor & T-Bone poster into the duo cut-out and the logo.
- Traces the SWAT KATS logo into a crisp multi-colour SVG (potrace) so it stays sharp at any size.

Usage:  python3 tools/prepare_launch_art.py   (needs: pip install pillow numpy scipy potracer)
Writes: web/launch/*.png, web/launch/logo.svg, assets/ui/logo.svg
"""
from pathlib import Path

import numpy as np
import potrace
from PIL import Image, ImageFilter
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "launch_src"
WEB = ROOT / "web" / "launch"
UI = ROOT / "assets" / "ui"


def row_background(rgb: np.ndarray, edge: int = 8) -> np.ndarray:
    """Background colour per row, from the left and right edges (handles vertical gradients)."""
    sides = np.concatenate([rgb[:, :edge], rgb[:, -edge:]], axis=1)
    return np.median(sides, axis=1)


def cut_out(img: Image.Image, tolerance: float, bg: np.ndarray | None = None, hole_tolerance: float = 0.0) -> Image.Image:
    """Makes edge-connected background pixels transparent, with a soft 1 px edge.
    With hole_tolerance > 0, enclosed pockets of background colour (e.g. between two
    characters) are cleared too, and small stray blobs (signatures) are dropped."""
    rgb = np.asarray(img.convert("RGB")).astype(np.float32)
    if bg is None:
        bg = row_background(rgb)
    dist = np.linalg.norm(rgb - bg[:, None, :], axis=2)
    near = dist < tolerance
    labels, _ = ndimage.label(near)
    border = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    background = np.isin(labels, border[border > 0])
    if hole_tolerance > 0:
        pockets, n = ndimage.label(dist < hole_tolerance)
        sizes = ndimage.sum(np.ones_like(dist), pockets, range(1, n + 1))
        for i, size in enumerate(sizes, start=1):
            if size > 300:
                background |= pockets == i
        fg, n = ndimage.label(~background)
        sizes = ndimage.sum(np.ones_like(dist), fg, range(1, n + 1))
        keep = [i for i, size in enumerate(sizes, start=1) if size > 0.02 * fg.size]
        background |= ~np.isin(fg, keep)
    # Close pin-holes, then feather.
    background = ndimage.binary_opening(background, iterations=1, border_value=1)
    alpha = Image.fromarray(((~background) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    return out


def clean_alpha(img: Image.Image, floor: int = 60) -> Image.Image:
    """Zeroes near-transparent fringe pixels so glows and shadows don't outline the image box."""
    a = np.asarray(img.getchannel("A")).copy()
    a[a < floor] = 0
    out = img.copy()
    out.putalpha(Image.fromarray(a))
    return out


def crop_to_content(img: Image.Image, pad: int = 4) -> Image.Image:
    box = img.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
    if not box:
        return img
    l, t, r, b = box
    return img.crop((max(l - pad, 0), max(t - pad, 0), min(r + pad, img.width), min(b + pad, img.height)))


def upscale(img: Image.Image, height: int) -> Image.Image:
    if img.height >= height:
        return img
    w = round(img.width * height / img.height)
    return img.resize((w, height), Image.LANCZOS)


def trace_layer(mask: np.ndarray, fill: str, scale: float, ox: float = 0.0, oy: float = 0.0) -> str:
    """Traces a boolean mask into one SVG <path> with smooth curves (offset by ox, oy)."""
    bmp = potrace.Bitmap(~mask)  # potracer traces the unset pixels
    paths = bmp.trace(turdsize=8, alphamax=1.0, opticurve=True, opttolerance=0.3)

    def pt(p):
        return f"{p.x * scale + ox:.2f},{p.y * scale + oy:.2f}"

    d = []
    for curve in paths:
        d.append("M" + pt(curve.start_point))
        for seg in curve.segments:
            if seg.is_corner:
                d.append("L" + pt(seg.c) + "L" + pt(seg.end_point))
            else:
                d.append("C" + pt(seg.c1) + " " + pt(seg.c2) + " " + pt(seg.end_point))
        d.append("Z")
    return f'<path fill="{fill}" fill-rule="evenodd" d="{"".join(d)}"/>'


# The logo sits in the poster's bottom band (poster pixel coordinates).
LOGO_BOX = (36, 434, 444, 640)  # x0, y0, x1, y1
LETTERS_Y = (458, 596)
SUBTITLE_Y = (598, 632)
EMBLEM_X = 243.5
# Cat-ear shield behind the letters (left half; mirrored about EMBLEM_X). Redrawn as vectors
# because the characters' boots overlap it in the source art.
EMBLEM_LEFT = [(150, 442), (176, 522), (207, 588), (243.5, 635)]
EMBLEM_NOTCH = [(287, 476), (200, 476)]


def emblem_svg() -> str:
    left = EMBLEM_LEFT
    right = [(2 * EMBLEM_X - x, y) for x, y in reversed(left[:-1])]
    pts = left + right + EMBLEM_NOTCH
    poly = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    claws = []
    for i, x in enumerate((240.6, 245.6, 250.6)):
        top = 489 + i * 1.5
        claws.append(f'<polygon fill="#141a33" points="{x - 1.6:.1f},{top} {x + 1.6:.1f},{top} {x + 0.5:.1f},{top + 118} {x - 0.5:.1f},{top + 118}"/>')
    return (
        '<defs><linearGradient id="emb" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#6f8fc4"/><stop offset="1" stop-color="#3c5885"/></linearGradient>'
        '<linearGradient id="red" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#f2533f"/><stop offset="0.45" stop-color="#d42a22"/><stop offset="1" stop-color="#a5121a"/>'
        "</linearGradient></defs>"
        f'<polygon points="{poly}" fill="url(#emb)" stroke="#0b0b10" stroke-width="3.5" stroke-linejoin="round"/>'
        + "".join(claws)
    )


def build_logo(poster: Image.Image) -> str:
    """SWAT KATS logo: vector emblem plus traced letters, ink and subtitle."""
    x0, y0, x1, y1 = LOGO_BOX
    k = 4  # trace at 4x for smooth curves
    crop = poster.crop(LOGO_BOX)
    big = np.asarray(crop.resize((crop.width * k, crop.height * k), Image.LANCZOS)).astype(np.float32)
    r, g, b = big[..., 0], big[..., 1], big[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    yy = np.arange(big.shape[0])[:, None] / k + y0
    xx = np.arange(big.shape[1])[None, :] / k + x0
    in_letters = (yy >= LETTERS_Y[0]) & (yy <= LETTERS_Y[1])
    red = in_letters & (r > 105) & (r > g * 1.55) & (r > b * 1.55)
    red = ndimage.binary_opening(red, iterations=2)
    near_red = ndimage.distance_transform_edt(~red) < 5.5 * k
    ink = in_letters & (lum < 70) & near_red
    ink = ndimage.binary_closing(ink | red, iterations=2)
    # Keep clear of the emblem's lower tip (its half-width shrinks from ~44 px at y=588 to 0 at y=642).
    emblem_half = np.clip((642 - yy) / (642 - 588) * 44, 0, None) + 9
    subtitle = (yy >= SUBTITLE_Y[0]) & (yy <= SUBTITLE_Y[1]) & (lum < 75) & (np.abs(xx - EMBLEM_X) > emblem_half)
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0} {y0} {x1 - x0} {y1 - y0}" '
        f'width="{(x1 - x0) * 3}" height="{(y1 - y0) * 3}">'
        + emblem_svg()
        + trace_layer(ink, "#0b0b10", 1 / k, x0, y0)
        + trace_layer(red, "url(#red)", 1 / k, x0, y0)
        # Subtitle in cream with an ink outline so it reads on dark backgrounds too.
        + trace_layer(subtitle, "#f4ece0", 1 / k, x0, y0).replace("<path ", '<path stroke="#0b0b10" stroke-width="1.6" paint-order="stroke" ')
        + "</svg>"
    )


# (name, source, crop box) for the radio portraits.
PORTRAITS = [
    ("tbone", "swat_kats_duo.png", (88, 52, 208, 172)),
    ("razor", "swat_kats_duo.png", (270, 8, 380, 118)),
    ("callie", "callie.png", (110, 20, 250, 160)),
    ("dark_kat", "dark_kat.png", (280, 20, 400, 140)),
    ("turmoil", "turmoil.png", (170, 60, 320, 210)),
]


def main() -> None:
    WEB.mkdir(parents=True, exist_ok=True)
    UI.mkdir(parents=True, exist_ok=True)

    # Dark Kat: white background.
    dk = Image.open(SRC / "dark_kat.png").convert("RGB")
    dk_cut = cut_out(dk, 42, bg=np.full((dk.height, 3), 255.0))
    upscale(crop_to_content(clean_alpha(dk_cut)), 1100).save(WEB / "dark_kat.png", optimize=True)

    # Turmoil: already transparent.
    upscale(crop_to_content(clean_alpha(Image.open(SRC / "turmoil.png").convert("RGBA"))), 1000).save(WEB / "turmoil.png", optimize=True)

    # Callie: a framed screenshot, used as a comm-screen portrait (kept rectangular).
    Image.open(SRC / "callie.png").convert("RGB").resize((420, 420), Image.LANCZOS).save(WEB / "callie.png", optimize=True)

    # Razor & T-Bone poster: gradient background; heroes above y=SPLIT, logo below.
    poster = Image.open(SRC / "swat_kats_duo.png").convert("RGB")
    split = 452
    duo = cut_out(poster.crop((0, 0, poster.width, split)), 30, hole_tolerance=14)
    upscale(crop_to_content(clean_alpha(duo)), 1400).save(WEB / "swat_kats.png", optimize=True)

    svg = build_logo(poster)

    # Radio portraits (square face crops) for the loading-screen comm panel.
    for name, src, box in PORTRAITS:
        face = Image.open(SRC / src).convert("RGBA")
        if name == "dark_kat":
            face = dk_cut
        tile = Image.new("RGBA", face.size, (26, 16, 32, 255))
        tile.alpha_composite(face)
        tile.convert("RGB").crop(box).resize((160, 160), Image.LANCZOS).save(WEB / f"face_{name}.png", optimize=True)
    (WEB / "logo.svg").write_text(svg)
    (UI / "logo.svg").write_text(svg)
    print("wrote", sorted(p.name for p in WEB.glob("*")))


if __name__ == "__main__":
    main()
