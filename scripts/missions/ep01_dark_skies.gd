extends Mission
## Episode 1: Dark Skies Over Megakat, in three parts.
##
##   Prologue  (strip, after the episode is chosen)  a news flash, HQ under attack, Callie's call
##   Part 1    First Strike     Creeplings over Enforcer HQ; it was bait
##   Part 2    Breaking News    gliders and bombers over City Hall; Dark Kat takes over the airwaves
##   Part 3    Dark Kat City    the Fear Ship II; the Enforcer building is the target
##   Epilogue  (strip)          the aftermath
##
## Dark Kat is cutting the city's head off piece by piece: HQ, then City Hall, then HQ again with
## the bomb. All dialogue is original fan writing.

enum Phase { WAVE_1, WAVE_2, BOSS, OUTRO }

var phase := Phase.WAVE_1
var boss: DarkKatWarship
var _advancing := false
var _spotted := false


## Every comic strip of the episode, by name (also used by `--comicshow`).
func strips() -> Dictionary:
	return {
		"intro": [
			{"who": "Ann Gora", "mood": "reporting", "caption": "Over Megakat City",
				"text": "Breaking news, live over Megakat City! Creeplings, dozens of them, swarming Enforcer HQ. I'm not going anywhere!"},
			{"who": "Mayor Manx", "mood": "golf", "caption": "Megakat Golf Club",
				"text": "Evacuate? Of course! Someone fetch my limo. And my clubs."},
			{"who": "Commander Feral", "mood": "stern", "caption": "Enforcer HQ",
				"text": "All jets, scramble! Dark Kat hit this building the day it opened. Two of my pilots stopped him. Best I ever had."},
			{"who": "T-Bone", "mood": "grin", "caption": "The salvage yard",
				"text": "\"Best I ever had,\" huh? Not one word, buddy."},
			{"who": "Callie Briggs", "mood": "alarmed", "caption": "City Hall",
				"text": "SWAT Kats, come in! They're heading for City Hall and the Enforcers can't hold them. Please, we need you!"},
			{"who": "Razor", "mood": "focused", "caption": "The TurboKat",
				"text": "Hang on, Callie. Hatch is open and the turbines are spooling. We're on our way."},
		],
		"wave1": [
			{"who": "Commander Feral", "mood": "angry", "caption": "Enforcer HQ",
				"text": "SWAT Kats! This is an Enforcer operation. Clear my airspace!"},
			{"who": "Lt. Felina Feral", "mood": "alert", "caption": "Enforcer radar",
				"text": "Uncle, my radar says the Creeplings are peeling off toward City Hall. HQ was bait."},
			{"who": "Ann Gora", "mood": "reporting", "caption": "Good Kat Blimp",
				"text": "Ann Gora here, and yes, that Creepling clipped my blimp. I'm fine! Keep rolling!"},
			{"who": "Razor", "mood": "focused", "caption": "The TurboKat",
				"text": "HQ first, then City Hall. He's taking the city's head off, piece by piece. And we've got bombers on radar."},
		],
		"wave2": [
			{"who": "Dark Kat", "mood": "sneer", "caption": "Every channel in Megakat City",
				"text": "Citizens of Megakat City, tonight your Enforcers fall. My Fear Ship II rises, and by dawn this will be Dark Kat City!"},
			{"who": "Callie Briggs", "mood": "alarmed", "caption": "City Hall",
				"text": "He's hijacked every channel. SWAT Kats, that bomb bay is aimed at the Enforcer building!"},
			{"who": "Ann Gora", "mood": "reporting", "caption": "Good Kat Blimp",
				"text": "The broadcast is hijacked, folks, but my camera sees it: something enormous, rising out of the clouds over the bay."},
			{"who": "Razor", "mood": "focused", "caption": "The TurboKat",
				"text": "That's not a ship. That's a flying fortress."},
		],
		"epilogue": [
			{"who": "Dark Kat", "mood": "angry", "caption": "Escape pod",
				"text": "This isn't over, SWAT Kats! You'll pay for this!"},
			{"who": "Commander Feral", "mood": "stern", "caption": "Enforcer HQ roof",
				"text": "Hmph. The SWAT Kats are still under investigation."},
			{"who": "Lt. Felina Feral", "mood": "alert", "caption": "Enforcer HQ roof",
				"text": "Of course they are, Uncle."},
			{"who": "Mayor Manx", "mood": "smug", "caption": "City Hall steps",
				"text": "Well! That went splendidly. I always said it would."},
			{"who": "Ann Gora", "mood": "reporting", "caption": "Good Kat Blimp",
				"text": "Megakat City is damaged but standing. Who saved us? Two pilots nobody can name."},
			{"who": "Callie Briggs", "mood": "calm", "caption": "City Hall",
				"text": "Megakat City owes you again, guys. Thank you."},
		],
	}


