class_name DarkKatWarship
extends Node3D
## Episode 1 boss. A 230 m armored airship that circles downtown.
## Phase 1: hull is armored and three flak turrets shoot back.
## Phase 2: once the turrets are down, the hull opens up and the ship launches gliders.

signal destroyed
signal phase_changed(phase: int)

const ORBIT_RADIUS := 680.0
const ALTITUDE := 330.0
const CRUISE_SPEED := 24.0
const HULL_HALF_LENGTH := 100.0
const HULL_RADIUS := 31.0

var combat: Combat
var hull: Hull
var turrets: Array[Turret] = []
var phase := 0
## Called with a world position when the ship wants to launch a glider in phase 2.
var spawn_glider: Callable

var _angle := 0.0
var _approach := 1.0
var _launch_cd := 6.0
var _dying := -1.0
var _boom_cd := 0.0
var _hull_mat: StandardMaterial3D


## Hull weak point (capsule-shaped hit test).
class Hull extends Target:
	var ship: DarkKatWarship

	func hit_test(p0: Vector3, p1: Vector3) -> bool:
		var a := global_transform * Vector3(0, 0, -DarkKatWarship.HULL_HALF_LENGTH)
		var b := global_transform * Vector3(0, 0, DarkKatWarship.HULL_HALF_LENGTH)
		return Combat.point_capsule_dist(p1, a, b) < DarkKatWarship.HULL_RADIUS or Combat.point_capsule_dist(p0.lerp(p1, 0.5), a, b) < DarkKatWarship.HULL_RADIUS


## Flak turret weak point: tracks the TurboKat and fires bursts.
class Turret extends Target:
	var barrel: Node3D
	var _cd := 2.0
	var _burst := 0
	var _burst_t := 0.0

	func tick(dt: float) -> void:
		var player: TurboKat = combat.player
		velocity = Vector3.ZERO
		if not player.alive:
			return
		var to := player.global_position - global_position
		var dist := to.length()
		if dist > 1.0:
			Combat.safe_look(barrel, to)
		_cd -= dt
		if dist < 950.0 and _cd <= 0.0:
			_cd = randf_range(1.8, 2.6)
			_burst = 4
		if _burst > 0:
			_burst_t -= dt
			if _burst_t <= 0.0:
				_burst_t = 0.12
				_burst -= 1
				var lead := player.global_position + player.velocity * (dist / 430.0)
				var dir := ((lead - global_position).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.035).normalized()
				combat.fire_bullet(global_position + dir * 8.0, dir * 430.0, Combat.ENEMY_TEAM, 8.0, 3.0, 2.2)


func setup(c: Combat) -> void:
	combat = c
	_angle = randf() * TAU
	_build()
	_place(0.0)


func _build() -> void:
	var body := Node3D.new()
	add_child(body)
	_hull_mat = MeshKit.toon(Color(0.13, 0.1, 0.16), 0.55, 0.4)
	var trim := MeshKit.toon(Color(0.28, 0.08, 0.1), 0.4, 0.5)
	var glow_red := MeshKit.glow(Color(1.0, 0.12, 0.15))

	hull = Hull.new()
	hull.ship = self
	hull.display_name = "Warship Hull"
	hull.set_max_hp(1400.0)
	hull.radius = 45.0
	hull.score = 5000
	hull.invulnerable = true
	hull.lockable = false
	hull.is_objective = true
	combat.add_target(hull, self)
	hull.died.connect(_on_hull_died)

	var hm := hull.flashable(_hull_mat)
	MeshKit.part(body, MeshKit.sphere(1.0, 24), hm, Vector3.ZERO, Vector3.ZERO, Vector3(HULL_RADIUS, HULL_RADIUS * 0.85, HULL_HALF_LENGTH + HULL_RADIUS * 0.6))
	# Red running lights along the flanks.
	for sx in [-1.0, 1.0]:
		MeshKit.part(body, MeshKit.box(Vector3(0.8, 1.2, 150)), glow_red, Vector3(HULL_RADIUS * 0.97 * sx, 0, 0))
	# Command bridge (where Dark Kat watches) and keel gondola.
	MeshKit.part(body, MeshKit.box(Vector3(18, 14, 40)), trim, Vector3(0, -HULL_RADIUS * 0.85 - 5.0, 10))
	MeshKit.part(body, MeshKit.box(Vector3(14, 3, 30)), MeshKit.glow(Color(0.9, 0.3, 0.9)), Vector3(0, -HULL_RADIUS * 0.85 - 6.0, -6))
	MeshKit.part(body, MeshKit.box(Vector3(10, 20, 26)), trim, Vector3(0, HULL_RADIUS * 0.8, 40))
	# Tail fins.
	var fin := PackedVector2Array([Vector2(0, 0), Vector2(0, 40), Vector2(40, 52), Vector2(40, 30)])
	MeshKit.part(body, MeshKit.slab(fin, 2.0), trim, Vector3(0, HULL_RADIUS * 0.6, 80), Vector3(0, 0, PI / 2))
	MeshKit.part(body, MeshKit.slab(fin, 2.0), trim, Vector3(0, -HULL_RADIUS * 0.6, 80), Vector3(0, 0, -PI / 2))
	MeshKit.part(body, MeshKit.slab(fin, 2.0), trim, Vector3(HULL_RADIUS * 0.6, 0, 80))
	MeshKit.part(body, MeshKit.slab(fin, 2.0), trim, Vector3(-HULL_RADIUS * 0.6, 0, 80), Vector3(0, 0, PI))
	# Engine glow.
	for p in [Vector3(14, 0, 128), Vector3(-14, 0, 128), Vector3(0, 12, 126)]:
		MeshKit.part(body, MeshKit.sphere(6.0, 10), MeshKit.glow(Color(0.8, 0.3, 1.0, 0.9), true), p)

	# Three flak turrets: two on top, one underneath.
	var turret_spots := [Vector3(0, HULL_RADIUS * 0.82, -55), Vector3(0, HULL_RADIUS * 0.84, 5), Vector3(0, -HULL_RADIUS * 0.82, -50)]
	for spot in turret_spots:
		var t := Turret.new()
		t.display_name = "Flak Turret"
		t.set_max_hp(220.0)
		t.radius = 10.0
		t.score = 600
		t.is_objective = true
		combat.add_target(t, self)
		t.position = spot
		var base_mat := t.flashable(MeshKit.toon(Color(0.35, 0.32, 0.38), 0.5, 0.4))
		MeshKit.part(t, MeshKit.cyl(6.5, 8.0, 5.0, 12), base_mat, Vector3(0, 2.0 * signf(spot.y), 0))
		MeshKit.part(t, MeshKit.sphere(1.6, 8), MeshKit.glow(Color(1, 0.2, 0.1)), Vector3(0, 5.0 * signf(spot.y), 0))
		var barrel := Node3D.new()
		t.add_child(barrel)
		barrel.position = Vector3(0, 4.0 * signf(spot.y), 0)
		MeshKit.part(barrel, MeshKit.cyl(0.9, 0.9, 12.0, 8), base_mat, Vector3(1.6, 0, -6), Vector3(-PI / 2, 0, 0))
		MeshKit.part(barrel, MeshKit.cyl(0.9, 0.9, 12.0, 8), base_mat, Vector3(-1.6, 0, -6), Vector3(-PI / 2, 0, 0))
		t.barrel = barrel
		t.died.connect(_on_turret_died)
		turrets.append(t)


