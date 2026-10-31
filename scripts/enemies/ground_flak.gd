class_name GroundFlak
extends Target
## A flak nest guarding a supply cache: tracks the TurboKat and fires bursts while it is low and
## close, so grabbing the cache costs some hull. Destroying it is worth points.

var barrel: Node3D
var _cd := 2.0
var _burst := 0
var _burst_t := 0.0


func setup(c: Combat) -> void:
	combat = c
	display_name = "Flak Nest"
	set_max_hp(140.0)
	radius = 9.0
	score = 250
	var base_mat := flashable(MeshKit.toon(Color(0.4, 0.38, 0.34), 0.5, 0.5))
	MeshKit.part(self, MeshKit.cyl(7.0, 8.5, 5.0, 12), base_mat, Vector3(0, 2.5, 0))
	MeshKit.part(self, MeshKit.sphere(1.8, 8), MeshKit.glow(Color(1, 0.25, 0.1)), Vector3(0, 6.0, 0))
	barrel = Node3D.new()
	add_child(barrel)
	barrel.position = Vector3(0, 6.0, 0)
	MeshKit.part(barrel, MeshKit.cyl(0.9, 0.9, 12.0, 8), base_mat, Vector3(1.6, 0, -6), Vector3(-PI / 2, 0, 0))
	MeshKit.part(barrel, MeshKit.cyl(0.9, 0.9, 12.0, 8), base_mat, Vector3(-1.6, 0, -6), Vector3(-PI / 2, 0, 0))
	died.connect(func(_t):
		combat.explode(global_position + Vector3(0, 4, 0), 1.6)
		queue_free())


func tick(dt: float) -> void:
	var player := combat.player
	velocity = Vector3.ZERO
	if not player.alive:
		return
	var to := player.global_position - global_position
	var dist := to.length()
	if dist > 1.0:
		Combat.safe_look(barrel, to)
	_cd -= dt
	if dist < 700.0 and player.global_position.y - global_position.y < 260.0 and _cd <= 0.0:
		_cd = randf_range(1.6, 2.4)
		_burst = 4
	if _burst > 0:
		_burst_t -= dt
		if _burst_t <= 0.0:
			_burst_t = 0.12
			_burst -= 1
			var lead := player.global_position + player.velocity * (dist / 420.0)
			var dir := ((lead - global_position).normalized() + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.04).normalized()
			combat.fire_bullet(global_position + Vector3(0, 6, 0) + dir * 8.0, dir * 420.0, Combat.ENEMY_TEAM, 7.0, 2.6, 2.0)
