class_name Creepling
extends Target
## Dark Kat's Creepling gliders. Patrol around an anchor point, then make attack runs on the
## TurboKat: pursue with a lead and fire, then break off and extend away before turning back
## for another pass. Runs are time-limited (shorter when sitting on the player's tail) and
## Creeplings turn slower than the TurboKat, so the player can always turn the fight around.
## Bombers are slower, tougher and fire a three-shot spread.

const ATTACK_TIME := Vector2(5.0, 7.0) # seconds per attack run
const TAIL_LIMIT := 3.0 # seconds allowed behind the player before breaking off
const EXTEND_DIST := 600.0 # how far to run out before turning back
const OVERSHOOT_DIST := 130.0

var heavy := false
var speed := 100.0
var turn_rate := 1.15
var fwd := Vector3.FORWARD
var anchor := Vector3.ZERO
var orbit_radius := 250.0

var _mode := "patrol"
var _mode_t := 0.0
var _evade_dir := Vector3.UP
var _orbit := 0.0
var _fire_cd := 2.0
var _bank := 0.0
var _model: Node3D
var _has_token := false
var _tail_t := 0.0


func setup(pos: Vector3, is_heavy: bool, anchor_point: Vector3) -> void:
	heavy = is_heavy
	global_position = pos
	anchor = anchor_point
	_orbit = randf() * TAU
	orbit_radius = randf_range(150.0, 380.0)
	fwd = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	_fire_cd = randf_range(1.5, 3.5)
	if heavy:
		display_name = "Creepling Bomber"
		set_max_hp(160.0)
		radius = 11.0
		speed = 75.0
		turn_rate = 0.7
		score = 350
	else:
		display_name = "Creepling Glider"
		set_max_hp(30.0)
		radius = 6.0
		speed = randf_range(95.0, 115.0)
		score = 100
	_model = _build_model()
	tree_exiting.connect(_release_token)
	died.connect(func(_t): _release_token())


func _release_token() -> void:
	if _has_token:
		_has_token = false
		combat.attack_tokens += 1


func _build_model() -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var s := 2.0 if heavy else 1.0
	root.scale = Vector3.ONE * s
	var hull := flashable(MeshKit.toon(Color(0.3, 0.16, 0.38) if not heavy else Color(0.22, 0.1, 0.12), 0.3, 0.5))
	var wing_mat := flashable(MeshKit.toon(Color(0.14, 0.09, 0.2), 0.2, 0.6))
	MeshKit.part(root, MeshKit.sphere(1.0, 12), hull, Vector3.ZERO, Vector3.ZERO, Vector3(1.4, 1.0, 3.0))
	# Scalloped bat wings.
	var wing := PackedVector2Array([
		Vector2(0, -1.5), Vector2(3.0, -0.8), Vector2(7.5, 0.2), Vector2(6.0, 1.6), Vector2(4.5, 1.0),
		Vector2(3.0, 2.2), Vector2(0, 1.6), Vector2(-3.0, 2.2), Vector2(-4.5, 1.0), Vector2(-6.0, 1.6),
		Vector2(-7.5, 0.2), Vector2(-3.0, -0.8),
	])
	MeshKit.part(root, MeshKit.slab(wing, 0.25), wing_mat, Vector3(0, 0.2, 0.5))
	# The Creepling pilot and its glowing eyes.
	MeshKit.part(root, MeshKit.sphere(0.75, 10), MeshKit.toon(Color(0.45, 0.55, 0.3)), Vector3(0, 0.9, -0.6))
	for sx in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.sphere(0.2, 6), MeshKit.glow(Color(1.0, 0.15, 0.1)), Vector3(0.28 * sx, 1.05, -1.25))
	MeshKit.part(root, MeshKit.sphere(0.6, 8), MeshKit.glow(Color(0.7, 0.3, 1.0, 0.9), true), Vector3(0, 0, 3.0))
	return root


## Stunned: lose lift and tumble.
func stunned_tick(dt: float) -> void:
	velocity = velocity * maxf(0.0, 1.0 - 0.6 * dt) + Vector3.DOWN * 25.0 * dt
	global_position += velocity * dt
	_model.rotate_z(dt * 6.0)
	if global_position.y < combat.city.height_at(global_position.x, global_position.z) + 2.0:
		take_damage(9999.0, global_position, true)


