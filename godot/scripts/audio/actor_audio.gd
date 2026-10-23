class_name ActorAudio
extends Node3D
## Actor-local bounded voice pool. Signals announce sound; no gameplay is changed.
## P7 adds movement, low-health and terminal-boss feedback; all of it is driven by
## signals or a local floor check, never by polling gameplay numbers.

signal cue_played(cue: StringName)

## Below this fraction of max health the player receives one danger cue.
const LOW_HEALTH_RATIO: float = 0.3
## Shorter airtime than this is spawn/step noise, not a real landing.
const MIN_AIRBORNE_FOR_LAND: float = 0.15

@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready() and not value:
			stop_all()
@export_range(-40.0, 0.0, 1.0) var volume_db: float = -7.0
@export_range(1, 6, 1) var max_voices: int = 4
@export_range(5.0, 40.0, 1.0) var audible_distance: float = 26.0
var _voices: Array[AudioStreamPlayer3D] = []
var _next_voice: int = 0
var _actor: CharacterBody3D
var _health: HealthComponent
var _brain: EnemyBrain
var _is_player: bool = false
var _critical: bool = false
var _airborne_time: float = 0.0
var _was_airborne: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"scene_audio")
	_actor = get_parent() as CharacterBody3D
	assert(_actor != null, "ActorAudio requires a character parent")
	_health = _actor.get_node("Health") as HealthComponent
	_is_player = _actor is PlayerController
	# Tall actors emit from chest height so the boss does not sound like a sentinel.
	position.y = 1.0
	if _actor is SentinelController:
		_brain = _actor.get_node("EnemyBrain") as EnemyBrain
		if _brain is GuardianBrain:
			position.y = 1.8
	for index: int in range(max_voices):
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.name = "Voice%d" % index
		voice.bus = &"SFX"
		voice.unit_size = 8.0
		voice.max_db = 0.0
		voice.max_distance = audible_distance
		voice.panning_strength = 0.65
		voice.finished.connect(_release_voice.bind(voice))
		add_child(voice)
		_voices.append(voice)
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_died)
	if _is_player:
		_health.health_changed.connect(_on_health_changed)
		(_actor.get_node("Combat") as PlayerCombat).action_started.connect(_on_player_action)
		(_actor.get_node("StateMachine") as PlayerStateMachine).dodge_started.connect(_on_dodge)
		(_actor.get_node("StateMachine") as PlayerStateMachine).state_changed.connect(_on_player_state)
	elif _brain != null:
		_brain.attack_committed.connect(_on_enemy_commit)
		_brain.state_changed.connect(_on_enemy_state)


func _process(_delta: float) -> void:
	if get_tree().paused or not enabled:
		stop_all()


func _physics_process(delta: float) -> void:
	# Landing is the only event without a signal: CharacterBody3D exposes the floor
	# state, so the pool tracks airtime locally and stays silent for spawn drops.
	if not _is_player or not enabled or get_tree().paused or not _health.is_alive():
		return
	if _actor.is_on_floor():
		if _was_airborne and _airborne_time >= MIN_AIRBORNE_FOR_LAND:
			play_cue(&"land")
		_airborne_time = 0.0
		_was_airborne = false
	else:
		_airborne_time += delta
		_was_airborne = true


func play_cue(cue: StringName) -> bool:
	if not enabled or not is_inside_tree() or get_tree().paused or _voices.is_empty():
		return false
	var stream: AudioStreamWAV = AudioCues.get_cue(cue)
	if stream == null:
		return false
	var voice: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = stream
	voice.volume_db = volume_db + AudioCues.get_gain(cue)
	voice.play()
	cue_played.emit(cue)
	return true


func stop_all() -> void:
	for voice: AudioStreamPlayer3D in _voices:
		_release_voice(voice)


func get_active_voice_count() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer3D in _voices:
		if voice.stream != null:
			count += 1
	return count


func _release_voice(voice: AudioStreamPlayer3D) -> void:
	voice.stop()
	voice.stream = null


func _on_player_action(_action_name: String, combo_step: int) -> void:
	play_cue(&"skill" if combo_step == 0 else StringName("swing_%02d" % combo_step))


func _on_dodge(_direction: Vector3) -> void:
	play_cue(&"dodge")


func _on_player_state(_previous: String, current: String) -> void:
	if current == "Jump":
		play_cue(&"jump")


func _on_health_changed(current: int, maximum: int) -> void:
	if not _is_player or maximum <= 0:
		return
	var critical: bool = current > 0 and float(current) / float(maximum) <= LOW_HEALTH_RATIO
	if critical and not _critical:
		play_cue(&"low_hp")
	_critical = critical


func _on_enemy_commit(_attack_id: int) -> void:
	if _brain is GuardianBrain:
		play_cue(&"guardian_shock_warning" if _brain.get_attack_definition().arc_degrees > 359.0 else &"guardian_sweep_warning")
	else:
		play_cue(&"sentinel_warning")


func _on_enemy_state(_previous: String, current: String) -> void:
	if current == "Attack":
		play_cue(&"guardian_slam" if _brain is GuardianBrain else &"swing_02")


func _on_damaged(_amount: int, _info: DamageInfo) -> void:
	if _health.is_alive():
		play_cue(&"hurt" if _is_player else &"impact")


func _on_died(_info: DamageInfo) -> void:
	stop_all()
	if _is_player:
		play_cue(&"hurt")
	elif _brain is GuardianBrain:
		# The core guardian death is the run climax and gets its own larger cue.
		play_cue(&"boss_death")
	else:
		play_cue(&"shatter")


func _exit_tree() -> void:
	stop_all()
