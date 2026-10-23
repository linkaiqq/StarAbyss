extends "res://tests/full_run_integration_test.gd"
## Continuous Forward+ rendering, real wall-clock samples and normal-stat input bot.
## Deliberately separate from the fast fixed-fps/disabled-render-loop regression suite.

var _phase: String = "warmup"
var _samples: Dictionary[String, Array] = {}
var _previous_frame_usec: int = 0
var _started_usec: int = 0
var _label: String = "latest"
var _rounds: int = 1
var _cooldown_frames: int = 0
var _peak_nodes: int = 0
var _peak_objects: int = 0
var _peak_video_mb: float = 0.0
var _nodes_at_start: Array[int] = []


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	if _previous_frame_usec == 0:
		_previous_frame_usec = now
		return false
	var wall_ms: float = float(now - _previous_frame_usec) / 1000.0
	_previous_frame_usec = now
	_peak_nodes = maxi(_peak_nodes, get_node_count())
	_peak_objects = maxi(_peak_objects, int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	_peak_video_mb = maxf(_peak_video_mb, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)
	if _cooldown_frames > 0:
		_cooldown_frames -= 1
		return false
	if _phase not in _samples:
		return false
	var viewport_rid: RID = root.get_viewport_rid()
	_samples[_phase].append([
		wall_ms,
		RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	])
	return false


func _test() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=").validate_filename()
		elif argument.begins_with("--rounds="):
			_rounds = clampi(argument.trim_prefix("--rounds=").to_int(), 1, 3)
	if DisplayServer.get_name() == "headless" or not RenderingServer.is_render_loop_enabled():
		push_error("Benchmark requires a graphical desktop and continuous rendering")
		quit(2)
		return
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = Vector2i(1920, 1080)
	root.grab_focus()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_started_usec = Time.get_ticks_usec()
	var menu: MainMenu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await create_timer(2.0).timeout
	_check(root.get_texture().get_size() == Vector2(1920, 1080), "actual continuously rendered framebuffer is 1920 by 1080")
	_samples["menu"] = []
	_phase = "menu"
	await create_timer(2.0).timeout
	_samples["initial_transition"] = []
	_phase = "initial_transition"
	await _start_from_menu()
	for round_number: int in range(1, _rounds + 1):
		_nodes_at_start.append(get_node_count())
		_set_phase("room_1_combat")
		await _fight(1)
		_phase = "modal"
		await _click_card("blessing_vitality")
		_set_phase("room_1_traversal")
		await _walk_to_exit(0)
		_set_phase("room_2_combat")
		await _fight(2)
		_phase = "modal"
		await _click_card("blessing_flame")
		_set_phase("room_2_traversal")
		await _walk_to_exit(1)
		_set_phase("boss_combat")
		await _fight_boss(round_number)
		_phase = "modal"
		_check(_run.current_state == RunManager.State.WON and _run.kills == 6 and _run.rooms_cleared == 3, "real-time round %d reaches complete victory" % round_number)
		if _run.current_state != RunManager.State.WON:
			break
		if round_number < _rounds:
			await _click_button("重新开始")
			await _ticks(20)
			_run = current_scene as RunManager
			_bind()
	var report: Dictionary = {
		"label": _label,
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_rendering_device().get_device_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"viewport": [root.size.x, root.size.y],
		"continuous_rendering": true,
		"vsync": "disabled",
		"max_fps": Engine.max_fps,
		"physics_hz": Engine.physics_ticks_per_second,
		"wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0,
		"rounds_requested": _rounds,
		"checks": _checks,
		"failures": _failures,
		"nodes_at_run_start": _nodes_at_start,
		"peak_nodes": _peak_nodes,
		"peak_objects": _peak_objects,
		"peak_video_memory_mb": _peak_video_mb,
		"phases": {},
		"limits": "Script bot; not human feel or physical-input acceptance. First 30 rendered frames per combat/traversal phase excluded, initial menu-to-game transition reported separately. CPU render timing excludes scripts. Performance process/physics/object/VRAM monitors may update up to one second late; their observed maxima are not per-frame percentiles. Build type is recorded in debug_build/editor_feature.",
		"debug_build": OS.is_debug_build(),
		"editor_feature": OS.has_feature("editor"),
	}
	for phase_name: String in _samples:
		report.phases[phase_name] = _summarize(_samples[phase_name])
	var destination: String = ProjectSettings.globalize_path("res://").path_join("../.local/validation/performance_" + _label + ".json")
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PERFORMANCE REPORT: " + destination)
	print(JSON.stringify(report.phases))
	_release()
	_phase = "cleanup"
	current_scene.queue_free()
	current_scene = null
	paused = false
	# Wall-clock wait, not SceneTreeTimer: under `--fixed-fps 60 --max-fps 0` a timer's
	# simulated 0.25 s can elapse in a couple of milliseconds of real time, which is not
	# long enough for the audio server to release finished playbacks. Every other fixture
	# waits on Time.get_ticks_msec() for the same reason, otherwise the process exits with
	# "resources still in use" and the check fails on an engine error line.
	var deadline: int = Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("PERFORMANCE RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _set_phase(value: String) -> void:
	_phase = value
	if not _samples.has(value):
		_samples[value] = []
	_cooldown_frames = 30


func _summarize(rows: Array) -> Dictionary:
	if rows.is_empty():
		return {"samples": 0}
	var wall: Array[float] = []
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var process: Array[float] = []
	var physics: Array[float] = []
	var draw_calls: Array[float] = []
	for row: Array in rows:
		wall.append(row[0])
		cpu.append(row[1])
		gpu.append(row[2])
		process.append(row[3])
		physics.append(row[4])
		draw_calls.append(row[5])
	wall.sort()
	cpu.sort()
	gpu.sort()
	process.sort()
	physics.sort()
	draw_calls.sort()
	var total_ms: float = 0.0
	var slow: int = 0
	for value: float in wall:
		total_ms += value
		if value > 1000.0 / 60.0:
			slow += 1
	return {
		"samples": rows.size(), "measured_seconds": total_ms / 1000.0,
		"mean_fps": 1000.0 * rows.size() / total_ms,
		"wall_ms_p50": _percentile(wall, 0.50), "wall_ms_p95": _percentile(wall, 0.95),
		"wall_ms_p99": _percentile(wall, 0.99), "wall_ms_max": wall[-1],
		"frames_over_16_67_ms_percent": 100.0 * slow / rows.size(),
		"cpu_render_ms_p95": _percentile(cpu, 0.95), "gpu_ms_p95": _percentile(gpu, 0.95),
		"process_monitor_ms_max_observed": process[-1], "physics_monitor_ms_max_observed": physics[-1],
		"draw_calls_p95": _percentile(draw_calls, 0.95),
	}


func _percentile(values: Array[float], fraction: float) -> float:
	return values[mini(values.size() - 1, int(ceil(fraction * values.size())) - 1)]


func _screenshot(_filename: String) -> void:
	# A natural frame is already drawn every iteration. Do not force extra draws
	# or read back pixels during timing; functional rendering has its own suite.
	await process_frame
