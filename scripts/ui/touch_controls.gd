class_name TouchControls
extends Control
## On-screen flight controls for phones and tablets (landscape only).
##
##   Left hand   a throttle slider with the BOOST (afterburner, hold) icon on top of it, a gun icon
##               (hold to fire), a small missile icon (homing Blowtorch) and a round special-missile
##               carousel: tap the round picture to fire the selected special, swipe it sideways
##               to change which one is selected.
##   Right hand  a floating stick: drag anywhere on the right half of the screen to steer. Up/down
##               is pitch, left/right is roll, and banking turns the nose, so no separate rudder is
##               needed. The pitch setting (invert) applies as it does for the keyboard.
##
## It presses the same InputMap actions as the keyboard (Game._setup_input), so the flight and
## weapon code is untouched. Several fingers work at once. Shown only while flying on a touch
## device (Main toggles `visible`).

signal pause_requested

const DEADZONE := 0.16
const STICK_RADIUS := 150.0 # in ui units (see _ui): more thumb travel for the same turn
const STICK_CURVE := 1.9 # >1 keeps small movements gentle and saves full deflection for the edge
const SWIPE_STEP := 52.0 # ui units of sideways travel per carousel step
const TAP_SLOP := 20.0 # a touch on the carousel that moved less than this (ui units) is a tap

var main
var _touches := {} # finger index -> {kind, id, origin, pos, moved}
var _throttle_target := 0.6
var _stick := Vector2.ZERO
var _release_next: Array[String] = []
var _hint_t := 9.0
var _font: Font
var _spin := 0.0 # carousel slide animation: -1..1 card widths


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


## The round buttons: id -> {c: centre, r: radius, action, hold, col}. Positions are measured from
## the bottom-left corner so the left thumb reaches everything. "special" is the carousel.
func _buttons() -> Dictionary:
	var u := _ui()
	var h := _vs().y / u
	var sl := _slider()
	return {
		"boost": {"c": Vector2(float(sl.x), float(sl.top) - 46.0 * u), "r": 40.0 * u, "action": "boost", "hold": true, "col": Color(1.0, 0.75, 0.2)},
		"fire": {"c": Vector2(300, h - 105) * u, "r": 56.0 * u, "action": "fire_guns", "hold": true, "col": Color(1.0, 0.35, 0.25)},
		"missile": {"c": Vector2(222, h - 222) * u, "r": 56.0 * u, "action": "fire_missile", "hold": false, "col": Color(0.9, 0.9, 1.0)},
		"special": {"c": Vector2(398, h - 232) * u, "r": 62.0 * u, "action": "fire_special", "hold": false, "col": Color(0.75, 0.45, 1.0)},
		"pause": {"c": Vector2(_vs().x / u - 56, 100) * u, "r": 34.0 * u, "action": "", "hold": false, "col": Color(0.85, 0.85, 0.9)},
	}


## The throttle track: x centre, y of the top and bottom ends.
func _slider() -> Dictionary:
	var u := _ui()
	var h := _vs().y
	return {"x": 100.0 * u, "top": h - 400.0 * u, "bottom": h - 110.0 * u}


func _slider_value(y: float) -> float:
	var s := _slider()
	return clampf(inverse_lerp(s.bottom, s.top, y), 0.0, 1.0)


func _hit_button(p: Vector2) -> String:
	var b := _buttons()
	var best := ""
	var best_d := INF
	for id: String in b:
		var d := p.distance_to(b[id].c)
		if d <= float(b[id].r) * 1.25 and d < best_d:
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
		_touches[index] = {"kind": "button", "id": id, "origin": p, "pos": p, "moved": 0.0, "steps": 0}
		var def: Dictionary = _buttons()[id]
		if id == "pause":
			pause_requested.emit()
		elif id == "special":
			pass # decided on release: a tap fires, a sideways swipe changes the missile
		elif def.hold:
			Input.action_press(def.action)
		else:
			Input.action_press(def.action)
			_release_next.append(def.action)
			Input.vibrate_handheld(18)
		return
	var s := _slider()
	if absf(p.x - float(s.x)) < 60.0 * _ui() and p.y > float(s.top) - 40.0 * _ui() and p.y < float(s.bottom) + 50.0 * _ui():
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
		"button":
			if t.id == "special":
				t.moved = maxf(float(t.moved), p.distance_to(t.origin))
				# Each SWIPE_STEP of sideways travel turns the carousel one card (right = next).
				var steps := int(floor((p.x - t.origin.x) / (SWIPE_STEP * _ui())))
				if steps != int(t.steps):
					var dir := steps - int(t.steps)
					t.steps = steps
					main.player.cycle_special(dir)
					_spin = clampf(-float(dir), -1.0, 1.0)
					Input.vibrate_handheld(10)


