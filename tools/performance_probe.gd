extends "res://tests/performance_benchmark.gd"
## Dev-only performance probe. Not referenced by any scene, resource or autoload,
## and it lives outside res:// so it can never be exported into a build.
##
## It reuses the real-combat benchmark flow of res://tests/performance_benchmark.gd
## (real menu click, real input bot, real physics, continuous Forward+ rendering)
## but adds what the shipped benchmark cannot do without editing tests/:
##   * a parameterised render resolution, so 1280x720 and 1920x1080 both have data;
##   * a frame cap, so frame-time spread can be measured at the shipped 60 FPS cap;
##   * extra per-frame engine monitors (primitives, draw calls, node/resource/object
##     counts, static memory, video memory) reported per phase.
##
## Run from the project root (a real desktop window is opened, do not touch it):
##   Godot_v4.7.2-stable_win64_console.exe --path godot --disable-vsync \
##       --script ../tools/performance_probe.gd -- --label=720p60 \
##       --resolution=1280x720 --fps=60 --rounds=1
##
## Report: .local/validation/performance_probe_<label>.json

const PROBE_EXCLUDED_FRAMES: int = 30

var _probe_resolution: Vector2i = Vector2i(1920, 1080)
var _probe_frame_cap: int = 0
var _probe_rows: Dictionary[String, Array] = {}
var _probe_cooldown: int = 0
var _probe_mode: String = "run"
var _probe_stretch_disabled: bool = false
## 0 = run the whole flow. 2 = stop right after room_2_combat is measured, which is
## what an A/B on a single phase needs (same code path, shorter wall clock).
var _probe_stop_room: int = 0


func _process(delta: float) -> bool:
	var keep_running: bool = super._process(delta)
	_sample_monitors()
	return keep_running


func _set_phase(value: String) -> void:
	super._set_phase(value)
	if not _probe_rows.has(value):
		_probe_rows[value] = []
	_probe_cooldown = PROBE_EXCLUDED_FRAMES


func _sample_monitors() -> void:
	if _probe_cooldown > 0:
		_probe_cooldown -= 1
		return
	if not _probe_rows.has(_phase):
		return
	_probe_rows[_phase].append([
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	])


