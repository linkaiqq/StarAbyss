class_name CombatVFX
extends Node3D
## Scene-local cosmetic fragments. No collision, damage or gameplay clocks.
## P7 keeps the same bounded fragment pool but makes hits read heavier: sparks are
## pushed away from the attacker and scale with the damage actually applied, and a
## terminal death adds one expanding ground ring. Every extra node is a Fragment, so
## max_fragments still caps the whole effect.

signal burst_emitted(fragment_count: int, terminal: bool)

## Damage applied by one hit that is worth one extra spark.
const DAMAGE_PER_EXTRA_SPARK: float = 12.0
## Sparks further than this many extra fragments are pointless; the pool caps it anyway.
const MAX_EXTRA_SPARKS: int = 4

class Fragment:
	var visual: MeshInstance3D
	var velocity: Vector3
	var age: float = 0.0
	var lifetime: float
	var initial_scale: float
	## > 0 makes the fragment expand from 35% to this multiple of its start size.
	var growth: float = 0.0
	## Anchored fragments ignore gravity and translation (ground rings).
	var anchored: bool = false
	## Owned material, only set when the fragment has to fade its own alpha.
	var material: StandardMaterial3D
	var base_alpha: float = 1.0

@export var actor_path: NodePath = NodePath("..")
@export_range(0.0, 1.0, 0.05) var effect_strength: float = 0.7
@export_range(1, 24, 1) var max_fragments: int = 12
@export_range(1, 8, 1) var impact_fragments: int = 4
@export_range(1, 16, 1) var death_fragments: int = 10
var _actor: Node3D
var _health: HealthComponent
var _feedback: CombatFeedback
var _fragments: Array[Fragment] = []
var _fragment_mesh: PrismMesh
var _ring_mesh: TorusMesh
var _impact_material: StandardMaterial3D
var _death_material: StandardMaterial3D
var _burst_serial: int = 0
var _burst_height: float = 1.0
var _death_emitted: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 20
	_actor = get_node(actor_path) as Node3D
	_health = _actor.get_node("Health") as HealthComponent
	_feedback = _actor.get_node("Feedback") as CombatFeedback
	for child: Node in _actor.get_children():
		if child is CollisionShape3D:
			var capsule: CapsuleShape3D = (child as CollisionShape3D).shape as CapsuleShape3D
			if capsule != null:
				_burst_height = capsule.height * 0.58
				break
	_fragment_mesh = PrismMesh.new()
	_fragment_mesh.size = Vector3(0.055, 0.12, 0.055)
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = 0.38
	_ring_mesh.outer_radius = 0.5
	_ring_mesh.rings = 6
	_ring_mesh.ring_segments = 28
	var is_player: bool = _actor is PlayerController
	_impact_material = _make_material(Color(1.0, 0.46, 0.13) if is_player else Color(0.34, 0.86, 1.0))
	_death_material = _make_material(Color(0.3, 0.8, 0.95) if is_player else Color(1.0, 0.52, 0.13))
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	# Living impacts follow pause and local hit stop. Terminal shards may finish
	# behind the result panel, like the existing terminal skeletal collapse.
	if not _death_emitted and (get_tree().paused or _feedback.freeze_remaining > 0.0):
		return
	for index: int in range(_fragments.size() - 1, -1, -1):
		var fragment: Fragment = _fragments[index]
		fragment.age += delta
		if fragment.age >= fragment.lifetime:
			_remove_fragment(index)
			continue
		if not fragment.anchored:
			fragment.velocity.y -= 9.0 * delta
			fragment.visual.global_position += fragment.velocity * delta
			fragment.visual.rotate_y(delta * 5.0)
			fragment.visual.rotate_z(delta * 3.0)
		var remaining: float = 1.0 - fragment.age / fragment.lifetime
		if fragment.growth > 0.0:
			fragment.visual.scale = Vector3.ONE * fragment.initial_scale * lerpf(0.35, fragment.growth, 1.0 - remaining)
		else:
			fragment.visual.scale = Vector3.ONE * fragment.initial_scale * remaining
		if fragment.material != null:
			var color: Color = fragment.material.albedo_color
			color.a = fragment.base_alpha * remaining
			fragment.material.albedo_color = color
	if _fragments.is_empty():
		set_physics_process(false)


func _on_damaged(amount: int, info: DamageInfo) -> void:
	if not _death_emitted:
		_burst(_impact_count(amount), false, info)


