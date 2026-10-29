class_name Combat
extends Node3D
## Runtime combat systems: target registry, bullets (drawn with two MultiMeshes),
## missiles, explosions, sparks and pickups. Uses plain maths instead of physics bodies.

signal target_killed(target: Target)

const MAX_BULLETS := 600
const PLAYER_TEAM := 0
const ENEMY_TEAM := 1

var player: TurboKat
var city: City
var camera: ChaseCamera

var targets: Array[Target] = []
## How many enemies may attack the player at once; the rest circle and wait their turn.
var attack_tokens := 4
var stats := {"shots": 0, "hits": 0, "kills": 0, "score": 0}

# Bullet = {p: Vector3, v: Vector3, life: float, dmg: float, team: int, size: float}
var _bullets: Array[Dictionary] = []
var _missiles: Array[Dictionary] = []
var _pickups: Array[Node3D] = []
var _player_mm: MultiMesh
var _enemy_mm: MultiMesh
var _fire_mat: StandardMaterial3D
var _smoke_mat: StandardMaterial3D
var _armor_ping_cd := 0.0
var _armor_msg_cd := 0.0

## Set by main: callback(text) to show a HUD message.
var on_message: Callable


func _ready() -> void:
	_player_mm = _make_tracer_mm(Color(1.0, 0.9, 0.45), Vector3(0.28, 0.28, 7.0))
	_enemy_mm = _make_tracer_mm(Color(1.0, 0.25, 0.2), Vector3(0.9, 0.9, 4.5))
	_fire_mat = MeshKit.particle_material(true)
	_smoke_mat = MeshKit.particle_material(false)


func _make_tracer_mm(color: Color, size: Vector3) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = MeshKit.box(size)
	mm.instance_count = MAX_BULLETS
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MeshKit.glow(color)
	mmi.custom_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 8000, 40000))
	add_child(mmi)
	return mm


# --- maths helpers -------------------------------------------------------------------

static func seg_sphere(p0: Vector3, p1: Vector3, c: Vector3, r: float) -> bool:
	var d := p1 - p0
	var len2 := d.length_squared()
	var t := 0.0
	if len2 > 0.000001:
		t = clampf((c - p0).dot(d) / len2, 0.0, 1.0)
	return (p0 + d * t).distance_squared_to(c) < r * r


static func point_capsule_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Rotates unit vector `dir` toward `desired` by at most `max_angle` radians.
static func steer(dir: Vector3, desired: Vector3, max_angle: float) -> Vector3:
	var ang := dir.angle_to(desired)
	if ang < 0.0001:
		return desired
	return dir.slerp(desired, minf(1.0, max_angle / ang)).normalized()


static func safe_look(node: Node3D, dir: Vector3, up := Vector3.UP) -> void:
	if dir.length_squared() < 0.0001:
		return
	if absf(dir.normalized().dot(up)) > 0.995:
		up = Vector3.RIGHT
	node.look_at(node.global_position + dir, up)


# --- registry ---------------------------------------------------------------------

func add_target(t: Target, parent: Node = null) -> Target:
	t.combat = self
	(parent if parent else self).add_child(t)
	targets.append(t)
	t.died.connect(_on_target_died)
	t.tree_exiting.connect(func(): targets.erase(t))
	return t


func living_count(filter := "") -> int:
	var n := 0
	for t in targets:
		if t.alive and (filter == "" or t.display_name == filter):
			n += 1
	return n


func _on_target_died(t: Target) -> void:
	stats.kills += 1
	stats.score += t.score
	target_killed.emit(t)


func clear() -> void:
	for t in targets:
		if is_instance_valid(t) and t.get_parent() == self:
			t.queue_free()
	targets.clear()
	_bullets.clear()
	for m in _missiles:
		if is_instance_valid(m.node):
			m.node.queue_free()
	_missiles.clear()
	for p in _pickups:
		if is_instance_valid(p):
			p.queue_free()
	_pickups.clear()
	stats = {"shots": 0, "hits": 0, "kills": 0, "score": 0}
	attack_tokens = 4


