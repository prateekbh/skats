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
## Octopus Missile tentacle rigs: reusable, and the ones currently holding a captive.
var _tentacle_pool: Array[Node3D] = []
var _captures: Array[Dictionary] = []
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


## The target struck by the segment p0→p1. When several overlap (a turret sitting on the
## warship's hull), the smallest one wins, so weak points are never shadowed by the hull.
func first_hit(p0: Vector3, p1: Vector3, extra_radius := 0.0) -> Target:
	var best: Target = null
	for t in targets:
		if not t.alive:
			continue
		if t.hit_test(p0, p1) or (extra_radius > 0.0 and Combat.seg_sphere(p0, p1, t.global_position, t.radius + extra_radius)):
			if best == null or t.radius < best.radius:
				best = t
	return best


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
	for c in _captures:
		c.rig.visible = false
		_tentacle_pool.append(c.rig)
	_captures.clear()
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
	_update_captures(delta)
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
			var t := first_hit(p0, p1)
			if t:
				var was_armored := t.invulnerable
				t.take_damage(b.dmg, p1)
				if not was_armored:
					stats.hits += 1
					spark(p1)
				hit = true
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


## Builds a missile body in its canon livery (see Arsenal for the swatkats.info notes).
func _build_missile(def: Dictionary) -> Node3D:
	var node := Node3D.new()
	add_child(node)
	var s: float = def.size
	var fwd := Vector3(-PI / 2, 0, 0)
	var body_mat := MeshKit.toon(def.color, 0.4, 0.4)
	var red := MeshKit.toon(Color(0.9, 0.2, 0.15))
	var steel := MeshKit.toon(Color(0.7, 0.72, 0.78), 0.8, 0.25)
	MeshKit.part(node, MeshKit.cyl(0.25 * s, 0.25 * s, 3.2 * s, 8), body_mat, Vector3.ZERO, fwd)
	MeshKit.part(node, MeshKit.sphere(0.5 * s, 8), MeshKit.glow(Color(1.0, 0.7, 0.3), true), Vector3(0, 0, 1.8 * s))
	for k in 4: # tail fins
		var a := TAU * k / 4.0
		MeshKit.part(node, MeshKit.box(Vector3(0.05, 0.6 * s, 0.6 * s)), body_mat, Vector3(sin(a), cos(a), 0) * 0.35 * s + Vector3(0, 0, 1.3 * s), Vector3(0, 0, a))
	match def.model:
		"octopus":
			# Folded tentacles wrapped around a bulbous head.
			MeshKit.part(node, MeshKit.sphere(0.45 * s, 10), body_mat, Vector3(0, 0, -1.8 * s))
			for k in 6:
				var a := TAU * k / 6.0
				MeshKit.part(node, MeshKit.cyl(0.06 * s, 0.1 * s, 1.6 * s, 6), MeshKit.toon(def.color.darkened(0.25)),
					Vector3(sin(a), cos(a), 0) * 0.3 * s + Vector3(0, 0, -0.9 * s), fwd)
		"buzzsaw":
			# Red casing with the grinning shark decal and the saw blade at the nose.
			MeshKit.part(node, MeshKit.cyl(0.0, 0.25 * s, 0.7 * s, 8), red, Vector3(0, 0, -1.95 * s), fwd)
			MeshKit.part(node, MeshKit.box(Vector3(0.36 * s, 0.08 * s, 0.7 * s)), MeshKit.toon(Color(0.95, 0.95, 0.95)), Vector3(0, -0.2 * s, -1.1 * s))
			MeshKit.part(node, MeshKit.sphere(0.07 * s, 6), MeshKit.toon(Color(0.05, 0.05, 0.05)), Vector3(0.18 * s, 0.12 * s, -1.4 * s))
			var saw := Node3D.new()
			saw.name = "Spin"
			saw.position = Vector3(0, 0, -2.3 * s)
			node.add_child(saw)
			MeshKit.part(saw, MeshKit.cyl(0.8 * s, 0.8 * s, 0.06, 14), steel, Vector3.ZERO, fwd)
			for k in 10:
				var a := TAU * k / 10.0
				MeshKit.part(saw, MeshKit.box(Vector3(0.16 * s, 0.3 * s, 0.06)), steel, Vector3(sin(a), cos(a), 0) * 0.88 * s, Vector3(0, 0, -a))
		"scrambler":
			# Rounded discharge nose and the lightning-bolt marking.
			MeshKit.part(node, MeshKit.sphere(0.3 * s, 10), MeshKit.toon(Color(0.85, 0.85, 0.9), 0.7, 0.3), Vector3(0, 0, -1.65 * s))
			var bolt := PackedVector2Array()
			for v in [Vector2(-0.12, -0.5), Vector2(0.1, -0.05), Vector2(-0.02, -0.02), Vector2(0.12, 0.5), Vector2(-0.1, 0.05), Vector2(0.02, 0.02)]:
				bolt.append(v * s)
			MeshKit.part(node, MeshKit.slab(bolt, 0.04),
				MeshKit.glow(Color(1.0, 0.85, 0.1)), Vector3(0.26 * s, 0, -0.3 * s), Vector3(0, 0, PI / 2))
		"slicer":
			# Bladed nose: four steel cutting fins.
			MeshKit.part(node, MeshKit.cyl(0.0, 0.25 * s, 0.9 * s, 8), steel, Vector3(0, 0, -2.05 * s), fwd)
			for k in 4:
				var a := TAU * k / 4.0 + PI / 4.0
				MeshKit.part(node, MeshKit.box(Vector3(0.03, 0.55 * s, 1.0 * s)), steel, Vector3(sin(a), cos(a), 0) * 0.3 * s + Vector3(0, 0, -1.5 * s), Vector3(0, 0, a))
		"matchhead":
			# The match-like ball tip that ignites after launch.
			MeshKit.part(node, MeshKit.sphere(0.42 * s, 12), MeshKit.glow(Color(1.0, 0.35, 0.1)), Vector3(0, 0, -1.9 * s))
			MeshKit.part(node, MeshKit.sphere(0.55 * s, 12), MeshKit.glow(Color(1.0, 0.75, 0.2, 0.7), true), Vector3(0, 0, -1.9 * s))
		_:
			MeshKit.part(node, MeshKit.cyl(0.0, 0.25 * s, 0.8 * s, 8), red, Vector3(0, 0, -2.0 * s), fwd)
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
		var spin := node.get_node_or_null("Spin")
		if spin:
			spin.rotate_z(dt * 40.0)
		# Exhaust: a puff every few metres of flight.
		var big: bool = def.size > 1.2
		m.trail += m.speed * dt
		var spacing := 4.0 if big else 5.0
		while m.trail >= spacing:
			m.trail -= spacing
			vfx.trail(p1 - m.dir * m.trail, big)
		var hit: Target = null
		if m.arm <= 0.0:
			# Proximity fuse: once close to its own target, a guided missile only goes for it,
			# so a turret's hull can't intercept a missile aimed at the turret.
			if tgt != null and p1.distance_to(tgt.global_position) < tgt.radius + 40.0:
				if Combat.seg_sphere(p0, p1, tgt.global_position, tgt.radius + 6.0):
					hit = tgt
			else:
				hit = first_hit(p0, p1, 3.0)
		if hit or p1.y < city.height_at(p1.x, p1.z) or m.life <= 0.0:
			_missile_hit(def, p1, hit)
			_recycle_missile(m)
			_missiles.remove_at(i)


