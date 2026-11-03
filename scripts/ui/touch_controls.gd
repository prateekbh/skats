class_name TouchControls
extends Control
## On-screen flight controls for phones and tablets (landscape only).
##
##   Left hand   a throttle slider, FIRE (guns, hold), BOOST (afterburner, hold), BLOWTORCH (homing
##               missile), SPECIAL (fire the selected special missile) and NEXT (cycle specials)
##   Right hand  a floating stick: drag anywhere on the right half of the screen to steer. Up/down
##               is pitch, left/right is roll, and banking turns the nose, so no separate rudder is
##               needed. The pitch setting (invert) applies as it does for the keyboard.
##
## It presses the same InputMap actions as the keyboard (Game._setup_input), so the flight and
## weapon code is untouched. Several fingers work at once. Shown only while flying on a touch
## device (Main toggles `visible`).

signal pause_requested

const DEADZONE := 0.1
const STICK_RADIUS := 105.0 # in ui units (see _ui)

var main
var _touches := {} # finger index -> {kind: "button"|"slider"|"stick", id: String, origin: Vector2, pos: Vector2}
var _throttle_target := 0.6
var _stick := Vector2.ZERO
var _release_next: Array[String] = []
var _hint_t := 9.0
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keep releasing held actions while the game is paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


## The screen in pixels (the viewport, so it is right even before the layout has run).
func _vs() -> Vector2:
	var v := get_viewport_rect().size
	if DisplayServer.get_name() == "headless": # headless runs have no real window: use the project's design size
		return Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")), float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	return v


func _ui() -> float:
	return clampf(_vs().y / 720.0, 0.6, 1.6)


## The buttons: id -> {c: centre, r: radius, label, action, hold}. Positions are measured from the
## bottom-left corner so the left thumb reaches everything.
func _buttons() -> Dictionary:
	var u := _ui()
	var h := _vs().y
	return {
		"fire": {"c": Vector2(330, h / u - 120) * u, "r": 74.0 * u, "label": "FIRE", "action": "fire_guns", "hold": true, "col": Color(1.0, 0.35, 0.25)},
		"boost": {"c": Vector2(490, h / u - 92) * u, "r": 52.0 * u, "label": "BOOST", "action": "boost", "hold": true, "col": Color(1.0, 0.75, 0.2)},
		"missile": {"c": Vector2(270, h / u - 290) * u, "r": 52.0 * u, "label": "MISSILE", "action": "fire_missile", "hold": false, "col": Color(0.9, 0.9, 1.0)},
		"special": {"c": Vector2(430, h / u - 262) * u, "r": 54.0 * u, "label": "SPECIAL", "action": "fire_special", "hold": false, "col": Color(0.75, 0.45, 1.0)},
		"next": {"c": Vector2(365, h / u - 400) * u, "r": 34.0 * u, "label": "NEXT", "action": "cycle_special", "hold": false, "col": Color(0.55, 0.8, 1.0)},
		"pause": {"c": Vector2(_vs().x / u - 56, 100) * u, "r": 34.0 * u, "label": "II", "action": "", "hold": false, "col": Color(0.85, 0.85, 0.9)},
	}


## The throttle track: x centre, y of the top and bottom ends.
func _slider() -> Dictionary:
	var u := _ui()
	var h := _vs().y
	return {"x": 140.0 * u, "top": h - 480.0 * u, "bottom": h - 150.0 * u}


func _slider_value(y: float) -> float:
	var s := _slider()
	return clampf(inverse_lerp(s.bottom, s.top, y), 0.0, 1.0)


