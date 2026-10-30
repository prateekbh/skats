class_name Target
extends Node3D
## Anything the TurboKat can shoot: enemies and boss weak points.
## Subclasses override tick(dt) for behaviour and may override hit_test() for non-sphere shapes.

signal died(target: Target)

var combat: Combat
var max_hp := 100.0
var hp := 100.0
var radius := 6.0
var lockable := true
var invulnerable := false
var alive := true
var score := 100
var display_name := "Target"
## Movement this frame, used by the player's aim assist and enemy lead calculations.
var velocity := Vector3.ZERO
## When true the HUD always shows an arrow to this target.
var is_objective := false
## Materials that flash white when hit (should be unique to this target).
var flash_materials: Array[StandardMaterial3D] = []
## Seconds left disabled (Octopus, Scrambler): no AI, no firing.
var stunned := 0.0
## Incendiary damage over time (Match Head): seconds left and damage per second.
var burn_t := 0.0
var burn_dps := 0.0
## True while held by an Octopus Missile (Combat draws the tentacles).
var captured := false
## Targets that the Slicer / Buzz-Saw cut apart instead of exploding (Creeplings; dragons later).
var cuttable := false
## Set by a cutting missile just before its damage lands: a kill then cuts the target into this
## many pieces (Combat.cut_apart) and the usual explosion is skipped.
var cut_pieces := 0
var _flash := 0.0
var _fx_t := 0.0


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		var e := 2.5 if _flash > 0.0 else 0.0
		for m in flash_materials:
			m.emission_energy_multiplier = e
	if alive:
		_fx_t -= delta
		if burn_t > 0.0:
			burn_t -= delta
			if not invulnerable:
				hp -= burn_dps * delta
				if hp <= 0.0:
					take_damage(1.0, global_position, true)
					return
			if _fx_t <= 0.0:
				_fx_t = 0.08
				combat.vfx.burn(global_position)
		if stunned > 0.0:
			stunned -= delta
			if stunned <= 0.0:
				captured = false
			elif not captured and _fx_t <= 0.0:
				_fx_t = 0.15
				combat.vfx.crackle(global_position)
			stunned_tick(delta)
		else:
			tick(delta)


func tick(_dt: float) -> void:
	pass


## Called instead of tick() while stunned. Subclasses can drift or tumble here.
func stunned_tick(_dt: float) -> void:
	pass


func stun(seconds: float) -> void:
	if alive:
		stunned = maxf(stunned, seconds)


func ignite(seconds: float, dps: float) -> void:
	if alive:
		burn_t = maxf(burn_t, seconds)
		burn_dps = maxf(burn_dps, dps)


## Cuttable targets: the node whose children match Creepling.model_parts(), and its half-extents.
func model_root() -> Node3D:
	return null


func cut_extent() -> Vector3:
	return Vector3.ONE * radius


func set_max_hp(value: float) -> void:
	max_hp = value
	hp = value


func hit_test(p0: Vector3, p1: Vector3) -> bool:
	return Combat.seg_sphere(p0, p1, global_position, radius)


## `pierce` damages even invulnerable (armored) targets.
func take_damage(amount: float, point: Vector3, pierce := false) -> void:
	if not alive:
		return
	if invulnerable and not pierce:
		combat.armor_ping(point)
		return
	hp -= amount
	_flash = 0.07
	if hp <= 0.0:
		hp = 0.0
		alive = false
		died.emit(self)


## Registers materials for the white hit-flash. Returns a unique copy to assign to meshes.
func flashable(m: StandardMaterial3D) -> StandardMaterial3D:
	var copy := m.duplicate() as StandardMaterial3D
	copy.emission_enabled = true
	copy.emission = Color.WHITE
	copy.emission_energy_multiplier = 0.0
	flash_materials.append(copy)
	return copy
