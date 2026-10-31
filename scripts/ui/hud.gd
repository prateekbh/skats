extends Control
## In-flight HUD. Instruments are drawn every frame with _draw(); text panels are Labels.

const GREEN := Color(0.62, 1.0, 0.72)
const GREEN_DIM := Color(0.62, 1.0, 0.72, 0.35)
const RED := Color(1.0, 0.27, 0.3)
const AMBER := Color(1.0, 0.78, 0.25)
const GREY := Color(0.7, 0.72, 0.78, 0.7)
const RADAR_RANGE := 2400.0

var main: Node
var font: Font

var _objective: Label
var _score: Label
var _center: Label
var _radio_card: RadioCard
var _radio_queue: Array = []
var _radio_t := 0.0
var _center_t := 0.0
var _damage := 0.0
var _banner: Control
var _rack_art := {}
var _rack_pos := 0.0 # carousel rotation, in cards (unwrapped)
var _rack_target := 0
var _rack_index := 0


func _ready() -> void:
	add_to_group("hud")
	for def in Arsenal.SPECIALS:
		var path := "res://assets/ui/missiles/%s.jpg" % def.id
		if ResourceLoader.exists(path):
			_rack_art[def.id] = load(path)
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

	_radio_card = RadioCard.new()
	_radio_card.position = Vector2(18, 58)
	add_child(_radio_card)


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
	_radio_card.clear()
	_center.text = ""
	_damage = 0.0
	_rack_index = 0
	_rack_target = 0
	_rack_pos = 0.0


## Queues a radio line; `mood` picks the speaker's expression (see Comic.SPEAKERS).
func radio(who: String, text: String, seconds: float, mood := "") -> void:
	_radio_queue.append([who, text, seconds, mood])


func message(text: String, seconds := 2.5) -> void:
	_center.text = text
	_center_t = seconds
	_center.modulate.a = 1.0


## Comic-style title card for a special missile: slams in from the left, holds, fades.
func banner(def: Dictionary) -> void:
	if _banner:
		_banner.queue_free()
	var col: Color = def.color
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.darkened(0.35), 0.92)
	sb.border_color = Color.BLACK
	sb.set_border_width_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.8)
	sb.shadow_offset = Vector2(6, 6)
	sb.content_margin_left = 26
	sb.content_margin_right = 34
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.rotation_degrees = -4.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var name_l := _label(40, Color(1.0, 0.95, 0.75), HORIZONTAL_ALIGNMENT_LEFT, vb)
	name_l.text = str(def.name).to_upper() + "!"
	name_l.add_theme_color_override("font_outline_color", Color.BLACK)
	name_l.add_theme_constant_override("outline_size", 10)
	var sub := _label(17, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, vb)
	sub.text = def.get("blurb", "")
	sub.add_theme_color_override("font_outline_color", Color.BLACK)
	sub.add_theme_constant_override("outline_size", 5)
	panel.position = Vector2(-700, size.y * 0.62)
	_banner = panel
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(panel, "position:x", 60.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.3)
	tw.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(panel.queue_free)


func flash_damage() -> void:
	_damage = 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_radio_t -= delta
	if _radio_t <= 0.0:
		if _radio_queue.is_empty():
			_radio_card.dismiss()
		else:
			var r = _radio_queue.pop_front()
			_radio_card.present(r[0], r[1], r[3])
			_radio_t = r[2] + 1.0 # a beat longer than before: the card is there to be read
			Sfx.play("beep", -18.0, 0.6)
	_center_t -= delta
	_center.modulate.a = clampf(_center_t * 2.0, 0.0, 1.0)
	_damage = maxf(0.0, _damage - delta * 2.0)
	_radio_card.scale = Vector2.ONE * clampf(size.x / 1280.0, 0.75, 1.6)
	if main and main.player:
		# Slide the carousel forward to the selected missile, in real time.
		var n := Arsenal.SPECIALS.size()
		var idx: int = main.player.special_index
		if idx != _rack_index:
			_rack_target += posmod(idx - _rack_index, n)
			_rack_index = idx
		var real_dt := delta / maxf(Engine.time_scale, 0.01)
		_rack_pos = lerpf(_rack_pos, float(_rack_target), 1.0 - exp(-real_dt * 9.0))
		if absf(_rack_pos - _rack_target) < 0.002:
			_rack_pos = float(_rack_target)
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
	if p.boosting:
		_draw_speed_lines(vs)
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
	var six := _bandit_on_six(p)
	if six:
		var arrow_c := Vector2(c.x, vs.y * 0.82)
		var d := (six.global_position - p.global_position)
		var local := p.global_transform.basis.inverse() * d
		var dir2 := Vector2(local.x, local.z).normalized() # +z is behind the jet
		draw_colored_polygon(PackedVector2Array([arrow_c + dir2 * 26, arrow_c - dir2 * 10 + Vector2(-dir2.y, dir2.x) * 14, arrow_c - dir2 * 10 - Vector2(-dir2.y, dir2.x) * 14]), RED)
		if blink:
			_text(Vector2(c.x - 250, wy), "BANDIT ON YOUR SIX - BREAK!", 22, RED, HORIZONTAL_ALIGNMENT_CENTER, 500)
		wy += 28
	if p.airbrake:
		_text(Vector2(c.x - 200, wy), "AIRBRAKE", 16, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 400)
		wy += 22
	if p.warn_boundary and blink:
		_text(Vector2(c.x - 250, wy), "RETURN TO MEGAKAT CITY", 22, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 500)

	_draw_radar(p, Vector2(110 * ui + 10, vs.y - 110 * ui - 10), 95 * ui)
	_draw_status(p, Vector2(vs.x - 300 * ui - 20, vs.y - 150 * ui - 10), ui)


