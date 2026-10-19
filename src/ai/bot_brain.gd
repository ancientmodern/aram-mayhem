class_name BotBrain
extends RefCounted
## Champion AI: laning, teamfighting, kiting, retreating, sieging, dodging and ability usage.
## Team-level decisions (engage / hold / retreat, focus target) come from a shared TeamAI.
## Also serves as the `ctx` object passed to Ability.ai_consider() (see docs/KIT_GUIDE.md).

## [bot-diff] difficulty tiers (docs/BOT_DIFFICULTY.md). Every bot has its own level 0..3:
## 0 Intro, 1 Beginner, 2 Intermediate, 3 Hard. Resolved by level_for(): G.lineup entry > --botlevels=A,B > G.settings.difficulty.
const LEVEL_NAMES := ["Intro", "Beginner", "Intermediate", "Hard"]
## Parameter table: name -> value per level [Intro, Beginner, Intermediate, Hard].
const LV := {
	"reaction":      [0.55, 0.38, 0.26, 0.10],   ## decision interval (s)
	"aim_error":     [2.0, 1.3, 0.8, 0.04],     ## skillshot aim scatter (m)
	"lead":          [0.0, 0.5, 0.8, 1.0],       ## fraction of the target's movement the aim leads (3 = follows the move path)
	"dodge":         [0.0, 0.10, 0.3, 0.88],    ## chance to sidestep a skillshot that would hit
	"dodge_react":   [9.0, 0.45, 0.3, 0.09],    ## missile age (s) before the bot can react to it
	"retreat_hp":    [0.10, 0.20, 0.28, 0.32],   ## base retreat threshold (hp ratio)
	"ability_gap":   [1.2, 0.6, 0.3, 0.15],      ## pause after a cast (s)
	"ability_skip":  [0.45, 0.30, 0.15, 0.0],    ## chance to hesitate instead of casting a ready ability
	"hesitate":      [0.22, 0.12, 0.05, 0.0],     ## chance per decision to freeze for ~0.4-1.0 s
	"kite":          [0.0, 0.25, 0.5, 1.0],      ## fraction of attack cycles a ranged bot orb-walks
	"turret_aware":  [0.0, 0.5, 0.75, 1.0],       ## chance (per decision) to respect enemy turret range
	"relic_hp":      [0.0, 0.3, 0.5, 0.7],       ## health relic is used below this hp ratio
	"relic_range":   [0.0, 10.0, 16.0, 22.0],
	"lasthit":       [0.0, 0.4, 0.75, 1.0],       ## last-hit skill (else: nearest minion)
	"team_focus":    [0.0, 0.2, 0.5, 1.0],      ## chance per decision to adopt the team's focus target
	"back_scale":    [0.3, 0.65, 1.0, 1.1],      ## how far behind the wave front it stands
	"caution_scale": [0.2, 0.6, 1.0, 1.2],
	"wander_scale":  [1.6, 1.3, 1.0, 0.8],
	"push":          [0.0, 0.0, 0.0, 1.0],       ## 1 = sieges / pushes after winning a fight (numbers advantage)
	"judge_noise":   [0.55, 0.45, 0.3, 0.0],      ## misjudgement of fight strength (power ratio) in retreat / engage decisions
	"mana_floor":    [0.0, 0.0, 0.15, 0.3],      ## mana ratio kept in reserve in lane (no non-ult casts below it)
	"cc_hold":       [0.0, 0.0, 0.0, 1.0],       ## 1 = holds crowd control for engages and never stacks it
	"ult_wait":      [0.0, 0.0, 5.0, 8.0],       ## seconds an ultimate may wait for a worthwhile target (0 = casts whenever ready)
}

## Slot indices (0..3 = QWER) of each champion's crowd-control abilities (hard bots hold / chain them).
const CC_SLOTS := {"Ahri": [2], "Darius": [2], "Jinx": [2], "Leona": [0, 2, 3], "Lux": [0], "Malphite": [3], "Sona": [3], "Veigar": [2]}

static var _cli_levels = null    ## --botlevels=<order>,<chaos> (bench / tests), parsed once
static var _cli_lv = null        ## --botlv=<level>:<key>=<value>[,<level>:<key>=<value>] overrides LV entries (tuning / ablations)

var level := 1
var c: Champion
var m = null
var team_ai: TeamAI = null
var think_timer := 0.0
var mode := "lane"               ## "lane", "fight", "retreat" (read by kits)
var focus: Unit = null
var enemies: Array = []          ## visible enemy champions nearby
var allies: Array = []           ## allied champions nearby (not self)
var enemy_minions: Array = []
var ally_minions: Array = []
var enemy_turret: Unit = null    ## enemy turret whose range we are near
var is_ranged := true
var frontline := false           ## tanks / melee: lead the engage, stand in front
var aggression := 0.5
var reaction := 0.22
var aim_error := 0.35
var retreat_hp := 0.28
var dodge_chance := 0.3
var personal_offset := 0.0
var shop_timer := 0.0
var _move_goal := Vector3.INF
var _move_timer := 0.0
var _ability_timer := 0.0
var _dodge_until := -1.0
var _dodge_check := 0.0
var _dodged := {}                ## missile -> true (decided once per missile)
var _chase_since := -1.0
var _strafe_dir := 1.0
var _strafe_t := 0.0
var _kite_cycle := -1
# --- persona: every bot plays a little differently (human-like variety)
var forward_bias := 0.5          ## 0 = hangs back near own turret, 1 = walks up to the middle
var caution := 1.0               ## extra spacing (m) kept from enemy threat ranges
var wander := 1.4                ## radius (m) of idle "fidget" clicks around the spot it holds
var fidget_rate := 1.0           ## scales the time between fidget clicks
var emote_chance := 0.35         ## chance to emote after a kill (when safe)
var harass := 0.5                ## how eagerly a ranged bot steps in for a free auto during the face-off
var _fidget_at := 0.0
var _emote_until := -1.0
var _last_kills := 0
var _harass_until := -1.0
var _next_harass := 0.0
var _mode_since := 0.0
var _retreat_until := -1.0
var _kite_target: Unit = null
var _kite_goal := Vector3.INF
# --- [bot-diff] level-dependent state
var lead := 1.0
var dodge_react := 0.1
var ability_gap := 0.25
var ability_skip := 0.0
var hesitate := 0.0
var kite := 1.0
var turret_aware := 1.0
var relic_hp := 0.6
var relic_range := 22.0
var lasthit := 1.0
var team_focus := 1.0
var back_scale := 1.0
var _aware := true               ## respects enemy turret range this decision
var _stance := "hold"            ## the team stance as this bot perceives it
var _kiting := true              ## orb-walks the current attack cycle
var _build_perm: Array = []      ## level 1: a stable shuffled build order
var _incoming := 0.0             ## smoothed damage taken per second
var _dtt := 0.0
var _gather_t := 0.0
var _ult_hold_since := -1.0
var _next_shop := 0.0
# stats for tools/bot_bench.sh
var stat_casts := 0
var stat_threats := 0            ## enemy skillshots that were about to hit us
var stat_dodges := 0             ## ... of which we decided to sidestep
var stat_flash := 0
var stat_summ := 0


