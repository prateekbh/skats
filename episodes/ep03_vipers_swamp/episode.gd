extends RefCounted
## Episode 3 (coming soon): a menu card only. To build it, add mission.gd next to this file.


func info() -> Dictionary:
	return {
		"id": "ep03",
		"number": "Episode 3",
		"title": "Viper's Swamp",
		"villain": "Dr. Viper",
		"playable": false,
		"story": "Mutant vines are tearing through downtown, and Dr. Viper is laughing from the sewers.",
		"objectives": ["Coming in v0.3"],
	}
