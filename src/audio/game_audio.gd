class_name GameAudio
extends Node3D
## In-match audio: League's own sound events (extracted by tools/lol/extract_game_audio.py into
## data/audio/*.json) played as pooled 3D sounds heard from the camera's ground focus, plus the
## announcer (League-style priority queue), player voice lines, ambience loops and structure sounds.
##
## [juice] Event routing is derived from the event names themselves (see tools/lol/audit_game_audio.py, which
## mirrors _index_champion): every cast / missile launch / buff activation / hit event of a champion is routed to its
## ability slot, and basic attack + crit events to the attack hooks, so no extracted sound stays unused by accident.
## `--audiolog` prints every played event (time, event, tag); unknown events warn once.

const POOL_3D := 48
const POOL_2D := 16
const LOOP_POOL := 10

var m = null
var moments: Moments = null
var events := {}                 ## event name -> Array of res:// paths
var _streams := {}               ## path -> AudioStream
var _requested := {}             ## path -> true (background load requested, not collected yet)
var _p3: Array = []
var _p2: Array = []
var _listener: AudioListener3D
var _last := {}                  ## rate limiting: key -> time (msec)
var _spell_events := {}          ## champion alias -> {"QWER" slot -> {cast, launch, act, hit, vo}}
var _ba_events := {}             ## champion alias -> {cast, crit_cast, hit, crit_hit}
var _ann_player: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _vo_cd := {}                 ## player voice line cooldowns
var _gust_t := 20.0
var _warned := {}
var log_enabled := false
var play_log: Array = []         ## [[match time, event, tag]] (ring of the last 600 played events, for harnesses)
var stats := {}                  ## event -> play count

# ---- announcer queue
class Ann:
	var ev := ""
	var key := ""
	var prio := 0
	var ttl := 5.0
	var t := 0.0
var _ann_queue: Array = []
var _ann_cur_prio := 0
var _ann_gap := 0.0
var _turrets_down := 0
var _ann_locked := false          ## after victory / defeat nothing else is announced

# ---- ambience / structure loops
class Loop:
	var player: AudioStreamPlayer3D
	var ev := ""
	var pos := Vector3.ZERO
	var eid := -1                 ## emitter currently using this loop (-1 = free)
var _emitters: Array = []        ## [{ev, pos}] static world emitters (braziers) culled around the camera
var _loops: Array[Loop] = []
var _emit_t := 0.0
var _poll_t := 0.0
var _poll := {}                  ## state tracked by _poll_world()
var _wave_seen := 0


func setup(p_match) -> void:
	m = p_match
	log_enabled = "--audiolog" in OS.get_cmdline_user_args()
	for f in ["shared", "map12", "announcer"]:
		_load_map("res://data/audio/%s.json" % f)
	for c in m.champions:
		_load_map("res://data/audio/%s.json" % c.alias.to_lower())
		_index_champion(c.alias)
	prefetch_all()
	moments = Moments.new()
	moments.name = "Moments"
	add_child(moments)
	moments.setup(m)
	_setup_emitters()


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
	for i in LOOP_POOL:
		var lp := AudioStreamPlayer3D.new()
		lp.bus = "SFX"
		lp.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		lp.unit_size = 6.0
		lp.max_distance = 26.0
		lp.panning_strength = 0.7
		lp.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(lp)
		var l := Loop.new()
		l.player = lp
		_loops.append(l)
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
	G.match_over.connect(_on_match_over)
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


func _note(ev: String, tag: String) -> void:
	stats[ev] = int(stats.get(ev, 0)) + 1
	var t: float = m.time if m != null else 0.0
	play_log.append([t, ev, tag])
	if play_log.size() > 600:
		play_log.pop_front()
	if log_enabled:
		print("AUDIO %7.2f %s %s" % [t, ev, tag])


## Play a League sound event. pos = null plays it in 2D.
func play(ev: String, pos = null, volume_db: float = 0.0, pitch_var: float = 0.03) -> void:
	var pa := Prof.t0()
	_play(ev, pos, volume_db, pitch_var)
	Prof.add("audio.play", pa)


