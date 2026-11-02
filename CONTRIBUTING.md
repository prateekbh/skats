# Contributing

Thanks for helping build SWAT Kats: Megakat Skies. This is an unofficial, non-commercial fan
game, so a few ground rules keep it safe to share.

## Ground rules

- **No copyrighted material from the show.** No screenshots, frames, audio, music or official
  art in pull requests. Write new dialogue yourself and make art, models and sound from scratch
  or in code. (The few fan-use assets already in the repo are listed in the README credits and
  are not a precedent for adding more.)
- **Credit your sources.** Anything taken from swatkats.info or another source goes in `CREDITS.md`.
- **Stay canon.** Names, weapons, villains and story beats should match the show; the
  reference is <https://swatkats.info/>. If you can't check a detail, say so in the PR.
- **Web first.** The game ships as a single-threaded WebGL2 build. Avoid per-frame allocations,
  real-time shadows and per-shot nodes; use the pooled `VFX` system and MultiMeshes (see `CLAUDE.md`).

## Getting set up

1. Install [Godot 4.7](https://godotengine.org/) (standard build, no .NET).
2. Clone the repo and open the folder in Godot, or run `godot --path .`. Press **F5** to play.
3. No other dependencies: everything visual is generated in code, apart from the committed assets.

## Before you open a pull request

```bash
tools/check.sh
```

runs the import, the episode-folder check, a 30 s autopilot smoke test, both ends of the boss
fight and the city flight test (`tools/check.sh quick` skips the slow ones). CI runs the smoke
test and deploys `main` to GitHub Pages.

For anything you can see, attach a screenshot. The repo has headless helpers for that, listed in
`CLAUDE.md` (`--viewshot`, `--showcase`, `--comicshow`, `--jetview`...).

## Where things go

- `episodes/<name>/`: everything specific to one episode (mission, boss, shaders, art, strips).
  See [`episodes/README.md`](episodes/README.md) for how to add one.
- `scripts/`: shared engine code used by every episode (flight, combat, world, UI).
- `docs/ARCHITECTURE.md` has the map of the shared code.

If code is used by two or more episodes it belongs in `scripts/`; if only one, in its folder.

## Style

- GDScript with **tabs**, typed variables and function signatures where practical, `##` doc
  comments on classes and non-obvious functions. `.editorconfig` has the details.
- Keep data (missiles, city layout, dialogue) in data structures, not buried in logic.
- Small, focused pull requests are easier to review than big ones.

## Reporting bugs and proposing features

Use the issue templates. For a new episode, enemy or boss, open an issue first with the show
reference so we can agree on the shape of it before you build.
