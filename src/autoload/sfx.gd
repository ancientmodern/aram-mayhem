extends Node
## Audio manager (autoload `Sfx`): pooled 2D/3D one-shots, named UI sounds, music with crossfade.
## Buses: Master > Music, SFX, UI.

const UI_SOUNDS := {
	"hover": "sfx-uikit-grid-hover",
	"click": "sfx-uikit-generic-click-small",
	"gold_hover": "sfx-uikit-button-gold-hover",
	"gold_click": "sfx-uikit-button-gold-click",
	"play_hover": "sfx-lobby-button-find-match-hover",
	"play_click": "sfx-lobby-button-find-match-click",
	"lockin_hover": "sfx-cs-lockin-button-hover",
	"lockin": "sfx-cs-lockin-button-click",
	"lock_confirm": "sfx-ui-jade-champselect-lockchampion",
	"reroll_hover": "sfx-cs-button-reroll-hover",
	"reroll": "sfx-cs-button-reroll-click",
	"swap": "sfx-cs-button-swap-click",
	"bench": "sfx-champ-select-bench-update",
	"card_appear": "sfx-cs-aram-card-2-appear",
	"card_appear2": "sfx-cs-aram-card-3-appear",
	"card_hover": "sfx-cs-aram-card-hover",
	"card_select": "sfx-cs-aram-card-select",
	"tick": "sfx-cs-timer-tick-small",
	"victory": "sfx-eog-ui-exp-burst",
	"defeat": "sfx-eog-ui-exp-burst-negative",
	"eog": "sfx-eog-chaos-order",
	"flare": "sfx-eog-ui-edge-flare",
	"toast": "sfx-uikit-reward-toast",
	"celebrate": "sfx-vignette-celebration-intro",
	"buy": "sfx-purchase-button-click",
	"buy_hover": "sfx-purchase-button-hover",
	"toggle": "sfx-uikit-radio-click",
	"checkbox": "sfx-uikit-checkbox-click",
	"locked": "sfx-uikit-button-locked-click",
	"accept": "sfx-ui-jade-match-accept",
	"your_pick": "sfx-cs-draft-notif-yourpick",
	"pick_intro": "sfx-cs-draft-pick-intro",
	"spells_open": "sfx-cs-spells-open",
	"reward": "sfx-celebrate-receive-generic",
}

var players: Array = []
var players3d: Array = []
var _cache := {}
var _last_play := {}          ## name -> time (rate limiting)
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer = null
var _music_name := ""
var _layers: Array = []       ## extra synced music layers


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	music_a = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	for m in [music_a, music_b]:
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
	apply_volumes()


func _setup_buses() -> void:
	for b in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


func apply_volumes() -> void:
	var s: Dictionary = G.settings
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(s.get("master_volume", 0.8)), 0.0001)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(float(s.get("music_volume", 0.5)), 0.0001)))
	var sfx_db := linear_to_db(maxf(float(s.get("sfx_volume", 0.9)), 0.0001))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), sfx_db)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("UI"), sfx_db)


func stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_cache[path] = s
	return s


func play(s: AudioStream, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	if s == null:
		return
	for p in players:
		if not p.playing:
			p.stream = s
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.bus = bus
			p.play()
			return


## Named client UI sound (see UI_SOUNDS). Rate-limited so hover spam stays clean.
func ui(name: String, volume_db: float = 0.0) -> void:
	var file: String = UI_SOUNDS.get(name, "")
	if file == "":
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 45:
		return
	_last_play[name] = now
	play(stream("res://assets/audio/ui/%s.ogg" % file), volume_db - 4.0, 1.0, "UI")


## Any UI sound file by path (res://...ogg/.wav), rate-limited per path. Lets each UI area ship its own
## League sounds (assets/audio/ui/<area>/...) without editing UI_SOUNDS.
func ui_file(path: String, volume_db: float = 0.0, min_gap_ms: int = 45) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(path, -1000)) < min_gap_ms:
		return
	_last_play[path] = now
	var s := stream(path)
	if s != null:
		play(s, volume_db - 4.0, 1.0, "UI")


## Champion voice / stinger from the client (choose_vo, stinger, ban_vo).
func champ(alias: String, kind: String, volume_db: float = 0.0) -> void:
	play(stream("res://assets/champions/%s/audio/%s.ogg" % [alias.to_lower(), kind]), volume_db, 1.0, "UI")


# ===================================================================== music
## Crossfade to a music track (file name in assets/audio/music, without extension). "" stops.
func music(name: String, fade: float = 1.5, layers: Array = [], loop: bool = true) -> void:
	if name == _music_name:
		return
	_music_name = name
	var old := _music_cur
	for l in _layers:
		_fade_out(l, fade, true)
	_layers.clear()
	if old != null:
		_fade_out(old, fade, false)
	if name == "":
		_music_cur = null
		return
	var nxt := music_b if old == music_a else music_a
	var s := stream(name if name.begins_with("res://") else "res://assets/audio/music/%s.ogg" % name)
	if s == null:
		return
	if s is AudioStreamOggVorbis:
		s.loop = loop
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	nxt.stream = s
	nxt.volume_db = -40.0
	nxt.play()
	create_tween().tween_property(nxt, "volume_db", -6.0, fade)
	_music_cur = nxt
	for ln in layers:
		var ls := stream("res://assets/audio/music/%s.ogg" % ln)
		if ls == null:
			continue
		if ls is AudioStreamOggVorbis:
			ls.loop = true
		var lp := AudioStreamPlayer.new()
		lp.bus = "Music"
		lp.stream = ls
		lp.volume_db = -40.0
		add_child(lp)
		lp.play()
		create_tween().tween_property(lp, "volume_db", -10.0, fade * 2.0)
		_layers.append(lp)


## Longest track of a League music event from data/audio/<map>.json ("" if missing).
func game_music(map_file: String, event: String) -> String:
	var path := "res://data/audio/%s.json" % map_file
	if not FileAccess.file_exists(path):
		return ""
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not d.has("music") or not d.music.has(event):
		return ""
	var best := ""
	var best_len := -1.0
	for p in d.music[event]:
		var st := stream(p)
		if st != null and st.get_length() > best_len:
			best_len = st.get_length()
			best = p
	return best


func _fade_out(p: AudioStreamPlayer, fade: float, free_after: bool) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, fade)
	tw.tween_callback(func():
		p.stop()
		if free_after:
			p.queue_free())
