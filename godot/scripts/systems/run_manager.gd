class_name RunManager
extends Node3D
## Scene-local run lifecycle. Independent scenes retain the P4 staging fixture.

signal state_changed(state: State)
signal progress_changed
signal clock_changed(seconds: float)
signal boss_health_changed(current: int, maximum: int)
signal boss_action_changed(action: String)

enum State { COMBAT, CHOOSING, EXPLORING, PAUSED, FAILED, STAGE_COMPLETE, TRANSITION, WON }
const ROOM: PackedScene = preload("res://scenes/levels/combat_room.tscn")
@export var rooms: Array[RoomDefinition] = []
## -1 generates a new seed. Set a nonnegative value in Inspector for reproducible candidates.
@export var run_seed: int = -1
var active_seed: int = 0
var current_state: State = State.TRANSITION
var room_index: int = 0
var rooms_cleared: int = 0
var kills: int = 0
var elapsed: float = 0.0
var room: RoomController
## Human-readable cause of the killing blow, filled once on death (GAMEPLAY_DESIGN G-07).
## Kept as a plain string so it never leaks into DamageInfo or the combat rules.
var last_hit_summary: String = ""
var _resume_state: State = State.COMBAT
var _last_clock_second: int = -1
@onready var player: PlayerController = $Player
@onready var blessings: BlessingManager = $BlessingManager
@onready var ui: RunUI = $RunUI


func _ready() -> void:
	assert(rooms.size() == 3 and (rooms[2].boss_staging or rooms[2].boss_room))
	active_seed = run_seed if run_seed >= 0 else int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_usec()
	blessings.initialize(player, active_seed)
	blessings.selection_completed.connect(_on_blessing_selected)
	player.health.died.connect(_on_player_died)
	ui.bind_run(self)
	_load_room()


func _physics_process(delta: float) -> void:
	if current_state not in [State.COMBAT, State.EXPLORING] or get_tree().paused:
		return
	elapsed += delta
	if int(elapsed) != _last_clock_second:
		_last_clock_second = int(elapsed)
		clock_changed.emit(elapsed)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse") and not event.is_echo():
		if current_state == State.PAUSED:
			resume()
		elif current_state in [State.COMBAT, State.EXPLORING]:
			pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		pause()


func pause() -> void:
	if current_state in [State.COMBAT, State.EXPLORING]:
		_resume_state = current_state
		_set_state(State.PAUSED)


func resume() -> void:
	if current_state == State.PAUSED:
		_set_state(_resume_state)


func select_blessing(id: StringName) -> bool:
	return current_state == State.CHOOSING and blessings.choose(id)


func restart() -> void:
	get_tree().paused = false
	var error: Error = get_tree().reload_current_scene()
	if error != OK:
		push_error("Failed to restart run: " + error_string(error))


func return_to_menu() -> void:
	if current_state not in [State.PAUSED, State.FAILED, State.WON, State.STAGE_COMPLETE]:
		return
	_set_state(State.TRANSITION)
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	if error != OK:
		push_error("Failed to return to menu: " + error_string(error))


func _load_room() -> void:
	var definition: RoomDefinition = rooms[room_index]
	player.state_machine.transition_to(PlayerStateMachine.State.FALL)
	player.combat.interrupt()
	player.velocity = Vector3.ZERO
	player.global_position = definition.player_spawn
	player.camera_controller.rotation.y = 0.0
	player.visual.rotation = Vector3.ZERO
	room = ROOM.instantiate() as RoomController
	room.definition = definition
	room.player = player
	room.run_seed = active_seed
	room.enemy_defeated.connect(_on_enemy_defeated)
	room.enemies_changed.connect(_on_enemies_changed)
	room.cleared.connect(_on_room_cleared)
	room.exit_requested.connect(_on_exit_requested)
	room.boss_defeated.connect(_on_boss_defeated)
	add_child(room)
	if is_instance_valid(room.boss):
		room.boss.health.health_changed.connect(_on_boss_health_changed)
		(room.boss.brain as GuardianBrain).move_selected.connect(_on_boss_action_changed)
		room.boss.brain.state_changed.connect(_on_boss_state_changed)
		_on_boss_health_changed(room.boss.health.current_health, room.boss.health.max_health)
		_on_boss_action_changed("留意横扫与圆形冲击预警")
	progress_changed.emit()
	_set_state(State.STAGE_COMPLETE if definition.boss_staging else State.COMBAT)