func setup(champ: Champion, p_match) -> void:
	c = champ
	m = p_match
	is_ranged = c.stats.attack_range > 300.0
	var roles := ChampionDB.roles(c.alias)
	frontline = not is_ranged or "tank" in roles
	aggression = clampf(0.45 + G.rng.randf_range(-0.15, 0.2) + (0.15 if frontline else 0.0), 0.2, 0.9)
	personal_offset = G.rng.randf_range(-2.5, 2.5)
	if c.kit != null and c.kit.has_method("ai_tuning"):
		var t: Dictionary = c.kit.ai_tuning()
		aggression = t.get("aggression", aggression)
	team_ai = p_match.team_ai(c.team)
	forward_bias = clampf(G.rng.randf_range(0.15, 0.95) * (0.6 + aggression * 0.8), 0.05, 1.0)
	caution = G.rng.randf_range(0.6, 2.4) * (1.4 - aggression)
	wander = G.rng.randf_range(0.8, 2.2)
	fidget_rate = G.rng.randf_range(0.6, 1.5)
	emote_chance = G.rng.randf_range(0.1, 0.6)
	harass = clampf(G.rng.randf_range(0.2, 1.0) * (0.5 + aggression), 0.0, 1.0)
	_next_harass = G.rng.randf_range(2.0, 6.0)
	_persona_forward = forward_bias
	_persona_caution = caution
	_persona_wander = wander
	set_level(level_for(c))


## [bot-diff] (Re)apply a difficulty level 0..3 to this bot (setup() calls it; tests / the bench may call it again).
func set_level(lv: int) -> void:
	level = clampi(lv, 0, 3)
	judge_noise = LV.judge_noise[level]
	push_on = LV.push[level] > 0.0
	mana_floor = LV.mana_floor[level]
	cc_hold = LV.cc_hold[level]
	ult_wait = LV.ult_wait[level]
	reaction = LV.reaction[level]
	aim_error = LV.aim_error[level]
	lead = LV.lead[level]
	dodge_chance = LV.dodge[level]
	dodge_react = LV.dodge_react[level]
	retreat_hp = LV.retreat_hp[level]
	ability_gap = LV.ability_gap[level]
	ability_skip = LV.ability_skip[level]
	hesitate = LV.hesitate[level]
	kite = LV.kite[level]
	turret_aware = LV.turret_aware[level]
	relic_hp = LV.relic_hp[level]
	relic_range = LV.relic_range[level]
	lasthit = LV.lasthit[level]
	team_focus = LV.team_focus[level]
	back_scale = LV.back_scale[level]
	if _cli_lv == null:
		_cli_lv = {}
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--botlv="):
				for part in a.substr(8).split(","):
					var kv := part.split("=")
					var lk := kv[0].split(":")
					if kv.size() == 2 and lk.size() == 2:
						_cli_lv[[int(lk[0]), lk[1]]] = float(kv[1])
	if not _cli_lv.is_empty():
		for k in LV.keys():
			if _cli_lv.has([level, k]):
				set(_param_var(k), _cli_lv[[level, k]])
	push_on = push_f > 0.0 if _cli_lv.has([level, "push"]) else push_on
	forward_bias = clampf(_persona_forward * [1.3, 1.1, 1.0, 0.95][level], 0.05, 1.0)
	caution = _persona_caution * LV.caution_scale[level]
	wander = _persona_wander * LV.wander_scale[level]
	_build_perm = []
	if team_ai != null:
		team_ai.set_bot_noise(get_instance_id(), judge_noise)


## LV key -> member variable (only used by the --botlv tuning override).
static func _param_var(k: String) -> String:
	match k:
		"reaction", "aim_error", "lead", "dodge_react", "retreat_hp", "ability_gap", "ability_skip", "hesitate", "kite", 		"turret_aware", "relic_hp", "relic_range", "lasthit", "team_focus", "back_scale", "mana_floor", "cc_hold", "ult_wait", "judge_noise":
			return k
		"push":
			return "push_f"
		"dodge":
			return "dodge_chance"
	return "_unused"


var judge_noise := 0.0
var push_on := false
var push_f := 0.0
var _judge := 0.0
var mana_floor := 0.0
var cc_hold := 0.0
var ult_wait := 0.0
var _unused := 0.0
var _persona_forward := 0.5
var _persona_caution := 1.0
var _persona_wander := 1.4


## Difficulty of a bot: G.lineup entry {team, champion, difficulty} > --botlevels=<order>,<chaos> > G.settings.difficulty.
static func level_for(champ) -> int:
	var d := lineup_difficulty(champ.team, champ.alias)
	if d >= 0:
		return clampi(d, 0, 3)
	if _cli_levels == null:
		_cli_levels = []
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--botlevels="):
				for part in a.substr(12).split(","):
					_cli_levels.append(clampi(int(part), 0, 3))
	if _cli_levels.size() >= 2 and champ.team < 2:
		return _cli_levels[champ.team]
	return clampi(int(G.settings.get("difficulty", 1)), 0, 3)


## Difficulty stored in G.lineup for (team, champion alias): 0..3, -1 for the human, -2 when there is no entry.
static func lineup_difficulty(team: int, alias: String) -> int:
	for e in G.lineup:
		if e is Dictionary and int(e.get("team", -1)) == team and str(e.get("champion", "")) == alias:
			return int(e.get("difficulty", -2))
	return -2


# ===================================================================== main loop
func think(dt: float) -> void:
	think_timer -= dt
	_move_timer -= dt
	_ability_timer -= dt
	_dodge_check -= dt
	if _dodge_check <= 0.0:
		_dodge_check = 0.05
		if _try_dodge():
			return
	if m.time < _dodge_until:
		return
	if c.has_meta("hexgate_busy"):   # [env3] walking to / using a hexgate: HexgateNet drives this bot
		return
	if m.time < _emote_until:
		if enemies.is_empty() or _nearest_enemy_dist() > 9.0:
			return
		_emote_until = -1.0
	if c.kills > _last_kills:
		_last_kills = c.kills
		_maybe_emote(0.6)
	if think_timer > 0.0:
		return
	think_timer = reaction * G.rng.randf_range(0.8, 1.2)
	# [bot-diff] low levels freeze for a moment now and then (not while in real trouble)
	if hesitate > 0.0 and c.hp_ratio() > 0.2 and G.rng.randf() < hesitate:
		think_timer += G.rng.randf_range(0.4, 1.0)
		return
	team_ai.refresh()
	_gather()
	_perceive()
	if c.in_fountain:
		_shop_and_augments()
	if c.is_busy() and not c.casting.is_empty():
		return
	if not c.channel.is_empty() and not c.channel.ability.can_move_while_channeling:
		return
	# focus fire: adopt the team's target when it's within reach
	var tf := team_ai.focus
	if tf != null and is_instance_valid(tf) and not tf.dead and G.flat_dist(tf.global_position, c.global_position) < c.attack_range_m() + 6.0 			and (team_focus >= 1.0 or G.rng.randf() < team_focus):
		focus = tf
	elif focus != null and (not is_instance_valid(focus) or focus.dead):
		focus = null
	if _ability_timer <= 0.0:
		if _try_abilities():
			_ability_timer = ability_gap
			stat_casts += 1
	_try_summoners()
	for it in c.items:
		if it.has_active() and it.active_left <= 0.0 and it.ai_should_activate(self):
			var tp: Vector3 = focus.global_position if focus != null and is_instance_valid(focus) else c.global_position + c.facing * 3.0
			it.activate(tp, focus)
	# decisions commit for a moment (players don't flip between advancing and backing off every few
	# hundred ms): a retreat lasts a while once started, a fresh engage isn't dropped on a whim
	var want_retreat := _should_retreat()
	if mode == "retreat" and not want_retreat and m.time < _retreat_until:
		want_retreat = true
	elif mode == "fight" and want_retreat and m.time - _mode_since < 0.9 and not _must_retreat():
		want_retreat = false
	if want_retreat:
		if mode != "retreat":
			_set_mode("retreat")
			_retreat_until = m.time + G.rng.randf_range(1.4, 2.2) * (0.45 if level == 0 else 1.0)
		_retreat()
		return
	var t := _pick_fight_target()
	# just stopped retreating: don't turn straight back into a fight unless it comes to us
	if t != null and mode == "retreat" and G.flat_dist(t.global_position, c.global_position) > c.attack_range_m() + c.radius + 0.5 			and m.time < _retreat_until + 0.8:
		t = null
	if t != null:
		if mode != "fight" or t != focus:
			_chase_since = m.time
		_set_mode("fight")
		focus = t
		_fight(t)
		return
	_set_mode("lane")
	_lane()


