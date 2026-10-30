extends Node
## Builds the world and runs the game state machine: TITLE → PLAYING ⇄ PAUSED → DEBRIEF.
##
## Command-line options (after `--`), used for automated testing:
##   --autotest            start Episode 1 with an autopilot that fights and prints status
##   --episode=<id>        episode to autotest (default ep01)
##   --seconds=<n>         quit the autotest after n seconds (default 150)
##   --shots=<dir>         save screenshots to <dir> during the autotest (needs a display)
##   --weapons             (with --autotest) fire each special missile at a target and report the result
##   --mcam                (with --autotest) allow the missile-cam cutscene
##   --god                 invulnerable player with perfect aim (tests mission logic, not skill)
##   --snap=<file.png>     save a screenshot of the title screen after 4 s, then quit
##                         (add --intro to capture the launch cinematic, --snap-at=<s> to pick the moment)
##   --fxshow=<dir>        photograph explosions and effects at several moments, then quit
##   --weaponshow=<dir>    photograph the special-missile models and their effects, then quit
##   --showcase=<dir>      photograph the TurboKat from several angles into <dir>, then quit

enum State { INTRO, TITLE, PLAYING, PAUSED, DEBRIEF }

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

# Launch cinematic shown once per session before the title screen.
var _intro_seq := -1.0
var _intro_events := {}


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
	elif _opts.has("fxshow"):
		_fx_showcase.call_deferred()
	elif _opts.has("weaponshow"):
		_weapon_showcase.call_deferred()
	elif _autotest:
		start_episode(Game.episode_by_id(_opts.get("episode", "ep01")))
	elif _opts.has("snap") and not _opts.has("intro"):
		_show_title()
	else:
		_start_intro()


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
	player.special_fired.connect(_on_special_fired)
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
	_end_missile_cam()
	combat.clear()
	city.reset_damage() # the damage stays until the next stage starts
	for n in get_tree().get_nodes_in_group("mission_spawn"):
		n.queue_free()


## A split-second freeze on big kills so impacts land with weight.
func hit_stop(real_seconds: float) -> void:
	Engine.time_scale = 0.05
	get_tree().create_timer(real_seconds, true, false, true).timeout.connect(func():
		if not _mcam.is_empty():
			Engine.time_scale = MCAM_SLOWMO
		else:
			Engine.time_scale = 0.35 if _slowmo_until > Time.get_ticks_msec() else 1.0)


# --- missile cam ----------------------------------------------------------------------

## Launch shot for special missiles: a title card and a short slow-motion beat from beside the
## TurboKat's nose as the missile leaves the rack, then straight back to the game. The camera is
## locked to the jet and kept level (no chasing the missile, which got nauseating).
## Skippable with any fire button.
const MCAM_SLOWMO := 0.3
const MCAM_TIME := 1.1 # unscaled seconds
var _mcam := {}


func _on_special_fired(missiles: Array, def: Dictionary) -> void:
	hud.banner(def)
	if not Game.missile_cam or (_autotest and not _opts.has("mcam")) or not _mcam.is_empty() or missiles.is_empty():
		return
	_mcam = {"t": 0.0}
	camera.shot = "script"
	Engine.time_scale = MCAM_SLOWMO
	player.grant_invulnerability(1.0)


func _missile_cam_step(real_dt: float) -> void:
	_mcam.t = float(_mcam.t) + real_dt
	var elapsed: float = _mcam.t
	var skip := elapsed > 0.3 and (Input.is_action_just_pressed("fire_guns") or Input.is_action_just_pressed("fire_special") or Input.is_action_just_pressed("fire_missile"))
	var tb := player.global_transform.basis
	var fwd := -tb.z
	var right := tb.x
	# Low off the right wing and behind the tail, looking down the flight line: the jet sits on
	# the left of the frame and the missile streaks away from it into the distance.
	camera.global_position = player.global_position - fwd * 24.0 + right * 15.0 + Vector3.UP * 3.0
	camera.look_at(player.global_position + fwd * 70.0, Vector3.UP)
	if skip or elapsed > MCAM_TIME or not player.alive:
		_end_missile_cam()


func _end_missile_cam() -> void:
	if _mcam.is_empty():
		return
	_mcam = {}
	camera.shot = ""
	Engine.time_scale = 0.35 if _slowmo_until > Time.get_ticks_msec() else 1.0


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
	if not _autotest:
		Music.play_theme()


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
	Music.fade_out(2.5)


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
	if t.score >= 300 and not _autotest:
		hit_stop(0.07)
	if t is Creepling:
		if t.cut_pieces > 0:
			combat.cut_apart(t) # Slicer / Buzz-Saw: cut to pieces, no explosion
		else:
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
	Music.play_theme(3.0)
	if player.alive:
		player.player_control = false
		camera.shot = "orbit"
		camera.shot_time = 0.0


