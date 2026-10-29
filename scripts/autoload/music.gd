extends Node
## Theme music ("Big Trouble"). On the web, the loading page's <audio> element keeps playing
## from the loader into the game, so the track never restarts; this node drives it through
## JavaScriptBridge (window.skMusic, defined in web/shell.html). On desktop it plays the
## same file with an AudioStreamPlayer.

const TRACK := "res://assets/audio/big_trouble.mp3"
const THEME_VOLUME := 0.7 # linear, 0..1

var _web := OS.has_feature("web")
var _player: AudioStreamPlayer
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _web or not ResourceLoader.exists(TRACK):
		return
	var stream := load(TRACK) as AudioStreamMP3
	stream.loop = true
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = -80.0
	add_child(_player)


## Fades the theme in (or keeps it playing if it already is).
func play_theme(seconds := 2.5) -> void:
	_fade_to(THEME_VOLUME, seconds)


func fade_out(seconds := 2.0) -> void:
	_fade_to(0.0, seconds)


func set_muted(muted: bool) -> void:
	if _web:
		JavaScriptBridge.eval("window.skMusic && window.skMusic.setMuted(%s)" % ("true" if muted else "false"))
	# On desktop the player sits on the master bus, which Game mutes.


func _fade_to(volume: float, seconds: float) -> void:
	if _web:
		JavaScriptBridge.eval("window.skMusic && window.skMusic.fadeTo(%f, %f)" % [volume, seconds])
		return
	if _player == null:
		return
	if volume > 0.0 and not _player.playing:
		_player.play()
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", linear_to_db(maxf(volume, 0.0001)), seconds)
	if volume <= 0.0:
		_tween.tween_callback(_player.stop)
