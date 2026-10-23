class_name RunAudio
extends Node
## Scene-local result/reward cues remain audible while the result UI is paused.
## P7 adds a seamless ambience bed, pause/resume feedback and a room-transition
## cue. The bed is faded rather than cut, because the result cues are one-shots.

signal cue_played(cue: StringName)
## P7 feedback that is not one of the four discrete run events. Kept on its own
## channel so "exactly one run-event cue per run event" stays assertable.
signal state_cue_played(cue: StringName)
## Emitted whenever the ambience bed changes, including to &"" when it stops.
signal ambience_changed(cue: StringName)

@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_node_ready():
			if value:
				_sync_ambience(_current_state())
			else:
				stop_all()
@export_range(-40.0, 0.0, 1.0) var volume_db: float = -8.0
@export_range(1, 3, 1) var max_voices: int = 2
@export_range(-40.0, 0.0, 1.0) var ambience_volume_db: float = -21.0
## How far the bed drops while gameplay is paused, so UI cues stay intelligible.
@export_range(0.0, 24.0, 1.0) var pause_duck_db: float = 6.0
@export_range(0.05, 2.0, 0.05) var ambience_fade_seconds: float = 0.55
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _ambience: AudioStreamPlayer
var _ambience_cue: StringName = &""
var _ambience_tween: Tween
var _paused_audio: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"scene_audio")
	for index: int in range(max_voices):
		var voice: AudioStreamPlayer = AudioStreamPlayer.new()
		voice.name = "Voice%d" % index
		voice.bus = &"UI"
		voice.finished.connect(_release_voice.bind(voice))
		add_child(voice)
		_voices.append(voice)
	# Ambient beds are non-positional: the ruins surround the player everywhere.
	_ambience = AudioStreamPlayer.new()
	_ambience.name = "Ambience"
	_ambience.bus = &"SFX"
	_ambience.volume_db = -60.0
	add_child(_ambience)
	var run: RunManager = get_parent() as RunManager
	assert(run != null, "RunAudio requires a run parent")
	run.state_changed.connect(_on_state_changed)
	(run.get_node("BlessingManager") as BlessingManager).selection_completed.connect(_on_blessing_selected)


func play_cue(cue: StringName) -> bool:
	var played: bool = _play(cue)
	if played:
		cue_played.emit(cue)
	return played


## Plays P7 state feedback (pause / resume / room transition) without touching the
## run-event channel.
func play_state_cue(cue: StringName) -> bool:
	var played: bool = _play(cue)
	if played:
		state_cue_played.emit(cue)
	return played


func _play(cue: StringName) -> bool:
	if not enabled or not is_inside_tree() or _voices.is_empty():
		return false
	var stream: AudioStreamWAV = AudioCues.get_cue(cue)
	if stream == null:
		return false
	var voice: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = stream
	voice.volume_db = volume_db + AudioCues.get_gain(cue)
	voice.play()
	return true


func stop_all() -> void:
	_stop_voices()
	_stop_ambience()


func get_active_voice_count() -> int:
	var count: int = 0
	for voice: AudioStreamPlayer in _voices:
		if voice.stream != null:
			count += 1
	return count


## Cue name of the bed currently owned by this node, or &"" when silent.
func current_ambience() -> StringName:
	return _ambience_cue


func is_ambience_playing() -> bool:
	return _ambience != null and _ambience.playing


func _release_voice(voice: AudioStreamPlayer) -> void:
	voice.stop()
	voice.stream = null


## Frees the one-shot voices only. The ambience bed is owned by _sync_ambience()
## so a pause, a blessing choice or a room change never restarts the bed.
func _stop_voices() -> void:
	for voice: AudioStreamPlayer in _voices:
		_release_voice(voice)


func _on_state_changed(state: RunManager.State) -> void:
	match state:
		RunManager.State.PAUSED:
			_stop_voices()
			play_state_cue(&"pause")
		RunManager.State.TRANSITION:
			_stop_voices()
			play_state_cue(&"room_transition")
		RunManager.State.CHOOSING, RunManager.State.STAGE_COMPLETE:
			_stop_voices()
			play_cue(&"room_clear")
		RunManager.State.WON:
			_stop_voices()
			play_cue(&"victory")
		RunManager.State.FAILED:
			_stop_voices()
			play_cue(&"defeat")
	if state != RunManager.State.PAUSED and _paused_audio:
		_paused_audio = false
		# Only an actual return to play gets the unpause blip; leaving the run from
		# the pause menu must not sound like time resumed.
		if state in [RunManager.State.COMBAT, RunManager.State.EXPLORING]:
			play_state_cue(&"resume")
	elif state == RunManager.State.PAUSED:
		_paused_audio = true
	_sync_ambience(state)


func _on_blessing_selected(_blessing: BlessingDefinition) -> void:
	play_cue(&"blessing")


func _sync_ambience(state: RunManager.State) -> void:
	var wanted: StringName = &""
	if enabled and state not in [RunManager.State.WON, RunManager.State.FAILED]:
		wanted = _ambience_for_room()
	if wanted == _ambience_cue:
		if wanted != &"" and _ambience.playing:
			_fade_ambience(_ambience_target_db(state), false)
		return
	_ambience_cue = wanted
	ambience_changed.emit(wanted)
	if wanted == &"":
		_fade_ambience(-60.0, true)
		return
	var stream: AudioStreamWAV = AudioCues.make_ambient_stream(wanted)
	if stream == null:
		_stop_ambience()
		return
	_ambience.stream = stream
	_ambience.volume_db = -60.0
	_ambience.play()
	_fade_ambience(_ambience_target_db(state), false)


func _ambience_for_room() -> StringName:
	var run: RunManager = get_parent() as RunManager
	if run != null and is_instance_valid(run.room) and is_instance_valid(run.room.boss):
		return &"ambient_boss_loop"
	return &"ambient_ruins_loop"


func _ambience_target_db(state: RunManager.State) -> float:
	return ambience_volume_db - (pause_duck_db if state == RunManager.State.PAUSED else 0.0)


func _fade_ambience(target_db: float, stop_when_done: bool) -> void:
	if not is_inside_tree():
		return
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience, "volume_db", target_db, ambience_fade_seconds)
	if stop_when_done:
		_ambience_tween.tween_callback(_release_ambience)


func _release_ambience() -> void:
	_ambience.stop()
	_ambience.stream = null
	if _ambience_cue != &"":
		_ambience_cue = &""
		ambience_changed.emit(&"")


func _stop_ambience() -> void:
	if _ambience == null:
		return
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_release_ambience()


func _current_state() -> RunManager.State:
	var run: RunManager = get_parent() as RunManager
	if run == null:
		return RunManager.State.COMBAT
	return run.current_state


func _exit_tree() -> void:
	stop_all()