func _set_mode(md: String) -> void:
	if md != mode:
		mode = md
		_mode_since = m.time


## Retreat reasons that override any commitment.
func _must_retreat() -> bool:
	if level == 0:
		return c.hp_ratio() < 0.08
	return c.hp_ratio() < 0.15 or (_turret_targeting_me() and not _minions_tanking(enemy_turret) and not _push_ok())


## [bot-diff] Hard bots close out a won fight: with at least 2 more champions alive than the enemy they take the turret
## down without waiting for minions to tank it (and keep going while the turret shoots them, as long as they stay healthy).
func _push_ok() -> bool:
	return push_on and team_ai.alive >= 3 and team_ai.alive - team_ai.enemy_alive >= 2 and c.hp_ratio() > 0.55


func _enemy_front_turret() -> Unit:
	var best: Unit = null
	var bd := INF
	for s in m.structures:
		if s.team != c.team and s.kind == G.Kind.TURRET and not s.dead and not s.is_invulnerable():
			var d := G.flat_dist(c.global_position, s.global_position)
			if d < bd:
				bd = d
				best = s
	return best


func think_dead(_dt: float) -> void:
	shop_timer -= _dt
	if shop_timer <= 0.0:
		shop_timer = 1.0
		_shop_and_augments()


func _gather() -> void:
	var p := c.global_position
	enemies.clear()
	allies.clear()
	enemy_minions.clear()
	ally_minions.clear()
	enemy_turret = null
	for u in m.units_in_radius(p, 17.0, -1):
		if u == c or u.dead:
			continue
		if u.team == c.team:
			if u.kind == G.Kind.CHAMPION:
				allies.append(u)
			elif u.kind == G.Kind.MINION:
				ally_minions.append(u)
		else:
			if not u.is_targetable_by(c.team) and u.kind != G.Kind.TURRET:
				continue
			match u.kind:
				G.Kind.CHAMPION:
					enemies.append(u)
				G.Kind.MINION, G.Kind.SUMMON:
					enemy_minions.append(u)
				G.Kind.TURRET:
					if not u.dead and G.flat_dist(p, u.global_position) < u.attack_range_m() + 4.0:
						enemy_turret = u


## [bot-diff] Item build this bot follows (ItemDB.bot_next_purchase asks): Hard / Intermediate = the curated build,
## Beginner = the same items in a scrambled order, Intro = the generic bruiser build whatever the champion.
func shape_build(build: Array) -> Array:
	match level:
		0:
			return ItemDB.DEFAULT_BUILD
		1:
			if _build_perm.is_empty():
				var rest := build.slice(1)
				rest.shuffle()   # (Array.shuffle uses the global RNG, which --seed fixes)
				_build_perm = [build[0]] + rest
			return _build_perm
	return build


## [bot-diff] Per-decision perception: turret awareness roll, the team stance as this level reads it, incoming damage.
func _perceive() -> void:
	_aware = turret_aware >= 1.0 or G.rng.randf() < turret_aware
	_judge = lerpf(_judge, G.rng.randf_range(-1.0, 1.0), 0.35)
	var st := team_ai.stance
	if st == "engage" and level <= 1:
		st = "hold" if level == 0 or G.rng.randf() < 0.6 else "engage"
	_stance = st
	var now: float = m.time
	var dt := maxf(now - _gather_t, 0.05)
	if _gather_t > 0.0:
		_incoming = lerpf(_incoming, maxf(c.damage_taken_total - _dtt, 0.0) / dt, clampf(dt / 1.2, 0.2, 1.0))
	_dtt = c.damage_taken_total
	_gather_t = now


## Expected damage taken over the next second (smoothed), in hp.
func incoming_dps() -> float:
	return _incoming


# ===================================================================== evaluation
static func power_of(u) -> float:
	var dps: float = u.stats.ad * u.stats.attack_speed * (1.0 + u.stats.crit_chance) + u.stats.ap * 0.8 + u.level * 25.0
	var ehp: float = u.hp * (1.0 + (u.stats.armor + u.stats.mr) * 0.005) + u.total_shield()
	return sqrt(maxf(dps, 1.0) * maxf(ehp, 1.0))


func team_power(list: Array, include_self: bool) -> float:
	var s := power_of(c) if include_self else 0.0
	for u in list:
		s += power_of(u)
	return s


func in_danger() -> bool:
	return not enemies.is_empty() and c.hp_ratio() < 0.5


func wants_speed() -> bool:
	return mode == "retreat" and in_danger() or (mode == "fight" and focus != null and focus.hp_ratio() < 0.3 and G.flat_dist(c.global_position, focus.global_position) > c.attack_range_m() + 2.0)


func _turret_targeting_me() -> bool:
	return enemy_turret != null and enemy_turret.attack_target == c


func _minions_tanking(tu: Unit) -> bool:
	for mn in ally_minions:
		if G.flat_dist(mn.global_position, tu.global_position) < tu.attack_range_m() + 0.5:
			return true
	return false


## Rough damage we can deal in a short trade (for kill decisions).
func _burst() -> float:
	var d: float = c.stats.ad * 2.5 + c.stats.ap * 1.2 + c.level * 40.0
	for ab in c.abilities:
		if ab != null and ab.level > 0 and ab.is_ready():
			d += 60.0 + 30.0 * ab.level + c.stats.ap * 0.4
	return d


