class_name TurboKat
extends Node3D
## The player's jet: arcade flight model, twin cannons, lock-on missiles and the
## Mega-Missile special. Input comes from the InputMap, or from `ai` when autopilot is on.

signal destroyed

const MIN_SPEED := 35.0
const MAX_SPEED := 360.0
const BOUNDARY := 2700.0
const CEILING := 1500.0
const LOCK_RANGE := 1200.0
const LOCK_CONE := 0.21 # radians, about 12 degrees
const LOCK_TIME := 0.65

var combat: Combat
var city: City

var speed := 120.0
var throttle := 0.55
var hp := 100.0
var max_hp := 100.0
var boost := 100.0
var heat := 0.0
var overheated := false
var missiles := 16
var max_missiles := 16
## Special-missile rack (see Arsenal): ammo per weapon id and the selected slot.
var special_ammo := {}
var special_index := 0
var alive := true
var boosting := false

## When false the jet flies itself using `ai`: {pitch, roll, yaw, throttle, fire}.
var player_control := true
var ai := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.55, "fire": false, "missile": false}

## Test harness only: survive terrain impacts too.
var god_mode := false

var lock_target: Target
var lock_time := 0.0
var locked := false

var warn_pull_up := false
var warn_boundary := false
## Holding throttle-down at idle deploys the airbrake: hard deceleration, tighter turns.
var airbrake := false

var _in := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0}
var _gun_cd := 0.0
var _gun_side := 1.0
var _missile_cd := 0.0
var _missile_side := 1.0
var _missile_regen := 0.0
var _beep_cd := 0.0
var _invuln := 0.0
var _model: Dictionary
var _contrails: Array[CPUParticles3D] = []
var _damage_smoke: CPUParticles3D


func _ready() -> void:
	_model = TurboKatModel.build(self)
	for tip in _model.wingtips:
		var c := _trail_emitter(Color(1, 1, 1, 0.35), 0.5, 0.9)
		c.position = tip
		_contrails.append(c)
	_damage_smoke = _trail_emitter(Color(0.12, 0.12, 0.13, 0.7), 2.5, 1.8)
	_damage_smoke.position = Vector3(0, 0.5, 6.0)


func _trail_emitter(color: Color, size: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 50
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	var q := QuadMesh.new()
	q.material = MeshKit.particle_material(false)
	p.mesh = q
	p.spread = 10.0
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 1.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.4
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color, 0.0))
	p.color_ramp = g
	add_child(p)
	return p


func reset(pos: Vector3, look_target: Vector3) -> void:
	global_position = pos
	look_at(look_target, Vector3.UP)
	speed = 130.0
	throttle = 0.55
	hp = max_hp
	boost = 100.0
	heat = 0.0
	overheated = false
	missiles = max_missiles
	special_ammo.clear()
	for def in Arsenal.SPECIALS:
		special_ammo[def.id] = def.ammo
	special_index = 0
	alive = true
	visible = true
	lock_target = null
	locked = false
	_invuln = 0.0
	_damage_smoke.emitting = false


var velocity: Vector3:
	get:
		return -global_transform.basis.z * speed


func forward() -> Vector3:
	return -global_transform.basis.z


func _process(delta: float) -> void:
	if not alive:
		return
	_invuln -= delta
	_fly(delta)
	if not alive:
		return
	_weapons(delta)
	_update_lock(delta)
	_effects(delta)


func _read(action_pos: String, action_neg: String) -> float:
	return Input.get_action_strength(action_pos) - Input.get_action_strength(action_neg)


