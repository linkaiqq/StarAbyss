class_name ActorPresentation
extends Node3D
## Read-only view of the existing action clocks. Animation never drives the motor or damage.

@export var model_scene: PackedScene
@export var weapon_scene: PackedScene
@export var weapon_bone: StringName = &"WeaponSocket"
@export var weapon_rotation_degrees: Vector3 = Vector3.ZERO
@export var actor_path: NodePath = NodePath("../..")
## P7: drive the cel shader's per-instance charge-up glow from the enemy windup clock.
@export var threat_pulse_enabled: bool = true
## Flicker cycles the warning glow goes through across one windup.
@export var threat_flicker_cycles: float = 4.0

var model: Node3D
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var weapon_attachment: BoneAttachment3D
var current_clip: StringName = &""
var sampled_time: float = 0.0
var _local_elapsed: float = 0.0
var _actor: CharacterBody3D
var _health: HealthComponent
var _feedback: CombatFeedback
var _player: PlayerController
var _enemy: SentinelController
var _threat_meshes: Array[MeshInstance3D] = []
var _threat_value: float = -1.0


func _ready() -> void:
	# The view is built before its actor's Feedback._ready scans all visible meshes.
	process_physics_priority = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_actor = get_node(actor_path) as CharacterBody3D
	_player = _actor as PlayerController
	_enemy = _actor as SentinelController
	_health = _actor.get_node("Health") as HealthComponent
	_feedback = _actor.get_node("Feedback") as CombatFeedback
	assert(model_scene != null and weapon_scene != null, "Actor requires imported model and weapon")
	model = model_scene.instantiate() as Node3D
	add_child(model)
	for child: Node in model.find_children("*", "Skeleton3D", true, false):
		skeleton = child as Skeleton3D
		break
	for child: Node in model.find_children("*", "AnimationPlayer", true, false):
		animation_player = child as AnimationPlayer
		break
	assert(skeleton != null and animation_player != null, "Imported actor requires skeleton and animations")
	assert(skeleton.find_bone(weapon_bone) >= 0, "Imported actor requires weapon socket bone")
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	weapon_attachment = BoneAttachment3D.new()
	weapon_attachment.name = "WeaponAttachment"
	weapon_attachment.bone_name = weapon_bone
	skeleton.add_child(weapon_attachment)
	var weapon: Node3D = weapon_scene.instantiate() as Node3D
	# The authored grip points forward at rest. Cancel any rest-axis adjustment
	# made by the skeleton importer before applying an optional artist offset.
	var rest_basis: Basis = skeleton.get_bone_global_rest(skeleton.find_bone(weapon_bone)).basis.orthonormalized()
	var offset: Vector3 = weapon_rotation_degrees * (PI / 180.0)
	weapon.basis = rest_basis.inverse() * Basis.from_euler(offset)
	weapon_attachment.add_child(weapon)
	ToonPalette.apply_to(model)
	_cache_threat_meshes()
	_health.died.connect(_on_died)
	_sample(&"Idle", 0.0, true)


func _physics_process(delta: float) -> void:
	# A terminal collapse may finish behind the result panel. Living actors remain
	# frozen during pause/selection, exactly like their physics and action clocks.
	if not _health.is_alive():
		_sample(&"Death", delta)
		return
	if get_tree().paused:
		return
	if _player != null:
		_sample_player(delta)
	else:
		_sample_enemy(delta)