func _pause() -> void:
	_end_missile_cam()
	state = State.PAUSED
	get_tree().paused = true
	Sfx.set_engine(false, 0, 0)
	menu.show_pause()


func _resume() -> void:
	state = State.PLAYING
	menu.hide_all()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if state == State.INTRO:
		var pressed := (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton) and event.is_pressed()
		if pressed and _intro_seq > 0.5:
			_finish_intro()
		return
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
		Engine.time_scale = MCAM_SLOWMO if not _mcam.is_empty() else 1.0

	match state:
		State.INTRO:
			_intro_step(delta)
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
			if not _mcam.is_empty():
				_missile_cam_step(delta / maxf(Engine.time_scale, 0.01))
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
		if _test_t > float(_opts.get("snap-at", "4")):
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


# --- launch cinematic -------------------------------------------------------------------

## The TurboKat rises out of the salvage-yard hangar and blasts off over Megakat City.
func _start_intro() -> void:
	state = State.INTRO
	_intro_seq = 0.0
	_intro_events = {}
	_clear_world()
	hud.visible = false
	var yard := city.salvage_yard_pos
	player.reset(yard + Vector3(0, -14, 0), Vector3(0, -14, 0))
	player.set_process(false)
	player.throttle = 0.2
	player.boosting = false
	city.set_hatch(0.0)
	camera.shot = "script"
	menu.show_intro()
	Music.play_theme()


## Launch timing: the hatch snaps open, then the TurboKat bursts out of the underground
## runway already nose-up at speed and keeps climbing, as in the show. No hover.
const INTRO_EMERGE := 1.9 # seconds until the nose clears the hatch
const INTRO_CLIMB_DEG := 32.0 # launch angle out of the tunnel
const INTRO_EXIT_SPEED := 120.0 # m/s at the hatch
const INTRO_ACCEL := 45.0 # m/s² after emerging


func _intro_step(delta: float) -> void:
	_intro_seq += delta
	var t := _intro_seq
	var yard := city.salvage_yard_pos
	var hatch := yard + Vector3(0, 1.5, 0)
	var flat := Vector3(-yard.x, 0, -yard.z).normalized() # toward downtown
	city.set_hatch(smoothstep(0.5, 1.4, t))

	# Distance travelled along the launch path, measured from the hatch (negative = still in the tunnel).
	var dt_e := t - INTRO_EMERGE
	var dist := INTRO_EXIT_SPEED * dt_e + (0.5 * INTRO_ACCEL * dt_e * dt_e if dt_e > 0.0 else 0.0)
	# Climb angle eases from the tunnel's 32° to a 14° cruise climb once clear of the yard.
	var climb := deg_to_rad(lerpf(INTRO_CLIMB_DEG, 14.0, smoothstep(INTRO_EMERGE + 1.2, INTRO_EMERGE + 4.0, t)))
	var dir := (flat * cos(climb) + Vector3.UP * sin(climb)).normalized()
	if dist <= 0.0:
		var tunnel := (flat * cos(deg_to_rad(INTRO_CLIMB_DEG)) + Vector3.UP * sin(deg_to_rad(INTRO_CLIMB_DEG))).normalized()
		player.global_position = hatch + tunnel * dist
		player.look_at(player.global_position + tunnel, Vector3.UP)
	else:
		# Integrate along the (gently flattening) climb so the path stays continuous.
		player.global_position += dir * (INTRO_EXIT_SPEED + INTRO_ACCEL * dt_e) * delta
		player.look_at(player.global_position + dir, Vector3.UP)
	player.visible = dist > -30.0
	player.speed = maxf(INTRO_EXIT_SPEED + INTRO_ACCEL * maxf(dt_e, 0.0), 0.0)
	player.throttle = 1.0
	player.boosting = true

	# No launch sound effects: the intro plays over the theme music alone.
	_intro_once("launch", INTRO_EMERGE - 0.05, func():
		camera.add_shake(1.8)
		combat.vfx.dust(hatch, 1.4))
	_intro_once("logo", INTRO_EMERGE + 2.4, menu.slam_logo)

	# Camera: low on the yard floor watching the hatch, then swinging in behind the climb.
	# The crane stands on the other side of the yard, so the camera sits on this side, above the junk.
	var side := Vector3.UP.cross(flat).normalized()
	var low := hatch - side * 46.0 + flat * 22.0 + Vector3(0, 11, 0)
	var k := smoothstep(INTRO_EMERGE + 0.45, INTRO_EMERGE + 1.8, t)
	var chase := player.global_position - dir * 30.0 + Vector3.UP * 8.0
	camera.global_position = low.lerp(chase, k)
	var target := hatch + Vector3(0, 4, 0) if dist < -10.0 else player.global_position + dir * 25.0 * k
	camera.look_at(target, Vector3.UP)

	player._effects(delta)
	if t > INTRO_EMERGE + 6.0:
		_finish_intro()