func _fly(dt: float) -> void:
	var pitch: float
	var roll: float
	var yaw: float
	var thr_cmd: float
	var want_boost: bool
	if player_control:
		pitch = _read("pitch_up", "pitch_down") * (-1.0 if Game.invert_pitch else 1.0)
		roll = _read("roll_right", "roll_left")
		yaw = _read("yaw_right", "yaw_left")
		thr_cmd = _read("throttle_up", "throttle_down")
		want_boost = Input.is_action_pressed("boost")
		throttle = clampf(throttle + thr_cmd * 0.7 * dt, 0.0, 1.0)
	else:
		pitch = ai.pitch
		roll = ai.roll
		yaw = ai.yaw
		want_boost = false
		throttle = move_toward(throttle, ai.throttle, dt)

	# Smooth digital key input so the jet eases into manoeuvres.
	var k := 1.0 - exp(-dt * 7.0)
	_in.pitch = lerpf(_in.pitch, pitch, k)
	_in.roll = lerpf(_in.roll, roll, k)
	_in.yaw = lerpf(_in.yaw, yaw, k)

	boosting = want_boost and boost > 1.0
	airbrake = player_control and not boosting and throttle <= 0.01 and Input.is_action_pressed("throttle_down")
	boost = maxf(0.0, boost - 28.0 * dt) if boosting else minf(100.0, boost + 10.0 * dt)

	# Turn rate peaks at a "corner speed" of about 110-200 m/s, like a real fighter: slow
	# down to out-turn a bandit, and the airbrake tightens it further.
	var authority := clampf(speed / 110.0, 0.5, 1.25) * (1.0 - clampf((speed - 200.0) / 400.0, 0.0, 0.25))
	if airbrake:
		authority *= 1.2
	var b := global_transform.basis
	b = b * Basis(Vector3.RIGHT, _in.pitch * 1.55 * authority * dt)
	b = b * Basis(Vector3.BACK, -_in.roll * 2.9 * authority * dt)
	b = b * Basis(Vector3.UP, -_in.yaw * 0.7 * authority * dt)

	# Banking turns the nose (coordinated turn); releasing roll gently levels the wings.
	var right := b.x
	if b.y.y > 0.1:
		b = Basis(Vector3.UP, right.y * 0.95 * dt) * b
		if absf(_in.roll) < 0.1:
			b = b * Basis(Vector3.BACK, -right.y * 1.7 * dt)

	var fwd := -b.z
	# Keep the fight over Megakat City: steer back toward the centre past the boundary.
	warn_boundary = Vector2(global_position.x, global_position.z).length() > BOUNDARY
	if warn_boundary:
		var to_c := Vector3(-global_position.x, 0.0, -global_position.z).normalized()
		var side := Vector3.UP.cross(fwd).dot(to_c)
		b = Basis(Vector3.UP, signf(side) * 0.9 * dt) * b
	if global_position.y > CEILING and fwd.y > 0.0:
		b = b * Basis(Vector3.RIGHT, -1.2 * dt)

	global_transform.basis = b.orthonormalized()
	fwd = forward()

	var target_speed := 60.0 + throttle * 135.0 + (130.0 if boosting else 0.0)
	if airbrake:
		target_speed = 45.0
		speed = move_toward(speed, target_speed, 45.0 * dt)
	speed = lerpf(speed, target_speed, 1.0 - exp(-dt * 0.9))
	speed -= fwd.y * 45.0 * dt # climbing bleeds speed, diving gains it
	speed = clampf(speed, MIN_SPEED, MAX_SPEED)
	var vel := fwd * speed
	vel.y -= maxf(0.0, 75.0 - speed) * 0.7 # mushy sink when slow
	global_position += vel * dt

	var ground := city.height_at(global_position.x, global_position.z)
	if global_position.y < ground + 1.5:
		if god_mode:
			global_position.y = ground + 40.0
		else:
			crash()
			return
	var ahead := global_position + vel * 1.6
	var mid := global_position + vel * 0.8
	warn_pull_up = vel.y < -5.0 and (ahead.y < city.height_at(ahead.x, ahead.z) + 8.0 or mid.y < city.height_at(mid.x, mid.z) + 8.0)


func _weapons(dt: float) -> void:
	_gun_cd -= dt
	_missile_cd -= dt
	var firing: bool = Input.is_action_pressed("fire_guns") if player_control else ai.fire
	if overheated:
		heat -= 30.0 * dt
		if heat <= 25.0:
			overheated = false
	elif firing and _gun_cd <= 0.0:
		_fire_gun()
	else:
		heat = maxf(0.0, heat - 28.0 * dt)

	_missile_regen += dt
	if _missile_regen >= 6.0:
		_missile_regen = 0.0
		missiles = mini(missiles + 1, max_missiles)

	var want_missile: bool = Input.is_action_just_pressed("fire_missile") if player_control else ai.get("missile", false)
	ai.missile = false
	if want_missile and missiles > 0 and _missile_cd <= 0.0:
		missiles -= 1
		_missile_cd = 0.3
		_missile_side = -_missile_side
		var pos := global_transform * Vector3(4.0 * _missile_side, -1.2, -0.5)
		combat.fire_missile(pos, forward(), speed, lock_target if locked else null)
	if player_control and Input.is_action_just_pressed("cycle_special") and Arsenal.SPECIALS.size() > 1:
		special_index = (special_index + 1) % Arsenal.SPECIALS.size()
		Sfx.play("beep", -8.0, 0.8)
	var special := selected_special()
	if player_control and Input.is_action_just_pressed("fire_special") and special_ammo.get(special.id, 0) > 0 and _missile_cd <= 0.0:
		special_ammo[special.id] -= 1
		_missile_cd = 0.6
		combat.fire_missile(global_transform * Vector3(0, -1.8, -1.0), forward(), speed, lock_target if locked else null, special)