func _play(ev: String, pos, volume_db: float, pitch_var: float, pitch_base: float = 1.0) -> bool:
	if ev == "":
		return false
	if not events.has(ev):
		if not _warned.has(ev):
			_warned[ev] = true
			push_warning("GameAudio: unknown event %s" % ev)
		return false
	if not _rate_ok(ev, 40):
		return false
	var s := _pick(ev)
	if s == null:
		return false
	var pitch := pitch_base * (1.0 + G.rng.randf_range(-pitch_var, pitch_var))
	if pos == null:
		for q in _p2:
			if not q.playing:
				q.stream = s
				q.volume_db = volume_db
				q.pitch_scale = pitch
				q.play()
				_note(ev, "2d")
				return true
		return false
	var p3 := _free_3d(pos)
	if p3 == null:
		return false
	p3.global_position = pos
	p3.stream = s
	p3.volume_db = volume_db
	p3.pitch_scale = pitch
	p3.play()
	_note(ev, "3d")
	return true


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
	_ann_tick(_dt)
	# occasional wind gusts across the bridge
	_gust_t -= _dt
	if _gust_t <= 0.0:
		_gust_t = G.rng.randf_range(18.0, 40.0)
		play("Play_sfx_env_map12_heavywind_cast", null, -14.0, 0.08)
	_emit_t -= _dt
	if _emit_t <= 0.0:
		_emit_t = 0.3
		_update_loops()
	_poll_t -= _dt
	if _poll_t <= 0.0:
		_poll_t = 0.25
		_poll_world()


func _start_ambience() -> void:
	var s := _pick("Play_sfx_Env_Map12_Ambience_base")
	if s == null:
		return
	_loopify(s)
	_ambience.stream = s
	_ambience.play()


static func _loopify(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)


# ===================================================================== champion event routing
## League event name tokens -> what the sound is for.
const CAST_SUF := ["_oncast", "_cast", "_missilecast", "_castself", "_cast_self"]
const LAUNCH_SUF := ["_onmissilelaunch", "_missilelaunch", "_onmissilecast"]
const ACT_SUF := ["_buffactivate", "_onbuffactivate"]
## Events whose spell family does not start with the ability's script name (League names them after helper spells).
const ALT_BASES := {
	"Yasuo": {"E": ["YasuoDash"], "Q": ["YasuoQ"], "R": ["YasuoRKnockUp"], "W": ["YasuoWMoving"]},
	"Malphite": {"W": ["MalphiteShieldEffect"], "E": ["MalphiteThunderclap"], "R": ["UFSlash"]},
	"Leona": {"E": ["LeonaZenithBlade"], "W": ["LeonaSolarBarrier"], "R": ["LeonaSolarFlare"]},
	"Ezreal": {"W": ["EzrealWAttach"], "E": ["EzrealE"]},
	"Darius": {"Q": ["DariusCleave"], "R": ["DariusExecute"]},
	"Jinx": {"Q": ["JinxQ"], "W": ["JinxW"], "E": ["JinxE"], "R": ["JinxR"]},
}


static func _kind_of(low: String) -> Array:
	for s in CAST_SUF:
		if low.ends_with(s):
			return ["cast", low.substr(0, low.length() - s.length())]
	for s in LAUNCH_SUF:
		if low.ends_with(s):
			return ["launch", low.substr(0, low.length() - s.length())]
	for s in ACT_SUF:
		if low.ends_with(s):
			return ["act", low.substr(0, low.length() - s.length())]
	var toks := low.split("_")
	for i in range(1, toks.size()):
		var t: String = toks[i]
		if t == "hit" or t == "onhit" or t.begins_with("hit") or t == "beamend" or t == "land" or t == "detonate":
			return ["hit", "_".join(toks.slice(0, i))]
	return ["other", low]


