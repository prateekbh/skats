# SWAT Kats: Megakat Skies — Game Design Document

> Unofficial, non-commercial fan game. SWAT Kats: The Radical Squadron and all related
> characters, names and marks belong to their owners (Hanna-Barbera / Warner Bros. Discovery).
> This project is not affiliated with or endorsed by them. Code is MIT; no official assets
> (art, audio, music, video, scripts) are included or may be added to the repository.

## 1. Vision

**One line:** Be Razor and T-Bone in the TurboKat for a "season" of episode-style missions:
arcade flight, dogfights, gadget missiles and giant set-piece bosses over Megakat City.

**Feel targets**
- *Ace Combat* arcade flight: easy to fly, hard to master, no stalls that punish beginners.
- *Saturday-morning episode* pacing: cold open, briefing, villain attack, boss, cheeky outro.
- *Cel-shaded cartoon* look, generated in code (no art team) and readable at 60 fps in a browser.

| Decision | Choice | Why |
|---|---|---|
| Engine | Godot 4.7 (MIT) | Fully open source, strong web export |
| Renderer | Compatibility (WebGL 2) | The only renderer Godot exports to the web |
| Platform | Web first (itch.io / GitHub Pages); desktop builds for free | Single-threaded export, no special server headers |
| Team | 1 human + Claude | Everything procedural: meshes, shaders, synthesized SFX |
| Mode | Single-player | Keeps scope realistic |

## 2. Core loop

```
Episode select → Briefing (story card) → Launch cinematic
   → Waves (dogfight) → Radio story beats → Boss (weak points)
   → Outro banter → Debrief (score, rank, unlocks) → next episode
```

## 3. Player: the TurboKat

**The jet is the game's personality**, so its model gets the most detail budget. It follows the show's design:
a flat black faceted arrowhead body, a raised red cockpit pod with light-blue window panels split by red frames,
red slit panels, lavender-blue leading-edge stripes, two big round rear engines (red housings, white turbine
rings, spinning fan blades), hooked forward blades, and twin canted tails. It's cel-shaded with ink outlines and a
rim light so the black airframe reads at dusk. Underwing missiles disappear as the magazine empties.
Source: `scripts/player/turbokat_model.gd` (all colours are constants at the top of the file).

| System | Spec (prototype values, tune in `scripts/player/turbokat.gd`) |
|---|---|
| Flight | Arcade 6-DOF; auto-coordinated turns when banked; gentle auto-level when roll is released |
| Speed | 35–360 m/s; throttle 0–100%; diving speeds you up, climbing slows you down |
| Afterburner | Boost meter: drains 28/s, refills 10/s |
| Cannon | Twin guns, 16 rds/s, heat builds and overheats; light aim-assist near the reticle |
| Missiles | Lock-on (0.65 s in a 12° cone, 1.2 km); homing; regenerate 1 per 6 s, max 16 |
| Mega-Missile | Special, 3 per sortie, large blast radius. Later episodes swap in other gadget missiles |
| Hull | 100 HP; repair pickups dropped by enemies |
| Cameras | Chase / far chase / cockpit (C) |