func intro() -> Array:
	return strips()["intro"]


func start() -> void:
	var hq: Vector3 = main.city.enforcer_hq_pos
	spawn_wave(hq + Vector3(0, 280, 0), 6)
	radio("Razor", "Enforcer HQ is %.0f klicks out across the city. Light the afterburner, Shift, and keep it low over the rooftops." % (main.player.global_position.distance_to(hq) / 1000.0), 5.5)
	radio("Razor", "Weapons hot. Keep 'em in the reticle for a lock, then send a missile. And if you're dry, dive for the supply beacons.", 5.0)
	# The trip across the city is long: a little company on the radio.
	after(9.0, func(): radio("T-Bone", "Never gets old, that skyline. The MegaKat Tower, all 300 floors of it.", 4.5, "grin"))
	after(20.0, func(): radio("Callie Briggs", "Enforcer HQ is taking a beating! How far out are you, guys?", 4.5, "alarmed"))


func objective() -> String:
	match phase:
		Phase.WAVE_1:
			return "PART 1/3: DESTROY THE CREEPLINGS (%d LEFT)%s" % [enemies_alive(), far_note()]
		Phase.WAVE_2:
			return "PART 2/3: DEFEND CITY HALL (%d LEFT)%s" % [enemies_alive(), far_note()]
		Phase.BOSS:
			if boss and boss.phase == 0:
				var n := 0
				for t in boss.turrets:
					if t.alive:
						n += 1
				return "PART 3/3: FEAR SHIP II: DESTROY THE FLAK TURRETS (%d LEFT)" % n
			return "PART 3/3: FEAR SHIP II: DESTROY THE HULL"
	return "DARK KAT IS ESCAPING..."


func update(_dt: float) -> void:
	if phase == Phase.WAVE_1 and not _spotted and far_note() == "" and enemies_alive() > 0:
		# Close enough to see it: the Creeplings aren't really attacking HQ, they're pulling the
		# Enforcer jets off it.
		_spotted = true
		radio("Razor", "Wait. They're not hitting HQ, they're dragging the Enforcer jets away from it. Why?", 4.5)
		radio("T-Bone", "Ask 'em after we pop a few.", 3.0, "grin")
	if _advancing:
		return
	match phase:
		Phase.WAVE_1:
			if enemies_alive() == 0:
				_advancing = true
				message("WAVE CLEARED")
				after(1.5, func(): cutscene(strips()["wave1"], _start_wave_2))
		Phase.WAVE_2:
			if enemies_alive() == 0:
				_advancing = true
				message("WAVE CLEARED")
				after(1.5, func(): cutscene(strips()["wave2"], _start_boss))


func _start_wave_2() -> void:
	var center: Vector3 = main.city.city_hall_pos + Vector3(0, 260, 0)
	spawn_wave(center, 8, 2)
	radio("T-Bone", "Bombers are slow, but they hit hard. Missiles, buddy!", 4.0, "grin")
	# Callie stays at City Hall to run the evacuation; the Mayor does not.
	after(6.0, func(): radio("Callie Briggs", "Everyone's out of City Hall except me and the Mayor. ...The Mayor is under his desk.", 5.0, "alarmed"))
	after(15.0, func(): radio("Mayor Manx", "Is it over? Somebody tell me it's over!", 3.5, "nervous"))
	phase = Phase.WAVE_2
	_advancing = false


func _start_boss() -> void:
	phase = Phase.BOSS
	var ship := DarkKatWarship.new()
	ship.center = main.city.enforcer_hq_pos # the Fear Ship II circles Enforcer HQ
	boss = main.spawn_boss(ship)
	boss.spawn_glider = func(pos: Vector3): main.spawn_creepling(pos, false, pos)
	boss.phase_changed.connect(_on_boss_phase)
	boss.destroyed.connect(_on_boss_destroyed)
	main.hud.message("WARNING: LARGE CONTACT", 3.0)
	Sfx.play("alarm", -6.0)
	radio("Razor", "The hull's armored. Take out the three flak turrets first!", 4.0)
	radio("Lt. Felina Feral", "I'll draw their fire. Go for the turrets, SWAT Kats!", 4.0, "alert")


func _on_boss_phase(_p: int) -> void:
	message("ARMOR DOWN")
	radio("Razor", "Turrets are scrap and the hull's exposed! Hit it with the Mega-Missile, R!", 4.5)
	radio("Dark Kat", "Launch the gliders! All of them!", 3.0, "angry")


func _on_boss_destroyed() -> void:
	phase = Phase.OUTRO
	main.slow_motion(1.6)
	message("FEAR SHIP II DESTROYED", 3.5)
	radio("T-Bone", "Bill it to the salvage yard, creep.", 3.0, "grin")
	after(4.5, func(): cutscene(strips()["epilogue"], win))
