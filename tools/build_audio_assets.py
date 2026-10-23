"""Rebuild original Star Abyss PCM sound cues using only Python's standard library.

No downloaded samples, external synthesizer, or runtime synthesis is required.
Run with the installed Python: py tools/build_audio_assets.py

Two families are produced:
  * one-shot event cues (mono, non-looping, 16-bit/44.1 kHz, peak ~0.58);
  * seamless ambient beds (mono loops, peak ~0.34) built from partials that are
    exact integer multiples of 1/duration, so the last sample joins the first
    without a click and no runtime crossfade is needed.
"""
import json
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'godot' / 'assets' / 'audio'
OUT.mkdir(parents=True, exist_ok=True)
RATE = 44100
SEED = 271022
# Raised-cosine fade applied to both ends of every ambient loop. 40 ms per side on
# an 8 s bed is inaudible as a gap but guarantees a zero-valued, click-free seam.
SEAM_EDGE_SECONDS = 0.04

# P7 additions. Kept in explicit lists so the manifest can name what is new
# without re-deriving it from file timestamps.
P7_ONE_SHOTS = ['jump', 'land', 'low_hp', 'pause', 'resume', 'room_transition', 'boss_death',
                'ui_confirm', 'ui_hover']
P7_AMBIENCE = ['ambient_ruins_loop', 'ambient_boss_loop']


def envelope(t, duration, attack=0.008, release=0.04):
    return min(1.0, t / attack) * min(1.0, (duration - t) / release)


