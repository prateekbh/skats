class_name VFX
extends Node3D
## Pooled cartoon effects. Each effect type is one MultiMesh with a fixed capacity and
## packed arrays of particle state, so explosions, hit stars, muzzle flashes and smoke
## trails never create or free nodes during play (no GC hitches on the web).

const PuffShader := preload("res://shaders/toon_puff.gdshader")
const FlashShader := preload("res://shaders/toon_flash.gdshader")

const KIND_FIRE := 0.0
const KIND_SMOKE := 0.33
const KIND_DUST := 0.66
const KIND_TRAIL := 1.0


## A fixed-size pool of particles drawn by one MultiMesh. Dead particles are swap-removed,
## so live ones stay packed at the front and only `count` instances are drawn.
class Pool:
	var mm: MultiMesh
	var cap: int
	var count := 0
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var size0 := PackedFloat32Array()
	var size1 := PackedFloat32Array()
	var seed := PackedFloat32Array()
	var kind := PackedFloat32Array() # puffs: KIND_*, flashes: intensity
	var drag := PackedFloat32Array()
	var lift := PackedFloat32Array()
	var tint := PackedFloat32Array() # flashes: 0 = fire colours, 1 = electric blue; trail puffs: colour id
	## Frozen pools don't move their particles (beam segments keep `vel` as their vector).
	var frozen := false

	func _init(capacity: int, mesh: Mesh, material: Material, parent: Node3D, use_colors := false) -> void:
		cap = capacity
		pos.resize(cap)
		vel.resize(cap)
		age.resize(cap)
		life.resize(cap)
		size0.resize(cap)
		size1.resize(cap)
		seed.resize(cap)
		kind.resize(cap)
		drag.resize(cap)
		lift.resize(cap)
		tint.resize(cap)
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = use_colors
		mm.mesh = mesh
		mm.instance_count = cap
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.custom_aabb = AABB(Vector3(-20000, -2000, -20000), Vector3(40000, 8000, 40000))
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)

	## Adds a particle; when full, the oldest slot (index 0) is recycled.
	func spawn(p: Vector3, v: Vector3, lifetime: float, s0: float, s1: float, k: float, drag_k := 1.5, lift_k := 0.0, tint_k := 0.0) -> void:
		var i := count
		if count >= cap:
			i = 0
		else:
			count += 1
		pos[i] = p
		vel[i] = v
		age[i] = 0.0
		life[i] = lifetime
		size0[i] = s0
		size1[i] = s1
		seed[i] = randf()
		kind[i] = k
		drag[i] = drag_k
		lift[i] = lift_k
		tint[i] = tint_k

	func step(dt: float) -> void:
		var i := count - 1
		while i >= 0:
			age[i] += dt
			if age[i] >= life[i]:
				_remove(i)
			elif not frozen:
				var v := vel[i] * maxf(0.0, 1.0 - drag[i] * dt)
				v.y += lift[i] * dt
				vel[i] = v
				pos[i] += v * dt
			i -= 1

	func _remove(i: int) -> void:
		var last := count - 1
		if i != last:
			pos[i] = pos[last]
			vel[i] = vel[last]
			age[i] = age[last]
			life[i] = life[last]
			size0[i] = size0[last]
			size1[i] = size1[last]
			seed[i] = seed[last]
			kind[i] = kind[last]
			drag[i] = drag[last]
			lift[i] = lift[last]
			tint[i] = tint[last]
		count -= 1

	## Uniform-scale instances that grow from size0 to size1 with an ease-out.
	func draw_scaled() -> void:
		for i in count:
			var t := age[i] / life[i]
			var s := lerpf(size0[i], size1[i], 1.0 - pow(1.0 - t, 3.0))
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), pos[i]))
			mm.set_instance_custom_data(i, Color(t, seed[i], kind[i], tint[i]))
		mm.visible_instance_count = count

	## Streaks stretched along their velocity (debris and sparks).
	func draw_streaks() -> void:
		for i in count:
			var t := age[i] / life[i]
			var v := vel[i]
			var speed := v.length()
			var dir := v / speed if speed > 0.01 else Vector3.FORWARD
			var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
			var thick := lerpf(size0[i], size1[i], t)
			var basis := Basis.looking_at(dir, up).scaled(Vector3(thick, thick, clampf(speed * 0.045, 0.6, 7.0)))
			mm.set_instance_transform(i, Transform3D(basis, pos[i]))
			mm.set_instance_color(i, Color(1.0, lerpf(0.95, 0.45, t), lerpf(0.7, 0.1, t)))
			mm.set_instance_custom_data(i, Color(t, seed[i], 1.0, 0.0))
		mm.visible_instance_count = count


