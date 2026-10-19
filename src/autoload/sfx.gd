extends Node
## Audio manager (autoload `Sfx`): pooled 2D/3D one-shots, named UI sounds, music with crossfade.
## Buses: Master > Music, SFX, UI.

## UI sound catalog: name -> [file in assets/audio/ui (no extension), loudness role]. The files are League's own
## client sounds, wired the way the real client wires them (rcp-fe-lol-uikit sound map: flat buttons use
## gold-hover/gold-click, checkboxes checkbox-click, radios radio-click, dropdowns dropdown-click/select, close
## buttons circlegold-hover / circlex-click, primary buttons magic-button-*, tabs/sub-nav text-click-small, ...).
## Raw client files ship at wildly different levels (hovers peak around -53 dBFS, stingers around -2 dBFS) because the
## client mixes them per category, so every sound is normalised from data/audio/ui_gain.json (measured peaks,
## tools/lol/ui_audio_gain.py) to the ROLE_TARGET peak of its role.
const ROLE_TARGET := {
	"hover": -23.0,     ## shimmer / tick under the cursor
	"click": -14.0,     ## ordinary button / tab / toggle clicks
	"big": -10.0,       ## confirm, play, lock-in
	"stinger": -9.0,    ## victory / defeat / card reveals / celebrations
	"tick": -17.0,      ## countdown ticks
	"notify": -12.0,    ## chat / notification dings
}
const HUD_TRIM_DB := 10.0       ## [ui-feel] League HUD mix -> our output (see hud())
const HUD_PEAK_CAP_DB := -1.0
const ROLE_GAP_MS := {"hover": 70, "click": 25, "big": 60, "stinger": 120, "tick": 60, "notify": 80}

