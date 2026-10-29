extends Control
## Title, briefing, pause and debrief screens, built in code in a comic-panel style.

signal launch(episode: Dictionary)
signal resume
signal restart
signal quit_to_title

const YELLOW := Color(1.0, 0.82, 0.25)
const ORANGE := Color(1.0, 0.42, 0.12)
const INK := Color(0.03, 0.03, 0.05)
const PANEL := Color(0.09, 0.11, 0.18, 0.94)
const TEXT := Color(0.93, 0.94, 1.0)
const MUTED := Color(0.65, 0.68, 0.8)

const CONTROLS := [
	["Pitch", "↑ / ↓", "Left stick"],
	["Roll", "← / →", "Left stick"],
	["Rudder", "A / D", "Right stick"],
	["Throttle", "W / S", "RT / LT"],
	["Afterburner", "Shift", "RB"],
	["Cannon", "Space / Left click", "A"],
	["Missile (lock first)", "F / Right click", "B"],
	["Mega-Missile", "R", "X"],
	["Camera", "C", "Y"],
	["Invert pitch / Mute", "Y / M", ""],
	["Pause", "Esc / P", "Start"],
]

var _screen: Control
var _theme := Theme.new()
var _pending_episode: Dictionary


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	theme = _theme


func _build_theme() -> void:
	var normal := _button_box(YELLOW)
	var hover := _button_box(Color(1.0, 0.9, 0.5))
	var pressed := _button_box(ORANGE)
	var disabled := _button_box(Color(0.3, 0.32, 0.4))
	_theme.set_stylebox("normal", "Button", normal)
	_theme.set_stylebox("hover", "Button", hover)
	_theme.set_stylebox("pressed", "Button", pressed)
	_theme.set_stylebox("disabled", "Button", disabled)
	var focus := _button_box(Color(0, 0, 0, 0))
	focus.draw_center = false
	focus.border_color = Color.WHITE
	_theme.set_stylebox("focus", "Button", focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_theme.set_color(c, "Button", INK)
	_theme.set_color("font_disabled_color", "Button", Color(0.65, 0.66, 0.72))
	_theme.set_font_size("font_size", "Button", 20)
	_theme.set_color("font_color", "Label", TEXT)
	_theme.set_font_size("font_size", "Label", 18)


func _button_box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.shadow_color = INK
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(5, 5)
	sb.set_content_margin_all(12)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	return sb


func _panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL
	sb.border_color = INK
	sb.set_border_width_all(4)
	sb.shadow_color = Color(0, 0, 0, 0.7)
	sb.shadow_offset = Vector2(8, 8)
	sb.set_content_margin_all(26)
	return sb


## Intro overlay: a skip hint, then (via slam_logo) the logo crashing onto the screen.
func show_intro() -> void:
	hide_all()
	visible = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_screen = root
	var hint := _label(root, "PRESS ANY KEY TO SKIP", 14, Color(1, 1, 1, 0.6))
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -200
	hint.offset_right = 200
	hint.offset_top = -44
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func slam_logo() -> void:
	if _screen == null:
		return
	var flash := ColorRect.new()
	flash.color = Color(1, 0.95, 0.85, 0.85)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(flash)
	var title: Control = _logo_art(720.0)
	if title:
		_screen.add_child(title)
		var sz := title.custom_minimum_size
		title.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		title.offset_left = -sz.x * 0.5
		title.offset_right = sz.x * 0.5
		title.offset_top = -sz.y * 0.5 - 70
		title.offset_bottom = sz.y * 0.5 - 70
		title.pivot_offset = sz * 0.5
	else:
		var label := _label(_screen, "SWAT KATS", 120, YELLOW)
		label.add_theme_color_override("font_outline_color", ORANGE)
		label.add_theme_constant_override("outline_size", 22)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		label.offset_left = -560
		label.offset_right = 560
		label.offset_top = -180
		label.offset_bottom = -20
		label.pivot_offset = Vector2(560, 80)
		title = label
	var sub := _label(_screen, "MEGAKAT  SKIES", 32, TEXT)
	sub.add_theme_color_override("font_outline_color", INK)
	sub.add_theme_constant_override("outline_size", 8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sub.offset_left = -400
	sub.offset_right = 400
	sub.offset_top = 150
	sub.offset_bottom = 200
	sub.modulate.a = 0.0
	title.scale = Vector2.ONE * 2.6
	title.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "color:a", 0.0, 0.45)
	tw.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(title, "modulate:a", 1.0, 0.2)
	tw.tween_property(sub, "modulate:a", 1.0, 0.4).set_delay(0.45)


func hide_all() -> void:
	if _screen:
		_screen.queue_free()
		_screen = null
	visible = false


func _new_screen(dim := 0.35, left := false) -> VBoxContainer:
	hide_all()
	visible = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_screen = root
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.06, dim)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var holder: Container
	if left and get_viewport_rect().size.x >= 1000.0:
		# Wide screens: dock the panel left so the TurboKat flyby stays visible on the right.
		holder = MarginContainer.new()
		holder.add_theme_constant_override("margin_left", 48)
		holder.add_theme_constant_override("margin_top", 32)
		holder.add_theme_constant_override("margin_bottom", 32)
		holder.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	else:
		holder = CenterContainer.new()
		holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_box())
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(minf(620.0, get_viewport_rect().size.x - 48.0), 0)
	panel.add_child(vb)
	return vb


func _label(parent: Node, text: String, size := 18, color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable, enabled := true) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


const LOGO_PATH := "res://assets/ui/logo.svg"


