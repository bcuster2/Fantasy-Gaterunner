extends Node
## Audio: pooled SFX players with per-sound throttling, and crossfading music loops.
## Sounds come from data/sounds.json (files in assets/audio, rendered by tools/audio_forge). The old
## runtime synth stays as a fallback for any id without a file, so the game is never silent.

const MIX_RATE := 22050
const PLAYER_COUNT := 16
const SILENT_DB := -40.0

var sfx_enabled := true
var music_enabled := true

var _defs: Dictionary = {}
var _music_defs: Dictionary = {}
var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played: Dictionary = {}
var _music: Array[AudioStreamPlayer] = []
var _music_index := 0
var _current_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = SILENT_DB
		add_child(m)
		_music.append(m)
	var table := JsonUtil.load_dict("res://data/sounds.json")
	_defs = table.get("sfx", {})
	_music_defs = table.get("music", {})
	_build_placeholder_sfx()
	_prefer_files()


## volume_db is an offset on top of the sound's gain_db; min_interval throttles rapid repeats
## (shots at 12/s); pitch lets callers build rising combos (coins).
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.05, min_interval := 0.0, pitch := 1.0) -> void:
	if not sfx_enabled:
		return
	var stream := _stream(sound)
	if stream == null:
		return
	var def: Dictionary = _defs.get(sound, {})
	var now := Time.get_ticks_msec() * 0.001
	var throttle := maxf(min_interval, float(def.get("min_interval", 0.0)))
	if throttle > 0.0 and now - float(_last_played.get(sound, -100.0)) < throttle:
		return
	_last_played[sound] = now
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.volume_db = float(def.get("gain_db", 0.0)) + volume_db
	player.pitch_scale = pitch * (1.0 + randf_range(-pitch_jitter, pitch_jitter))
	player.play()


## Crossfades to a music loop by id (zone id, "boss", "menu"). Unknown ids fall back to forest.
func play_music(track: String, fade := 0.8) -> void:
	if not _music_defs.has(track):
		track = "forest"
	if track == _current_track:
		return
	var def: Dictionary = _music_defs[track]
	var path := String(def.get("file", ""))
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_current_track = track
	var old := _music[_music_index]
	_music_index = 1 - _music_index
	var new := _music[_music_index]
	new.stream = stream
	new.volume_db = SILENT_DB
	new.play()
	var tween := create_tween().set_parallel()
	tween.tween_property(new, "volume_db", float(def.get("gain_db", -6.0)), fade)
	tween.tween_property(old, "volume_db", SILENT_DB, fade)
	tween.chain().tween_callback(old.stop)


func stop_music(fade := 0.8) -> void:
	_current_track = ""
	for m in _music:
		create_tween().tween_property(m, "volume_db", SILENT_DB, fade)


## Release every playback on quit so nothing is left referenced by the audio server.
func _exit_tree() -> void:
	for player in _players + _music:
		player.stop()
		player.stream = null
	_streams.clear()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not enabled)


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not enabled)


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var path := String(_defs.get(sound, {}).get("file", ""))
	if path != "" and ResourceLoader.exists(path):
		_streams[sound] = load(path)
		return _streams[sound]
	return null


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


# --- Fallback synthesis (ids without a file) ---------------------------------------------------

func _build_placeholder_sfx() -> void:
	_streams["shoot"] = _wav(_tone(0.07, 1150.0, 520.0, "square", 0.16))
	_streams["hit"] = _wav(_tone(0.05, 320.0, 140.0, "square", 0.22, 0.65))
	_streams["kill"] = _wav(_tone(0.15, 560.0, 90.0, "tri", 0.5, 0.25))
	_streams["hurt"] = _wav(_tone(0.22, 190.0, 55.0, "square", 0.5, 0.45))
	_streams["gate_good"] = _wav(_join([
		_tone(0.07, 523.0, 523.0, "square", 0.22),
		_tone(0.07, 659.0, 659.0, "square", 0.22),
		_tone(0.18, 1046.0, 1046.0, "square", 0.22),
	]))
	_streams["gate_bad"] = _wav(_tone(0.32, 320.0, 105.0, "saw", 0.3))
	_streams["element"] = _wav(_join([
		_tone(0.12, 300.0, 1400.0, "tri", 0.35, 0.35),
		_tone(0.2, 1400.0, 1300.0, "sine", 0.3),
	]))
	_streams["summon"] = _wav(_join([
		_tone(0.09, 392.0, 392.0, "tri", 0.4),
		_tone(0.09, 523.0, 523.0, "tri", 0.4),
		_tone(0.22, 784.0, 760.0, "tri", 0.4),
	]))
	_streams["curse"] = _wav(_join([
		_tone(0.18, 220.0, 207.0, "saw", 0.3),
		_tone(0.4, 155.0, 110.0, "saw", 0.32, 0.15),
	]))
	_streams["immune"] = _wav(_tone(0.06, 2200.0, 1900.0, "square", 0.12))
	_streams["enemy_shot"] = _wav(_tone(0.12, 900.0, 300.0, "saw", 0.2, 0.3))
	_streams["ally_die"] = _wav(_tone(0.18, 700.0, 200.0, "square", 0.25, 0.5))
	_streams["coin"] = _wav(_join([
		_tone(0.05, 1318.0, 1318.0, "square", 0.16),
		_tone(0.12, 1760.0, 1760.0, "square", 0.16),
	]))
	_streams["win"] = _wav(_join([
		_tone(0.12, 523.0, 523.0, "square", 0.25),
		_tone(0.12, 659.0, 659.0, "square", 0.25),
		_tone(0.12, 784.0, 784.0, "square", 0.25),
		_tone(0.45, 1046.0, 1046.0, "square", 0.25),
	]))
	_streams["lose"] = _wav(_join([
		_tone(0.18, 392.0, 392.0, "tri", 0.4),
		_tone(0.18, 330.0, 330.0, "tri", 0.4),
		_tone(0.5, 262.0, 180.0, "tri", 0.4),
	]))


func _prefer_files() -> void:
	for id: String in _defs:
		var path := String(_defs[id].get("file", ""))
		if path != "" and ResourceLoader.exists(path):
			_streams.erase(id)


func _tone(duration: float, f_start: float, f_end: float, wave: String, volume: float, noise := 0.0) -> PackedFloat32Array:
	var count := int(duration * MIX_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		phase += lerpf(f_start, f_end, t) / MIX_RATE
		var p := fmod(phase, 1.0)
		var v: float
		match wave:
			"square":
				v = 1.0 if p < 0.5 else -1.0
			"saw":
				v = 2.0 * p - 1.0
			"tri":
				v = 1.0 - 4.0 * absf(p - 0.5)
			_:
				v = sin(p * TAU)
		v = lerpf(v, randf_range(-1.0, 1.0), noise)
		var attack := minf(1.0, t * duration / 0.004)
		out[i] = v * volume * attack * pow(1.0 - t, 2.0)
	return out


func _join(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for part: PackedFloat32Array in parts:
		out.append_array(part)
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	return stream
