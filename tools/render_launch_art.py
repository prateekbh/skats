#!/usr/bin/env python3
"""Renders the launch page's in-game art with the game itself (needs Godot and xvfb-run):

- web/launch/turbokat_hero.png: our TurboKat banked in flight (`--jetrender`), the centre panel.
- web/launch/city_attack.png: a missile-damaged tower burning over Megakat City (from
  `--weaponshow`), the "KA-BLAM!" panel.

Usage:  python3 tools/render_launch_art.py
"""
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web" / "launch"


def godot(args: list, w: int, h: int) -> None:
    subprocess.run(["xvfb-run", "-a", "-s", f"-screen 0 {w}x{h}x24", "godot", "--path", str(ROOT),
                    "--rendering-driver", "opengl3", "--resolution", f"{w}x{h}", "--fixed-fps", "30", "--", *args],
                   check=True, capture_output=True, timeout=900)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        # Rendered large with 4x MSAA in the game, then scaled down for clean edges.
        godot([f"--jetrender={tmp / 'jet.png'}"], 3200, 2000)
        jet = Image.open(tmp / "jet.png").convert("RGBA")
        jet = jet.crop(jet.getbbox())
        jet.thumbnail((1600, 1600), Image.LANCZOS)
        jet.save(OUT / "turbokat_hero.png", optimize=True)

        godot([f"--weaponshow={tmp}"], 1280, 720)
        city = Image.open(tmp / "building.png").convert("RGB")
        # Portrait crop for a narrow panel, centred on the smoke column.
        w, h = city.size
        cw = int(h * 0.7)
        left = max(0, min(w - cw, int(w * 0.45) - cw // 2))
        city.crop((left, 0, left + cw, h)).save(OUT / "city_attack.png", optimize=True)
    print("wrote", OUT / "turbokat_hero.png", OUT / "city_attack.png")


if __name__ == "__main__":
    main()