## The show's logo (traced vector, see tools/prepare_launch_art.py) at the given width.
func _logo_art(width: float) -> TextureRect:
	if not ResourceLoader.exists(LOGO_PATH):
		return null
	var tex := load(LOGO_PATH) as Texture2D
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(width, width * tex.get_height() / tex.get_width())
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _logo(parent: Node) -> void:
	var art := _logo_art(440.0)
	if art:
		parent.add_child(art)
		var s0 := _label(parent, "MEGAKAT  SKIES", 22, TEXT)
		s0.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s0.add_theme_color_override("font_outline_color", INK)
		s0.add_theme_constant_override("outline_size", 6)
		return
	var t := _label(parent, "SWAT KATS", 76, YELLOW)
	t.add_theme_color_override("font_outline_color", ORANGE)
	t.add_theme_constant_override("outline_size", 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := _label(parent, "MEGAKAT  SKIES", 26, TEXT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_color_override("font_outline_color", INK)
	s.add_theme_constant_override("outline_size", 6)


# --- screens ----------------------------------------------------------------------

func show_title() -> void:
	var vb := _new_screen(0.0, true)
	vb.custom_minimum_size.x = minf(520.0, get_viewport_rect().size.x - 48.0)
	_logo(vb)
	_label(vb, "Fly the TurboKat. Defend Megakat City.", 17, MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(HSeparator.new())
	var first: Button
	for ep in Game.EPISODES:
		var best := int(Game.best_scores.get(ep.id, 0))
		var txt := "%s  ·  %s" % [ep.number.to_upper(), ep.title]
		if not ep.playable:
			txt += "   (coming soon)"
		elif best > 0:
			txt += "   ★ %d" % best
		var b := _button(vb, txt, _choose.bind(ep), ep.playable)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if first == null and ep.playable:
			first = b
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	_button(row, "Controls", show_controls).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inv := _button(row, "Invert pitch: %s" % ("ON" if Game.invert_pitch else "OFF"), func():
		Game.toggle_invert()
		show_title())
	inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var foot := _label(vb, "Unofficial non-commercial fan game. SWAT Kats is a trademark of its owners; this project is not affiliated with or endorsed by Warner Bros. Discovery.", 12, MUTED, true)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if first:
		first.grab_focus.call_deferred()


func _choose(ep: Dictionary) -> void:
	show_briefing(ep)


func show_briefing(ep: Dictionary) -> void:
	_pending_episode = ep
	var vb := _new_screen(0.5)
	_label(vb, ep.number.to_upper(), 16, ORANGE)
	var title := _label(vb, ep.title, 40, YELLOW)
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 8)
	_label(vb, "Villain: " + ep.villain, 16, MUTED)
	vb.add_child(HSeparator.new())
	_label(vb, ep.story, 18, TEXT, true)
	_label(vb, "OBJECTIVES", 15, ORANGE)
	for o in ep.objectives:
		_label(vb, "▸ " + o, 17, TEXT, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var go := _button(row, "LAUNCH THE TURBOKAT", func(): launch.emit(_pending_episode))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "Back", show_title)
	go.grab_focus.call_deferred()


func show_controls() -> void:
	var vb := _new_screen(0.5)
	_label(vb, "FLIGHT CONTROLS", 30, YELLOW)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for h in ["Action", "Keyboard / Mouse", "Gamepad"]:
		_label(grid, h, 14, ORANGE)
	for row in CONTROLS:
		_label(grid, row[0], 16, TEXT)
		_label(grid, row[1], 16, YELLOW)
		_label(grid, row[2], 16, MUTED)
	_label(vb, "Tip: bank and pull to turn. Release the roll keys and the TurboKat levels itself.", 15, MUTED, true)
	_button(vb, "Back", show_title).grab_focus.call_deferred()


func show_pause() -> void:
	var vb := _new_screen(0.55)
	_label(vb, "PAUSED", 40, YELLOW).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(vb, "Resume", func(): resume.emit()).grab_focus.call_deferred()
	_button(vb, "Restart episode", func(): restart.emit())
	_button(vb, "Invert pitch: %s" % ("ON" if Game.invert_pitch else "OFF"), func():
		Game.toggle_invert()
		show_pause())
	_button(vb, "Quit to title", func(): quit_to_title.emit())


## data: {win, reason, episode, score, kills, accuracy, time, hull, bonus, rank, new_best}
func show_debrief(data: Dictionary) -> void:
	var vb := _new_screen(0.6)
	var head := _label(vb, "MISSION COMPLETE" if data.win else "TURBOKAT DOWN", 40, YELLOW if data.win else ORANGE)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_outline_color", INK)
	head.add_theme_constant_override("outline_size", 8)
	if data.reason != "":
		_label(vb, data.reason, 16, MUTED, true).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rank := _label(vb, "RANK  " + data.rank, 56, YELLOW)
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	vb.add_child(grid)
	for row in [
		["Score", str(data.score) + ("   NEW BEST!" if data.new_best else "")],
		["Kills", str(data.kills)],
		["Accuracy", "%d%%" % data.accuracy],
		["Time", "%d:%02d" % [int(data.time) / 60, int(data.time) % 60]],
		["Hull remaining", "%d%%" % data.hull],
		["Bonus", "+" + str(data.bonus)],
	]:
		_label(grid, row[0], 18, MUTED)
		_label(grid, row[1], 18, TEXT)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vb.add_child(row2)
	var next_ep: Dictionary = Game.next_playable_after(data.episode.id) if data.win else {}
	var first: Button
	if not next_ep.is_empty():
		first = _button(row2, "Next episode", func(): show_briefing(next_ep))
	var retry := _button(row2, "Retry", func(): restart.emit())
	if first == null:
		first = retry
	_button(row2, "Title", func(): quit_to_title.emit())
	first.grab_focus.call_deferred()