func _index_champion(alias: String) -> void:
	var slots: Dictionary = ChampionDB.game_data(alias).get("spell_slots", {})
	var pre := "Play_sfx_%s_" % alias
	var vpre := "Play_vo_%s_" % alias
	var out := {}
	var bases := {}
	for k in ["Q", "W", "E", "R"]:
		var base: String = str(slots.get(k, alias + k)).replace("1Wrapper", "").replace("Wrapper", "")
		var list: Array = [base.to_lower()]
		for a in ALT_BASES.get(alias, {}).get(k, []):
			list.append(String(a).to_lower())
		bases[k] = list
		out[k] = {"cast": [], "launch": [], "act": [], "hit": [], "vo": []}
	var ba := {"cast": [], "crit_cast": [], "hit": [], "crit_hit": []}
	for ev in events:
		if ev.begins_with(vpre):
			var vlow: String = ev.substr(vpre.length()).to_lower()
			if "cast" in vlow:
				for k in ["Q", "W", "E", "R"]:
					if _fam_matches(vlow.replace("_cast3d", "").replace("cast3d", ""), bases[k]):
						out[k].vo.append(ev)
						break
			continue
		if not ev.begins_with(pre):
			continue
		var low: String = ev.substr(pre.length()).to_lower()
		var kc := _kind_of(low)
		var kind: String = kc[0]
		var fam: String = kc[1]
		if "basicattack" in low or "critattack" in low or "passiveattack" in low:
			var crit := "crit" in low
			if kind == "cast" or kind == "launch":
				ba["crit_cast" if crit else "cast"].append(ev)
			elif kind == "hit":
				ba["crit_hit" if crit else "hit"].append(ev)
			continue
		if kind == "other":
			continue
		for k in ["Q", "W", "E", "R"]:
			if _fam_matches(fam, bases[k]):
				if out[k].has(kind):
					out[k][kind].append(ev)
				break
	_spell_events[alias] = out
	_ba_events[alias] = ba


static func _fam_matches(fam: String, bases: Array) -> bool:
	for b in bases:
		if fam.begins_with(b) or (b.begins_with(fam) and fam.length() > 4):
			return true
	return false


func _is_champ(u) -> bool:
	return u != null and is_instance_valid(u) and u.kind == G.Kind.CHAMPION


func _vol(u) -> float:
	# the player's own sounds a touch louder
	return 0.0 if u == G.player else -3.0


func _choice(list: Array):
	return list[G.rng.randi() % list.size()]


## Attack wind-up (swing / cast) sound.
func attack_start(u, crit: bool) -> void:
	if _is_champ(u):
		var ba: Dictionary = _ba_events.get(u.alias, {})
		var list: Array = ba.get("crit_cast", []) if crit else []
		if list.is_empty():
			list = ba.get("cast", [])
		if not list.is_empty():
			play(_choice(list), u.global_position, _vol(u) - 4.0)
		var a: String = u.alias
		if G.rng.randf() < 0.12:
			_vo_line(u, ["%sBasicAttack_cast3D" % a, "%sBasicAttack2_cast3D" % a, "%sCritAttack_cast3D" % a if crit else "%sBasicAttack3_cast3D" % a], -4.0, 2500)
	elif u.kind == G.Kind.MINION:
		play(_minion_ev(u, "OnCast"), u.global_position, -20.0)
	elif u.kind == G.Kind.TURRET:
		_turret_shot(u)


## Basic attack impact sound (on the target).
func attack_hit(u, t, crit: bool) -> void:
	if t == null or not is_instance_valid(t):
		return
	if _is_champ(u):
		var ba: Dictionary = _ba_events.get(u.alias, {})
		var list: Array = ba.get("crit_hit", []) if crit else []
		if list.is_empty():
			list = ba.get("hit", [])
		if not list.is_empty():
			play(_choice(list), t.global_position, _vol(u) - 5.0)
	elif u.kind == G.Kind.MINION:
		play(_minion_ev(u, "OnHit"), t.global_position, -22.0)
	elif u.kind == G.Kind.TURRET:
		var tn := "Order" if u.team == G.Team.ORDER else "Chaos"
		var champ: bool = t.kind == G.Kind.CHAMPION
		var ev := "Play_sfx_Env_map11_%sTurret%sBasicAttack_hit" % [tn, "Champion" if champ else "Minion"]
		if not events.has(ev):
			ev = "Play_sfx_Env_TurretChampionBasicAttack_hit" if champ else "Play_sfx_Env_TurretBasicAttack_hit"
		play(ev, t.global_position, -4.0 + (1.5 * clampi(int(u.get("ramp")), 0, 3) if champ else 0.0))


## Turret shot: wind-up + missile launch, escalating with consecutive shots on champions (League's ramp 1..4 uses the
## lvl1 / lvl3 / lvl4 launch layers and gets louder and a little higher with each shot).
const TURRET_LVL := [1, 1, 3, 4]


