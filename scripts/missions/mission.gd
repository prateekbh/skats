class_name Mission
extends RefCounted
## Base class for an episode. Override start(), update(dt) and objective().
## `main` gives access to combat, player, city and the HUD.

var main: Node
var time := 0.0
var finished := false
var _timers: Array[Dictionary] = []


func start() -> void:
	pass


## Whether supply caches are guarded by ground flak nests in this episode.
func ground_guards() -> bool:
	return true


## The opening story, played as comic-strip panels after the episode is chosen and before the
## hatch launch (see ComicStrip). Empty for episodes without one.
func intro() -> Array:
	return []


func update(_dt: float) -> void:
	pass


func objective() -> String:
	return ""


## Player start position and the point the jet faces at launch.
func start_pose() -> Array:
	var yard: Vector3 = main.city.salvage_yard_pos
	return [yard + Vector3(40, 150, 0), yard + main.city.launch_dir * 600.0 + Vector3(0, 220, 0)]


func step(dt: float) -> void:
	time += dt
	for i in range(_timers.size() - 1, -1, -1):
		_timers[i].t -= dt
		if _timers[i].t <= 0.0:
			var cb: Callable = _timers[i].cb
			_timers.remove_at(i)
			cb.call()
	if not finished:
		update(dt)


func after(seconds: float, cb: Callable) -> void:
	_timers.append({"t": seconds, "cb": cb})


## A radio line on the HUD's comic card; `mood` picks the speaker's expression
## (assets/ui/portraits/<character>_<mood>.png, see Comic.SPEAKERS).
func radio(who: String, text: String, seconds := 4.5, mood := "") -> void:
	main.hud.radio(who, text, seconds, mood)


## A comic-strip cutscene (game paused), then `then`. Panels: see ComicStrip.
func cutscene(panels: Array, then: Callable) -> void:
	if finished: # the player went down while the scene was waiting to start
		return
	main.show_comic(panels, then)


func message(text: String, seconds := 2.5) -> void:
	main.hud.message(text, seconds)


func win() -> void:
	if not finished:
		finished = true
		main.end_mission(true, "")


func fail(reason: String) -> void:
	if not finished:
		finished = true
		main.end_mission(false, reason)


## " · 4.2 KM" while the nearest enemy is more than a kilometre away, else nothing.
func far_note() -> String:
	var near := INF
	for t in main.combat.targets:
		if is_instance_valid(t) and t.alive and (t is Creepling):
			near = minf(near, t.global_position.distance_to(main.player.global_position))
	return "  ·  %.1f KM" % (near / 1000.0) if near > 1000.0 and near < INF else ""


func enemies_alive() -> int:
	return main.combat.living_count("Creepling Glider") + main.combat.living_count("Creepling Bomber")


## Spawns `count` Creeplings in a loose formation around `center`.
func spawn_wave(center: Vector3, gliders: int, bombers := 0) -> void:
	for k in gliders + bombers:
		var a := TAU * k / float(gliders + bombers) + randf_range(-0.2, 0.2)
		var r := randf_range(120.0, 320.0)
		var pos := center + Vector3(cos(a) * r, randf_range(-60.0, 80.0), sin(a) * r)
		pos.y = maxf(pos.y, main.city.height_at(pos.x, pos.z) + 60.0)
		main.spawn_creepling(pos, k >= gliders, center)