const UI_SOUNDS := {
	# ---- generic uikit
	"hover": ["sfx-uikit-grid-hover", "hover"],
	"click": ["sfx-uikit-generic-click-small", "click"],
	"grid_hover": ["sfx-uikit-grid-hover", "hover"],
	"grid_click": ["sfx-uikit-grid-click", "click"],
	"grid_release": ["sfx-uikit-grid-click-release", "click"],
	"grid_big_hover": ["sfx-uikit-grid-big-hover", "hover"],
	"grid_big_click": ["sfx-uikit-grid-big-click", "click"],
	"gold_hover": ["sfx-uikit-button-gold-hover", "hover"],        ## flat button hover
	"gold_click": ["sfx-uikit-button-gold-click", "click"],        ## flat button click
	"flat_hover": ["sfx-uikit-button-gold-hover", "hover"],
	"flat_click": ["sfx-uikit-button-gold-click", "click"],
	"generic_hover": ["sfx-uikit-button-generic-hover", "hover"],
	"generic_click": ["sfx-uikit-button-generic-click", "click"],
	"big_click": ["sfx-uikit-button-big-click", "big"],
	"magic_hover": ["sfx-uikit-magic-button-hover", "hover"],      ## primary (call to action) button
	"magic_click": ["sfx-uikit-magic-button-click", "big"],
	"nav_click": ["sfx-nav-button-text-click", "click"],
	"tab": ["sfx-uikit-text-click-small", "click"],                ## tabs / sub-nav
	"text_click": ["sfx-uikit-button-text-click", "click"],
	"toggle": ["sfx-uikit-radio-click", "click"],                  ## radio / segmented option
	"checkbox": ["sfx-uikit-checkbox-click", "click"],
	"dropdown": ["sfx-uikit-dropdown-click", "click"],
	"dropdown_select": ["sfx-uikit-dropdown-select", "click"],
	"close_hover": ["sfx-uikit-button-circlegold-hover", "hover"],
	"close_click": ["sfx-uikit-button-circlex-click", "click"],
	"arrow_hover": ["sfx-uikit-arrow-button-hover", "hover"],
	"arrow_click": ["sfx-uikit-arrow-button-click", "click"],
	"back_click": ["sfx-uikit-button-arrowback-click", "click"],
	"fwd_click": ["sfx-uikit-button-arrowfwd-click", "click"],
	"pip": ["sfx-uikit-button-pip-click", "click"],
	"locked": ["sfx-uikit-button-locked-click", "click"],          ## disabled / not allowed
	"slide": ["sfx-uikit-click-and-slide", "click"],               ## slider grab
	"slide_tick": ["sfx-vc-volume-scroll-click", "click"],         ## slider step
	"slide_release": ["sfx-vc-volume-scroll-release", "click"],
	"drag": ["sfx-uikit-drag", "click"],
	"drop": ["sfx-uikit-drop", "click"],
	"edit": ["sfx-uikit-edit-click", "click"],
	"flyout_open": ["sfx-uikit-button-flyout-open-click", "click"],
	"flyout_close": ["sfx-uikit-button-flyout-close-click", "click"],
	"replay": ["sfx-uikit-button-replay-click", "click"],
	"framed_click": ["sfx-uikit-framed-icon-click", "click"],
	"toast": ["sfx-uikit-reward-toast", "notify"],
	# ---- lobby / nav / game select
	"play_hover": ["sfx-nav-button-play-hover", "hover"],
	"play_click": ["sfx-nav-button-play-click", "big"],
	"find_hover": ["sfx-lobby-button-find-match-hover", "hover"],
	"find_click": ["sfx-lobby-button-find-match-click", "big"],
	"quit_hover": ["sfx-lobby-button-quit-hover", "hover"],
	"quit_click": ["sfx-lobby-button-quit-click", "big"],
	"confirm_hover": ["sfx-gameselect-button-confirm-hover", "hover"],
	"confirm_click": ["sfx-gameselect-button-confirm-click", "big"],
	"to_lobby": ["sfx-gameselect-trans-to-lobby", "stinger"],
	"to_gameselect": ["sfx-lobby-trans-to-gameselect", "stinger"],
	"accept": ["sfx-ui-jade-match-accept", "big"],
	"decline": ["sfx-ui-jade-match-decline", "click"],
	"readycheck_click": ["sfx-readycheck-accept-button-click", "big"],
	"readycheck_hover": ["sfx-readycheck-accept-button-hover", "hover"],
	"readycheck_decline": ["sfx-readycheck-decline-button-click", "click"],
	"readycheck_countdown": ["sfx-readycheck-ringmagic-countdown", "stinger"],
	"jade_press": ["sfx-ui-jade-buttonpress", "click"],
	"jade_press1": ["sfx-ui-jade-buttonpress-1", "click"],
	"jade_locked": ["sfx-ui-jade-buttonlocked", "click"],
	"openstore": ["sfx-ui-jade-openstore", "click"],
	# ---- champion select
	"lockin_hover": ["sfx-cs-lockin-button-hover", "hover"],
	"lockin": ["sfx-cs-lockin-button-click", "big"],
	"lock_confirm": ["sfx-ui-jade-champselect-lockchampion", "big"],
	"lock_done": ["sfx-ui-jade-champselect-lockchampion-confirmed", "big"],
	"reroll_hover": ["sfx-cs-button-reroll-hover", "hover"],
	"reroll": ["sfx-cs-button-reroll-click", "big"],
	"swap": ["sfx-cs-button-swap-click", "click"],
	"swap_accepted": ["sfx-cs-notif-swaprequest-accepted", "notify"],
	"swap_declined": ["sfx-cs-notif-swaprequest-declined", "notify"],
	"swap_request": ["sfx-cs-notif-swaprequest-rcvd", "notify"],
	"bench": ["sfx-champ-select-bench-update", "notify"],
	"thumb_click": ["sfx-cs-button-thumbnail-click", "click"],
	"grid_open": ["sfx-cs-champgrid-button-open", "click"],
	"grid_close": ["sfx-cs-champgrid-button-close", "click"],
	"splash_fwd": ["sfx-cs-splash-forward", "click"],
	"splash_back": ["sfx-cs-splash-back", "click"],
	"ward_select": ["sfx-cs-ward-select", "click"],
	"spells_open": ["sfx-cs-spells-open", "click"],
	"boost_unlocked": ["sfx-cs-notif-boost-unlocked", "notify"],
	"card_appear": ["sfx-cs-aram-card-2-appear", "stinger"],
	"card_appear2": ["sfx-cs-aram-card-3-appear", "stinger"],
	"card_hover": ["sfx-cs-aram-card-hover", "hover"],
	"card_select": ["sfx-cs-aram-card-select", "stinger"],
	"tick": ["sfx-cs-timer-tick-small", "tick"],
	"tick_big": ["sfx-cs-timer-tick", "tick"],
	"countdown": ["sfx-ui-jade-champselect-countdown-single", "tick"],
	"countdown10": ["sfx-ui-jade-champselect-countdown10", "tick"],
	"your_turn": ["sfx-ui-jade-champselect-yourturn", "notify"],
	"your_pick": ["sfx-cs-draft-notif-yourpick", "notify"],
	"pick_intro": ["sfx-cs-draft-pick-intro", "stinger"],
	"cs_exit": ["sfx-ui-jade-champselect-exit", "click"],
	"browse": ["sfx-ui-jade-champselect-browse-skins", "click"],
	# ---- end of game
	"victory": ["sfx-eog-ui-exp-burst", "stinger"],
	"defeat": ["sfx-eog-ui-exp-burst-negative", "stinger"],
	"neutral": ["sfx-eog-ui-neutral-burst", "stinger"],
	"eog": ["sfx-eog-chaos-order", "stinger"],
	"flare": ["sfx-eog-ui-edge-flare", "stinger"],
	"consolation": ["sfx-uikit-consolation-stinger", "stinger"],
	"honor_intro": ["sfx-honor-voting-intro", "stinger"],
	"honor_team": ["sfx-honor-scoreboard-team-choice", "click"],
	"honor_cast": ["sfx-honor-vote-cast", "click"],
	"postgame_level": ["sfx-levelup-postgame-generic", "stinger"],
	"celebrate_intro": ["sfx-celebrate-notif-intro", "stinger"],
	"celebrate": ["sfx-vignette-celebration-intro", "stinger"],
	"celebrate_outro": ["sfx-vignette-celebration-outro", "stinger"],
	"reward": ["sfx-celebrate-receive-generic", "stinger"],
	# ---- chat / social
	"chat_rcvd": ["sfx-ui-jade-chat-message-receive", "notify"],
	"chat_notif": ["sfx-soc-notif-chat-rcvd", "notify"],
	"soc_click": ["sfx-soc-ui-click-generic", "click"],
	"soc_drag": ["sfx-soc-ui-drag", "click"],
	"soc_drop": ["sfx-soc-ui-drop", "click"],
	# ---- store buttons (shop agent keeps these names)
	"buy": ["sfx-purchase-button-click", "big"],
	"buy_hover": ["sfx-purchase-button-hover", "hover"],
}

