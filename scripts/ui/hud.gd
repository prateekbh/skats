extends Control
## In-flight HUD. Instruments are drawn every frame with _draw(); text panels are Labels.

const GREEN := Color(0.62, 1.0, 0.72)
const GREEN_DIM := Color(0.62, 1.0, 0.72, 0.35)
const RED := Color(1.0, 0.27, 0.3)
const AMBER := Color(1.0, 0.78, 0.25)
const GREY := Color(0.7, 0.72, 0.78, 0.7)
const RADAR_RANGE := 1600.0

var main: Node
var font: Font

var _objective: Label
var _score: Label
var _center: Label
var _radio_box: PanelContainer
var _radio_who: Label
var _radio_text: Label
var _radio_queue: Array = []
var _radio_t := 0.0
var _center_t := 0.0
var _damage := 0.0


func _ready() -> void:
	add_to_group("hud")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font

	_objective = _label(20, GREEN, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_objective, Control.PRESET_CENTER_TOP, -400, 14, 400, 44)

	_score = _label(22, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(_score, Control.PRESET_TOP_RIGHT, -320, 14, -20, 44)

	_center = _label(44, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_place(_center, Control.PRESET_CENTER, -500, -180, 500, -120)
	_center.add_theme_color_override("font_outline_color", Color.BLACK)
	_center.add_theme_constant_override("outline_size", 8)

	_radio_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.72)
	sb.border_color = GREEN_DIM
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_content_margin_all(10)
	_radio_box.add_theme_stylebox_override("panel", sb)
	_radio_box.position = Vector2(20, 56)
	_radio_box.custom_minimum_size = Vector2(430, 0)
	add_child(_radio_box)
	var vb := VBoxContainer.new()
	_radio_box.add_child(vb)
	_radio_who = _label(15, AMBER, HORIZONTAL_ALIGNMENT_LEFT, vb)
	_radio_text = _label(18, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, vb)
	_radio_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_radio_text.custom_minimum_size = Vector2(410, 0)
	_radio_box.visible = false


## Anchors a control to a preset, then sets its offsets from those anchors.
func _place(c: Control, preset: Control.LayoutPreset, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


func _label(size: int, color: Color, align: HorizontalAlignment, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(l)
	return l


func reset() -> void:
	_radio_queue.clear()
	_radio_t = 0.0
	_radio_box.visible = false
	_center.text = ""
	_damage = 0.0


func radio(who: String, text: String, seconds: float) -> void:
	_radio_queue.append([who, text, seconds])


func message(text: String, seconds := 2.5) -> void:
	_center.text = text
	_center_t = seconds
	_center.modulate.a = 1.0


func flash_damage() -> void:
	_damage = 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_radio_t -= delta
	if _radio_t <= 0.0:
		if _radio_queue.is_empty():
			_radio_box.visible = false
		else:
			var r = _radio_queue.pop_front()
			_radio_who.text = "◢ " + str(r[0]).to_upper()
			_radio_text.text = r[1]
			_radio_t = r[2]
			_radio_box.visible = true
			Sfx.play("beep", -18.0, 0.6)
	_center_t -= delta
	_center.modulate.a = clampf(_center_t * 2.0, 0.0, 1.0)
	_damage = maxf(0.0, _damage - delta * 2.0)
	if main and main.mission:
		_objective.text = main.mission.objective()
		_score.text = "SCORE %06d" % main.combat.stats.score
	queue_redraw()


func _draw() -> void:
	if main == null or main.player == null:
		return
	var p: TurboKat = main.player
	var cam: Camera3D = main.camera
	var vs := size
	var ui := clampf(vs.x / 1280.0, 0.65, 1.4)

	if _damage > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0, 0, _damage * 0.22))
	if p.alive and p.hp < 30.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		_draw_vignette(vs, Color(1, 0, 0, 0.18 * pulse))
	if not p.alive:
		return

	var fwd := p.forward()
	_draw_targets(p, cam, vs, ui)

	# Gun reticle, projected where the cannons converge.
	var aim := p.global_position + fwd * 500.0
	if not cam.is_position_behind(aim):
		var s := cam.unproject_position(aim)
		var col := RED if p.overheated else GREEN
		draw_arc(s, 18 * ui, 0, TAU, 32, col, 2.0)
		draw_circle(s, 2.0 * ui, col)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(s + d * 24 * ui, s + d * 34 * ui, col, 2.0)

	# Speed (left) and altitude (right) readouts beside screen centre.
	var c := vs * 0.5
	var kts := int(p.speed * 1.94)
	var ft := int(p.global_position.y * 3.28)
	_text(Vector2(c.x - 300 * ui, c.y), "%d KTS" % kts, 20, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 150 * ui)
	_text(Vector2(c.x - 300 * ui, c.y + 22 * ui), "THR %d%%" % int(p.throttle * 100), 14, GREEN_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 150 * ui)
	_text(Vector2(c.x + 150 * ui, c.y), "%d FT" % ft, 20, GREEN, HORIZONTAL_ALIGNMENT_LEFT, 150 * ui)
	_text(Vector2(c.x + 150 * ui, c.y + 22 * ui), "G %.1f" % (1.0 + absf(p._in.pitch) * p.speed / 60.0), 14, GREEN_DIM, HORIZONTAL_ALIGNMENT_LEFT, 150 * ui)
	_draw_horizon(p, c, ui)

	# Warnings.
	var blink := int(Time.get_ticks_msec() / 250) % 2 == 0
	var wy := c.y + 90 * ui
	if p.warn_pull_up and blink:
		_text(Vector2(c.x - 200, wy), "PULL UP", 30, RED, HORIZONTAL_ALIGNMENT_CENTER, 400)
		wy += 34
	if p.overheated:
		_text(Vector2(c.x - 200, wy), "GUNS OVERHEATED", 20, RED, HORIZONTAL_ALIGNMENT_CENTER, 400)
		wy += 26
	if p.warn_boundary and blink:
		_text(Vector2(c.x - 250, wy), "RETURN TO MEGAKAT CITY", 22, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 500)

	_draw_radar(p, Vector2(110 * ui + 10, vs.y - 110 * ui - 10), 95 * ui)
	_draw_status(p, Vector2(vs.x - 300 * ui - 20, vs.y - 150 * ui - 10), ui)


func _text(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string_outline(font, pos, s, align, width, size, 4, Color(0, 0, 0, 0.6))
	draw_string(font, pos, s, align, width, size, col)


func _draw_vignette(vs: Vector2, col: Color) -> void:
	var t := 60.0
	draw_rect(Rect2(0, 0, vs.x, t), col)
	draw_rect(Rect2(0, vs.y - t, vs.x, t), col)
	draw_rect(Rect2(0, t, t, vs.y - 2 * t), col)
	draw_rect(Rect2(vs.x - t, t, t, vs.y - 2 * t), col)


## Artificial horizon: a short bank line through the centre plus a pitch number.
func _draw_horizon(p: TurboKat, c: Vector2, ui: float) -> void:
	var b := p.global_transform.basis
	var bank := atan2(b.x.y, b.y.y)
	var pitch_deg := rad_to_deg(asin(clampf(p.forward().y, -1.0, 1.0)))
	# Rolling right tips the horizon's right end up (screen y grows downward).
	var dir := Vector2(cos(bank), sin(bank))
	var r := 110.0 * ui
	draw_line(c - dir * r, c - dir * (r * 0.55), GREEN_DIM, 2.0)
	draw_line(c + dir * (r * 0.55), c + dir * r, GREEN_DIM, 2.0)
	_text(c + Vector2(-30, 64 * ui), "%+d°" % int(pitch_deg), 14, GREEN_DIM, HORIZONTAL_ALIGNMENT_CENTER, 60)


func _draw_targets(p: TurboKat, cam: Camera3D, vs: Vector2, ui: float) -> void:
	var nearest_off: Target = null
	var nearest_d := INF
	var any_on := false
	for t: Target in main.combat.targets:
		if not is_instance_valid(t) or not t.alive or not t.is_visible_in_tree():
			continue
		var d := p.global_position.distance_to(t.global_position)
		var on := not cam.is_position_behind(t.global_position)
		var s := Vector2.ZERO
		if on:
			s = cam.unproject_position(t.global_position)
			on = Rect2(Vector2.ZERO, vs).has_point(s)
		if not on:
			if (t.is_objective or d < nearest_d) and d < 3000.0:
				if t.is_objective:
					_draw_offscreen(p, cam, vs, t, AMBER)
				elif d < nearest_d:
					nearest_d = d
					nearest_off = t
			continue
		if d > 2500.0:
			continue
		any_on = true
		var col := GREY if t.invulnerable else RED
		var half := clampf(t.radius / maxf(d, 1.0) * 900.0, 9.0, 70.0) * ui
		_brackets(s, half, col)
		if t == p.lock_target:
			var k := clampf(p.lock_time / TurboKat.LOCK_TIME, 0.0, 1.0)
			var lr := lerpf(half * 3.0, half + 6.0, k)
			var lc := RED if p.locked else AMBER
			var pts := PackedVector2Array([s + Vector2(0, -lr), s + Vector2(lr, 0), s + Vector2(0, lr), s + Vector2(-lr, 0), s + Vector2(0, -lr)])
			draw_polyline(pts, lc, 2.5 if p.locked else 1.5)
			if p.locked:
				_text(s + Vector2(-40, -half - 12), "LOCK", 16, RED, HORIZONTAL_ALIGNMENT_CENTER, 80)
		if t.is_objective or t == p.lock_target:
			_text(s + Vector2(-80, half + 18), "%s  %dm" % [t.display_name.to_upper(), int(d)], 13, col, HORIZONTAL_ALIGNMENT_CENTER, 160)
			if t.max_hp >= 200.0 and not t.invulnerable:
				var w := 60.0 * ui
				draw_rect(Rect2(s + Vector2(-w * 0.5, half + 24), Vector2(w, 4)), Color(0, 0, 0, 0.5))
				draw_rect(Rect2(s + Vector2(-w * 0.5, half + 24), Vector2(w * t.hp / t.max_hp, 4)), col)
	if not any_on and nearest_off:
		_draw_offscreen(p, cam, vs, nearest_off, RED)


func _brackets(s: Vector2, h: float, col: Color) -> void:
	var l := h * 0.45
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := s + Vector2(h * sx, h * sy)
			draw_line(corner, corner - Vector2(l * sx, 0), col, 2.0)
			draw_line(corner, corner - Vector2(0, l * sy), col, 2.0)


## Arrow on an ellipse around screen centre pointing toward an off-screen target.
func _draw_offscreen(p: TurboKat, cam: Camera3D, vs: Vector2, t: Target, col: Color) -> void:
	var local := cam.global_transform.basis.inverse() * (t.global_position - cam.global_position)
	var dir := Vector2(local.x, -local.y)
	if dir.length() < 0.001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var c := vs * 0.5
	var pos := c + Vector2(dir.x * vs.x * 0.38, dir.y * vs.y * 0.36)
	var perp := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([pos + dir * 16, pos - dir * 8 + perp * 11, pos - dir * 8 - perp * 11]), col)
	var d := p.global_position.distance_to(t.global_position)
	_text(pos - dir * 30 + Vector2(-40, 5), "%dm" % int(d), 12, col, HORIZONTAL_ALIGNMENT_CENTER, 80)


func _draw_radar(p: TurboKat, c: Vector2, r: float) -> void:
	draw_circle(c, r, Color(0.02, 0.06, 0.05, 0.6))
	draw_arc(c, r, 0, TAU, 48, GREEN_DIM, 1.5)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(GREEN_DIM, 0.15), 1.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(GREEN_DIM, 0.15))
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(GREEN_DIM, 0.15))
	var fwd := p.forward()
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	var right2 := Vector2(-f2.y, f2.x)
	var scale := r / RADAR_RANGE
	# City limits and City Hall for orientation.
	var hall: Vector3 = main.city.city_hall_pos
	var hd := Vector2(hall.x - p.global_position.x, hall.z - p.global_position.z)
	var hs := Vector2(hd.dot(right2), -hd.dot(f2)) * scale
	if hs.length() < r:
		draw_rect(Rect2(c + hs - Vector2(3, 3), Vector2(6, 6)), Color(0.5, 0.7, 1.0, 0.8))
	for t: Target in main.combat.targets:
		if not is_instance_valid(t) or not t.alive or not t.is_visible_in_tree():
			continue
		var d := Vector2(t.global_position.x - p.global_position.x, t.global_position.z - p.global_position.z)
		var s := Vector2(d.dot(right2), -d.dot(f2)) * scale
		if s.length() > r - 3:
			s = s.normalized() * (r - 3)
		var big := t.radius > 20.0
		var dy := t.global_position.y - p.global_position.y
		var col := AMBER if t.is_objective else RED
		draw_circle(c + s, 5.0 if big else 2.5, col)
		if absf(dy) > 120.0:
			draw_line(c + s, c + s + Vector2(0, -6 if dy > 0 else 6), col, 1.5)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 5), c + Vector2(-5, 5)]), GREEN)
	_text(c + Vector2(-r, r + 18), "RADAR %.1f KM" % (RADAR_RANGE / 1000.0), 12, GREEN_DIM, HORIZONTAL_ALIGNMENT_CENTER, r * 2)


