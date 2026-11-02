extends Node
## Player analytics (Google Analytics 4, web build only). The page in web/shell.html loads gtag and
## defines window.skTrack / window.skState; this autoload sends the game's events through them.
## It does nothing on desktop, in autotests, or when the page has no analytics (so contributors'
## local runs and CI never send anything). No personal data is collected: only gameplay events.
##
## The user journey, in order (GA4 event names, snake_case):
##   game_loaded        the game finished loading behind the launcher (load_ms)
##   launcher_shown     the title page is up
##   episode_selected   a stage was picked (episode_id, attempt)
##   comic_started / comic_finished   story strips: intro, wave1, wave2, shield, epilogue (strip, seconds, skipped)
##   launch_skipped     the hatch launch was skipped with a key press
##   mission_started    controls in hand (episode_id, attempt, screen size, touch)
##   milestone          progress inside a mission: wave_1_cleared, boss_started, shield_proven, ...
##   special_fired      each special missile (weapon, ammo_left)
##   pause              paused mid-mission
##   mission_end        win or lose, with time, score, kills, accuracy, hull, rank, last milestone, reason
##   retry / quit_to_menu   what the player does next
##   setting_changed    invert pitch, missile cam, sound
##   game_exit          (sent by the page) the last state when the tab closed

var _enabled := false
## `--analytics-log`: print every event instead of sending it (for checking event wiring locally).
var _log := false
var _attempts := {}
var _t0 := 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_log = "--analytics-log" in OS.get_cmdline_user_args()
	_enabled = OS.has_feature("web") and _page_has_tracker()


func _page_has_tracker() -> bool:
	return bool(JavaScriptBridge.eval("typeof window.skTrack === 'function'", true))


## Sends one event. Parameters are flattened to strings and numbers (GA4 limits: 40-character
## names, 25 parameters, 100-character string values).
func track(event: String, params := {}) -> void:
	if not _enabled and OS.has_feature("web"):
		_enabled = _page_has_tracker() # the page may finish defining skTrack after this autoload started
	if not _enabled and not _log:
		return
	var clean := {}
	for k in params:
		var v = params[k]
		clean[str(k)] = v if (v is int or v is float or v is bool) else str(v).left(100)
	clean["session_s"] = int((Time.get_ticks_msec() - _t0) / 1000.0)
	if _log:
		print("[analytics] ", event, " ", JSON.stringify(clean))
	if _enabled:
		JavaScriptBridge.eval("window.skTrack(%s, %s)" % [JSON.stringify(event), JSON.stringify(clean)])


## What the player is doing right now; the page reports it if they close the tab.
func set_state(state: String) -> void:
	if not _enabled and OS.has_feature("web"):
		_enabled = _page_has_tracker()
	if _enabled:
		JavaScriptBridge.eval("window.skState = %s" % JSON.stringify(state))


## 1 for the first try of an episode in this session, 2 for the first retry, and so on.
func next_attempt(episode_id: String) -> int:
	_attempts[episode_id] = int(_attempts.get(episode_id, 0)) + 1
	return _attempts[episode_id]


func attempt(episode_id: String) -> int:
	return int(_attempts.get(episode_id, 1))
