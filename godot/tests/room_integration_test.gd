extends SceneTree
## Graphical full P4 flow: normal stats, real attacks, UI pointer events and walking to exits.

var _run: RunManager
var _player: PlayerController
var _checks: int = 0
var _failures: int = 0
var _last_buffered_id: int = -1
var _max_actions: int = 0
var _actions_started: int = 0
var _saw_flame_hit: bool = false
var _saw_unmodified_skill: bool = false
var _wind_cooldown_at_start: float = -1.0
## RunManager pauses itself on NOTIFICATION_APPLICATION_FOCUS_OUT (correct player-facing
## behaviour: alt-tab must pause). Any other window taking focus during a fight makes the
## fight loop exit immediately with the player untouched, which used to be reported as a
## mysterious "combat clears enemies (27 frames, HP 100)" failure. Counting and resuming
## keeps the result honest: a non-zero count means the desktop was stolen mid-run.
var _focus_pauses: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.grab_focus()
	_run = (load("res://scenes/levels/room_run.tscn") as PackedScene).instantiate() as RunManager
	_run.run_seed = 424242
	root.add_child(_run)
	current_scene = _run
	_bind()
	await _ticks(5)
	# The game can only capture the mouse while its OS window owns the foreground. On an
	# unattended desktop another window can hold it for seconds, which used to fail the
	# capture assertion for reasons unrelated to the game. A real player clicking the
	# window always has the foreground, so claiming it here restores the real precondition
	# instead of weakening the assertion.
	DisplayServer.window_move_to_foreground()
	for frame: int in range(300):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			break
		await _ticks(1)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "P4 graphical session captures mouse")
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_abort("desktop focus unavailable: the game could not capture the mouse. This is an invalid environment for a graphical run, not a game defect.")
		return
	await _screenshot("room_preview.png")
	await _escape()
	_check(_run.current_state == RunManager.State.PAUSED and paused, "actual Esc event opens pause menu")
	var old_time: float = _run.elapsed
	var old_hp: int = _player.health.current_health
	Input.action_press("attack")
	Input.action_press("skill")
	Input.action_press("dodge")
	await _ticks(20)
	_check(_run.elapsed == old_time and _player.health.current_health == old_hp, "paused input cannot advance time or damage player")
	await _escape()
	await _ticks(2)
	_check(_run.current_state == RunManager.State.COMBAT and not paused, "Esc resumes exact active state")
	_check(_player.combat.current_attack == null and _player.state_machine.cooldown_remaining == 0.0, "held actions across modal do not fire on resume")
	_release()
	await _fight(1)
	_check(_run.current_state == RunManager.State.CHOOSING and _run.blessings.candidates.size() == 3, "input-driven first clear displays three reward cards")
	await _screenshot("blessing_preview.png")
	await _escape()
	_check(_run.current_state == RunManager.State.CHOOSING and paused, "Esc cannot dismiss mandatory blessing selection")
	var hp_before: int = _player.health.current_health
	var actions_before: int = _actions_started
	await _click_card("blessing_vitality")
	_check(_run.blessings.has_blessing(&"blessing_vitality") and _run.current_state == RunManager.State.EXPLORING, "actual pointer click selects vitality and resumes")
	_check(_player.health.current_health == mini(100, hp_before + 20), "card selection heals through shared HealthComponent")
	await _ticks(3)
	_check(_actions_started == actions_before, "card click does not start an additional world attack")
	await _walk_to_exit(0)
	_check(_run.room_index == 1 and _run.room.get_living_enemy_count() == 3, "ordinary player movement crosses exit into room two")
	_check(_run.blessings.has_blessing(&"blessing_vitality"), "selected blessing survives actual traversal")
	await _fight(2)
	_check(_run.blessings.candidates.size() == 2 and _run.kills == 5, "second real clear offers two remaining rewards and counts five kills")
	await _screenshot("blessing_second_preview.png")
	await _click_card("blessing_flame")
	_check(_run.blessings.has_blessing(&"blessing_flame") and _run.blessings.acquired.size() == 2, "second pointer selection acquires a distinct blessing")
	await _walk_to_exit(1)
	_check(_run.room_index == 2 and _run.current_state == RunManager.State.STAGE_COMPLETE, "real traversal reaches third-room stage summary")
	_check(_run.kills == 5 and _run.rooms_cleared == 2 and _player.health.is_alive(), "ordinary-room run ends alive with correct summary counts")
	await _screenshot("room_complete.png")
	await _click_button("重新开始")
	await _ticks(20)
	_run = current_scene as RunManager
	_bind()
	_check(_run.room_index == 0 and _run.blessings.acquired.is_empty() and _player.health.current_health == 100, "summary restart button resets actual scene and run state")
	_check(_player.combat.skill_cooldown_remaining == 0 and _player.state_machine.cooldown_remaining == 0, "UI restart clears both cooldowns")
	# A second ordinary-room flow puts flame into real combat and tests wind via real input.
	root.size = Vector2i(1920, 1080)
	await _ticks(5)
	await _fight(1)
	await _click_card("blessing_flame")
	await _walk_to_exit(0)
	for sentinel: SentinelController in _run.room.enemies:
		sentinel.health.damaged.connect(_on_flame_room_damage)
	await _fight(2)
	_check(_saw_flame_hit, "flame produces enhanced damage through real hitbox contacts")
	_check(_saw_unmodified_skill, "flame leaves real skill contacts at their original multiplier")
	await _screenshot("blessing_1080_preview.png")
	await _click_card("blessing_wind")
	_release()
	await _ticks(60)
	_player.state_machine.dodge_started.connect(_on_wind_dodge)
	Input.action_press("dodge")
	await _ticks(1)
	Input.action_release("dodge")
	_check(is_equal_approx(_wind_cooldown_at_start, 0.9), "wind changes actual input-driven dodge cooldown to 0.9 seconds")
	await _walk_to_exit(1)
	_check(_run.room_index == 2 and _run.kills == 5 and _player.health.is_alive(), "second ordinary-room run completes with flame and wind")
	_check(_max_actions <= 1, "three-enemy room keeps at most one complete attack chain active")
	_release()
	_player.camera_controller.set_mouse_captured(false)
	_run.queue_free()
	current_scene = null
	await process_frame
	# Physics frames may run faster than real audio callbacks in this fixture.
	# Match other suites by allowing stopped playback references to be reclaimed.
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("ROOM INTEGRATION RESULT: %d checks, %d failures (focus pauses: %d)" % [_checks, _failures, _focus_pauses])
	quit(0 if _failures == 0 else 1)


