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

**Missiles (canon, from https://swatkats.info/entry-type/swat-kats-weapons/)**

| Missile | Canon summary | Gameplay | Flight / trail |
|---|---|---|---|
| Blowtorch (F) | High-explosive guided missile carried aboard the TurboKat | Lock-on homing missile, regenerates | Straight, white smoke |
| Octopus | Signature less-than-lethal missile that captures and restrains a target | Restrained gliders fall; turrets pinned for 8 s | Swimming wave, pink ink |
| Buzz-Saw | Non-explosive spinning saw in a red casing with a shark decal; best against wings; fired as a barrage | One saw per locked target (up to 4); bonus vs gliders; a kill saws the target in two, no explosion | Corkscrew, sparks |
| Scrambler | Million-megavolt discharge that disables electrical systems; lightning-bolt marking | Disables everything within 75 m for 6 s | Lightning zigzag, electric arcs |
| Slicer | Non-explosive bladed missile that penetrates targets | Damages armored targets (the warship hull before its turrets fall); a kill slices the target into five pieces, no explosion | Very fast and dead straight, laser beam |
| Match Head | Explosive-incendiary missile with a match-like ball tip that ignites | Large blast that sets targets burning | Lobbed arc, fire |

Cut pieces are pooled rigs drawn with `shaders/cut_piece.gdshader` (each piece shows one slab of
the model between two cut planes; the open cut glows and cools) and trail sparks, electric
crackle and smoke. Missile hits on buildings deform them (`City.damage_at`: a hit building moves
into a small MultiMesh of subdivided boxes that `building.gdshader` bends into a crater, a lean
and a jagged roofline; roofs are knocked down with rubble, tower tiers snap and lean, and walls
are scorched with burning holes) and start a persistent black smoke column (`VFX.add_smoke_column`). The damage
lasts until the next stage starts (`City.reset_damage`).

Firing a special shows a comic title card and (unless turned off in the pause menu) a ~1 s
slow-motion launch shot from beside the jet, then straight back to play; the camera never chases
the missile (that tested as nauseating). Skippable with any fire button. The HUD shows only the
selected special, as a card with the missile's picture from the show on a flat cockpit weapons
screen; cycling slides the cards across it like a carousel.

Candidates for later episodes: Banshee (sonic, disrupts guidance), Megavolt, Mole (drilling),
Pincer, Spider (needs a canon description), Decoy (countermeasure once enemies fire homing weapons),
and the Wet Cement Machine Gun (less-than-lethal cannon).

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
| 1 | Dark Skies Over Megakat | Dark Kat | Creepling glider waves, then Dark Kat's Fear Ship II (turrets, then the armored hull) | **Playable in v0.1** |
| 2 | Turmoil Rising | Turmoil | Flying-fortress chase through the clouds; boarding drones | Planned |
| 3 | Viper's Swamp | Dr. Viper | Mutated plant tendrils grabbing at the TurboKat over the city; bio-pod weak points | Planned |
| 4 | Pastmaster's Rift | The Pastmaster | Time rift spawns prehistoric fliers; a dragon boss | Planned |
| 5 | Metal Gang | The Metallikats | Robot gangsters in a stolen heavy gunship, with a bank-heist ground strike | Planned |
| 6 | Hard Drive's Blackout | Hard Drive | Fight in a city with the power cut and the HUD glitching | Planned |
| ∞ | Free Flight: Endless Defense | Everyone | Escalating waves, score attack | **Playable in v0.1** |

**Recurring cast (radio):** Razor (weapons, gadgets), T-Bone (pilot), Callie Briggs (deputy
mayor, mission giver), Commander Feral (rival, "stay out of Enforcer business"), Lt. Felina Feral
(capable niece who gives the SWAT Kats the benefit of the doubt), Mayor Manx (cowardly, golf),
Ann Gora (news reporter in the Good Kat Blimp). Characters and their traits follow swatkats.info.

### Episode 1: Dark Skies Over Megakat (three parts)

Dark Kat is cutting the city's head off, piece by piece: Enforcer HQ, then City Hall, then HQ
again with the bomb. Story is told as comic strips (`ComicStrip`, `scripts/missions/ep01_dark_skies.gd`):

| Beat | When | What happens |
|---|---|---|
| **Opening** (6 panels, 2 pages, "Drop Bomb" plays) | After the episode is chosen, before the hatch launch | Ann Gora's news flash from the blimp; Manx on the golf course wants his limo; Feral: "Dark Kat hit this building the day it opened. Two of my pilots stopped him. Best I ever had." (the Enforcer pilots were Chance Furlong and Jake Clawson); T-Bone: not one word, buddy; Callie calls for help from City Hall; Razor answers |
| **Part 1: First Strike** | Creepling gliders over Enforcer HQ | In flight Razor realises they're dragging the Enforcer jets away from HQ. Strip: Feral wants his airspace; Felina sees HQ was bait; Ann's blimp is clipped; Razor: the city's head is coming off piece by piece, and bombers are on radar |
| **Part 2: Breaking News** | Gliders and bombers over City Hall | Callie stays to run the evacuation, Manx hides under his desk. Strip: Dark Kat hijacks every channel, "by dawn this will be Dark Kat City"; Callie: the bomb bay is aimed at the Enforcer building; Ann's camera sees the warship rise from the clouds; Razor: it's a flying fortress |
| **Part 3: Dark Kat City** | The Fear Ship II (turrets, then the armored hull) | Felina flies cover; Dark Kat launches every glider. Epilogue strip: Dark Kat flees; Feral says the SWAT Kats are still under investigation, Felina: "of course they are, Uncle"; Manx takes credit; Ann: who saved us, two pilots nobody can name; Callie thanks them |

The opening can be skipped with Esc. The hatch launch follows it and hands over the controls.

## 6. Enemies (v0.1)

| Enemy | HP | Behaviour |
|---|---|---|
| Creepling Glider | 30 | Fast swarm flyer: patrol, then pursue with lead, break off when close; red bolts |
| Creepling Bomber | 160 | Heavier and slower; 3-shot spread |
| Warship Turret | 220 | Boss part: aims flak bursts at the player |
| Warship Hull | 1400 | Armored until all turrets are down; launches gliders in phase 2 |

## 7. World

**Megakat City** is a 15 x 10 km world (about 150 km2, from the environment handoff) generated from a
small data file, `data/city_plan.json`: water, districts, landmarks, mountain ridges, piers, bridges and
supply caches in a few dozen lines (coordinates in km, sizes in metres). Edit the plan, then look at it
with `--citymap` and measure it with `--citycheck` (see CLAUDE.md); nothing else needs touching.

| District | What it is | Street gaps |
|---|---|---|
| Downtown core | A Manhattan of long blocks and towers of 140-520 m (about 90 over 300 m); MegaKat Tower (~1,200 m, 300 storeys) and City Hall (~250 m, working clock) | 45-80 m, avenues 100-140 m |
| Commercial high-rise | Glass towers of 120-480 m, podium towers, twin towers with sky-bridges, round towers | 45-80 m |
| Civic + Enforcer | Stone civic blocks around Enforcer HQ (~300 m, shield emblem) | 50-85 m |
| Residential | Brick mid-rise (25-110 m) with rows of houses | 40-65 m |
| Suburb | Packed rows of houses with gardens and trees | 32-52 m |
| Industrial waterfront + docks | Warehouses, factories, container yards, piers with gantry cranes and ships | 40-65 m |
| Salvage yard | Jake & Chance's Garage (two-storey) in a scrapyard; the hangar hatch is below | 45-75 m |
| Park | A large open meadow with a lake and tree groves: a combat arena | none |
| Outer wilds | Mountain ridges, a river with a dam, wetlands, beaches, islands, a lighthouse, the open sea | none |

- **Density and flyability:** the handoff's gaps (60-100 m, 100-160 m for skyscrapers) played too relaxed,
  so the streets are tighter: 32-85 m, with wider avenues every few streets, in long Manhattan-style
  blocks. The grid is continuous, so there are always several routes and no dead ends; `--flytest` flies
  every district's narrowest street and widest avenue on the real controller. Open plazas are rare.
  Buildings stay inset from district borders so two districts never pinch a street.
- **Bridges:** three high bridges (deck 95 m up, pylons on the banks, piers at the ends) cross the river.
  The deck is solid, so flying through it crashes, but the river beneath is a clear corridor.
- **Looks:** twelve facade styles (glass curtain wall, art-deco stone, brick, concrete, industrial,
  house, civic limestone, painted metal, containers, neon signs...) and about a dozen building types
  built from boxes, cylinders, gable roofs and cones, with district palettes, rooftop props and street
  lamps. One shader draws all of it; windows are laid out in each part's own metres.
- **Terrain:** a real height-mapped terrain (sea floor, shores, beaches, ridges up to 700 m, wetlands)
  with a water plane at 0. Land fades to sea past the playable edge.
- **Collision:** a 20 m height grid, so podiums, setbacks and mountains all count, plus a grid saying which
  building owns each cell. `height_at()` is a lookup; there are no physics bodies.
- **Damage:** a missile hit knocks a roof down with rubble, snaps and tilts a narrower crown, or blasts a
  burning, bent hole in a wall; the building moves into a MultiMesh of subdivided boxes that the shader
  bends. Thick smoke columns rise and the damage lasts until the next stage.
- **Supply caches:** about fifty light-beam caches on streets, plazas, piers and in the park hold special
  missiles (two types, +2 each), a Blowtorch pack or repair; collect one by flying within 26 m and under
  40 m above it. In Free Flight about a third are guarded by flak nests; Episode 1 is planes only (the
  mission opts out with `ground_guards()`). They refill after 60 s and show on the radar.
- Landmark geometry is generated from the handoff's proposed proportions; check the silhouettes against
  series frames before polishing (only the 300-storey MegaKat Tower is a canon anchor).

Collisions use custom math (height grid plus spheres and capsules) instead of physics bodies:
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
