class_name RunUI
extends CanvasLayer
## Signal-driven view. Buttons request actions; RunManager owns every transition.

const INK: Color = Color("dce8ef")
const MUTED: Color = Color("9bb3c2")
const CYAN: Color = Color("6ee8d2")
var _run: RunManager
var _health: Label
var _health_bar: ProgressBar
var _room: Label
var _objective: Label
var _stats: Label
var _collection: Label
var _skill: Label
var _dodge: Label
var _dodge_confirm: Label
var _dodge_confirm_timer: Timer
var _onboarding: Label
var _onboarding_timer: Timer
var _shown_combat_hint: bool = false
var _shown_heavy_hit_hint: bool = false
var _scrim: ColorRect
var _modal: VBoxContainer
var _card_row: HBoxContainer
var _restart: Button
var _resume: Button
var _title: Label
var _subtitle: Label
var _summary: Label
var _menu: Button
var _boss_panel: PanelContainer
var _boss_health: Label
var _boss_bar: ProgressBar
var _boss_action: Label
var _audio_toggle: CheckButton


func bind_run(run: RunManager) -> void:
	_run = run
	_build()
	run.state_changed.connect(_on_state_changed)
	run.progress_changed.connect(_on_progress_changed)
	run.clock_changed.connect(_on_clock_changed)
	run.blessings.collection_changed.connect(_on_collection_changed)
	run.blessings.candidates_offered.connect(_on_candidates)
	run.player.health.health_changed.connect(_on_health_changed)
	run.player.health.blocked.connect(_on_player_blocked)
	run.player.health.damaged.connect(_on_player_damaged)
	run.player.telemetry_updated.connect(_on_telemetry)
	run.boss_health_changed.connect(_on_boss_health_changed)
	run.boss_action_changed.connect(_on_boss_action_changed)
	_on_health_changed(run.player.health.current_health, run.player.health.max_health)
	_on_collection_changed()
	_on_clock_changed(0.0)
	_on_telemetry("", 0.0, 0.0)


