#!/usr/bin/env python3
"""Convert the Thingiverse TurboKat STLs into painted, game-ready GLB models.

Source: "TurboKat from Swat Kats Fixed STL" by RabbitXGT (thing:4500382), a fix of
Captain_Ahab_62's model. CC-BY. See assets/turbokat/source/.

The STLs are single uncoloured print meshes, so each triangle is assigned a paint
region (body, cockpit, glass, engine, nozzle, stripe) from its position and normal.
Godot replaces each region's material by name with the cel-shaded palette in
scripts/player/turbokat_model.gd, so only the names matter here.

Usage:  python3 tools/convert_turbokat.py      (needs: pip install trimesh scipy shapely)
Writes: assets/turbokat/turbokat_swept.glb, assets/turbokat/turbokat_open.glb
"""
from pathlib import Path

import numpy as np
import trimesh

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets" / "turbokat" / "source"
OUT = ROOT / "assets" / "turbokat"

LENGTH = 22.0          # metres nose-to-tail in game (matches the flight model)
NOSE_X, TAIL_X = 2.13, 106.18  # STL x extents (nose at low x)
SCALE = LENGTH / (TAIL_X - NOSE_X)
MID_X = (NOSE_X + TAIL_X) * 0.5

# Engine nozzle centres in STL units (y = ±ENGINE_Y, z = ENGINE_Z), radius about 4.
ENGINE_Y, ENGINE_Z, ENGINE_R = 10.9, -1.6, 4.3

# Placeholder colours (Godot swaps these for the real palette by material name).
PREVIEW = {
    "body": (0.08, 0.08, 0.11, 1.0),
    "cockpit": (0.86, 0.1, 0.08, 1.0),
    "glass": (0.28, 0.42, 0.92, 1.0),
    "engine": (0.86, 0.1, 0.08, 1.0),
    "nozzle": (0.05, 0.05, 0.06, 1.0),
    "stripe": (0.2, 0.3, 0.85, 1.0),
}


def split_along(mesh: trimesh.Trimesh, normal, origin) -> trimesh.Trimesh:
    """Cuts every triangle crossing a plane so paint boundaries there come out straight."""
    a = trimesh.intersections.slice_mesh_plane(mesh, normal, origin)
    b = trimesh.intersections.slice_mesh_plane(mesh, -np.asarray(normal, dtype=float), origin)
    return trimesh.util.concatenate([a, b])


def prepare(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    """Pre-cuts the mesh at the paint boundaries used by classify()."""
    span = np.abs(mesh.vertices[:, 1]).max()
    for side in (-1.0, 1.0):
        mesh = split_along(mesh, [0, side, 0], [0, side * span * 0.8, 0])
    for t in (0.045, 0.12, 0.6, 0.72):
        mesh = split_along(mesh, [1, 0, 0], [NOSE_X + t * (TAIL_X - NOSE_X), 0, 0])
    return mesh


def classify(mesh: trimesh.Trimesh) -> np.ndarray:
    """Returns a region name per face, using STL coordinates (x back, y side, z up)."""
    c = mesh.triangles_center
    n = mesh.face_normals
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    ay = np.abs(y)
    t = (x - NOSE_X) / (TAIL_X - NOSE_X)  # 0 at the nose, 1 at the tail
    region = np.full(len(c), "body", dtype=object)
    up = n[:, 2] > 0.45
    span = ay.max() + 1e-3

    # Paint scheme follows the show's hangar shot: glossy black airframe, red cockpit pod
    # with royal-blue glass, red panels beside the cockpit and on the wing roots,
    # royal-blue panels near the wingtips, a blue nose tip, red engine pods.

    # Royal-blue panels on the outer wings (top and bottom) and the very tips.
    region[(ay > span * 0.8) & (z < 6.0) & (np.abs(n[:, 2]) > 0.45)] = "stripe"
    region[ay > span * 0.93] = "stripe"

    # Red panels: flanking the cockpit along the chines, and a strip on each wing root.
    region[up & (t > 0.3) & (t < 0.56) & (ay > 6.2) & (ay < 12.5) & (z < 9.0)] = "cockpit"
    region[up & (t > 0.6) & (t < 0.72) & (ay > 13.0) & (ay < 21.0) & (z < 6.0)] = "cockpit"

    # Engine housings: the round pods either side of the tail.
    r_eng = np.hypot(ay - ENGINE_Y, z - ENGINE_Z)
    engine = (t > 0.8) & (r_eng < ENGINE_R + 1.6) & (z < 4.0)
    region[engine] = "engine"
    # Nozzle faces (rear-facing, inside the ring) go dark; Godot adds turbines and flames there.
    region[engine & (n[:, 0] > 0.6) & (r_eng < ENGINE_R - 0.6)] = "nozzle"

    # Cockpit pod: the raised hump behind the nose, painted red.
    pod = (t > 0.12) & (t < 0.52) & (ay < 6.8) & (z > 1.5)
    region[pod] = "cockpit"
    # Canopy glass: the upward- and outward-facing panels high on the hump.
    glass = pod & (t > 0.16) & (t < 0.48) & (z > 3.2) & ((n[:, 2] > 0.3) | (np.abs(n[:, 1]) > 0.4)) & (ay < 6.2)
    region[glass] = "glass"

    # Blue nose tip.
    region[t < 0.045] = "stripe"
    return region


def to_godot(vertices: np.ndarray) -> np.ndarray:
    """STL (x back, y side, z up) -> Godot (x right, y up, -z forward), scaled and centred."""
    v = np.empty_like(vertices)
    v[:, 0] = vertices[:, 1] * SCALE
    v[:, 1] = vertices[:, 2] * SCALE
    v[:, 2] = (vertices[:, 0] - MID_X) * SCALE
    return v


def convert(stl_name: str, out_name: str) -> None:
    mesh = prepare(trimesh.load(SRC / stl_name, force="mesh"))
    regions = classify(mesh)
    scene = trimesh.Scene()
    for name, rgba in PREVIEW.items():
        idx = np.nonzero(regions == name)[0]
        if len(idx) == 0:
            continue
        part = mesh.submesh([idx], append=True)
        part.vertices = to_godot(part.vertices)
        part.visual = trimesh.visual.TextureVisuals(
            material=trimesh.visual.material.PBRMaterial(name=name, baseColorFactor=rgba, metallicFactor=0.4, roughnessFactor=0.5)
        )
        scene.add_geometry(part, node_name=name, geom_name=name)
        print(f"  {out_name}: {name:8s} {len(idx):5d} faces")
    scene.export(OUT / out_name)


if __name__ == "__main__":
    convert("FIX_turbokat_swept.stl", "turbokat_swept.glb")
    convert("FIX_turbokat_open.stl", "turbokat_open.glb")
    # Engine nozzle centres in game space, for turbokat_model.gd.
    for side in (-1, 1):
        p = to_godot(np.array([[TAIL_X, side * ENGINE_Y, ENGINE_Z]]))[0]
        print(f"  nozzle {side:+d}: Vector3({p[0]:.2f}, {p[1]:.2f}, {p[2]:.2f})")
