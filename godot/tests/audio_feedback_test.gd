extends SceneTree
## Signal/audio lifecycle fixture; direct actions and damage are not a playthrough.
##
## Cue coverage is manifest-driven instead of a hardcoded count:
##   * the sixteen P6 event cues stay frozen, so the original coverage cannot be weakened;
##   * P7 one-shot cues and looping ambience are read from whatever dictionaries
##     AudioCues exposes (STREAMS / P7_STREAMS / AMBIENCE_STREAMS);
##   * the union of those dictionaries must equal the generated manifest, in both
##     directions, so a silently dropped wav or an unregistered cue fails the suite
##     instead of quietly shrinking it.

const CUES_SCRIPT: GDScript = preload("res://scripts/audio/audio_cues.gd")
const MANIFEST_PATH: String = "res://assets/audio/audio_manifest.json"
const AUDIO_DIR: String = "res://assets/audio"
const EXPECTED_MIX_RATE: int = 44100
const PEAK_FLOOR: int = 1000
const PEAK_CEILING: int = 20000
const EDGE_SILENCE: int = 300
const LOOP_SEAM_TOLERANCE: int = 600

## Frozen P6 event cues: exactly these names, no substitutions, original durations.
const FROZEN_EVENT_CUES: Array[StringName] = [
	&"swing_01", &"swing_02", &"swing_03", &"skill", &"dodge", &"impact", &"hurt",
	&"sentinel_warning", &"guardian_sweep_warning", &"guardian_shock_warning",
	&"guardian_slam", &"shatter", &"room_clear", &"blessing", &"victory", &"defeat",
]
const FROZEN_MIN_SECONDS: float = 0.1
const FROZEN_MAX_SECONDS: float = 1.5
const P7_MIN_SECONDS: float = 0.08
const P7_MAX_SECONDS: float = 2.5
const AMBIENCE_MIN_SECONDS: float = 2.0
const MIN_AMBIENCE_CUES: int = 2

var _checks: int = 0
var _failures: int = 0
var _actor_cues: Array[StringName] = []
var _enemy_cues: Array[StringName] = []
var _run_cues: Array[StringName] = []


func _initialize() -> void:
	_test.call_deferred()


