extends Mission
## Free Flight: endless, escalating Creepling waves. Ends when the TurboKat goes down.

var wave := 0
var _spawning := false


func start() -> void:
	radio("Razor", "Free flight. No Feral, no rules. Let's see how long we last.", 3.5)
	_next_wave()


func objective() -> String:
	return "WAVE %d   CONTACTS: %d" % [wave, enemies_alive()]


func update(_dt: float) -> void:
	if not _spawning and enemies_alive() <= 1:
		_spawning = true
		message("WAVE %d CLEARED" % wave)
		after(3.0, _next_wave)


func _next_wave() -> void:
	wave += 1
	var player: TurboKat = main.player
	var a := randf() * TAU
	var center := Vector3(cos(a) * 600.0, randf_range(220.0, 420.0), sin(a) * 600.0)
	if player.alive:
		center = (center + player.global_position) * 0.5 + Vector3(0, 120, 0)
	spawn_wave(center, 4 + wave * 2, wave / 2)
	_spawning = false