## Places the ship on its orbit. `_approach` > 0 pulls it in from far away at the start.
func _place(dt: float) -> void:
	_angle += dt * CRUISE_SPEED / ORBIT_RADIUS
	_approach = maxf(0.0, _approach - dt / 18.0)
	var r := ORBIT_RADIUS + _approach * 1800.0
	var pos := Vector3(cos(_angle) * r, ALTITUDE + _approach * 150.0, sin(_angle) * r)
	var tangent := Vector3(-sin(_angle), 0, cos(_angle))
	global_position = pos
	look_at(pos + tangent - Vector3(cos(_angle), 0, sin(_angle)) * _approach * 3.0, Vector3.UP)


func _process(delta: float) -> void:
	if _dying >= 0.0:
		_die_step(delta)
		return
	var before := global_position
	_place(delta)
	hull.velocity = (global_position - before) / maxf(delta, 0.0001)
	for t in turrets:
		if is_instance_valid(t):
			t.velocity = hull.velocity

	# Ramming the hull hurts.
	var player: TurboKat = combat.player
	if player.alive:
		var a := global_transform * Vector3(0, 0, -HULL_HALF_LENGTH)
		var b := global_transform * Vector3(0, 0, HULL_HALF_LENGTH)
		if Combat.point_capsule_dist(player.global_position, a, b) < HULL_RADIUS + 3.0:
			player.take_damage(40.0)
			player.grant_invulnerability(1.2)
			player.global_position += (player.global_position - global_position).normalized() * 25.0

	if phase == 1:
		_launch_cd -= delta
		if _launch_cd <= 0.0 and spawn_glider.is_valid() and combat.living_count("Creepling Glider") < 6:
			_launch_cd = 9.0
			spawn_glider.call(global_transform * Vector3(0, -HULL_RADIUS - 10.0, 20.0))
			spawn_glider.call(global_transform * Vector3(0, -HULL_RADIUS - 10.0, 40.0))


func _on_turret_died(t: Target) -> void:
	combat.explode(t.global_position, 2.0)
	t.visible = false
	var remaining := 0
	for tt in turrets:
		if tt.alive:
			remaining += 1
	if remaining == 0:
		phase = 1
		hull.invulnerable = false
		hull.lockable = true
		_hull_mat.albedo_color = Color(0.3, 0.12, 0.14)
		phase_changed.emit(1)


func _on_hull_died(_t: Target) -> void:
	_dying = 0.0
	destroyed.emit()


## Death sequence: chained explosions while the ship noses down and sinks.
func _die_step(dt: float) -> void:
	_dying += dt
	_boom_cd -= dt
	if _boom_cd <= 0.0 and _dying < 4.0:
		_boom_cd = 0.18
		var local := Vector3(randf_range(-25, 25), randf_range(-20, 20), randf_range(-HULL_HALF_LENGTH, HULL_HALF_LENGTH))
		combat.explode(global_transform * local, randf_range(1.5, 3.0))
	rotate_object_local(Vector3.RIGHT, -dt * 0.12)
	global_position.y -= dt * (10.0 + _dying * 12.0)
	if _dying > 5.0 or global_position.y < -60.0:
		combat.explode(global_position, 5.0)
		queue_free()