func _release(index: int) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	if t.kind == "button":
		var def: Dictionary = _buttons()[t.id]
		if t.id == "special":
			if float(t.moved) < TAP_SLOP * _ui():
				Input.action_press("fire_special")
				_release_next.append("fire_special")
				Input.vibrate_handheld(18)
		elif def.hold:
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
	return signf(v) * pow((a - DEADZONE) / (1.0 - DEADZONE), STICK_CURVE)


func _process(delta: float) -> void:
	if not visible:
		if not _touches.is_empty():
			release_all()
		_hint_t = 9.0
		return
	_hint_t = maxf(0.0, _hint_t - delta)
	_spin = move_toward(_spin, 0.0, delta * 5.0)
	for a in _release_next:
		Input.action_release(a)
	_release_next.clear()
	_axis("roll_right", "roll_left", _shape(_stick.x))
	_axis("pitch_up", "pitch_down", _shape(-_stick.y))
	# The slider is sticky: it sets a target and the throttle follows it at the usual rate.
	var diff: float = _throttle_target - float(main.player.throttle)
	_axis("throttle_up", "throttle_down", clampf(diff * 5.0, -1.0, 1.0) if absf(diff) > 0.02 else 0.0)
	queue_redraw()


# --- drawing ------------------------------------------------------------------------

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
	var track := Rect2(float(s.x) - 10.0 * u, s.top, 20.0 * u, float(s.bottom) - float(s.top))
	draw_rect(track.grow(4.0 * u), Color(0, 0, 0, 0.35))
	draw_rect(track, Color(1, 1, 1, 0.16))
	var fill_h := track.size.y * _throttle_target
	draw_rect(Rect2(track.position.x, track.end.y - fill_h, track.size.x, fill_h), Color(0.35, 0.85, 1.0, 0.55))
	var actual_y := lerpf(float(s.bottom), float(s.top), p.throttle)
	draw_line(Vector2(track.position.x - 6.0 * u, actual_y), Vector2(track.end.x + 6.0 * u, actual_y), Color(1, 1, 1, 0.55), 2.0 * u)
	var knob := Vector2(float(s.x), lerpf(float(s.bottom), float(s.top), _throttle_target))
	draw_circle(knob, 24.0 * u, Color(0.1, 0.12, 0.2, 0.75))
	draw_arc(knob, 24.0 * u, 0, TAU, 28, Color(0.6, 0.9, 1.0, 0.95), 3.0 * u)
	_label(Vector2(float(s.x) - 50.0 * u, float(s.bottom) + 36.0 * u), "THROTTLE", int(13 * u), 100.0 * u)
	# Round buttons with icons.
	var b := _buttons()
	for id: String in b:
		if id == "special":
			continue
		var def: Dictionary = b[id]
		var down: bool = held.has(id)
		var col: Color = def.col
		draw_circle(def.c, def.r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, 0.55 if not down else 0.85))
		draw_arc(def.c, def.r, 0, TAU, 36, Color(col.r, col.g, col.b, 0.95 if down else 0.7), 3.5 * u)
		match id:
			"fire":
				_icon_guns(def.c, def.r * 0.66)
			"missile":
				_icon_missile(def.c, def.r * 0.66)
			"boost":
				_icon_flame(def.c, def.r * 0.6, col)
			"pause":
				_label(def.c + Vector2(-def.r, 8.0 * u), "II", int(24 * u), float(def.r) * 2.0)
	_label(b.missile.c + Vector2(-b.missile.r, b.missile.r + 18.0 * u), "x%d" % p.missiles, int(14 * u), float(b.missile.r) * 2.0)
	_draw_carousel(b.special, p, u, held.has("special"))
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
		var hy := 262.0 * u
		draw_rect(Rect2(w * 0.5 - 330.0 * u, hy - 30.0 * u, 660.0 * u, 96.0 * u), Color(0, 0, 0, 0.55 * a))
		_label(Vector2(w * 0.5 - 330.0 * u, hy), "LEFT THUMB: throttle, guns, missiles", int(20 * u), 660.0 * u, a)
		_label(Vector2(w * 0.5 - 330.0 * u, hy + 28.0 * u), "tap the round picture to fire it, swipe it to change", int(18 * u), 660.0 * u, a)
		_label(Vector2(w * 0.5 - 330.0 * u, hy + 56.0 * u), "RIGHT THUMB: drag anywhere to steer", int(20 * u), 660.0 * u, a)


