# TurboKat model

`turbokat_swept.glb` and `turbokat_open.glb` are the TurboKat airframe in its two wing poses.
The game swaps between them with airspeed (`scripts/player/turbokat.gd`, `SWEEP_AT` / `SPREAD_AT`).

They are generated from the STL files in `source/` by:

```bash
pip install trimesh scipy shapely
```

```bash
python3 tools/convert_turbokat.py
```

The converter turns the model to Godot's axes, scales it to 22 m and paints it region by region
(body, cockpit, glass, engine, nozzle, stripe). Godot swaps each region for the cel-shaded
palette in `scripts/player/turbokat_model.gd`. To repaint the jet, edit `classify()` in the
converter, or the colour constants in the model script.

## Credits

"TurboKat from Swat Kats Fixed STL" by **RabbitXGT**
(https://www.thingiverse.com/thing:4500382), a fix of the original model by **Captain_Ahab_62**,
licensed under **Creative Commons Attribution** (CC BY). Changes: converted to glTF, re-oriented,
scaled, cut along paint lines and painted.