func _test() -> void:
	var event_cues: Dictionary = _cue_dict(&"STREAMS")
	var p7_cues: Dictionary = _cue_dict(&"P7_STREAMS")
	var ambience_cues: Dictionary = _cue_dict(&"AMBIENCE_STREAMS")
	var registered: PackedStringArray = _union_keys([event_cues, p7_cues, ambience_cues])
	var manifest_names: PackedStringArray = _manifest_cue_names()

	# Table integrity: the original table stays frozen, the shipped manifest and the
	# code tables must agree, and the P7 additions must actually be present.
	_check(_sorted_keys(event_cues) == _sorted_strings(FROZEN_EVENT_CUES), "P6 event cue table is exactly the frozen sixteen names")
	_check(ambience_cues.size() >= MIN_AMBIENCE_CUES, "at least %d looping ambience cues are registered (found %d)" % [MIN_AMBIENCE_CUES, ambience_cues.size()])
	_check(p7_cues.size() > 0, "P7 one-shot cue table is registered (found %d)" % p7_cues.size())
	_check(not manifest_names.is_empty(), "audio manifest lists generated cues (%d entries)" % manifest_names.size())
	_check(registered == manifest_names, "registered cues and manifest agree in both directions (code=%d manifest=%d)" % [registered.size(), manifest_names.size()])
	if registered != manifest_names:
		print("  ! registered: ", registered)
		print("  ! manifest:   ", manifest_names)

	var hashes: Dictionary[int, bool] = {}
	for cue: StringName in _sorted_keys(event_cues):
		_verify_one_shot(cue, FROZEN_MIN_SECONDS, FROZEN_MAX_SECONDS, true, hashes)
	for cue: StringName in _sorted_keys(p7_cues):
		_verify_one_shot(cue, P7_MIN_SECONDS, P7_MAX_SECONDS, false, hashes)
	for cue: StringName in _sorted_keys(ambience_cues):
		_verify_ambience(cue)
	_check(hashes.size() == event_cues.size() + p7_cues.size(), "all %d one-shot cues have distinct waveform content" % (event_cues.size() + p7_cues.size()))
	_check(AudioCues.get_cue(&"__missing_cue__") == null, "unknown cue names resolve to null instead of aliasing a real stream")

	_check(AudioServer.get_bus_index(&"SFX") >= 0 and AudioServer.get_bus_index(&"UI") >= 0, "SFX and UI route through configured buses")
	var limiter: AudioEffect = AudioServer.get_bus_effect(0, 0)
	_check(limiter is AudioEffectHardLimiter and is_equal_approx((limiter as AudioEffectHardLimiter).ceiling_db, -1.0), "Master uses the configured hard limiter and ceiling")
	var run: RunManager = (load("res://scenes/levels/game_run.tscn") as PackedScene).instantiate() as RunManager
	root.add_child(run)
	current_scene = run
	await _ticks(3)
	var player: PlayerController = run.player
	player.set_physics_process(false)
	for enemy: SentinelController in run.room.enemies:
		enemy.set_physics_process(false)
	var actor_audio: ActorAudio = player.get_node("Audio") as ActorAudio
	var enemy_audio: ActorAudio = run.room.enemies[0].get_node("Audio") as ActorAudio
	var run_audio: RunAudio = run.get_node("RunAudio") as RunAudio
	_check(actor_audio != null and enemy_audio != null and run_audio != null, "production actor and run scenes include audio components")
	actor_audio.cue_played.connect(_record_actor)
	enemy_audio.cue_played.connect(_record_enemy)
	run_audio.cue_played.connect(_record_run)
	for index: int in range(3):
		player.combat.start_attack()
		player.combat.interrupt()
	_check(_actor_cues == [&"swing_01", &"swing_02", &"swing_03"], "three accepted combo actions emit exactly one corresponding swing cue each")
	player.combat.start_skill()
	player.combat.interrupt()
	_check(_actor_cues.back() == &"skill" and _actor_cues.size() == 4, "accepted skill action emits a distinct single cue")
	player.state_machine.transition_to(PlayerStateMachine.State.DODGE)
	_check(_actor_cues.back() == &"dodge" and _actor_cues.size() == 5, "FSM dodge signal emits a single dodge cue")
	player.state_machine.transition_to(PlayerStateMachine.State.IDLE)
	var hit: DamageInfo = DamageInfo.create(10, run.room.enemies[0], 2)
	player.health.receive_damage(10, hit)
	_check(_actor_cues.back() == &"hurt" and _actor_cues.size() == 6, "actual Health damage emits player hurt once")
	player.health.receive_damage(10, hit)
	_check(_actor_cues.size() == 6, "deduplicated contact never emits another hurt cue")
	var brain: EnemyBrain = run.room.enemies[0].brain
	brain.attack_committed.emit(701)
	_check(_enemy_cues == [&"sentinel_warning"], "enemy commitment signal announces sentinel warning once")
	brain.state_changed.emit("Telegraph", "Attack")
	_check(_enemy_cues.back() == &"swing_02" and _enemy_cues.size() == 2, "enemy active state has its own swing sound")
	for index: int in range(24):
		actor_audio.play_cue(&"impact")
	_check(actor_audio.get_active_voice_count() <= actor_audio.max_voices and actor_audio.get_child_count() == actor_audio.max_voices, "bursts reuse a fixed voice pool without growing nodes")
	actor_audio.enabled = false
	_check(not actor_audio.play_cue(&"impact") and actor_audio.get_active_voice_count() == 0, "component mute immediately stops playback and rejects new cues")
	actor_audio.enabled = true
	actor_audio.play_cue(&"skill")
	run.pause()
	await _ticks(2)
	_check(actor_audio.get_active_voice_count() == 0 and enemy_audio.get_active_voice_count() == 0, "pause cleans actor playback instead of leaving voices running")
	_check(not actor_audio.play_cue(&"impact"), "paused actors cannot begin another cue")
	run.resume()
	run.state_changed.emit(RunManager.State.CHOOSING)
	_check(_run_cues == [&"room_clear"], "room-clear state emits one UI cue")
	run.blessings.selection_completed.emit(run.blessings.pool[0])
	_check(_run_cues.back() == &"blessing" and _run_cues.size() == 2, "blessing choice signal emits one reward cue")
	run.state_changed.emit(RunManager.State.WON)
	_check(_run_cues.back() == &"victory", "victory state selects victory fanfare")
	run.state_changed.emit(RunManager.State.FAILED)
	_check(_run_cues.back() == &"defeat", "failure state selects distinct defeat cue")
	run_audio.enabled = false
	_check(run_audio.get_active_voice_count() == 0 and not run_audio.play_cue(&"victory"), "UI mute also stops and suppresses result audio")
	run_audio.enabled = true
	paused = true
	_check(run_audio.play_cue(&"victory") and run_audio.get_active_voice_count() == 1, "result UI audio can play while gameplay is paused")
	run_audio.stop_all()
	_check(run_audio.get_active_voice_count() == 0, "explicit shutdown clears all UI stream references")
	paused = false
	run.free()
	current_scene = null
	await process_frame
	var deadline: int = Time.get_ticks_msec() + 200
	while Time.get_ticks_msec() < deadline:
		await process_frame
	print("AUDIO FEEDBACK RESULT: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## Reads an AudioCues dictionary without hardcoding or requiring it to exist.
func _cue_dict(constant: StringName) -> Dictionary:
	var constants: Dictionary = CUES_SCRIPT.get_script_constant_map()
	var value: Variant = constants.get(constant, null)
	if value is Dictionary:
		return value as Dictionary
	return {}


func _sorted_strings(names: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for name: Variant in names:
		out.append(String(name))
	out.sort()
	return out


func _sorted_keys(dict: Dictionary) -> PackedStringArray:
	return _sorted_strings(dict.keys())


func _union_keys(dicts: Array) -> PackedStringArray:
	var merged: Dictionary = {}
	for dict: Variant in dicts:
		for key: Variant in (dict as Dictionary).keys():
			merged[String(key)] = true
	return _sorted_strings(merged.keys())


## Cue names the generator claims to have produced; the manifest is the expectation list.
func _manifest_cue_names() -> PackedStringArray:
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return PackedStringArray()
	var manifest: Dictionary = parsed as Dictionary
	var sections: Array = ["cues", "ambience", "loops"]
	var names: Dictionary = {}
	for section: String in sections:
		var entries: Variant = manifest.get(section, null)
		if entries is Dictionary:
			for key: Variant in (entries as Dictionary).keys():
				names[String(key)] = true
	return _sorted_strings(names.keys())


func _verify_one_shot(cue: StringName, min_seconds: float, max_seconds: float, exact_zero_start: bool, hashes: Dictionary[int, bool]) -> void:
	var stream: AudioStreamWAV = AudioCues.get_cue(cue)
	_check(stream != null, "%s resolves through the merged cue lookup" % cue)
	if stream == null:
		return
	_check_file(cue, stream)
	var length: float = stream.get_length()
	_check(not stream.stereo and stream.mix_rate == EXPECTED_MIX_RATE and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED and length >= min_seconds and length <= max_seconds, "%s imports as %.2fs nonlooping mono PCM cue" % [cue, length])
	var data: PackedByteArray = stream.data
	var peak: int = 0
	for offset: int in range(0, data.size(), 2):
		peak = maxi(peak, absi(data.decode_s16(offset)))
	var start: int = data.decode_s16(0)
	var end: int = absi(data.decode_s16(data.size() - 2))
	var start_ok: bool = start == 0 if exact_zero_start else absi(start) < EDGE_SILENCE
	_check(peak > PEAK_FLOOR and peak < PEAK_CEILING and start_ok and end < EDGE_SILENCE, "%s has headroom and click-free endpoint envelope (peak %d)" % [cue, peak])
	hashes[hash(data)] = true


func _verify_ambience(cue: StringName) -> void:
	var stream: AudioStreamWAV = AudioCues.get_cue(cue)
	_check(stream != null, "ambience %s resolves through the merged cue lookup" % cue)
	if stream == null:
		return
	_check_file(cue, stream)
	var length: float = stream.get_length()
	_check(not stream.stereo and stream.mix_rate == EXPECTED_MIX_RATE and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.loop_mode != AudioStreamWAV.LOOP_DISABLED and length >= AMBIENCE_MIN_SECONDS, "ambience %s loops at %.2fs mono PCM" % [cue, length])
	var data: PackedByteArray = stream.data
	var peak: int = 0
	var squares: float = 0.0
	var samples: int = 0
	for offset: int in range(0, data.size(), 2):
		var sample: int = data.decode_s16(offset)
		peak = maxi(peak, absi(sample))
		squares += float(sample) * float(sample)
		samples += 1
	var rms: float = sqrt(squares / maxf(float(samples), 1.0))
	var start: int = data.decode_s16(0)
	var end: int = data.decode_s16(data.size() - 2)
	_check(peak > PEAK_FLOOR and peak < PEAK_CEILING and rms > 300.0 and rms < 11000.0, "ambience %s has headroom and sustained energy (peak %d rms %.0f)" % [cue, peak, rms])
	_check(absi(start) < EDGE_SILENCE and absi(end) < EDGE_SILENCE and absi(start - end) < LOOP_SEAM_TOLERANCE, "ambience %s has a click-free loop seam (start %d end %d)" % [cue, start, end])


func _check_file(cue: StringName, stream: AudioStreamWAV) -> void:
	var expected_path: String = "%s/%s.wav" % [AUDIO_DIR, cue]
	_check(FileAccess.file_exists(expected_path) and stream.resource_path == expected_path, "%s is a real file at %s" % [cue, expected_path])


func _ticks(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _record_actor(cue: StringName) -> void:
	_actor_cues.append(cue)


func _record_enemy(cue: StringName) -> void:
	_enemy_cues.append(cue)


func _record_run(cue: StringName) -> void:
	_run_cues.append(cue)


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print(("PASS: " if ok else "FAIL: ") + label)
