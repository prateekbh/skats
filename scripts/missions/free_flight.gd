extends Mission
## Free Flight: endless, escalating Creepling waves. Ends when the TurboKat goes down.

var wave := 0
var _spawning := false

## A warning strip every third wave, in rotation.
const BEATS := [
	[{"who": "Lt. Felina Feral", "mood": "alert", "caption": "Enforcer radar",
		"text": "Radar's lighting up over the bay. A bigger wave is inbound, SWAT Kats!"}],
	[{"who": "Mayor Manx", "mood": "nervous", "caption": "City Hall",
		"text": "I have an election coming up! Keep those things away from City Hall!"},
	{"who": "Callie Briggs", "mood": "calm", "caption": "City Hall",
		"text": "Ignore him, guys. Just keep the city in one piece."}],
	[{"who": "Commander Feral", "mood": "stern", "caption": "Enforcer HQ",
		"text": "Hmph. Fine, SWAT Kats. Hold them off until my Enforcers regroup."}],
	[{"who": "Callie Briggs", "mood": "alarmed", "caption": "City Hall",
		"text": "They just keep coming! How much longer can you hold out?"}],
]


func start() -> void:
	radio("Razor", "Free flight. No Feral, no rules. Let's see how long we last.", 3.5)
	_next_wave()


func objective() -> String:
	return "WAVE %d   CONTACTS: %d" % [wave, enemies_alive()]


func update(_dt: float) -> void:
	if not _spawning and enemies_alive() <= 1:
		_spawning = true
		message("WAVE %d CLEARED" % wave)
		if wave % 3 == 0:
			var beat: Array = BEATS[(wave / 3 - 1) % BEATS.size()]
			after(1.5, func(): cutscene(beat, func(): after(1.0, _next_wave)))
		else:
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
