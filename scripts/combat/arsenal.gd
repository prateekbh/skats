class_name Arsenal
extends RefCounted
## The TurboKat's special-missile rack, as data. The player cycles the rack with Q (gamepad LB)
## and fires the selected missile with R (gamepad X); homing missiles stay on F.
##
## Combat implements these behaviours (add new ones in Combat._missile_hit):
##   "blast"   big explosion that damages everything within blast_radius
##   "stun"    disables the target for `stun` seconds (stops firing, drifts and tumbles)
##   "pierce"  damages even armored targets (e.g. the warship hull before its turrets fall)
##
## Names, effects and colours of the show's missiles must come from swatkats.info
## (see CLAUDE.md). Add an entry here per missile once its canon details are confirmed.

const SPECIALS: Array[Dictionary] = [
	{
		"id": "mega", "name": "Mega-Missile", "behaviour": "blast",
		"ammo": 3, "max": 5,
		"damage": 450.0, "blast_radius": 90.0, "blast_damage": 220.0,
		"color": Color(0.95, 0.75, 0.15), "size": 1.8, "speed": 420.0, "turn": 1.8,
	},
]

## The standard homing missile fired with F.
const HOMING := {
	"id": "homing", "name": "Homing Missile", "behaviour": "homing",
	"damage": 120.0, "color": Color(0.9, 0.9, 0.92), "size": 1.0, "speed": 560.0, "turn": 2.8,
}
