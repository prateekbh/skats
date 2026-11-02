extends Mission
## Episode 1: Dark Skies Over Megakat, in three parts.
##
##   Prologue  (strip, after the episode is chosen)  a news flash, HQ under attack, Callie's call
##   Part 1    First Strike     Creeplings over Enforcer HQ; it was bait
##   Part 2    Breaking News    gliders and bombers over City Hall; Dark Kat takes over the airwaves
##   Part 3    Dark Kat City    Dark Kat's own jet, inside an energy shield; the Enforcer building is the target
##   Epilogue  (strip)          the aftermath
##
## Dark Kat is cutting the city's head off piece by piece: HQ, then City Hall, then HQ again with
## the bomb. All dialogue is original fan writing.
##
## The boss fight: the jet's shield shrugs off two missile hits, a cutscene arms the Scrambler
## Missiles (locked until then, and then the default selection) with exactly two shots. Both
## missing is game over; one hit drops the shield and the jet takes damage from everything.

enum Phase { WAVE_1, WAVE_2, BOSS_SHIELD, BOSS_SCRAMBLE, BOSS_OPEN, OUTRO }

var phase := Phase.WAVE_1
var boss: DarkKatJet
var _scramblers_fired := 0
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
				"text": "Citizens of Megakat City, tonight your Enforcers fall. I'm coming for them myself, and by dawn this will be Dark Kat City!"},
			{"who": "Callie Briggs", "mood": "alarmed", "caption": "City Hall",
				"text": "He's hijacked every channel. SWAT Kats, he's carrying the bomb himself, and it's meant for the Enforcer building!"},
			{"who": "Ann Gora", "mood": "reporting", "caption": "Good Kat Blimp",
				"text": "The broadcast is hijacked, folks, but my camera sees it: one purple jet, screaming in out of the clouds over the bay."},
			{"who": "Razor", "mood": "focused", "caption": "The TurboKat",
				"text": "That's Dark Kat's own fighter. And my scanner says it's wrapped in some kind of energy field."},
		],
		"shield": [
			{"who": "T-Bone", "mood": "grin", "caption": "The TurboKat",
				"text": "Two direct hits and not a scratch! What is that thing made of?"},
			{"who": "Razor", "mood": "focused", "caption": "The TurboKat",
				"text": "It's not the armor, buddy, it's the field around it. A shield generator. Our missiles are just bouncing off."},
			{"who": "Razor", "mood": "focused", "caption": "The TurboKat",
				"text": "A million megavolts will short it out. I'm arming the Scrambler Missiles. But I've only got two."},
			{"who": "T-Bone", "mood": "grin", "caption": "The TurboKat",
				"text": "Two shots. No pressure. Lock him up and make 'em count!"},
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


## Episode 1 is planes only: no surface-to-air guns (the warship's own turrets aside).
func ground_guards() -> bool:
	return false


func intro() -> Array:
	return strips()["intro"]


func start() -> void:
	if main._opts.has("boss"):
		_start_boss() # --boss: jump to the final fight (testing)
		var hq: Vector3 = main.city.enforcer_hq_pos + Vector3(0, 450, 0)
		main.player.global_position = hq + Vector3(-700, 0, 0)
		main.player.look_at(hq, Vector3.UP)
		return
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
		Phase.BOSS_SHIELD:
			return "PART 3/3: DARK KAT'S JET: HIT IT WITH MISSILES (%d/%d)" % [boss.proof_hits if boss else 0, DarkKatJet.PROOF_HITS]
		Phase.BOSS_SCRAMBLE:
			return "PART 3/3: SCRAMBLE THE SHIELD: %d SHOTS LEFT" % maxi(0, 2 - _scramblers_fired)
		Phase.BOSS_OPEN:
			return "PART 3/3: SHIELD DOWN: DESTROY THE JET"
	return "DARK KAT IS ESCAPING..."


func update(_dt: float) -> void:
	if phase == Phase.BOSS_SCRAMBLE and _scramblers_fired >= 2 and boss and boss.shield_up and not _scrambler_in_flight():
		fail("Both Scrambler Missiles missed. The shield held and Dark Kat got away.")
		return
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
				milestone("wave_1_cleared")
				after(1.5, func(): cutscene(strips()["wave1"], _start_wave_2, "wave1"))
		Phase.WAVE_2:
			if enemies_alive() == 0:
				_advancing = true
				message("WAVE CLEARED")
				milestone("wave_2_cleared")
				after(1.5, func(): cutscene(strips()["wave2"], _start_boss, "wave2"))


func _start_wave_2() -> void:
	var center: Vector3 = main.city.city_hall_pos + Vector3(0, 520, 0)
	spawn_wave(center, 8, 2)
	radio("T-Bone", "Bombers are slow, but they hit hard. Missiles, buddy!", 4.0, "grin")
	# Callie stays at City Hall to run the evacuation; the Mayor does not.
	after(6.0, func(): radio("Callie Briggs", "Everyone's out of City Hall except me and the Mayor. ...The Mayor is under his desk.", 5.0, "alarmed"))
	after(15.0, func(): radio("Mayor Manx", "Is it over? Somebody tell me it's over!", 3.5, "nervous"))
	phase = Phase.WAVE_2
	_advancing = false


func _scrambler_in_flight() -> bool:
	for m in main.combat._missiles:
		if m.def.id == "scrambler":
			return true
	return false


func _start_boss() -> void:
	phase = Phase.BOSS_SHIELD
	milestone("boss_started")
	main.player.lock_special("scrambler", true) # not before the cutscene
	var jet := DarkKatJet.new()
	jet.anchor = main.city.enforcer_hq_pos + Vector3(0, 450, 0)
	boss = main.spawn_boss(jet)
	boss.shield_proven.connect(_on_shield_proven)
	boss.shield_broken.connect(_on_shield_broken)
	boss.died.connect(_on_boss_destroyed)
	main.player.special_fired.connect(_on_special_fired)
	main.hud.message("WARNING: HOSTILE FIGHTER", 3.0)
	Sfx.play("alarm", -6.0)
	radio("Razor", "Single bogey, big and fast. Missiles, buddy. Make it count!", 4.0)
	radio("Dark Kat", "Burn, SWAT Kats! My laser cannons will melt your little jet!", 3.5, "angry")


func _on_special_fired(_missiles: Array, def: Dictionary) -> void:
	if def.id == "scrambler":
		_scramblers_fired += 1


func _on_shield_proven() -> void:
	if phase != Phase.BOSS_SHIELD:
		return
	phase = Phase.BOSS_SCRAMBLE
	milestone("shield_proven")
	after(0.9, func(): cutscene(strips()["shield"], _arm_scramblers, "shield"))


func _arm_scramblers() -> void:
	boss.scramble_ready = true
	milestone("scramblers_armed")
	main.player.unlock_and_select("scrambler", 2)
	message("SCRAMBLER MISSILES ARMED: 2 SHOTS", 3.5)
	Sfx.play("beep", -4.0, 1.2)
	radio("Razor", "Scramblers are hot, and they're your default now. Lock on, then fire with R!", 4.5)


func _on_shield_broken() -> void:
	if phase != Phase.BOSS_SCRAMBLE:
		return
	phase = Phase.BOSS_OPEN
	milestone("shield_down")
	main.slow_motion(0.8)
	message("SHIELD DOWN", 3.0)
	radio("Razor", "Shield's fried! Everything we've got works on him now. Hit him!", 4.0)
	radio("Dark Kat", "Impossible! You'll pay for that, SWAT Kats!", 3.5, "angry")


func _on_boss_destroyed(_t: Target) -> void:
	phase = Phase.OUTRO
	milestone("boss_destroyed")
	main.slow_motion(1.6)
	message("DARK KAT'S JET DESTROYED", 3.5)
	radio("T-Bone", "Bill it to the salvage yard, creep.", 3.0, "grin")
	after(4.5, func(): cutscene(strips()["epilogue"], win, "epilogue"))
