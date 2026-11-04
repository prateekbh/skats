class_name RexBoss
extends Node3D
## The Episode 2 boss model, from the show's frame: an upright green dinosaur with a banded
## pale-yellow belly, a snarling toothy mouth, an angry yellow eye under a heavy brow, small clawed
## arms, slate spikes down the back and a thick tail that curls up at the tip. Sculpted as smooth
## tubes (Sculpt) and cel-shaded with an ink outline. Nose points to -Z; the head is about 34 units
## up (scale it in game). Model only for now: it breathes and sways its tail.
##
## If models/rex.glb exists (made by tools/prepare_rex.py from a CC-BY Tyrannosaurus, see CREDITS.md)
## that mesh is used instead, recoloured in darker greens and cel-shaded with the same ink outline;
## the sculpted body below is the fallback.

const MODEL := "res://episodes/ep02_the_pastmaster_always_rings_twice/models/rex.glb"
## The imported mesh is about 5.9 units tall: scale it to the sculpted body's height.
const MODEL_SCALE := 6.0

const GREEN := Color(0.42, 0.66, 0.28)
const GREEN_DARK := Color(0.3, 0.5, 0.22)
const BELLY := Color(0.86, 0.9, 0.52)
const BAND := Color(0.66, 0.76, 0.34)
const SLATE := Color(0.24, 0.3, 0.36)
const IVORY := Color(0.96, 0.94, 0.84)
const MOUTH := Color(0.55, 0.12, 0.14)
const INK := 0.22

var _body: Node3D
var _tail_pivot: Node3D
var _jaw: Node3D
var _t := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	if ResourceLoader.exists(MODEL):
		_build_imported()
		return
	var skin := Sculpt.cel(Color(0.5, 0.6, 0.62), INK)
	# The trunk: one smooth tube from the back of the head, down the upright torso, into the tail
	# (the tail itself is a second tube on a pivot so it can sway).
	var trunk_pts := [Vector3(0, 32.0, -3.2), Vector3(0, 28.5, -2.4), Vector3(0, 24.0, -1.4), Vector3(0, 18.5, 0.2), Vector3(0, 13.0, 2.4), Vector3(0, 10.0, 5.0)]
	var trunk_r := [Vector2(3.0, 3.0), Vector2(3.8, 3.6), Vector2(6.2, 6.0), Vector2(7.6, 7.2), Vector2(6.8, 6.4), Vector2(5.2, 4.8)]
	MeshKit.part(_body, Sculpt.tube(trunk_pts, trunk_r, _paint_trunk, 48, 22, Vector3(0, 0, 1)), skin)
	_tail_pivot = Node3D.new()
	_tail_pivot.position = Vector3(0, 10.0, 5.0)
	_body.add_child(_tail_pivot)
	var tail_pts := [Vector3(0, 0.6, -1.5), Vector3(0, -3.2, 4.0), Vector3(0, -4.6, 10.0), Vector3(0, -4.0, 15.5), Vector3(0, -1.2, 19.6), Vector3(0, 2.8, 21.0)]
	var tail_r := [Vector2(5.0, 4.6), Vector2(4.2, 3.6), Vector2(3.0, 2.6), Vector2(1.9, 1.7), Vector2(1.0, 0.9), Vector2(0.0, 0.0)]
	MeshKit.part(_tail_pivot, Sculpt.tube(tail_pts, tail_r, _paint_belly_side, 40, 18, Vector3(0, 1, 0)), skin)
	_spikes(_tail_pivot, tail_pts, tail_r, Vector3(0, 1, 0), 5, 0.62, 3.4, 0.1, 0.8)
	_spikes(_body, trunk_pts, trunk_r, Vector3(0, 0, 1), 7, 2.2, 1.6, 0.12, 0.92)
	_head(skin)
	# Legs: thick thighs, shins, feet with three clawed toes.
	for sx in [-1.0, 1.0]:
		var leg := Sculpt.tube([Vector3(4.0 * sx, 15.0, 1.8), Vector3(5.4 * sx, 10.0, 0.4), Vector3(5.2 * sx, 6.2, -1.6), Vector3(4.9 * sx, 2.2, 0.6), Vector3(4.9 * sx, 0.8, -1.4)],
			[Vector2(4.4, 4.8), Vector2(4.0, 4.4), Vector2(2.6, 2.6), Vector2(1.9, 1.9), Vector2(1.8, 1.0)], _paint_plain, 30, 16, Vector3(0, 0, -1))
		MeshKit.part(_body, leg, skin)
		for k in 3:
			var x: float = (4.9 + (k - 1) * 1.15) * sx
			var toe := Sculpt.tube([Vector3(x, 0.9, -1.6), Vector3(x + (k - 1) * 0.4 * sx, 0.7, -3.6), Vector3(x + (k - 1) * 0.6 * sx, 0.6, -4.6)],
				[Vector2(0.75, 0.65), Vector2(0.6, 0.5), Vector2(0.45, 0.38)], _paint_plain, 8, 10, Vector3.UP)
			MeshKit.part(_body, toe, skin)
			_claw(_body, Vector3(x + (k - 1) * 0.6 * sx, 0.55, -4.9), Vector3(0, -0.25, -1).normalized(), 0.45, 1.2)
		# Small arms held up in front of the chest, three claws each.
		var arm := Sculpt.tube([Vector3(4.9 * sx, 22.6, -3.4), Vector3(6.2 * sx, 20.2, -5.2), Vector3(5.3 * sx, 20.8, -7.4)],
			[Vector2(1.4, 1.4), Vector2(1.1, 1.1), Vector2(0.85, 0.85)], _paint_plain, 14, 12, Vector3(0, 1, 0))
		MeshKit.part(_body, arm, skin)
		for k in 3:
			_claw(_body, Vector3((5.0 + (k - 1) * 0.45) * sx, 20.4, -7.9), Vector3(0, -0.6, -0.8).normalized(), 0.28, 1.0)