## The round special-missile carousel: the selected missile's picture in a medallion with its
## ammo in a badge. Tap fires, a sideways swipe changes it (the picture slides as it turns).
func _draw_carousel(def: Dictionary, p: TurboKat, u: float, down: bool) -> void:
	var idx: int = p.special_index
	var c: Vector2 = def.c
	var r: float = def.r
	var sel: Dictionary = Arsenal.SPECIALS[idx]
	var col: Color = def.col
	var ammo := int(p.special_ammo.get(sel.id, 0))
	_medallion(c + Vector2(_spin * r * 0.5, 0), r * (0.96 if down else 1.0), sel, 1.0 if ammo > 0 else 0.5, p)
	draw_arc(c, r + 3.0 * u, 0, TAU, 40, Color(col.r, col.g, col.b, 0.95 if down else 0.8), 4.0 * u)
	# The ammo badge.
	var bc := c + Vector2(r * 0.72, r * 0.72)
	draw_circle(bc, 17.0 * u, Color(0.08, 0.08, 0.14, 0.92))
	draw_arc(bc, 17.0 * u, 0, TAU, 20, Color(col.r, col.g, col.b, 1.0), 2.5 * u)
	_label(bc + Vector2(-17.0 * u, 7.0 * u), str(ammo), int(20 * u), 34.0 * u)
	if p.locked_specials.has(sel.id):
		_label(c + Vector2(-r, 6.0 * u), "OFFLINE", int(15 * u), r * 2.0)


## A round, picture-filled disc: the missile's card art (square centre crop) on a circle polygon.
func _medallion(c: Vector2, r: float, def: Dictionary, alpha: float, p: TurboKat) -> void:
	var tex: Texture2D = main.hud._rack_art.get(def.id)
	var dim := Color(1, 1, 1, alpha) if not p.locked_specials.has(def.id) else Color(0.4, 0.4, 0.45, alpha)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var seg := 40
	for k in seg:
		var a := TAU * k / seg
		pts.append(c + Vector2(cos(a), sin(a)) * r)
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5)) # placeholder, remapped below for non-square art
		cols.append(dim)
	if tex:
		var ts := tex.get_size()
		var side := minf(ts.x, ts.y)
		var rx := side / ts.x * 0.5
		var ry := side / ts.y * 0.5
		for k in seg:
			var a := TAU * k / seg
			uvs[k] = Vector2(0.5 + cos(a) * rx, 0.5 + sin(a) * ry)
		draw_polygon(pts, cols, uvs, tex)
	else:
		draw_colored_polygon(pts, Color(def.color.r, def.color.g, def.color.b, alpha))
	draw_arc(c, r, 0, TAU, 32, Color(0, 0, 0, 0.8 * alpha), 3.0)


# --- icons (drawn with primitives, so no art files are needed) ----------------------

