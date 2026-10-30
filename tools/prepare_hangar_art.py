#!/usr/bin/env python3
"""The hangar backdrop for the launch screen, redrawn as layered vector art.

Composition follows the show's hangar frame in tools/launch_src/hangar_ref.png (used only as a
layout reference): the left wall with a red blast door, the dark corridor with ceiling robot arms,
the landing circle, stairs, a strapped crate of missiles and a tyre in the foreground. The
TurboKat itself is not drawn here; the game renders our own 3D model onto the pad.

Coordinates are the reference frame's (640x480) mapped to a 16:9 canvas at 3x, with extra wall
at both sides so it also fills wide screens.

Usage:  python3 tools/prepare_hangar_art.py   (needs Node + Playwright's Chromium, Godot, xvfb-run)
Writes: web/launch/hangar.svg (layers: back, floor, arms, fore), web/launch/hangar.jpg (the
        backdrop), web/launch/turbokat_hangar.png (our TurboKat rendered by the game with
        `--hangarjet`, placed on the pad, same canvas size) and web/launch/hangar_preview.jpg
"""
import json
import math
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web" / "launch"

W, H = 2560, 1440
S = 3.0
OX = (W - 640 * S) / 2  # reference x=0 sits here

INK = "#0a0e11"
WALL = "#5d8b8f"
WALL_SHADE = "#3f676c"
WALL_DARK = "#2a4649"
PILLAR = "#8fb0aa"
CEIL = "#121a20"
CEIL_LIT = "#1d2a31"
FLOOR_NEAR = "#c4bb9f"
FLOOR_FAR = "#7f9e9a"
RED = "#b8261d"
RED_DARK = "#6d120e"
BRASS = "#c8962f"
BRASS_DARK = "#7a5416"
STEEL = "#8e9fa6"
STEEL_DARK = "#4b5a61"

rng = random.Random(1993)


def P(x: float, y: float) -> str:
    """Reference-frame point -> canvas coordinates string."""
    return f"{OX + x * S:.1f},{y * S:.1f}"


def X(x: float) -> float:
    return OX + x * S


def Y(y: float) -> float:
    return y * S


def poly(points, fill, stroke=INK, width=4.5, extra="") -> str:
    pts = " ".join(P(*p) for p in points)
    st = f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round"' if stroke else ""
    return f'<polygon points="{pts}" fill="{fill}"{st} {extra}/>'


def line(a, b, stroke=INK, width=3.0, extra="") -> str:
    return f'<line x1="{X(a[0]):.1f}" y1="{Y(a[1]):.1f}" x2="{X(b[0]):.1f}" y2="{Y(b[1]):.1f}" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" {extra}/>'


def path(d_ref: list, fill="none", stroke=INK, width=3.0, extra="") -> str:
    """d_ref: list of ('M', x, y) / ('L', x, y) / ('Q', cx, cy, x, y) / ('C', ...) / ('Z',)."""
    parts = []
    for cmd in d_ref:
        c = cmd[0]
        nums = cmd[1:]
        coords = []
        for i in range(0, len(nums), 2):
            coords.append(P(nums[i], nums[i + 1]))
        parts.append(c + " " + " ".join(coords))
    st = f' stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"' if stroke else ""
    return f'<path d="{" ".join(parts)}" fill="{fill}"{st} {extra}/>'


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def quad_pt(q, u, v):
    """Bilinear point in a quad (tl, tr, br, bl)."""
    top = lerp(q[0], q[1], u)
    bot = lerp(q[3], q[2], u)
    return lerp(top, bot, v)


# --- layers -------------------------------------------------------------------------------