func _turret_shot(u) -> void:
	var t = u.get("attack_target")
	var champ: bool = t != null and is_instance_valid(t) and t.kind == G.Kind.CHAMPION
	var tn := "Order" if u.team == G.Team.ORDER else "Chaos"
	var pos: Vector3 = u.global_position
	var ramp := clampi(int(u.get("ramp")), 0, 3)
	var cast := "Play_sfx_Env_map11_%sTurret%sBasicAttack_cast" % [tn, "Champion" if champ else "Minion"]
	if not events.has(cast):
		cast = "Play_sfx_Env_TurretChampionBasicAttack_cast" if champ else "Play_sfx_Env_TurretBasicAttack_missilelaunch"
	_play(cast, pos, -6.0 + 1.2 * ramp, 0.02, 1.0 + 0.025 * ramp)
	if champ:
		var beam := "Play_sfx_Env_map11_%sTurretBeam_missilelaunch_lvl%d" % [tn, TURRET_LVL[ramp]]
		_play(beam, pos, -9.0 + 1.5 * ramp, 0.0, 1.0 + 0.02 * ramp)


func _minion_ev(u, phase: String) -> String:
	var team := "Order" if u.team == G.Team.ORDER else "Chaos"
	var typ := "Melee"
	match int(u.minion_type):
		Minion.Type.CASTER: typ = "Ranged"
		Minion.Type.SIEGE: typ = "Siege"
		Minion.Type.SUPER: typ = "Super"
	var n: String = ["", "2", "3"][G.rng.randi() % 3]
	if typ == "Siege" and phase == "OnCast":
		# cannon minions: League names the shot "OnMissileCast" (Order has a plain OnCast too)
		var sev := "Play_sfx_HA_%sMinionSiegeBasicAttack_OnCast" % team
		if events.has(sev):
			return sev
		return "Play_sfx_HA_%sMinionSiegeBasicAttack_OnMissileCast" % team
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
			"Ignite": "", "Clarity": "Play_sfx_SummonerMana_OnCast"}.get(ab.id, "")
		if ab.id == "Mark" and ab.recast_window > 0.0:
			sev = "Play_sfx_SnowballFollowupCast_OnCast"
		if ab.id == "Ignite":
			# Ignite's cast is the debuff landing: League plays its OnBuffActivate (with the tick-hit loop afterwards)
			sev = "Play_sfx_SummonerDot_OnBuffActivate"
		play(sev, u.global_position, _vol(u))
		return
	var slot: int = ab.slot
	if slot < 0 or slot > 3:
		return
	var info: Dictionary = _spell_events.get(u.alias, {}).get("QWER"[slot], {})
	if _rate_ok("cast%d_%d" % [u.get_instance_id(), slot], 60):
		var casts: Array = info.get("cast", [])
		var launches: Array = info.get("launch", [])
		var acts: Array = info.get("act", [])
		var v := _vol(u)
		if not casts.is_empty():
			play(_choice(casts), u.global_position, v)
		if not launches.is_empty():
			play(_choice(launches), u.global_position, v - (3.0 if not casts.is_empty() else 0.0))
		if not acts.is_empty() and (casts.is_empty() or slot != 0):
			play(_choice(acts), u.global_position, v - (3.0 if not casts.is_empty() else 0.0))
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
	var sev := "Play_sfx_%s_%s_buffactivate" % [u.alias, k]
	if not u.anim_sound_bound(sev):   # [anim-events] else the emote clip's sound event plays it
		play(sev, u.global_position, _vol(u) - 2.0)
	_vo_line(u, ["%sGeneral" % k], 0.0, 800)


# ===================================================================== global events
func _on_level_up(c, _lvl) -> void:
	if c == G.player:
		play("Play_sfx_levelup_levelup", null, -4.0, 0.0)


func _on_gold(c, amount, src) -> void:
	# League's coin pickup chime for gold the player earns from kills (minion last hits, champion takedowns)
	if c == G.player and src != null and is_instance_valid(src) and amount > 0 \
			and (src.kind == G.Kind.MINION or src.kind == G.Kind.CHAMPION):
		play("Play_sfx_GoldAquisition_P_cast", null, -8.0 if src.kind == G.Kind.MINION else -4.0, 0.02)


func _on_champion_killed(victim, killer, _assisters) -> void:
	var pa := Prof.t0()
	_on_champion_killed_impl(victim, killer)
	Prof.slow("death.audio", pa, "")


