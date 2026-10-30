#!/usr/bin/env python3
"""Fetch the special-missile pictures for the HUD carousel from the swatkats.info missile catalogue
(https://swatkats.info/entry-type/swat-kats-missiles/) and crop them into 16:10 cards.

    python3 tools/fetch_missile_art.py

Writes assets/ui/missiles/<id>.jpg (ids match scripts/combat/arsenal.gd). Re-run instead of editing
the outputs. The crop centre is tuned per frame so the missile itself fills the card.
"""
import io
import pathlib
import urllib.request

from PIL import Image, ImageEnhance

BASE = "https://swatkats.info/wp-content/uploads/"
# id: (upload path, crop centre as fractions of the frame)
MISSILES = {
    "blowtorch": ("2018/07/blowtorch_missiles.jpg", (0.45, 0.45)),
    "octopus": ("2018/06/octopus-missile.jpg", (0.55, 0.5)),
    "buzzsaw": ("2018/07/buzz-saw-missile.jpg", (0.6, 0.45)),
    "scrambler": ("2018/07/scrambler.jpg", (0.45, 0.5)),
    "slicer": ("2018/07/slicer_missile.jpg", (0.5, 0.5)),
    "matchhead": ("2018/07/match_head_missile.jpg", (0.5, 0.45)),
}
OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "ui" / "missiles"
SIZE = (384, 240)


def card(img: Image.Image, centre: tuple) -> Image.Image:
    w, h = img.size
    cw = w
    ch = int(cw * SIZE[1] / SIZE[0])
    if ch > h:
        ch = h
        cw = int(ch * SIZE[0] / SIZE[1])
    cx = min(max(int(centre[0] * w), cw // 2), w - cw // 2)
    cy = min(max(int(centre[1] * h), ch // 2), h - ch // 2)
    img = img.crop((cx - cw // 2, cy - ch // 2, cx + cw // 2, cy + ch // 2)).resize(SIZE, Image.LANCZOS)
    # A little extra punch so the cel colours read at HUD size.
    return ImageEnhance.Color(ImageEnhance.Contrast(img).enhance(1.08)).enhance(1.12)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for mid, (path, centre) in MISSILES.items():
        with urllib.request.urlopen(BASE + path) as r:
            img = Image.open(io.BytesIO(r.read())).convert("RGB")
        card(img, centre).save(OUT / f"{mid}.jpg", quality=88)
        print("wrote", OUT / f"{mid}.jpg")


if __name__ == "__main__":
    main()