func _on_enemies_changed(_remaining: int, _total: int) -> void:
	progress_changed.emit()


func _on_enemy_defeated(info: DamageInfo) -> void:
	if info != null and info.source == player:
		kills += 1
		blessings.on_ordinary_enemy_killed()
	progress_changed.emit()


func _on_room_cleared() -> void:
	if current_state != State.COMBAT or not player.health.is_alive():
		return
	rooms_cleared += 1
	_set_state(State.CHOOSING)
	blessings.offer()
	progress_changed.emit()


func _on_blessing_selected(_blessing: BlessingDefinition) -> void:
	if current_state == State.CHOOSING:
		_set_state(State.EXPLORING)


func _on_exit_requested() -> void:
	if current_state != State.EXPLORING or not room.is_cleared or room_index >= rooms.size() - 1:
		return
	_set_state(State.TRANSITION)
	_advance_room.call_deferred()


func _advance_room() -> void:
	if current_state != State.TRANSITION:
		return
	# Remove the old region before adding another at the same coordinates.
	remove_child(room)
	room.queue_free()
	room_index += 1
	_load_room()


func _on_player_died(info: DamageInfo) -> void:
	last_hit_summary = describe_damage_source(info)
	if current_state not in [State.FAILED, State.WON]:
		_set_state(State.FAILED)


## Reverse lookup from the attacker the hit came from; DamageInfo itself stays untouched.
## Sentinel and guardian both expose settings.display_name ("遗迹哨兵" / "晶核守卫") and the
## attack Resource that is currently resolving ("哨兵横扫" / "重锤横扫" / "晶能冲击"),
## so no display text is duplicated here.
func describe_damage_source(info: DamageInfo) -> String:
	if info == null:
		return "未知来源"
	var attacker: SentinelController = info.source as SentinelController
	if attacker == null or not is_instance_valid(attacker):
		return "未知来源"
	var attacker_name: String = attacker.brain.settings.display_name
	var move_name: String = attacker.brain.get_attack_definition().display_name
	var damage: int = int(round(info.base_damage * info.attack_multiplier))
	return "%s · %s（%d 伤害）" % [attacker_name, move_name, damage]


func _on_boss_defeated(info: DamageInfo) -> void:
	if current_state != State.COMBAT or not player.health.is_alive():
		return
	rooms_cleared += 1
	if info != null and info.source == player:
		kills += 1
	# Boss deaths never pass through ordinary-kill vitality healing or reward offers.
	player.combat.interrupt()
	_set_state(State.WON)
	progress_changed.emit()


func _on_boss_health_changed(current: int, maximum: int) -> void:
	boss_health_changed.emit(current, maximum)


func _on_boss_action_changed(action: String) -> void:
	boss_action_changed.emit(action)


func _on_boss_state_changed(_previous: String, current: String) -> void:
	if current == "Recover":
		boss_action_changed.emit("恢复中 · 进攻机会")
	elif current in ["Idle", "Chase", "Return"]:
		boss_action_changed.emit("留意横扫与圆形冲击预警")


func _set_state(state: State) -> void:
	current_state = state
	var blocked: bool = state not in [State.COMBAT, State.EXPLORING]
	get_tree().paused = blocked
	player.suppress_action_input()
	player.camera_controller.set_mouse_captured(not blocked)
	state_changed.emit(state)


func _exit_tree() -> void:
	get_tree().paused = false
