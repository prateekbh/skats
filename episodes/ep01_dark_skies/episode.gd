extends RefCounted
## Episode 1: menu card and briefing. The mission itself is mission.gd; everything in this
## folder (the boss, its shield shader) belongs to this episode only.


func info() -> Dictionary:
	return {
		"id": "ep01",
		"number": "Episode 1",
		"title": "Dark Skies Over Megakat",
		"villain": "Dark Kat",
		"playable": true,
		"story": "Dusk over Megakat City. Dark Kat has unleashed a swarm of Creepling gliders on downtown, and the Enforcers are getting shredded. Callie Briggs has hit the emergency line to the salvage yard.\n\nRazor and T-Bone scramble the TurboKat.",
		"objectives": ["Destroy two waves of Creepling gliders", "Face Dark Kat's shielded jet: two missiles to learn why, two Scramblers to break it"],
	}