var players: Array = []
var players3d: Array = []
var ui_players: Array = []    ## dedicated UI voices (bus "UI")
var _ui_path: Array = []      ## file currently playing on each UI voice (hovers restart instead of stacking)
var _ui_rr := 0
var _cache := {}
var _req := {}                ## path -> true while a threaded load request is outstanding
var _gain := {}               ## res:// path -> {peak, rms, len} (tools/lol/ui_audio_gain.py)
var _last_play := {}          ## name -> time (rate limiting)
var _last_role := {}          ## role -> time (global per-role rate limit)
var _log := false             ## --sfxlog: print every UI sound with its resolved gain (verification without ears)
var stats := {}               ## name/path -> play count (for harnesses)
var hud_log: Array = []       ## [ui-feel] [msec, event, applied dB, file] of the last 400 HUD sounds (harnesses / --sfxlog)
var _hud := {}                ## [ui-feel] Wwise event -> {"v": [{f, g, p, len}]} from data/audio/hud_sfx.json
var music_a: AudioStreamPlayer
var music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer = null
var _music_name := ""
var _layers: Array = []       ## extra synced music layers


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log = "--sfxlog" in OS.get_cmdline_user_args()
	_setup_buses()
	for i in 24:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	for i in 14:
		var u := AudioStreamPlayer.new()
		u.bus = "UI"
		add_child(u)
		ui_players.append(u)
		_ui_path.append("")
	music_a = AudioStreamPlayer.new()
	music_b = AudioStreamPlayer.new()
	for m in [music_a, music_b]:
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
	apply_volumes()
	_load_gain()
	_load_hud()
	_prewarm()


func _load_gain() -> void:
	var path := "res://data/audio/ui_gain.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			_gain = d


## Every catalog sound is requested on a background thread at boot so the first hover/click never loads from disk.
func _prewarm() -> void:
	for k in UI_SOUNDS:
		var path := _path_of(UI_SOUNDS[k][0])
		if not _cache.has(path) and not _req.has(path) and ResourceLoader.exists(path):
			if ResourceLoader.load_threaded_request(path, "", false) == OK:
				_req[path] = true


## [ui-feel] League's HUD mix (tools/lol/extract_hud_audio.py): per event the WAVs, their Wwise gain and peak.
func _load_hud() -> void:
	var path := "res://data/audio/hud_sfx.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.get("events") is Dictionary:
			_hud = d.events
	for ev in _hud:
		for v in _hud[ev].v:
			var p: String = v.f
			if not _cache.has(p) and not _req.has(p) and ResourceLoader.exists(p):
				if ResourceLoader.load_threaded_request(p, "", false) == OK:
					_req[p] = true


