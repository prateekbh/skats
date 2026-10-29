class_name ChaseCamera
extends Camera3D
## Follows the TurboKat. Modes: chase, far chase, cockpit, plus scripted orbit / intro shots.

enum Mode { CHASE, FAR, COCKPIT }

var target: TurboKat
var mode := Mode.CHASE
## "orbit" for the title screen, "intro" for launch cinematics, "" for normal play.
var shot := ""
var shot_time := 0.0

var _offset := Vector3(0, 6, 24)
var _up := Vector3.UP
var _shake := 0.0


func _ready() -> void:
	near = 0.5
	far = 12000.0
	fov = 68.0


func cycle_mode() -> void:
	mode = ((mode + 1) % 3) as Mode


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 3.0)


func _process(delta: float) -> void:
	if target == null:
		return
	shot_time += delta
	var tb := target.global_transform.basis
	var fwd := -tb.z
	var up := tb.y
	var pos := target.global_position
	target.visible = target.alive and not (mode == Mode.COCKPIT and shot == "")

	if shot == "orbit":
		# Slow hero orbit for the title screen: close enough to show off the TurboKat.
		# The look point is offset so the jet sits right of centre, clear of the menu panel.
		var a := shot_time * 0.15
		global_position = pos + Vector3(cos(a) * 36.0, 8.0 + sin(shot_time * 0.3) * 4.0, sin(a) * 36.0)
		var to_jet := (pos - global_position).normalized()
		var cam_left := Vector3.UP.cross(to_jet).normalized()
		_look(pos + cam_left * 13.0, Vector3.UP)
	elif shot == "script":
		pass # positioned by whoever is running a cutscene
	elif shot.begins_with("view:"):
		# Fixed local-space camera, used for showcase screenshots: "view:x,y,z".
		var v := shot.trim_prefix("view:").split_floats(",")
		global_position = target.global_transform * Vector3(v[0], v[1], v[2])
		_look(pos, up)
	elif shot == "intro":
		# Swing from a low side angle into the chase position over ~3 seconds.
		var k := smoothstep(0.0, 3.2, shot_time)
		var side := tb.x * 38.0 + up * 4.0 + fwd * 30.0
		var chase := -fwd * 24.0 + up * 6.0
		_offset = side.lerp(chase, k)
		_up = up
		global_position = pos + _offset
		_look(pos + fwd * 20.0 * k, Vector3.UP.lerp(up, k))
	elif mode == Mode.COCKPIT:
		global_position = target.global_transform * Vector3(0, 1.55, -5.4)
		_look(global_position + fwd * 200.0, up)
	else:
		var back := 24.0 if mode == Mode.CHASE else 50.0
		var height := 6.0 if mode == Mode.CHASE else 14.0
		back += maxf(0.0, target.speed - 130.0) * 0.035
		var desired := -fwd * back + up * height
		_offset = _offset.lerp(desired, 1.0 - exp(-delta * 6.0))
		_up = _up.lerp(up, 1.0 - exp(-delta * 3.5)).normalized()
		global_position = pos + _offset
		_look(pos + fwd * 30.0, _up)

	if _shake > 0.0:
		global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = maxf(0.0, _shake - delta * 3.0)
	var want_fov := 68.0 + clampf((target.speed - 120.0) * 0.07, -4.0, 16.0)
	fov = lerpf(fov, want_fov, 1.0 - exp(-delta * 3.0))


func _look(at: Vector3, up: Vector3) -> void:
	var dir := at - global_position
	if dir.length_squared() < 0.0001:
		return
	if absf(dir.normalized().dot(up.normalized())) > 0.995:
		up = Vector3.FORWARD
	look_at(at, up)
