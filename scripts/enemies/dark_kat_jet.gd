class_name DarkKatJet
extends Target
## Episode 1's final boss: Dark Kat's personal fighter, 2.5 times the TurboKat's size. It flies
## inside a blue energy shield and fires lasers instead of bullets.
##
## The shield soaks up everything. The first PROOF_HITS missiles that strike it emit
## `shield_proven` (the mission then plays the cutscene where Razor arms the Scrambler
## Missiles). Once `scramble_ready` is set, a Scrambler hit overloads the shield generator and
## the jet becomes an ordinary target; any other weapon is still absorbed.

signal shield_proven
signal shield_broken

const MODEL_SCALE := 2.5
const PROOF_HITS := 2
const SHIELD_RADIUS := 46.0
const LASER_SPEED := 800.0

var anchor := Vector3.ZERO
var shield_up := true
var scramble_ready := false
var proof_hits := 0
var speed := 150.0
var turn_rate := 0.95
var fwd := Vector3.FORWARD

var _mode := "attack"
var _mode_t := 0.0
var _evade_dir := Vector3.UP
var _fire_cd := 3.0
var _burst := 0
var _burst_t := 0.0
var _side := 1.0
var _bank := 0.0
var _model: Node3D
var _shield: MeshInstance3D
var _shield_mat: ShaderMaterial
var _pulse := 0.0
var _collapse := -1.0
var _dying := -1.0
var _boom_cd := 0.0
var _tail_t := 0.0

const LILAC := Color(0.8, 0.72, 0.97)
const RED := Color(0.88, 0.1, 0.07)
const DARK := Color(0.09, 0.08, 0.14)
const GREY := Color(0.36, 0.32, 0.46)


func setup(c: Combat) -> void:
	combat = c
	c.targets.append(self)
	died.connect(c._on_target_died)
	tree_exiting.connect(func(): c.targets.erase(self))
	display_name = "Dark Kat's Jet"
	set_max_hp(900.0)
	radius = SHIELD_RADIUS - 4.0
	score = 5000
	invulnerable = true
	lock_through_armor = true
	is_objective = true
	cuttable = false
	died.connect(_on_died)
	_build()
	var dir := Vector3(0.8, 0.0, 0.6).normalized()
	global_position = anchor + dir * 1800.0 + Vector3(0, 150, 0)
	fwd = -dir
	Combat.safe_look(self, fwd)


func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	_model.scale = Vector3.ONE * MODEL_SCALE
	var lilac := flashable(MeshKit.toon(LILAC, 0.25, 0.45))
	var red := flashable(MeshKit.toon(RED, 0.3, 0.4))
	var dark := MeshKit.toon(DARK, 0.4, 0.4)
	var grey := MeshKit.toon(GREY, 0.3, 0.5)
	var white := MeshKit.toon(Color(0.95, 0.95, 1.0), 0.1, 0.5)
	var flame := MeshKit.glow(Color(0.55, 0.8, 1.0, 0.85), true)
	var core := MeshKit.glow(Color(0.95, 0.98, 1.0, 0.9), true)
	# Fuselage: a long rounded body with a pointed nose.
	MeshKit.part(_model, MeshKit.sphere(1.0, 20), lilac, Vector3(0, 0, 1.5), Vector3.ZERO, Vector3(2.7, 1.9, 8.5))
	MeshKit.part(_model, MeshKit.cyl(0.0, 1.95, 9.0, 8), lilac, Vector3(0, -0.05, -8.2), Vector3(-PI / 2, 0, 0))
	# Dark canopy and cheek panels on the nose.
	MeshKit.part(_model, MeshKit.slab(PackedVector2Array([Vector2(0, -11.0), Vector2(1.5, -4.0), Vector2(-1.5, -4.0)]), 0.3), dark, Vector3(0, 1.55, 0))
	for sx in [-1.0, 1.0]:
		MeshKit.part(_model, MeshKit.slab(PackedVector2Array([Vector2(0, -8.5), Vector2(1.0 * sx, -2.0), Vector2(2.2 * sx, -2.6)]), 0.25), dark, Vector3(0, 0.3, 0), Vector3(0, 0, 0.0))
	# Swept wings, tips cut square, as in the show.
	var wing_r := PackedVector2Array([Vector2(1.8, -3.5), Vector2(12.8, 4.5), Vector2(12.8, 8.0), Vector2(2.2, 5.5)])
	var wing_l := PackedVector2Array([Vector2(-2.2, 5.5), Vector2(-12.8, 8.0), Vector2(-12.8, 4.5), Vector2(-1.8, -3.5)])
	MeshKit.part(_model, MeshKit.slab(wing_r, 0.4), lilac, Vector3(0, -0.2, 0))
	MeshKit.part(_model, MeshKit.slab(wing_l, 0.4), lilac, Vector3(0, -0.2, 0))
	# Twin red engine pods with white intakes and blue-white afterburners.
	for sx in [-1.0, 1.0]:
		var x: float = 4.8 * sx
		MeshKit.part(_model, MeshKit.box(Vector3(3.0, 0.9, 6.0)), lilac, Vector3(x * 0.6, -0.2, 2.5))
		MeshKit.part(_model, MeshKit.cyl(1.35, 1.35, 10.0, 14), red, Vector3(x, -0.3, 3.0), Vector3(PI / 2, 0, 0))
		MeshKit.part(_model, MeshKit.cyl(1.5, 1.5, 0.7, 14), white, Vector3(x, -0.3, -2.1), Vector3(PI / 2, 0, 0))
		MeshKit.part(_model, MeshKit.cyl(1.05, 1.05, 0.2, 14), dark, Vector3(x, -0.3, -2.5), Vector3(PI / 2, 0, 0))
		MeshKit.part(_model, MeshKit.cyl(1.0, 1.35, 1.4, 14), dark, Vector3(x, -0.3, 8.4), Vector3(PI / 2, 0, 0))
		MeshKit.part(_model, MeshKit.cyl(0.0, 1.0, 8.0, 10), flame, Vector3(x, -0.3, 13.0), Vector3(PI / 2, 0, 0))
		MeshKit.part(_model, MeshKit.cyl(0.0, 0.5, 4.0, 8), core, Vector3(x, -0.3, 11.0), Vector3(PI / 2, 0, 0))
		# Dark vertical tail fin and a small red flap.
		var fin := PackedVector2Array([Vector2(0, 0), Vector2(4.0, 4.4), Vector2(4.0, 7.6), Vector2(0, 6.4)])
		MeshKit.part(_model, MeshKit.slab(fin, 0.3), grey, Vector3(2.0 * sx, 1.1, 2.0), Vector3(0, 0, PI / 2 + (0.0 if sx > 0.0 else 0.0)))
		var flap := PackedVector2Array([Vector2(0, 0), Vector2(3.8 * sx, 0.6), Vector2(3.8 * sx, 2.4), Vector2(0, 1.8)])
		MeshKit.part(_model, MeshKit.slab(flap, 0.3), red, Vector3(x + 1.2 * sx, -0.1, 7.0))
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = load("res://shaders/shield.gdshader")
	_shield = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = SHIELD_RADIUS
	sm.height = SHIELD_RADIUS * 2.0
	sm.radial_segments = 28
	sm.rings = 14
	_shield.mesh = sm
	_shield.material_override = _shield_mat
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shield)