var puffs: Pool
var beams: Pool
var stars: Pool
var rings: Pool
var streaks: Pool


func _ready() -> void:
	var puff_mat := ShaderMaterial.new()
	puff_mat.shader = PuffShader
	puffs = Pool.new(700, _icosphere(), puff_mat, self)

	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var star_mat := ShaderMaterial.new()
	star_mat.shader = FlashShader
	star_mat.set_shader_parameter("shape", 0)
	stars = Pool.new(160, quad, star_mat, self)
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = FlashShader
	ring_mat.set_shader_parameter("shape", 1)
	ring_mat.set_shader_parameter("edge_color", Color(1.0, 0.45, 0.2))
	rings = Pool.new(48, quad, ring_mat, self)

	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.vertex_color_use_as_albedo = true
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beams = Pool.new(300, MeshKit.box(Vector3(1, 1, 1)), beam_mat, self, true)
	beams.frozen = true

	var streak_mat := StandardMaterial3D.new()
	streak_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	streak_mat.vertex_color_use_as_albedo = true
	streaks = Pool.new(400, MeshKit.box(Vector3(1, 1, 1)), streak_mat, self, true)


func _icosphere() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


func _process(delta: float) -> void:
	puffs.step(delta)
	beams.step(delta)
	stars.step(delta)
	rings.step(delta)
	streaks.step(delta)
	for i in streaks.count:
		streaks.vel[i].y -= 70.0 * delta # debris falls
	puffs.draw_scaled()
	_draw_beams()
	stars.draw_scaled()
	rings.draw_scaled()
	streaks.draw_streaks()


## Beam segments: `vel` holds the segment vector, size0 its thickness; they fade out.
func _draw_beams() -> void:
	for i in beams.count:
		var t := beams.age[i] / beams.life[i]
		var seg := beams.vel[i]
		var length := seg.length()
		var dir := seg / length if length > 0.001 else Vector3.FORWARD
		var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
		var th := beams.size0[i] * (1.0 - t * 0.7)
		var basis := Basis.looking_at(dir, up).scaled(Vector3(th, th, length))
		beams.mm.set_instance_transform(i, Transform3D(basis, beams.pos[i]))
		beams.mm.set_instance_color(i, Color(0.75, 0.95, 1.0, 1.0 - t))
	beams.mm.visible_instance_count = beams.count


func clear() -> void:
	puffs.count = 0
	beams.count = 0
	stars.count = 0
	rings.count = 0
	streaks.count = 0


static func _rand_dir() -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()


# --- effects --------------------------------------------------------------------------

## Cartoon explosion: flash star, shockwave ring, banded fireball cluster, smoke and debris.
func explosion(p: Vector3, scale := 1.0) -> void:
	var s := scale
	stars.spawn(p, Vector3.ZERO, 0.16, 6.0 * s, 14.0 * s, 1.0, 0.0)
	rings.spawn(p, Vector3.ZERO, 0.38, 3.0 * s, 26.0 * s, 0.9, 0.0)
	var fire := int(5 + 5 * s)
	for k in fire:
		var d := _rand_dir()
		puffs.spawn(p + d * randf_range(0.0, 2.5) * s, d * randf_range(8.0, 24.0) * s,
			randf_range(0.55, 0.95), randf_range(1.5, 3.0) * s, randf_range(4.5, 8.5) * s, KIND_FIRE, 3.0, 6.0)
	var smoke := int(3 + 4 * s)
	for k in smoke:
		var d := _rand_dir()
		puffs.spawn(p + d * 2.0 * s, d * randf_range(4.0, 12.0) * s + Vector3.UP * 6.0,
			randf_range(1.4, 2.4), randf_range(2.0, 3.5) * s, randf_range(6.0, 10.0) * s, KIND_SMOKE, 1.4, 5.0)
	for k in int(10 * s + 4):
		streaks.spawn(p, _rand_dir() * randf_range(60.0, 150.0) * sqrt(s), randf_range(0.4, 0.8), 0.35, 0.15, 0.0, 0.8)


## Bullet impact: a small star and a few sparks.
func hit(p: Vector3, intensity := 1.0) -> void:
	stars.spawn(p, Vector3.ZERO, 0.12, 1.2, 3.2 * intensity, intensity, 0.0)
	for k in 3:
		streaks.spawn(p, _rand_dir() * randf_range(40.0, 90.0), randf_range(0.2, 0.35), 0.18, 0.08, 0.0, 1.0)