func _on_champion_killed_impl(victim, killer) -> void:
	if _is_champ(victim):
		# the death cry always; the body-fall sfx exists for most champions; your own death adds League's low "Death_Self" hit
		var dev := "Play_sfx_%s_Death3D_cast" % victim.alias
		if events.has(dev) and not victim.anim_sound_bound(dev):   # [anim-events] else the death clip's event plays it      # Annie / Malphite / Miss Fortune / Sona / Veigar only have the voice line
			play(dev, victim.global_position, -2.0, 0.0)
		_vo_line(victim, ["Death3D"], 0.0, 0)
		if victim == G.player:
			play("Play_sfx_Death_Self", null, -4.0, 0.0)
	if _is_champ(killer) and _is_champ(victim):
		var specific := "Kill3D%s" % victim.alias
		_vo_line(killer, [specific, "Kill3DGeneral"], -1.0, 3000)


func on_respawn(c) -> void:
	if c == G.player:
		play("Play_sfx_Respawn_respawn", null, -4.0, 0.0)
	elif c != null and is_instance_valid(c):
		play("Play_sfx_Spawn_Base_buffactivate", c.global_position, -8.0, 0.02)
	_vo_line(c, ["Respawn2DGeneral"], -2.0, 0)
	if moments != null:
		moments.on_respawn(c)


func _on_structure_destroyed(s, _killer) -> void:
	var side := "Order" if s.team == G.Team.ORDER else "Chaos"
	match s.kind:
		G.Kind.TURRET:
			_turrets_down += 1
			var pos: Vector3 = s.global_position
			play("Play_sfx_Env_Turret_map12_%sTurret_break0%d" % [side, G.rng.randi_range(1, 3)], pos, 2.0, 0.0)
			# the Howling Abyss turret shatters into falling slabs a beat later
			if m != null:
				m.after(0.35, func(): play("Play_sfx_Env_Map12_Turret_Shatter_buffactivate", pos, -2.0, 0.0))
		G.Kind.INHIBITOR:
			play("Play_sfx_Env_map12_%s_inhibitor_death_cast" % side.to_lower(), s.global_position, 2.0, 0.0)
		G.Kind.NEXUS:
			var ev := "Play_sfx_Env_Global_EoG_ChaosNexus_death_cast" if s.team == G.Team.CHAOS else "Play_sfx_Env_Global_EoG_OrderNexus_death_oc"
			play(ev, null, 0.0, 0.0)


func _on_match_over(_winner: int) -> void:
	# the world goes quiet around the final explosion: stop loops, drop the ambience bed
	for l in _loops:
		l.player.stop()
		l.eid = -1
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_ambience, "volume_db", -40.0, 2.5)


# ===================================================================== announcer
const ANN := "Play_vo_Announcer_Female1_"

## key -> [priority, seconds a queued line stays worth saying]
const ANN_PRIO := {
	"victory": [100, 20.0], "defeat": [100, 20.0],
	"penta_kill": [90, 8.0], "quadra_kill": [85, 8.0], "ace": [80, 8.0], "triple_kill": [75, 7.0],
	"first_blood": [70, 7.0], "double_kill": [65, 6.0], "shutdown": [60, 6.0],
	"legendary": [58, 6.0], "godlike": [56, 6.0], "dominating": [54, 6.0], "unstoppable": [52, 6.0],
	"rampage": [51, 6.0], "killing_spree": [50, 6.0],
	"nexus_attack": [47, 5.0], "inhib_destroyed": [45, 9.0], "inhib_lost": [45, 9.0],
	"inhib_attack": [44, 5.0], "inhib_respawn_soon": [42, 8.0], "inhib_respawn": [42, 8.0],
	"turret_destroyed": [40, 8.0], "turret_lost": [40, 8.0],
	"you_slain": [32, 3.0], "you_killed": [31, 3.0], "enemy_slain": [30, 2.5], "ally_slain": [30, 2.5],
	"minions_spawned": [14, 14.0], "minions_30": [14, 14.0], "welcome": [14, 14.0],
}
const MULTI_KEYS := ["double_kill", "triple_kill", "quadra_kill", "penta_kill"]
const SLAIN_KEYS := ["you_slain", "you_killed", "enemy_slain", "ally_slain"]