def defs() -> str:
    return f"""
<defs>
  <linearGradient id="floor" x1="0" y1="{Y(235)}" x2="0" y2="{Y(480)}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{FLOOR_FAR}"/><stop offset="0.45" stop-color="#a6ae9c"/><stop offset="1" stop-color="{FLOOR_NEAR}"/>
  </linearGradient>
  <linearGradient id="ceil" x1="0" y1="0" x2="0" y2="{Y(140)}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#0b1116"/><stop offset="1" stop-color="{CEIL_LIT}"/>
  </linearGradient>
  <linearGradient id="wallL" x1="{X(50)}" y1="0" x2="{X(300)}" y2="0" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{WALL}"/><stop offset="1" stop-color="{WALL_SHADE}"/>
  </linearGradient>
  <linearGradient id="back" x1="0" y1="{Y(120)}" x2="0" y2="{Y(250)}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="#0e171b"/><stop offset="1" stop-color="#22393c"/>
  </linearGradient>
  <linearGradient id="missile" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2a2840"/><stop offset="0.3" stop-color="#8a87b8"/><stop offset="0.55" stop-color="#3a3858"/><stop offset="1" stop-color="#151422"/>
  </linearGradient>
  <linearGradient id="nose" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#e2463a"/><stop offset="0.5" stop-color="{RED}"/><stop offset="1" stop-color="{RED_DARK}"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="#d8f0e8" stop-opacity="0.55"/><stop offset="1" stop-color="#d8f0e8" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="vignette" cx="0.5" cy="0.45" r="0.75">
    <stop offset="0.5" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity="0.65"/>
  </radialGradient>
  <!-- The show's dry-brush grime: thresholded noise as dark speckle. -->
  <filter id="grime" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.55" numOctaves="2" seed="7" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.02  0 0 0 0 0.04  0 0 0 0 0.05  0 0 0 16 -10.6" result="speck"/>
    <feComposite in="speck" in2="SourceAlpha" operator="in"/>
  </filter>
  <filter id="stain" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.012 0.03" numOctaves="3" seed="3" result="n"/>
    <feColorMatrix in="n" type="matrix" values="0 0 0 0 0.03  0 0 0 0 0.05  0 0 0 0 0.05  0 0 0 4 -2.3" result="s"/>
    <feComposite in="s" in2="SourceAlpha" operator="in"/>
  </filter>
</defs>"""


# Room outline (reference coords). The left wall recedes from the pillar to the corridor mouth.
LW = [(50, 12), (300, 128), (300, 246), (50, 292)]          # left wall quad
BACK = [(300, 118), (565, 118), (565, 246), (300, 246)]     # dark back of the corridor
RW = [(565, 118), (760, 60), (760, 300), (565, 246)]         # right wall (extends off-frame)
PILLAR_Q = [(-120, 0), (50, 0), (50, 292), (-120, 322)]       # near pillar / wall section at left


