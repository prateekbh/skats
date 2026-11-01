extends RefCounted
## Free Flight: endless escalating waves (see mission.gd).


func info() -> Dictionary:
	return {
		"id": "free",
		"number": "Free Flight",
		"title": "Endless Defense",
		"villain": "Everyone",
		"playable": true,
		"story": "No briefing, no Enforcers, no limits. Wave after wave of Creeplings. How long can the TurboKat hold the line?",
		"objectives": ["Survive escalating waves", "Score as high as you can"],
	}
