extends Node
## SFX/music playback with a pooled set of players and per-sound throttling.
## Until CC0 audio is added (Milestone 8), SFX are synthesized at startup so the game is never silent.

const MIX_RATE := 22050
const PLAYER_COUNT := 14

var sfx_enabled := true
var music_enabled := true

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("SFX")
	_ensure_bus("Music")
	for i in PLAYER_COUNT:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_players.append(player)
	_build_placeholder_sfx()


## min_interval throttles rapid repeats (e.g. shots at 12/s) so the mix stays clean.
func play(sound: String, volume_db := 0.0, pitch_jitter := 0.05, min_interval := 0.0) -> void:
	if not sfx_enabled or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec() * 0.001
	if min_interval > 0.0 and now - float(_last_played.get(sound, -100.0)) < min_interval:
		return
	_last_played[sound] = now
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = _streams[sound]
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not enabled)


func set_music_enabled(enabled: bool) -> void:
	music_enabled = enabled
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not enabled)


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


# --- Placeholder synthesis -------------------------------------------------------------------

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