def room() -> str:
    o = []
    o.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="{CEIL}"/>')
    # Ceiling: girders converging into the corridor.
    o.append(poly([(-120, 0), (760, 0), (760, 60), (565, 118), (300, 118), (300, 128), (50, 12), (-120, 0)], "url(#ceil)", stroke=None))
    vp = (430, 175)
    for k in range(6):
        x0 = -60 + k * 160
        a = (x0, -5)
        b = lerp((x0, 0), vp, 0.6)
        o.append(line(a, b, INK, 26) + line(a, b, "#24333b", 19) + line(a, b, "#33474f", 5))
    for t in (0.18, 0.4):
        a = lerp((-60, 0), vp, t)
        b = lerp((760, 0), vp, t)
        o.append(line(a, b, INK, 22) + line(a, b, "#1f2d34", 15))
    # Corridor back.
    o.append(poly(BACK, "url(#back)"))
    # Far corridor detail: lit doorway and panels.
    o.append(poly([(470, 160), (520, 160), (520, 246), (470, 246)], "#36565a"))
    o.append(poly([(478, 168), (512, 168), (512, 246), (478, 246)], "#4c7376"))
    for k in range(6):
        x = 312 + k * 26
        o.append(poly([(x, 150), (x + 18, 150), (x + 18, 200), (x, 200)], "#22383c", width=2))
    # Left wall with panels.
    o.append(poly(LW, "url(#wallL)"))
    for u in (0.18, 0.42, 0.66, 0.88):
        o.append(line(quad_pt(LW, u, 0.04), quad_pt(LW, u, 1.0), WALL_DARK, 2.5))
    o.append(line(quad_pt(LW, 0.0, 0.33), quad_pt(LW, 1.0, 0.33), WALL_DARK, 2.5))
    o.append(line(quad_pt(LW, 0.0, 0.82), quad_pt(LW, 1.0, 0.82), WALL_DARK, 3))
    # Right wall.
    o.append(poly(RW, WALL_SHADE))
    for u in (0.25, 0.55, 0.85):
        o.append(line(quad_pt(RW, u, 0.0), quad_pt(RW, u, 1.0), WALL_DARK, 2.5))
    o.append(line(quad_pt(RW, 0.0, 0.7), quad_pt(RW, 1.0, 0.7), WALL_DARK, 2.5))
    # Right-wall red door and its frame.
    o.append(poly([(570, 172), (603, 166), (603, 252), (570, 245)], "#20363a"))
    o.append(poly([(573, 176), (600, 171), (600, 249), (573, 243)], RED))
    o.append(line((575, 182), (598, 240), RED_DARK, 4) + line((598, 178), (575, 238), RED_DARK, 4))
    # Near pillar.
    o.append(poly(PILLAR_Q, PILLAR))
    o.append(line((50, 0), (50, 292), INK, 4))
    o.append(line((-120, 150), (50, 140), "#6f938e", 3))
    # Vent box on the pillar.
    o.append(poly([(-2, 100), (22, 99), (22, 121), (-2, 122)], "#9fc0c2"))
    for k in range(4):
        o.append(line((2, 104 + k * 4.5), (19, 103.5 + k * 4.5), "#2b4549", 2))
    return "\n".join(o)


def floor() -> str:
    o = []
    o.append(poly([(-120, 322), (50, 292), (300, 246), (565, 246), (760, 300), (760, 480), (-120, 480)], "url(#floor)", stroke=None))
    o.append(line((50, 292), (300, 246), INK, 3) + line((300, 246), (565, 246), INK, 3) + line((565, 246), (760, 300), INK, 3))
    o.append(line((-120, 322), (50, 292), INK, 3))
    # Floor slab seams.
    for a, b in [((500, 292), (520, 480)), ((150, 290), (40, 480)), ((300, 250), (250, 480)),
                 ((560, 300), (640, 340)), ((-100, 380), (160, 330))]:
        o.append(line(a, b, "#5d6e66", 2.2))
    # Landing circle with arrows.
    cx, cy, rx, ry = X(425), Y(263), 192 * S, 28 * S
    o.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="{INK}" stroke-width="15"/>')
    o.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="none" stroke="#e8ece4" stroke-width="10"/>')
    for sgn in (-1, 1):
        o.append(path([("M", 425 + sgn * 70, 263), ("L", 425 + sgn * 150, 263)], stroke="#e8ece4", width=10))
        o.append(poly([(425 + sgn * 182, 263), (425 + sgn * 150, 255), (425 + sgn * 150, 271)], "#e8ece4", stroke=INK, width=2))
    o.append(path([("M", 425, 240), ("L", 425, 286)], stroke="#e8ece4", width=11))
    o.append(path([("M", 395, 250), ("L", 455, 250)], stroke="#e8ece4", width=8))
    o.append(path([("M", 395, 276), ("L", 455, 276)], stroke="#e8ece4", width=8))
    # Contact shadow where the TurboKat stands.
    o.append(f'<ellipse cx="{X(452)}" cy="{Y(281)}" rx="{165 * S}" ry="{11 * S}" fill="#0d1616" opacity="0.45"/>')
    # Stencilled bay markings.
    for (x0, y0, w, h) in [(205, 292, 95, 22), (318, 300, 102, 22)]:
        pts = [(x0, y0), (x0 + w * 0.38, y0), (x0 + w * 0.38, y0 + h * 0.3), (x0 + w * 0.62, y0 + h * 0.3), (x0 + w * 0.62, y0),
               (x0 + w, y0), (x0 + w - 6, y0 + h), (x0 + w * 0.62 - 6, y0 + h), (x0 + w * 0.62 - 5, y0 + h * 0.7),
               (x0 + w * 0.38 - 5, y0 + h * 0.7), (x0 + w * 0.38 - 6, y0 + h), (x0 - 6, y0 + h)]
        o.append(poly(pts, "none", stroke="#3b4a44", width=2.5))
    # Oil stains.
    for (x, y, r) in [(260, 330, 22), (480, 300, 30), (120, 350, 18), (610, 300, 16)]:
        o.append(f'<ellipse cx="{X(x)}" cy="{Y(y)}" rx="{r * S}" ry="{r * S * 0.3}" fill="#4e5a52" opacity="0.25"/>')
    return "\n".join(o)