func _kill_flavour() -> String:
	## "Hero" / "Turret" / "Minion": who landed the last kill (the Match appends its entry before emitting)
	if m == null or m.events.is_empty():
		return "Hero"
	var k = m.events.back().killer
	if k == null or not is_instance_valid(k):
		return "Hero"
	if k.kind == G.Kind.TURRET:
		return "Turret"
	if k.kind == G.Kind.MINION or k.kind == G.Kind.SUMMON:
		return "Minion"
	return "Hero"


func _on_announcer(key: String, ally_side: bool) -> void:
	var mine := "YourTeam" if ally_side else "EnemyTeam"
	var ev := ""
	match key:
		"welcome": ev = ANN + "StartGameMessage2Map12"
		"minions_30": ev = ANN + "StartGameMessage1Map11"
		"minions_spawned": ev = ANN + "MinionSpawn"
		"ace": ev = ANN + "Ace" + mine
		"turret_destroyed":
			ev = ANN + ("TurretLostFirstBloodEnemyTeam" if _turrets_down <= 1 else "TurretLostEnemyTeam")
			if not events.has(ev):
				ev = ANN + "TurretLostEnemyTeam"
		"turret_lost":
			ev = ANN + ("TurretLostFirstBloodYourTeam" if _turrets_down <= 1 else "TurretLostYourTeam")
			if not events.has(ev):
				ev = ANN + "TurretLostYourTeam"
		"inhib_destroyed": ev = ANN + "InhibitorLostEnemyTeam"
		"inhib_lost": ev = ANN + "InhibitorLostYourTeam"
		"victory": ev = "Play_vo_Announcer_Global_Female1_OnVictory"
		"defeat": ev = "Play_vo_Announcer_Global_Female1_OnDefeat"
		"you_slain": ev = ANN + "KillChampion%sYouEnemyTeam" % _kill_flavour()
		"you_killed": ev = ANN + "KillChampionYouHeroYourTeam"
		"enemy_slain": ev = ANN + "KillChampion%sHeroYourTeam" % _kill_flavour()
		"ally_slain": ev = ANN + "KillChampion%sHeroEnemyTeam" % _kill_flavour()
		_:
			var names := {"first_blood": "FirstBlood", "double_kill": "DoubleKill", "triple_kill": "TripleKill",
				"quadra_kill": "QuadraKill", "penta_kill": "PentaKill", "shutdown": "Shutdown", "killing_spree": "KillingSpree",
				"rampage": "Rampage", "unstoppable": "Unstoppable", "dominating": "Dominating", "godlike": "Godlike",
				"legendary": "Legendary"}
			var base: String = names.get(key, "")
			if base == "":
				return
			var last = m.events.back() if not m.events.is_empty() else null
			var you_killed: bool = last != null and last.killer == G.player
			ev = ANN + base + ("YouYourTeam" if you_killed else "Hero" + mine)
	# e.g. a turret killing an ally has its own line; fall back to the champion-kill line if the variant is missing
	if not events.has(ev) and key in SLAIN_KEYS:
		ev = ev.replace("KillChampionTurret", "KillChampionHero").replace("KillChampionMinion", "KillChampionHero")
	if not events.has(ev):
		if not _warned.has(ev):
			_warned[ev] = true
			push_warning("GameAudio: announcer event %s missing (key %s)" % [ev, key])
		return
	_ann_push(key, ev)


func _ann_push(key: String, ev: String) -> void:
	if _ann_locked:
		return
	var pr: Array = ANN_PRIO.get(key, [20, 4.0])
	var a := Ann.new()
	a.ev = ev
	a.key = key
	a.prio = int(pr[0])
	a.ttl = float(pr[1])
	a.t = Time.get_ticks_msec() * 0.001
	if a.prio >= 100:
		# victory / defeat: nothing else matters any more
		_ann_queue.clear()
		_ann_player.stop()
		_ann_cur_prio = 0
		_ann_locked = true
	elif key in SLAIN_KEYS:
		# League does not pile up "an enemy has been slain": one generic kill line waiting at a time, and none at all
		# when a multikill / shutdown / ace line is already waiting
		for q in _ann_queue:
			if q.prio >= 40 or q.key in SLAIN_KEYS:
				return
	else:
		# a real announcement replaces the generic kill lines that were waiting behind it
		_ann_queue = _ann_queue.filter(func(q: Ann): return q.key not in SLAIN_KEYS or a.prio < 40)
		for q in _ann_queue:
			if q.ev == ev:
				return
	_ann_queue.append(a)
	if _ann_queue.size() > 5:
		_ann_queue.sort_custom(func(x: Ann, y: Ann): return x.prio > y.prio)
		_ann_queue.resize(5)


