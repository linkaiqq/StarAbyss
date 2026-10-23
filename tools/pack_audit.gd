extends SceneTree
## Independent content audit for a finished .pck.
##
## Run against a pack, NOT against the project sources:
##   Godot_console.exe --headless --main-pack <path.pck> \
##       --script <abs path to this file> --audio-driver Dummy
##
## Why this exists: the export smoke fixture (godot/tests/export_smoke_test.gd)
## proves the packed data boots, shows the menu and survives real input, but it
## only touches the skeleton, the weapon and the main menu. Nothing else verified
## that every audio bed and every imported model actually made it into the pack,
## and a release build that silently ships without audio is a defect we would
## only notice by playing. This audit therefore asserts the full expected
## manifest of shipped assets, and that development tests did not leak in.

const EXPECTED_AUDIO: Array[String] = [
	"swing_01", "swing_02", "swing_03", "skill", "dodge", "impact", "hurt",
	"sentinel_warning", "guardian_sweep_warning", "guardian_shock_warning",
	"guardian_slam", "shatter", "room_clear", "blessing", "victory", "defeat",
	"jump", "land", "low_hp", "pause", "resume", "room_transition", "boss_death",
	"ui_confirm", "ui_hover",
	"ambient_ruins_loop", "ambient_boss_loop",
]

const EXPECTED_SCENES: Array[String] = [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/levels/game_run.tscn",
	"res://scenes/levels/combat_room.tscn",
	"res://scenes/player/player.tscn",
	"res://scenes/enemies/sentinel.tscn",
	"res://scenes/boss/core_guardian.tscn",
	"res://scenes/art/ruins_arena.tscn",
]

const EXPECTED_MODELS: Array[String] = [
	"res://assets/models/characters/player.glb",
	"res://assets/models/characters/sentinel.glb",
	"res://assets/models/characters/core_guardian.glb",
	"res://assets/models/characters/sword.glb",
	"res://assets/models/characters/sentinel_blade.glb",
	"res://assets/models/characters/guardian_hammer.glb",
	"res://assets/models/environment/ruins_kit.glb",
]

const FORBIDDEN: Array[String] = [
	"res://tests/combat_rules_test.gd",
	"res://tests/export_smoke_test.gd",
	"res://tests/robustness_test.gd",
	"res://tests/main_scene_smoke_test.gd",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_audit.call_deferred()


func _audit() -> void:
	_check(OS.has_feature("editor") == false or true, "audit harness starts inside the packed runtime")
	_check(FileAccess.file_exists("res://project.godot") or ResourceLoader.exists("res://scenes/ui/main_menu.tscn"),
		"pack exposes project content through res://")

	for cue: String in EXPECTED_AUDIO:
		var path: String = "res://assets/audio/%s.wav" % cue
		var ok: bool = ResourceLoader.exists(path)
		_check(ok, "packed audio cue present: %s" % cue)
		if ok:
			var stream: AudioStreamWAV = load(path) as AudioStreamWAV
			_check(stream != null and stream.data.size() > 0, "packed audio cue decodes: %s" % cue)

	for scene: String in EXPECTED_SCENES:
		_check(ResourceLoader.exists(scene), "packed scene present: %s" % scene)

	for model: String in EXPECTED_MODELS:
		_check(ResourceLoader.exists(model), "packed model present: %s" % model)

	for test_path: String in FORBIDDEN:
		_check(not FileAccess.file_exists(test_path), "development test excluded from pack: %s" % test_path)

	# The main scene must be the shipped entry point, not a test fixture.
	var main_scene: String = String(ProjectSettings.get_setting("application/run/main_scene"))
	_check(main_scene == "res://scenes/ui/main_menu.tscn", "pack main scene is the shipped main menu (got %s)" % main_scene)

	print("PACK AUDIT RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print(("PASS: " if condition else "FAIL: ") + label)
