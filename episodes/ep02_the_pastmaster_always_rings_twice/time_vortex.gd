class_name TimeVortex
extends Node3D
## The Pastmaster's time vortex: a big swirling disc in the sky with magenta lightning (see
## time_vortex.gdshader). `open_amount` grows it from nothing; `pulse()` flashes it. Pterosaurs spawn
## from its position.

var radius := 260.0
var open_amount := 1.0:
	set(v):
		open_amount = v
		if _mat:
			_mat.set_shader_parameter("open", v)

var _mat: ShaderMaterial
var _flash := 0.0


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.0, radius * 2.0)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://episodes/ep02_the_pastmaster_always_rings_twice/time_vortex.gdshader")
	_mat.set_shader_parameter("open", open_amount)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 2000.0
	add_child(mi)


func pulse() -> void:
	_flash = 1.0


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 2.5)
	if _mat:
		_mat.set_shader_parameter("flash", _flash)