func _hit_button(p: Vector2) -> String:
	var b := _buttons()
	var best := ""
	var best_d := INF
	for id: String in b:
		var d := p.distance_to(b[id].c)
		if d <= float(b[id].r) * 1.3 and d < best_d:
			best = id
			best_d = d
	return best


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.index, event.position)
		else:
			_release(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
		get_viewport().set_input_as_handled()


func _press(index: int, p: Vector2) -> void:
	var id := _hit_button(p)
	if id != "":
		_touches[index] = {"kind": "button", "id": id, "origin": p, "pos": p}
		var def: Dictionary = _buttons()[id]
		if id == "pause":
			pause_requested.emit()
		elif def.hold:
			Input.action_press(def.action)
		else:
			Input.action_press(def.action)
			_release_next.append(def.action)
			Input.vibrate_handheld(18)
		return
	var s := _slider()
	if absf(p.x - float(s.x)) < 70.0 * _ui() and p.y > float(s.top) - 50.0 * _ui() and p.y < float(s.bottom) + 50.0 * _ui():
		_touches[index] = {"kind": "slider", "id": "throttle", "origin": p, "pos": p}
		_throttle_target = _slider_value(p.y)
		return
	if p.x > _vs().x * 0.45:
		_touches[index] = {"kind": "stick", "id": "stick", "origin": p, "pos": p}
		_stick = Vector2.ZERO


func _drag(index: int, p: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	t.pos = p
	match t.kind:
		"slider":
			_throttle_target = _slider_value(p.y)
		"stick":
			var v: Vector2 = (p - t.origin) / (STICK_RADIUS * _ui())
			if v.length() > 1.0:
				v = v.normalized()
				t.origin = p - v * STICK_RADIUS * _ui() # the base follows a thumb dragged past the edge
			_stick = v


func _release(index: int) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t.kind == "button":
		var def: Dictionary = _buttons()[t.id]
		if def.hold:
			Input.action_release(def.action)
	elif t.kind == "stick":
		_stick = Vector2.ZERO
	_touches.erase(index)


## Lets go of everything (when the controls are hidden or the game pauses).
func release_all() -> void:
	for index in _touches.keys():
		_release(index)
	_stick = Vector2.ZERO
	for a in ["pitch_up", "pitch_down", "roll_left", "roll_right", "throttle_up", "throttle_down"]:
		Input.action_release(a)


func _axis(positive: String, negative: String, v: float) -> void:
	if v > 0.0:
		Input.action_press(positive, v)
		Input.action_release(negative)
	elif v < 0.0:
		Input.action_press(negative, -v)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


func _shape(v: float) -> float:
	var a := absf(v)
	if a < DEADZONE:
		return 0.0
	return signf(v) * pow((a - DEADZONE) / (1.0 - DEADZONE), 1.25)


func _process(delta: float) -> void:
	if not visible:
		if not _touches.is_empty():
			release_all()
		_hint_t = 9.0
		return
	_hint_t = maxf(0.0, _hint_t - delta)
	for a in _release_next:
		Input.action_release(a)
	_release_next.clear()
	_axis("roll_right", "roll_left", _shape(_stick.x))
	_axis("pitch_up", "pitch_down", _shape(-_stick.y))
	# The slider is sticky: it sets a target and the throttle follows it at the usual rate.
	var diff: float = _throttle_target - float(main.player.throttle)
	_axis("throttle_up", "throttle_down", clampf(diff * 5.0, -1.0, 1.0) if absf(diff) > 0.02 else 0.0)
	queue_redraw()


func _draw() -> void:
	if not visible or main == null or main.player == null:
		return
	var u := _ui()
	var p: TurboKat = main.player
	var held := {}
	for t in _touches.values():
		if t.kind == "button":
			held[t.id] = true
	# Throttle slider.
	var s := _slider()
	var track := Rect2(float(s.x) - 11.0 * u, s.top, 22.0 * u, float(s.bottom) - float(s.top))
	draw_rect(track.grow(4.0 * u), Color(0, 0, 0, 0.35))
	draw_rect(track, Color(1, 1, 1, 0.16))
	var fill_h := track.size.y * _throttle_target
	draw_rect(Rect2(track.position.x, track.end.y - fill_h, track.size.x, fill_h), Color(0.35, 0.85, 1.0, 0.55))
	var actual_y := lerpf(float(s.bottom), float(s.top), p.throttle)
	draw_line(Vector2(track.position.x - 6.0 * u, actual_y), Vector2(track.end.x + 6.0 * u, actual_y), Color(1, 1, 1, 0.55), 2.0 * u)
	var knob := Vector2(float(s.x), lerpf(float(s.bottom), float(s.top), _throttle_target))
	draw_circle(knob, 26.0 * u, Color(0.1, 0.12, 0.2, 0.75))
	draw_arc(knob, 26.0 * u, 0, TAU, 28, Color(0.6, 0.9, 1.0, 0.95), 3.0 * u)
	_label(Vector2(float(s.x) - 50.0 * u, float(s.bottom) + 40.0 * u), "THROTTLE", int(15 * u), 100.0 * u)
	# Buttons.
	var b := _buttons()
	for id: String in b:
		var def: Dictionary = b[id]
		var down: bool = held.has(id)
		var col: Color = def.col
		draw_circle(def.c, def.r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.55 if not down else 0.85))
		draw_arc(def.c, def.r, 0, TAU, 36, Color(col.r, col.g, col.b, 0.95 if down else 0.7), 3.5 * u)
		_label(def.c + Vector2(-def.r, 6.0 * u), def.label, int((22 if id != "pause" else 24) * u), float(def.r) * 2.0)
	# Ammo under the missile buttons.
	var sp: Dictionary = p.selected_special()
	_label(b.missile.c + Vector2(-b.missile.r, 30.0 * u), "x%d" % p.missiles, int(17 * u), float(b.missile.r) * 2.0)
	_label(b.special.c + Vector2(-b.special.r, 30.0 * u), "%s x%d" % [str(sp.name).replace(" Missile", "").to_upper(), int(p.special_ammo.get(sp.id, 0))], int(14 * u), float(b.special.r) * 2.0)
	# The floating stick.
	for t in _touches.values():
		if t.kind == "stick":
			var r := STICK_RADIUS * u
			draw_circle(t.origin, r, Color(0, 0, 0, 0.28))
			draw_arc(t.origin, r, 0, TAU, 40, Color(1, 1, 1, 0.5), 3.0 * u)
			draw_circle(t.origin + _stick * r, 40.0 * u, Color(1, 1, 1, 0.45))
	# First seconds: how to play.
	if _hint_t > 0.0:
		var a := clampf(_hint_t, 0.0, 1.0)
		var w := _vs().x
		var size_y := _vs().y
		var hy := 262.0 * u
		draw_rect(Rect2(w * 0.5 - 330.0 * u, hy - 30.0 * u, 660.0 * u, 70.0 * u), Color(0, 0, 0, 0.55 * a))
		_label(Vector2(w * 0.5 - 330.0 * u, hy), "LEFT THUMB: throttle, guns, missiles", int(20 * u), 660.0 * u, a)
		_label(Vector2(w * 0.5 - 330.0 * u, hy + 28.0 * u), "RIGHT THUMB: drag anywhere to steer", int(20 * u), 660.0 * u, a)


func _label(pos: Vector2, text: String, font_size: int, width: float, alpha := 1.0) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 4, Color(0, 0, 0, 0.7 * alpha))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color(1, 1, 1, alpha))