func _should_retreat() -> bool:
	var hp := c.hp_ratio()
	if level >= 1 and _turret_targeting_me() and (not _minions_tanking(enemy_turret) or hp < 0.6) and not (_push_ok() and hp > 0.6):
		return true
	if enemies.is_empty():
		return hp < (0.1 if level == 0 else 0.15) and _nearest_relic() == null
	var p := c.global_position
	var near_allies := allies.filter(func(a): return G.flat_dist(a.global_position, p) < 11.0)
	var near_enemies := enemies.filter(func(e): return G.flat_dist(e.global_position, p) < 12.0)
	var ally_p := team_power(near_allies, true)
	var enemy_p := team_power(near_enemies, false) * (1.0 - judge_noise * _judge)   # [bot-diff] low levels misjudge the fight
	# finishing a kill is worth staying for
	if focus != null and is_instance_valid(focus) and not focus.dead and focus.hp < _burst() * 0.8 and hp > 0.12 \
			and c.in_attack_range(focus, 1.5):
		return false
	var threshold := retreat_hp * (0.75 if frontline else 1.1) * (1.2 - aggression * 0.4)
	if hp < threshold and (enemy_p > ally_p * 0.55 or hp < 0.1):
		return true
	# outnumbered and alone
	if level >= 1 and near_allies.is_empty() and near_enemies.size() >= 2 and enemy_p > ally_p * 1.3:
		return true
	# the team is falling back and the fight here is not winnable
	if level >= 2 and team_ai.stance == "retreat" and not near_enemies.is_empty() and enemy_p > ally_p * 0.9:
		return true
	if level >= 3:
		# numbers disadvantage in the fight (not just a power ratio)
		if near_enemies.size() >= 2 and near_allies.size() + 1 < near_enemies.size() and enemy_p > ally_p * 1.1:
			return true
		# a ranged caster with no mana left is dead weight in a fight
		if c.stats.uses_mana and is_ranged and c.mana < c.stats.max_mana * 0.06 and hp < 0.75 and not near_enemies.is_empty():
			return true
	return false


func _pick_fight_target() -> Unit:
	if enemies.is_empty():
		return null
	var p := c.global_position
	var st := _stance
	var reach := c.attack_range_m() + c.radius
	var engage := reach + 1.0
	match st:
		"engage":
			engage = reach + (6.5 if frontline else 3.5) + aggression * 3.0
		"hold":
			engage = reach + (3.0 if frontline else 1.5) + aggression * 1.5
		"retreat":
			engage = reach + 0.5
	var burst := _burst()
	var best: Unit = null
	var best_s := -INF
	var w_hp: float = [0.0, 1.0, 3.0, 3.0][level]
	var w_kill: float = [0.0, 2.0, 4.0, 5.0][level]
	var w_focus: float = [0.0, 0.0, 2.0, 3.0][level]
	var w_ranged: float = [0.0, 0.0, 0.6, 1.5][level]
	for e in enemies:
		var d := G.flat_dist(p, e.global_position)
		var killable: bool = e.hp < burst and d < reach + 4.0
		var attacking_me: bool = c.damage_log.has(e) and m.time - float(c.damage_log[e]) < 2.0
		if d > engage and not killable and not (attacking_me and d < reach + 2.0):
			continue
		# do not dive under their turret unless it is a sure thing (only hard bots take real dives)
		if _under_enemy_turret(e.global_position):
			var dive_ok := false
			if level >= 3:
				dive_ok = (killable and c.hp_ratio() > 0.5 and (_minions_tanking(enemy_turret) if enemy_turret != null else true)) \
						or (st == "engage" and e.hp_ratio() < 0.3 and enemy_turret != null and _minions_tanking(enemy_turret))
			elif level == 2:
				dive_ok = killable and c.hp_ratio() > 0.6 and enemy_turret != null and _minions_tanking(enemy_turret)
			if not dive_ok:
				continue
		var s := -d * (0.5 if level == 0 else 0.15)
		s += (1.0 - e.hp_ratio()) * w_hp
		s += w_kill if killable else 0.0
		s += 1.5 if (e.cc & Buff.IMMOBILIZE) != 0 and level >= 2 else 0.0
		s += w_focus if e == team_ai.focus else 0.0
		s += 1.0 if e == focus and level >= 1 else 0.0
		s += w_ranged if e.stats.attack_range > 300.0 else 0.0
		s += 1.0 if attacking_me else 0.0
		if level >= 3:
			# squishy / low effective-hp targets first, isolated ones are safer to commit to
			s -= (e.hp * (1.0 + (e.stats.armor + e.stats.mr) * 0.004) + e.total_shield()) / 700.0
			var isolated := true
			for e2 in enemies:
				if e2 != e and G.flat_dist(e2.global_position, e.global_position) < 6.0:
					isolated = false
					break
			s += 1.0 if isolated else 0.0
		if s > best_s:
			best_s = s
			best = e
	# melee: give up long chases of something we can't catch
	if best != null and best == focus and not is_ranged and _chase_since > 0.0 and m.time - _chase_since > [1.5, 2.0, 3.0, 4.0][level] \
			and G.flat_dist(p, best.global_position) > reach + 2.5 and best.stats.move_speed >= c.stats.move_speed and best.hp_ratio() > 0.25:
		_chase_since = m.time + 2.0   # cool off
		return null
	return best


func _under_enemy_turret(pos: Vector3) -> bool:
	if not _aware:   # [bot-diff] low levels do not keep track of turret range
		return false
	for s in m.structures:
		if s.team != c.team and s.kind == G.Kind.TURRET and not s.dead:
			if G.flat_dist(pos, s.global_position) < s.attack_range_m() + s.radius:
				return true
	return false


# ===================================================================== actions
func _move(goal: Vector3, force: bool = false) -> void:
	if not force and _move_timer > 0.0 and _move_goal != Vector3.INF and G.flat_dist(goal, _move_goal) < 1.0:
		return
	if not m.nav.is_walkable(goal):
		goal = m.nav.nearest_walkable(goal)
	_move_goal = goal
	_move_timer = 0.3
	c.issue_move(goal)


func _attack(u: Unit) -> void:
	if c.attack_target != u or c.cmd != Unit.Cmd.ATTACK:
		c.issue_attack(u)


func _retreat() -> void:
	var goal := team_ai.safe_point
	var relic = _nearest_relic()
	if relic != null and G.flat_dist(relic.global_position, c.global_position) < G.flat_dist(goal, c.global_position) * 0.7:
		goal = relic.global_position
	# never retreat past our own fountain line
	if G.flat_dist(c.global_position, c.spawn_point) < G.flat_dist(goal, c.spawn_point):
		goal = c.spawn_point
	_move(goal)


func _nearest_relic():
	if relic_range <= 0.0:   # [bot-diff] Intro bots never use health relics
		return null
	var best = null
	var bd := relic_range
	for r in m.relics:
		if r.active:
			var d := G.flat_dist(r.global_position, c.global_position)
			if d < bd and not _under_enemy_turret(r.global_position):
				bd = d
				best = r
	return best


func _fight(t: Unit) -> void:
	var p := c.global_position
	if not is_ranged:
		_attack(t)
		return
	# ranged: orb-walk like a player. Attack when ready; between attacks take ONE deliberate step
	# (kite back from threats, close distance, or a short reposition) and then wait for the next attack.
	if c.windup_timer >= 0.0:
		return
	if not c.in_attack_range(t) or c.attack_timer <= 0.05:
		_attack(t)
		return
	if kite <= 0.0:
		return   # [bot-diff] Intro bots stand still and trade
	if _kite_cycle != c.attack_count or _kite_target != t:
		_kite_cycle = c.attack_count
		_kite_target = t
		_kiting = kite >= 1.0 or G.rng.randf() < kite
		_kite_goal = _pick_kite_goal(t) if _kiting else Vector3.INF
	if _kite_goal == Vector3.INF:
		# holding position: cancel the attack order so we don't walk in, but stay put
		if c.moving:
			c.issue_stop()
		return
	if G.flat_dist(p, _kite_goal) > 0.25:
		_move(_kite_goal)