## Shots bouncing off armour: grey star and sparks.
func ricochet(p: Vector3) -> void:
	stars.spawn(p, Vector3.ZERO, 0.1, 1.0, 2.6, 0.6, 0.0)
	for k in 4:
		streaks.spawn(p, _rand_dir() * randf_range(50.0, 110.0), 0.25, 0.15, 0.06, 0.0, 1.0)


func muzzle(p: Vector3) -> void:
	stars.spawn(p, Vector3.ZERO, 0.05, 0.8, 1.6, 0.9, 0.0)


## One puff of missile exhaust (called every few metres of flight).
func trail(p: Vector3, big := false) -> void:
	var s := (1.6 if big else 1.0) * randf_range(0.8, 1.25)
	puffs.spawn(p + _rand_dir() * 0.6 * s, _rand_dir() * 2.0, randf_range(0.7, 1.05), 1.0 * s, 3.2 * s, KIND_TRAIL, 2.0, 2.0)


## Scrambler discharge: a blue shockwave, electric stars and arcing sparks.
func electric(p: Vector3, radius: float) -> void:
	rings.spawn(p, Vector3.ZERO, 0.45, 4.0, radius * 1.15, 1.0, 0.0, 0.0, 1.0)
	stars.spawn(p, Vector3.ZERO, 0.22, 6.0, 16.0, 1.0, 0.0, 0.0, 1.0)
	for k in 6:
		stars.spawn(p + _rand_dir() * radius * randf_range(0.2, 0.7), Vector3.ZERO, randf_range(0.12, 0.3), 2.0, 6.0, 1.0, 0.0, 0.0, 1.0)


## A small electric crackle on a disabled target.
func crackle(p: Vector3) -> void:
	stars.spawn(p + _rand_dir() * 3.0, Vector3.ZERO, 0.12, 1.0, 3.5, 0.9, 0.0, 0.0, 1.0)


## A lick of flame on a burning target.
func burn(p: Vector3) -> void:
	puffs.spawn(p + _rand_dir() * 2.0, Vector3.UP * 8.0 + _rand_dir() * 3.0, randf_range(0.35, 0.6), 1.0, 2.6, KIND_FIRE, 2.0, 10.0)


# --- missile trails (one look per missile type, see Arsenal "trail") ---------------------

## Octopus: puffs of pink ink.
func ink(p: Vector3) -> void:
	puffs.spawn(p + _rand_dir() * 0.5, _rand_dir() * 1.5, randf_range(0.6, 0.9), 0.8, 2.6, KIND_TRAIL, 2.0, 0.5, 1.0)


## Buzz-Saw: showers of sparks thrown off the spinning blade.
func sparks(p: Vector3) -> void:
	for k in 2:
		streaks.spawn(p, _rand_dir() * randf_range(30.0, 70.0), randf_range(0.2, 0.35), 0.14, 0.05, 0.0, 1.0)


## Scrambler: electric crackles and a blue haze.
func electric_trail(p: Vector3) -> void:
	stars.spawn(p + _rand_dir() * 1.5, Vector3.ZERO, randf_range(0.1, 0.18), 0.8, 2.6, 0.9, 0.0, 0.0, 1.0)
	puffs.spawn(p, _rand_dir(), 0.5, 0.4, 1.4, KIND_TRAIL, 2.0, 0.0, 2.0)


## Slicer: a glowing beam segment from a to b.
func beam(a: Vector3, b: Vector3, thickness := 0.35) -> void:
	beams.spawn((a + b) * 0.5, b - a, 0.35, thickness, thickness, 0.0, 0.0)


## Match Head: a burning tail.
func fire_trail(p: Vector3) -> void:
	puffs.spawn(p + _rand_dir() * 0.5, _rand_dir() * 2.0, randf_range(0.3, 0.5), 0.9, 2.4, KIND_FIRE, 2.0, 2.0)


## Ground dust (the hangar launch).
func dust(p: Vector3, scale := 1.0) -> void:
	for k in int(14 * scale):
		var d := Vector3(randf_range(-1, 1), randf_range(0.0, 0.4), randf_range(-1, 1)).normalized()
		puffs.spawn(p + d * 4.0, d * randf_range(14.0, 34.0) * scale, randf_range(1.2, 2.2),
			randf_range(3.0, 5.0) * scale, randf_range(7.0, 12.0) * scale, KIND_DUST, 1.6, 2.0)
