# Architecture

A short map for new contributors. The project is plain GDScript on Godot 4.7 (Compatibility
renderer, web first); nearly everything visual is generated in code.

## Folders

| Path | What lives there |
|---|---|
| `episodes/<name>/` | One self-contained folder per episode (see `episodes/README.md`) |
| `scripts/main.gd` | Entry point and state machine (title, intro, playing, debrief) plus the headless test tools |
| `scripts/autoload/` | `Game` (input map, settings, saves, episode list), `Sfx` (synthesized audio), `Music`, `WebLauncher` (bridge to the HTML title page) |
| `scripts/player/` | TurboKat flight model, procedural fallback model, chase camera |
| `scripts/combat/` | `Combat` (bullets, lasers, missiles, pickups), `Target` base class, `Arsenal` (missile data), supply caches |
| `scripts/enemies/` | Enemies shared between episodes: Creepling gliders and bombers, ground flak |
| `scripts/missions/mission.gd` | The `Mission` base class every episode extends |
| `scripts/world/` | Megakat City: `CityPlan` (data to raster), `CityBuildings`, `CityLandmarks`, `City` |
| `scripts/ui/` | HUD, menus, comic strips and radio cards (all built in code) |
| `scripts/fx/` | Pooled cartoon effects (`VFX`) |
| `shaders/` | Shared shaders: buildings, ground, water, clouds, cel shading |
| `data/` | Data the code reads (`city_plan.json`) |
| `assets/` | Fonts, UI art, the TurboKat model, music |
| `tools/` | Python generators for art, and `check.sh` |
| `web/` | The HTML shell (comic-page launcher) and its art |

## How a game runs

`main.gd` builds the world (sky, city, `Combat`, player, camera, HUD), then `start_episode()`
loads the chosen episode's `mission.gd` and calls `Mission.start()`. Each frame the mission's
`update()` decides what happens next (spawn a wave, play a cutscene, spawn the boss, win or fail).

## Combat in one paragraph

Everything shootable is a `Target` registered with `Combat` (hit tests are spheres or custom).
Bullets, lasers and missiles are plain data stepped by `Combat` and drawn with MultiMeshes;
missile behaviours are data in `Arsenal` and applied in `Combat._missile_hit`. A target can hook
in with `missile_struck(def, point)` (return true to absorb a hit) and `scrambled(def)`; Episode 1's
shielded boss uses both.

## Rules of thumb

- Shared code must not mention a specific episode. If an episode needs a behaviour, add a small
  generic hook in `scripts/` and implement it in the episode's folder.
- Keep per-frame work allocation-free; pool anything spawned in combat.
- Prefer data over code for content (missiles, city plan, dialogue arrays).