func _start_attack() -> void:
	_mode = "attack"
	_mode_t = randf_range(ATTACK_TIME.x, ATTACK_TIME.y)
	_tail_t = 0.0


## Break away from the player: keep momentum, veer off to one side and climb or dive a little.
func _break_off(to_player: Vector3) -> void:
	_mode = "extend"
	_mode_t = randf_range(2.5, 4.0)
	var side := to_player.cross(Vector3.UP).normalized() * (1.0 if randf() < 0.5 else -1.0)
	_evade_dir = (fwd * 0.6 - to_player * 0.5 + side * 0.7 + Vector3.UP * randf_range(-0.15, 0.3)).normalized()


func tick(dt: float) -> void:
	var player: TurboKat = combat.player
	var to_p := player.global_position - global_position
	var dist := to_p.length()
	var desired: Vector3
	var lead := player.global_position + player.velocity * clampf(dist / 520.0, 0.0, 1.5)
	_mode_t -= dt
	if _mode == "extend":
		# Breaking off: run out, then come back around for a fresh (often head-on) pass.
		desired = _evade_dir
		if (_mode_t <= 0.0 and dist > EXTEND_DIST) or _mode_t <= -4.0:
			_start_attack()
	elif dist > 1000.0 or not player.alive:
		_mode = "patrol"
		_release_token()
		_orbit += dt * 0.35
		var goal := anchor + Vector3(cos(_orbit) * orbit_radius, 0.0, sin(_orbit) * orbit_radius)
		desired = (goal - global_position).normalized()
	elif not _has_token and combat.attack_tokens <= 0 and dist > 350.0:
		# No attack slot free: keep circling the patrol area until one opens up
		# (or the TurboKat comes close enough to force a fight).
		_mode = "wait"
		_orbit += dt * 0.35
		var goal := anchor + Vector3(cos(_orbit) * orbit_radius, 0.0, sin(_orbit) * orbit_radius)
		desired = (goal - global_position).normalized()
	else:
		if not _has_token and combat.attack_tokens > 0:
			_has_token = true
			combat.attack_tokens -= 1
		if _mode != "attack":
			_start_attack()
		desired = (lead - global_position).normalized()
		# Time sat behind the player counts down a shorter fuse.
		if player.forward().dot(-to_p / dist) < -0.5:
			_tail_t += dt
		if _mode_t <= 0.0 or _tail_t > TAIL_LIMIT or dist < OVERSHOOT_DIST:
			_break_off(to_p / dist)

	# Terrain avoidance: climb over towers ahead, stay under the ceiling.
	var ahead := global_position + fwd * 80.0
	var floor_h := maxf(combat.city.height_at(ahead.x, ahead.z), combat.city.height_at(global_position.x, global_position.z)) + 30.0
	if global_position.y < floor_h:
		desired = (desired + Vector3.UP * 2.0).normalized()
	# Stay in the fight's altitude band (around the anchor) so dogfights don't drift skyward.
	if global_position.y > anchor.y + 300.0 or global_position.y > 900.0:
		desired = (desired + Vector3.DOWN * 0.8).normalized()

	var prev := fwd
	fwd = Combat.steer(fwd, desired, turn_rate * dt)
	velocity = fwd * speed
	global_position += velocity * dt
	Combat.safe_look(self, fwd)
	var turn := prev.cross(fwd).y / maxf(dt, 0.0001)
	_bank = lerpf(_bank, clampf(turn * 0.8, -1.1, 1.1), 1.0 - exp(-dt * 4.0))
	_model.rotation.z = _bank

	_fire_cd -= dt
	if _mode == "attack" and dist < 600.0 and _fire_cd <= 0.0 and fwd.dot(to_p / dist) > 0.9:
		_fire_cd = randf_range(2.8, 4.2) if heavy else randf_range(2.0, 3.6)
		var aim := (lead - global_position).normalized()
		var shots := 3 if heavy else 1
		for k in shots:
			var spread := (k - (shots - 1) * 0.5) * 0.05
			var d := (aim + Vector3(randf_range(-0.045, 0.045), randf_range(-0.045, 0.045), randf_range(-0.045, 0.045)) + aim.cross(Vector3.UP).normalized() * spread).normalized()
			combat.fire_bullet(global_position + fwd * radius, d * 540.0, Combat.ENEMY_TEAM, 6.0 if heavy else 4.0, 2.2, 1.6 if heavy else 1.0)