## Applies a missile's effect where it detonated. `hit` is null for ground or timeout.
func _missile_hit(def: Dictionary, p: Vector3, hit: Target) -> void:
	match def.behaviour:
		"capture":
			# Octopus: restrain the target. A captured glider loses lift and falls.
			vfx.hit(p, 1.5)
			if hit:
				hit.take_damage(def.damage, p)
				var falls := hit is Creepling
				hit.stun(60.0 if falls else def.hold)
				hit.captured = true
				_attach_tentacles(hit, def)
		"barrage":
			# Buzz-Saw: non-explosive cut, extra effective against wings.
			vfx.hit(p, 1.8)
			if hit:
				var mult: float = def.wing_bonus if hit is Creepling else 1.0
				hit.take_damage(def.damage * mult, p)
		"scramble":
			# Scrambler: a million-megavolt discharge shorts out everything nearby.
			vfx.electric(p, def.radius)
			if camera:
				Sfx.play_at("armor", p, camera.global_position, 4.0, 0.5)
			for t in targets:
				if t.alive and t.global_position.distance_to(p) < def.radius + t.radius:
					t.take_damage(def.damage, t.global_position)
					t.stun(def.disable)
		"pierce":
			# Slicer: cuts through armor.
			explode(p, 1.1)
			if hit:
				hit.take_damage(def.damage, p, true)
		"blast":
			# Match Head: explosive-incendiary.
			explode(p, 3.2)
			if hit:
				hit.take_damage(def.damage, p)
			for t in targets:
				if t.alive and t.global_position.distance_to(p) < def.radius + t.radius:
					t.take_damage(def.radius_damage, t.global_position)
					t.ignite(4.0, def.burn)
		_:
			explode(p, 1.2)
			if hit:
				hit.take_damage(def.damage, p)


# --- Octopus tentacle rigs (pooled, follow their captive) ------------------------------

func _attach_tentacles(t: Target, def: Dictionary) -> void:
	var rig: Node3D = _tentacle_pool.pop_back() if not _tentacle_pool.is_empty() else _build_tentacles(def)
	rig.visible = true
	rig.scale = Vector3.ONE * clampf(t.radius / 6.0, 0.8, 3.0)
	_captures.append({"rig": rig, "target": t, "t": 0.0})


func _build_tentacles(def: Dictionary) -> Node3D:
	var rig := Node3D.new()
	add_child(rig)
	var mat := MeshKit.toon(def.color, 0.2, 0.5)
	for k in 8:
		var a := TAU * k / 8.0
		var arm := MeshKit.part(rig, MeshKit.cyl(0.25, 0.5, 9.0, 6), mat, Vector3(sin(a), cos(a), 0) * 3.2, Vector3(0, 0, -a))
		arm.rotation.x = 0.35
	MeshKit.part(rig, MeshKit.sphere(2.0, 10), mat, Vector3(0, 0, -3.0))
	return rig


func _update_captures(dt: float) -> void:
	for i in range(_captures.size() - 1, -1, -1):
		var c := _captures[i]
		var t = c.target
		var rig: Node3D = c.rig
		c.t += dt
		if not is_instance_valid(t) or not t.alive or not t.captured:
			rig.visible = false
			_tentacle_pool.append(rig)
			_captures.remove_at(i)
			continue
		rig.global_position = t.global_position
		rig.rotation = Vector3(0, c.t * 1.5, sin(c.t * 4.0) * 0.2)


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