## A missile struck the jet. While the shield is up it soaks the hit (returns true: no damage, no
## stun); a Scrambler is the exception once armed, see scrambled().
func missile_struck(def: Dictionary, p: Vector3) -> bool:
	if not shield_up:
		return false
	if def.behaviour == "scramble":
		return false # handled by scrambled() when the discharge goes off
	_pulse = 1.0
	combat.vfx.hit(p, 2.0)
	if camera_ok():
		Sfx.play_at("armor", p, combat.camera.global_position, 0.0)
	if not scramble_ready:
		proof_hits += 1
		if proof_hits == PROOF_HITS:
			shield_proven.emit()
	return true


## The shield absorbs everything, even armor-piercing cuts: a flash and a ricochet, no message.
func take_damage(amount: float, point: Vector3, pierce := false) -> void:
	if shield_up:
		_pulse = maxf(_pulse, 0.5)
		if combat.vfx and alive:
			combat.armor_ping_quiet(point)
		return
	super.take_damage(amount, point, pierce)


func camera_ok() -> bool:
	return combat != null and combat.camera != null


## A Scrambler discharge went off in range. Returns true if the shield absorbed it.
func scrambled(_def: Dictionary) -> bool:
	if not shield_up:
		return false
	if scramble_ready:
		_drop_shield()
	else:
		_pulse = 1.0
	return true


func _drop_shield() -> void:
	shield_up = false
	invulnerable = false
	radius = 30.0
	_collapse = 0.0
	combat.vfx.electric(global_position, 110.0)
	combat.explode(global_position + fwd * 20.0, 1.5)
	Sfx.play("explosion", -2.0, 0.8)
	shield_broken.emit()