## One kiting step for the time until the next attack is ready (INF = hold still).
func _pick_kite_goal(t: Unit) -> Vector3:
	var p := c.global_position
	var spd: float = c.stats.move_speed * G.U
	# how far we can walk and still turn back to attack on time
	var budget := clampf(spd * c.attack_timer * (0.88 if level >= 3 else 0.75), 0.0, 3.0)
	if budget < 0.35:
		return Vector3.INF
	var threat: Unit = null
	var td := INF
	for e in enemies:
		var d := G.flat_dist(e.global_position, p)
		var their_reach: float = e.attack_range_m() + e.radius + c.radius
		if d < their_reach + 1.2 and d < td:
			td = d
			threat = e
	var want := c.attack_range_m() + c.radius + t.radius - 0.4
	var dist := G.flat_dist(t.global_position, p)
	var away := G.flat_dir(t.global_position, p)
	var back := -team_ai.lane_dir
	var goal := Vector3.INF
	if threat != null:
		# kite: away from the threat, biased toward our side of the lane
		var dir := (G.flat_dir(threat.global_position, p) * 0.7 + back * 0.3).normalized()
		goal = p + dir * budget
	elif dist > want - 0.2:
		goal = p - away * minf(dist - want + 0.6, budget)
	elif dist < want - 1.6:
		goal = p + away * minf(want - 0.6 - dist, budget)
	elif G.rng.randf() < 0.45:
		# short reposition step, usually continuing the previous side
		if G.rng.randf() < 0.3:
			_strafe_dir = -_strafe_dir
		var side := Vector3(-away.z, 0, away.x) * _strafe_dir
		goal = p + side * minf(G.rng.randf_range(0.6, 1.2), budget)
	if goal == Vector3.INF:
		return goal
	if _under_enemy_turret(goal) and not _under_enemy_turret(p):
		goal = p + back * minf(1.5, budget)
	if not m.nav.is_walkable(goal):
		goal = m.nav.nearest_walkable(goal)
	return goal


func _lane() -> void:
	var p := c.global_position
	var ta := team_ai
	var lane_dir := ta.lane_dir
	# health relic when hurt and it's on our side of the fight
	if c.hp_ratio() < relic_hp:
		var relic = _nearest_relic()
		if relic != null and ta.lane_coord(relic.global_position) < ta.lane_coord(ta.contact) + 3.0:
			_move(relic.global_position)
			return
	var threat_close := false
	for e in enemies:
		if G.flat_dist(e.global_position, p) < e.attack_range_m() + e.radius + c.radius + 1.0:
			threat_close = true
			break
	# farm: last hits first, then push the wave if it's safe
	if not enemy_minions.is_empty() and _stance != "retreat":
		var best: Unit = null
		var best_s := INF
		var ad := c.stats.ad
		var skilled := lasthit >= 1.0 or G.rng.randf() < lasthit
		for e in enemy_minions:
			if _under_enemy_turret(e.global_position) and (enemy_turret == null or not _minions_tanking(enemy_turret) or _turret_targeting_me()):
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > c.attack_range_m() + 6.0:
				continue
			# while enemy champions are close, only farm what's already in range
			if threat_close and level >= 2 and not c.in_attack_range(e):
				continue
			var dmg: float = ad * Combat.resist_multiplier(e.stats.armor, c, true)
			var s: float = e.hp + d * 15.0
			if not skilled:
				s = d   # [bot-diff] attacks whatever is nearest
			elif e.hp <= dmg * 1.05:
				s -= 1000.0
			if s < best_s:
				best_s = s
				best = e
		if best != null:
			_attack(best)
			return
	# siege the turret while our minions tank it
	var pushing := _push_ok()
	if enemy_turret != null and not enemy_turret.is_invulnerable() and (_minions_tanking(enemy_turret) or pushing) \
			and (enemy_turret.attack_target != c or pushing) and _stance != "retreat":
		_attack(enemy_turret)
		return
	if pushing and enemy_turret == null and enemies.is_empty():
		var tt := _enemy_front_turret()
		if tt != null:   # walk up to the turret's edge together with the team
			var dir := G.flat_dir(tt.global_position, c.global_position)
			_move(tt.global_position + dir * (c.attack_range_m() + tt.radius - 0.6))
			return
	# hit exposed inhibitor / nexus
	for s in m.structures:
		if s.team != c.team and (s.kind == G.Kind.INHIBITOR or s.kind == G.Kind.NEXUS) and not s.dead and not s.is_invulnerable():
			if G.flat_dist(p, s.global_position) < 12.0 and (enemy_turret == null or _minions_tanking(enemy_turret)):
				_attack(s)
				return
	# position relative to our wave front
	var goal: Vector3
	if _stance == "retreat":
		goal = ta.safe_point
	else:
		var back := (1.5 if frontline else 4.5)
		if _stance == "hold" and not ta.enemies.is_empty():
			back += 1.0 if frontline else 2.0
		back *= back_scale   # [bot-diff] low levels stand at / in front of the wave
		var k := minf(ta.front, ta.enemy_front + (1.0 if frontline else -2.0)) - back
		goal = ta.lane_point(k)
	var side := Vector3(-lane_dir.z, 0, lane_dir.x)
	goal += side * personal_offset
	if _under_enemy_turret(goal) and (enemy_turret == null or not _minions_tanking(enemy_turret)):
		goal -= lane_dir * 4.0
	if enemy_minions.is_empty() and ally_minions.is_empty() and _stance != "retreat":
		_opening(goal)
		return
	_hold_area(goal)


# ===================================================================== dodging
func _try_dodge() -> bool:
	if m.missiles.is_empty() or c.dead:
		return false
	if not c.casting.is_empty() or not c.channel.is_empty() or not c.dash.is_empty() or (c.cc & Buff.BLOCK_MOVE) != 0:
		return false
	var p := c.global_position
	for mi_v in m.missiles:
		if not is_instance_valid(mi_v):
			continue
		var mi: Missile = mi_v
		if not mi.alive or mi.team == c.team or mi.is_attack:
			continue
		if mi.mode != Missile.Mode.LINEAR or not mi.collides or not mi.hits_champions:
			continue
		var to := Vector3(p.x - mi.global_position.x, 0, p.z - mi.global_position.z)
		var along := to.dot(mi.dir)
		if along < -0.5 or along > maxf(mi.speed, 1.0) * 0.9 + 1.0 or along > mi.max_dist - mi.traveled + c.radius:
			continue
		var perp_v := to - mi.dir * along
		var perp := perp_v.length()
		var clear: float = mi.width + c.radius + 0.35
		if perp > clear:
			continue
		if not _dodged.has(mi):
			if _dodged.size() > 64:
				_dodged.clear()
			_dodged[mi] = false
			stat_threats += 1
		if _dodged[mi] or mi.age < dodge_react:   # [bot-diff] reaction time to a skillshot depends on the level
			continue
		_dodged[mi] = true
		if G.rng.randf() > dodge_chance:
			continue
		stat_dodges += 1
		var side: Vector3 = Vector3(-mi.dir.z, 0, mi.dir.x)
		if perp_v.dot(side) < 0.0:
			side = -side
		var goal := p + side * (clear - perp + 0.5)
		if not m.nav.is_walkable(goal):
			goal = p - side * (clear + perp + 0.5)
			if not m.nav.is_walkable(goal):
				continue
		c.issue_move(goal)
		_dodge_until = m.time + (clear + 0.5) / maxf(c.stats.move_speed * G.U, 1.0) + 0.05
		return true
	return false


