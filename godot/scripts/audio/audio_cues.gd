class_name AudioCues
extends RefCounted
## Immutable original PCM resources, generated offline by tools/build_audio_assets.py.
##
## Three explicitly separated collections exist so automated fixtures can enumerate
## every cue, its kind and its loop flag without reading the build script:
##   STREAMS           original P6 combat/result cues, one-shot, non-looping.
##   P7_STREAMS        P7 additions, one-shot, non-looping (movement, danger, pause,
##                     scene transition, boss death, menu confirmations).
##   AMBIENCE_STREAMS  seamless ambient beds; always played through
##                     make_ambient_stream() so the shared resource stays immutable.
## All files are mono 16-bit 44.1 kHz PCM. GAINS holds a per-cue mix trim in dB that
## players add on top of their component volume; it exists so loudness can be tuned
## per event without touching gameplay code.

const STREAMS: Dictionary[StringName, AudioStreamWAV] = {
	&"swing_01": preload("res://assets/audio/swing_01.wav"),
	&"swing_02": preload("res://assets/audio/swing_02.wav"),
	&"swing_03": preload("res://assets/audio/swing_03.wav"),
	&"skill": preload("res://assets/audio/skill.wav"),
	&"dodge": preload("res://assets/audio/dodge.wav"),
	&"impact": preload("res://assets/audio/impact.wav"),
	&"hurt": preload("res://assets/audio/hurt.wav"),
	&"sentinel_warning": preload("res://assets/audio/sentinel_warning.wav"),
	&"guardian_sweep_warning": preload("res://assets/audio/guardian_sweep_warning.wav"),
	&"guardian_shock_warning": preload("res://assets/audio/guardian_shock_warning.wav"),
	&"guardian_slam": preload("res://assets/audio/guardian_slam.wav"),
	&"shatter": preload("res://assets/audio/shatter.wav"),
	&"room_clear": preload("res://assets/audio/room_clear.wav"),
	&"blessing": preload("res://assets/audio/blessing.wav"),
	&"victory": preload("res://assets/audio/victory.wav"),
	&"defeat": preload("res://assets/audio/defeat.wav"),
}

const P7_STREAMS: Dictionary[StringName, AudioStreamWAV] = {
	&"jump": preload("res://assets/audio/jump.wav"),
	&"land": preload("res://assets/audio/land.wav"),
	&"low_hp": preload("res://assets/audio/low_hp.wav"),
	&"pause": preload("res://assets/audio/pause.wav"),
	&"resume": preload("res://assets/audio/resume.wav"),
	&"room_transition": preload("res://assets/audio/room_transition.wav"),
	&"boss_death": preload("res://assets/audio/boss_death.wav"),
	&"ui_confirm": preload("res://assets/audio/ui_confirm.wav"),
	&"ui_hover": preload("res://assets/audio/ui_hover.wav"),
}

const AMBIENCE_STREAMS: Dictionary[StringName, AudioStreamWAV] = {
	&"ambient_ruins_loop": preload("res://assets/audio/ambient_ruins_loop.wav"),
	&"ambient_boss_loop": preload("res://assets/audio/ambient_boss_loop.wav"),
}

const GAINS: Dictionary[StringName, float] = {
	&"jump": -4.0,
	&"land": -5.0,
	&"low_hp": 1.0,
	&"pause": -6.0,
	&"resume": -6.0,
	&"room_transition": -3.0,
	&"boss_death": 1.0,
	&"ui_confirm": -8.0,
	&"ui_hover": -14.0,
}


## Resolves any registered cue, one-shot or ambience. Prefer get_cue() for plain
## lookups (fixtures, tooling) and make_ambient_stream() when the stream is handed
## to a player, so loop repeat mode is guaranteed regardless of import settings.
static func get_cue(cue: StringName) -> AudioStreamWAV:
	var stream: AudioStreamWAV = STREAMS.get(cue) as AudioStreamWAV
	if stream != null:
		return stream
	stream = P7_STREAMS.get(cue) as AudioStreamWAV
	if stream != null:
		return stream
	return AMBIENCE_STREAMS.get(cue) as AudioStreamWAV


static func get_gain(cue: StringName) -> float:
	return GAINS.get(cue, 0.0)


static func one_shot_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for cue: StringName in STREAMS:
		names.append(cue)
	for cue: StringName in P7_STREAMS:
		names.append(cue)
	return names


static func ambience_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for cue: StringName in AMBIENCE_STREAMS:
		names.append(cue)
	return names


static func is_loop(cue: StringName) -> bool:
	return AMBIENCE_STREAMS.has(cue)


## Returns a loop-enabled copy of an ambient bed. The preloaded resource is never
## mutated, so one caller cannot change the loop settings seen by another.
static func make_ambient_stream(cue: StringName) -> AudioStreamWAV:
	var source: AudioStreamWAV = AMBIENCE_STREAMS.get(cue) as AudioStreamWAV
	if source == null:
		return null
	var stream: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	var bytes_per_frame: int = 2 * (2 if stream.stereo else 1)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / bytes_per_frame
	return stream