def wall_details() -> str:
    o = []
    # Big red blast door with X bracing.
    o.append(poly([(196, 143), (266, 150), (266, 252), (196, 258)], "#22383c", width=3))
    o.append(poly([(201, 148), (262, 154), (262, 248), (201, 253)], RED))
    o.append(poly([(206, 153), (257, 158), (257, 243), (206, 248)], "none", stroke=RED_DARK, width=3))
    o.append(line((210, 160), (253, 238), RED_DARK, 9) + line((253, 163), (210, 241), RED_DARK, 9))
    o.append(line((210, 160), (253, 238), "#e0453a", 2) + line((253, 163), (210, 241), "#e0453a", 2))
    # Light over the door.
    o.append(f'<ellipse cx="{X(231)}" cy="{Y(140)}" rx="{30 * S}" ry="{14 * S}" fill="url(#glow)"/>')
    o.append(poly([(224, 134), (238, 135), (238, 141), (224, 140)], "#f0f4c8", width=2))
    # Fuse / switch box on the wall.
    o.append(poly([(64, 140), (96, 143), (96, 186), (64, 186)], "#9cb6b8"))
    o.append(poly([(70, 148), (90, 150), (90, 180), (70, 179)], "#7e9a9c", width=2))
    o.append(f'<circle cx="{X(84)}" cy="{Y(158)}" r="{4.5 * S}" fill="#5a7476" stroke="{INK}" stroke-width="3"/>')
    o.append(f'<circle cx="{X(84)}" cy="{Y(171)}" r="{4.5 * S}" fill="#5a7476" stroke="{INK}" stroke-width="3"/>')
    # Conduit and pipes along the wall.
    o.append(path([("M", 80, 186), ("L", 80, 228), ("L", 120, 222), ("L", 196, 214)], stroke=INK, width=13))
    o.append(path([("M", 80, 186), ("L", 80, 228), ("L", 120, 222), ("L", 196, 214)], stroke="#a9c3c4", width=7))
    o.append(path([("M", 60, 262), ("L", 120, 250), ("L", 196, 238)], stroke=INK, width=17))
    o.append(path([("M", 60, 262), ("L", 120, 250), ("L", 196, 238)], stroke="#8aa7a8", width=10))
    o.append(path([("M", 72, 245), ("L", 72, 262)], stroke=INK, width=16) + path([("M", 72, 245), ("L", 72, 262)], stroke="#8aa7a8", width=9))
    # Machinery between the door and the corridor.
    o.append(poly([(268, 150), (296, 140), (296, 246), (268, 248)], "#35575b"))
    for (a, b) in [((272, 160), (292, 154)), ((272, 190), (292, 186)), ((272, 220), (292, 218))]:
        o.append(line(a, b, WALL_DARK, 3))
    o.append(path([("M", 276, 128), ("L", 276, 148), ("Q", 276, 156, 284, 156), ("L", 294, 156)], stroke=INK, width=14))
    o.append(path([("M", 276, 128), ("L", 276, 148), ("Q", 276, 156, 284, 156), ("L", 294, 156)], stroke="#8fa9ab", width=8))
    o.append(poly([(270, 196), (284, 194), (284, 214), (270, 215)], "#9cb3b5", width=2.5))
    # Ceiling pipes along the left wall top.
    o.append(path([("M", 160, 70), ("L", 300, 130)], stroke=INK, width=16) + path([("M", 160, 70), ("L", 300, 130)], stroke="#4f6c71", width=9))
    o.append(path([("M", 176, 64), ("L", 192, 72), ("L", 192, 92)], stroke=INK, width=14) + path([("M", 176, 64), ("L", 192, 72), ("L", 192, 92)], stroke="#9fb8ba", width=8))
    # Wall monitors (blank for now; the launch screen puts news and stats on them).
    for (x0, y0, w, h) in [(112, 128, 52, 34), (110, 172, 34, 22), (148, 170, 34, 22)]:
        o.append(poly([(x0, y0), (x0 + w, y0 + 3), (x0 + w, y0 + h + 3), (x0, y0 + h)], "#1b2a2e", width=3, extra='class="monitor"'))
        o.append(poly([(x0 + 3, y0 + 3), (x0 + w - 3, y0 + 5.5), (x0 + w - 3, y0 + h), (x0 + 3, y0 + h - 2.5)], "#123c3a", width=1.5))
    return "\n".join(o)


