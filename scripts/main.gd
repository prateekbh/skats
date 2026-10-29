extends Node
## Builds the world and runs the game state machine: TITLE → PLAYING ⇄ PAUSED → DEBRIEF.
##
## Command-line options (after `--`), used for automated testing:
##   --autotest            start Episode 1 with an autopilot that fights and prints status
##   --episode=<id>        episode to autotest (default ep01)
##   --seconds=<n>         quit the autotest after n seconds (default 150)
##   --shots=<dir>         save screenshots to <dir> during the autotest (needs a display)
##   --god                 invulnerable player with perfect aim (tests mission logic, not skill)
##   --snap=<file.png>     save a screenshot of the title screen after 4 s, then quit
##   --showcase=<dir>      photograph the TurboKat from several angles into <dir>, then quit

enum State { TITLE, PLAYING, PAUSED, DEBRIEF }

const HUD := preload("res://scripts/ui/hud.gd")
const Menu := preload("res://scripts/ui/menu.gd")

var state := State.TITLE
var world: Node3D
var city: City
var combat: Combat
var player: TurboKat
var camera: ChaseCamera
var hud: Control
var menu: Control
var mission: Mission
var episode: Dictionary

var _end_timer := -1.0
var _end_win := false
var _end_reason := ""
var _intro_t := 0.0
var _slowmo_until := 0

var _opts := {}
var _autotest := false
var _test_t := 0.0
var _report_t := 0.0
var _shot_times := [3.0, 9.0, 20.0, 45.0, 80.0]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	_autotest = _opts.has("autotest")
	_build_world()
	_build_ui()
	if _opts.has("showcase"):
		_showcase.call_deferred()
	elif _autotest:
		start_episode(Game.episode_by_id(_opts.get("episode", "ep01")))
	else:
		_show_title()


# --- world ------------------------------------------------------------------------

func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.09, 0.09, 0.26)
	sky_mat.sky_horizon_color = Color(0.98, 0.52, 0.4)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.55, 0.32, 0.34)
	sky_mat.ground_bottom_color = Color(0.07, 0.05, 0.09)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.38, 0.42)
	env.fog_density = 0.00028
	env.fog_sky_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	# Low dusk sun over the western mountains.
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.76, 0.56)
	sun.light_energy = 1.15
	sun.rotation_degrees = Vector3(-16, -105, 0)
	world.add_child(sun)

	city = City.new()
	world.add_child(city)
	combat = Combat.new()
	combat.city = city
	world.add_child(combat)
	player = TurboKat.new()
	player.combat = combat
	player.city = city
	world.add_child(player)
	player.destroyed.connect(_on_player_destroyed)
	camera = ChaseCamera.new()
	camera.target = player
	world.add_child(camera)
	camera.current = true
	combat.player = player
	combat.camera = camera
	combat.target_killed.connect(_on_target_killed)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD.new()
	hud.main = self
	hud.process_mode = Node.PROCESS_MODE_PAUSABLE
	hud.visible = false
	layer.add_child(hud)
	combat.on_message = func(t: String): hud.message(t, 2.0)
	menu = Menu.new()
	layer.add_child(menu)
	menu.launch.connect(start_episode)
	menu.resume.connect(_resume)
	menu.restart.connect(func(): start_episode(episode))
	menu.quit_to_title.connect(_show_title)


func spawn_creepling(pos: Vector3, heavy: bool, anchor: Vector3) -> Creepling:
	var c := Creepling.new()
	combat.add_target(c)
	c.setup(pos, heavy, anchor)
	return c


func spawn_boss(boss: Node3D) -> Node3D:
	boss.add_to_group("mission_spawn")
	combat.add_child(boss)
	boss.setup(combat)
	return boss


func _clear_world() -> void:
	combat.clear()
	for n in get_tree().get_nodes_in_group("mission_spawn"):
		n.queue_free()


func slow_motion(real_seconds: float) -> void:
	Engine.time_scale = 0.35
	_slowmo_until = Time.get_ticks_msec() + int(real_seconds * 1000.0)


# --- state flow -------------------------------------------------------------------

func _show_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_world()
	mission = null
	hud.visible = false
	player.reset(Vector3(900, 320, 0), Vector3(900, 320, -100))
	player.player_control = false
	camera.shot = "orbit"
	menu.show_title()


func start_episode(ep: Dictionary) -> void:
	if ep.is_empty() or not ep.playable:
		return
	episode = ep
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_world()
	mission = load(ep.script).new()
	mission.main = self
	var pose: Array = mission.start_pose()
	player.reset(pose[0], pose[1])
	player.player_control = false
	player.ai = {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "throttle": 0.6, "fire": false, "missile": false}
	camera.shot = "intro"
	camera.shot_time = 0.0
	camera.mode = ChaseCamera.Mode.CHASE
	_intro_t = 3.2
	_end_timer = -1.0
	hud.reset()
	hud.visible = true
	menu.hide_all()
	hud.message("%s: %s" % [ep.number.to_upper(), ep.title.to_upper()], 3.2)
	state = State.PLAYING
	mission.start()


