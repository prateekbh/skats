# SWAT Kats: Megakat Skies

Unofficial, non-commercial SWAT Kats fan game. Godot 4.7, GDScript, web-first (Compatibility renderer,
single-threaded web export). See `README.md` for layout and `docs/GDD.md` for design.

## Canon reference

- **https://swatkats.info/** is the reference for everything SWAT Kats (the weapons catalogue is
  https://swatkats.info/entry-type/swat-kats-weapons/; missiles are data in `scripts/combat/arsenal.gd`): characters, villains,
  episodes, the TurboKat and its weapons. When adding or changing weapons, missile types, gadgets,
  enemies or story beats, look them up there and match the show (names, behaviour, colours).
  If the site isn't reachable from your environment, ask the user for the relevant page or
  details instead of guessing.
- Visual references the user supplied: the TurboKat paint scheme follows the show's hangar shot
  (glossy black, red cockpit pod with royal-blue glass, blue wingtips and nose, red engines);
  the launch follows the show (trapdoor opens, jet emerges nose-up at speed, no hover).

## Working here

- Run the checks before pushing:
  `godot --headless --path . --import` then `godot --headless --path . -- --autotest --god --seconds=30`.
  CI (`.github/workflows/web.yml`) runs the same smoke test, exports for web and deploys to Pages.
  `--autotest --god --weapons` fires every special missile at targets and prints the result
  (the missile cam is skipped in autotests; add `--mcam` to include it, and `--shots=<dir>` under
  xvfb to photograph it).
- Screenshots need a display: `xvfb-run godot --path . --rendering-driver opengl3 -- --showcase=<dir>`
  (TurboKat angles), `--fxshow=<dir>` (explosion/effect stages), `--weaponshow=<dir>` (missile models
  and effects), `--snap=<file> [--intro --snap-at=<s>]`
  (title or intro frames).
- Everything visual is generated in code or by the scripts in `tools/` (re-run them, don't hand-edit
  their outputs): `convert_turbokat.py` (3D model and paint), `prepare_launch_art.py` (launch-screen
  cut-outs, portraits and the traced logo).
- Keep the web budget in mind: one MultiMesh per bullet type, no real-time shadows, and no nodes
  created per shot or per explosion. Effects go through the pooled `VFX` system
  (`scripts/fx/vfx.gd`, one MultiMesh per effect type); missile bodies are pooled in `Combat`.
- The TurboKat is cel-shaded with `shaders/cel.gdshader` plus an ink-outline hull exported by the
  converter (crease-angle normals for the paint regions, fully smooth normals for the outline).
- The launch screen is `web/shell.html` (a custom Godot HTML shell); its art and music live in
  `web/launch/` and are copied next to `index.html` by CI.