def stairs() -> str:
    """Concrete stairs climbing to the left, with a railing."""
    o = []
    steps = 7
    for k in range(steps):
        y = 312 - k * 13
        x0 = -110 + k * 4
        x1 = 44 - k * 6
        o.append(poly([(x0, y - 13), (x1, y - 15), (x1 + 4, y), (x0, y + 2)], "#7f9a96" if k % 2 == 0 else "#748f8b", width=2.5))
        o.append(line((x0, y - 13), (x1, y - 15), "#a9c0bb", 2))
    # Railing.
    o.append(path([("M", 40, 300), ("L", -60, 205)], stroke=INK, width=10) + path([("M", 40, 300), ("L", -60, 205)], stroke=STEEL, width=5))
    for t in (0.0, 0.33, 0.66, 1.0):
        a = lerp((40, 300), (-60, 205), t)
        o.append(line(a, (a[0] + 2, a[1] + 34), INK, 8) + line(a, (a[0] + 2, a[1] + 34), STEEL, 4))
    return "\n".join(o)


def arm_segment(a, b, width, fill, dark) -> str:
    """A chunky arm link from a to b (reference coords) with an inked edge and a joint."""
    o = [line(a, b, INK, width * S + 6), line(a, b, fill, width * S), line(a, b, dark, max(2.0, width * S * 0.25), 'opacity="0.6"')]
    for p in (a, b):
        o.append(f'<circle cx="{X(p[0])}" cy="{Y(p[1])}" r="{width * S * 0.75}" fill="{fill}" stroke="{INK}" stroke-width="3"/>')
        o.append(f'<circle cx="{X(p[0])}" cy="{Y(p[1])}" r="{width * S * 0.28}" fill="{dark}"/>')
    return "\n".join(o)


def claw(at, fill, dark, size=1.0, angle=0.0) -> str:
    x, y = at
    s = size
    jaws = []
    for sgn in (-1, 1):
        jaws.append(path([("M", x + sgn * 4 * s, y), ("Q", x + sgn * 16 * s, y + 6 * s, x + sgn * 13 * s, y + 22 * s),
                          ("L", x + sgn * 7 * s, y + 30 * s)], stroke=INK, width=9 * s + 4))
        jaws.append(path([("M", x + sgn * 4 * s, y), ("Q", x + sgn * 16 * s, y + 6 * s, x + sgn * 13 * s, y + 22 * s),
                          ("L", x + sgn * 7 * s, y + 30 * s)], stroke=fill, width=9 * s))
    hub = f'<rect x="{X(x - 7 * s)}" y="{Y(y - 5 * s)}" width="{14 * s * S}" height="{9 * s * S}" rx="6" fill="{fill}" stroke="{INK}" stroke-width="3"/>'
    return f'<g transform="rotate({angle} {X(x)} {Y(y)})">' + "\n".join(jaws) + hub + "</g>"


