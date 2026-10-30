class_name Arsenal
extends RefCounted
## The TurboKat's missiles, as data. Homing missiles are on F; the special rack is cycled
## with Q (gamepad LB) and the selected missile fired with R (gamepad X).
##
## Every missile here is canon, from the SWAT Kats weapons catalogue at
## https://swatkats.info/entry-type/swat-kats-weapons/ (see CLAUDE.md). The quoted
## summaries below are from each entry; the gameplay behaviour is our interpretation.
##
## Behaviours implemented in Combat._missile_hit / TurboKat._fire_special:
##   "homing"  guided high explosive
##   "capture" restrains the target: gliders fall out of the sky, turrets are pinned
##   "barrage" fires one missile per locked target (up to `volley`), non-explosive saw hits
##   "scramble" electrical discharge that disables every target within `radius`
##   "pierce"  damages armored targets too
##   "blast"   explosion that damages everything within `radius` and sets targets burning
##
## Each missile also flies its own way so it can be told apart at a glance:
##   path:  "straight", "undulate" (swimming wave), "spiral" (corkscrew), "zigzag" (lightning),
##          "laser" (very fast, dead straight), "arc" (lobbed onto the target)
##   trail: "smoke", "ink", "sparks", "electric", "beam", "fire"

## Blowtorch Missile: "High explosive guided missile carried aboard the Turbokat."
const HOMING := {
	"id": "blowtorch", "name": "Blowtorch Missile", "behaviour": "homing", "model": "standard",
	"path": "straight", "trail": "smoke",
	"damage": 120.0, "color": Color(0.9, 0.9, 0.92), "size": 1.0, "speed": 560.0, "turn": 2.8,
}

const SPECIALS: Array[Dictionary] = [
	{
		# "Signature weapon of the SWAT Kats. This less-than lethal missile is used to capture
		# and restrain a target."
		"id": "octopus", "name": "Octopus Missile", "behaviour": "capture", "model": "octopus",
		"path": "undulate", "trail": "ink",
		"blurb": "Captures and restrains a target",
		"ammo": 3, "max": 4, "damage": 10.0, "hold": 8.0,
		"color": Color(0.78, 0.2, 0.55), "size": 1.4, "speed": 460.0, "turn": 3.2,
	},
	{
		# "Non-explosive, rocket-propelled projectile that contains a motorized, spinning
		# saw-blade that expands out of a red casing... most effective when used against
		# lines, tethers, propellers and wings... the Turbokat can rapidly fire a barrage of
		# Buzz-Saw Missiles against a multitude of enemy targets."
		"id": "buzzsaw", "name": "Buzz-Saw Missile", "behaviour": "barrage", "model": "buzzsaw",
		"path": "spiral", "trail": "sparks",
		"blurb": "Saw barrage, one per locked target",
		"ammo": 3, "max": 5, "volley": 4, "damage": 110.0, "wing_bonus": 1.6,
		"color": Color(0.85, 0.12, 0.1), "size": 1.0, "speed": 520.0, "turn": 3.0,
	},
	{
		# "Used to disable electrical systems with a discharge of a million megavolts upon
		# impact... Occasionally... a lightning bolt symbol painted on it."
		"id": "scrambler", "name": "Scrambler Missile", "behaviour": "scramble", "model": "scrambler",
		"path": "zigzag", "trail": "electric",
		"blurb": "Shorts out everything nearby",
		"ammo": 2, "max": 3, "damage": 20.0, "radius": 75.0, "disable": 6.0,
		"color": Color(0.25, 0.35, 0.8), "size": 1.3, "speed": 480.0, "turn": 2.4,
	},
	{
		# "A non-explosive, bladed missile... to penetrate targets in a highly destructive,
		# yet controlled and isolated, fashion."
		"id": "slicer", "name": "Slicer Missile", "behaviour": "pierce", "model": "slicer",
		"path": "laser", "trail": "beam",
		"blurb": "Cuts through armor",
		"ammo": 3, "max": 4, "damage": 260.0,
		"color": Color(0.75, 0.78, 0.85), "size": 1.2, "speed": 950.0, "turn": 4.0,
	},
	{
		# "An explosive-incendiary missile characterized by its match-like ball tip that ignites
		# after being fired. It is one of the SWAT Kats signature missiles."
		"id": "matchhead", "name": "Match Head Missile", "behaviour": "blast", "model": "matchhead",
		"path": "arc", "trail": "fire",
		"blurb": "Big incendiary blast",
		"ammo": 2, "max": 3, "damage": 380.0, "radius": 90.0, "radius_damage": 200.0, "burn": 40.0,
		"color": Color(0.92, 0.88, 0.75), "size": 1.6, "speed": 420.0, "turn": 1.9,
	},
]
