extends Node
## Sound effects synthesized at startup, so the repo ships no audio files.
## Sounds are mono 16-bit at 22.05 kHz to keep generation fast in the browser.

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 18:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build()
	_engine = AudioStreamPlayer.new()
	_engine.stream = _streams["engine"]
	add_child(_engine)


func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


## Plays a sound attenuated by distance from the listener (simple inverse-distance falloff).
func play_at(sound: String, pos: Vector3, listener: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var d := maxf(pos.distance_to(listener), 40.0)
	var db := volume_db - 20.0 * log(d / 40.0) / log(10.0)
	if db > -40.0:
		play(sound, db, pitch)


func set_engine(active: bool, throttle: float, boost: float) -> void:
	if not active:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.volume_db = lerpf(-20.0, -10.0, throttle) + boost * 4.0
	_engine.pitch_scale = 0.7 + throttle * 0.55 + boost * 0.35


# --- synthesis -----------------------------------------------------------------

func _build() -> void:
	_streams["gun"] = _wav(_gen(0.09, func(t, n, s):
		var hp: float = n - s.lp
		s.lp += 0.25 * (n - s.lp)
		return (hp * 0.9 + sin(TAU * 95.0 * t) * 0.6) * exp(-t * 45.0)))
	_streams["boom"] = _wav(_gen(1.6, func(t, n, s):
		s.lp += lerpf(0.35, 0.03, minf(t / 1.2, 1.0)) * (n - s.lp)
		return s.lp * 2.4 * exp(-t * 2.6) + sin(TAU * lerpf(70.0, 28.0, minf(t * 2.0, 1.0)) * t) * exp(-t * 4.5) * 0.8))
	_streams["missile"] = _wav(_gen(1.0, func(t, n, s):
		s.lp += lerpf(0.05, 0.4, minf(t * 3.0, 1.0)) * (n - s.lp)
		return s.lp * 1.6 * minf(t * 25.0, 1.0) * exp(-t * 2.2)))
	_streams["beep"] = _wav(_gen(0.07, func(t, _n, _s):
		return sin(TAU * 1150.0 * t) * 0.5 * minf((0.07 - t) * 60.0, 1.0)))
	_streams["lock"] = _wav(_gen(0.35, func(t, _n, _s):
		return signf(sin(TAU * 1650.0 * t)) * 0.22 * minf((0.35 - t) * 20.0, 1.0)))
	_streams["hit"] = _wav(_gen(0.18, func(t, n, _s):
		return (sin(TAU * 910.0 * t) + sin(TAU * 1437.0 * t) * 0.7 + sin(TAU * 2213.0 * t) * 0.4) * 0.35 * exp(-t * 28.0) + n * 0.5 * exp(-t * 70.0)))
	_streams["armor"] = _wav(_gen(0.12, func(t, n, _s):
		return (sin(TAU * 2600.0 * t) * 0.4 + n * 0.3) * exp(-t * 40.0)))
	_streams["pickup"] = _wav(_gen(0.36, func(t, _n, _s):
		var f := 880.0 if t < 0.12 else (1320.0 if t < 0.24 else 1760.0)
		return sin(TAU * f * t) * 0.45 * minf((0.36 - t) * 15.0, 1.0)))
	_streams["alarm"] = _wav(_gen(0.5, func(t, _n, _s):
		var f := 880.0 if fmod(t, 0.25) < 0.125 else 660.0
		return signf(sin(TAU * f * t)) * 0.18))
	_streams["overheat"] = _wav(_gen(0.6, func(t, n, s):
		s.lp += 0.5 * (n - s.lp)
		return (n - s.lp) * 0.6 * exp(-t * 4.0)))
	_streams["roar"] = _wav(_gen(1.8, func(t, n, s):
		s.lp += 0.08 * (n - s.lp)
		var saw := fmod(t * lerpf(95.0, 45.0, t / 1.8), 1.0) * 2.0 - 1.0
		return (saw * 0.45 + s.lp * 1.5) * minf(t * 6.0, 1.0) * exp(-t * 1.2)))
	# Engine loop: whole-number frequencies so the 1 s loop is seamless.
	_streams["engine"] = _wav(_gen(1.0, func(t, n, s):
		s.lp += 0.06 * (n - s.lp)
		var a := fmod(t * 55.0, 1.0) * 2.0 - 1.0
		var b := fmod(t * 83.0, 1.0) * 2.0 - 1.0
		return a * 0.18 + b * 0.12 + s.lp * 1.4), true)


func _gen(duration: float, f: Callable) -> PackedFloat32Array:
	var n := int(duration * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var state := {"lp": 0.0}
	for i in n:
		out[i] = f.call(float(i) / RATE, randf() * 2.0 - 1.0, state)
	return out


func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