func _ann_tick(dt: float) -> void:
	if _ann_player.playing:
		return
	_ann_cur_prio = 0
	if _ann_gap > 0.0:
		_ann_gap -= dt
		return
	if _ann_queue.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	var best: Ann = null
	var keep: Array[Ann] = []
	for q in _ann_queue:
		if now - q.t > q.ttl:
			continue      # stale: League drops announcements that waited too long
		keep.append(q)
		if best == null or q.prio > best.prio or (q.prio == best.prio and q.t < best.t):
			best = q
	_ann_queue = keep
	if best == null:
		return
	_ann_queue.erase(best)
	var s := _pick(best.ev)
	if s == null:
		return
	_ann_player.stream = s
	_ann_player.play()
	_ann_cur_prio = best.prio
	_ann_gap = 0.25
	_note(best.ev, "announcer p%d" % best.prio)


# ===================================================================== world polling (structure state, relics, waves)
func _poll_world() -> void:
	if m == null or G.player == null:
		return
	var pt: int = G.player.team
	var now: float = m.time
	# --- inhibitors: respawn warnings, "under attack"
	for i in 2:
		var ih = m.inhibitor_units[i]
		if ih == null or not is_instance_valid(ih):
			continue
		var ours: bool = ih.team == pt
		var k_dead := "ih_dead%d" % i
		var k_soon := "ih_soon%d" % i
		var k_hp := "ih_hp%d" % i
		var k_atk := "ih_atk%d" % i
		if ih.dead:
			_poll[k_dead] = true
			var left: float = float(ih.respawn_at) - now
			if left > 0.0 and left <= 15.0 and not _poll.get(k_soon, false):
				_poll[k_soon] = true
				_ann_named("inhib_respawn_soon", ANN + "InhibitorRespawnSoon" + ("YourTeam" if ours else "EnemyTeam"))
		else:
			if _poll.get(k_dead, false):
				_poll[k_dead] = false
				_poll[k_soon] = false
				_ann_named("inhib_respawn", ANN + "InhibitorRespawn" + ("YourTeam" if ours else "EnemyTeam"))
			var hp: float = ih.hp
			if ours and hp < float(_poll.get(k_hp, hp)) - ih.stats.max_hp * 0.004 and now - float(_poll.get(k_atk, -100.0)) > 40.0:
				_poll[k_atk] = now
				_ann_named("inhib_attack", ANN + "DampenerUnderAttack" + ("Blue" if ih.team == G.Team.ORDER else "Red"))
			_poll[k_hp] = hp
	# --- nexus under attack (once every 45 s)
	var nx = m.nexus_units[pt] if pt < 2 else null
	if nx != null and is_instance_valid(nx) and not nx.dead:
		var hp2: float = nx.hp
		if hp2 < float(_poll.get("nx_hp", hp2)) - nx.stats.max_hp * 0.003 and now - float(_poll.get("nx_atk", -100.0)) > 45.0:
			_poll["nx_atk"] = now
			_ann_named("nexus_attack", ANN + "NexusUnderAttack" + ("Blue" if pt == G.Team.ORDER else "Red"))
		_poll["nx_hp"] = hp2
	# --- relic pickups
	var ri := 0
	for r in m.relics:
		var key := "relic%d" % ri
		ri += 1
		var act: bool = r.active
		if _poll.get(key, false) and not act:
			var rp: Vector3 = r.global_position
			play("Play_sfx_Env_Map12_Crepe_healthpickup_cast", rp, 0.0, 0.0)
			# the area heal beam lands Rules.RELIC_BEAM_DELAY later
			m.after(Rules.RELIC_BEAM_DELAY, func(): play("Play_sfx_Env_Map12_Crepe_healthpickup_cast", rp, -3.0, 0.0))
		_poll[key] = act
	# --- poros hopping around the bridge (MapAmbient owns their state machine)
	var amb = m.get_node_or_null("MapAmbient")
	if amb != null:
		var pi := 0
		for po in amb._poros:
			var st: String = po.state
			if st == "hop" and _poll.get("poro%d" % pi, "") != "hop" and po.node != null and is_instance_valid(po.node) and _rate_ok("poro%d" % pi, 4000):
				play("Play_sfx_env_map12_ha_ap_poro_base_jump", po.node.global_position, -5.0, 0.04)
			_poll["poro%d" % pi] = st
			pi += 1
	# --- minion waves leaving the barracks
	if m.spawner != null and m.spawner.wave_index > _wave_seen:
		_wave_seen = m.spawner.wave_index
		for ih2 in m.inhibitor_units:
			if ih2 != null and is_instance_valid(ih2):
				play("Play_sfx_SRU_Spawn_MinionsSpawn_cast", ih2.global_position + Vector3(0, 0, 0), -10.0, 0.03)