func _build_imported() -> void:
	var scene: Node3D = (load(MODEL) as PackedScene).instantiate()
	scene.scale = Vector3.ONE * MODEL_SCALE
	_body.add_child(scene)
	var skin := Sculpt.cel(Color(0.45, 0.55, 0.6), INK / MODEL_SCALE * 0.8, 0.12, 0.2)
	skin.set_shader_parameter("gloss", 80.0) # small, crisp glints (a broad gloss reads as pale blotches on skin)
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = skin
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _head(skin: Material) -> void:
	# Skull and upper snout as one tube; the lower jaw hinges open under it.
	var skull := [Vector3(0, 31.4, -2.6), Vector3(0, 33.0, -5.4), Vector3(0, 32.4, -8.8), Vector3(0, 31.0, -11.6), Vector3(0, 30.2, -12.6)]
	var skull_r := [Vector2(3.4, 3.1), Vector2(3.3, 2.8), Vector2(2.7, 2.0), Vector2(1.9, 1.4), Vector2(1.0, 0.8)]
	MeshKit.part(_body, Sculpt.tube(skull, skull_r, _paint_plain, 30, 20, Vector3.UP), skin)
	var mouth_mat := Sculpt.cel(Color(0.5, 0.4, 0.5), 0.0)
	MeshKit.part(_body, Sculpt.tube([Vector3(0, 29.8, -4.6), Vector3(0, 29.0, -8.4), Vector3(0, 28.6, -11.2)],
		[Vector2(2.6, 1.1), Vector2(2.1, 0.9), Vector2(1.2, 0.5)], func(_s, _a, _f): return MOUTH, 12, 14, Vector3.UP), mouth_mat)
	_jaw = Node3D.new()
	_jaw.position = Vector3(0, 29.6, -3.8)
	_body.add_child(_jaw)
	var jaw := [Vector3(0, -0.4, -0.6), Vector3(0, -1.6, -4.0), Vector3(0, -2.2, -7.0), Vector3(0, -2.4, -8.4)]
	var jaw_r := [Vector2(2.8, 1.5), Vector2(2.4, 1.2), Vector2(1.7, 0.9), Vector2(0.9, 0.6)]
	MeshKit.part(_jaw, Sculpt.tube(jaw, jaw_r, _paint_belly_side, 20, 16, Vector3.UP), skin)
	# Teeth: rows of ivory fangs along both jaws.
	for sx in [-1.0, 1.0]:
		for k in 7:
			var z := -5.4 - k * 0.95
			var w: float = lerpf(2.2, 1.0, float(k) / 6.0)
			_claw(_body, Vector3(w * sx * 0.92, 30.0 - k * 0.12, z), Vector3(0, -1, 0), 0.32, 1.3 - k * 0.06)
		for k in 5:
			var zl := -5.2 - k * 1.0
			var wl: float = lerpf(2.0, 1.1, float(k) / 4.0)
			_claw(_jaw, Vector3(wl * sx * 0.9, -1.2 - k * 0.15, zl + 3.8), Vector3(0, 1, 0.1).normalized(), 0.28, 1.0)
		# Eye under a heavy brow, horn behind it, nostril on the snout.
		var eye_mat := StandardMaterial3D.new()
		eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		eye_mat.albedo_color = Color(1.0, 0.9, 0.2)
		MeshKit.part(_body, MeshKit.sphere(1.0, 12), eye_mat, Vector3(2.75 * sx, 32.7, -6.6), Vector3(0, 0, 0.0), Vector3(0.35, 0.65, 1.0))
		var pupil := StandardMaterial3D.new()
		pupil.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pupil.albedo_color = Color(0.05, 0.03, 0.03)
		MeshKit.part(_body, MeshKit.sphere(1.0, 8), pupil, Vector3(2.98 * sx, 32.6, -6.9), Vector3.ZERO, Vector3(0.18, 0.5, 0.28))
		MeshKit.part(_body, Sculpt.tube([Vector3(2.4 * sx, 33.7, -4.6), Vector3(2.9 * sx, 33.7, -6.4), Vector3(2.5 * sx, 33.1, -8.0)],
			[Vector2(0.9, 0.8), Vector2(1.0, 0.85), Vector2(0.5, 0.4)], func(_s, _a, _f): return GREEN_DARK, 12, 12, Vector3.UP), skin)
		_claw(_body, Vector3(2.1 * sx, 34.4, -3.6), Vector3(0.25 * sx, 1.0, 0.7).normalized(), 0.6, 2.0, SLATE)
		MeshKit.part(_body, MeshKit.sphere(0.3, 8), pupil, Vector3(0.7 * sx, 31.6, -12.0))
	_claw(_body, Vector3(0, 32.5, -10.8), Vector3(0, 1, -0.3).normalized(), 0.45, 1.2, SLATE) # nose horn