func _test() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=").validate_filename()
		elif argument.begins_with("--rounds="):
			_rounds = clampi(argument.trim_prefix("--rounds=").to_int(), 1, 3)
		elif argument.begins_with("--resolution="):
			var parts: PackedStringArray = argument.trim_prefix("--resolution=").split("x", false)
			if parts.size() == 2:
				_probe_resolution = Vector2i(maxi(320, parts[0].to_int()), maxi(180, parts[1].to_int()))
		elif argument.begins_with("--fps="):
			_probe_frame_cap = maxi(0, argument.trim_prefix("--fps=").to_int())
		elif argument.begins_with("--mode="):
			_probe_mode = argument.trim_prefix("--mode=").validate_filename()
		elif argument.begins_with("--stretch="):
			_probe_stretch_disabled = argument.trim_prefix("--stretch=") == "off"
		elif argument.begins_with("--stop-after-room="):
			_probe_stop_room = maxi(0, argument.trim_prefix("--stop-after-room=").to_int())
	if DisplayServer.get_name() == "headless" or not RenderingServer.is_render_loop_enabled():
		push_error("Performance probe requires a graphical desktop and continuous rendering")
		quit(2)
		return
	Engine.max_fps = _probe_frame_cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.size = _probe_resolution
	if _probe_stretch_disabled:
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.content_scale_size = _probe_resolution
	root.grab_focus()
	await process_frame
	await process_frame
	if _probe_mode == "info":
		# Load the real main menu so the captured frame is presentable content (UI text
		# sharpness is the human-visible symptom if the framebuffer is really smaller).
		var info_menu: MainMenu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
		root.add_child(info_menu)
		current_scene = info_menu
		await create_timer(0.75).timeout
		# Second sample disables the project's canvas_items stretch to show whether a
		# shrink in root_texture_size comes from stretching or from the real swapchain.
		var stretched: Dictionary = _resolution_info("canvas_items")
		root.content_scale_size = _probe_resolution
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		await create_timer(0.5).timeout
		var unscaled: Dictionary = _resolution_info("no_stretch")
		print("PERFORMANCE PROBE INFO: " + JSON.stringify({"shipped_stretch": stretched, "stretch_disabled": unscaled}, "\t"))
		quit(0)
		return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	_started_usec = Time.get_ticks_usec()
	var menu: MainMenu = (load("res://scenes/ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await create_timer(2.0).timeout
	var resolution: Dictionary = _resolution_info()
	_check(Vector2i(int(resolution.display_server_window_size[0]), int(resolution.display_server_window_size[1])) == _probe_resolution, "actual continuously rendered window is %d by %d" % [_probe_resolution.x, _probe_resolution.y])
	_samples["menu"] = []
	_probe_rows["menu"] = []
	_probe_cooldown = PROBE_EXCLUDED_FRAMES
	_phase = "menu"
	await create_timer(2.0).timeout
	_samples["initial_transition"] = []
	_probe_rows["initial_transition"] = []
	_probe_cooldown = PROBE_EXCLUDED_FRAMES
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
		if _probe_stop_room == 2:
			_phase = "modal"
			break
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
		"probe": "tools/performance_probe.gd",
		"engine": Engine.get_version_info(),
		"os": OS.get_name(),
		"cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_rendering_device().get_device_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"requested_resolution": [_probe_resolution.x, _probe_resolution.y],
		"resolution": resolution,
		"stretch": "disabled" if _probe_stretch_disabled else "shipped canvas_items",
		"frame_cap": Engine.max_fps,
		"vsync": "disabled",
		"physics_hz": Engine.physics_ticks_per_second,
		"continuous_rendering": true,
		"wall_seconds": float(Time.get_ticks_usec() - _started_usec) / 1000000.0,
		"rounds_requested": _rounds,
		"checks": _checks,
		"failures": _failures,
		"peak_nodes": _peak_nodes,
		"peak_objects": _peak_objects,
		"peak_video_memory_mb": _peak_video_mb,
		"phases": {},
		"phase_monitors": {},
		"debug_build": OS.is_debug_build(),
		"editor_feature": OS.has_feature("editor"),
		"limits": "Script bot; not human feel or physical-input acceptance. First 30 rendered frames per phase excluded; modal (paused) phases are not sampled. frame_cap 0 means uncapped throughput measurement, >0 means the shipped FPS cap with vsync disabled. Engine monitors may update up to one second late; their observed maxima are not per-frame percentiles. Editor build includes debug checks, so numbers are a conservative lower bound versus an export build.",
	}
	for phase_name: String in _samples:
		report.phases[phase_name] = _summarize(_samples[phase_name])
	for phase_name: String in _probe_rows:
		report.phase_monitors[phase_name] = _summarize_monitors(_probe_rows[phase_name])
	var destination: String = ProjectSettings.globalize_path("res://").path_join("../.local/validation/performance_probe_" + _label + ".json")
	var file: FileAccess = FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PERFORMANCE PROBE REPORT: " + destination)
	print("PERFORMANCE PROBE PHASES: " + JSON.stringify(report.phases))
	print("PERFORMANCE PROBE MONITORS: " + JSON.stringify(report.phase_monitors))
	_release()
	_phase = "cleanup"
	current_scene.queue_free()
	current_scene = null
	paused = false
	await create_timer(0.25).timeout
	print("PERFORMANCE PROBE RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _resolution_info(tag: String = "") -> Dictionary:
	var screen_index: int = DisplayServer.window_get_current_screen()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var decorated_size: Vector2i = DisplayServer.window_get_size_with_decorations()
	var root_texture: Vector2i = root.get_texture().get_size()
	var visible_rect: Vector2 = root.get_visible_rect().size
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_index)
	# The saved image is the framebuffer that is actually presented to the display:
	# this settles "window size vs render resolution" without guessing. force_draw()
	# first so the captured image is the drawn frame, not a stale/blank canvas.
	var image_size: Vector2i = Vector2i.ZERO
	RenderingServer.force_draw()
	var image: Image = root.get_texture().get_image()
	if image != null:
		image_size = image.get_size()
		var suffix: String = "_" + tag if tag != "" else ""
		image.save_png(ProjectSettings.globalize_path("res://").path_join(
			"../.local/validation/probe_presented_%dx%d%s.png" % [_probe_resolution.x, _probe_resolution.y, suffix]))
	return {
		"requested": [_probe_resolution.x, _probe_resolution.y],
		"root_size": [root.size.x, root.size.y],
		"display_server_window_size": [window_size.x, window_size.y],
		"display_server_window_size_with_decorations": [decorated_size.x, decorated_size.y],
		"root_texture_size": [root_texture.x, root_texture.y],
		"presented_image_size": [image_size.x, image_size.y],
		"root_visible_rect": [int(visible_rect.x), int(visible_rect.y)],
		"content_scale_size": [root.content_scale_size.x, root.content_scale_size.y],
		"content_scale_mode": root.content_scale_mode,
		"content_scale_stretch": root.content_scale_stretch,
		"content_scale_factor": root.content_scale_factor,
		"allow_hidpi_setting": ProjectSettings.get_setting("display/window/dpi/allow_hidpi", "<unset>"),
		"screen_size": [screen_size.x, screen_size.y],
		"screen_scale": DisplayServer.screen_get_scale(screen_index),
		"screen_dpi": DisplayServer.screen_get_dpi(screen_index),
		"screen_max_scale": DisplayServer.screen_get_max_scale(),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(screen_index),
	}


func _summarize_monitors(rows: Array) -> Dictionary:
	if rows.is_empty():
		return {"samples": 0}
	var names: PackedStringArray = PackedStringArray([
		"primitives", "draw_calls", "nodes", "resources", "objects", "static_memory_mb", "video_memory_mb",
	])
	var columns: Array[Array] = []
	for index: int in range(names.size()):
		columns.append([])
	for row: Array in rows:
		for index: int in range(names.size()):
			(columns[index] as Array).append(float(row[index]))
	var summary: Dictionary = {"samples": rows.size()}
	for index: int in range(names.size()):
		var values: Array[float] = []
		for value: float in columns[index]:
			values.append(value)
		values.sort()
		var total: float = 0.0
		for value: float in values:
			total += value
		summary[names[index]] = {
			"mean": total / values.size(),
			"p95": _percentile(values, 0.95),
			"max": values[-1],
		}
	return summary