func _build() -> void:
	var screen: Control = Control.new()
	screen.name = "Screen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var hp_panel: PanelContainer = _panel(screen, Vector2(36, 32), Vector2(350, 146))
	var hp_rows: VBoxContainer = _rows(hp_panel)
	_label(hp_rows, "STAR ABYSS   /   遗迹探索者", 18, CYAN)
	_health = _label(hp_rows, "", 30, INK)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(0, 12)
	_health_bar.show_percentage = false
	_health_bar.add_theme_stylebox_override("background", _style(Color("273d49")))
	_health_bar.add_theme_stylebox_override("fill", _style(CYAN))
	hp_rows.add_child(_health_bar)
	var room_panel: PanelContainer = _panel(screen, Vector2(-360, 32), Vector2(720, 116))
	room_panel.anchor_left = 0.5
	room_panel.anchor_right = 0.5
	var room_rows: VBoxContainer = _rows(room_panel)
	_room = _label(room_rows, "", 27, INK)
	_room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective = _label(room_rows, "", 20, CYAN)
	_objective.name = "ObjectiveText"
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# ONB-2/ONB-3 hints live in their own label. _objective is never rewritten: its text is
	# locked by robustness_test.gd ("存活哨兵  2 / 2"), so onboarding must not touch it.
	_onboarding = _label(room_rows, "", 18, MUTED)
	_onboarding.name = "OnboardingHint"
	_onboarding.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_onboarding.visible = false
	_onboarding_timer = Timer.new()
	_onboarding_timer.name = "OnboardingHintTimer"
	_onboarding_timer.one_shot = true
	add_child(_onboarding_timer)
	_onboarding_timer.timeout.connect(_on_onboarding_elapsed)
	_boss_panel = _panel(screen, Vector2(-380, 166), Vector2(760, 126))
	_boss_panel.name = "BossPanel"
	_boss_panel.anchor_left = 0.5
	_boss_panel.anchor_right = 0.5
	var boss_rows: VBoxContainer = _rows(_boss_panel)
	_boss_health = _label(boss_rows, "晶核守卫", 25, Color("ffb276"))
	_boss_health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(0, 12)
	_boss_bar.show_percentage = false
	_boss_bar.add_theme_stylebox_override("background", _style(Color("273d49")))
	_boss_bar.add_theme_stylebox_override("fill", _style(Color("ed8760")))
	boss_rows.add_child(_boss_bar)
	_boss_action = _label(boss_rows, "", 20, MUTED)
	_boss_action.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_panel.hide()
	var pause_button: Button = _button(screen, "Esc  暂停", _on_pause_pressed)
	pause_button.anchor_left = 1.0
	pause_button.anchor_right = 1.0
	pause_button.position = Vector2(-204, 32)
	pause_button.size = Vector2(168, 52)
	var collection_panel: PanelContainer = _panel(screen, Vector2(36, -158), Vector2(610, 122))
	collection_panel.anchor_top = 1.0
	collection_panel.anchor_bottom = 1.0
	var collection_rows: VBoxContainer = _rows(collection_panel)
	_collection = _label(collection_rows, "", 21, INK)
	_stats = _label(collection_rows, "", 17, MUTED)
	_label(collection_rows, "WASD 移动  ·  左键剑击  ·  E 星刃斩  ·  Shift 闪避  ·  Space 跳跃  ·  鼠标转镜头", 17, MUTED)
	var skills: PanelContainer = _panel(screen, Vector2(-400, -158), Vector2(364, 122))
	skills.anchor_left = 1.0
	skills.anchor_right = 1.0
	skills.anchor_top = 1.0
	skills.anchor_bottom = 1.0
	var skill_rows: VBoxContainer = _rows(skills)
	_skill = _label(skill_rows, "", 24, CYAN)
	_dodge = _label(skill_rows, "", 24, INK)
	_label(skill_rows, "留意橙色预警，红色区域生效", 17, MUTED)
	_dodge_confirm = _label(screen, "", 26, CYAN)
	_dodge_confirm.name = "DodgeConfirm"
	_dodge_confirm.position = Vector2(-400, -204)
	_dodge_confirm.size = Vector2(364, 38)
	_dodge_confirm.anchor_left = 1.0
	_dodge_confirm.anchor_right = 1.0
	_dodge_confirm.anchor_top = 1.0
	_dodge_confirm.anchor_bottom = 1.0
	_dodge_confirm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dodge_confirm.visible = false
	_dodge_confirm_timer = Timer.new()
	_dodge_confirm_timer.name = "DodgeConfirmTimer"
	_dodge_confirm_timer.one_shot = true
	_dodge_confirm_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_dodge_confirm_timer)
	_dodge_confirm_timer.timeout.connect(_on_dodge_confirm_elapsed)
	_scrim = ColorRect.new()
	_scrim.name = "ModalOverlay"
	_scrim.color = Color(0.015, 0.035, 0.065, 0.94)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(_scrim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.add_child(center)
	_modal = VBoxContainer.new()
	_modal.custom_minimum_size = Vector2(1160, 0)
	_modal.add_theme_constant_override("separation", 24)
	center.add_child(_modal)
	var brand: Label = _label(_modal, "S T A R   A B Y S S   /   星 渊 遗 迹", 19, CYAN)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title = _label(_modal, "", 52, INK)
	_title.name = "ModalTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle = _label(_modal, "", 23, MUTED)
	_subtitle.name = "ModalSubtitle"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_row = HBoxContainer.new()
	_card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_row.add_theme_constant_override("separation", 24)
	_modal.add_child(_card_row)
	_summary = _label(_modal, "", 24, INK)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	_modal.add_child(buttons)
	_resume = _button(buttons, "继续探索", _on_resume_pressed)
	_resume.custom_minimum_size = Vector2(250, 64)
	_restart = _button(buttons, "重新开始", _on_restart_pressed)
	_restart.custom_minimum_size = Vector2(250, 64)
	_menu = _button(buttons, "返回主菜单", _on_menu_pressed)
	_menu.custom_minimum_size = Vector2(250, 64)
	_audio_toggle = CheckButton.new()
	_audio_toggle.name = "MuteAudio"
	_audio_toggle.text = "静音"
	_audio_toggle.add_theme_font_size_override("font_size", 22)
	_audio_toggle.button_pressed = AudioServer.is_bus_mute(0)
	_audio_toggle.toggled.connect(func(muted: bool) -> void: AudioServer.set_bus_mute(0, muted))
	_audio_toggle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_modal.add_child(_audio_toggle)
	_scrim.hide()


func _on_state_changed(state: RunManager.State) -> void:
	var choosing: bool = state == RunManager.State.CHOOSING
	_scrim.visible = state in [RunManager.State.PAUSED, RunManager.State.CHOOSING, RunManager.State.FAILED, RunManager.State.STAGE_COMPLETE, RunManager.State.WON]
	_card_row.visible = choosing
	_summary.visible = not choosing
	_resume.visible = state == RunManager.State.PAUSED
	_restart.visible = not choosing
	_menu.visible = not choosing
	_audio_toggle.visible = not choosing
	_audio_toggle.set_pressed_no_signal(AudioServer.is_bus_mute(0))
	match state:
		RunManager.State.COMBAT:
			# ONB-2: once per run, on the first live combat, spell out what a dodge actually is.
			if not _shown_combat_hint:
				_shown_combat_hint = true
				_show_onboarding("Shift 闪避 0.45 秒 · 无敌只有 0.10–0.30 秒 · 冷却 1.2 秒", 6.0)
		RunManager.State.CHOOSING:
			_title.text = "选择你的祝福"
			_subtitle.text = "第 %d 房已清除 · 战斗已暂停 · 选择后穿过出口继续" % (_run.room_index + 1)
			# ONB-4: answer "第 3 个祝福去哪了" before it is asked (first pick of the run).
			if _run.blessings.acquired.is_empty():
				_subtitle.text += "\n本局祝福只能选 2 次（这是第 1 次）"
		RunManager.State.PAUSED:
			_title.text = "探索已暂停"
			_subtitle.text = "战斗、冷却与本局计时已冻结"
			_resume.grab_focus()
		RunManager.State.FAILED:
			_title.text = "探索者已倒下"
			_subtitle.text = _failed_cause_text()
			_restart.grab_focus()
		RunManager.State.STAGE_COMPLETE:
			_title.text = "抵达晶核封印"
			_subtitle.text = "普通试炼完成 · 你已清除遗迹前庭与星辉回廊"
			_restart.grab_focus()
		RunManager.State.WON:
			_title.text = "晶核已稳定"
			_subtitle.text = "结界在黎明时分平息了遗迹的侵蚀。"
			_restart.grab_focus()
	_on_progress_changed()


## Failure attribution (GAMEPLAY_DESIGN §5.8 G-07): which move, how much health was left and
## how far the run got. The cause string is produced by RunManager from the existing
## DamageInfo + the attacker's own Resource names, so the UI adds no new coupling.
func _failed_cause_text() -> String:
	var progress: String = "倒在第 %d 房 / 共 %d 房 · 剩余生命 %d / %d" % [
		_run.room_index + 1, _run.rooms.size(),
		_run.player.health.current_health, _run.player.health.max_health]
	var closing: String = "黎明未至 · 再入星渊，皆从头。"
	if _run.last_hit_summary.is_empty():
		return "%s\n%s" % [closing, progress]
	return "%s\n最后一击：%s\n%s" % [closing, _run.last_hit_summary, progress]


func _on_candidates(candidates: Array[BlessingDefinition]) -> void:
	for child: Node in _card_row.get_children():
		_card_row.remove_child(child)
		child.queue_free()
	for blessing: BlessingDefinition in candidates:
		var card: Button = Button.new()
		card.name = String(blessing.id)
		card.custom_minimum_size = Vector2(346, 342)
		card.add_theme_stylebox_override("normal", _style(Color("102633"), blessing.color))
		card.add_theme_stylebox_override("hover", _style(Color("1e3c4a"), blessing.color))
		card.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CYAN))
		card.pressed.connect(_on_card_pressed.bind(blessing.id))
		_card_row.add_child(card)
		var content: VBoxContainer = VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 26
		content.offset_top = 28
		content.offset_right = -26
		content.offset_bottom = -28
		content.add_theme_constant_override("separation", 20)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		_label(content, blessing.icon, 46, blessing.color)
		_label(content, blessing.display_name, 30, INK)
		var description: Label = _label(content, blessing.description, 22, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_label(content, "点击选择   →", 19, blessing.color)
	if _card_row.get_child_count() > 0:
		(_card_row.get_child(0) as Button).grab_focus()


func _on_progress_changed() -> void:
	if _run.room == null:
		return
	_room.text = "%02d / 03    %s" % [_run.room_index + 1, _run.rooms[_run.room_index].display_name]
	_boss_panel.visible = _run.room.definition.boss_room
	if _run.room.definition.boss_room:
		_objective.text = "晶核已稳定 · 黎明已至" if _run.room.is_cleared else "直面晶核守卫 · 留意扇形与圆形预警"
	elif _run.room.definition.boss_staging:
		_objective.text = "晶核封印 · 普通试炼完成"
	elif _run.room.is_cleared:
		_objective.text = "出口已开启 · 前往北侧青色能量门"
	else:
		_objective.text = "存活哨兵  %d / %d  ·  出口封锁" % [_run.room.get_living_enemy_count(), _run.room.enemies.size()]
	_summary.text = "已清除 %d 房   /   击杀 %d   /   用时 %s\n\n祝福：%s\n随机种子：%d" % [_run.rooms_cleared, _run.kills, _format_time(_run.elapsed), _blessing_names(), _run.active_seed]
	_update_stats()


func _on_clock_changed(_seconds: float) -> void:
	_update_stats()


func _update_stats() -> void:
	_stats.text = "%s  ·  击杀 %d  ·  种子 %d" % [_format_time(_run.elapsed), _run.kills, _run.active_seed]


func _on_collection_changed() -> void:
	_collection.text = "本局祝福  /  " + _blessing_names()


func _blessing_names() -> String:
	var names: PackedStringArray = []
	for blessing: BlessingDefinition in _run.blessings.acquired:
		names.append(blessing.display_name)
	return "、".join(names) if not names.is_empty() else "尚未获得"


func _on_health_changed(current: int, maximum: int) -> void:
	_health.text = "生命   %d / %d" % [current, maximum]
	_health_bar.max_value = maximum
	_health_bar.value = current


func _on_player_damaged(amount: int, _info: DamageInfo) -> void:
	# ONB-3: only a Boss-grade hit (20+) earns the colour-legend hint, and only once.
	# Colours are read from the shipped scene, not invented: sentinel.tscn:84-85 gives
	# warning_color = Color(1, 0.45, 0.05) (orange) and active_color = Color(1, 0.12, 0.03) (red),
	# and core_guardian.tscn inherits that scene.
	if amount < 20 or _shown_heavy_hit_hint:
		return
	_shown_heavy_hit_hint = true
	_show_onboarding("橙色是预警 · 红色才生效 · 走出红区可免伤", 6.0)


func _show_onboarding(text: String, seconds: float) -> void:
	_onboarding.text = text
	_onboarding.visible = true
	_onboarding_timer.start(seconds)


func _on_onboarding_elapsed() -> void:
	_onboarding.visible = false


func _on_player_blocked(_info: DamageInfo) -> void:
	# Only a deliberate dodge i-frame counts as "perfect"; post-hit protection is not a dodge.
	if not _run.player.health.has_invulnerability_reason(&"dodge"):
		return
	_dodge_confirm.text = "完美闪避"
	_dodge_confirm.visible = true
	_dodge_confirm_timer.start(0.6)


func _on_dodge_confirm_elapsed() -> void:
	_dodge_confirm.visible = false


func _on_telemetry(_state: String, _speed: float, cooldown: float) -> void:
	var skill_cd: float = _run.player.combat.skill_cooldown_remaining
	_skill.text = "E   星刃斩   /   %.1f 秒" % skill_cd if skill_cd > 0.0 else "E   星刃斩   /   就绪"
	_dodge.text = "Shift   闪避   /   %.1f 秒" % cooldown if cooldown > 0.0 else "Shift   闪避   /   就绪"


func _on_card_pressed(id: StringName) -> void:
	_run.select_blessing(id)


func _on_pause_pressed() -> void:
	_run.pause()


func _on_resume_pressed() -> void:
	_run.resume()


func _on_restart_pressed() -> void:
	_run.restart()


func _on_menu_pressed() -> void:
	_run.return_to_menu()


func _on_boss_health_changed(current: int, maximum: int) -> void:
	_boss_health.text = "晶核守卫   %d / %d" % [current, maximum]
	_boss_bar.max_value = maximum
	_boss_bar.value = current


func _on_boss_action_changed(action: String) -> void:
	_boss_action.text = action


func _format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _label(parent: Node, value: String, font_size: int, color: Color) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


func _panel(parent: Control, at: Vector2, dimensions: Vector2) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = at
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.07, 0.105, 0.91)))
	parent.add_child(panel)
	return panel


func _rows(parent: Node) -> VBoxContainer:
	var rows: VBoxContainer = VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 8)
	parent.add_child(rows)
	return rows


func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_stylebox_override("normal", _style(Color("173341"), Color("397568")))
	button.add_theme_stylebox_override("hover", _style(Color("23505b"), CYAN))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, CYAN))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
