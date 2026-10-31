class_name SupplyCache
extends Node3D
## A supply cache on the ground (streets, plazas, the park, the piers): fly low to grab it.
## A tall light beam shows where it is from far away and the radar marks it. To collect one the
## TurboKat has to be within RADIUS of the crate and no more than MAX_ALT above it, which in the
## city means diving down between the buildings, and some caches are guarded by flak nests.
## Specials are limited, so these are where you restock them. An emptied cache refills later.

const RADIUS := 26.0
const MAX_ALT := 40.0
const RESPAWN := 60.0

var combat: Combat
var kind := "special" # "special" | "blowtorch" | "repair"
var contents := {}
var available := true

var _t := 0.0
var _crate: Node3D
var _beam: Node3D


## Rolls what a cache of this kind holds.
static func roll(k: String, rng: RandomNumberGenerator) -> Dictionary:
	match k:
		"blowtorch":
			return {"blowtorch": 8}
		"repair":
			return {"hp": 45, "boost": 60}
	var ids: Array[String] = []
	for def in Arsenal.SPECIALS:
		ids.append(def.id)
	ids.shuffle()
	var out := {}
	for i in 2:
		out[ids[i]] = 2
	return out


static func color_for(k: String) -> Color:
	match k:
		"blowtorch":
			return Color(0.85, 0.92, 1.0)
		"repair":
			return Color(0.3, 1.0, 0.5)
	return Color(1.0, 0.7, 0.2)


func setup(c: Combat, k: String, rng: RandomNumberGenerator) -> void:
	combat = c
	kind = k
	contents = SupplyCache.roll(k, rng)
	var col := SupplyCache.color_for(k)
	_crate = Node3D.new()
	add_child(_crate)
	MeshKit.part(_crate, MeshKit.box(Vector3(7, 4.5, 7)), MeshKit.toon(Color(0.25, 0.27, 0.3), 0.4, 0.5), Vector3(0, 2.25, 0))
	MeshKit.part(_crate, MeshKit.box(Vector3(7.4, 1.0, 7.4)), MeshKit.glow(col), Vector3(0, 3.6, 0))
	MeshKit.part(_crate, MeshKit.box(Vector3(1.4, 4.7, 7.6)), MeshKit.glow(col), Vector3(0, 2.3, 0))
	if k == "repair":
		MeshKit.part(_crate, MeshKit.box(Vector3(4.5, 1.2, 1.2)), MeshKit.glow(Color.WHITE), Vector3(0, 5.3, 0))
		MeshKit.part(_crate, MeshKit.box(Vector3(1.2, 1.2, 4.5)), MeshKit.glow(Color.WHITE), Vector3(0, 5.3, 0))
	_beam = Node3D.new()
	add_child(_beam)
	var glow := MeshKit.glow(Color(col, 0.35), true)
	MeshKit.part(_beam, MeshKit.cyl(1.4, 2.4, 320.0, 10), glow, Vector3(0, 160.0, 0))
	MeshKit.part(_beam, MeshKit.cyl(RADIUS * 0.7, RADIUS * 0.7, 0.4, 24), MeshKit.glow(Color(col, 0.28), true), Vector3(0, 0.5, 0))


func _process(delta: float) -> void:
	if not available:
		_t -= delta
		if _t <= 0.0:
			_set_available(true)
		return
	_crate.rotate_y(delta * 0.8)
	var p := combat.player
	if p == null or not p.alive:
		return
	var d := p.global_position - global_position - Vector3(0, 3.0, 0)
	if d.length() < RADIUS and p.global_position.y - global_position.y < MAX_ALT:
		var text := p.collect_cache(contents)
		combat.on_message.call("SUPPLY: " + text)
		Sfx.play("pickup", -4.0)
		_set_available(false)
		_t = RESPAWN


func _set_available(on: bool) -> void:
	available = on
	_crate.visible = on
	_beam.visible = on
