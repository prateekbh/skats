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
## Reusable missile bodies, keyed by weapon id.
var _missile_pools := {}
## Pooled cartoon effects (explosions, hit stars, smoke trails).
var vfx: VFX
var _armor_ping_cd := 0.0
var _armor_msg_cd := 0.0

## Set by main: callback(text) to show a HUD message.
var on_message: Callable


func _ready() -> void:
	_player_mm = _make_tracer_mm(Color(1.0, 0.9, 0.45), Vector3(0.28, 0.28, 7.0))
	_enemy_mm = _make_tracer_mm(Color(1.0, 0.25, 0.2), Vector3(0.9, 0.9, 4.5))
	vfx = VFX.new()
	add_child(vfx)


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
		_recycle_missile(m)
	_missiles.clear()
	vfx.clear()
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
						spark(p1)
					hit = true
					break
		elif player_alive and seg_sphere(p0, p1, pp, 3.5 + b.size * 0.5):
			player.take_damage(b.dmg)
			hit = true
		if not hit and p1.y < city.height_at(p1.x, p1.z):
			if p1.distance_squared_to(pp) < 1500.0 * 1500.0:
				spark(p1, 0.6)
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

## Fires a missile described by `def` (see Arsenal; defaults to the homing missile).
## `target` may be null (dumb-fire). Missile bodies are pooled per type and reused;
## their exhaust is drawn by the VFX puff pool.
func fire_missile(pos: Vector3, dir: Vector3, launch_speed: float, target: Target, def: Dictionary = {}) -> void:
	if def.is_empty():
		def = Arsenal.HOMING
	var id: String = def.id
	if not _missile_pools.has(id):
		_missile_pools[id] = []
	var pool: Array = _missile_pools[id]
	var node: Node3D = pool.pop_back() if not pool.is_empty() else _build_missile(def)
	node.visible = true
	node.global_position = pos
	safe_look(node, dir)
	_missiles.append({
		"node": node, "def": def, "dir": dir.normalized(), "speed": launch_speed + 30.0,
		"target": target, "life": 7.0, "arm": 0.15, "trail": 0.0,
	})
	var big: bool = def.size > 1.2
	Sfx.play("missile", -2.0 if big else -5.0, 0.8 if big else 1.0)


func _build_missile(def: Dictionary) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var s: float = def.size
	var body_mat := MeshKit.toon(def.color, 0.4, 0.4)
	MeshKit.part(node, MeshKit.cyl(0.25 * s, 0.25 * s, 3.2 * s, 8), body_mat, Vector3.ZERO, Vector3(-PI / 2, 0, 0))
	MeshKit.part(node, MeshKit.cyl(0.0, 0.25 * s, 0.8 * s, 8), MeshKit.toon(Color(0.9, 0.2, 0.15)), Vector3(0, 0, -2.0 * s), Vector3(-PI / 2, 0, 0))
	MeshKit.part(node, MeshKit.sphere(0.5 * s, 8), MeshKit.glow(Color(1.0, 0.7, 0.3), true), Vector3(0, 0, 1.8 * s))
	return node


func _recycle_missile(m: Dictionary) -> void:
	var node: Node3D = m.node
	node.visible = false
	_missile_pools[m.def.id].append(node)


func _update_missiles(dt: float) -> void:
	for i in range(_missiles.size() - 1, -1, -1):
		var m := _missiles[i]
		var def: Dictionary = m.def
		var node: Node3D = m.node
		m.life -= dt
		m.arm -= dt
		m.speed = minf(m.speed + 380.0 * dt, def.speed)
		var tgt = m.target
		if tgt != null and (not is_instance_valid(tgt) or not tgt.alive):
			m.target = null
			tgt = null
		if tgt != null and m.arm <= 0.0:
			var to: Vector3 = (tgt.global_position - node.global_position).normalized()
			m.dir = steer(m.dir, to, def.turn * dt)
		var p0 := node.global_position
		var p1: Vector3 = p0 + m.dir * m.speed * dt
		node.global_position = p1
		safe_look(node, m.dir)
		# Exhaust: a puff every few metres of flight.
		var big: bool = def.size > 1.2
		m.trail += m.speed * dt
		var spacing := 4.0 if big else 5.0
		while m.trail >= spacing:
			m.trail -= spacing
			vfx.trail(p1 - m.dir * m.trail, big)
		var hit: Target = null
		if m.arm <= 0.0:
			for t in targets:
				if t.alive and (t.hit_test(p0, p1) or Combat.seg_sphere(p0, p1, t.global_position, t.radius + 3.0)):
					hit = t
					break
		if hit or p1.y < city.height_at(p1.x, p1.z) or m.life <= 0.0:
			_missile_hit(def, p1, hit)
			_recycle_missile(m)
			_missiles.remove_at(i)


## Applies a missile's effect where it detonated. `hit` is null for ground or timeout.
func _missile_hit(def: Dictionary, p: Vector3, hit: Target) -> void:
	match def.behaviour:
		"blast":
			explode(p, 3.2)
			if hit:
				hit.take_damage(def.damage, p)
			for t in targets:
				if t.alive and t.global_position.distance_to(p) < def.blast_radius + t.radius:
					t.take_damage(def.blast_damage, t.global_position)
		"stun":
			vfx.hit(p, 2.0)
			if hit:
				hit.take_damage(def.get("damage", 0.0), p)
				hit.stun(def.stun)
		"pierce":
			explode(p, 1.4)
			if hit:
				hit.take_damage(def.damage, p, true)
		_:
			explode(p, 1.2)
			if hit:
				hit.take_damage(def.damage, p)


# --- effects (drawn by the pooled VFX system) -----------------------------------------

func explode(pos: Vector3, scale := 1.0) -> void:
	vfx.explosion(pos, scale)
	if camera:
		Sfx.play_at("boom", pos, camera.global_position, 2.0 + scale * 2.0, randf_range(0.8, 1.1) / sqrt(scale))
		var d := pos.distance_to(camera.global_position)
		camera.add_shake(clampf(scale * 60.0 / maxf(d, 1.0), 0.0, 2.5))


func spark(pos: Vector3, intensity := 1.0) -> void:
	vfx.hit(pos, intensity)


func muzzle_flash(pos: Vector3) -> void:
	vfx.muzzle(pos)


## Hits on armored parts spark grey and remind the player where to aim.
func armor_ping(point: Vector3) -> void:
	if _armor_ping_cd > 0.0:
		return
	_armor_ping_cd = 0.08
	vfx.ricochet(point)
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