## A rotary machine gun on a tripod (white silhouette, as in the weapon-icon sets).
func _icon_guns(c: Vector2, s: float) -> void:
	var o := c + Vector2(-0.05, -0.32) * s
	var white := Color(1, 1, 1, 0.96)
	var dark := Color(0.06, 0.06, 0.1, 0.95)
	draw_rect(Rect2(o + Vector2(0.1, -0.55) * s, Vector2(0.95, 0.5) * s), white) # barrel cluster
	for gx in [0.38, 0.64, 0.9]:
		draw_rect(Rect2(o + Vector2(gx, -0.55) * s, Vector2(0.05, 0.5) * s), dark) # barrel rings
	draw_rect(Rect2(o + Vector2(-0.35, -0.65) * s, Vector2(0.55, 0.7) * s), white) # receiver
	draw_rect(Rect2(o + Vector2(-0.95, -0.5) * s, Vector2(0.65, 0.42) * s), white) # feed / hand guard
	draw_rect(Rect2(o + Vector2(-0.7, -0.02) * s, Vector2(0.5, 0.5) * s), white) # grip
	draw_rect(Rect2(o + Vector2(-0.03, 0.05) * s, Vector2(0.1, 0.55) * s), white) # post
	draw_rect(Rect2(o + Vector2(-0.22, 0.6) * s, Vector2(0.48, 0.15) * s), white) # swivel
	for leg in [-0.5, 0.0, 0.5]:
		draw_line(o + Vector2(0.02, 0.75) * s, o + Vector2(0.02 + leg, 1.35) * s, white, maxf(2.0, 0.1 * s)) # tripod


## A rocket flying up and to the right, with speed streaks behind it.
func _icon_missile(c: Vector2, s: float) -> void:
	var white := Color(1, 1, 1, 0.96)
	var dark := Color(0.06, 0.06, 0.1, 0.95)
	draw_set_transform(c + Vector2(0.15, -0.1) * s, PI / 4.0, Vector2.ONE)
	draw_rect(Rect2(Vector2(-0.22, -0.55) * s, Vector2(0.44, 1.2) * s), white) # body
	var nose := PackedVector2Array() # ogive nose cone, a small gap above the body
	for k in 11:
		var t := float(k) / 10.0
		nose.append(Vector2(0.22 * s * sqrt(1.0 - t * t), (-0.64 - t * 0.55) * s))
	for k in range(10, -1, -1):
		var t := float(k) / 10.0
		nose.append(Vector2(-0.22 * s * sqrt(1.0 - t * t), (-0.64 - t * 0.55) * s))
	draw_colored_polygon(nose, white)
	draw_line(Vector2(0.05, -0.35) * s, Vector2(0.05, 0.5) * s, dark, maxf(2.0, 0.07 * s)) # panel line
	for sx in [-1.0, 1.0]: # fins
		draw_colored_polygon(PackedVector2Array([Vector2(0.22 * sx, 0.0) * s, Vector2(0.62 * sx, 0.72) * s, Vector2(0.22 * sx, 0.62) * s]), white)
	for k in 3: # speed streaks
		var x := (-0.22 + 0.22 * k) * s
		draw_line(Vector2(x, 0.82 * s), Vector2(x, (1.05 + 0.1 * (k % 2)) * s), white, maxf(2.0, 0.09 * s))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## An afterburner flame (teardrop with a bright core).
func _icon_flame(c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		var r := s * (0.55 + 0.45 * (1.0 - cos(a)) * 0.5)
		pts.append(c + Vector2(sin(a) * s * 0.62 * (1.0 if cos(a) < 0.0 else 0.9), -cos(a) * s * 1.05) * (r / s))
	draw_colored_polygon(pts, Color(1.0, 0.55, 0.12, 0.96))
	var core := PackedVector2Array()
	for k in 24:
		var a := TAU * k / 24.0
		core.append(c + Vector2(sin(a) * s * 0.3, -cos(a) * s * 0.55 + s * 0.2))
	draw_colored_polygon(core, Color(1.0, 0.92, 0.5, 0.98))
	draw_arc(c, s * 1.12, PI * 1.15, PI * 1.85, 10, Color(1, 1, 1, 0.5), 2.0) # a glint


func _label(pos: Vector2, text: String, font_size: int, width: float, alpha := 1.0) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, 4, Color(0, 0, 0, 0.7 * alpha))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color(1, 1, 1, alpha))