# ===================================================================== abilities
func _try_abilities() -> bool:
	if not c.can_cast():
		return false
	var order := [3, 0, 2, 1]
	if level >= 3:
		# hard bots open with their crowd control, then the ultimate, then the damage abilities
		order = []
		for sl in CC_SLOTS.get(c.alias, []):
			if sl != 3:
				order.append(sl)
		order.append(3)
		for sl in [0, 2, 1]:
			if not order.has(sl):
				order.append(sl)
	for slot in order:
		var ab: Ability = c.abilities[slot]
		if ab == null or ab.cast_block_reason() != "":
			continue
		if not _ability_allowed(ab, slot):
			continue
		var t := ab.ai_consider(self)
		if t.get("_default", false):
			t = default_consider(ab)
		if not t.is_empty():
			if ability_skip > 0.0 and ab.recast_window <= 0.0 and G.rng.randf() < ability_skip:
				continue   # [bot-diff] hesitation: the ability is simply not used this time
			if ab.try_cast(t):
				return true
	return false


## [bot-diff] Level gates in front of a ready ability: ultimate patience, mana discipline, holding / chaining crowd control.
func _ability_allowed(ab: Ability, slot: int) -> bool:
	if slot == 3:
		return _ult_worth()
	if level < 2 or enemies.is_empty() and mode != "lane":
		return true
	if mode == "lane" and c.stats.uses_mana and mana_floor > 0.0:
		if c.mana < c.stats.max_mana * mana_floor and not _focus_killable():
			return false
	if cc_hold > 0.0 and slot in CC_SLOTS.get(c.alias, []):
		var all_held := not enemies.is_empty()
		for e in enemies:
			if G.flat_dist(e.global_position, c.global_position) < 12.0 and (e.cc & Buff.IMMOBILIZE) == 0:
				all_held = false
				break
		if all_held:
			return false   # chain: do not stack a second CC on someone who is already locked down
		if mode == "lane" and not _recently_attacked() and not _focus_killable():
			return false   # hold the CC for an engage / a pick
	return true


func _focus_killable() -> bool:
	return focus != null and is_instance_valid(focus) and not focus.dead and focus.hp < _burst()


func _recently_attacked() -> bool:
	return m.time - c.last_damaged_time < 2.0


func _ult_worth() -> bool:
	if enemies.is_empty() or level == 1:
		return true
	if level == 0:
		return G.rng.randf() < 0.5
	if ult_wait <= 0.0:
		return true
	var worth := c.hp_ratio() < 0.4 and mode != "lane"
	if not worth:
		var near_n := count_enemies_near(c.global_position, 9.0)
		worth = near_n >= 2
		if not worth:
			var burst := _burst() * 1.3 if level >= 3 else 0.0
			for e in enemies:
				if e.hp_ratio() < 0.5 or e.hp < burst:
					worth = true
					break
		if not worth and level >= 3 and mode == "fight" and _stance == "engage":
			worth = true
	if worth:
		_ult_hold_since = -1.0
		return true
	if mode == "fight":
		if _ult_hold_since < 0.0:
			_ult_hold_since = m.time
		elif m.time - _ult_hold_since > ult_wait:
			return true   # do not sit on it forever
	else:
		_ult_hold_since = -1.0
	return false


func _try_summoners() -> bool:
	for sm in c.summoners:
		if sm == null or sm.cast_block_reason() != "":
			continue
		var t: Dictionary = sm.ai_consider(self)
		if not t.is_empty() and not t.get("_default", false):
			stat_summ += 1
			return sm.try_cast(t)
	return false


## Generic ability usage based on the ability's targeting metadata.
func default_consider(ab: Ability) -> Dictionary:
	var rng := ab.range_m()
	match ab.target_type:
		Ability.Target.UNIT:
			if ab.target_side == Ability.Side.ENEMY:
				var t := best_enemy_in_range(rng + 0.5)
				if t != null:
					return {"unit": t, "pos": t.global_position, "dir": G.flat_dir(c.global_position, t.global_position)}
			else:
				var a := lowest_ally(rng, 0.6)
				if a != null:
					return {"unit": a, "pos": a.global_position, "dir": G.flat_dir(c.global_position, a.global_position)}
		Ability.Target.DIRECTION:
			var t2 := best_enemy_in_range(rng * 0.92)
			if t2 != null:
				var aim := predict(t2, ab.cast_time + G.flat_dist(c.global_position, t2.global_position) / maxf(ab_speed(ab), 1.0))
				return aim_at(aim, ab)
		Ability.Target.POINT:
			var t3 := best_enemy_in_range(rng + ab.ind_radius * G.U * 0.6)
			if t3 != null:
				var aim2 := predict(t3, ab.cast_time + 0.25)
				return aim_at(aim2, ab)
		Ability.Target.NONE:
			var r := maxf(ab.ind_radius * G.U, c.attack_range_m() + 1.0)
			if count_enemies_near(c.global_position, r) > 0:
				return {"pos": c.global_position, "dir": c.facing}
	return {}


func ab_speed(ab: Ability) -> float:
	return float(ab.get_meta("missile_speed", 18.0)) if ab.has_meta("missile_speed") else 18.0


func aim_at(pos: Vector3, ab: Ability) -> Dictionary:
	var scale := 1.0
	if level >= 2:   # [bot-diff] a locked-down target is an easy shot
		for e in enemies:
			if G.flat_dist(e.global_position, pos) < 2.5 and (e.cc & Buff.BLOCK_MOVE) != 0:
				scale = 0.15
				break
	var err := Vector3(G.rng.randf_range(-1, 1), 0, G.rng.randf_range(-1, 1)) * aim_error * scale
	var p := pos + err
	return ab.make_target(p, null)


## Predicted position of a unit after `t` seconds. Lead quality depends on the level: none (Intro) -> half the
## velocity (Beginner) -> full velocity (Intermediate) -> follows the target's actual move path (Hard).
func predict(u: Unit, t: float) -> Vector3:
	if (u.cc & Buff.BLOCK_MOVE) != 0 or lead <= 0.0:
		return u.global_position
	if level >= 3:
		if not u.casting.is_empty() and not u.casting.ability.can_move_while_casting:
			return u.global_position
		if u.moving and u.dash.is_empty() and (u.cc & Buff.FORCED_MOVE) == 0 and u.path_i < u.path.size():
			return _along_path(u, u.stats.move_speed * G.U * clampf(t, 0.0, 2.0))
	return u.global_position + u.velocity * clampf(t, 0.0, 1.5) * lead