func _ann_named(key: String, ev: String) -> void:
	if events.has(ev):
		_ann_push(key, ev)
	elif not _warned.has(ev):
		_warned[ev] = true
		push_warning("GameAudio: announcer event %s missing (key %s)" % [ev, key])


# ===================================================================== world loops (braziers, structures)
func _setup_emitters() -> void:
	var path := "res://data/map/map12_particles.json"
	if FileAccess.file_exists(path):
		var arr = JSON.parse_string(FileAccess.get_file_as_string(path))
		if arr is Array:
			var evs := {"HA_Audio_Emitter_FireBig": "Play_sfx_Env_map12_fire_big", "HA_Audio_Emitter_FireMed_Big": "Play_sfx_Env_map12_fire_med_big"}
			for r in arr:
				var ev: String = evs.get(String(r.system), "")
				if ev == "" or not events.has(ev):
					continue
				var x: Array = r.xform
				var pos := G.lol_pos(float(x[12]), float(x[13]), float(x[14]))
				if pos.y < -50.0:
					continue
				_emitters.append({"id": _emitters.size(), "ev": ev, "pos": pos, "owner": null, "vol": -4.0})
	# nexus / inhibitor hum (stops while the inhibitor is down)
	for i in 2:
		var side := "order" if i == G.Team.ORDER else "chaos"
		for pair in [[m.nexus_units[i], "Play_sfx_Env_map12_%s_nexus_alive_loop" % side], [m.inhibitor_units[i], "Play_sfx_Env_map12_%s_inhibitor_alive_loop" % side]]:
			var u = pair[0]
			if u != null and is_instance_valid(u) and events.has(pair[1]):
				_emitters.append({"id": _emitters.size(), "ev": pair[1], "pos": u.global_position, "owner": u, "vol": -2.0})


func _update_loops() -> void:
	if m == null or m.over or m.camera_rig == null:
		return
	var f: Vector3 = m.camera_rig.focus
	var cand: Array = []
	for e in _emitters:
		var o = e.owner
		if o != null and (not is_instance_valid(o) or o.dead):
			continue
		var d := G.flat_dist(f, e.pos)
		if d < 30.0:
			cand.append([d, e])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var n := mini(cand.size(), _loops.size())
	var wanted := {}
	for i in n:
		wanted[int(cand[i][1].id)] = true
	# free loops whose emitter is no longer wanted, then hand free loops to new emitters
	var busy := {}
	for l in _loops:
		if l.player.playing and l.eid >= 0 and not wanted.has(l.eid):
			l.player.stop()
			l.eid = -1
		if l.player.playing and l.eid >= 0:
			busy[l.eid] = true
	for i in n:
		var e: Dictionary = cand[i][1]
		if busy.has(int(e.id)):
			continue
		for l in _loops:
			if not l.player.playing:
				var s := _pick(e.ev)
				if s == null:
					break
				var s2: AudioStream = s.duplicate() if s is AudioStreamWAV else s
				_loopify(s2)
				l.eid = int(e.id)
				l.player.stream = s2
				l.player.global_position = e.pos + Vector3(0, 1.0, 0)
				l.player.volume_db = float(e.vol)
				l.player.pitch_scale = 1.0 + G.rng.randf_range(-0.04, 0.04)
				l.player.play(G.rng.randf() * 2.0)
				busy[int(e.id)] = true
				break
