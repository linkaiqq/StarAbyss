extends "res://tests/room_integration_test.gd"
## Reuses ordinary-room input fixtures; three complete runs use normal game stats.

var _saw_sweep: bool = false
var _saw_shockwave: bool = false
var _boss_damage_events: int = 0


func _test() -> void:
	root.grab_focus()
	var menu: MainMenu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await _ticks(5)
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not paused, "title starts mouse-visible and unpaused")
	await _screenshot("main_menu_preview.png")
	await _start_from_menu()
	if _run == null:
		return
	for round_number: int in range(1, 4):
		_check(_run.room_index == 0 and _player.health.current_health == 100 and _run.kills == 0 and _run.rooms_cleared == 0, "run %d starts with clean player and progress" % round_number)
		_check(_run.blessings.acquired.is_empty() and _player.combat.skill_cooldown_remaining == 0 and _player.state_machine.cooldown_remaining == 0, "run %d has no blessing or cooldown residue" % round_number)
		await _fight(1)
		await _click_card("blessing_flame" if round_number == 2 else "blessing_vitality")
		await _walk_to_exit(0)
		await _fight(2)
		await _click_card("blessing_wind" if round_number == 2 else "blessing_flame")
		await _walk_to_exit(1)
		_check(_run.room_index == 2 and _run.room.definition.boss_room and _run.current_state == RunManager.State.COMBAT, "run %d enters actual third-room Boss encounter" % round_number)
		if not is_instance_valid(_run.room.boss):
			# Fail fast. Accessing .health on a missing Boss used to raise inside a coroutine,
			# so quit() was never reached and the whole suite hung until the harness timeout.
			_check(false, "run %d third room actually contains a Boss node" % round_number)
			print("FULL RUN INTEGRATION RESULT: %d checks, %d failures (aborted: no Boss)" % [_checks, _failures])
			quit(1)
			return
		_check(_run.room.boss.health.current_health == 350 and _run.ui.find_child("BossPanel", true, false).visible, "run %d starts with full Boss HP and upper-screen health bar" % round_number)
		_run.room.boss.health.damaged.connect(_on_boss_damage)
		await _fight_boss(round_number)
		_check(_run.current_state == RunManager.State.WON and paused and _player.health.is_alive(), "run %d reaches real victory alive" % round_number)
		_check(_run.kills == 6 and _run.rooms_cleared == 3 and _run.blessings.acquired.size() == 2, "run %d summary reports six kills, three rooms and two blessings" % round_number)
		_check(_run.room.boss.brain.hitbox.damage_info == null and not _run.room.boss.brain.hitbox.active, "run %d winning hit leaves no Boss attack" % round_number)
		if _run.current_state != RunManager.State.WON:
			break
		if round_number == 1:
			await _screenshot("victory_preview.png")
		if round_number == 2:
			root.size = Vector2i(1920, 1080)
			await _screenshot("victory_1080_preview.png")
		if round_number < 3:
			var restart_from: int = _run.get_instance_id()
			await _click_button("重新开始")
			_run = await _await_new_run(restart_from)
			_bind()
	_check(_saw_sweep and _saw_shockwave, "full-run play observes both actual Boss moves")
	_check(_boss_damage_events > 10, "Boss HP is depleted through many real shared hitbox contacts")
	if _run.current_state == RunManager.State.WON:
		await _click_button("返回主菜单")
		await _await_main_menu()
		_check(current_scene is MainMenu and not paused, "victory menu button returns to clean title")
		await _start_from_menu()
		await _escape()
		await _click_button("返回主菜单")
		await _await_main_menu()
		_check(current_scene is MainMenu and not paused, "pause menu can abandon run and return to title")
		await _start_from_menu()
		_release()
		for frame: int in range(3600):
			if _run.current_state == RunManager.State.PAUSED:
				_focus_pauses += 1
				_run.resume()
			if _run.current_state == RunManager.State.FAILED:
				break
			await _ticks(1)
		_check(_run.current_state == RunManager.State.FAILED and _player.health.current_health == 0, "ordinary enemy attacks produce an actual failure without injected damage")
		await _screenshot("failure_preview.png")
		var retry_from: int = _run.get_instance_id()
		await _click_button("重新开始")
		_run = await _await_new_run(retry_from)
		_bind()
		_check(_player.health.current_health == 100 and _run.kills == 0 and _run.blessings.acquired.is_empty(), "failure restart clears actual run state")
	_release()
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("FULL RUN INTEGRATION RESULT: %d checks, %d failures (focus pauses: %d)" % [_checks, _failures, _focus_pauses])
	quit(0 if _failures == 0 else 1)


