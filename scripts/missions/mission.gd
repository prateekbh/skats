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


func update(_dt: float) -> void:
	pass


func objective() -> String:
	return ""


## Player start position and the point the jet faces at launch.
func start_pose() -> Array:
	var yard: Vector3 = main.city.salvage_yard_pos
	return [yard + Vector3(40, 150, 0), Vector3(0, 180, 0)]


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


func radio(who: String, text: String, seconds := 4.5) -> void:
	main.hud.radio(who, text, seconds)


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
