#!/usr/bin/env python3
"""Character portraits for the in-game radio cards and the comic-strip cutscenes, cropped from
show frames on swatkats.info (character entries, https://swatkats.info/?s=characters) and from
the launcher's T-Bone & Razor art (tools/launch_src/).

Each character has a few expressions so a line can be delivered calm, alarmed, angry...

    python3 tools/fetch_character_art.py

Writes assets/ui/portraits/<character>_<mood>.png (256x256 face crops, radio cards) and
assets/ui/panels/<character>_<mood>.jpg (wider frames, cutscene panels). Re-run instead of
editing the outputs.
"""
import io
import pathlib
import urllib.request

from PIL import Image, ImageEnhance

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "tools" / "launch_src"
PORTRAITS = ROOT / "assets" / "ui" / "portraits"
PANELS = ROOT / "assets" / "ui" / "panels"
BASE = "https://swatkats.info/wp-content/uploads/"

# id: (source, face crop box, panel crop box or None for the whole frame)
# Sources starting with "local:" come from tools/launch_src/.
ART = {
    "callie_calm": ("2018/06/callie-briggs.png", (190, 30, 410, 250), (60, 0, 480, 315)),
    "callie_alarmed": ("local:callie.png", (85, 15, 225, 155), None),
    "feral_stern": ("2018/06/Commander-Ulysses-Feral-large.png", (120, 0, 270, 150), (0, 0, 482, 320)),
    "feral_angry": ("2018/07/t-bone-commander-feral.jpg", (430, 0, 640, 210), (280, 0, 640, 270)),
    "felina_alert": ("2018/06/lt-felina-feral.png", (150, 10, 340, 200), (40, 0, 500, 345)),
    "manx_smug": ("2018/06/mayor-manx.png", (80, 20, 300, 240), (0, 0, 483, 320)),
    "manx_golf": ("2018/07/mayor-manx-012.jpg", (255, 90, 415, 250), None),
    "ann_reporting": ("2018/06/ann-gora.png", (190, 20, 510, 340), (60, 0, 640, 480)),
    "manx_nervous": ("2018/07/mayor-manx-button-pin.jpg", (140, 0, 410, 270), None),
    "tbone_grin": ("local:swat_kats_duo.png", (88, 52, 208, 172), (40, 20, 280, 200)),
    "tbone_scared": ("2018/05/fear-of-bugs.jpg", (250, 0, 600, 350), None),
    "razor_focused": ("local:swat_kats_duo.png", (270, 8, 380, 118), (230, 0, 450, 165)),
    "dark_kat_sneer": ("2018/06/dark-kat.png", (165, 0, 305, 140), (60, 0, 420, 270)),
    "dark_kat_angry": ("2018/06/katastrophe-873-swat-kats.jpg", (40, 110, 330, 400), None),
}


def load(source: str) -> Image.Image:
    if source.startswith("local:"):
        img = Image.open(SRC / source[6:])
    else:
        with urllib.request.urlopen(BASE + source) as r:
            img = Image.open(io.BytesIO(r.read()))
    # Transparent cut-outs sit on the panel ink colour.
    img = img.convert("RGBA")
    bg = Image.new("RGBA", img.size, (20, 16, 28, 255))
    bg.alpha_composite(img)
    return bg.convert("RGB")


def punch(img: Image.Image) -> Image.Image:
    return ImageEnhance.Color(ImageEnhance.Contrast(img).enhance(1.06)).enhance(1.1)


def main() -> None:
    PORTRAITS.mkdir(parents=True, exist_ok=True)
    PANELS.mkdir(parents=True, exist_ok=True)
    cache: dict = {}
    for art_id, (source, face, panel) in ART.items():
        if source not in cache:
            cache[source] = load(source)
        img = cache[source]
        punch(img.crop(face).resize((256, 256), Image.LANCZOS)).save(PORTRAITS / f"{art_id}.png", optimize=True)
        frame = img.crop(panel) if panel else img
        frame.thumbnail((720, 720), Image.LANCZOS)
        punch(frame).save(PANELS / f"{art_id}.jpg", quality=88)
        print("wrote", art_id)


if __name__ == "__main__":
    main()
