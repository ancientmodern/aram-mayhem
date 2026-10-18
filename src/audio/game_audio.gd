class_name GameAudio
extends Node3D
## In-match audio: League's own sound events (extracted by tools/lol/extract_game_audio.py into
## data/audio/*.json) played as pooled 3D sounds heard from the camera's ground focus, plus the
## announcer queue, player voice lines, ambience and structure sounds.

const POOL_3D := 48
const POOL_2D := 16

var m = null
var events := {}                 ## event name -> Array of res:// paths
var _streams := {}               ## path -> AudioStream
var _requested := {}             ## path -> true (background load requested, not collected yet)
var _p3: Array = []
var _p2: Array = []
var _listener: AudioListener3D
var _last := {}                  ## rate limiting: key -> time (msec)
var _spell_events := {}          ## champion alias -> {slot -> {cast: [], hit: [], vo: []}}
var _ann_queue: Array = []       ## [event, queued_at]
var _ann_player: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _vo_cd := {}                 ## player voice line cooldowns
var _gust_t := 20.0


func setup(p_match) -> void:
	m = p_match
	for f in ["shared", "map12", "announcer"]:
		_load_map("res://data/audio/%s.json" % f)
	for c in m.champions:
		_load_map("res://data/audio/%s.json" % c.alias.to_lower())
		_index_champion(c.alias)
	prefetch_all()


func _ready() -> void:
	_listener = AudioListener3D.new()
	add_child(_listener)
	_listener.make_current()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 14.0
		p.max_distance = 42.0
		p.panning_strength = 0.6
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_p3.append(p)
	for i in POOL_2D:
		var q := AudioStreamPlayer.new()
		q.bus = "SFX"
		add_child(q)
		_p2.append(q)
	_ann_player = AudioStreamPlayer.new()
	_ann_player.bus = "UI"
	add_child(_ann_player)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "SFX"
	_ambience.volume_db = -15.0
	add_child(_ambience)
	G.announcer_event.connect(_on_announcer)
	G.level_up.connect(_on_level_up)
	G.gold_earned.connect(_on_gold)
	G.champion_killed.connect(_on_champion_killed)
	G.structure_destroyed.connect(_on_structure_destroyed)
	_start_ambience()