func _draw_status(p: TurboKat, o: Vector2, ui: float) -> void:
	var w := 300.0 * ui
	draw_rect(Rect2(o - Vector2(12, 26), Vector2(w + 24, 172 * ui)), Color(0.02, 0.05, 0.06, 0.55))
	_bar(o, w, "HULL", p.hp / p.max_hp, RED if p.hp < 30.0 else GREEN, ui)
	_bar(o + Vector2(0, 34 * ui), w, "AFTERBURNER", p.boost / 100.0, Color(0.5, 0.8, 1.0), ui)
	_bar(o + Vector2(0, 68 * ui), w, "GUN HEAT", p.heat / 100.0, RED if p.overheated else AMBER, ui)
	var y := o.y + 110 * ui
	_text(Vector2(o.x, y), "MISSILES  %02d" % p.missiles, 18, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(o.x + w * 0.55, y), "MEGA  %d" % p.mega, 18, AMBER, HORIZONTAL_ALIGNMENT_LEFT)
	var lock_txt := "LOCKED" if p.locked else ("LOCKING" if p.lock_target else "NO LOCK")
	_text(Vector2(o.x, y + 24 * ui), lock_txt, 13, RED if p.locked else GREEN_DIM, HORIZONTAL_ALIGNMENT_LEFT)


func _bar(o: Vector2, w: float, label: String, v: float, col: Color, ui: float) -> void:
	_text(o + Vector2(0, -6), label, 12, GREEN_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(Rect2(o + Vector2(0, 0), Vector2(w, 10 * ui)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(o + Vector2(0, 0), Vector2(w * clampf(v, 0.0, 1.0), 10 * ui)), col)
