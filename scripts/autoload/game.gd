extends Node
## Global state: input map (built in code so it is readable and diffable), settings,
## saved best scores and the episode list.

const SAVE_PATH := "user://megakat_skies.cfg"
const SETTINGS_VERSION := 2

## Every folder under res://episodes/ that holds an episode. Each folder is self-contained: an
## `episode.gd` (menu card and briefing) and, for playable ones, a `mission.gd`, plus whatever
## code, shaders and art only that episode uses. Adding an episode = a new folder + one line here
## (the list is explicit so web exports never depend on scanning the packed file system).
const EPISODE_FOLDERS: Array[String] = ["ep01_dark_skies", "ep02_turmoil_rising", "ep03_vipers_swamp", "free_flight"]

## The episode cards, built from the folders above: {id, number, title, villain, story, objectives,
## playable, folder, script}. `script` is the folder's mission.gd (empty for coming-soon episodes).
var EPISODES: Array[Dictionary] = []

var invert_pitch := true
var muted := false
## Cinematic camera that follows special missiles.
var missile_cam := true
var best_scores := {}


func _init() -> void:
	for folder in EPISODE_FOLDERS:
		var dir := "res://episodes/%s" % folder
		var info: Dictionary = load(dir + "/episode.gd").new().info()
		info["folder"] = dir
		if ResourceLoader.exists(dir + "/mission.gd"):
			info["script"] = dir + "/mission.gd"
		EPISODES.append(info)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load()


func episode_by_id(id: String) -> Dictionary:
	for ep in EPISODES:
		if ep.id == id:
			return ep
	return {}


func next_playable_after(id: String) -> Dictionary:
	var found := false
	for ep in EPISODES:
		if found and ep.playable and ep.id != "free":
			return ep
		if ep.id == id:
			found = true
	return {}


## Returns true when this is a new best.
func record_score(id: String, score: int) -> bool:
	if score > int(best_scores.get(id, 0)):
		best_scores[id] = score
		_save()
		return true
	return false


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, muted)
	Music.set_muted(muted)
	_save()


func toggle_missile_cam() -> void:
	missile_cam = not missile_cam
	_save()


func toggle_invert() -> void:
	invert_pitch = not invert_pitch
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "version", SETTINGS_VERSION)
	cfg.set_value("settings", "invert_pitch", invert_pitch)
	cfg.set_value("settings", "muted", muted)
	cfg.set_value("settings", "missile_cam", missile_cam)
	for id in best_scores:
		cfg.set_value("best", id, best_scores[id])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	# Version 2 made inverted pitch the default: older saves get it switched on once.
	invert_pitch = cfg.get_value("settings", "invert_pitch", true) if int(cfg.get_value("settings", "version", 1)) >= 2 else true
	muted = cfg.get_value("settings", "muted", false)
	missile_cam = cfg.get_value("settings", "missile_cam", true)
	AudioServer.set_bus_mute(0, muted)
	Music.set_muted.call_deferred(muted)
	if cfg.has_section("best"):
		for id in cfg.get_section_keys("best"):
			best_scores[id] = cfg.get_value("best", id, 0)


func _setup_input() -> void:
	_bind("pitch_up", [KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("pitch_down", [KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("roll_left", [KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("roll_right", [KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("yaw_left", [KEY_A], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_bind("yaw_right", [KEY_D], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_bind("throttle_up", [KEY_W], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_bind("throttle_down", [KEY_S], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_bind("boost", [KEY_SHIFT], [JOY_BUTTON_RIGHT_SHOULDER])
	_bind("fire_guns", [KEY_SPACE], [JOY_BUTTON_A], [], [MOUSE_BUTTON_LEFT])
	_bind("fire_missile", [KEY_F], [JOY_BUTTON_B], [], [MOUSE_BUTTON_RIGHT])
	_bind("fire_special", [KEY_R], [JOY_BUTTON_X])
	_bind("cycle_special", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_bind("camera_cycle", [KEY_C], [JOY_BUTTON_Y])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	_bind("toggle_invert", [KEY_Y])
	_bind("toggle_mute", [KEY_M])


func _bind(action: String, keys: Array, buttons: Array = [], axes: Array = [], mouse: Array = []) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)
	for k in keys:
		var ek := InputEventKey.new()
		ek.physical_keycode = k
		InputMap.action_add_event(action, ek)
	for b in buttons:
		var eb := InputEventJoypadButton.new()
		eb.button_index = b
		InputMap.action_add_event(action, eb)
	for a in axes:
		var ea := InputEventJoypadMotion.new()
		ea.axis = a[0]
		ea.axis_value = a[1]
		InputMap.action_add_event(action, ea)
	for m in mouse:
		var em := InputEventMouseButton.new()
		em.button_index = m
		InputMap.action_add_event(action, em)
