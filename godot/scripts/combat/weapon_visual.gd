class_name WeaponVisual
extends Node3D
## Danger fan uses Hitbox's action clock. Legacy pivot remains for regression scenes;
## P6 weapons are attached to the imported character's animated socket instead.

@export var active_color: Color = Color(0.25, 0.85, 1.0, 0.36)
@export var warning_color: Color = Color(0.25, 0.85, 1.0, 0.07)
@export_range(0.0, 1.0, 0.05) var effect_strength: float = 0.7
## P7 readability. The warning fan pulses between its configured alpha
## (warning_color.a) and that alpha reduced by this fraction, so the pulse can never
## make the danger zone brighter than the colour the scene already ships.
@export_range(0.0, 0.9, 0.05) var warning_pulse_depth: float = 0.55
## Pulse cycles across one windup. The phase accelerates, so it reads as a countdown.
@export_range(1.0, 8.0, 0.5) var warning_pulse_cycles: float = 3.0
## Peak alpha of the thin reach-edge rim during the windup, and on the damaging frame.
@export_range(0.0, 1.0, 0.05) var rim_warning_alpha: float = 0.85
@export_range(0.0, 1.0, 0.05) var rim_active_alpha: float = 0.95

@onready var pivot: Node3D = $WeaponPivot
@onready var arc: MeshInstance3D = $Arc
var _arc_material: StandardMaterial3D
var _rim: MeshInstance3D
var _trail: MeshInstance3D
var _shock_ring: MeshInstance3D
var _rim_material: StandardMaterial3D
var _trail_material: StandardMaterial3D
var _trail_mesh: ImmediateMesh
var _definition: AttackDefinition
var _last_elapsed: float = -1.0
var _last_active: bool = false


func _ready() -> void:
	_arc_material = StandardMaterial3D.new()
	_arc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_arc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc.material_override = _arc_material
	_rim_material = _make_effect_material(warning_color)
	_trail_material = _make_effect_material(active_color)
	_rim = _make_effect_node("RangeRim", _rim_material)
	_trail = _make_effect_node("ActionTrail", _trail_material)
	_shock_ring = _make_effect_node("ShockRing", _trail_material)
	_trail_mesh = ImmediateMesh.new()
	_trail.mesh = _trail_mesh
	clear_pose()


func begin(attack: AttackDefinition) -> void:
	_definition = attack
	_last_elapsed = -1.0
	var mesh: ImmediateMesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_angle: float = deg_to_rad(attack.arc_degrees * 0.5)
	for index: int in range(24):
		var a: float = lerpf(-half_angle, half_angle, float(index) / 24.0)
		var b: float = lerpf(-half_angle, half_angle, float(index + 1) / 24.0)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(Vector3(sin(a), 0, -cos(a)) * attack.reach)
		mesh.surface_add_vertex(Vector3(sin(b), 0, -cos(b)) * attack.reach)
	mesh.surface_end()
	arc.mesh = mesh
	arc.visible = true
	_rim.position.y = arc.position.y + 0.008
	_rim.mesh = _band_mesh(attack.reach - 0.045, attack.reach, -half_angle, half_angle, 32)
	_rim.visible = effect_strength > 0.0
	_shock_ring.position.y = arc.position.y + 0.016
	if attack.arc_degrees >= 359.0:
		_shock_ring.mesh = _band_mesh(attack.reach - 0.15, attack.reach, -PI, PI, 48)


