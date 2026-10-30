extends Node
## Music: the launcher theme ("Big Trouble") and the Episode 1 story track ("Drop Bomb"), with
## crossfades. On the web the page's <audio> elements keep playing from the launcher into the
## game, so the theme never restarts; this node drives them through JavaScriptBridge
## (window.skMusic, defined in web/shell.html). On desktop it plays the same files with
## AudioStreamPlayers.

const TRACKS := {
	"theme": {"path": "res://assets/audio/big_trouble.mp3", "volume": 0.7, "loop": true},
	"story": {"path": "res://assets/audio/drop_bomb.mp3", "volume": 0.8, "loop": true}, # fades out at handover
}

var _web := OS.has_feature("web")
var _players := {}
var _tweens := {}
var _current := "theme"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _web:
		return
	for id in TRACKS:
		if not ResourceLoader.exists(TRACKS[id].path):
			continue
		var stream := load(TRACKS[id].path) as AudioStreamMP3
		stream.loop = TRACKS[id].loop
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -80.0
		add_child(player)
		_players[id] = player


## The launcher theme: fades it in (or keeps it playing), fading any other track out.
func play_theme(seconds := 2.5) -> void:
	_play("theme", seconds, false)


## The Episode 1 story music, from the top, crossfading from the theme.
func play_story(seconds := 1.5) -> void:
	_play("story", seconds, true)


func fade_out(seconds := 2.0) -> void:
	if _web:
		JavaScriptBridge.eval("window.skMusic && window.skMusic.fadeTo(0, %f)" % seconds)
		return
	for id in _players:
		_fade_player(id, 0.0, seconds)


func set_muted(muted: bool) -> void:
	if _web:
		JavaScriptBridge.eval("window.skMusic && window.skMusic.setMuted(%s)" % ("true" if muted else "false"))
	# On desktop the players sit on the master bus, which Game mutes.


func _play(id: String, seconds: float, restart: bool) -> void:
	_current = id
	var volume: float = TRACKS[id].volume
	if _web:
		JavaScriptBridge.eval("window.skMusic && window.skMusic.play('%s', %f, %f, %s)" % [id, volume, seconds, "true" if restart else "false"])
		return
	for other in _players:
		if other != id and _players[other].playing:
			_fade_player(other, 0.0, seconds)
	if not _players.has(id):
		return
	var player: AudioStreamPlayer = _players[id]
	if restart or not player.playing:
		player.volume_db = -80.0
		player.play(0.0)
	_fade_player(id, volume, seconds)


func _fade_player(id: String, volume: float, seconds: float) -> void:
	var player: AudioStreamPlayer = _players[id]
	if _tweens.has(id) and _tweens[id]:
		_tweens[id].kill()
	var tw := create_tween()
	_tweens[id] = tw
	tw.tween_property(player, "volume_db", linear_to_db(maxf(volume, 0.0001)), seconds)
	if volume <= 0.0:
		tw.tween_callback(player.stop)