def arms() -> str:
    o = []
    # Brass arm hanging from the ceiling at the left, with cable loops.
    o.append(f'<g id="arm-brass" transform="translate({X(222):.1f} 0) scale(1.25) translate({-X(222):.1f} 0)">')
    o.append(path([("M", 118, 40), ("C", 100, 120, 115, 190, 128, 182), ("C", 142, 170, 128, 90, 132, 50)], stroke=INK, width=8))
    o.append(path([("M", 118, 40), ("C", 100, 120, 115, 190, 128, 182), ("C", 142, 170, 128, 90, 132, 50)], stroke=BRASS, width=4))
    o.append(path([("M", 182, 0), ("C", 180, 50, 230, 60, 232, 0)], stroke=INK, width=8) + path([("M", 182, 0), ("C", 180, 50, 230, 60, 232, 0)], stroke=BRASS, width=4))
    o.append(path([("M", 196, 0), ("C", 196, 36, 218, 40, 220, 0)], stroke=INK, width=7) + path([("M", 196, 0), ("C", 196, 36, 218, 40, 220, 0)], stroke=BRASS, width=3.5))
    o.append(arm_segment((222, -10), (128, 52), 5.5, BRASS, BRASS_DARK))
    o.append(arm_segment((96, 50), (150, 52), 4.0, BRASS, BRASS_DARK))
    o.append(arm_segment((96, 50), (88, 88), 3.2, BRASS, BRASS_DARK))
    o.append(f'<ellipse cx="{X(86)}" cy="{Y(91)}" rx="{10 * S}" ry="{3 * S}" fill="{BRASS}" stroke="{INK}" stroke-width="3"/>')
    o.append(arm_segment((140, 55), (150, 102), 3.6, BRASS, BRASS_DARK))
    o.append(arm_segment((150, 102), (168, 122), 3.4, BRASS, BRASS_DARK))
    o.append(claw((168, 126), BRASS, BRASS_DARK, 1.15))
    o.append("</g>")
    # Steel arms up in the dark corridor ceiling.
    o.append('<g id="arm-steel" opacity="0.92">')
    o.append(f'<rect x="{X(400)}" y="{Y(0)}" width="{60 * S}" height="{12 * S}" fill="#26343b" stroke="{INK}" stroke-width="3"/>')
    o.append(arm_segment((428, 8), (428, 52), 5.0, STEEL, STEEL_DARK))
    o.append(arm_segment((428, 52), (440, 96), 4.2, STEEL, STEEL_DARK))
    o.append(claw((440, 100), STEEL, STEEL_DARK, 1.0))
    o.append(arm_segment((300, 62), (330, 78), 3.4, STEEL_DARK, "#2b363b"))
    o.append(arm_segment((330, 78), (342, 108), 3.0, STEEL_DARK, "#2b363b"))
    o.append(claw((343, 111), STEEL_DARK, "#2b363b", 0.7))
    o.append(arm_segment((560, 40), (520, 78), 3.6, STEEL_DARK, "#2b363b"))
    o.append(arm_segment((520, 78), (490, 80), 3.0, STEEL_DARK, "#2b363b"))
    o.append(claw((486, 84), STEEL_DARK, "#2b363b", 0.65, 30))
    o.append("</g>")
    return "\n".join(o)