func _sample_player(delta: float) -> void:
	var combat: PlayerCombat = _player.combat
	if combat.current_attack != null:
		var clip: StringName = &"Skill_01" if combat.is_skill else StringName("Attack_%02d" % (combat.combo_index + 1))
		_sample(clip, combat.elapsed, true)
		return
	var machine: PlayerStateMachine = _player.state_machine
	if machine.current_state == PlayerStateMachine.State.DODGE:
		_sample(&"Dodge", machine.dodge_elapsed, true)
		return
	# An impact starts hit stop inside the motor's current tick, after its action
	# clock advanced. Sample that authoritative clock first, then freeze local loops.
	if _feedback.freeze_remaining > 0.0:
		return
	match machine.current_state:
		PlayerStateMachine.State.JUMP:
			_sample(&"Jump", delta)
		PlayerStateMachine.State.FALL:
			_sample(&"Fall", delta)
		PlayerStateMachine.State.HURT:
			_sample(&"Hurt", delta)
		PlayerStateMachine.State.MOVE:
			_sample(&"Run", delta)
		_:
			_sample(&"Idle", delta)


func _sample_enemy(delta: float) -> void:
	var brain: EnemyBrain = _enemy.brain
	_update_threat(brain)
	if brain.current_state in [EnemyBrain.State.TELEGRAPH, EnemyBrain.State.ATTACK, EnemyBrain.State.RECOVER]:
		var clip: StringName = &"Attack"
		if brain is GuardianBrain:
			clip = &"Attack_Shockwave" if brain.get_attack_definition().arc_degrees >= 359.0 else &"Attack_Sweep"
		_sample(clip, brain.action_elapsed, true)
		return
	if _feedback.freeze_remaining > 0.0:
		return
	if brain.current_state == EnemyBrain.State.HURT:
		_sample(&"Hurt", delta)
	elif Vector2(_enemy.velocity.x, _enemy.velocity.z).length() > 0.1:
		_sample(&"Run", delta)
	else:
		_sample(&"Idle", delta)


func _sample(clip: StringName, value: float, absolute_time: bool = false) -> void:
	if current_clip != clip:
		assert(animation_player.has_animation(clip), "Missing imported animation: %s" % clip)
		current_clip = clip
		_local_elapsed = 0.0
		animation_player.play(clip)
	if absolute_time:
		_local_elapsed = value
	else:
		_local_elapsed += value
	var animation: Animation = animation_player.get_animation(clip)
	var loops: bool = clip in [&"Idle", &"Run", &"Fall"]
	sampled_time = fposmod(_local_elapsed, animation.length) if loops else minf(_local_elapsed, animation.length)
	animation_player.seek(sampled_time, true)


## Collects only the imported body meshes that carry a cel ShaderMaterial, so the
## per-instance charge glow never touches the weapon or arena geometry.
func _cache_threat_meshes() -> void:
	_threat_meshes.clear()
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance.mesh != null:
			_threat_meshes.append(mesh_instance)


## Maps the enemy's authoritative windup clock onto a 0..1 charge glow. This is a
## pure read: it never writes brain state, timings or the damage window.
func _update_threat(brain: EnemyBrain) -> void:
	if not threat_pulse_enabled or _threat_meshes.is_empty():
		return
	var value: float = 0.0
	if brain.current_state == EnemyBrain.State.TELEGRAPH:
		var attack: AttackDefinition = brain.get_attack_definition()
		if attack != null:
			var windup: float = maxf(attack.hit_start, 0.001)
			var progress: float = clampf(brain.action_elapsed / windup, 0.0, 1.0)
			# The flicker phase accelerates with progress, so the body pulses faster
			# and faster like a countdown instead of a steady throb.
			var beat: float = 0.5 + 0.5 * sin(progress * progress * TAU * threat_flicker_cycles)
			value = clampf(progress * (0.45 + 0.55 * beat), 0.0, 1.0)
	_apply_threat(value)


func _apply_threat(value: float) -> void:
	if is_equal_approx(value, _threat_value):
		return
	_threat_value = value
	for mesh_instance: MeshInstance3D in _threat_meshes:
		mesh_instance.set_instance_shader_parameter(&"threat_pulse", value)


func _on_died(_info: DamageInfo) -> void:
	# Health signals precede run settlement, so the result panel never retains an
	# attack pose even when SceneTree.pause is set in the same damage callback.
	_apply_threat(0.0)
	_sample(&"Death", 0.0, true)