# --- bullets ----------------------------------------------------------------------

func fire_bullet(pos: Vector3, vel: Vector3, team: int, dmg: float, life := 1.6, size := 1.0) -> void:
	if _bullets.size() >= MAX_BULLETS:
		return
	_bullets.append({"p": pos, "v": vel, "life": life, "dmg": dmg, "team": team, "size": size})
	if team == PLAYER_TEAM:
		stats.shots += 1


func _process(delta: float) -> void:
	_armor_ping_cd -= delta
	_armor_msg_cd -= delta
	_update_bullets(delta)
	_update_missiles(delta)
	_update_pickups(delta)
	_prune_targets()


func _prune_targets() -> void:
	for i in range(targets.size() - 1, -1, -1):
		if not is_instance_valid(targets[i]):
			targets.remove_at(i)


func _update_bullets(dt: float) -> void:
	var pp: Vector3 = player.global_position
	var player_alive: bool = player.alive
	for i in range(_bullets.size() - 1, -1, -1):
		var b := _bullets[i]
		var p0: Vector3 = b.p
		var p1: Vector3 = p0 + b.v * dt
		b.life -= dt
		var hit := false
		if b.team == PLAYER_TEAM:
			for t in targets:
				if t.alive and t.hit_test(p0, p1):
					var was_armored := t.invulnerable
					t.take_damage(b.dmg, p1)
					if not was_armored:
						stats.hits += 1
						spark(p1, Color(1.0, 0.8, 0.4), 6)
					hit = true
					break
		elif player_alive and seg_sphere(p0, p1, pp, 3.5 + b.size * 0.5):
			player.take_damage(b.dmg)
			hit = true
		if not hit and p1.y < city.height_at(p1.x, p1.z):
			if p1.distance_squared_to(pp) < 1500.0 * 1500.0:
				spark(p1, Color(0.9, 0.85, 0.7), 4)
			hit = true
		if hit or b.life <= 0.0:
			_bullets.remove_at(i)
		else:
			b.p = p1
	_draw_bullets()


func _draw_bullets() -> void:
	var np := 0
	var ne := 0
	for b in _bullets:
		var dir: Vector3 = (b.v as Vector3).normalized()
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		var basis := Basis.looking_at(dir, up)
		if b.team == PLAYER_TEAM:
			_player_mm.set_instance_transform(np, Transform3D(basis, b.p))
			np += 1
		else:
			_enemy_mm.set_instance_transform(ne, Transform3D(basis.scaled(Vector3.ONE * b.size), b.p))
			ne += 1
	_player_mm.visible_instance_count = np
	_enemy_mm.visible_instance_count = ne


# --- missiles ---------------------------------------------------------------------

