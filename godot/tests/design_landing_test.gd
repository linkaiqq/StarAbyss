extends SceneTree
## P8 design-landing fixture (game-dev / D6).
##
## Covers exactly the four batch-1 items of docs/DESIGN_REVIEW.md §3.1 and nothing else.
## Every assertion here is NEW; no existing suite is modified, and no expectation of the
## frozen L1 assertions is touched.
##   I-1 perfect-dodge confirmation  -> GAMEPLAY_DESIGN §5.5 G-04A (SYSTEM_DESIGN §5.2)
##   I-2 failure attribution         -> GAMEPLAY_DESIGN §5.8 G-07
##   I-3 onboarding ONB-1..ONB-4     -> GAMEPLAY_DESIGN §4.4
##   I-4 narrative text landing      -> STORY_BIBLE §10.0 (9 strings + sentinel state words)
##
## Direct HealthComponent calls are used so the fixture never depends on enemy AI timing.
## Registered in tools/verify.py as the headless check "design-landing".

var _checks: int = 0
var _failures: int = 0
var _run: RunManager
var _blocked_count: int = 0


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	await _test_menu_tagline()
	await _test_dodge_confirmation()
	await _test_fail_attribution()
	await _test_boss_attribution()
	await _test_onboarding()
	await _test_story_text()
	print("DESIGN LANDING RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


# --- I-4 main menu tagline (STORY_BIBLE P0-1) -------------------------------

func _test_menu_tagline() -> void:
	var menu_path: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	var menu: Control = (load(menu_path) as PackedScene).instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _ticks(6)
	_check(_has_label_containing(menu, "黎明之前，重封晶核；孤身入渊，与旧誓一战。"),
		"I-4 P0-1 the main menu ships the narrative tagline")
	_check(not _has_label_containing(menu, "深入遗迹，收集祝福"),
		"I-4 P0-1 the old menu tagline is gone")
	_check(_find_button(menu, "开始本局") != null and _find_button(menu, "退出游戏") != null,
		"I-4 P0-1 the menu buttons are untouched by the text change")
	menu.queue_free()
	current_scene = null
	await _ticks(4)


# --- I-1 完美闪避确认 (G-04A) ------------------------------------------------

func _test_dodge_confirmation() -> void:
	await _fresh()
	var health: HealthComponent = _run.player.health
	var ui: RunUI = _run.ui
	var confirm: Label = ui.find_child("DodgeConfirm", true, false) as Label
	_check(confirm != null, "I-1 HUD owns a dedicated dodge-confirmation label")
	_check(confirm != null and not confirm.visible, "I-1 dodge confirmation starts hidden")
	if confirm == null:
		await _teardown()
		return
	health.blocked.connect(_on_blocked)

	# 1. A hit inside a dodge i-frame is still worth 0 damage and now reports itself.
	_blocked_count = 0
	health.set_invulnerable(&"dodge", true)
	var blocked_damage: int = health.receive_damage(20, DamageInfo.create(20.0, null, 2))
	_check(blocked_damage == 0, "I-1 a dodge i-frame still returns 0 damage (combat rules unchanged)")
	_check(_blocked_count == 1, "I-1 a hit inside a dodge i-frame emits blocked exactly once")
	_check(confirm.visible and confirm.text.contains("完美闪避"), "I-1 HUD shows 完美闪避 when the dodge i-frame blocks a hit")

	await _wait_seconds(0.75)
	_check(not confirm.visible, "I-1 完美闪避 confirmation hides by itself after 0.6 s")

	# 2. A normal hit must behave exactly as before and must not claim a perfect dodge.
	health.set_invulnerable(&"dodge", false)
	health.protection_remaining = 0.0
	_blocked_count = 0
	var health_before: int = health.current_health
	var applied: int = health.receive_damage(12, DamageInfo.create(12.0, null, 2))
	_check(applied == 12 and health.current_health == health_before - 12, "I-1 a normal hit still applies its full damage")
	_check(_blocked_count == 0, "I-1 a normal hit does not emit blocked")
	_check(not confirm.visible, "I-1 a normal hit never shows 完美闪避")

	# 3. Post-hit protection is invulnerability too: it reports blocked, but is not a dodge.
	_blocked_count = 0
	var protected_damage: int = health.receive_damage(12, DamageInfo.create(12.0, null, 2))
	_check(protected_damage == 0 and health.current_health == health_before - 12, "I-1 post-hit protection still absorbs damage (return value unchanged)")
	_check(_blocked_count == 1, "I-1 post-hit protection reports a block through the new signal")
	_check(not confirm.visible, "I-1 only dodge i-frames show 完美闪避, post-hit protection does not")

	# 4. One attack can never report two blocks (the existing attack-id memory still applies).
	health.set_invulnerable(&"dodge", true)
	_blocked_count = 0
	var repeated: DamageInfo = DamageInfo.create(20.0, null, 2)
	health.receive_damage(20, repeated)
	health.receive_damage(20, repeated)
	_check(_blocked_count == 1, "I-1 one attack id can never report two blocks")

	await _teardown()


# --- I-2 失败归因 (G-07) -----------------------------------------------------

func _test_fail_attribution() -> void:
	await _fresh()
	var player: PlayerController = _run.player
	var ui: RunUI = _run.ui
	var sentinel: SentinelController = _run.room.enemies[0]
	var subtitle: Label = ui.find_child("ModalSubtitle", true, false) as Label
	_check(_run.last_hit_summary.is_empty(), "I-2 no failure cause is invented before the player dies")

	# The cause is derived from the attacker's own Resources, not from hardcoded text.
	var sentinel_cause: String = _run.describe_damage_source(DamageInfo.create(10.0, sentinel, 2))
	_check(sentinel_cause.contains("遗迹哨兵") and sentinel_cause.contains("哨兵横扫"),
		"I-2 a sentinel hit names the sentinel and the move that landed (%s)" % sentinel_cause)
	_check(sentinel_cause.contains("10 伤害"), "I-2 the cause reports the move's own damage, not the overkill amount")
	_check(_run.describe_damage_source(null) == "未知来源", "I-2 a hit without an attacker degrades to 未知来源 instead of crashing")

	# The death screen itself carries the attribution, and the FAILED state is unchanged.
	var lethal: int = player.health.receive_damage(100, DamageInfo.create(10.0, sentinel, 2))
	await _ticks(4)
	_check(lethal == 100 and player.health.current_health == 0, "I-2 the killing blow still resolves through the frozen damage rules")
	_check(_run.current_state == RunManager.State.FAILED, "I-2 death still enters FAILED (state machine untouched)")
	_check(not _run.last_hit_summary.is_empty() and _run.last_hit_summary.contains("遗迹哨兵"),
		"I-2 RunManager records the cause of the killing blow")
	_check(subtitle != null and subtitle.text.contains("最后一击：") and subtitle.text.contains("遗迹哨兵"),
		"I-2 the failure screen shows 最后一击 with the attacker and move")
	_check(subtitle != null and subtitle.text.contains("倒在第 1 房") and subtitle.text.contains("剩余生命 0 / 100"),
		"I-2 the failure screen shows the room reached and the remaining health")
	_check(_has_label_containing(ui, "探索者已倒下"), "I-2 the failure title is unchanged")

	await _teardown()


func _test_boss_attribution() -> void:
	await _fresh()
	# Walk the production transition path instead of instantiating the boss alone:
	# a detached guardian has no ../../Player target and would log SCRIPT ERRORs.
	_run.room_index = 1
	_run._set_state(RunManager.State.TRANSITION)
	_run._advance_room()
	await _ticks(10)
	var boss: SentinelController = _run.room.boss
	_check(boss != null, "I-2 the boss room still spawns the guardian through the normal transition")
	if boss != null:
		var cause: String = _run.describe_damage_source(DamageInfo.create(25.0, boss, 2))
		_check(cause.contains("晶核守卫") and cause.contains("重锤横扫"),
			"I-2 a guardian hit names 晶核守卫 and its move (%s)" % cause)
	await _teardown()


# --- I-3 新手引导 ONB-1..4 (§4.4) -------------------------------------------

func _test_onboarding() -> void:
	await _fresh()
	var ui: RunUI = _run.ui
	var player: PlayerController = _run.player
	var hint: Label = ui.find_child("OnboardingHint", true, false) as Label
	var objective: Label = ui.find_child("ObjectiveText", true, false) as Label
	var subtitle: Label = ui.find_child("ModalSubtitle", true, false) as Label
	_check(hint != null and objective != null and subtitle != null, "I-3 the onboarding labels exist as their own nodes")
	if hint == null or objective == null or subtitle == null:
		await _teardown()
		return

	# ONB-1: the bottom control row lists the two abilities players forget.
	_check(_has_label_containing(ui, "E 星刃斩") and _has_label_containing(ui, "Shift 闪避"),
		"I-3 ONB-1 the control row lists E 星刃斩 and Shift 闪避")
	_check(_has_label_containing(ui, "Space 跳跃") and _has_label_containing(ui, "鼠标转镜头"),
		"I-3 ONB-1 the earlier control hints survive the extension")

	# ONB-2: one 6 s hint on the first live combat, stating the real magnitudes.
	_check(hint.visible, "I-3 ONB-2 the first live combat shows the dodge hint")
	_check(hint.text.contains("0.45") and hint.text.contains("0.10–0.30"),
		"I-3 ONB-2 the hint states the real numbers (0.45 s dodge, only 0.10–0.30 s i-frames)")
	_check(objective.text.contains("存活哨兵  2 / 2"),
		"I-3 ONB-2 the objective label keeps its frozen text (robustness_test contract)")
	await _wait_seconds(6.3)
	_check(not hint.visible, "I-3 ONB-2 the dodge hint hides itself after 6 s")
	_run.pause()
	await _frames(2)
	_run.resume()
	await _frames(2)
	_check(not hint.visible, "I-3 ONB-2 leaving and re-entering combat does not show the hint twice")

	# ONB-3: only a Boss-grade hit earns the colour legend, and it must match the shipped scene.
	player.health.protection_remaining = 0.0
	player.health.receive_damage(10, DamageInfo.create(10.0, null, 2))
	await _frames(2)
	_check(not hint.visible, "I-3 ONB-3 an ordinary 10-damage hit does not trigger the colour legend")
	player.health.protection_remaining = 0.0
	player.health.receive_damage(20, DamageInfo.create(20.0, null, 2))
	await _frames(2)
	_check(hint.visible and hint.text.contains("橙色是预警") and hint.text.contains("红色才生效"),
		"I-3 ONB-3 a 20+ hit explains the orange warning and the red active window")
	_check(hint.text.contains("走出红区可免伤"), "I-3 ONB-3 the colour legend also says how to avoid the damage")
	await _wait_seconds(6.3)
	_check(not hint.visible, "I-3 ONB-3 the colour legend hides itself after 6 s")

	# ONB-4: the first reward modal says how many picks a run has.
	for enemy: SentinelController in _run.room.enemies:
		enemy.health.receive_damage(45, DamageInfo.create(45.0, _run.player, 1))
	await _frames(8)
	_check(_run.current_state == RunManager.State.CHOOSING, "I-3 ONB-4 clearing the room still opens the reward modal")
	_check(subtitle.text.contains("只能选 2 次"), "I-3 ONB-4 the first reward modal states that a run only offers 2 picks")
	var first_id: StringName = _run.blessings.candidates[0].id
	_run.select_blessing(first_id)
	await _frames(4)
	_check(_run.blessings.acquired.size() == 1, "I-3 ONB-4 choosing a card still acquires exactly one blessing")
	_run.pause()
	await _frames(2)
	_check(not subtitle.text.contains("只能选 2 次"), "I-3 ONB-4 the pick-count reminder is only shown on the first pick")
	_run.resume()
	await _frames(2)

	await _teardown()


# --- I-4 narrative text landing (STORY_BIBLE §10.0) -------------------------

func _test_story_text() -> void:
	await _fresh()
	var ui: RunUI = _run.ui
	var subtitle: Label = ui.find_child("ModalSubtitle", true, false) as Label

	# P0-2: failure subtitle.
	_run.player.health.receive_damage(100, DamageInfo.create(10.0, _run.room.enemies[0], 2))
	await _frames(4)
	_check(subtitle != null and subtitle.text.begins_with("黎明未至 · 再入星渊，皆从头。"),
		"I-4 P0-2 the failure subtitle opens with the narrative line")
	_check(subtitle != null and subtitle.text.contains("最后一击："),
		"I-4 P0-2 the narrative rewrite keeps the G-07 cause line (no information lost)")
	await _teardown()

	# P0-4 / P0-5 / P0-6 / P0-7: boss objective, boss gate caption, victory lines.
	await _fresh()
	var boss_ui: RunUI = _run.ui
	var boss_objective: Label = boss_ui.find_child("ObjectiveText", true, false) as Label
	var win_subtitle: Label = boss_ui.find_child("ModalSubtitle", true, false) as Label
	_run.room_index = 1
	_run._set_state(RunManager.State.TRANSITION)
	_run._advance_room()
	await _ticks(10)
	_check(boss_objective != null and boss_objective.text == "直面晶核守卫 · 留意扇形与圆形预警",
		"I-4 P0-5 the boss objective keeps the telegraph warning after the narrative rewrite")
	_check(_run.room.gate.caption.text == "晶核封印 · 旧誓仍守此门",
		"I-4 P0-6 the boss gate caption uses the narrative line")
	var boss: SentinelController = _run.room.boss
	_check(boss != null, "I-4 the boss room spawns the guardian before the victory-line check")
	if boss != null:
		boss.health.receive_damage(350, DamageInfo.create(350.0, _run.player, 1))
		await _frames(8)
		_check(_run.current_state == RunManager.State.WON, "I-4 the boss death still reaches the WON state")
		_check(boss_objective.text == "晶核已稳定 · 黎明已至", "I-4 P0-4 the cleared boss objective uses the dawn line")
		_check(win_subtitle != null and win_subtitle.text == "结界在黎明时分平息了遗迹的侵蚀。",
			"I-4 P0-3 the victory subtitle uses the narrative line")
		_check(_run.room.gate.caption.text == "晶核已稳定 · 黎明已至",
			"I-4 P0-7 the cleared boss gate caption uses the dawn line")
	await _teardown()

	# P1-1 / P1-2: blessing descriptions keep every mechanic and add the flavour clause.
	var flame: BlessingDefinition = load("res://resources/blessings/blessing_flame.tres") as BlessingDefinition
	var wind: BlessingDefinition = load("res://resources/blessings/blessing_wind.tres") as BlessingDefinition
	_check(flame != null and flame.description.contains("× 1.20") and flame.description.contains("星辉附刃"),
		"I-4 P1-1 the flame blessing keeps × 1.20 and gains the flavour line")
	_check(flame != null and is_equal_approx(flame.normal_attack_multiplier, 1.2),
		"I-4 P1-1 the flame multiplier is untouched")
	_check(wind != null and wind.description.contains("0.9 秒") and wind.description.contains("距离与无敌区间不变")
		and wind.description.contains("步借渊风"),
		"I-4 P1-2 the wind blessing keeps every mechanic and gains the flavour clause")
	_check(wind != null and is_equal_approx(wind.dodge_cooldown, 0.9), "I-4 P1-2 the wind cooldown is untouched")

	# §10.6 row 1: the floating state word above a sentinel is Chinese; the FSM contract is not.
	await _fresh()
	var sentinel: SentinelController = _run.room.enemies[0]
	await _ticks(2)
	var shown: String = sentinel.status_label.text
	_check(_contains_any(shown, ["巡守", "寻敌", "蓄势", "出击", "收势", "归位", "受创", "已毁"]),
		"I-4 L4 the sentinel status label shows a Chinese state word (%s)" % shown.replace("\n", " / "))
	_check(not _contains_any(shown, ["Idle", "Chase", "Telegraph", "Attack", "Recover", "Return", "Hurt", "Dead"]),
		"I-4 L4 the sentinel status label no longer leaks the English FSM word")
	_check(_contains_any(sentinel.brain.get_state_name(), ["Idle", "Chase", "Telegraph", "Attack", "Recover", "Return", "Hurt", "Dead"]),
		"I-4 L4 EnemyBrain.get_state_name() still returns the English contract value (%s)" % sentinel.brain.get_state_name())
	await _teardown()


# --- helpers ---------------------------------------------------------------

func _contains_any(haystack: String, needles: Array) -> bool:
	for needle: String in needles:
		if haystack.contains(needle):
			return true
	return false


func _has_label_containing(container: Node, needle: String) -> bool:
	for node: Node in container.find_children("*", "Label", true, false):
		var label: Label = node as Label
		if label != null and label.text.contains(needle):
			return true
	return false


func _find_button(container: Node, text: String) -> Button:
	for node: Node in container.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button != null and button.text == text:
			return button
	return null


func _on_blocked(_info: DamageInfo) -> void:
	_blocked_count += 1


func _fresh() -> void:
	_run = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	_run.run_seed = 2468
	root.add_child(_run)
	current_scene = _run
	_run.player.camera_controller.set_process_unhandled_input(false)
	await _ticks(12)
	for enemy: SentinelController in _run.room.enemies:
		enemy.set_physics_process(false)


func _teardown() -> void:
	# Damage cues are still playing when the fixture ends; stop them and give the audio
	# server real time to release the playbacks. The wait is on the wall clock, not a
	# SceneTreeTimer: under `--fixed-fps 60` a simulated 0.25 s elapses in a few real
	# milliseconds, which is why this class of leak is recorded as DEF-03 in docs/FIXES.md.
	var audio: Node = _run.find_child("RunAudio", true, false)
	if audio != null and audio.has_method("stop_all"):
		audio.stop_all()
	current_scene = null
	_run.queue_free()
	var deadline: int = Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


## Idle frames only: safe while the tree is paused (physics frames are not required).
func _frames(count: int) -> void:
	for index: int in range(count):
		await process_frame


## Simulated seconds. The registered check runs with --fixed-fps 60, so one idle frame is
## exactly 1/60 s; counting frames keeps the wait independent of wall-clock speed.
func _wait_seconds(seconds: float) -> void:
	var frames: int = int(ceil(seconds * 60.0))
	for index: int in range(frames):
		await process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