## The nearest attacker sitting behind the jet within gun range, if any.
func _bandit_on_six(p: TurboKat) -> Target:
	var best: Target = null
	var best_d := 520.0
	for t: Target in main.combat.targets:
		if not is_instance_valid(t) or not t.alive or not (t is Creepling):
			continue
		var d := t.global_position - p.global_position
		var dist := d.length()
		if dist < best_d and p.forward().dot(d / dist) < -0.55 and (t as Creepling)._mode == "attack":
			best = t
			best_d = dist
	return best


## Anime-style speed lines streaking in from the screen edges while on afterburner.
func _draw_speed_lines(vs: Vector2) -> void:
	var c := vs * 0.5
	var r_out := vs.length() * 0.55
	for k in 34:
		var a := randf() * TAU
		var dir := Vector2(cos(a), sin(a))
		var r_in := r_out * randf_range(0.48, 0.72)
		var w := randf_range(1.0, 3.0)
		draw_line(c + dir * r_in, c + dir * r_out, Color(1, 1, 1, randf_range(0.12, 0.3)), w)


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
	for cache in main.combat.caches():
		if not is_instance_valid(cache) or not cache.available:
			continue
		var cd := Vector2(cache.global_position.x - p.global_position.x, cache.global_position.z - p.global_position.z)
		var cs := Vector2(cd.dot(right2), -cd.dot(f2)) * scale
		if cs.length() < r - 4:
			draw_rect(Rect2(c + cs - Vector2(3, 3), Vector2(6, 6)), SupplyCache.color_for(cache.kind))
			draw_rect(Rect2(c + cs - Vector2(3, 3), Vector2(6, 6)), Color.BLACK, false, 1.0)
	for t: Target in main.combat.targets:
		if not is_instance_valid(t) or not t.alive or not t.is_visible_in_tree():
			continue
		var d := Vector2(t.global_position.x - p.global_position.x, t.global_position.z - p.global_position.z)
		if t is GroundFlak and d.length() > 900.0:
			continue # flak nests only show up when you are close enough to matter
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
	_text(Vector2(o.x, y), "[F] BLOWTORCH  %02d" % p.missiles, 16, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	_draw_rack(p, Vector2(o.x, o.y - 50 * ui), w, ui)
	var lock_txt := "LOCKED" if p.locked else ("LOCKING" if p.lock_target else "NO LOCK")
	_text(Vector2(o.x, y + 24 * ui), lock_txt, 13, RED if p.locked else GREEN_DIM, HORIZONTAL_ALIGNMENT_LEFT)


## The special-missile rack as a cockpit weapons screen: a flat MFD showing one card for the
## selected missile (its picture from the show, via tools/fetch_missile_art.py), name and ammo.
## Cycling (Q) slides the cards sideways across the screen like a carousel.
func _draw_rack(p: TurboKat, o: Vector2, w: float, ui: float) -> void:
	var n := Arsenal.SPECIALS.size()
	var bez := 8.0 * ui
	var head_h := 18.0 * ui
	var img_h := (w - bez * 2.0) * 0.625
	var plate_h := 30.0 * ui
	var screen := Rect2(o.x + bez, o.y - plate_h - img_h - bez, w - bez * 2.0, img_h + plate_h)
	var frame := Rect2(screen.position - Vector2(bez, bez + head_h), screen.size + Vector2(bez * 2.0, bez * 2.0 + head_h))
	# Bezel and header strip.
	draw_rect(Rect2(frame.position + Vector2(4, 4) * ui, frame.size), Color(0, 0, 0, 0.5))
	draw_rect(frame, Color(0.09, 0.1, 0.12, 0.95))
	draw_rect(frame, Color(0.32, 0.34, 0.38), false, 2.0 * ui)
	var hy := frame.position.y + head_h * 0.5 + bez * 0.5 + 5 * ui
	_text(Vector2(screen.position.x, hy), "WPN SEL  [Q]", 12, GREEN, HORIZONTAL_ALIGNMENT_LEFT)
	_text(Vector2(screen.end.x - 120, hy), "[R] FIRE", 12, GREEN, HORIZONTAL_ALIGNMENT_RIGHT, 120)
	draw_rect(screen, Color(0.01, 0.02, 0.02))
	# Cards either side of the current slide position, clipped to the screen.
	var j0 := floori(_rack_pos)
	for j in [j0, j0 + 1]:
		var off := float(j) - _rack_pos # -1..1 card widths
		if absf(off) >= 1.0:
			continue
		_draw_rack_card(p, Arsenal.SPECIALS[posmod(j, n)], screen, img_h, off, ui)
	# Scanlines and a glass sheen sell the screen.
	var y := screen.position.y
	while y < screen.end.y:
		draw_line(Vector2(screen.position.x, y), Vector2(screen.end.x, y), Color(0, 0, 0, 0.18), 1.0)
		y += 3.0 * ui
	draw_rect(Rect2(screen.position, Vector2(screen.size.x, screen.size.y * 0.35)), Color(1, 1, 1, 0.04))
	draw_rect(screen, Color(0.62, 1.0, 0.72, 0.5), false, 1.0)
	# Position in the rack.
	for k in n:
		var dot := Vector2(screen.get_center().x + (k - (n - 1) * 0.5) * 12 * ui, frame.end.y + 9 * ui)
		draw_circle(dot, (3.5 if k == p.special_index else 2.2) * ui, AMBER if k == p.special_index else GREEN_DIM)


func _draw_rack_card(p: TurboKat, def: Dictionary, screen: Rect2, img_h: float, off: float, ui: float) -> void:
	var sw := screen.size.x
	var x0 := screen.position.x + off * sw
	var vis_l := maxf(x0, screen.position.x)
	var vis_r := minf(x0 + sw, screen.end.x)
	if vis_r - vis_l < 1.0:
		return
	var u0 := (vis_l - x0) / sw
	var u1 := (vis_r - x0) / sw
	var ammo: int = p.special_ammo.get(def.id, 0)
	var tex: Texture2D = _rack_art.get(def.id)
	var tint := Color.WHITE if ammo > 0 else Color(0.4, 0.4, 0.45)
	var img := Rect2(vis_l, screen.position.y, vis_r - vis_l, img_h)
	if tex:
		var ts := tex.get_size()
		draw_texture_rect_region(tex, img, Rect2(u0 * ts.x, 0, (u1 - u0) * ts.x, ts.y), tint)
	else:
		draw_rect(img, def.color * tint)
	var col: Color = def.color
	var plate := Rect2(vis_l, screen.position.y + img_h, vis_r - vis_l, screen.size.y - img_h)
	draw_rect(plate, col.darkened(0.45))
	draw_line(Vector2(vis_l, plate.position.y), Vector2(vis_r, plate.position.y), col.lightened(0.2), 2.0 * ui)
	if absf(off) > 0.02:
		return # labels once the card has settled
	var name_size := int(17 * ui)
	var name_pos := Vector2(x0 + 8 * ui, plate.position.y + plate.size.y * 0.5 + name_size * 0.36)
	draw_string_outline(font, name_pos, str(def.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, int(5 * ui), Color.BLACK)
	draw_string(font, name_pos, str(def.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(1.0, 0.95, 0.75))
	# Ammo pips down the right of the picture.
	var mx: int = def.get("max", ammo)
	for i in mx:
		var pip := Vector2(x0 + sw - 11 * ui, screen.position.y + (11 + i * 14) * ui)
		draw_circle(pip, 5.5 * ui, Color.BLACK)
		draw_circle(pip, 4.0 * ui, Color(1.0, 0.85, 0.3) if i < ammo else Color(0.25, 0.25, 0.28))
	if ammo <= 0:
		var stamp_pos := Vector2(x0, screen.position.y + img_h * 0.5 + 10 * ui)
		draw_string_outline(font, stamp_pos, "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, sw, int(28 * ui), int(8 * ui), Color.BLACK)
		draw_string(font, stamp_pos, "EMPTY", HORIZONTAL_ALIGNMENT_CENTER, sw, int(28 * ui), RED)


func _bar(o: Vector2, w: float, label: String, v: float, col: Color, ui: float) -> void:
	_text(o + Vector2(0, -6), label, 12, GREEN_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	draw_rect(Rect2(o + Vector2(0, 0), Vector2(w, 10 * ui)), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(o + Vector2(0, 0), Vector2(w * clampf(v, 0.0, 1.0), 10 * ui)), col)
