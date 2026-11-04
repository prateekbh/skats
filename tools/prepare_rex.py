#!/usr/bin/env python3
"""Turns the downloaded Tyrannosaurus rex (tools/model_src/tyrannosaurus_rex.glb, CC-BY 4.0,
"Tyrannosaurus rex" by IagoMendez on Sketchfab) into the Episode 2 boss mesh:

  episodes/ep02_the_pastmaster_always_rings_twice/models/rex.glb

- keeps only positions, normals and triangles (no textures: the game cel-shades it),
- turns it to face -Z (Godot forward) with its feet at y = 0,
- bakes vertex colours in darker green shades, taken from the original skin texture's light and
  dark (so its stripes and scales still read), a paler olive belly, and ivory teeth and claws.

Run from the repo root:  python3 tools/prepare_rex.py   (needs numpy and pillow)
"""
import io
import json
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

SRC = Path("tools/model_src/tyrannosaurus_rex.glb")
OUT = Path("episodes/ep02_the_pastmaster_always_rings_twice/models/rex.glb")

DARK = np.array([0.07, 0.16, 0.07])
MID = np.array([0.20, 0.36, 0.15])
LIGHT = np.array([0.30, 0.48, 0.20])
BELLY = np.array([0.40, 0.48, 0.22])
IVORY = np.array([0.92, 0.88, 0.74])


def read_glb(path):
    d = path.read_bytes()
    jlen = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jlen])
    b0 = 20 + jlen
    blen = struct.unpack("<I", d[b0:b0 + 4])[0]
    return j, d[b0 + 8:b0 + 8 + blen]


def accessor(j, binary, index):
    a = j["accessors"][index]
    bv = j["bufferViews"][a["bufferView"]]
    dtype = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
    n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    size = np.dtype(dtype).itemsize
    stride = bv.get("byteStride", 0) or n * size
    raw = np.frombuffer(binary, dtype=np.uint8, count=stride * (a["count"] - 1) + n * size, offset=off)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], n * size), strides=(stride, 1))
    return np.ascontiguousarray(rows).view(dtype).reshape(a["count"], n)


def image(j, binary, index):
    bv = j["bufferViews"][j["images"][index]["bufferView"]]
    off = bv.get("byteOffset", 0)
    return Image.open(io.BytesIO(binary[off:off + bv["byteLength"]])).convert("RGB")


def write_glb(path, pos, nrm, col, idx):
    blobs = [pos.astype("<f4").tobytes(), nrm.astype("<f4").tobytes(), col.astype("<f4").tobytes(), idx.astype("<u4").tobytes()]
    views, offset = [], 0
    for b in blobs:
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(b)})
        offset += (len(b) + 3) // 4 * 4
    binary = b"".join(b + b"\0" * ((4 - len(b) % 4) % 4) for b in blobs)
    j = {
        "asset": {"version": "2.0", "generator": "tools/prepare_rex.py",
                  "copyright": "Tyrannosaurus rex by IagoMendez (Sketchfab), CC-BY 4.0; recoloured for SWAT Kats: Megakat Skies"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": "Rex", "mesh": 0}],
        "meshes": [{"name": "Rex", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "COLOR_0": 2}, "indices": 3}]}],
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": views,
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": pos.min(0).tolist(), "max": pos.max(0).tolist()},
            {"bufferView": 1, "componentType": 5126, "count": len(nrm), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(col), "type": "VEC4"},
            {"bufferView": 3, "componentType": 5125, "count": len(idx), "type": "SCALAR"},
        ],
    }
    js = json.dumps(j).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(binary)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
                     + struct.pack("<I4s", len(binary), b"BIN\0") + binary)


def main():
    j, binary = read_glb(SRC)
    prim = j["meshes"][0]["primitives"][0]
    pos = accessor(j, binary, prim["attributes"]["POSITION"]).astype(np.float64)
    nrm = accessor(j, binary, prim["attributes"]["NORMAL"]).astype(np.float64)
    idx = accessor(j, binary, prim["indices"]).reshape(-1)
    mat = j["materials"][prim.get("material", 0)]
    tex = mat["pbrMetallicRoughness"]["baseColorTexture"]
    uv = accessor(j, binary, prim["attributes"]["TEXCOORD_%d" % tex.get("texCoord", 0)])
    img = np.asarray(image(j, binary, j["textures"][tex["index"]]["source"]), dtype=np.float64) / 255.0
    h, w, _ = img.shape
    px = img[np.clip((uv[:, 1] % 1.0) * h, 0, h - 1).astype(int), np.clip((uv[:, 0] % 1.0) * w, 0, w - 1).astype(int)]
    lum = px @ np.array([0.299, 0.587, 0.114])
    sat = px.max(1) - px.min(1)
    # The source has its head toward +Z: turn it round to face -Z.
    pos[:, 0] *= -1.0
    pos[:, 2] *= -1.0
    nrm[:, 0] *= -1.0
    nrm[:, 2] *= -1.0
    pos[:, 1] -= pos[:, 1].min()
    # Skin: the texture's light and dark mapped onto a dark-to-mid green ramp.
    t = np.clip((lum - np.percentile(lum, 5)) / max(np.percentile(lum, 95) - np.percentile(lum, 5), 1e-6), 0, 1)[:, None]
    col = np.where(t < 0.5, DARK + (MID - DARK) * (t / 0.5), MID + (LIGHT - MID) * ((t - 0.5) / 0.5))
    # Paler olive underside (belly, throat, under the tail).
    under = np.clip((-nrm[:, 1] - 0.2) / 0.4, 0, 1)[:, None]
    col = col + (BELLY - col) * under * 0.85
    # Teeth and claws: bright, unsaturated texels.
    # Only in the jaws (front of the head) and at the toe tips, so pale skin patches stay green.
    head = pos[:, 2] < pos[:, 2].min() + 2.2
    toes = pos[:, 1] < 0.35
    teeth = ((lum > np.percentile(lum, 93)) & (sat < 0.2) & (head | toes))[:, None]
    col = np.where(teeth, IVORY, col)
    rgba = np.hstack([col, np.ones((len(col), 1))])
    write_glb(OUT, pos.astype(np.float32), nrm.astype(np.float32), rgba.astype(np.float32), idx.astype(np.uint32))
    print("wrote %s: %d vertices, %d triangles, %.0f KB" % (OUT, len(pos), len(idx) // 3, OUT.stat().st_size / 1024))


if __name__ == "__main__":
    sys.exit(main())