func _along_path(u: Unit, dist: float) -> Vector3:
	var pos := u.global_position
	var i: int = u.path_i
	while i < u.path.size() and dist > 0.0:
		var wp: Vector3 = u.path[i]
		var to := Vector3(wp.x - pos.x, 0.0, wp.z - pos.z)
		var d := to.length()
		if d <= dist:
			dist -= d
			pos = Vector3(wp.x, pos.y, wp.z)
			i += 1
		else:
			pos += to / d * dist
			dist = 0.0
	return pos


func best_enemy_in_range(r: float, champs_only: bool = true) -> Unit:
	var p := c.global_position
	if level >= 1 and focus != null and is_instance_valid(focus) and not focus.dead and focus.is_targetable_by(c.team) \
			and G.flat_dist(p, focus.global_position) <= r + focus.radius:
		return focus
	var best: Unit = null
	var best_s := INF
	var burst := _burst() if level >= 3 else 0.0
	for e in enemies:
		var d := G.flat_dist(p, e.global_position)
		if d > r + e.radius:
			continue
		var s: float
		match level:
			0:
				s = d   # Intro: whoever is nearest
			1:
				s = e.hp_ratio() * 4.0 + d * 0.6
			2:
				s = e.hp_ratio() * 10.0 + d * 0.3
			_:
				# Hard: lowest effective hp, kills first, locked-down and ranged carries preferred
				s = (e.hp * (1.0 + (e.stats.armor + e.stats.mr) * 0.004) + e.total_shield()) / 60.0 + d * 0.5
				s -= 30.0 if e.hp < burst else 0.0
				s -= 12.0 if (e.cc & Buff.IMMOBILIZE) != 0 else 0.0
				s -= 6.0 if e.stats.attack_range > 300.0 else 0.0
		if s < best_s:
			best_s = s
			best = e
	return best


func lowest_ally(r: float, below: float) -> Unit:
	var best: Unit = null
	var br := below
	for a in allies + [c]:
		if a.dead:
			continue
		if G.flat_dist(c.global_position, a.global_position) > r + a.radius:
			continue
		if a.hp_ratio() < br:
			br = a.hp_ratio()
			best = a
	return best


func count_enemies_near(pos: Vector3, r: float, champs_only: bool = true) -> int:
	var n := 0
	for e in enemies:
		if G.flat_dist(pos, e.global_position) <= r + e.radius:
			n += 1
	if not champs_only:
		for e in enemy_minions:
			if G.flat_dist(pos, e.global_position) <= r + e.radius:
				n += 1
	return n


## Best point to hit the most enemy champions with a circle of radius r within range.
## Returns Vector3.INF when fewer than min_count enemies can be hit.
func best_cluster_point(rng: float, r: float, min_count: int = 1) -> Vector3:
	var best := Vector3.INF
	var best_n := min_count - 1
	for e in enemies:
		if G.flat_dist(c.global_position, e.global_position) > rng + r:
			continue
		var n := count_enemies_near(e.global_position, r)
		if n > best_n:
			best_n = n
			best = e.global_position
	return best


# ===================================================================== summoner decisions
func flash_decision(_ab) -> Dictionary:
	if level == 0:
		return {}
	var hp := c.hp_ratio()
	if not enemies.is_empty() and mode == "retreat":
		var danger_hp: float = [0.0, 0.12, 0.2, 0.3][level]
		var doomed := level >= 3 and _incoming * 1.5 > c.hp and hp < 0.5
		if (hp < danger_hp and in_danger()) or doomed:
			var away := G.flat_dir(enemies[0].global_position, c.global_position)
			if level >= 3:   # hard bots flash toward safety, not just away
				away = (away * 0.6 + G.flat_dir(c.global_position, team_ai.safe_point) * 0.4).normalized()
			var goal := c.global_position + away * 4.0
			if level < 3 or not _under_enemy_turret(goal):
				return {"pos": goal, "dir": away}
	if level >= 2 and mode == "fight" and focus != null and is_instance_valid(focus) and not focus.dead:
		var secure := focus.hp_ratio() < 0.15 and c.hp_ratio() > 0.4 if level == 2 else (focus.hp < _burst() * 0.8 and hp > 0.35 \
				and not _under_enemy_turret(focus.global_position))
		if secure:
			var d := G.flat_dist(c.global_position, focus.global_position)
			if d > c.attack_range_m() + 1.0 and d < c.attack_range_m() + 4.5:
				return {"pos": focus.global_position, "dir": G.flat_dir(c.global_position, focus.global_position)}
	return {}


func heal_decision(ab) -> Dictionary:
	var hp := c.hp_ratio()
	var thr: float = [0.10, 0.20, 0.28, 0.40][level]
	if not enemies.is_empty():
		if hp < thr:
			return {"pos": c.global_position}
		if level >= 3 and hp < 0.6 and (c.hp - _incoming * 1.2) < c.stats.max_hp * 0.12:
			return {"pos": c.global_position}   # burst coming in: heal before it lands
	if level >= 2 and not enemies.is_empty():
		var ally_thr := 0.22 if level == 2 else 0.32
		for a in allies:
			if not a.dead and a.hp_ratio() < ally_thr and G.flat_dist(a.global_position, c.global_position) < ab.range_m():
				return {"pos": c.global_position}
	return {}


func barrier_decision(_ab) -> Dictionary:
	if enemies.is_empty():
		return {}
	var hp := c.hp_ratio()
	if hp < [0.10, 0.20, 0.27, 0.38][level]:
		return {"pos": c.global_position}
	if level >= 3 and hp < 0.65 and _incoming * 2.0 > c.stats.max_hp * 0.25:
		return {"pos": c.global_position}
	return {}


const _HARD_CC := Buff.CC.STUN | Buff.CC.ROOT | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP


func cleanse_decision(_ab) -> Dictionary:
	if level == 0 or (c.cc & _HARD_CC) == 0:
		return {}
	if level == 1 and G.rng.randf() > 0.4:
		return {}
	if level == 2 and enemies.is_empty():
		return {}
	if level >= 3 and enemies.is_empty() and c.hp_ratio() > 0.8:
		return {}
	return {"pos": c.global_position}


func ghost_decision(_ab) -> Dictionary:
	return {} if level == 0 or not wants_speed() else {"pos": c.global_position}


## Exhaust the melee diver that is on top of a hurt bot (Intermediate and up).
func exhaust_decision(ab) -> Dictionary:
	if level < 2 or enemies.is_empty():
		return {}
	var best = null
	var best_hp := INF
	var hp_lim := 0.55 if level >= 3 else 0.35
	for e in enemies:
		var d := G.flat_dist(e.global_position, c.global_position)
		if d > ab.range_m() + e.radius or e.has_buff("exhaust"):
			continue
		var attacking_me: bool = c.damage_log.has(e) and m.time - float(c.damage_log[e]) < 1.5
		var diver: bool = e.stats.attack_range < 300.0 or "assassin" in ChampionDB.roles(e.alias)
		if diver and attacking_me and d < 6.0 and c.hp_ratio() < hp_lim and e.hp_ratio() > 0.3 and e.hp < best_hp:
			best_hp = e.hp
			best = e
	if best == null:
		return {}
	return {"unit": best, "pos": best.global_position}