**Gadget missile roadmap** (one unlocked per episode, inspired by the show's arsenal):
Octopus (grabs and stuns), Cement (freezes a target in place), Spider (net that clips wings),
Scrambler (jams turrets), Buzzsaw (cuts through armor). The Mega-Missile ships in v0.1.

## 4. Controls

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Pitch | ↑ / ↓ | Left stick Y |
| Roll | ← / → | Left stick X |
| Yaw (rudder) | A / D | Right stick X |
| Throttle | W / S | RT / LT |
| Afterburner | Shift | RB |
| Cannon | Space / Left mouse | A |
| Missile | F / Right mouse | B |
| Special missile | R | X |
| Camera | C | Y |
| Invert pitch | Y | — |
| Mute | M | — |
| Pause | Esc / P | Start |

## 5. Season 1: episodes

Missions are **inspired by** the show's villains and situations. All mission dialogue is
written fresh for this project; no lines are copied from the series.

| # | Working title | Villain | Set piece | Status |
|---|---|---|---|---|
| 1 | Dark Skies Over Megakat | Dark Kat | Creepling glider waves, then Dark Kat's warship (turrets, then the armored hull) | **Playable in v0.1** |
| 2 | Turmoil Rising | Turmoil | Flying-fortress chase through the clouds; boarding drones | Planned |
| 3 | Viper's Swamp | Dr. Viper | Mutated plant tendrils grabbing at the TurboKat over the city; bio-pod weak points | Planned |
| 4 | Pastmaster's Rift | The Pastmaster | Time rift spawns prehistoric fliers; a dragon boss | Planned |
| 5 | Metal Gang | The Metallikats | Robot gangsters in a stolen heavy gunship, with a bank-heist ground strike | Planned |
| 6 | Hard Drive's Blackout | Hard Drive | Fight in a city with the power cut and the HUD glitching | Planned |
| ∞ | Free Flight: Endless Defense | Everyone | Escalating waves, score attack | **Playable in v0.1** |

**Recurring cast (radio):** Razor (weapons, gadgets), T-Bone (pilot), Callie Briggs (deputy
mayor, mission giver), Commander Feral (rival, "stay out of Enforcer business").

## 6. Enemies (v0.1)

| Enemy | HP | Behaviour |
|---|---|---|
| Creepling Glider | 30 | Fast swarm flyer: patrol, then pursue with lead, break off when close; red bolts |
| Creepling Bomber | 160 | Heavier and slower; 3-shot spread |
| Warship Turret | 220 | Boss part: aims flak bursts at the player |
| Warship Hull | 1400 | Armored until all turrets are down; launches gliders in phase 2 |

## 7. World

Procedural **Megakat City** (28×28 blocks, about 2.5 km across):
- A world-space window shader keeps window size constant on any building height; lit windows are randomized per building.
- A downtown height falloff, so the skyline peaks at City Hall and Enforcer HQ.
- The bay to the east and mountains on the horizon, under a dusk sky with fog and glow.
- The salvage yard to the west (the hidden hangar) is where every sortie launches.
- Buildings collapse when bosses walk through them (the API exists; Viper's and Pastmaster's bosses will use it).

Collisions use custom math (height field plus spheres and capsules) instead of physics bodies:
cheap on the web and deterministic.

## 8. Presentation

- **HUD:** green jet-HUD reticle, target brackets, lock diamond, off-screen arrows, radar, hull/boost/heat bars,
  KTS and FT readouts, PULL UP / OVERHEAT / RETURN warnings.
- **Radio subtitles** with a speaker name, queued.
- **Audio:** all SFX synthesized at startup (engine loop, guns, booms, lock tones). Original music is planned.
- **Debrief:** score, kills, accuracy, time, hull, rank S/A/B/C, best score saved in browser storage.

## 9. Technical architecture

```
scenes/main.tscn            → scripts/main.gd  (state machine: MENU / PLAYING / PAUSED / DEBRIEF)
scripts/autoload/game.gd    input map (built in code), settings, save data, episode list
scripts/autoload/sfx.gd     procedural sound synthesis + player pool
scripts/world/city.gd       Megakat City generator + height_at() collision query
scripts/player/turbokat.gd  flight model, weapons, lock-on
scripts/player/turbokat_model.gd  procedural TurboKat mesh
scripts/player/chase_camera.gd    chase/cockpit/cinematic camera, shake
scripts/combat/combat.gd    bullets (MultiMesh), missiles, explosions, pickups, target registry
scripts/combat/target.gd    base class for anything that can be shot
scripts/enemies/*.gd        enemy AI + procedural models
scripts/missions/*.gd       one script per episode, extends Mission
scripts/ui/hud.gd, menu.gd  HUD drawn with _draw(); menus built in code
shaders/*.gdshader          buildings, ground, water
```

**Adding an episode:** create `scripts/missions/epNN_name.gd` extending `Mission`, implement
`start()`, `update(dt)` and `objective()`, then add an entry to `Game.EPISODES`.

**Performance budget (web):** at most 60 live targets, at most 600 bullets (2 MultiMesh draws),
CPU particles only, no real-time shadows, about 1,000 building instances in one MultiMesh.

## 10. Roadmap

| Milestone | Content |
|---|---|
| **v0.1 prototype** (this) | Flight, guns, missiles, lock-on, Ep 1, Free Flight, HUD, menus, synthesized SFX, web export CI |
| v0.2 feel pass | Tuning, gamepad rumble, hit-stop, better explosions, original music loop, touch controls |
| v0.3 Ep 2–3 | Turmoil's fortress, Viper's tendril boss, the first two gadget missiles, building destruction |
| v0.4 hangar | Salvage-yard hub, loadout selection, upgrade tree |
| v0.5 Ep 4–6 | Remaining villains, the season finale |
| v1.0 | Polish, accessibility options, localization, voiced radio (fan VO, volunteer) |