def missile_crate() -> str:
    """A strapped bundle of red-tipped missiles in the left foreground."""
    o = ['<g id="crate">']
    rows = [(360, 4), (388, 5), (418, 5), (450, 5)]
    for (y, n) in rows:
        pass
    # Missiles: back row first, rows overlapping so the bundle reads as round and heavy.
    layout = [(356, 150, 470), (372, 120, 478), (396, 96, 486), (424, 84, 492), (454, 78, 496)]
    for (y, x0, x1) in layout:
        r = 16
        # Fins at the tail.
        o.append(poly([(x0 + 14, y - r + 2), (x0 - 34, y - r - 10), (x0 - 38, y - r + 3), (x0 + 8, y - 3)], RED, width=3))
        o.append(poly([(x0 + 14, y + r - 2), (x0 - 34, y + r + 8), (x0 - 38, y + r - 4), (x0 + 8, y + 3)], RED_DARK, width=3))
        # Body.
        o.append(f'<rect x="{X(x0)}" y="{Y(y - r)}" width="{(x1 - x0) * S}" height="{2 * r * S}" rx="{r * S * 0.35}" fill="url(#missile)" stroke="{INK}" stroke-width="5"/>')
        o.append(line((x0 + 14, y - r * 0.42), (x1 - 10, y - r * 0.42), "#c4c1ec", 5, 'opacity="0.55"'))
        # Nose cone.
        o.append(path([("M", x1, y - r), ("Q", x1 + 44, y - r * 0.7, x1 + 58, y + 1), ("Q", x1 + 44, y + r * 0.75, x1, y + r), ("Z",)], fill="url(#nose)", width=5))
        o.append(path([("M", x1 + 6, y - r * 0.6), ("Q", x1 + 32, y - r * 0.5, x1 + 46, y - 3)], stroke="#f39a8c", width=4))
        o.append(line((x1, y - r + 2), (x1, y + r - 2), INK, 5))
    # The crate frame: a top rail with a lid plate and two straps wrapping the bundle.
    o.append(poly([(150, 334), (430, 326), (440, 344), (158, 352)], "#3a3c55", width=5))
    for k in range(5):
        o.append(f'<rect x="{X(186 + k * 46)}" y="{Y(331 - k * 1.2)}" width="{24 * S}" height="{7 * S}" fill="#2a2c42" stroke="{INK}" stroke-width="3"/>')
    for xs in (150, 316):
        o.append(poly([(xs, 340), (xs + 26, 338), (xs + 30, 484), (xs + 4, 484)], "#2c2e45", width=5))
        o.append(line((xs + 9, 348), (xs + 13, 482), "#5f6286", 3.5))
        for yy in range(352, 480, 16):
            o.append(f'<circle cx="{X(xs + 20)}" cy="{Y(yy)}" r="4" fill="#7b7ea6"/>')
    o.append("</g>")
    return "\n".join(o)


def tyre() -> str:
    cx, cy = 640, 400
    o = ['<g id="tyre">']
    o.append(f'<ellipse cx="{X(cx + 16)}" cy="{Y(cy)}" rx="{56 * S}" ry="{88 * S}" fill="#15171b" stroke="{INK}" stroke-width="4"/>')
    o.append(f'<ellipse cx="{X(cx)}" cy="{Y(cy)}" rx="{56 * S}" ry="{88 * S}" fill="#24272d" stroke="{INK}" stroke-width="4"/>')
    for k in range(10):
        a = k / 10 * math.tau
        o.append(line((cx + math.cos(a) * 50, cy + math.sin(a) * 79), (cx + math.cos(a) * 56, cy + math.sin(a) * 88), "#3a3e46", 4))
    o.append(f'<ellipse cx="{X(cx)}" cy="{Y(cy)}" rx="{34 * S}" ry="{54 * S}" fill="#2e3238" stroke="{INK}" stroke-width="4"/>')
    o.append(f'<ellipse cx="{X(cx)}" cy="{Y(cy)}" rx="{22 * S}" ry="{36 * S}" fill="#6f6d4a" stroke="{INK}" stroke-width="3"/>')
    o.append(f'<ellipse cx="{X(cx - 3)}" cy="{Y(cy - 4)}" rx="{11 * S}" ry="{18 * S}" fill="#c9c27a" stroke="{INK}" stroke-width="3"/>')
    o.append(path([("M", cx - 30, cy - 60), ("Q", cx - 52, cy, cx - 30, cy + 60)], stroke="#4a4f58", width=4))
    o.append("</g>")
    return "\n".join(o)