## Slate spikes along a tube's dorsal side, `count` of them, sized `big` at the front shrinking to
## `small`, between `t0` and `t1` (0..1) along the tube.
func _spikes(parent: Node3D, pts: Array, radii: Array, up0: Vector3, count: int, big: float, small: float, t0: float, t1: float) -> void:
	var fr := Sculpt.frames(pts, radii, 60, up0)
	for k in count:
		var t := lerpf(t0, t1, float(k) / float(maxi(count - 1, 1)))
		var f: Dictionary = fr[int(t * 59.0)]
		var h := lerpf(big, small, float(k) / float(maxi(count - 1, 1))) * 1.6
		var dir: Vector3 = (f.up + f.tan * 0.55).normalized() # raked back toward the tail
		_claw(parent, f.pos + f.up * f.ry * 0.82, dir, h * 0.42, h, SLATE, 0.45)


## A cone (claw, tooth, horn or spike) from `base` pointing along `dir`. `flat` < 1 squashes it into a blade.
func _claw(parent: Node3D, base: Vector3, dir: Vector3, radius: float, length: float, col := IVORY, flat := 1.0) -> void:
	var m := Sculpt.cel(Color(0.6, 0.6, 0.66), INK * 0.5)
	var mi := MeshKit.part(parent, Sculpt.tube([Vector3.ZERO, Vector3(0, length * 0.5, 0), Vector3(0, length, 0)],
		[Vector2(radius * flat, radius), Vector2(radius * 0.6 * flat, radius * 0.6), Vector2(0, 0)], func(_s, _a, _f): return col, 6, 10, Vector3(0, 0, 1)), m)
	var up := dir.normalized()
	var side := up.cross(Vector3(0, 0, 1) if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var fwd := side.cross(up).normalized()
	mi.transform = Transform3D(Basis(side, up, fwd), base)


func _paint_trunk(s: float, ang: float, _f: Dictionary) -> Color:
	# Pale belly on the front (ventral side) of the torso, with darker bands across it.
	if sin(ang) < -0.25:
		return BAND if s > 5.0 and s < 22.0 and fmod(s, 2.2) < 0.32 else BELLY
	return GREEN


func _paint_belly_side(_s: float, ang: float, _f: Dictionary) -> Color:
	return BELLY if sin(ang) < -0.45 else GREEN


func _paint_plain(_s: float, _ang: float, _f: Dictionary) -> Color:
	return GREEN


func _process(delta: float) -> void:
	_t += delta
	_body.scale = Vector3(1.0, 1.0 + sin(_t * 1.6) * 0.01, 1.0) # breathing
	if _tail_pivot:
		_tail_pivot.rotation.y = sin(_t * 1.1) * 0.12
	if _jaw:
		_jaw.rotation.x = 0.12 + sin(_t * 2.3) * 0.05 # snarling