func _fight(number: int) -> void:
	var frames: int = 0
	for frame: int in range(1800):
		if _run.current_state == RunManager.State.PAUSED:
			_focus_pauses += 1
			_run.resume()
		if _run.current_state != RunManager.State.COMBAT or not _player.health.is_alive():
			break
		frames += 1
		_bot_input()
		var active: int = 0
		for enemy: SentinelController in _run.room.enemies:
			if is_instance_valid(enemy) and enemy.brain.current_state in [EnemyBrain.State.TELEGRAPH, EnemyBrain.State.ATTACK, EnemyBrain.State.RECOVER]:
				active += 1
		_max_actions = maxi(_max_actions, active)
		await _ticks(1)
	_release()
	_check(_run.room.get_living_enemy_count() == 0 and _player.health.is_alive(), "room %d: real-input combat clears enemies (%d frames, HP %d, focus pauses %d, exit state %s, tree paused %s, living %d)" % [number, frames, _player.health.current_health, _focus_pauses, RunManager.State.keys()[_run.current_state], paused, _run.room.get_living_enemy_count()])
	_check(_run.current_state == RunManager.State.CHOOSING, "room %d: last real hit opens reward modal" % number)


func _bot_input() -> void:
	Input.action_release("attack")
	Input.action_release("skill")
	var nearest: SentinelController
	var best_distance: float = INF
	for actor: SentinelController in _run.room.enemies:
		if not is_instance_valid(actor) or not actor.health.is_alive():
			continue
		var distance: float = actor.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			nearest = actor
	if nearest == null:
		return
	var toward: Vector3 = nearest.global_position - _player.global_position
	toward.y = 0.0
	toward = toward.normalized()
	_player.camera_controller.rotation.y = atan2(-toward.x, -toward.z)
	var state: String = _player.state_machine.get_state_name()
	if state in ["Idle", "Move"]:
		Input.action_press("move_forward")
		var facing: bool = _player.get_facing_direction().dot(toward) > 0.95
		if facing and _player.combat.skill_cooldown_remaining <= 0.0 and best_distance < 4.7:
			Input.action_press("skill")
		elif facing and best_distance < 1.85:
			Input.action_press("attack")
	else:
		Input.action_release("move_forward")
	if state == "Attack" and _player.combat.current_attack != null:
		var attack_id: int = _player.combat.hitbox.damage_info.attack_id
		if _player.combat.elapsed > _player.combat.current_attack.duration - 0.12 and attack_id != _last_buffered_id:
			_last_buffered_id = attack_id
			Input.action_press("attack")


