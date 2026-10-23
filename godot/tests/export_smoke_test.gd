extends SceneTree
## External PCK fixture. The shipped PCK excludes this file and all other tests.
## Official release templates disable path overrides, so use the same-version editor
## with --main-pack and this external script. Test release EXE startup separately.

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	root.grab_focus()
	_check(OS.has_feature("editor") and not Engine.is_editor_hint(), "designated same-version game runtime loads packed data for external fixture")
	_check(not FileAccess.file_exists("res://tests/combat_rules_test.gd"), "shipped pack excludes development tests")
	var menu_path: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	var menu: Control = (load(menu_path) as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _ticks(8)
	var start: Button = menu.find_child("StartRun", true, false) as Button
	_check(start != null and start.is_visible_in_tree(), "pack loads actual main menu and start button")
	await _pointer_click(start)
	await _ticks(20)
	var run: RunManager = current_scene as RunManager
	_check(run != null and run.room_index == 0, "actual menu click loads first room from PCK")
	if run == null:
		quit(1)
		return
	var player: PlayerController = run.player
	player.camera_controller.set_process_unhandled_input(false)
	_check(run.room.get_living_enemy_count() == 2 and player.health.current_health == 100, "pack starts with correct enemies and player health")
	# Fail fast: if the pack carries a script that does not parse (a package built while a
	# source file was mid-edit), the presentation node keeps existing but loses its script.
	# Without this guard the coroutine dies on the nil access below and the process never
	# reaches quit(), so the run hangs until the harness timeout instead of failing.
	var presentation: ActorPresentation = player.get_node_or_null("Visual/ActorPresentation") as ActorPresentation
	if presentation == null:
		_check(false, "packed-data runtime loads a parseable ActorPresentation script")
		print("EXPORT SMOKE RESULT: %d checks, %d failures" % [_checks, _failures])
		quit(1)
		return
	_check(presentation.skeleton != null and presentation.weapon_attachment.get_child_count() == 1, "pack loads imported skeleton and independent weapon")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "packed-data game window captures input")
	var before_move: Vector3 = player.position
	Input.action_press("move_forward")
	await _ticks(25)
	Input.action_release("move_forward")
	_check(player.position.distance_to(before_move) > 1.0, "packed-data runtime executes actual movement input")
	Input.action_press("skill")
	await _ticks(2)
	Input.action_release("skill")
	_check(player.combat.skill_cooldown_remaining > 0.0 and player.combat.is_skill, "packed-data runtime executes actual skill input")
	RenderingServer.force_draw(false)
	await process_frame
	var screenshot: Image = root.get_texture().get_image()
	_check(screenshot != null and not screenshot.is_empty(), "packed-data runtime renders an actual gameplay frame")
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if not user_args.is_empty():
		_check(screenshot.save_png(user_args[0]) == OK, "package gameplay screenshot saved")
	await _escape()
	_check(paused and run.current_state == RunManager.State.PAUSED, "packed-data Esc pauses the real run")
	var before_pause: float = run.elapsed
	await _ticks(10)
	_check(is_equal_approx(run.elapsed, before_pause), "paused package does not advance run clock")
	await _click_button(run.ui, "重新开始")
	await _ticks(20)
	run = current_scene as RunManager
	_check(run.player.health.current_health == 100 and run.kills == 0 and run.blessings.acquired.is_empty(), "package restart clears run data")
	await _escape()
	await _click_button(run.ui, "返回主菜单")
	await _ticks(8)
	_check(current_scene is MainMenu and not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "package can return to clean main menu")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("EXPORT SMOKE RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _click_button(container: Node, text: String) -> void:
	for child: Node in container.find_children("*", "Button", true, false):
		var button: Button = child as Button
		if button.text == text and button.is_visible_in_tree():
			await _pointer_click(button)
			return
	_check(false, "package button is visible: " + text)


func _pointer_click(button: Button) -> void:
	await _ticks(2)
	var point: Vector2 = button.get_global_rect().get_center()
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
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


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print(("PASS: " if condition else "FAIL: ") + label)
