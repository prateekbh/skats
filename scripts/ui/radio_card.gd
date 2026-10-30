class_name RadioCard
extends Control
## In-flight radio chatter as a comic card: the speaker's portrait (with an expression for the
## line), a name caption and a speech bubble. Slides in from the left, types its line out, and
## slides away when the HUD moves on. Villains get a purple caption and a lilac bubble.

const PORTRAIT := 152.0
const BUBBLE_X := 176.0
const BUBBLE_W := 500.0

var _frame: Panel
var _face: TextureRect
var _caption: PanelContainer
var _name: Label
var _bubble: PanelContainer
var _text: Label
var _tail: Control
var _tween: Tween
var _shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(BUBBLE_X + BUBBLE_W + 10, PORTRAIT + 30)

	_frame = Panel.new()
	_frame.add_theme_stylebox_override("panel", Comic.box(Color.WHITE, 5, 0, 5))
	_frame.size = Vector2(PORTRAIT, PORTRAIT)
	_frame.pivot_offset = _frame.size * 0.5
	_frame.rotation_degrees = -3.0
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_frame)
	_face = TextureRect.new()
	_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face.position = Vector2(5, 5)
	_face.size = Vector2(PORTRAIT - 10, PORTRAIT - 10)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(_face)

	_bubble = PanelContainer.new()
	var bsb := Comic.box(Color.WHITE, 4, 26, 5)
	bsb.content_margin_left = 22
	bsb.content_margin_right = 22
	bsb.content_margin_top = 14
	bsb.content_margin_bottom = 16
	_bubble.add_theme_stylebox_override("panel", bsb)
	_bubble.position = Vector2(BUBBLE_X, 6)
	_bubble.custom_minimum_size = Vector2(BUBBLE_W, 86)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bubble)
	_text = Comic.label("", Comic.BODY_FONT, 24, Comic.INK)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(BUBBLE_W - 44, 0)
	_bubble.add_child(_text)

	# The tail is drawn over the bubble's border so the two read as one shape.
	_tail = Control.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.draw.connect(func():
		var fill: Color = (_bubble.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
		Comic.draw_tail(_tail, Vector2(BUBBLE_X + 3, 36), Vector2(BUBBLE_X + 3, 66), Vector2(PORTRAIT - 6, 78), fill))
	_tail.size = size
	add_child(_tail)

	_caption = PanelContainer.new()
	var csb := Comic.box(Comic.YELLOW, 3, 0, 3)
	csb.content_margin_left = 10
	csb.content_margin_right = 10
	csb.content_margin_top = 1
	csb.content_margin_bottom = 1
	_caption.add_theme_stylebox_override("panel", csb)
	_caption.position = Vector2(-4, PORTRAIT - 12)
	_caption.rotation_degrees = -3.0
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_caption)
	_name = Comic.label("", Comic.DISPLAY_FONT, 28, Comic.INK)
	_caption.add_child(_name)
	visible = false


## Shows a line. `mood` picks the portrait expression (see Comic.SPEAKERS).
func present(who: String, text: String, mood := "") -> void:
	var villain := Comic.is_villain(who)
	_face.texture = Comic.portrait(who, mood)
	_frame.visible = _face.texture != null
	_name.text = who.to_upper()
	_name.add_theme_color_override("font_color", Color.WHITE if villain else Comic.INK)
	(_caption.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Comic.VILLAIN_CAPTION if villain else Comic.YELLOW
	(_bubble.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Comic.VILLAIN_BUBBLE if villain else Color.WHITE
	_text.text = text
	_text.visible_ratio = 0.0
	_tail.queue_redraw()
	visible = true
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	if not _shown:
		modulate.a = 1.0
		position.x = -size.x - 40.0
		_tween.tween_property(self, "position:x", _rest_x(), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		# Next line from the same card: a quick pop on the portrait.
		_frame.scale = Vector2.ONE * 0.85
		_tween.tween_property(_frame, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_text, "visible_ratio", 1.0, clampf(text.length() * 0.022, 0.3, 1.2))
	_shown = true


func dismiss() -> void:
	if not _shown:
		return
	_shown = false
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "position:x", -size.x - 40.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func(): visible = false)


func clear() -> void:
	if _tween:
		_tween.kill()
	_shown = false
	visible = false


func _rest_x() -> float:
	return 18.0