func _walk_to_exit(old_index: int) -> void:
	_release()
	for frame: int in range(1000):
		if _run.room_index != old_index:
			break
		var toward: Vector3 = Vector3(0, 0, -17) - _player.position
		toward.y = 0.0
		_player.camera_controller.rotation.y = atan2(-toward.x, -toward.z)
		Input.action_press("move_forward")
		await _ticks(1)
	_release()
	await _ticks(5)


func _bind() -> void:
	_player = _run.player
	_player.camera_controller.set_process_unhandled_input(false)
	_player.combat.action_started.connect(_on_action_started)
	_last_buffered_id = -1


func _on_action_started(_action: String, _combo: int) -> void:
	_actions_started += 1


func _on_flame_room_damage(amount: int, info: DamageInfo) -> void:
	if info.base_damage in [12.0, 16.0, 24.0] and is_equal_approx(info.attack_multiplier, 1.2) and amount in [14, 19, 29]:
		_saw_flame_hit = true
	if is_equal_approx(info.base_damage, 35.0) and is_equal_approx(info.attack_multiplier, 1.0):
		_saw_unmodified_skill = true


func _on_wind_dodge(_direction: Vector3) -> void:
	_wind_cooldown_at_start = _player.state_machine.cooldown_remaining


func _click_card(id: String) -> void:
	var button: Button = _run.ui.find_child(id, true, false) as Button
	_check(button != null and button.is_visible_in_tree(), "reward card %s is visible and clickable" % id)
	if button != null:
		await _pointer_click(button)


func _click_button(text: String) -> void:
	var button: Button = await _find_button(text, 240)
	if button == null:
		_check(false, "button is available: " + text)
		return
	await _pointer_click(button)


## Waits for a button instead of assuming a fixed number of frames is enough.
## A fixed `_ticks(8)` window made victory-menu navigation fail whenever the scene
## swap took slightly longer, which surfaced as unrelated cascading failures.
func _find_button(text: String, limit: int) -> Button:
	for frame: int in range(limit):
		var host: Node = current_scene if current_scene != null else _run
		if host != null:
			for node: Node in host.find_children("*", "Button", true, false):
				var button: Button = node as Button
				if button.text == text and button.is_visible_in_tree():
					return button
		await _ticks(1)
	return null


func _await_main_menu(limit: int = 300) -> void:
	for frame: int in range(limit):
		if current_scene is MainMenu and not paused:
			return
		await _ticks(1)


## Takes the previous run's instance id rather than the object: after a restart the old
## RunManager is already freed, and passing a freed object into a typed parameter raises
## "is not a subclass of the expected argument class" and kills the coroutine.
func _await_new_run(previous_id: int, limit: int = 300) -> RunManager:
	for frame: int in range(limit):
		var scene: Node = current_scene
		if scene is RunManager and scene.get_instance_id() != previous_id:
			return scene as RunManager
		await _ticks(1)
	return current_scene as RunManager


func _pointer_click(button: Button) -> void:
	await _ticks(2)
	var point: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.position = point
		root.push_input(event, true)
	await _ticks(4)


func _escape() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
		await _ticks(2)


func _screenshot(filename: String) -> void:
	await _ticks(3)
	RenderingServer.force_draw()
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../docs/" + filename)) == OK, "rendered preview saved: " + filename)


func _ticks(count: int) -> void:
	for frame: int in range(count):
		await physics_frame
		await process_frame


func _release() -> void:
	for action: String in ["move_forward", "move_backward", "move_left", "move_right", "jump", "dodge", "attack", "skill"]:
		Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures += 1
		printerr("FAIL: " + description)


## Stops the run immediately instead of letting a broken precondition cascade into a
## meaningless assertion, or into a coroutine error that never reaches quit() and makes
## the whole suite hang until the harness timeout.
func _abort(reason: String) -> void:
	for action: String in ["move_forward", "move_backward", "move_left", "move_right", "jump", "dodge", "attack", "skill"]:
		Input.action_release(action)
	printerr("ABORT: " + reason)
	print("INTEGRATION ABORTED: %d checks, %d failures (reason: %s)" % [_checks, _failures, reason])
	quit(1)