func _intro_once(key: String, at: float, cb: Callable) -> void:
	if _intro_seq >= at and not _intro_events.has(key):
		_intro_events[key] = true
		cb.call()


func _finish_intro() -> void:
	if state != State.INTRO:
		return
	_intro_seq = -1.0
	player.set_process(true)
	player.boosting = false
	city.set_hatch(0.0)
	Sfx.set_engine(false, 0, 0)
	_show_title()


## Sets off effects in front of a fixed camera and saves frames at set moments.
func _fx_showcase() -> void:
	_show_title()
	menu.hide_all()
	set_process(false)
	player.set_process(false)
	player.visible = false
	camera.shot = "script"
	var at := Vector3(300, 420, 300)
	camera.global_position = at + Vector3(0, 6, 70)
	camera.look_at(at, Vector3.UP)
	combat.explode(at, 1.6)
	combat.explode(at + Vector3(-34, 4, -10), 0.8)
	for k in 5:
		combat.spark(at + Vector3(28 + k * 3, -8 + k * 2, 8), 1.0)
	var trail_from := at + Vector3(-60, -20, 10)
	for k in 40:
		combat.vfx.trail(trail_from + Vector3(k * 2.5, k * 0.6, 0) * 2.0)
	var moments := [0.06, 0.18, 0.4, 0.8, 1.5]
	var t := 0.0
	for m in moments:
		while t < m:
			await get_tree().process_frame
			t += get_process_delta_time()
		get_viewport().get_texture().get_image().save_png("%s/fx_%03d.png" % [_opts.fxshow, int(m * 100)])
		print("[fxshow] ", m)
	get_tree().quit()


## Lines up every missile model and shows the capture, discharge and burn effects.
func _weapon_showcase() -> void:
	_show_title()
	menu.hide_all()
	set_process(false)
	player.set_process(false)
	player.visible = false
	camera.shot = "script"
	var at := Vector3(300, 420, 300)
	camera.global_position = at + Vector3(0, 3, 16)
	camera.look_at(at + Vector3(0, -1, 0), Vector3.UP)
	var defs: Array = [Arsenal.HOMING] + Arsenal.SPECIALS
	var models: Array[Node3D] = []
	for k in defs.size():
		var m := combat._build_missile(defs[k])
		m.global_position = at + Vector3(0, ((defs.size() - 1) * 0.5 - k) * 1.9, 0)
		m.rotation = Vector3(0, PI / 2 - 0.25, 0) # side-on, nose to the right
		models.append(m)
	camera.global_position = at + Vector3(0, 0, 13)
	camera.look_at(at, Vector3.UP)
	for f in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/missiles.png" % _opts.weaponshow)
	for m in models:
		m.queue_free()
	# Each effect in its own close-up on a Creepling.
	var defs_by_id := {}
	for d in Arsenal.SPECIALS:
		defs_by_id[d.id] = d
	for shot in ["octopus", "scrambler", "matchhead"]:
		var c := spawn_creepling(at, shot == "matchhead", at)
		camera.global_position = at + Vector3(0, 6, 34 if shot != "matchhead" else 48)
		camera.look_at(at, Vector3.UP)
		if shot == "matchhead":
			c.ignite(5.0, 0.5)
		else:
			combat._missile_hit(defs_by_id[shot], at + Vector3(0, 0, 2), c)
		var t := 0.0
		while t < (0.18 if shot == "scrambler" else 0.45):
			await get_tree().process_frame
			t += get_process_delta_time()
			if is_instance_valid(c):
				c.stunned = maxf(c.stunned, 1.0)
				c.global_position = at # hold still for the photo
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_opts.weaponshow, shot])
		combat.clear()
	# Cutting kills: the Slicer's five pieces and the Buzz-Saw's two, just after the cut and later.
	for shot in ["slicer", "buzzsaw"]:
		var c := spawn_creepling(at, false, at)
		c.set_process(false)
		camera.global_position = at + Vector3(0, 6, 22)
		camera.look_at(at + Vector3(0, -2, 0), Vector3.UP)
		combat._missile_hit(defs_by_id[shot], at + Vector3(0, 0, 2), c)
		var t := 0.0
		for snap in [0.15, 0.7]:
			while t < snap:
				await get_tree().process_frame
				t += get_process_delta_time()
			get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [_opts.weaponshow, shot, int(snap * 100)])
		combat.clear()
	# Building damage: two roof hits and a wall hit on a downtown tower, then let the smoke rise.
	var c0 := city.cell_index(200.0, -150.0)
	for i in range(city.N / 2 - 6, city.N / 2 + 6):
		for j in range(city.N / 2 - 6, city.N / 2 + 6):
			var cc := i * city.N + j
			if city._instance[cc] >= 0 and city._tier[cc] < 0 and city._block_h[cc] > city._block_h[c0]:
				c0 = cc
	var bc := Vector3(city._cx[c0], 0.0, city._cz[c0])
	var bh: float = city._block_h[c0]
	combat._missile_hit(Arsenal.HOMING, bc + Vector3(5, bh, 3), null)
	combat._missile_hit(Arsenal.SPECIALS[4], bc + Vector3(-10, bh, -6), null)
	combat._missile_hit(Arsenal.HOMING, bc + Vector3(city._hw[c0], bh * 0.25, 4), null)
	print("[weaponshow] building h=%.0f -> %.0f" % [bh, city._block_h[c0]])
	camera.global_position = bc + Vector3(95, bh + 25, 75)
	camera.look_at(bc + Vector3(0, bh * 0.45, 0), Vector3.UP)
	var bt := 0.0
	while bt < 0.8:
		await get_tree().process_frame
		bt += get_process_delta_time()
	get_viewport().get_texture().get_image().save_png("%s/building_close.png" % _opts.weaponshow)
	camera.global_position = bc + Vector3(110, bh + 170, 150)
	camera.look_at(bc + Vector3(0, bh * 0.55, 0), Vector3.UP)
	while bt < 9.0:
		await get_tree().process_frame
		bt += get_process_delta_time()
	get_viewport().get_texture().get_image().save_png("%s/building.png" % _opts.weaponshow)
	print("[weaponshow] done")
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
	player.ai.fire = local.z < -0.97 and best_d < 900.0 and not _opts.has("weapons")
	if _opts.has("god"):
		player.god_mode = true
		player.grant_invulnerability(1.0)
		player.ai.erase("aim")
		if best_d < 900.0 and local.z < -0.3 and not _opts.has("weapons"):
			var muzzle_t := best_d / (1150.0 + player.speed)
			player.ai.aim = (best.global_position + best.velocity * muzzle_t - player.global_position).normalized()
			player.ai.fire = true
	player.ai.missile = player.locked and randf() < 0.02


