# Episodes

One folder per episode. A folder holds **everything only that episode uses**; code and assets
used by several episodes live in the shared `scripts/`, `shaders/` and `assets/`.

```
episodes/
  ep01_dark_skies/
    episode.gd         menu card + briefing (id, title, villain, story, objectives)
    mission.gd         the mission: waves, boss, radio lines, comic strips (extends Mission)
    dark_kat_jet.gd    the final boss (only this episode uses it)
    shield.gdshader    the boss's shield effect
  ep02_turmoil_rising/ episode.gd only: a "coming soon" card
  free_flight/         endless waves
```

## Adding an episode

1. Create `episodes/epNN_name/` with an `episode.gd`:

   ```gdscript
   extends RefCounted

   func info() -> Dictionary:
   	return {
   		"id": "ep04", "number": "Episode 4", "title": "...", "villain": "...",
   		"playable": true, "story": "...", "objectives": ["...", "..."],
   	}
   ```

2. Add `mission.gd` next to it, extending `Mission` (`scripts/missions/mission.gd`). Implement
   `start()`, `update(dt)` and `objective()`; use the helpers `spawn_wave()`, `radio()`, `after()`,
   `cutscene()`, `message()`, `win()` and `fail()`. Put the comic strips in a `strips()` function
   and the opening in `intro()`; Episode 1's mission is a full example.
3. Register the folder name in `Game.EPISODE_FOLDERS` (`scripts/autoload/game.gd`), the one line
   outside the folder.
4. Bosses, enemies, shaders and art only your episode uses go in the folder. Reference them with
   full `res://episodes/...` paths. Reuse shared pieces (Creeplings, the arsenal, the city) from `scripts/`.
5. If you need a shared thing changed (a new missile, a `Target` hook), change it in `scripts/`
   and keep it generic, as Episode 1's shield did with `Target.lock_through_armor`.
6. Run `tools/check.sh`. `--autotest --episode=<id>` autopilots your episode.

Handy test switches (see `CLAUDE.md`): `--autotest --god --episode=<id>`, `--launch`, `--comic`.
