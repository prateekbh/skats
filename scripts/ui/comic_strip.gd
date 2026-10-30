class_name ComicStrip
extends Control
## Story beats between waves as a comic strip: the game pauses, a paper strip drops across the
## screen and its panels slam in one at a time, each with a character (show art from
## tools/fetch_character_art.py), a location caption and a speech bubble. Any key or click shows
## the next panel at once; after the last one it continues on a key, or by itself after a beat.
##
## Panel: {"who": "Mayor Manx", "mood": "nervous", "caption": "City Hall", "text": "..."}

signal finished

var _panels: Array = []
var _nodes: Array[Control] = []
var _shown := 0
var _next_t := 0.0
var _hold_t := 0.0
var _prompt: Label
var _active := false
var _closing := false
## Seconds since the strip opened: input is ignored at first, so a fire button still held from
## the fight doesn't skip it.
var _age := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func play(panels: Array) -> void:
	for c in get_children():
		c.queue_free()
	_panels = panels
	_nodes.clear()
	_shown = 0
	_next_t = 0.35
	_hold_t = 0.0
	_closing = false
	_age = 0.0
	_active = true
	visible = true
	modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var vs := get_viewport_rect().size
	var ui := clampf(vs.x / 1280.0, 0.6, 1.6)

	var dim := ColorRect.new()
	dim.color = Color(Comic.INK, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.55, 0.25)

	# The paper strip with the panels side by side.
	var n := panels.size()
	var gutter := 14.0 * ui
	var strip_w := minf(vs.x - 40.0 * ui, 420.0 * ui * n + gutter * (n + 1))
	var strip_h := minf(vs.y * 0.7, 440.0 * ui)
	var strip := Panel.new()
	strip.add_theme_stylebox_override("panel", Comic.box(Comic.PAPER, 0, 0, 0))
	strip.size = Vector2(strip_w, strip_h)
	strip.position = (vs - strip.size) * 0.5
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	var pw := (strip_w - gutter * (n + 1)) / n
	var ph := strip_h - gutter * 2.0
	for i in n:
		# An empty inked frame waits where each panel will land.
		var slot := Panel.new()
		var ssb := Comic.box(Comic.PAPER.darkened(0.08), int(5 * ui), 0, 0)
		slot.add_theme_stylebox_override("panel", ssb)
		slot.size = Vector2(pw, ph)
		slot.position = Vector2(gutter + i * (pw + gutter), gutter)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.add_child(slot)
	for i in n:
		var node := _build_panel(panels[i], Vector2(pw, ph), ui)
		node.position = Vector2(gutter + i * (pw + gutter), gutter)
		node.visible = false
		strip.add_child(node)
		_nodes.append(node)

	_prompt = Comic.label("PRESS ANY KEY  ▶", Comic.DISPLAY_FONT, int(22 * ui), Comic.YELLOW)
	_prompt.add_theme_color_override("font_outline_color", Comic.INK)
	_prompt.add_theme_constant_override("outline_size", int(8 * ui))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_prompt.size = Vector2(strip_w, 40 * ui)
	_prompt.position = strip.position + Vector2(0, strip_h + 8 * ui)
	_prompt.visible = false
	add_child(_prompt)


func _build_panel(p: Dictionary, sz: Vector2, ui: float) -> Control:
	var who: String = p.get("who", "")
	var villain := Comic.is_villain(who)
	var panel := Panel.new()
	panel.size = sz
	panel.pivot_offset = sz * 0.5
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", Comic.box(Color(0.1, 0.08, 0.14), int(6 * ui), 0, 0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.texture = Comic.panel_art(who, p.get("mood", ""))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.position = Vector2(6, 6) * ui
	art.size = sz - Vector2(12, 12) * ui
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(art)
	# Ink frame drawn over the art.
	var frame := Panel.new()
	var fsb := Comic.box(Color(0, 0, 0, 0), int(6 * ui), 0, 0)
	fsb.draw_center = false
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size = sz
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(frame)

	if p.get("caption", "") != "":
		var cap := PanelContainer.new()
		var csb := Comic.box(Comic.YELLOW, int(3 * ui), 0, int(3 * ui))
		csb.content_margin_left = 8 * ui
		csb.content_margin_right = 8 * ui
		cap.add_theme_stylebox_override("panel", csb)
		cap.position = Vector2(12, 12) * ui
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.add_child(Comic.label(str(p.caption).to_upper(), Comic.DISPLAY_FONT, int(22 * ui), Comic.INK))
		panel.add_child(cap)

	# Speech bubble along the bottom, its tail pointing up at the speaker.
	var bubble := PanelContainer.new()
	var bsb := Comic.box(Comic.VILLAIN_BUBBLE if villain else Color.WHITE, int(4 * ui), int(22 * ui), int(4 * ui))
	bsb.content_margin_left = 16 * ui
	bsb.content_margin_right = 16 * ui
	bsb.content_margin_top = 8 * ui
	bsb.content_margin_bottom = 12 * ui
	bubble.add_theme_stylebox_override("panel", bsb)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	bubble.add_child(vb)
	var name := Comic.label(who.to_upper(), Comic.DISPLAY_FONT, int(21 * ui), Comic.VILLAIN_CAPTION if villain else Comic.RED)
	vb.add_child(name)
	var text := Comic.label(p.get("text", ""), Comic.BODY_FONT, int(22 * ui), Comic.INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(sz.x - 60 * ui, 0)
	vb.add_child(text)
	panel.add_child(bubble)
	bubble.custom_minimum_size = Vector2(sz.x - 28 * ui, 0)
	var tail := Control.new()
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.size = sz
	panel.add_child(tail)
	# Place the bubble once its height is known.
	var place := func():
		var h := bubble.get_combined_minimum_size().y
		bubble.position = Vector2(14 * ui, sz.y - h - 14 * ui)
		var top := bubble.position.y + 2.0
		var x := sz.x * 0.42
		tail.draw.connect(func(): Comic.draw_tail(tail, Vector2(x, top), Vector2(x + 26 * ui, top), Vector2(x - 6 * ui, top - 34 * ui), bsb.bg_color, 4 * ui))
		tail.queue_redraw()
	place.call_deferred()
	return panel


func _process(delta: float) -> void:
	if not _active or _closing:
		return
	_age += delta
	if _shown < _nodes.size():
		_next_t -= delta
		if _next_t <= 0.0:
			_reveal()
	else:
		_hold_t -= delta
		_prompt.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.008)
		if _hold_t <= 0.0:
			_close()


func _reveal() -> void:
	var node := _nodes[_shown]
	var text: String = _panels[_shown].get("text", "")
	node.visible = true
	node.scale = Vector2.ONE * 1.3
	node.rotation_degrees = [-4.0, 3.0, -2.0][_shown % 3]
	node.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(node, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "rotation_degrees", 0.0, 0.3)
	tw.tween_property(node, "modulate:a", 1.0, 0.12)
	Sfx.play("beep", -16.0, 0.75)
	_shown += 1
	# Time to read this panel before the next one lands.
	_next_t = 1.0 + text.length() * 0.045
	if _shown == _nodes.size():
		_prompt.visible = true
		_hold_t = _next_t + 2.0


func _close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		visible = false
		_active = false
		finished.emit())


func is_active() -> bool:
	return _active


## Drops the strip without continuing (the world is being cleared).
func cancel() -> void:
	_active = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if not _active or _closing:
		return
	var pressed := (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if _age < 0.6:
		return
	if _shown < _nodes.size():
		_reveal()
	else:
		_close()
