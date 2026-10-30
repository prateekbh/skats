extends Mission
## Episode 1: Dark Skies Over Megakat.
## Two waves of Creeplings over downtown, then Dark Kat's warship, with comic-strip story beats
## between them.
## All dialogue is original fan writing.

enum Phase { WAVE_1, WAVE_2, BOSS, OUTRO }

var phase := Phase.WAVE_1
var boss: DarkKatWarship
var _advancing := false


func start() -> void:
	var hq: Vector3 = main.city.enforcer_hq_pos
	spawn_wave(hq + Vector3(0, 280, 0), 6)
	radio("Callie Briggs", "SWAT Kats, come in! Dark Kat's Creeplings are tearing up downtown, right over Enforcer HQ!", 5.0, "alarmed")
	radio("T-Bone", "We read you, Callie. TurboKat's off the ground and hungry.", 3.5)
	radio("Razor", "Weapons hot. Keep 'em in the reticle for a lock, then send a missile.", 3.5)


func objective() -> String:
	match phase:
		Phase.WAVE_1:
			return "WAVE 1/2: DESTROY THE CREEPLINGS (%d LEFT)" % enemies_alive()
		Phase.WAVE_2:
			return "WAVE 2/2: DESTROY THE CREEPLINGS (%d LEFT)" % enemies_alive()
		Phase.BOSS:
			if boss and boss.phase == 0:
				var n := 0
				for t in boss.turrets:
					if t.alive:
						n += 1
				return "DARK KAT'S WARSHIP: DESTROY THE FLAK TURRETS (%d LEFT)" % n
			return "DARK KAT'S WARSHIP: DESTROY THE HULL"
	return "DARK KAT IS ESCAPING..."


func update(_dt: float) -> void:
	if _advancing:
		return
	match phase:
		Phase.WAVE_1:
			if enemies_alive() == 0:
				_advancing = true
				message("WAVE CLEARED")
				after(1.5, func(): cutscene([
					{"who": "Commander Feral", "mood": "angry", "caption": "Enforcer HQ",
						"text": "SWAT Kats! This is an Enforcer operation. Clear my airspace!"},
					{"who": "Lt. Felina Feral", "mood": "alert", "caption": "Enforcer radar",
						"text": "Commander, more Creeplings over City Hall. And they've brought bombers!"},
					{"who": "T-Bone", "mood": "grin", "caption": "The TurboKat",
						"text": "Sure thing, Commander. Right after we save it."},
				], _start_wave_2))
		Phase.WAVE_2:
			if enemies_alive() == 0:
				_advancing = true
				message("WAVE CLEARED")
				after(1.5, func(): cutscene([
					{"who": "Mayor Manx", "mood": "nervous", "caption": "City Hall",
						"text": "Something enormous just came out of the clouds over the bay! Somebody do something!"},
					{"who": "Callie Briggs", "mood": "alarmed", "caption": "City Hall",
						"text": "It's Dark Kat's warship, and it's heading straight for downtown. SWAT Kats, it's all yours!"},
					{"who": "Dark Kat", "mood": "sneer", "caption": "Over the bay",
						"text": "Megakat City is mine tonight. Creeplings, swat those pests out of my sky!"},
				], _start_boss))


func _start_wave_2() -> void:
	var center: Vector3 = main.city.city_hall_pos + Vector3(0, 260, 0)
	spawn_wave(center, 8, 2)
	radio("Razor", "Bombers in the mix! They're slower, but they hit hard. Use missiles.", 4.0)
	phase = Phase.WAVE_2
	_advancing = false


func _start_boss() -> void:
	phase = Phase.BOSS
	boss = main.spawn_boss(DarkKatWarship.new())
	boss.spawn_glider = func(pos: Vector3): main.spawn_creepling(pos, false, pos)
	boss.phase_changed.connect(_on_boss_phase)
	boss.destroyed.connect(_on_boss_destroyed)
	main.hud.message("WARNING: LARGE CONTACT", 3.0)
	Sfx.play("alarm", -6.0)
	radio("Razor", "The hull's armored. Take out the three flak turrets first!", 4.0)


func _on_boss_phase(_p: int) -> void:
	message("ARMOR DOWN")
	radio("Razor", "Turrets are scrap and the hull's exposed! Hit it with the Mega-Missile, R!", 4.5)
	radio("Dark Kat", "Launch the gliders! All of them!", 3.0, "angry")


func _on_boss_destroyed() -> void:
	phase = Phase.OUTRO
	main.slow_motion(1.6)
	message("WARSHIP DESTROYED", 3.5)
	radio("Dark Kat", "This isn't over, SWAT Kats! You'll pay for this!", 3.5, "angry")
	radio("T-Bone", "Bill it to the salvage yard, creep.", 3.0)
	radio("Callie Briggs", "Megakat City owes you again, guys. Thank you.", 3.5)
	after(6.0, win)
