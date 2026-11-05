extends Node
## Offline audio generator: renders every sound effect and one music loop per zone (plus boss and
## menu loops) to res://assets/audio/*.wav. All original, procedurally synthesized material, so it is
## ours to ship (see CREDITS.md). Run once after changing it:
##   godot --headless --path . res://tools/audio_forge.tscn
## data/sounds.json maps sound ids to these files; point an id at any other CC0 file to replace it.

const RATE := 22050
const OUT := "res://assets/audio"

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/sfx"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/music"))
	var sfx := _sfx_specs()
	for id: String in sfx:
		_save(OUT + "/sfx/%s.wav" % id, sfx[id])
	for zone: String in ["forest", "crypt", "volcano", "boss", "menu"]:
		_save(OUT + "/music/%s.wav" % zone, _music(zone))
	print("[audio_forge] wrote %d sfx and 5 music loops to %s" % [sfx.size(), OUT])
	get_tree().quit()


# --- Building blocks ---------------------------------------------------------------------------

func _buf(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


func _freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


func _osc(kind: String, phase: float) -> float:
	var p := fmod(phase, 1.0)
	match kind:
		"square":
			return 1.0 if p < 0.5 else -1.0
		"pulse":
			return 1.0 if p < 0.25 else -1.0
		"saw":
			return 2.0 * p - 1.0
		"tri":
			return 1.0 - 4.0 * absf(p - 0.5)
		"noise":
			return _rng.randf_range(-1.0, 1.0)
	return sin(p * TAU)


## A voice mixed into buf: pitch glides f0 -> f1 (Hz), attack/decay envelope (exp), one-pole lowpass,
## optional vibrato. start/duration in seconds.
func _voice(buf: PackedFloat32Array, start: float, duration: float, kind: String, f0: float, f1: float,
		gain: float, attack := 0.004, curve := 2.0, cutoff := 1.0, vibrato := 0.0) -> void:
	var s0 := int(start * RATE)
	var n := int(duration * RATE)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var idx := s0 + i
		if idx >= buf.size():
			break
		var t := float(i) / n
		var f := lerpf(f0, f1, t) * (1.0 + vibrato * sin(float(i) / RATE * TAU * 5.5))
		phase += f / RATE
		var v := _osc(kind, phase)
		lp += (v - lp) * cutoff
		var env := minf(1.0, float(i) / maxf(attack * RATE, 1.0)) * pow(1.0 - t, curve)
		buf[idx] += lp * env * gain


func _bell(buf: PackedFloat32Array, start: float, duration: float, midi: float, gain: float) -> void:
	var f := _freq(midi)
	_voice(buf, start, duration, "sine", f, f, gain, 0.002, 2.5)
	_voice(buf, start, duration * 0.6, "sine", f * 2.76, f * 2.76, gain * 0.35, 0.002, 3.0)
	_voice(buf, start, duration * 0.4, "sine", f * 5.4, f * 5.4, gain * 0.15, 0.002, 3.5)


func _echo(buf: PackedFloat32Array, delay: float, feedback: float, wrap := false) -> void:
	var d := int(delay * RATE)
	var n := buf.size()
	for i in range(d, n + (n if wrap else 0)):
		var src := buf[(i - d) % n]
		var dst := i % n
		buf[dst] += src * feedback


func _normalize(buf: PackedFloat32Array, peak := 0.9) -> PackedFloat32Array:
	var m := 0.0001
	for v in buf:
		m = maxf(m, absf(v))
	for i in buf.size():
		buf[i] = tanh(buf[i] / m * 1.1) * peak
	return buf


func _save(path: String, buf: PackedFloat32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	var err := wav.save_to_wav(ProjectSettings.globalize_path(path))
	if err != OK:
		push_error("Could not write %s: %s" % [path, error_string(err)])


# --- Sound effects -----------------------------------------------------------------------------

func _sfx_specs() -> Dictionary:
	var out := {}
	var b: PackedFloat32Array

	b = _buf(0.09) # arcane bolt: soft pluck
	_voice(b, 0, 0.09, "sine", 1300, 700, 0.6, 0.002, 2.5)
	_voice(b, 0, 0.025, "noise", 0, 0, 0.25, 0.001, 3.0, 0.5)
	out["shoot"] = _normalize(b, 0.55)

	b = _buf(0.12) # fire bolt: whoosh
	_voice(b, 0, 0.12, "noise", 0, 0, 0.8, 0.004, 1.5, 0.12)
	_voice(b, 0, 0.1, "saw", 380, 190, 0.3, 0.003, 2.0, 0.3)
	out["shoot_fire"] = _normalize(b, 0.55)

	b = _buf(0.14) # ice shard: chime
	_bell(b, 0, 0.14, 100, 0.5)
	_voice(b, 0, 0.02, "noise", 0, 0, 0.2, 0.001, 3.0, 0.8)
	out["shoot_ice"] = _normalize(b, 0.5)

	b = _buf(0.1) # lightning: crackle
	for k in 6:
		_voice(b, k * 0.012, 0.02, "noise", 0, 0, 0.7, 0.001, 1.0, 0.9)
	_voice(b, 0, 0.08, "square", 950, 600, 0.2, 0.001, 2.0, 0.6)
	out["shoot_lightning"] = _normalize(b, 0.5)

	b = _buf(0.07) # hit thud
	_voice(b, 0, 0.07, "sine", 240, 70, 0.9, 0.001, 2.0)
	_voice(b, 0, 0.02, "noise", 0, 0, 0.5, 0.001, 2.0, 0.6)
	out["hit"] = _normalize(b, 0.6)

	b = _buf(0.16) # weak-point hit: thud + bright ping
	_voice(b, 0, 0.07, "sine", 260, 80, 0.8, 0.001, 2.0)
	_bell(b, 0.01, 0.15, 96, 0.5)
	out["hit_weak"] = _normalize(b, 0.65)

	b = _buf(0.14) # immune: metal clank
	_voice(b, 0, 0.14, "square", 2200, 2100, 0.3, 0.001, 3.0, 0.5)
	_voice(b, 0, 0.12, "square", 3310, 3300, 0.2, 0.001, 3.0, 0.5)
	out["immune"] = _normalize(b, 0.4)

	b = _buf(0.2) # kill pop
	_voice(b, 0, 0.16, "tri", 620, 110, 0.8, 0.002, 2.0)
	_voice(b, 0, 0.08, "noise", 0, 0, 0.5, 0.002, 2.0, 0.35)
	_voice(b, 0.02, 0.12, "sine", 1200, 1500, 0.15, 0.01, 2.0)
	out["kill"] = _normalize(b, 0.7)

	b = _buf(0.35) # elite kill: pop + chime
	_voice(b, 0, 0.16, "tri", 620, 110, 0.8, 0.002, 2.0)
	_bell(b, 0.05, 0.3, 91, 0.45)
	_bell(b, 0.12, 0.23, 95, 0.35)
	out["kill_elite"] = _normalize(b, 0.7)

	b = _buf(0.26) # hero hurt
	_voice(b, 0, 0.22, "sine", 170, 50, 1.0, 0.002, 1.5)
	_voice(b, 0, 0.2, "saw", 150, 60, 0.35, 0.002, 2.0, 0.25)
	_voice(b, 0, 0.05, "noise", 0, 0, 0.5, 0.001, 2.0, 0.5)
	out["hurt"] = _normalize(b, 0.8)

	b = _buf(0.5) # gate (good): bell arpeggio + sparkle
	for k in 4:
		_bell(b, k * 0.06, 0.32, [74, 78, 81, 86][k], 0.45)
	_voice(b, 0.18, 0.3, "noise", 0, 0, 0.12, 0.05, 2.0, 0.9)
	out["gate_good"] = _normalize(b, 0.7)

	b = _buf(0.45) # gate (bad): descending minor buzz
	_voice(b, 0, 0.4, "saw", 330, 140, 0.5, 0.005, 1.5, 0.2)
	_voice(b, 0, 0.4, "saw", 350, 148, 0.4, 0.005, 1.5, 0.2)
	out["gate_bad"] = _normalize(b, 0.6)

	b = _buf(0.45) # element: filtered whoosh + chime
	_voice(b, 0, 0.35, "noise", 0, 0, 0.6, 0.12, 1.5, 0.08)
	_bell(b, 0.08, 0.35, 88, 0.4)
	out["element"] = _normalize(b, 0.65)

	b = _buf(0.7) # summon: dark swell opening up
	for m: int in [48, 55, 60]:
		_voice(b, 0, 0.7, "saw", _freq(m), _freq(m), 0.25, 0.25, 1.2, 0.06)
	_voice(b, 0.3, 0.4, "sine", _freq(72), _freq(72), 0.25, 0.02, 2.0)
	out["summon"] = _normalize(b, 0.7)

	b = _buf(0.8) # curse: tritone drone with reverse swell
	_voice(b, 0, 0.8, "saw", _freq(45), _freq(44), 0.4, 0.4, 0.8, 0.07)
	_voice(b, 0, 0.8, "saw", _freq(51), _freq(50), 0.35, 0.4, 0.8, 0.07)
	_voice(b, 0.35, 0.45, "noise", 0, 0, 0.2, 0.3, 1.0, 0.15)
	out["curse"] = _normalize(b, 0.7)

	b = _buf(0.18) # coin: classic two-note bling
	_voice(b, 0, 0.06, "square", _freq(95), _freq(95), 0.35, 0.001, 0.6, 0.6)
	_voice(b, 0.055, 0.12, "square", _freq(100), _freq(100), 0.35, 0.001, 1.5, 0.6)
	out["coin"] = _normalize(b, 0.45)

	b = _buf(1.4) # win fanfare
	var notes := [[0.0, 72], [0.12, 76], [0.24, 79], [0.36, 84]]
	for n: Array in notes:
		_voice(b, n[0], 0.3, "square", _freq(n[1]), _freq(n[1]), 0.3, 0.003, 1.2, 0.5)
	for m: int in [72, 76, 79, 84]:
		_voice(b, 0.5, 0.9, "square", _freq(m), _freq(m), 0.18, 0.01, 1.4, 0.45, 0.004)
	_voice(b, 0.5, 0.9, "tri", _freq(48), _freq(48), 0.4, 0.01, 1.4)
	out["win"] = _normalize(b, 0.75)

	b = _buf(1.2) # lose phrase
	var lose := [[0.0, 67], [0.22, 63], [0.44, 60], [0.66, 55]]
	for n: Array in lose:
		_voice(b, n[0], 0.5, "tri", _freq(n[1]), _freq(n[1]) * 0.98, 0.4, 0.01, 1.5)
	_voice(b, 0.66, 0.5, "sine", _freq(43), _freq(41), 0.5, 0.02, 1.5)
	out["lose"] = _normalize(b, 0.7)

	b = _buf(1.3) # boss roar
	_voice(b, 0, 1.2, "saw", 85, 60, 0.6, 0.15, 1.0, 0.08, 0.04)
	_voice(b, 0, 1.2, "noise", 0, 0, 0.6, 0.1, 1.2, 0.05)
	_voice(b, 0, 1.0, "saw", 128, 90, 0.3, 0.2, 1.0, 0.1, 0.05)
	out["boss_roar"] = _normalize(b, 0.85)

	b = _buf(0.5) # boss slam impact
	_voice(b, 0, 0.45, "sine", 70, 28, 1.0, 0.001, 1.6)
	_voice(b, 0, 0.3, "noise", 0, 0, 0.8, 0.001, 2.0, 0.15)
	out["boss_slam"] = _normalize(b, 0.9)

	b = _buf(0.12) # telegraph warning tick
	_voice(b, 0, 0.1, "square", 880, 880, 0.35, 0.002, 1.5, 0.5)
	out["telegraph"] = _normalize(b, 0.4)

	b = _buf(0.8) # phase change: riser
	_voice(b, 0, 0.7, "saw", 110, 440, 0.4, 0.05, 0.7, 0.15)
	_voice(b, 0, 0.7, "noise", 0, 0, 0.3, 0.3, 0.6, 0.1)
	out["phase"] = _normalize(b, 0.75)

	b = _buf(0.22) # ally down: bone rattle
	for k in 4:
		_voice(b, k * 0.04, 0.04, "noise", 0, 0, 0.6, 0.001, 2.0, 0.7)
		_voice(b, k * 0.04, 0.03, "square", 1600 - k * 200, 1200 - k * 200, 0.2, 0.001, 2.0, 0.6)
	out["ally_die"] = _normalize(b, 0.55)

	b = _buf(0.18) # enemy shot: whistle
	_voice(b, 0, 0.16, "sine", 950, 600, 0.5, 0.004, 1.5)
	_voice(b, 0, 0.05, "noise", 0, 0, 0.3, 0.001, 2.0, 0.4)
	out["enemy_shot"] = _normalize(b, 0.5)

	b = _buf(0.05) # ui click
	_voice(b, 0, 0.04, "sine", 1100, 900, 0.6, 0.001, 2.5)
	out["ui_click"] = _normalize(b, 0.4)

	b = _buf(0.4) # shop buy: cha-ching
	_bell(b, 0, 0.3, 88, 0.5)
	_bell(b, 0.07, 0.3, 95, 0.5)
	_voice(b, 0, 0.06, "noise", 0, 0, 0.4, 0.001, 2.0, 0.6)
	out["ui_buy"] = _normalize(b, 0.6)

	b = _buf(1.2) # milestone sparkle
	for k in 8:
		_bell(b, k * 0.07, 0.5, [79, 83, 86, 91, 95, 98, 103, 107][k], 0.35)
	out["milestone"] = _normalize(b, 0.7)

	b = _buf(0.9) # level start: rising whoosh + chord
	_voice(b, 0, 0.5, "noise", 0, 0, 0.5, 0.4, 0.5, 0.06)
	for m: int in [60, 64, 67, 72]:
		_voice(b, 0.4, 0.5, "square", _freq(m), _freq(m), 0.15, 0.01, 1.5, 0.4)
	out["level_start"] = _normalize(b, 0.65)
	return out


# --- Music -------------------------------------------------------------------------------------

## Each loop: 8 bars of 16 steps. Chords are MIDI note lists per bar; drums are 16-char patterns
## repeated per bar ("x" hit, "." rest). The melody is generated once from chord tones with a fixed
## seed, so the result is deterministic.
func _music(zone: String) -> PackedFloat32Array:
	var spec := _music_spec(zone)
	var bpm := float(spec["bpm"])
	var step := 60.0 / bpm / 4.0
	var bars: Array = spec["chords"]
	var total := step * 16 * bars.size()
	var buf := _buf(total)
	var lead := _buf(total)
	_rng.seed = LevelSeed.fnv1a("music/" + zone)
	for bar in bars.size():
		var chord: Array = bars[bar]
		var t0 := bar * 16 * step
		# Pad: soft filtered saws holding the chord.
		for m: int in chord:
			_voice(buf, t0, step * 16, spec.get("pad", "saw"), _freq(m), _freq(m), float(spec.get("pad_gain", 0.07)), step * 4, 0.6, 0.05)
		# Bass pattern.
		var bass_pattern := String(spec["bass"])
		for s in 16:
			if bass_pattern[s] == "x":
				var root := float(chord[0]) - 12.0
				_voice(buf, t0 + s * step, step * 1.8, "tri", _freq(root), _freq(root), 0.45, 0.004, 1.2)
		# Arpeggio over chord tones.
		if float(spec.get("arp_gain", 0.0)) > 0.0:
			for s in 16:
				if s % int(spec.get("arp_every", 1)) == 0:
					var note := float(chord[s % chord.size()]) + 12.0
					_voice(buf, t0 + s * step, step * 0.9, "pulse", _freq(note), _freq(note), float(spec["arp_gain"]), 0.002, 2.0, 0.35)
		# Melody: walk chord/scale tones on a rhythm, with rests.
		var rhythm := String(spec["melody_rhythm"])
		var last := float(chord[1]) + 12.0
		for s in 16:
			if rhythm[s] != "x":
				continue
			var options: Array = []
			for m: int in chord:
				options.append(float(m) + 12.0)
				options.append(float(m) + 24.0)
			options.sort_custom(func(a: float, b2: float) -> bool: return absf(a - last) < absf(b2 - last))
			var pick: float = options[_rng.randi_range(0, mini(2, options.size() - 1))]
			last = pick
			var length := step * float(_rng.randi_range(1, 3))
			if String(spec.get("lead", "square")) == "bell":
				_bell(lead, t0 + s * step, length * 2.0, pick, 0.28)
			else:
				_voice(lead, t0 + s * step, length, String(spec.get("lead", "square")), _freq(pick), _freq(pick), 0.16, 0.006, 1.0, 0.4, 0.006)
		# Drums.
		var drums: Dictionary = spec["drums"]
		for s in 16:
			if String(drums.get("kick", "................"))[s] == "x":
				_voice(buf, t0 + s * step, 0.16, "sine", 140, 40, 0.9, 0.001, 1.8)
			if String(drums.get("snare", "................"))[s] == "x":
				_voice(buf, t0 + s * step, 0.14, "noise", 0, 0, 0.45, 0.001, 2.0, 0.5)
				_voice(buf, t0 + s * step, 0.08, "tri", 220, 160, 0.3, 0.001, 2.0)
			if String(drums.get("hat", "................"))[s] == "x":
				_voice(buf, t0 + s * step, 0.04, "noise", 0, 0, 0.16, 0.001, 3.0, 0.95)
	_echo(lead, step * 3.0, 0.3, true)
	for i in buf.size():
		buf[i] += lead[i]
	return _normalize(buf, 0.8)


func _music_spec(zone: String) -> Dictionary:
	match zone:
		"crypt": # A minor, slow and eerie: i - VI - iv - V
			return {"bpm": 92, "chords": [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59], [57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]],
				"pad": "square", "pad_gain": 0.05, "bass": "x.......x.......", "arp_gain": 0.07, "arp_every": 2,
				"melody_rhythm": "x...x.....x.....", "lead": "bell",
				"drums": {"kick": "x...............", "snare": "........x.......", "hat": "..x...x...x...x."}}
		"volcano": # E phrygian, driving: i - bII - i - VII
			return {"bpm": 136, "chords": [[52, 55, 59], [53, 57, 60], [52, 55, 59], [50, 54, 57], [52, 55, 59], [53, 57, 60], [48, 52, 55], [50, 54, 57]],
				"pad_gain": 0.06, "bass": "x.x.x.x.x.x.x.x.", "arp_gain": 0.0,
				"melody_rhythm": "x.x...x.x...x...", "lead": "square",
				"drums": {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}}
		"boss": # C harmonic minor, intense: i - VI - bII - V
			return {"bpm": 150, "chords": [[48, 51, 55], [44, 48, 51], [49, 53, 56], [43, 47, 50], [48, 51, 55], [44, 48, 51], [49, 53, 56], [43, 47, 50]],
				"pad_gain": 0.07, "bass": "x.xxx.xxx.xxx.xx", "arp_gain": 0.06, "arp_every": 1,
				"melody_rhythm": "x..x..x.x..x..x.", "lead": "saw",
				"drums": {"kick": "x..x..x.x..x..x.", "snare": "....x.......x...", "hat": "xxxxxxxxxxxxxxxx"}}
		"menu": # F major, gentle: I - iii - IV - V
			return {"bpm": 96, "chords": [[53, 57, 60], [57, 60, 64], [58, 62, 65], [60, 64, 67], [53, 57, 60], [57, 60, 64], [58, 62, 65], [60, 64, 67]],
				"pad_gain": 0.06, "bass": "x.......x.......", "arp_gain": 0.08, "arp_every": 2,
				"melody_rhythm": "x.......x...x...", "lead": "bell",
				"drums": {"hat": "....x.......x..."}}
		_: # forest: D major, upbeat: I - V - vi - IV
			return {"bpm": 112, "chords": [[50, 54, 57], [57, 61, 64], [59, 62, 66], [55, 59, 62], [50, 54, 57], [57, 61, 64], [59, 62, 66], [55, 59, 62]],
				"pad_gain": 0.06, "bass": "x...x.x.x...x.x.", "arp_gain": 0.07, "arp_every": 1,
				"melody_rhythm": "x.x.x...x.x.x...", "lead": "square",
				"drums": {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}}
