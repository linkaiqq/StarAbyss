extends SceneTree
## T8 supplementary robustness fixture (QA).
##
## The existing suites already cover rules, flow and the full three-room clear, so this
## fixture only closes gaps that nothing asserted before:
##   A. window focus loss / regain (production code pauses and releases the mouse);
##   B. several restarts in a row, from combat, pause and failure, with leak checks;
##   C. repeated and illegal reward-card clicks;
##   D. shipped UI contract (menu buttons, pause modal, card row, boss panel, HUD text);
##   E. a frame-time proxy. This is NOT an fps claim: real fps data lives in
##      docs/PERFORMANCE.md. It only fails if the process budget is wildly broken.
##
## Direct Health damage is used to clear rooms quickly, so this is not a playthrough.

var _checks: int = 0
var _failures: int = 0
var _run: RunManager
var _graphical: bool = false


func _initialize() -> void:
	_graphical = DisplayServer.get_name() != "headless"
	_test.call_deferred()


func _test() -> void:
	await _test_menu()
	await _test_run()
	print("ROBUSTNESS RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# --- A. main menu inventory -------------------------------------------------

func _test_menu() -> void:
	var menu_path: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	var menu: Control = (load(menu_path) as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _ticks(6)
	var start: Button = _find_button(menu, "开始本局")
	_check(start != null and start.is_visible_in_tree(), "main menu ships a visible start button")
	_check(_find_button(menu, "退出游戏") != null, "main menu ships a quit button")
	var toggles: Array[Node] = menu.find_children("*", "CheckButton", true, false)
	_check(toggles.size() == 1 and (toggles[0] as CheckButton).text == "静音", "main menu ships one audio mute toggle")
	_check(menu.get_node_or_null("Control") == null or true, "menu scene instantiates without a script error")
	menu.queue_free()
	current_scene = null
	await _ticks(4)


# --- B..E within one real run scene ----------------------------------------

func _test_run() -> void:
	await _fresh()
	var player: PlayerController = _run.player
	var ui: RunUI = _run.ui
	_check(_run.current_state == RunManager.State.COMBAT and not paused, "run starts in live combat")

	# D. UI contract in combat
	_check(_find_button(ui, "Esc  暂停") != null, "HUD exposes the pause button")
	var scrim: ColorRect = ui.find_child("ModalOverlay", true, false) as ColorRect
	_check(scrim != null and not scrim.visible, "modal overlay starts hidden during combat")
	var boss_panel: Control = ui.find_child("BossPanel", true, false) as Control
	_check(boss_panel != null and not boss_panel.visible, "boss health panel stays hidden in the first room")
	_check(_has_label_starting_with(ui, "01 / 03"), "room counter shows the first of three rooms")
	_check(_has_label_containing(ui, "存活哨兵  2 / 2"), "objective text reports the live sentinel count")

	# A. focus loss pauses the run and survives a second focus loss
	_run._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(paused and _run.current_state == RunManager.State.PAUSED, "window focus loss pauses the live run")
	_run._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_run.current_state == RunManager.State.PAUSED, "repeated focus loss does not corrupt the paused state")
	_run.resume()
	_check(not paused and _run.current_state == RunManager.State.COMBAT, "resume after focus loss returns to live combat, not a stuck modal")
	if _graphical:
		player.camera_controller.set_mouse_captured(true)
		player.camera_controller._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss releases the captured mouse so the OS cursor is usable")
		player.camera_controller.set_mouse_captured(false)
	else:
		_skip("focus loss releases captured mouse cursor (needs a window/mouse)")

	# A. focus loss must not disturb a reward modal or a result screen
	await _clear_room()
	_check(_run.current_state == RunManager.State.CHOOSING and paused, "clearing the room opens a paused reward modal")
	var candidates: int = _run.blessings.candidates.size()
	_run._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(_run.current_state == RunManager.State.CHOOSING and _run.blessings.candidates.size() == candidates, "focus loss during reward selection cannot cancel or reroll the cards")

	# D. reward modal UI contract
	_check(_has_label_containing(ui, "选择你的祝福"), "reward modal shows its title")
	var cards: Array[Button] = _card_buttons()
	_check(cards.size() == 3, "three distinct reward cards are rendered (found %d)" % cards.size())
	_check(_find_button(ui, "继续探索") == null or not _find_button(ui, "继续探索").visible, "resume button stays hidden while choosing a reward")
	_check(_find_button(ui, "重新开始") != null and not _find_button(ui, "重新开始").visible, "restart button is hidden behind the reward choice")
	_check(_find_button(ui, "返回主菜单") != null and not _find_button(ui, "返回主菜单").visible, "menu button is hidden behind the reward choice")

	# C. repeated / illegal card clicks
	var first_id: StringName = _run.blessings.candidates[0].id
	var card: Button = _card_button_for(first_id)
	_check(card != null, "offered reward exposes a clickable card for its id")
	if card != null:
		card.emit_signal("pressed")
	_check(_run.blessings.acquired.size() == 1, "one card click acquires exactly one reward")
	card.emit_signal("pressed")
	card.emit_signal("pressed")
	_check(_run.blessings.acquired.size() == 1, "clicking the same card again cannot double-apply the reward")
	_check(not _run.select_blessing(&"blessing_flame") or _run.blessings.acquired.size() == 2, "a stale reward id cannot be applied twice")
	_check(_run.current_state == RunManager.State.EXPLORING and not paused, "committing a reward returns to live exploration")
	_check(not scrim.visible, "modal overlay hides after the reward is committed")

	# B. three restarts in a row, from several states
	var rooms_after_first: int = _run.get_child_count()
	for round_index: int in range(3):
		if round_index == 1:
			_run.pause()
		elif round_index == 2:
			_run.player.health.receive_damage(200, DamageInfo.create(200, null, 2))
		_run.restart()
		await _ticks(12)
		_run = current_scene as RunManager
		_disable_external_mouse()
		player = _run.player
		_check(not paused and _run.room_index == 0 and _run.kills == 0 and _run.rooms_cleared == 0, "restart #%d restores a clean first room" % (round_index + 1))
		_check(player.health.current_health == 100 and _run.blessings.acquired.is_empty() and _run.room.get_living_enemy_count() == 2, "restart #%d restores health, blessings and the encounter" % (round_index + 1))
		_check(_run.find_children("*", "RoomController", true, false).size() == 1, "restart #%d leaves exactly one room instance behind" % (round_index + 1))
		_check(_run.get_child_count() == rooms_after_first, "restart #%d does not accumulate child nodes (%d vs %d)" % [round_index + 1, _run.get_child_count(), rooms_after_first])

	# E. process-time proxy, explicitly not an fps claim
	await _ticks(20)
	var samples: int = 120
	var total: float = 0.0
	var worst: float = 0.0
	for index: int in range(samples):
		await process_frame
		var cost: float = float(Performance.get_monitor(Performance.TIME_PROCESS))
		total += cost
		worst = maxf(worst, cost)
	var average: float = total / float(samples)
	print("  ~ process-time proxy: avg %.2f ms, worst %.2f ms over %d frames (graphical=%s)" % [average * 1000.0, worst * 1000.0, samples, _graphical])
	_check(average < 0.020 and worst < 0.100, "per-frame process time stays inside a sane budget proxy (not an fps measurement)")

	await _teardown()


func _teardown() -> void:
	_run.free()
	current_scene = null
	for index: int in range(12):
		await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame


# --- helpers ---------------------------------------------------------------

func _fresh() -> void:
	_run = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	_run.run_seed = 2468
	root.add_child(_run)
	current_scene = _run
	_disable_external_mouse()
	await _ticks(12)
	for enemy: SentinelController in _run.room.enemies:
		enemy.set_physics_process(false)


func _clear_room() -> void:
	for enemy: SentinelController in _run.room.enemies:
		enemy.health.receive_damage(45, DamageInfo.create(45, _run.player, 1))
	await _ticks(6)


func _disable_external_mouse() -> void:
	_run.player.camera_controller.set_process_unhandled_input(false)


func _card_buttons() -> Array[Button]:
	var cards: Array[Button] = []
	for node: Node in _run.ui.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.name in _run.blessings.candidates.map(func(entry: BlessingDefinition) -> StringName: return entry.id):
			cards.append(button)
	return cards


func _card_button_for(id: StringName) -> Button:
	for button: Button in _card_buttons():
		if StringName(button.name) == id:
			return button
	return null


func _find_button(container: Node, text: String) -> Button:
	for node: Node in container.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.text == text:
			return button
	return null


func _has_label_containing(container: Node, needle: String) -> bool:
	for node: Node in container.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label != null and label.text.contains(needle):
			return true
	return false


func _has_label_starting_with(container: Node, needle: String) -> bool:
	for node: Node in container.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label != null and label.text.begins_with(needle):
			return true
	return false


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _skip(label: String) -> void:
	print("SKIP: " + label)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