func end_mission(win: bool, reason: String) -> void:
	if _end_timer >= 0.0:
		return
	_end_win = win
	_end_reason = reason
	_end_timer = 2.5 if win else 3.0


func _on_player_destroyed() -> void:
	if mission and state == State.PLAYING:
		mission.fail("The TurboKat went down over Megakat City.")


func _on_target_killed(t: Target) -> void:
	if t is Creepling:
		combat.explode(t.global_position, 2.0 if t.heavy else 1.1)
		var r := randf()
		if r < (0.45 if t.heavy else 0.1):
			combat.drop_pickup(t.global_position, "repair")
		elif r < (0.7 if t.heavy else 0.16):
			combat.drop_pickup(t.global_position, "ammo")
		t.queue_free()


func _show_debrief() -> void:
	var s := combat.stats
	var accuracy := int(100.0 * s.hits / s.shots) if s.shots > 0 else 0
	var bonus := 0
	if _end_win:
		bonus = int(player.hp * 20.0) + maxi(0, int(600.0 - mission.time)) * 5 + accuracy * 20
	var score: int = s.score + bonus
	var rank := "C"
	if episode.id == "free":
		var w: int = mission.wave
		rank = "S" if w >= 10 else ("A" if w >= 7 else ("B" if w >= 4 else "C"))
	elif _end_win:
		rank = "S" if score >= 16000 else ("A" if score >= 12000 else ("B" if score >= 8000 else "C"))
	else:
		rank = "—"
	var new_best := Game.record_score(episode.id, score)
	state = State.DEBRIEF
	hud.visible = false
	Engine.time_scale = 1.0
	var data := {
		"win": _end_win, "reason": _end_reason, "episode": episode, "score": score,
		"kills": s.kills, "accuracy": accuracy, "time": mission.time, "hull": int(player.hp),
		"bonus": bonus, "rank": rank, "new_best": new_best,
	}
	if _autotest:
		print("[autotest] DEBRIEF win=%s score=%d kills=%d accuracy=%d%% time=%ds rank=%s" % [_end_win, score, s.kills, accuracy, int(mission.time), rank])
		get_tree().quit(0 if _end_win else 2)
		return
	menu.show_debrief(data)
	if player.alive:
		player.player_control = false
		camera.shot = "orbit"
		camera.shot_time = 0.0


func _pause() -> void:
	state = State.PAUSED
	get_tree().paused = true
	Sfx.set_engine(false, 0, 0)
	menu.show_pause()


func _resume() -> void:
	state = State.PLAYING
	menu.hide_all()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if state == State.PLAYING:
			_pause()
		elif state == State.PAUSED:
			_resume()
	elif event.is_action_pressed("camera_cycle") and state == State.PLAYING:
		camera.cycle_mode()
	elif event.is_action_pressed("toggle_mute"):
		Game.set_muted(not Game.muted)
		hud.message("SOUND OFF" if Game.muted else "SOUND ON", 1.2)
	elif event.is_action_pressed("toggle_invert") and state == State.PLAYING:
		Game.toggle_invert()
		hud.message("PITCH INVERTED" if Game.invert_pitch else "PITCH NORMAL", 1.5)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING and not _autotest:
		_pause()


func _process(delta: float) -> void:
	if _slowmo_until > 0 and Time.get_ticks_msec() > _slowmo_until:
		_slowmo_until = 0
		Engine.time_scale = 1.0

	match state:
		State.TITLE, State.DEBRIEF:
			if player.alive and not player.player_control:
				_cruise()
			Sfx.set_engine(false, 0, 0)
		State.PLAYING:
			if _intro_t > 0.0:
				_intro_t -= delta
				if _intro_t <= 0.0:
					player.player_control = not _autotest
					camera.shot = ""
			if _autotest and _intro_t <= 0.0:
				_autopilot_fight()
			mission.step(delta)
			Sfx.set_engine(player.alive, player.throttle, 1.0 if player.boosting else 0.0)
			if _end_timer >= 0.0:
				_end_timer -= delta
				if _end_timer < 0.0:
					_show_debrief()
	if _autotest:
		_autotest_step(delta)
	elif _opts.has("snap"):
		# --snap=<file.png> saves one frame after 4 seconds (e.g. the title screen), then quits.
		_test_t += delta
		if _test_t > 4.0:
			get_viewport().get_texture().get_image().save_png(_opts.snap)
			get_tree().quit()