def write_wav(name, pcm):
    """Write 16-bit mono PCM and return the manifest facts for that file."""
    with wave.open(str(OUT / (name + '.wav')), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(struct.pack('<{}h'.format(len(pcm)), *pcm))
    return {'duration_seconds': round(len(pcm) / RATE, 4),
            'peak_linear': round(max(abs(v) for v in pcm) / 32768.0, 4),
            'rms_linear': round(math.sqrt(sum((v / 32768.0) ** 2 for v in pcm) / len(pcm)), 4),
            'sample_rate': RATE, 'channels': 1, 'bits_per_sample': 16, 'loop': False}


def synth(name, duration, kind, pitch=440.0, end_pitch=None, notes=None):
    rng = random.Random(SEED + sum(ord(c) for c in name))
    values = []
    low_noise = 0.0
    phase = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        x = t / duration
        noise = rng.uniform(-1.0, 1.0)
        low_noise += .12 * (noise - low_noise)
        freq = pitch + ((end_pitch if end_pitch is not None else pitch) - pitch) * x
        phase += math.tau * freq / RATE
        if kind == 'swing':
            value = (noise - low_noise) * math.sin(math.pi * x) ** 1.5 * .70
            value += math.sin(phase) * .18 * math.sin(math.pi * x)
        elif kind == 'impact':
            decay = math.exp(-9.0 * x)
            value = (math.sin(phase) * .60 + low_noise * 1.7) * decay
            value += math.sin(phase * 2.31) * .20 * math.exp(-17.0 * x)
        elif kind == 'crystal':
            value = sum(math.sin(phase * ratio) * gain for ratio, gain in [(1, .5), (2.03, .22), (3.97, .09)])
            value *= math.exp(-4.8 * x)
            value += low_noise * .13 * math.exp(-16 * x)
        elif kind == 'warning':
            # A short pitched pulse precedes the action; the ground warning is
            # still authoritative and is not obscured by a looping siren.
            pulse = .65 + .35 * math.sin(math.tau * 18.0 * t)
            value = (math.sin(phase) * .65 + math.sin(phase * 2) * .12) * pulse * math.exp(-2.3 * x)
        elif kind == 'chord':
            value = 0.0
            for offset, note, gain in notes:
                nt = t - offset
                if nt >= 0:
                    value += math.sin(math.tau * note * nt) * gain * math.exp(-3.8 * nt)
                    value += math.sin(math.tau * note * 2.01 * nt) * gain * .16 * math.exp(-6 * nt)
        elif kind == 'blip':
            # Interface confirmations: short, soft, no low-frequency rumble so it
            # never competes with the telegraph cues.
            value = (math.sin(phase) * .72 + math.sin(phase * 2.02) * .18) * math.exp(-13.0 * x)
            value += low_noise * .10 * math.exp(-30.0 * x)
        elif kind == 'collapse':
            # Terminal boss impact: sub boom, rubble body, crystal shimmer tail.
            value = math.sin(phase) * .55 * math.exp(-2.4 * x)
            value += low_noise * 1.9 * math.exp(-3.2 * x)
            value += math.sin(phase * 3.02) * .18 * math.exp(-2.0 * x)
            value += math.sin(phase * 7.51 + 1.3) * .10 * math.exp(-1.6 * x)
        else:
            raise ValueError(kind)
        values.append(value * envelope(t, duration))
    peak = max(abs(v) for v in values)
    scale = .58 / peak
    pcm = [round(v * scale * 32767) for v in values]
    assert max(abs(v) for v in pcm) < 20000
    assert pcm[0] == 0 and abs(pcm[-1]) < 300
    return write_wav(name, pcm)


def seamless_loop(name, duration, drones, wind, pulses=(), peak_target=0.34):
    """Build a click-free loop.

    Every partial frequency and every LFO rate is an integer multiple of
    1/duration, so all phase align after exactly `duration` seconds and the last
    sample flows into the first. Partial phases are randomised, which is what
    turns a dense stack of on-grid sinusoids into wind instead of a chord.
    """
    frames = round(duration * RATE)
    rng = random.Random(SEED + sum(ord(c) for c in name))
    partials = []
    for freq, gain, lfo_rate, depth in drones:
        partials.append((freq, gain, lfo_rate, rng.uniform(0.0, math.tau), depth))
    for _ in range(wind['count']):
        grid = max(1, round(rng.uniform(wind['low'], wind['high']) * duration))
        partials.append((grid / duration, wind['gain'] * rng.uniform(.45, 1.0),
                         wind['lfo'], rng.uniform(0.0, math.tau), wind['depth']))
    for freq, gain, lfo_rate, width in pulses:
        partials.append((freq, gain, lfo_rate, 0.0, width))
    values = []
    for i in range(frames):
        t = i / RATE
        value = 0.0
        for freq, gain, lfo_rate, lfo_phase, depth in partials:
            if depth < 1.0:
                # Slow breathing amplitude modulation, also exactly periodic.
                shape = .5 + .5 * math.sin(math.tau * lfo_rate * t + lfo_phase)
                value += math.sin(math.tau * freq * t + lfo_phase * .5) * gain * (1.0 - depth + depth * shape)
            else:
                # depth >= 1.0 means "pulsed by the loop grid, not a plain tone".
                beat = (t * lfo_rate) % 1.0
                swell = math.exp(-((beat / depth) ** 2) * 5.0)
                value += math.sin(math.tau * freq * t) * gain * swell
        values.append(value)
    peak = max(abs(v) for v in values)
    scale = peak_target / peak
    pcm = [round(v * scale * 32767) for v in values]
    # Short raised-cosine edges. The loop grid already makes the seam periodic, but
    # a bed that is exactly zero at both ends is click-free by construction and can
    # be verified by any decoder without replaying the waveform.
    edge = max(1, round(SEAM_EDGE_SECONDS * RATE))
    for i in range(min(edge, len(pcm))):
        gain = .5 - .5 * math.cos(math.pi * i / edge)
        pcm[i] = round(pcm[i] * gain)
        pcm[len(pcm) - 1 - i] = round(pcm[len(pcm) - 1 - i] * gain)
    assert max(abs(v) for v in pcm) < 20000
    assert pcm[0] == 0 and pcm[-1] == 0
    # The wrap seam must be as quiet as any interior sample-to-sample step.
    step = max(abs(pcm[i + 1] - pcm[i]) for i in range(len(pcm) - 1))
    seam = abs(pcm[0] - pcm[-1])
    assert seam <= step * 1.5 + 1, 'loop seam %d exceeds interior step %d' % (seam, step)
    result = write_wav(name, pcm)
    result['loop'] = True
    result['loop_seconds'] = round(duration, 4)
    result['loop_seam_delta'] = seam
    result['loop_max_interior_step'] = step
    return result


manifest = {'origin': 'Original deterministic synthesis authored for Star Abyss',
            'license': 'Project-owned original sound waveforms; no third-party samples',
            'seed': SEED, 'cues': {}, 'ambience': {},
            'p7_additions': {'one_shots': P7_ONE_SHOTS, 'ambience': P7_AMBIENCE}}
definitions = [
    ('swing_01', .20, 'swing', 820, 410, None),
    ('swing_02', .24, 'swing', 680, 280, None),
    ('swing_03', .31, 'swing', 490, 130, None),
    ('skill', .49, 'crystal', 659, 988, None),
    ('dodge', .24, 'swing', 1100, 180, None),
    ('impact', .18, 'impact', 330, 78, None),
    ('hurt', .24, 'impact', 180, 60, None),
    ('sentinel_warning', .18, 'warning', 330, 390, None),
    ('guardian_sweep_warning', .26, 'warning', 174, 230, None),
    ('guardian_shock_warning', .34, 'warning', 246, 370, None),
    ('guardian_slam', .48, 'impact', 110, 39, None),
    ('shatter', .33, 'crystal', 880, 360, None),
    ('room_clear', .51, 'chord', 0, None, [(0, 440, .35), (.08, 554.37, .28), (.16, 659.25, .25)]),
    ('blessing', .61, 'chord', 0, None, [(0, 659.25, .4), (.08, 880, .3), (.17, 1318.5, .2)]),
    ('victory', 1.25, 'chord', 0, None, [(0, 392, .35), (.12, 523.25, .3), (.26, 659.25, .25), (.43, 783.99, .25)]),
    ('defeat', 1.05, 'chord', 0, None, [(0, 293.66, .38), (.17, 246.94, .3), (.36, 196, .28)]),
    # P7: movement, danger state, pause and scene-transition feedback.
    ('jump', .16, 'swing', 540, 1180, None),
    ('land', .16, 'impact', 150, 64, None),
    ('low_hp', .52, 'chord', 0, None, [(0, 61.25, .55), (0, 92.5, .20), (.21, 51.91, .46), (.21, 77.78, .16)]),
    ('pause', .13, 'blip', 470, 300, None),
    ('resume', .16, 'blip', 520, 880, None),
    ('room_transition', .55, 'swing', 1300, 240, None),
    ('boss_death', 1.35, 'collapse', 96, 30, None),
    # P7: menu/UI confirmations (main_menu.gd only; no layout or flow changes).
    ('ui_confirm', .16, 'blip', 620, 940, None),
    ('ui_hover', .09, 'blip', 880, 880, None),
]
for name, duration, kind, pitch, end, notes in definitions:
    manifest['cues'][name] = synth(name, duration, kind, pitch, end, notes)

# Ambient beds. Durations are 8 s so the 0.125 Hz grid gives plenty of room for
# slow, non-repeating-feeling modulation while still looping seamlessly.
manifest['ambience']['ambient_ruins_loop'] = seamless_loop(
    'ambient_ruins_loop', 8.0,
    drones=[(55.0, .30, .125, .35), (82.5, .20, .125, .35), (110.0, .13, .25, .30),
            (165.0, .06, .25, .45), (880.0, .022, .375, .55), (1172.0, .014, .375, .6)],
    wind={'count': 14, 'low': 180.0, 'high': 1500.0, 'gain': .055, 'lfo': .25, 'depth': .7},
)
manifest['ambience']['ambient_boss_loop'] = seamless_loop(
    'ambient_boss_loop', 8.0,
    drones=[(41.25, .34, .125, .30), (55.0, .22, .125, .30), (82.5, .11, .25, .40),
            (110.0, .05, .25, .45), (659.0, .020, .5, .55)],
    wind={'count': 10, 'low': 320.0, 'high': 2600.0, 'gain': .045, 'lfo': .5, 'depth': .75},
    # One slow sub swell every two seconds reads as the core's pulse.
    pulses=[(82.5, .18, .5, .35)],
    peak_target=.34,
)
(OUT / 'audio_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf8')
print('AUDIO_ASSETS: {} PCM cues, {} looping ambience beds, deterministic seed {}'.format(
    len(definitions), len(manifest['ambience']), SEED))
