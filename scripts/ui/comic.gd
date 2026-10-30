class_name Comic
extends RefCounted
## Shared look for the in-game comic elements (radio cards, cutscene strips), matching the
## comic-page launcher: ink borders, yellow captions, speech bubbles, Bangers and Comic Neue.
## Portraits come from tools/fetch_character_art.py.

const INK := Color(0.047, 0.043, 0.063)
const YELLOW := Color(1.0, 0.824, 0.227)
const RED := Color(0.843, 0.149, 0.118)
const PAPER := Color(0.937, 0.894, 0.784)
const VILLAIN_BUBBLE := Color(0.92, 0.87, 1.0)
const VILLAIN_CAPTION := Color(0.36, 0.13, 0.5)

const DISPLAY_FONT := preload("res://assets/fonts/Bangers-Regular.ttf")
const BODY_FONT := preload("res://assets/fonts/ComicNeue-Bold.ttf")

## Speaker -> [portrait id, default mood]. Moods available per character are the files in
## assets/ui/portraits/ (<id>_<mood>.png).
const SPEAKERS := {
	"Callie Briggs": ["callie", "calm"],
	"Commander Feral": ["feral", "stern"],
	"Lt. Felina Feral": ["felina", "alert"],
	"Mayor Manx": ["manx", "smug"],
	"Ann Gora": ["ann", "reporting"],
	"T-Bone": ["tbone", "grin"],
	"Razor": ["razor", "focused"],
	"Dark Kat": ["dark_kat", "sneer"],
}
const VILLAINS := ["Dark Kat", "Turmoil"]


static func is_villain(who: String) -> bool:
	return who in VILLAINS


## The art file for a speaker in a mood (falling back to their default mood), or "".
static func art_path(who: String, mood: String, folder: String, ext: String) -> String:
	if not SPEAKERS.has(who):
		return ""
	var id: String = SPEAKERS[who][0]
	for m in [mood, SPEAKERS[who][1]]:
		var path := "res://assets/ui/%s/%s_%s.%s" % [folder, id, m, ext]
		if m != "" and ResourceLoader.exists(path):
			return path
	return ""


static func portrait(who: String, mood := "") -> Texture2D:
	var path := art_path(who, mood, "portraits", "png")
	return load(path) if path != "" else null


static func panel_art(who: String, mood := "") -> Texture2D:
	var path := art_path(who, mood, "panels", "jpg")
	return load(path) if path != "" else null


## Flat box with an ink border and a hard offset shadow.
static func box(bg: Color, border := 4, radius := 0, shadow := 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = INK
	sb.set_border_width_all(border)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(INK, 0.85)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(shadow, shadow)
	if shadow > 0:
		sb.shadow_size = 1
	sb.anti_aliasing = true
	return sb


static func label(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A speech-bubble tail: a white wedge from `base` (two points on the bubble edge) to `tip`,
## inked on its two outer edges only so it joins the bubble seamlessly.
static func draw_tail(ci: CanvasItem, base_a: Vector2, base_b: Vector2, tip: Vector2, fill: Color, width := 4.0) -> void:
	ci.draw_colored_polygon(PackedVector2Array([base_a, tip, base_b]), fill)
	ci.draw_line(base_a, tip, INK, width, true)
	ci.draw_line(tip, base_b, INK, width, true)