func _on_died(_info: DamageInfo) -> void:
	if _death_emitted:
		return
	_death_emitted = true
	clear_effects()
	_burst(death_fragments, true, null)
	_spawn_death_ring()


## Heavier hits throw more sparks; the shared pool still caps the total.
func _impact_count(amount: int) -> int:
	if amount <= 0:
		return impact_fragments
	var extra: int = mini(int(float(amount) / DAMAGE_PER_EXTRA_SPARK), MAX_EXTRA_SPARKS)
	return impact_fragments + extra


func _burst(requested: int, terminal: bool, info: DamageInfo) -> void:
	if effect_strength <= 0.0 or max_fragments <= 0:
		return
	_burst_serial += 1
	var count: int = mini(requested, max_fragments)
	var push: Vector3 = _away_from_source(info)
	for index: int in range(count):
		while _fragments.size() >= max_fragments:
			_remove_fragment(0)
		var angle: float = TAU * (float(index) / float(count) + float(_burst_serial) * 0.6180339)
		var speed: float = (1.0 if terminal else 2.0) * (0.6 + effect_strength * 0.4)
		var fragment: Fragment = Fragment.new()
		fragment.visual = MeshInstance3D.new()
		fragment.visual.name = "CrystalFragment" if terminal else "ImpactSpark"
		fragment.visual.mesh = _fragment_mesh
		fragment.visual.material_override = _death_material if terminal else _impact_material
		fragment.visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(fragment.visual)
		fragment.visual.top_level = true
		fragment.visual.global_position = _actor.global_position + Vector3.UP * _burst_height
		fragment.visual.rotation = Vector3(angle, angle * 0.5, angle * 0.3)
		fragment.initial_scale = (1.0 if terminal else 0.55) * (0.5 + effect_strength * 0.5)
		fragment.visual.scale = Vector3.ONE * fragment.initial_scale
		# Sparks spray away from whoever hit this actor, so the impact reads as
		# directional instead of a symmetric puff.
		fragment.velocity = Vector3(cos(angle) * speed, 1.5 + float(index % 3) * 0.3, sin(angle) * speed) + push
		fragment.lifetime = 0.65 if terminal else 0.24
		_fragments.append(fragment)
	set_physics_process(true)
	burst_emitted.emit(mini(count, _fragments.size()), terminal)


## Horizontal direction pointing away from the damage source, in world space.
func _away_from_source(info: DamageInfo) -> Vector3:
	if info == null or not (info.source is Node3D) or not is_instance_valid(info.source):
		return Vector3.ZERO
	var source: Node3D = info.source as Node3D
	var away: Vector3 = _actor.global_position - source.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return Vector3.ZERO
	return away.normalized() * (1.1 * (0.5 + effect_strength * 0.5))


## One expanding ground ring marks a terminal hit. It is a Fragment, so it is
## counted and freed by the same pool and never breaks max_fragments.
func _spawn_death_ring() -> void:
	if effect_strength <= 0.0 or max_fragments <= 0:
		return
	while _fragments.size() >= max_fragments:
		_remove_fragment(0)
	var ring: Fragment = Fragment.new()
	ring.visual = MeshInstance3D.new()
	ring.visual.name = "DeathRing"
	ring.visual.mesh = _ring_mesh
	ring.material = _make_material(_death_material.albedo_color, true)
	ring.visual.material_override = ring.material
	ring.visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring.visual)
	ring.visual.top_level = true
	ring.visual.global_position = _actor.global_position + Vector3.UP * 0.05
	ring.initial_scale = 0.5 + effect_strength * 0.5
	ring.growth = 3.4
	ring.lifetime = 0.45
	ring.anchored = true
	ring.base_alpha = 0.75
	_fragments.append(ring)
	set_physics_process(true)


func active_effect_count() -> int:
	return _fragments.size()


func clear_effects() -> void:
	for index: int in range(_fragments.size() - 1, -1, -1):
		_remove_fragment(index)
	set_physics_process(false)


func _remove_fragment(index: int) -> void:
	var fragment: Fragment = _fragments[index]
	if is_instance_valid(fragment.visual):
		fragment.visual.free()
	_fragments.remove_at(index)


func _make_material(color: Color, transparent: bool = false) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.1
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _exit_tree() -> void:
	clear_effects()