def grime() -> str:
    """Speckle and stains over walls and floor, plus a vignette."""
    return f"""
<g opacity="0.9">
  <rect x="0" y="0" width="{W}" height="{H}" fill="#fff" filter="url(#grime)"/>
</g>
<g opacity="0.2">
  <rect x="0" y="0" width="{W}" height="{H}" fill="#fff" filter="url(#stain)"/>
</g>
<rect x="0" y="0" width="{W}" height="{H}" fill="url(#vignette)"/>"""


def build_svg() -> str:
    layers = [
        ('back', room() + wall_details() + stairs()),
        ('floor', floor()),
        ('grime', grime()),
        ('arms', arms()),
        ('fore', missile_crate() + tyre()),
    ]
    body = "\n".join(f'<g id="{name}">\n{svg}\n</g>' for name, svg in layers)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">{defs()}\n{body}\n</svg>\n'


def render(svg_path: Path, out: Path) -> None:
    """Rasterises the SVG with the pre-installed Playwright Chromium (Node package)."""
    script = f"""
const {{ chromium }} = require('playwright');
(async () => {{
  const browser = await chromium.launch();
  const page = await browser.newPage({{ viewport: {{ width: {W}, height: {H} }} }});
  await page.goto({json.dumps(svg_path.as_uri())});
  await page.screenshot({{ path: {json.dumps(str(out))}, type: 'jpeg', quality: 90 }});
  await browser.close();
}})();
"""
    subprocess.run(["node", "-e", script], check=True)


# Where the parked jet sits on the canvas (reference coords): nose to tail and wheel line.
JET_LEFT, JET_RIGHT, JET_WHEELS = 268, 628, 284


def render_jet(out: Path) -> None:
    """Renders our TurboKat with the game (`--hangarjet`) and places it on the pad."""
    import tempfile
    from PIL import Image
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "jet.png"
        subprocess.run(["xvfb-run", "-a", "-s", f"-screen 0 {W}x{H}x24", "godot", "--path", str(ROOT),
                        "--rendering-driver", "opengl3", "--resolution", f"{W}x{H}", "--", f"--hangarjet={raw}"],
                       check=True, capture_output=True)
        jet = Image.open(raw).convert("RGBA")
    jet = jet.crop(jet.getbbox())
    scale = (JET_RIGHT - JET_LEFT) * S / jet.width
    jet = jet.resize((round(jet.width * scale), round(jet.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    canvas.alpha_composite(jet, (round(X(JET_LEFT)), round(Y(JET_WHEELS) - jet.height)))
    canvas.save(out, optimize=True)


def main() -> None:
    from PIL import Image
    OUT.mkdir(parents=True, exist_ok=True)
    svg_path = OUT / "hangar.svg"
    svg_path.write_text(build_svg())
    render(svg_path, OUT / "hangar.jpg")
    render_jet(OUT / "turbokat_hangar.png")
    # Preview of the layers together: backdrop, jet, then the foreground drawn again on top
    # would need a separate pass; the jet sits behind nothing in the foreground at this layout.
    preview = Image.open(OUT / "hangar.jpg").convert("RGBA")
    preview.alpha_composite(Image.open(OUT / "turbokat_hangar.png"))
    preview.convert("RGB").save(OUT / "hangar_preview.jpg", quality=88)
    print("wrote", svg_path.name, "hangar.jpg", "turbokat_hangar.png", "hangar_preview.jpg")


if __name__ == "__main__":
    main()