var _six_t := 0.0
var _six_streak := 0.0
var _six_max := 0.0


var _weapon_test_t := 0.0
var _weapon_test_i := 0


## --weapons: every few seconds, aim at the nearest live target and fire the next special
## missile at it, then report what happened to it.
func _weapon_test_step(delta: float) -> void:
	_weapon_test_t -= delta
	if _weapon_test_t > 0.0 or state != State.PLAYING or _intro_t > 0.0:
		return
	_weapon_test_t = 3.0
	var best: Target = null
	var best_d := 900.0
	for t in combat.targets:
		var d := t.global_position.distance_to(player.global_position)
		if t.alive and t.visible and d < best_d and d > 80.0:
			best = t
			best_d = d
	if best == null:
		return
	var def: Dictionary = Arsenal.SPECIALS[_weapon_test_i % Arsenal.SPECIALS.size()]
	_weapon_test_i += 1
	player.look_at(best.global_position, Vector3.UP)
	player.special_ammo[def.id] = def.max
	player.special_index = Arsenal.SPECIALS.find(def)
	player.lock_target = best
	player.locked = true
	var hp_before := best.hp
	var tname := best.display_name
	var ref: WeakRef = weakref(best)
	player._fire_special(def)
	if _opts.has("shots"):
		# Photograph the missile cam mid-flight.
		for at in [0.02, 0.18, 0.3]:
			get_tree().create_timer(at).timeout.connect(func():
				var img := get_viewport().get_texture().get_image()
				if img:
					img.save_png("%s/mcam_%s_%d_%.2f.png" % [_opts.shots, def.id, _weapon_test_i, at]))
	get_tree().create_timer(2.0).timeout.connect(func():
		var tgt = ref.get_ref()
		var state_txt: String = "destroyed" if tgt == null or not tgt.alive else "hp %d->%d stunned=%.1f burning=%.1f captured=%s" % [hp_before, tgt.hp, tgt.stunned, tgt.burn_t, tgt.captured]
		print("[weapons] %-18s vs %-16s -> %s" % [def.name, tname, state_txt]))


func _autotest_step(delta: float) -> void:
	_test_t += delta / maxf(Engine.time_scale, 0.01)
	if _opts.has("weapons"):
		_weapon_test_step(delta)
	# Dogfight metric: how long an attacker sits behind the player without a break.
	if state == State.PLAYING and hud._bandit_on_six(player) != null:
		_six_t += delta
		_six_streak += delta
		_six_max = maxf(_six_max, _six_streak)
	else:
		_six_streak = 0.0
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
		print("[autotest] bandit-on-six total %.1fs, longest unbroken %.1fs" % [_six_t, _six_max])
		print("[autotest] time limit reached")
		get_tree().quit(1)
