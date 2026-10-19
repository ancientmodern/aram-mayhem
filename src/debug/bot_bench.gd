extends Node
## [bot-diff] Bot-vs-bot benchmark harness: one headless match with a difficulty level per team, results as a "BENCH {json}" line.
## Usage (tools/bot_bench.sh drives this over many seeds / pairings):
##   godot --headless --path . --fixed-fps 60 -- --sim --time=900 --seed=3 --botlevels=3,0 --harness=res://src/debug/bot_bench.gd
## --botlevels=<ORDER level>,<CHAOS level> (BotBrain.level_for); every champion on both teams is a BotBrain (SimMonitor installs the
## player's brain). Per team it reports: win / kills / damage to champions / structures / CS / gold / ability casts / summoner uses /
## champion-directed skillshots launched + hit / skillshots that threatened a champion + sidesteps.
## A match that is still running at the time cap is adjudicated: kills + structures destroyed (turret 3, inhibitor 6), tie = draw.

var main = null
var match_ref = null

var limit := 900.0
var _done := false
var _tracked: Array = []        ## [{mi, team, hits, directed}]
var shots := [0, 0]             ## champion-directed skillshots launched, per source team
var shot_hits := [0, 0]         ## ... of which hit a champion
var hits_taken := [0, 0]        ## skillshot hits on champions of this team (victim side)
var winner := -2
var _seen := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			limit = float(a.substr(7))
	G.match_over.connect(func(w): winner = w; _report("nexus"))


func _process(_dt: float) -> void:
	if match_ref == null or _done:
		return
	var m = match_ref
	for mi_v in m.missiles:
		if not is_instance_valid(mi_v):
			continue
		var mi: Missile = mi_v
		var id := mi.get_instance_id()
		if _seen.has(id):
			continue
		_seen[id] = true
		if mi.mode != Missile.Mode.LINEAR or mi.is_attack or not mi.hits_champions or mi.source == null \
				or not is_instance_valid(mi.source) or mi.source.kind != G.Kind.CHAMPION or mi.team > 1:
			continue
		var a: Vector3 = mi.global_position
		var b: Vector3 = a + mi.dir * mi.max_dist
		var directed := false
		for e in m.champions_of(1 - mi.team, true):
			if G.flat_dist(a, e.global_position) <= mi.max_dist + 1.0 and NavGrid._dist_to_segment(e.global_position, a, b) <= mi.width + e.radius + 2.5:
				directed = true
				break
		_tracked.append({"mi": mi, "team": mi.team, "hits": mi.hit_units, "directed": directed, "done": false})
	var keep: Array = []
	for t in _tracked:
		if is_instance_valid(t.mi) and t.mi.alive:
			keep.append(t)
		else:
			_finalize(t)
	_tracked = keep
	if _seen.size() > 4000:
		_seen.clear()
	if m.time >= limit - 0.5:
		_report("time")


func _finalize(t: Dictionary) -> void:
	var hit := false
	for u in t.hits.keys():
		if is_instance_valid(u) and u.kind == G.Kind.CHAMPION and u.team != t.team:
			hit = true
			hits_taken[u.team] += 1
	if t.directed or hit:
		shots[t.team] += 1
		if hit:
			shot_hits[t.team] += 1


func _score(team: int) -> int:
	# structures the OTHER team destroyed: turrets 3, inhibitors 6
	var sc := 0
	for s in match_ref.structures:
		if s.team == team and s.dead:
			if s.kind == G.Kind.TURRET and s.tier != Turret.Tier.FOUNTAIN:
				sc += 3
			elif s.kind == G.Kind.INHIBITOR:
				sc += 6
	return sc


func _report(how: String) -> void:
	if _done or match_ref == null:
		return
	_done = true
	for t in _tracked:
		_finalize(t)
	var m = match_ref
	var lv := [0, 0]
	var teams := []
	for tm in 2:
		teams.append({"kills": 0, "deaths": 0, "dmg": 0.0, "taken": 0.0, "cs": 0, "gold": 0.0, "casts": 0, "summ": 0,
				"threats": 0, "dodges": 0, "level": 0.0, "items": 0, "augs": 0})
	for c in m.champions:
		var tm: Dictionary = teams[c.team]
		tm.kills += c.kills
		tm.deaths += c.deaths
		tm.dmg += c.champion_damage_total
		tm.taken += c.damage_taken_total
		tm.cs += c.cs
		tm.gold += c.total_gold
		tm.level += c.level / 5.0
		tm.items += c.items.size()
		tm.augs += c.augments.size()
		if c.controller is BotBrain:
			lv[c.team] = c.controller.level
			tm.casts += c.controller.stat_casts
			tm.summ += c.controller.stat_summ
			tm.threats += c.controller.stat_threats
			tm.dodges += c.controller.stat_dodges
	var sc := [_score(1), _score(0)]   # structures destroyed BY team 0 = losses of team 1
	var w := winner
	var decided := "nexus"
	if w < 0:
		# time cap: composite score = kill difference + structure difference (a turret is worth 3 kills, an inhibitor 6)
		decided = "adjudicated"
		var d: int = (teams[0].kills + sc[0]) - (teams[1].kills + sc[1])
		w = 0 if d > 0 else (1 if d < 0 else -1)
	for tm in 2:
		teams[tm]["shots"] = shots[tm]
		teams[tm]["shot_hits"] = shot_hits[tm]
		teams[tm]["hits_taken"] = hits_taken[tm]
		teams[tm]["struct"] = sc[tm]
	var out := {"seed": _arg_int("--seed=", 0), "levels": lv, "winner": w, "decided": decided,
			"time": snappedf(m.time, 0.1), "teams": teams}
	print("BENCH " + JSON.stringify(out))


func _arg_int(prefix: String, dflt: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return int(a.substr(prefix.length()))
	return dflt