func tick(dt: float) -> void:
	var player: TurboKat = combat.player
	var to_p := player.global_position - global_position
	var dist := to_p.length()
	var lead := player.global_position + player.velocity * clampf(dist / LASER_SPEED, 0.0, 1.2)
	var desired: Vector3
	_mode_t -= dt
	if _mode == "extend":
		desired = _evade_dir
		if (_mode_t <= 0.0 and dist > 650.0) or _mode_t <= -4.0:
			_mode = "attack"
			_mode_t = randf_range(6.0, 8.0)
			_tail_t = 0.0
	else:
		desired = (lead - global_position).normalized()
		if player.alive and player.forward().dot(-to_p / maxf(dist, 1.0)) < -0.5:
			_tail_t += dt
		if _mode_t <= 0.0 or _tail_t > 3.5 or dist < 140.0:
			_break_off(to_p / maxf(dist, 1.0))
	# Stay over the city: keep clear of towers, within the fight's altitude band and near its anchor.
	var ahead := global_position + fwd * 140.0
	var floor_h := maxf(combat.city.height_at(ahead.x, ahead.z), combat.city.height_at(global_position.x, global_position.z)) + 60.0
	if global_position.y < floor_h:
		desired = (desired + Vector3.UP * 2.5).normalized()
	if global_position.y > anchor.y + 350.0:
		desired = (desired + Vector3.DOWN * 0.8).normalized()
	if global_position.distance_to(anchor) > 2600.0:
		desired = (desired + (anchor - global_position).normalized() * 1.5).normalized()
	var prev := fwd
	fwd = Combat.steer(fwd, desired, turn_rate * dt)
	var spd := speed * (0.86 if (scramble_ready and shield_up) else 1.0)
	velocity = fwd * spd
	global_position += velocity * dt
	Combat.safe_look(self, fwd)
	var turn := prev.cross(fwd).y / maxf(dt, 0.0001)
	_bank = lerpf(_bank, clampf(turn * 0.9, -1.0, 1.0), 1.0 - exp(-dt * 3.0))
	_model.rotation.z = _bank
	_fire(dt, player, dist, lead)


func _break_off(to_player: Vector3) -> void:
	_mode = "extend"
	_mode_t = randf_range(3.0, 4.5)
	var side := to_player.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	_evade_dir = (fwd * 0.7 - to_player * 0.4 + side * 0.6 + Vector3.UP * randf_range(-0.1, 0.25)).normalized()


## Lasers in short alternating bursts from the engine pods.
func _fire(dt: float, player: TurboKat, dist: float, lead: Vector3) -> void:
	_fire_cd -= dt
	if _burst <= 0 and _mode == "attack" and dist < 900.0 and player.alive and _fire_cd <= 0.0 and fwd.dot(to_unit(player.global_position)) > 0.93:
		_burst = 4
		_fire_cd = randf_range(2.4, 3.4) * (1.4 if (scramble_ready and shield_up) else 1.0)
	if _burst > 0:
		_burst_t -= dt
		if _burst_t <= 0.0:
			_burst_t = 0.13
			_burst -= 1
			_side = -_side
			var from := global_transform * (Vector3(4.8 * _side, -0.3, -3.0) * MODEL_SCALE)
			var aim := ((lead - from).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.02).normalized()
			combat.fire_laser(from, aim * LASER_SPEED, 9.0)


func to_unit(p: Vector3) -> Vector3:
	return (p - global_position).normalized()


## Stunned (a Scrambler after the shield is gone): drift on, nose dropping.
func stunned_tick(dt: float) -> void:
	velocity = velocity * maxf(0.0, 1.0 - 0.3 * dt)
	global_position += velocity * dt
	_model.rotation.z += dt * 0.5


func _on_died(_t: Target) -> void:
	_dying = 0.0
	invulnerable = true
	combat.explode(global_position, 3.0)


func _process(delta: float) -> void:
	super._process(delta)
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	if _shield_mat:
		_shield_mat.set_shader_parameter("pulse", _pulse)
	if _collapse >= 0.0:
		_collapse += delta
		var k := _collapse / 0.8
		_shield.scale = Vector3.ONE * (1.0 + k * 0.5)
		_shield_mat.set_shader_parameter("alpha", clampf(1.0 - k, 0.0, 1.0))
		if k >= 1.0:
			_shield.visible = false
			_collapse = -1.0
	if _dying >= 0.0:
		_die_step(delta)
	elif alive and not shield_up and hp < max_hp * 0.4:
		_smoke_step(delta)


func _smoke_step(delta: float) -> void:
	_boom_cd -= delta
	if _boom_cd <= 0.0:
		_boom_cd = 0.12
		combat.vfx.burn(global_transform * Vector3(randf_range(-20, 20), randf_range(-4, 4), randf_range(0, 25)))


## Death: spinning nose-down with chained explosions, then a final blast.
func _die_step(dt: float) -> void:
	_dying += dt
	_boom_cd -= dt
	if _boom_cd <= 0.0 and _dying < 4.0:
		_boom_cd = 0.15
		combat.explode(global_transform * Vector3(randf_range(-25, 25), randf_range(-6, 6), randf_range(-30, 40)), randf_range(1.5, 3.0))
	fwd = Combat.steer(fwd, (fwd + Vector3.DOWN * 0.9).normalized(), 0.6 * dt)
	global_position += fwd * speed * 0.8 * dt + Vector3.DOWN * dt * 20.0 * _dying
	Combat.safe_look(self, fwd)
	_model.rotate_z(dt * 3.0)
	var ground := combat.city.height_at(global_position.x, global_position.z)
	if _dying > 5.0 or global_position.y < ground + 8.0:
		combat.explode(global_position, 6.0)
		queue_free()
