extends SceneTree
## [ui-polish] Verifies the UI sound catalog without ears: every Sfx.UI_SOUNDS entry must decode, have a sane length
## (matches the vgmstream measurement in data/audio/ui_gain.json), and when actually played through Sfx.ui() the mixed
## UI bus must carry audible, non-clipping signal (AudioEffectCapture on the bus).
## Run: godot --headless --path . --script res://src/debug/sfx_check.gd
## Prints one line per sound ("SFXCHK ...") and a final "SFXCHK RESULT ok/FAIL n".

var _names: Array = []
var _i := 0
var _cap: AudioEffectCapture
var _state := 0
var _wait := 0
var _fails := 0
var _bus_peak := -100.0
var _expect := 0.0
var _need := 14


func _process(_dt: float) -> bool:
	var sfx = root.get_node("Sfx")
	if _cap == null:
		_names = sfx.UI_SOUNDS.keys()
		var bi := AudioServer.get_bus_index("UI")
		_cap = AudioEffectCapture.new()
		_cap.buffer_length = 0.5
		AudioServer.add_bus_effect(bi, _cap)
		print("SFXCHK catalog=%d sounds, bus UI=%d vol=%.1fdB master=%.1fdB" % [_names.size(), bi, AudioServer.get_bus_volume_db(bi), AudioServer.get_bus_volume_db(0)])
		return false
	if _i >= _names.size():
		print("SFXCHK RESULT ", "ok" if _fails == 0 else "FAIL %d" % _fails)
		quit(0 if _fails == 0 else 1)
		return true
	match _state:
		0:   # play
			var name: String = _names[_i]
			var e: Array = sfx.UI_SOUNDS[name]
			var path: String = sfx._path_of(e[0])
			var st: AudioStream = sfx.stream(path)
			if st == null:
				print("SFXCHK FAIL %-18s missing/undecodable %s" % [name, path])
				_fails += 1
				_i += 1
				return false
			_cap.clear_buffer()
			sfx._last_play.clear()
			sfx._last_role.clear()
			sfx.ui(name)
			_expect = float(sfx.ROLE_TARGET[e[1]]) + AudioServer.get_bus_volume_db(0) + AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI"))
			_bus_peak = -100.0
			_wait = 0
			_need = int(minf(st.get_length(), 1.5) * 60.0) + 6
			_state = 1
		1:   # capture for a few frames, track peak
			var n := _cap.get_frames_available() if _wait > 1 else 0
			if n > 0:
				for f in _cap.get_buffer(n):
					_bus_peak = maxf(_bus_peak, linear_to_db(maxf(absf(f.x), absf(f.y))))
			_wait += 1
			if _wait >= _need:
				var name: String = _names[_i]
				var e: Array = sfx.UI_SOUNDS[name]
				var path: String = sfx._path_of(e[0])
				var st: AudioStream = sfx.stream(path)
				var g = sfx._gain.get(path, {})
				var gl := float(g.get("len", -1.0))
				var ok := true
				var why := ""
				if gl > 0.0 and absf(st.get_length() - gl) > 0.06:
					ok = false
					why += " len mismatch %.2f vs %.2f" % [st.get_length(), gl]
				if st.get_length() < 0.03:
					ok = false
					why += " too short"
				if _bus_peak < -48.0:
					ok = false
					why += " inaudible on bus (%.1f dBFS)" % _bus_peak
				if _bus_peak > -0.5:
					ok = false
					why += " clipping"
				if not ok:
					_fails += 1
				print("SFXCHK %s %-18s %-48s len=%.2fs bus_peak=%6.1f dBFS (expect ~%.1f)%s" % ["ok  " if ok else "FAIL", name, path.get_file(), st.get_length(), _bus_peak, _expect, why])
				_i += 1
				_state = 0
				# let the voice finish / stop it so the capture stays clean
				for p in sfx.ui_players:
					p.stop()
	return false
