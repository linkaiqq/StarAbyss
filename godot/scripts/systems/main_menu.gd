class_name MainMenu
extends Control
## Title view and a scene transition. No run data survives outside the run scene.

var _starting: bool = false
var _audio: AudioStreamPlayer


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# P7: menu feedback only. Created in code so the menu scene file is untouched.
	_audio = AudioStreamPlayer.new()
	_audio.name = "MenuAudio"
	_audio.bus = &"UI"
	_audio.volume_db = -4.0
	add_child(_audio)
	var background: ColorRect = ColorRect.new()
	background.color = Color("081520")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	# Native geometry keeps the title usable without external or P6 art dependencies.
	var motif: Control = Control.new()
	motif.name = "CrystalMotif"
	motif.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	motif.mouse_filter = Control.MOUSE_FILTER_IGNORE
	motif.draw.connect(_draw_crystal.bind(motif))
	add_child(motif)
	var layout: MarginContainer = MarginContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("margin_left", 150)
	layout.add_theme_constant_override("margin_right", 150)
	layout.add_theme_constant_override("margin_top", 110)
	layout.add_theme_constant_override("margin_bottom", 90)
	add_child(layout)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 20)
	layout.add_child(rows)
	_label(rows, "S T A R   A B Y S S", 24, Color("6ee8d2"))
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(spacer)
	_label(rows, "星渊遗迹", 96, Color("e3eef4"))
	_label(rows, "黎明之前，重封晶核；孤身入渊，与旧誓一战。", 28, Color("a5bccb"))
	_label(rows, "两间哨兵试炼  /  两次祝福选择  /  一场晶核决战", 21, Color("7196a9"))
	var start: Button = _button(rows, "开始本局", start_game)
	start.name = "StartRun"
	start.grab_focus()
	_button(rows, "退出游戏", _quit_game)
	var mute: CheckButton = CheckButton.new()
	mute.name = "MuteAudio"
	mute.text = "静音"
	mute.button_pressed = AudioServer.is_bus_mute(0)
	mute.add_theme_font_size_override("font_size", 22)
	mute.toggled.connect(func(muted: bool) -> void: AudioServer.set_bus_mute(0, muted))
	mute.toggled.connect(func(_muted: bool) -> void: _play_menu_cue(&"ui_confirm"))
	mute.mouse_entered.connect(func() -> void: _play_menu_cue(&"ui_hover"))
	rows.add_child(mute)
	var lower_spacer: Control = Control.new()
	lower_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(lower_spacer)
	_label(rows, "WASD 移动  ·  鼠标转镜头  ·  左键剑击  ·  E 星刃斩  ·  Shift 闪避", 22, Color("a5bccb"))
	_label(rows, "Space 跳跃  ·  Esc 暂停  /  每局重新开始，祝福与进度不保留", 20, Color("7196a9"))


func start_game() -> void:
	if _starting:
		return
	_starting = true
	var error: Error = get_tree().change_scene_to_file("res://scenes/levels/game_run.tscn")
	if error != OK:
		_starting = false
		push_error("Failed to start run: " + error_string(error))


## P7 menu feedback. Purely additive: no menu state, layout or flow is touched.
func _play_menu_cue(cue: StringName) -> void:
	if not is_instance_valid(_audio):
		return
	var stream: AudioStreamWAV = AudioCues.get_cue(cue)
	if stream == null:
		return
	_audio.stop()
	_audio.stream = stream
	_audio.volume_db = -4.0 + AudioCues.get_gain(cue)
	_audio.play()


func _quit_game() -> void:
	get_tree().quit()


func _label(parent: Node, text: String, size: int, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(370, 72)
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.add_theme_font_size_override("font_size", 28)
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.bg_color = Color("173b48")
	normal.border_color = Color("397568")
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(8)
	button.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("256170")
	hover.border_color = Color("6ee8d2")
	button.add_theme_stylebox_override("hover", hover)
	button.mouse_entered.connect(func() -> void: _play_menu_cue(&"ui_hover"))
	button.pressed.connect(func() -> void: _play_menu_cue(&"ui_confirm"))
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _draw_crystal(canvas: Control) -> void:
	var center: Vector2 = Vector2(1440, 500)
	var diamond: PackedVector2Array = PackedVector2Array([center + Vector2(0, -260), center + Vector2(165, 0), center + Vector2(0, 260), center + Vector2(-165, 0)])
	canvas.draw_colored_polygon(diamond, Color("0d3545"))
	canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("3b9f9b"), 3, true)
	canvas.draw_line(diamond[0], diamond[2], Color("245b6b"), 2, true)
	canvas.draw_line(diamond[3], diamond[1], Color("245b6b"), 2, true)
	canvas.draw_arc(center, 330, 0, TAU, 96, Color("163848"), 2, true)
