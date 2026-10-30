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
  (the missile launch shot is skipped in autotests; add `--mcam` to include it, and `--shots=<dir>` under
  xvfb to photograph it).
- Screenshots need a display: `xvfb-run godot --path . --rendering-driver opengl3 -- --showcase=<dir>`
  (TurboKat angles), `--fxshow=<dir>` (explosion/effect stages), `--weaponshow=<dir>` (missile models,
  effects, Slicer / Buzz-Saw cuts and building damage), `--snap=<file> [--intro --snap-at=<s>]`
  (title or intro frames).
- Everything visual is generated in code or by the scripts in `tools/` (re-run them, don't hand-edit
  their outputs): `convert_turbokat.py` (3D model and paint), `prepare_launch_art.py` (launch-screen
  cut-outs, portraits and the traced logo), `render_launch_art.py` (the launcher's TurboKat and
  city shots, rendered by the game with `--jetrender` / `--weaponshow`), `fetch_missile_art.py`
  (HUD missile cards from the swatkats.info missile catalogue), `fetch_character_art.py`
  (character portraits with expressions and cutscene panels from swatkats.info show frames).
- Story is told with comic elements (`scripts/ui/comic.gd` shares the look): `RadioCard` on the HUD
  (`Mission.radio(who, text, seconds, mood)`) and `ComicStrip` cutscenes between waves
  (`Mission.cutscene(panels, then)`, game paused). New speakers or moods go in `Comic.SPEAKERS` and
  `fetch_character_art.py`. Autotests skip cutscenes unless `--comic`; `--launch` starts an autotest
  through the hatch launch.
- Keep the web budget in mind: one MultiMesh per bullet type, no real-time shadows, and no nodes
  created per shot or per explosion. Effects go through the pooled `VFX` system
  (`scripts/fx/vfx.gd`, one MultiMesh per effect type); missile bodies are pooled in `Combat`.
- The TurboKat is cel-shaded with `shaders/cel.gdshader` plus an ink-outline hull exported by the
  converter (crease-angle normals for the paint regions, fully smooth normals for the outline).
- The launcher is `web/shell.html` (a custom Godot HTML shell): a comic-book page that is the web
  title screen. The game loads behind it; `scripts/autoload/web_launcher.gd` hands it the episodes
  and settings and receives launches (`window.skGameLaunch`) and setting changes. Desktop builds and
  autotests use the in-game menu instead. The hatch launch plays after a stage is chosen.
  Its art and music live in `web/launch/` and are copied next to `index.html` by CI.