func _path_of(file: String) -> String:
	return "res://assets/audio/ui/%s.ogg" % file


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
	var s: AudioStream = null
	if _req.has(path):
		_req.erase(path)
		s = ResourceLoader.load_threaded_get(path)
	elif ResourceLoader.exists(path):
		s = load(path)
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


## dB to add so this file's measured peak lands on the role's target peak (0 when it was never measured).
func gain_for(path: String, role: String) -> float:
	var g = _gain.get(path)
	if g == null:
		return 0.0
	return clampf(float(ROLE_TARGET.get(role, -14.0)) - float(g.get("peak", -14.0)), -12.0, 42.0)


## Named client UI sound (see UI_SOUNDS). Rate-limited so hover spam stays clean.
func ui(name: String, volume_db: float = 0.0) -> void:
	var e = UI_SOUNDS.get(name)
	if e == null:
		if _log:
			push_warning("Sfx.ui: unknown sound '%s'" % name)
		return
	var role: String = e[1]
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 30:
		return
	if (role == "hover" or role == "tick") and now - int(_last_role.get(role, -1000)) < int(ROLE_GAP_MS.get(role, 25)):
		return
	_last_play[name] = now
	_last_role[role] = now
	_play_ui(_path_of(e[0]), role, volume_db, name)


## Any UI sound file by path (res://...ogg/.wav), rate-limited per path. Lets each UI area ship its own
## League sounds (assets/audio/ui/<area>/...) without editing UI_SOUNDS. `role` selects the loudness target;
## files listed in data/audio/ui_gain.json are normalised, anything else plays as authored.
func ui_file(path: String, volume_db: float = 0.0, min_gap_ms: int = 45, role: String = "click") -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(path, -1000)) < min_gap_ms:
		return
	_last_play[path] = now
	_play_ui(path, role, volume_db, path)


func has_hud(ev: String) -> bool:
	return _hud.has(ev)


## [ui-feel] HUD sounds are mastered per event in League's Wwise banks (data/audio/hud_sfx.json: "g" is the summed
## Volume + MakeUpGain, "p" the file's peak). Level = peak + g + HUD_TRIM_DB, never above HUD_PEAK_CAP_DB, so the
## relative loudness between HUD events is League's (level-up click -16 dB, shop open -6 dB, champion level-up -11 dB)
## while the whole HUD sits above the in-match SFX the way the real client mixes it. Returns the dB applied
## (-INF when the event is unknown / muted / rate-limited). `extra_db` is a per-call trim, `min_gap_ms` the per-event
## repeat guard (no double-play when two code paths report the same press).
func hud(ev: String, extra_db: float = 0.0, min_gap_ms: int = 60) -> float:
	var e = _hud.get(ev)
	if e == null or e.v.is_empty():
		if _log:
			push_warning("Sfx.hud: unknown HUD event '%s'" % ev)
		return -INF
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(ev, -1000)) < min_gap_ms:
		return -INF
	var v: Dictionary = e.v[G.rng.randi() % e.v.size()]
	if float(v.g) <= -60.0:
		return -INF
	_last_play[ev] = now
	var db := minf(float(v.p) + float(v.g) + HUD_TRIM_DB, HUD_PEAK_CAP_DB) - float(v.p) + extra_db
	hud_log.append([now, ev, db, v.f])
	if hud_log.size() > 400:
		hud_log.pop_front()
	_voice(v.f, db, "click", ev)
	return db


func _play_ui(path: String, role: String, volume_db: float, tag: String) -> void:
	_voice(path, gain_for(path, role) + volume_db, role, tag)


func _voice(path: String, db: float, role: String, tag: String) -> void:
	var s := stream(path)
	if s == null:
		if _log:
			push_warning("Sfx: missing UI sound %s" % path)
		return
	# hovers restart their own voice instead of stacking into a wash
	var idx := -1
	if role == "hover":
		idx = _ui_path.find(path)
		if idx >= 0 and not ui_players[idx].playing:
			idx = -1
	if idx < 0:
		for i in ui_players.size():
			var k := (_ui_rr + i) % ui_players.size()
			if not ui_players[k].playing:
				idx = k
				break
	if idx < 0:
		idx = _ui_rr   # all busy: steal the round-robin voice
	_ui_rr = (idx + 1) % ui_players.size()
	var p: AudioStreamPlayer = ui_players[idx]
	p.stream = s
	p.volume_db = db
	p.pitch_scale = 1.0
	p.play()
	_ui_path[idx] = path
	stats[tag] = int(stats.get(tag, 0)) + 1
	if _log:
		print("SFX %s [%s] %s vol=%+.1fdB len=%.2fs" % [tag, role, path.get_file(), db, s.get_length()])


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