func mark_decision(ab) -> Dictionary:
	if level == 0:
		return {}
	if ab.recast_window > 0.0:
		var tgt = ab.marked
		var hp_lim := 0.3 if level == 1 else 0.5
		if tgt != null and is_instance_valid(tgt) and tgt.kind == G.Kind.CHAMPION and mode == "fight" \
				and (tgt.hp_ratio() < hp_lim or (level >= 2 and frontline and _stance == "engage")) and c.hp_ratio() > 0.45 \
				and not _under_enemy_turret(tgt.global_position):
			return {"pos": tgt.global_position, "dir": G.flat_dir(c.global_position, tgt.global_position)}
		return {}
	var t := best_enemy_in_range(ab.range_m() * 0.85)
	if t != null and mode != "retreat":
		var aim := predict(t, G.flat_dist(c.global_position, t.global_position) / 12.0)
		if level >= 3:   # minions in the way eat the snowball
			for mn in enemy_minions:
				if G.flat_dist(c.global_position, mn.global_position) < G.flat_dist(c.global_position, aim) \
						and NavGrid._dist_to_segment(mn.global_position, c.global_position, aim) <= 0.5 + mn.radius:
					return {}
		return aim_at(aim, ab)
	return {}


func ignite_decision(ab) -> Dictionary:
	if level == 0:
		return {}
	if level == 3:
		# burn whoever the burst plus the burn will kill
		var lv: int = c.level
		var total: float = 70.0 + 20.0 * (mini(lv, 5) - 1) + 25.0 * maxi(lv - 5, 0)
		var burst := _burst() * 0.5 if mode == "fight" else 0.0
		var pick = null
		for e in enemies:
			if G.flat_dist(e.global_position, c.global_position) <= ab.range_m() + e.radius \
					and (e.hp <= total * 0.85 + burst or e.hp_ratio() < 0.25) and (pick == null or e.hp < pick.hp):
				pick = e
		return {"unit": pick, "pos": pick.global_position} if pick != null else {}
	var t := best_enemy_in_range(ab.range_m())
	if t != null and t.hp_ratio() < (0.2 if level == 1 else 0.35):
		return {"unit": t, "pos": t.global_position}
	return {}


# ===================================================================== shop / augments
func _shop_and_augments() -> void:
	if m.has_method("bot_shop") and m.time >= _next_shop:
		_next_shop = m.time + [40.0, 15.0, 0.0, 0.0][level]   # [bot-diff] low levels visit the shop late and rarely
		m.bot_shop(c)
	if c.augments_pending > 0 and m.has_method("bot_choose_augment"):
		m.bot_choose_augment(c)


# ===================================================================== human-like idle play
## Before the waves meet (game start, or a cleared lane): walk up toward the middle according to persona,
## face off with the enemy at a safe distance, step in for the occasional free auto, otherwise fidget.
func _opening(lane_goal: Vector3) -> void:
	var ta := team_ai
	var p := c.global_position
	var mid := ta.lane_coord(ta.enemy_nexus) * 0.5
	var own := ta.lane_coord(lane_goal)
	var k := lerpf(own, mid - (2.0 if frontline else 5.0), forward_bias)
	var side := Vector3(-ta.lane_dir.z, 0, ta.lane_dir.x)
	var anchor := ta.lane_point(k) + side * personal_offset
	var e := _nearest_enemy()
	if e != null:
		var away := G.flat_dir(e.global_position, p)
		var threat: float = e.attack_range_m() + e.radius + c.radius
		var dist := G.flat_dist(e.global_position, p)
		# a ranged bot with the longer reach (or a bold one) steps in for a poke now and then
		if is_ranged and m.time >= _next_harass and not _under_enemy_turret(e.global_position) 				and (c.attack_range_m() >= e.attack_range_m() - 0.5 or G.rng.randf() < harass * 0.4) and G.rng.randf() < harass:
			_harass_until = m.time + G.rng.randf_range(0.9, 1.6)
			_next_harass = m.time + G.rng.randf_range(3.0, 8.0) / maxf(harass, 0.2)
		if m.time < _harass_until:
			_attack(e)
			return
		# otherwise keep just outside their threat range (cautious personas a bit further)
		var keep := threat + caution
		if dist < keep:
			anchor = p + away * minf(keep - dist + 0.5, 3.0) + side * G.rng.randf_range(-0.8, 0.8)
		elif ta.lane_coord(anchor) > ta.lane_coord(e.global_position) - keep:
			anchor = e.global_position + away * keep
	_hold_area(anchor)


## Hold a spot like a player does: walk there, then keep making small clicks around it (sometimes pausing),
## drifting to face the enemy side, instead of freezing in place.
func _hold_area(anchor: Vector3) -> void:
	var p := c.global_position
	if G.flat_dist(p, anchor) > wander + 1.5:
		_move(anchor)
		_fidget_at = m.time + G.rng.randf_range(0.2, 0.6)
		return
	if m.time < _fidget_at:
		return
	_fidget_at = m.time + G.rng.randf_range(0.5, 1.8) * fidget_rate
	if G.rng.randf() < 0.3:
		return   # pause a moment
	var dir := Vector3(G.rng.randf_range(-1.0, 1.0), 0, G.rng.randf_range(-1.0, 1.0)).normalized()
	var e := _nearest_enemy()
	if e != null:
		dir = (dir + G.flat_dir(p, e.global_position) * 0.35).normalized()
	var goal := anchor + dir * G.rng.randf_range(0.4, wander)
	if not m.nav.is_walkable(goal):
		goal = m.nav.nearest_walkable(goal)
	if _under_enemy_turret(goal) and not _under_enemy_turret(p):
		return
	_move(goal, true)


func _nearest_enemy() -> Unit:
	var best: Unit = null
	var bd := INF
	for e in enemies:
		var d := G.flat_dist(e.global_position, c.global_position)
		if d < bd:
			bd = d
			best = e
	return best


func _nearest_enemy_dist() -> float:
	var e := _nearest_enemy()
	return G.flat_dist(e.global_position, c.global_position) if e != null else INF


## After a kill, when nobody is close: laugh / taunt / dance / joke for a moment, like players do.
func _maybe_emote(delay: float) -> void:
	if G.rng.randf() > emote_chance:
		return
	m.after(delay, func():
		if not is_instance_valid(c) or c.dead or c.is_busy() or _nearest_enemy_dist() < 9.0:
			return
		var opts := ["laugh", "taunt", "dance", "joke", "laugh", "taunt"]
		var kind: String = opts[G.rng.randi() % opts.size()]
		if not c.has_anim(kind):
			kind = "taunt" if c.has_anim("taunt") else ""
		if kind == "":
			return
		var dur := G.rng.randf_range(2.5, 4.0) if kind == "dance" else G.rng.randf_range(1.4, 2.2)
		c.issue_stop()
		c.play_anim(kind, 1.0, 0.2)
		c.anim_lock = dur
		_emote_until = m.time + dur
		if m.audio != null:
			m.audio.emote(c, kind))