func _showcase() -> void:
	_show_title()
	menu.hide_all()
	set_process(false)
	player.set_process(false)
	player.global_position = Vector3(0, 600, 0)
	player.global_transform.basis = Basis()
	player.throttle = 0.6
	player._effects(0.016)
	var views := {
		"rear_left": "-16,7,24", "front_right": "14,5,-22", "top": "0.1,30,2",
		"side": "-30,2,0", "rear_low": "8,-4,26", "front_low": "-10,-2,-20",
	}
	views["swept_top"] = "0.1,30,2"
	views["swept_rear_left"] = "-16,7,24"
	for v_name in views:
		if v_name.begins_with("swept"):
			player.speed = 300.0 # past the wing-sweep threshold
			player._effects(0.016)
		camera.shot = "view:" + views[v_name]
		for i in 3:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [_opts.showcase, v_name])
		print("[showcase] ", v_name)
	get_tree().quit()


# --- autopilot (title screen flyby and automated tests) -----------------------------

## Flies a wide lazy circle over downtown for the title screen.
func _cruise() -> void:
	var p := player.global_position
	var a := atan2(p.z, p.x) + 0.35
	_steer_to(Vector3(cos(a) * 900.0, 320.0, sin(a) * 900.0))
	player.ai.fire = false
	player.ai.throttle = 0.45


func _steer_to(point: Vector3) -> Vector3:
	var to := (point - player.global_position).normalized()
	var local := player.global_transform.basis.inverse() * to
	var pitch: float
	var roll: float
	if local.z < -0.92:
		# Nearly on the nose: fine-aim with pitch and rudder, keep the wings steady.
		pitch = clampf(local.y * 5.0, -1.0, 1.0)
		roll = clampf(local.x * 2.0, -0.4, 0.4)
	else:
		# Roll until the target is "overhead" in the canopy, then pull toward it.
		var roll_err := atan2(local.x, local.y)
		roll = clampf(roll_err * 1.5, -1.0, 1.0)
		pitch = 1.0 if absf(roll_err) < 0.6 else 0.25
	var ahead := player.global_position + player.velocity * 2.5
	if ahead.y < city.height_at(ahead.x, ahead.z) + 70.0 or player.global_position.y < 90.0:
		pitch = 1.0
		roll = clampf(-player.global_transform.basis.x.y * 4.0, -1.0, 1.0)
	player.ai.pitch = pitch
	player.ai.roll = roll
	player.ai.yaw = clampf(local.x * 3.0, -1.0, 1.0)
	return local


func _autopilot_fight() -> void:
	var best: Target = null
	var best_d := INF
	for t in combat.targets:
		if t.alive and t.is_visible_in_tree():
			var d := t.global_position.distance_to(player.global_position)
			if t.invulnerable:
				d *= 3.0
			if d < best_d:
				best_d = d
				best = t
	if best == null:
		_cruise()
		return
	var local := _steer_to(best.global_position + best.velocity * clampf(best_d / 1200.0, 0.0, 1.0))
	player.ai.throttle = 0.85 if best_d > 300.0 else 0.6
	player.ai.fire = local.z < -0.97 and best_d < 900.0
	if _opts.has("god"):
		player.god_mode = true
		player.grant_invulnerability(1.0)
		player.ai.erase("aim")
		if best_d < 900.0 and local.z < -0.3:
			var muzzle_t := best_d / (1150.0 + player.speed)
			player.ai.aim = (best.global_position + best.velocity * muzzle_t - player.global_position).normalized()
			player.ai.fire = true
	player.ai.missile = player.locked and randf() < 0.02


func _autotest_step(delta: float) -> void:
	_test_t += delta / maxf(Engine.time_scale, 0.01)
	_report_t -= delta
	if _report_t <= 0.0 and mission:
		_report_t = 3.0
		var near_d := INF
		var near_y := 0.0
		for t in combat.targets:
			if t.alive and t.global_position.distance_to(player.global_position) < near_d:
				near_d = t.global_position.distance_to(player.global_position)
				near_y = t.global_position.y
		print("[autotest] t=%5.1f fps=%3d hp=%3d score=%5d kills=%2d targets=%2d alt=%4d spd=%3d nearest=%5dm@%4d obj=%s" % [
			_test_t, Engine.get_frames_per_second(), int(player.hp), combat.stats.score, combat.stats.kills,
			combat.living_count(), player.global_position.y, player.speed, mini(int(near_d), 99999), near_y, mission.objective()])
	if _opts.has("shots") and not _shot_times.is_empty() and _test_t >= _shot_times[0]:
		var at: float = _shot_times.pop_front()
		var tex := get_viewport().get_texture()
		if tex:
			var img := tex.get_image()
			if img:
				var path := "%s/shot_%03d.png" % [_opts.shots, int(at)]
				img.save_png(path)
				print("[autotest] saved ", path)
	if _test_t >= float(_opts.get("seconds", "150")):
		print("[autotest] time limit reached")
		get_tree().quit(1)