func selected_special() -> Dictionary:
	return Arsenal.SPECIALS[special_index]


func _fire_gun() -> void:
	_gun_cd = 1.0 / 16.0
	heat += 2.3
	if heat >= 100.0:
		overheated = true
		Sfx.play("overheat", -4.0)
	var fwd := forward()
	var muzzle := global_transform * Vector3(2.0 * _gun_side, -0.3, -5.0)
	_gun_side = -_gun_side
	var dir := fwd
	if not player_control and ai.has("aim"):
		dir = ai.aim # test harness aimbot (--god)
	# Light aim assist: bend the stream toward the lead point of a target near the reticle.
	var t := lock_target if lock_target and is_instance_valid(lock_target) else null
	if t and player_control:
		var dist := muzzle.distance_to(t.global_position)
		var lead := t.global_position + t.velocity * (dist / (1150.0 + speed))
		var to_lead := (lead - muzzle).normalized()
		if fwd.angle_to(to_lead) < 0.09:
			dir = to_lead
	dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.005).normalized()
	combat.fire_bullet(muzzle, dir * (1150.0 + speed), Combat.PLAYER_TEAM, 9.0)
	combat.muzzle_flash(muzzle)
	Sfx.play("gun", -11.0, randf_range(0.92, 1.08))


func _update_lock(dt: float) -> void:
	var fwd := forward()
	var best: Target = null
	var best_ang := LOCK_CONE
	for t in combat.targets:
		if not t.alive or not t.lockable or t.invulnerable:
			continue
		var to := t.global_position - global_position
		var d := to.length()
		if d > LOCK_RANGE or d < 1.0:
			continue
		var a := fwd.angle_to(to / d)
		if a < best_ang:
			best_ang = a
			best = t
	if best != lock_target:
		lock_target = best
		lock_time = 0.0
		locked = false
	if lock_target:
		lock_time += dt
		if not locked:
			_beep_cd -= dt
			if _beep_cd <= 0.0:
				_beep_cd = 0.12
				Sfx.play("beep", -12.0)
			if lock_time >= LOCK_TIME:
				locked = true
				Sfx.play("lock", -10.0)


## Variable-geometry wings: swept back at speed, spread open when slow (imported model only).
const SWEEP_AT := 175.0
const SPREAD_AT := 145.0
var wings_swept := false


func _effects(dt: float) -> void:
	if _model.has("wings"):
		var want := wings_swept
		if speed > SWEEP_AT:
			want = true
		elif speed < SPREAD_AT:
			want = false
		if want != wings_swept:
			wings_swept = want
			_model.wings.swept.visible = wings_swept
			_model.wings.open.visible = not wings_swept
	for f in _model.fans:
		(f as Node3D).rotate_z(dt * (8.0 + throttle * 30.0))
	# Underwing missiles disappear as the magazine empties.
	var shown := ceili(float(missiles) / max_missiles * _model.missiles.size())
	for k in _model.missiles.size():
		(_model.missiles[k] as Node3D).visible = k < shown
	var t := Time.get_ticks_msec() * 0.001
	var flicker := 0.9 + 0.1 * sin(t * 60.0)
	var flame_len := (0.35 + throttle * 0.75 + (0.9 if boosting else 0.0)) * flicker
	for p in _model.burners:
		(p as Node3D).scale = Vector3(1.0 + (0.25 if boosting else 0.0), 1.0 + (0.25 if boosting else 0.0), flame_len)
	var trails_on := speed > 190.0 or absf(_in.pitch) > 0.7
	for c in _contrails:
		c.emitting = trails_on
	_damage_smoke.emitting = hp < 40.0


func take_damage(amount: float) -> void:
	if not alive or _invuln > 0.0:
		return
	hp -= amount
	combat.camera.add_shake(0.6)
	Sfx.play("hit", -6.0, randf_range(0.9, 1.1))
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.flash_damage()
	if hp <= 0.0:
		hp = 0.0
		crash()


## Brief invulnerability, used after scripted bumps against bosses.
func grant_invulnerability(seconds: float) -> void:
	_invuln = seconds


func collect(kind: String) -> void:
	if kind == "repair":
		hp = minf(max_hp, hp + 35.0)
	else:
		missiles = max_missiles
		for def in Arsenal.SPECIALS:
			special_ammo[def.id] = mini(special_ammo.get(def.id, 0) + 1, def.max)


func crash() -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	visible = false
	for c in _contrails:
		c.emitting = false
	_damage_smoke.emitting = false
	combat.explode(global_position, 2.6)
	destroyed.emit()