## Fires a homing missile. `target` may be null (dumb-fire). `mega` = big special missile.
func fire_missile(pos: Vector3, dir: Vector3, launch_speed: float, target: Target, mega := false) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	var body_mat := MeshKit.toon(Color(0.9, 0.9, 0.92) if not mega else Color(0.95, 0.75, 0.15), 0.4, 0.4)
	var s := 1.8 if mega else 1.0
	MeshKit.part(node, MeshKit.cyl(0.25 * s, 0.25 * s, 3.2 * s, 8), body_mat, Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	MeshKit.part(node, MeshKit.cyl(0.0, 0.25 * s, 0.8 * s, 8), MeshKit.toon(Color(0.9, 0.2, 0.15)), Vector3(0, 0, -2.0 * s), Vector3(-PI / 2, 0, 0))
	MeshKit.part(node, MeshKit.sphere(0.5 * s, 8), MeshKit.glow(Color(1.0, 0.7, 0.3), true), Vector3(0, 0, 1.8 * s))
	var trail := _make_trail(mega)
	add_child(trail)
	trail.global_position = pos
	safe_look(node, dir)
	_missiles.append({
		"node": node, "trail": trail, "dir": dir.normalized(), "speed": launch_speed + 30.0,
		"target": target, "life": 7.0, "mega": mega, "arm": 0.15,
	})
	Sfx.play("missile", -2.0 if mega else -5.0, 0.8 if mega else 1.0)


func _make_trail(mega: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 90 if mega else 60
	p.lifetime = 1.4
	p.local_coords = false
	p.mesh = _quad(_smoke_mat)
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 1.2 if mega else 0.8
	p.scale_amount_max = 2.0 if mega else 1.4
	p.scale_amount_curve = _curve(1.0, 4.0)
	p.color_ramp = _gradient([Color(1.0, 0.85, 0.5, 0.9), Color(0.7, 0.7, 0.72, 0.5), Color(0.6, 0.6, 0.65, 0.0)])
	return p


func _update_missiles(dt: float) -> void:
	for i in range(_missiles.size() - 1, -1, -1):
		var m := _missiles[i]
		var node: Node3D = m.node
		m.life -= dt
		m.arm -= dt
		m.speed = minf(m.speed + 380.0 * dt, 560.0 if not m.mega else 420.0)
		var tgt = m.target
		if tgt != null and (not is_instance_valid(tgt) or not tgt.alive):
			m.target = null
			tgt = null
		if tgt != null and m.arm <= 0.0:
			var to: Vector3 = (tgt.global_position - node.global_position).normalized()
			m.dir = steer(m.dir, to, (2.8 if not m.mega else 1.8) * dt)
		var p0 := node.global_position
		var p1: Vector3 = p0 + m.dir * m.speed * dt
		node.global_position = p1
		safe_look(node, m.dir)
		var trail: CPUParticles3D = m.trail
		trail.global_position = p1
		var boom := false
		if m.arm <= 0.0:
			for t in targets:
				if t.alive and (t.hit_test(p0, p1) or Combat.seg_sphere(p0, p1, t.global_position, t.radius + 3.0)):
					t.take_damage(450.0 if m.mega else 120.0, p1)
					boom = true
					break
		if not boom and (p1.y < city.height_at(p1.x, p1.z) or m.life <= 0.0):
			boom = true
		if boom:
			if m.mega:
				explode(p1, 3.2)
				for t in targets:
					if t.alive and t.global_position.distance_to(p1) < 90.0 + t.radius:
						t.take_damage(220.0, t.global_position)
			else:
				explode(p1, 1.2)
			trail.emitting = false
			get_tree().create_timer(1.6).timeout.connect(trail.queue_free)
			node.queue_free()
			_missiles.remove_at(i)


# --- effects ----------------------------------------------------------------------

func _quad(mat: Material) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = mat
	return q


func _curve(start: float, end: float) -> Curve:
	var c := Curve.new()
	c.max_value = maxf(start, end)
	c.add_point(Vector2(0, start))
	c.add_point(Vector2(1, end))
	return c


func _gradient(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for k in colors.size():
		offsets.append(float(k) / (colors.size() - 1))
		cols.append(colors[k])
	g.offsets = offsets
	g.colors = cols
	return g


func _burst(pos: Vector3, mat: Material, amount: int, life: float, vel: Vector2, size: Vector2, grow: float, colors: Array, gravity := Vector3.ZERO, damping := 0.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = maxi(amount, 1)
	p.lifetime = life
	p.local_coords = false
	p.mesh = _quad(mat)
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = vel.x
	p.initial_velocity_max = vel.y
	p.gravity = gravity
	p.damping_min = damping
	p.damping_max = damping
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.scale_amount_curve = _curve(1.0, grow)
	p.color_ramp = _gradient(colors)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
	return p


func explode(pos: Vector3, scale := 1.0) -> void:
	var s := scale
	_burst(pos, _fire_mat, int(26 * s), 0.9, Vector2(12, 45) * s, Vector2(5, 10) * s, 2.2,
		[Color(1, 1, 0.8, 1), Color(1, 0.6, 0.15, 0.9), Color(0.8, 0.15, 0.05, 0.0)], Vector3(0, 6, 0), 2.0 * s)
	_burst(pos, _smoke_mat, int(16 * s), 2.6, Vector2(6, 22) * s, Vector2(7, 12) * s, 3.0,
		[Color(0.3, 0.27, 0.27, 0.0), Color(0.2, 0.19, 0.2, 0.75), Color(0.15, 0.15, 0.17, 0.0)], Vector3(0, 8, 0), 1.5 * s)
	_burst(pos, _fire_mat, int(18 * s), 0.7, Vector2(60, 140) * s, Vector2(0.8, 1.6), 0.3,
		[Color(1, 0.95, 0.7, 1), Color(1, 0.5, 0.1, 0.0)], Vector3(0, -60, 0))
	# Flash ball.
	var flash := MeshKit.part(self, MeshKit.sphere(1.0, 12), MeshKit.glow(Color(1.0, 0.75, 0.4), true))
	flash.global_position = pos
	flash.scale = Vector3.ONE * 2.0 * s
	var tw := create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * 14.0 * s, 0.25)
	tw.parallel().tween_property(flash.material_override, "albedo_color:a", 0.0, 0.3)
	tw.tween_callback(flash.queue_free)
	if camera:
		Sfx.play_at("boom", pos, camera.global_position, 2.0 + s * 2.0, randf_range(0.8, 1.1) / sqrt(s))
		var d := pos.distance_to(camera.global_position)
		camera.add_shake(clampf(s * 60.0 / maxf(d, 1.0), 0.0, 2.5))


func spark(pos: Vector3, color: Color, amount := 6) -> void:
	_burst(pos, _fire_mat, amount, 0.35, Vector2(20, 60), Vector2(0.6, 1.2), 0.2, [color, Color(color, 0.0)], Vector3(0, -30, 0))


func muzzle_flash(pos: Vector3) -> void:
	_burst(pos, _fire_mat, 2, 0.06, Vector2(0, 4), Vector2(2.0, 3.0), 0.5, [Color(1, 0.9, 0.6, 1), Color(1, 0.6, 0.2, 0)])


## Hits on armored parts spark grey and remind the player where to aim.
func armor_ping(point: Vector3) -> void:
	if _armor_ping_cd > 0.0:
		return
	_armor_ping_cd = 0.08
	spark(point, Color(0.7, 0.75, 0.85), 4)
	if camera:
		Sfx.play_at("armor", point, camera.global_position, -6.0)
	if _armor_msg_cd <= 0.0 and on_message.is_valid():
		_armor_msg_cd = 4.0
		on_message.call("ARMORED: HIT THE WEAK POINTS")


# --- pickups ----------------------------------------------------------------------

func drop_pickup(pos: Vector3, kind: String) -> void:
	var node := Node3D.new()
	add_child(node)
	node.global_position = pos
	node.set_meta("kind", kind)
	node.set_meta("life", 25.0)
	var col := Color(0.3, 1.0, 0.5) if kind == "repair" else Color(1.0, 0.7, 0.2)
	MeshKit.part(node, MeshKit.sphere(3.2, 12), MeshKit.glow(col, true), Vector3.ZERO, Vector3.ZERO, Vector3.ONE)
	if kind == "repair":
		MeshKit.part(node, MeshKit.box(Vector3(4.5, 1.3, 1.3)), MeshKit.glow(Color.WHITE))
		MeshKit.part(node, MeshKit.box(Vector3(1.3, 4.5, 1.3)), MeshKit.glow(Color.WHITE))
	else:
		MeshKit.part(node, MeshKit.cyl(0.6, 0.6, 4.0, 8), MeshKit.glow(Color.WHITE))
	_pickups.append(node)


func _update_pickups(dt: float) -> void:
	for i in range(_pickups.size() - 1, -1, -1):
		var p := _pickups[i]
		var life: float = p.get_meta("life") - dt
		p.set_meta("life", life)
		p.rotate_y(dt * 2.0)
		p.global_position.y += sin(life * 3.0) * dt * 2.0
		if player.alive and p.global_position.distance_to(player.global_position) < 16.0:
			player.collect(p.get_meta("kind"))
			Sfx.play("pickup", -4.0)
			p.queue_free()
			_pickups.remove_at(i)
		elif life <= 0.0:
			p.queue_free()
			_pickups.remove_at(i)
