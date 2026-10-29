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
var _flash := 0.0


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash -= delta
		var e := 2.5 if _flash > 0.0 else 0.0
		for m in flash_materials:
			m.emission_energy_multiplier = e
	if alive:
		tick(delta)


func tick(_dt: float) -> void:
	pass


func set_max_hp(value: float) -> void:
	max_hp = value
	hp = value


func hit_test(p0: Vector3, p1: Vector3) -> bool:
	return Combat.seg_sphere(p0, p1, global_position, radius)


func take_damage(amount: float, point: Vector3) -> void:
	if not alive:
		return
	if invulnerable:
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