func _load_map(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		return
	for section in d.values():
		if section is Dictionary:
			for k in section:
				events[k] = section[k]


# ===================================================================== playback
func has(ev: String) -> bool:
	return events.has(ev)


## Every stream this match can play is requested on background threads at setup (during the loading
## screen), so playback never loads/decodes from disk on the main thread (that caused 20-60 ms hitches).
func prefetch_all() -> void:
	if "--noprefetch" in OS.get_cmdline_user_args():
		return
	for ev in events:
		var list = events[ev]
		if not (list is Array):
			continue
		for path in list:
			if path is String and not _streams.has(path) and not _requested.has(path) and ResourceLoader.exists(path):
				if ResourceLoader.load_threaded_request(path, "", false) == OK:
					_requested[path] = true


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	if _requested.has(path):
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null   # still loading in the background: skip this one play rather than stall the frame
		_requested.erase(path)
		var r: AudioStream = ResourceLoader.load_threaded_get(path) if st == ResourceLoader.THREAD_LOAD_LOADED else null
		_streams[path] = r
		return r
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_streams[path] = s
	return s


func _pick(ev: String) -> AudioStream:
	var list: Array = events.get(ev, [])
	if list.is_empty():
		return null
	return _stream(list[G.rng.randi() % list.size()])


func _rate_ok(key: String, ms: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_last.get(key, -100000)) < ms:
		return false
	_last[key] = now
	return true


## Play a League sound event. pos = null plays it in 2D.
func play(ev: String, pos = null, volume_db: float = 0.0, pitch_var: float = 0.03) -> void:
	var pa := Prof.t0()
	_play(ev, pos, volume_db, pitch_var)
	Prof.add("audio.play", pa)


func _play(ev: String, pos, volume_db: float, pitch_var: float) -> void:
	if ev == "" or not events.has(ev) or not _rate_ok(ev, 40):
		return
	var s := _pick(ev)
	if s == null:
		return
	var pitch := 1.0 + G.rng.randf_range(-pitch_var, pitch_var)
	if pos == null:
		for q in _p2:
			if not q.playing:
				q.stream = s
				q.volume_db = volume_db
				q.pitch_scale = pitch
				q.play()
				return
		return
	var p3 := _free_3d(pos)
	if p3 == null:
		return
	p3.global_position = pos
	p3.stream = s
	p3.volume_db = volume_db
	p3.pitch_scale = pitch
	p3.play()


func _free_3d(pos: Vector3) -> AudioStreamPlayer3D:
	# skip sounds far off screen
	if G.flat_dist(pos, _listener.global_position) > 46.0:
		return null
	for p in _p3:
		if not p.playing:
			return p
	return null


func _process(_dt: float) -> void:
	if m == null or m.camera_rig == null:
		return
	_listener.global_position = m.camera_rig.focus + Vector3(0, 7.0, 0)
	_listener.global_basis = m.camera_rig.cam.global_basis
	# announcer: one line at a time, drop stale ones
	if not _ann_player.playing and not _ann_queue.is_empty():
		var item: Array = _ann_queue.pop_front()
		while not _ann_queue.is_empty() and Time.get_ticks_msec() - int(item[1]) > 4500:
			item = _ann_queue.pop_front()
		var s := _pick(item[0])
		if s != null:
			_ann_player.stream = s
			_ann_player.play()
	# occasional wind gusts across the bridge
	_gust_t -= _dt
	if _gust_t <= 0.0:
		_gust_t = G.rng.randf_range(18.0, 40.0)
		play("Play_sfx_env_map12_heavywind_cast", null, -14.0, 0.08)


func _start_ambience() -> void:
	var s := _pick("Play_sfx_Env_Map12_Ambience_base")
	if s == null:
		return
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	_ambience.stream = s
	_ambience.play()


# ===================================================================== champions
func _index_champion(alias: String) -> void:
	var slots: Dictionary = ChampionDB.game_data(alias).get("spell_slots", {})
	var pre := "Play_sfx_%s_" % alias
	var vpre := "Play_vo_%s_" % alias
	var out := {}
	for k in ["Q", "W", "E", "R"]:
		var base: String = str(slots.get(k, alias + k)).replace("1Wrapper", "").replace("Wrapper", "")
		var cast := []
		var hit := []
		var vo := []
		for ev in events:
			if ev.begins_with(pre):
				var mid: String = ev.substr(pre.length())
				if not mid.begins_with(base):
					continue
				var low := mid.to_lower()
				if low.ends_with("_oncast") or low.ends_with("_cast"):
					cast.append(ev)
				elif "hit" in low:
					hit.append(ev)
			elif ev.begins_with(vpre) and ev.substr(vpre.length()).begins_with(base) and "cast" in ev.to_lower():
				vo.append(ev)
		# prefer the exact "<Spell>_OnCast" event
		var exact := pre + base + "_OnCast"
		if events.has(exact):
			cast = [exact]
		if cast.is_empty():
			for ev in events:
				if ev.begins_with(pre + base) and ("buffactivate" in ev.to_lower() or "missilelaunch" in ev.to_lower()):
					cast.append(ev)
					break
		out[k] = {"cast": cast, "hit": hit, "vo": vo}
	_spell_events[alias] = out


func _is_champ(u) -> bool:
	return u != null and is_instance_valid(u) and u.kind == G.Kind.CHAMPION


func _vol(u) -> float:
	# the player's own sounds a touch louder
	return 0.0 if u == G.player else -3.0


## Attack wind-up (swing / cast) sound.
func attack_start(u, crit: bool) -> void:
	if _is_champ(u):
		var a: String = u.alias
		var n := [""] if G.rng.randf() < 0.5 else ["2"]
		var ev := "Play_sfx_%s_%s%s_OnCast" % [a, a, "CritAttack" if crit else "BasicAttack" + n[0]]
		if not events.has(ev):
			ev = "Play_sfx_%s_%sBasicAttack_OnCast" % [a, a]
		play(ev, u.global_position, _vol(u) - 4.0)
		if G.rng.randf() < 0.12:
			_vo_line(u, ["%sBasicAttack_cast3D" % a, "%sBasicAttack2_cast3D" % a, "%sCritAttack_cast3D" % a if crit else "%sBasicAttack3_cast3D" % a], -4.0, 2500)
	elif u.kind == G.Kind.MINION:
		play(_minion_ev(u, "OnCast"), u.global_position, -20.0)
	elif u.kind == G.Kind.TURRET:
		var t = u.get("attack_target")
		var champ: bool = t != null and is_instance_valid(t) and t.kind == G.Kind.CHAMPION
		play("Play_sfx_Env_TurretChampionBasicAttack_cast" if champ else "Play_sfx_Env_TurretBasicAttack_missilelaunch", u.global_position, -6.0)


## Basic attack impact sound (on the target).
func attack_hit(u, t, crit: bool) -> void:
	if t == null or not is_instance_valid(t):
		return
	if _is_champ(u):
		var a: String = u.alias
		var ev := "Play_sfx_%s_%s%s_OnHit" % [a, a, "CritAttack" if crit else "BasicAttack"]
		if not events.has(ev):
			ev = "Play_sfx_%s_%sBasicAttack_OnHit" % [a, a]
		play(ev, t.global_position, _vol(u) - 5.0)
	elif u.kind == G.Kind.MINION:
		play(_minion_ev(u, "OnHit"), t.global_position, -22.0)
	elif u.kind == G.Kind.TURRET:
		play("Play_sfx_Env_TurretChampionBasicAttack_hit" if t.kind == G.Kind.CHAMPION else "Play_sfx_Env_TurretBasicAttack_hit", t.global_position, -5.0)


func _minion_ev(u, phase: String) -> String:
	var team := "Order" if u.team == G.Team.ORDER else "Chaos"
	var typ := "Melee"
	match int(u.minion_type):
		Minion.Type.CASTER: typ = "Ranged"
		Minion.Type.SIEGE: typ = "Siege"
		Minion.Type.SUPER: typ = "Super"
	var n: String = ["", "2", "3"][G.rng.randi() % 3]
	var ev := "Play_sfx_HA_%sMinion%sBasicAttack%s_%s" % [team, typ, n, phase]
	if not events.has(ev):
		ev = "Play_sfx_HA_%sMinion%sBasicAttack_%s" % [team, typ, phase]
	return ev


## Ability cast (slot 0-3) or summoner spell.
func spell_cast(u, ab) -> void:
	if not _is_champ(u) or ab == null:
		return
	if ab.is_summoner:
		var sev := {"Flash": "Play_sfx_SummonerFlash_OnCast", "Heal": "Play_sfx_SummonerHeal_OnCast",
			"Barrier": "Play_sfx_SummonerBarrier_OnCast", "Mark": "Play_sfx_SummonerSnowball_OnCast",
			"Ghost": "Play_sfx_SummonerHaste_OnCast", "Cleanse": "Play_sfx_SummonerBoost_OnCast",
			"Ignite": "Play_sfx_SummonerDot_OnCast", "Clarity": "Play_sfx_SummonerMana_OnCast"}.get(ab.id, "")
		if ab.id == "Mark" and ab.recast_window > 0.0:
			sev = "Play_sfx_SnowballFollowupCast_OnCast"
		play(sev, u.global_position, _vol(u))
		return
	var slot: int = ab.slot
	if slot < 0 or slot > 3:
		return
	var info: Dictionary = _spell_events.get(u.alias, {}).get("QWER"[slot], {})
	var casts: Array = info.get("cast", [])
	if not casts.is_empty():
		play(casts[0] if casts.size() == 1 else casts[G.rng.randi() % casts.size()], u.global_position, _vol(u))
	var vos: Array = info.get("vo", [])
	if not vos.is_empty() and G.rng.randf() < (0.6 if slot == 3 else 0.3):
		_vo_line(u, vos, -1.0, 1200, true)


## Spell damage landing on a target (rate limited per ability so AoE doesn't stack).
func spell_hit(u, ab, t) -> void:
	if not _is_champ(u) or ab == null or t == null or not is_instance_valid(t):
		return
	var slot: int = ab.slot
	if slot < 0 or slot > 3:
		return
	if not _rate_ok("hit%d_%d" % [u.get_instance_id(), slot], 120):
		return
	var hits: Array = _spell_events.get(u.alias, {}).get("QWER"[slot], {}).get("hit", [])
	if not hits.is_empty():
		var ev: String = hits[G.rng.randi() % hits.size()]
		_last.erase(ev)
		play(ev, t.global_position, _vol(u) - 2.0)


## Champion voice line from a list of event suffixes (or full names when `full`).
func _vo_line(u, names: Array, vol: float, cd_ms: int, full: bool = false) -> void:
	if not _rate_ok("vo%d" % u.get_instance_id(), cd_ms):
		return
	var cands := []
	for n in names:
		var ev: String = n if full else "Play_vo_%s_%s" % [u.alias, n]
		if events.has(ev):
			cands.append(ev)
	if cands.is_empty():
		return
	play(cands[G.rng.randi() % cands.size()], u.global_position, vol + _vol(u), 0.0)


## Player command voice lines (League plays these 2D for your own champion only).
func player_order(kind: String) -> void:
	var c = G.player
	if c == null or c.dead:
		return
	var key := "order_" + kind
	var now := Time.get_ticks_msec()
	if now < int(_vo_cd.get(key, 0)):
		return
	if G.rng.randf() > (0.35 if kind == "move" else 0.5):
		_vo_cd[key] = now + 1500
		return
	_vo_cd[key] = now + G.rng.randi_range(7000, 13000)
	var ev := "Play_vo_%s_%s" % [c.alias, "Move2DStandard" if kind == "move" else "Attack2DGeneral"]
	if kind == "move" and not events.has(ev):
		ev = "Play_vo_%s_Move2DFirst" % c.alias
	play(ev, null, -3.0, 0.0)


func emote(u, kind: String) -> void:
	if not _is_champ(u):
		return
	var k := {"joke": "Joke3D", "taunt": "Taunt3D", "laugh": "Laugh3D", "dance": "Dance3D"}.get(kind, "")
	play("Play_sfx_%s_%s_buffactivate" % [u.alias, k], u.global_position, _vol(u) - 2.0)
	_vo_line(u, ["%sGeneral" % k], 0.0, 800)


# ===================================================================== global events
func _on_level_up(c, _lvl) -> void:
	if c == G.player:
		play("Play_sfx_levelup_levelup", null, -4.0, 0.0)


func _on_gold(c, amount, src) -> void:
	if c == G.player and src != null and is_instance_valid(src) and src.kind == G.Kind.MINION and amount > 0:
		play("Play_sfx_GoldAquisition_P_cast", null, -8.0, 0.02)


func _on_champion_killed(victim, killer, _assisters) -> void:
	var pa := Prof.t0()
	_on_champion_killed_impl(victim, killer)
	Prof.slow("death.audio", pa, "")


func _on_champion_killed_impl(victim, killer) -> void:
	if _is_champ(victim):
		play("Play_sfx_%s_Death3D_cast" % victim.alias, victim.global_position, -2.0, 0.0)
		_vo_line(victim, ["Death3D"], 0.0, 0)
		if victim == G.player:
			play("Play_sfx_Death_Self", null, -4.0, 0.0)
	if _is_champ(killer) and _is_champ(victim):
		var specific := "Kill3D%s" % victim.alias
		_vo_line(killer, [specific, "Kill3DGeneral"], -1.0, 3000)


func on_respawn(c) -> void:
	if c == G.player:
		play("Play_sfx_Respawn_respawn", null, -4.0, 0.0)
	_vo_line(c, ["Respawn2DGeneral"], -2.0, 0)


func _on_structure_destroyed(s, _killer) -> void:
	var side := "Order" if s.team == G.Team.ORDER else "Chaos"
	match s.kind:
		G.Kind.TURRET:
			play("Play_sfx_Env_Turret_map12_%sTurret_break0%d" % [side, G.rng.randi_range(1, 3)], s.global_position, 2.0, 0.0)
		G.Kind.INHIBITOR:
			play("Play_sfx_Env_map12_%s_inhibitor_death_cast" % side.to_lower(), s.global_position, 2.0, 0.0)
		G.Kind.NEXUS:
			var ev := "Play_sfx_Env_Global_EoG_ChaosNexus_death_cast" if s.team == G.Team.CHAOS else "Play_sfx_Env_Global_EoG_OrderNexus_death_oc"
			play(ev, null, 0.0, 0.0)


# ===================================================================== announcer
const ANN := "Play_vo_Announcer_Female1_"


func _on_announcer(key: String, ally_side: bool) -> void:
	var you_killed := false
	var victim_is_you := false
	var mine := "YourTeam" if ally_side else "EnemyTeam"
	var ev := ""
	match key:
		"welcome": ev = ANN + "StartGameMessage2Map12"
		"minions_30": ev = ANN + "StartGameMessage1Map11"
		"minions_spawned": ev = ANN + "MinionSpawn"
		"ace": ev = ANN + "Ace" + mine
		"turret_destroyed": ev = ANN + "TurretLostEnemyTeam"
		"turret_lost": ev = ANN + "TurretLostYourTeam"
		"inhib_destroyed": ev = ANN + "InhibitorLostEnemyTeam"
		"inhib_lost": ev = ANN + "InhibitorLostYourTeam"
		"victory": ev = "Play_vo_Announcer_Global_Female1_OnVictory"
		"defeat": ev = "Play_vo_Announcer_Global_Female1_OnDefeat"
		"you_slain": ev = ANN + "KillChampionHeroYouEnemyTeam"
		"you_killed": ev = ANN + "KillChampionYouHeroYourTeam"
		"enemy_slain": ev = ANN + "KillChampionHeroHeroYourTeam"
		"ally_slain": ev = ANN + "KillChampionHeroHeroEnemyTeam"
		_:
			var names := {"first_blood": "FirstBlood", "double_kill": "DoubleKill", "triple_kill": "TripleKill",
				"quadra_kill": "QuadraKill", "penta_kill": "PentaKill", "shutdown": "Shutdown", "killing_spree": "KillingSpree",
				"rampage": "Rampage", "unstoppable": "Unstoppable", "dominating": "Dominating", "godlike": "Godlike",
				"legendary": "Legendary"}
			var base: String = names.get(key, "")
			if base == "":
				return
			var last = m.events.back() if not m.events.is_empty() else null
			you_killed = last != null and last.killer == G.player
			ev = ANN + base + ("YouYourTeam" if you_killed else "Hero" + mine)
	if events.has(ev):
		_ann_queue.append([ev, Time.get_ticks_msec()])