func _start_from_menu() -> void:
	# StartRun is a NODE NAME, not a button caption: match by name and poll for it.
	var start: Button = null
	for frame: int in range(240):
		if current_scene != null:
			var found: Node = current_scene.find_child("StartRun", true, false)
			if found is Button and (found as Button).is_visible_in_tree():
				start = found as Button
				break
		await _ticks(1)
	_check(start != null, "title has actual start button")
	if start == null:
		_abort("title never offered a start button")
		return
	await _pointer_click(start)
	_run = await _await_new_run(0)
	_check(_run != null, "pointer click starts game scene")
	if _run == null:
		_abort("start button did not open a run")
		return
	_bind()
	# Same reason as room_integration_test: restore the real precondition (window owns the
	# foreground) before asserting that starting a run captured the mouse.
	DisplayServer.window_move_to_foreground()
	for frame: int in range(120):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			break
		await _ticks(1)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "starting run captures mouse")


func _fight_boss(round_number: int) -> void:
	var frames: int = 0
	for frame: int in range(6000):
		if _run.current_state == RunManager.State.PAUSED:
			_focus_pauses += 1
			_run.resume()
		if _run.current_state != RunManager.State.COMBAT:
			break
		frames += 1
		_boss_input()
		var brain: GuardianBrain = _run.room.boss.brain as GuardianBrain
		if brain.current_state == EnemyBrain.State.TELEGRAPH and brain.action_elapsed > 0.15:
			var is_shock: bool = brain.get_attack_definition().arc_degrees > 350
			if is_shock and not _saw_shockwave:
				_saw_shockwave = true
				await _screenshot("guardian_shockwave_preview.png")
			elif not is_shock and not _saw_sweep:
				_saw_sweep = true
				await _screenshot("guardian_sweep_preview.png")
		await _ticks(1)
	_release()
	if not is_instance_valid(_run.room.boss):
		_check(false, "run %d Boss node still exists when the fight ends" % round_number)
		return
	_check(not _run.room.boss.health.is_alive(), "run %d input-driven Boss defeated (%d frames, HP %d, focus pauses %d, exit state %s, tree paused %s, boss HP %d)" % [round_number, frames, _player.health.current_health, _focus_pauses, RunManager.State.keys()[_run.current_state], paused, _run.room.boss.health.current_health])


func _boss_input() -> void:
	for action: String in ["attack", "skill", "dodge", "move_forward", "move_backward"]:
		Input.action_release(action)
	var boss: SentinelController = _run.room.boss
	var toward: Vector3 = boss.position - _player.position
	toward.y = 0.0
	var distance: float = toward.length()
	toward = toward.normalized()
	_player.camera_controller.rotation.y = atan2(-toward.x, -toward.z)
	var state: String = _player.state_machine.get_state_name()
	var danger: bool = boss.brain.current_state in [EnemyBrain.State.TELEGRAPH, EnemyBrain.State.ATTACK]
	if danger:
		Input.action_press("move_backward")
		if distance < boss.brain.get_attack_definition().reach + 0.4 and _player.state_machine.cooldown_remaining <= 0.0:
			Input.action_press("dodge")
		return
	if state in ["Idle", "Move"]:
		Input.action_press("move_forward")
		var facing: bool = _player.get_facing_direction().dot(toward) > 0.95
		if facing and _player.combat.skill_cooldown_remaining <= 0.0 and distance < 4.7:
			Input.action_press("skill")
		elif facing and distance < 1.85:
			Input.action_press("attack")
	if state == "Attack" and _player.combat.current_attack != null:
		var id: int = _player.combat.hitbox.damage_info.attack_id
		if _player.combat.elapsed > _player.combat.current_attack.duration - 0.12 and id != _last_buffered_id:
			_last_buffered_id = id
			Input.action_press("attack")


func _on_boss_damage(_amount: int, _info: DamageInfo) -> void:
	_boss_damage_events += 1
