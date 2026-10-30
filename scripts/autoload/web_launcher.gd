extends Node
## Bridge to the comic-page launcher in web/shell.html. On the web the page is the title screen:
## it shows the stage menu, briefings, controls and settings over the game canvas, and calls
## back here to launch a stage or change a setting. Inactive everywhere else (desktop builds and
## automated tests use the in-game menu).
##
## Page -> game: window.skGameLaunch(episode_id), window.skGameSetting(key, value)
## Game -> page: window.skLauncher.show(state_json), window.skLauncher.hide()

signal launch_requested(episode_id: String)

var active := false
## JavaScript callbacks must be kept alive for as long as the page may call them.
var _callbacks: Array = []


func _ready() -> void:
	if not OS.has_feature("web") or not JavaScriptBridge.eval("!!window.skLauncher", true):
		return
	active = true
	var win = JavaScriptBridge.get_interface("window")
	var launch_cb = JavaScriptBridge.create_callback(_on_launch)
	var setting_cb = JavaScriptBridge.create_callback(_on_setting)
	_callbacks = [launch_cb, setting_cb]
	win.skGameLaunch = launch_cb
	win.skGameSetting = setting_cb


## Brings the launcher up with the current episodes, best scores and settings.
func show() -> void:
	if not active:
		return
	# The canvas is covered while the launcher is up, so draw it at a low frame rate.
	Engine.max_fps = 20
	JavaScriptBridge.eval("window.skLauncher.show(%s)" % JSON.stringify(_state()))


func hide() -> void:
	if not active:
		return
	Engine.max_fps = 0
	JavaScriptBridge.eval("window.skLauncher.hide()")


func _state() -> Dictionary:
	var episodes := []
	for ep in Game.EPISODES:
		episodes.append({
			"id": ep.id, "number": ep.number, "title": ep.title, "villain": ep.villain,
			"story": ep.story, "objectives": ep.objectives, "playable": ep.playable,
			"best": int(Game.best_scores.get(ep.id, 0)),
		})
	return {
		"episodes": episodes,
		"settings": {"invert_pitch": Game.invert_pitch, "missile_cam": Game.missile_cam},
	}


func _on_launch(args: Array) -> void:
	if args.size() > 0:
		launch_requested.emit(str(args[0]))


func _on_setting(args: Array) -> void:
	if args.size() < 2:
		return
	var value := bool(args[1])
	match str(args[0]):
		"invert_pitch":
			if Game.invert_pitch != value:
				Game.toggle_invert()
		"missile_cam":
			if Game.missile_cam != value:
				Game.toggle_missile_cam()