func pose(attack: AttackDefinition, elapsed: float, active: bool) -> void:
	if attack == _definition and is_equal_approx(elapsed, _last_elapsed) and active == _last_active:
		return
	_last_elapsed = elapsed
	_last_active = active
	var swing: float
	if elapsed < attack.hit_start:
		swing = lerpf(0.0, -1.3, elapsed / maxf(attack.hit_start, 0.001))
	elif elapsed <= attack.hit_end:
		swing = lerpf(-1.3, 1.3, inverse_lerp(attack.hit_start, attack.hit_end, elapsed))
	else:
		swing = lerpf(1.3, 0.0, clampf(inverse_lerp(attack.hit_end, attack.duration, elapsed), 0.0, 1.0))
	pivot.rotation.y = -swing if attack.reverse_swing else swing
	# Warning readability: the fan alpha breathes within the configured alpha and
	# the accelerating phase reads as a countdown towards hit_start. Timings are only
	# read here; nothing in this file can move the damage window.
	var windup: float = maxf(attack.hit_start, 0.001)
	var pulse: float = _warning_pulse(clampf(elapsed / windup, 0.0, 1.0))
	if active:
		_arc_material.albedo_color = active_color
	else:
		_arc_material.albedo_color = Color(warning_color, warning_color.a * (1.0 - warning_pulse_depth * (1.0 - pulse) * effect_strength))
	arc.visible = elapsed < attack.hit_end
	if active:
		# Brightest exactly on the damaging frame, decaying across the active window.
		_rim_material.albedo_color = Color(active_color, lerpf(rim_active_alpha, 0.72, clampf(inverse_lerp(attack.hit_start, attack.hit_end, elapsed), 0.0, 1.0)))
	else:
		_rim_material.albedo_color = Color(warning_color, lerpf(0.6, rim_warning_alpha, pulse * effect_strength))
	_rim.visible = arc.visible and effect_strength > 0.0
	_trail.visible = active and effect_strength > 0.0 and attack.arc_degrees < 359.0
	_shock_ring.visible = active and effect_strength > 0.0 and attack.arc_degrees >= 359.0
	if _shock_ring.visible:
		_trail_material.albedo_color = Color(active_color, 0.55 * effect_strength)
	if not _trail.visible:
		return
	var progress: float = clampf(inverse_lerp(attack.hit_start, attack.hit_end, elapsed), 0.0, 1.0)
	var half_angle: float = deg_to_rad(attack.arc_degrees * 0.5)
	var is_skill: bool = attack.localization_key == &"skill_star_blade"
	var head: float = lerpf(-half_angle, half_angle, progress) if attack.reverse_swing else lerpf(half_angle, -half_angle, progress)
	var span: float = minf(deg_to_rad(24.0), half_angle)
	var first: float = -half_angle if is_skill else maxf(-half_angle, head - span)
	var last: float = half_angle if is_skill else minf(half_angle, head + span)
	# The outer edge is always derived from AttackDefinition.reach; only the inner
	# edge and the alpha change per combo step, so the readable danger area matches
	# the damage area exactly.
	var outer: float = attack.reach if is_skill else attack.reach * 0.88
	var inner: float = maxf(outer - _trail_thickness(attack, is_skill), 0.0)
	_trail.position.y = 0.12
	_trail_material.albedo_color = Color(active_color, _trail_alpha(attack, is_skill) * effect_strength)
	_update_band(_trail_mesh, inner, outer, first, last, 12)


## 0.5 + 0.5*sin() on an accelerating phase, so the windup pulses faster as the hit
## approaches instead of throbbing at a constant rate.
func _warning_pulse(progress: float) -> float:
	return 0.5 + 0.5 * sin(progress * progress * TAU * warning_pulse_cycles)


## Combo differentiation. Three light/medium/heavy steps get visibly different trail
## weight so a player can read combo progress from the effect alone.
func _trail_thickness(attack: AttackDefinition, is_skill: bool) -> float:
	if is_skill:
		return 0.20
	match attack.localization_key:
		&"attack_01":
			return 0.24
		&"attack_03":
			return 0.46
		_:
			return 0.32


func _trail_alpha(attack: AttackDefinition, is_skill: bool) -> float:
	if is_skill:
		return 0.35
	match attack.localization_key:
		&"attack_01":
			return 0.40
		&"attack_03":
			return 0.62
		_:
			return 0.50


func clear_pose() -> void:
	pivot.rotation = Vector3.ZERO
	arc.visible = false
	_definition = null
	_last_elapsed = -1.0
	if is_instance_valid(_rim):
		_rim.visible = false
		_trail.visible = false
		_shock_ring.visible = false


func _make_effect_material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	return material


func _make_effect_node(node_name: String, material: Material) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.add_to_group(&"combat_effect_mesh")
	add_child(instance)
	return instance


func _band_mesh(inner: float, outer: float, first: float, last: float, segments: int) -> ImmediateMesh:
	var mesh: ImmediateMesh = ImmediateMesh.new()
	_update_band(mesh, inner, outer, first, last, segments)
	return mesh


func _update_band(mesh: ImmediateMesh, inner: float, outer: float, first: float, last: float, segments: int) -> void:
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(segments):
		var a: float = lerpf(first, last, float(index) / float(segments))
		var b: float = lerpf(first, last, float(index + 1) / float(segments))
		var near_a: Vector3 = Vector3(sin(a), 0, -cos(a)) * maxf(inner, 0.0)
		var near_b: Vector3 = Vector3(sin(b), 0, -cos(b)) * maxf(inner, 0.0)
		var far_a: Vector3 = Vector3(sin(a), 0, -cos(a)) * outer
		var far_b: Vector3 = Vector3(sin(b), 0, -cos(b)) * outer
		for vertex: Vector3 in [near_a, far_a, far_b, near_a, far_b, near_b]:
			mesh.surface_add_vertex(vertex)
	mesh.surface_end()
