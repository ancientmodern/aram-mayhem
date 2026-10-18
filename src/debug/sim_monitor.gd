class_name SimMonitor
extends Node
## QA harness: logs match events/state and quits after a time limit.
## Usage: godot --path . --fixed-fps 60 -- --sim [--time=600] [--shots=10,60] [--botplayer]

var match_ref = null
var limit := 600.0
var report_every := 30.0
var _next_report := 0.0
var shots: Array = []
var shot_dir := "user://shots"
var bot_player := true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			limit = float(a.substr(7))
		elif a.begins_with("--shots="):
			for s in a.substr(8).split(","):
				shots.append(float(s))
		elif a == "--nobot":
			bot_player = false
		elif a.begins_with("--every="):
			report_every = float(a.substr(8))
		elif a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	G.champion_killed.connect(func(v, k, ass): _log("KILL %s -> %s (+%d assists)" % [
			k.display_name if k != null and is_instance_valid(k) else "?", v.display_name, ass.size()]))
	G.structure_destroyed.connect(func(s, k): _log("STRUCTURE %s %s destroyed" % [G.TEAM_NAMES[s.team], s.display_name]))
	G.augment_chosen.connect(func(c, a): _log("AUGMENT %s took %s [%s]" % [c.display_name, a.display_name, a.get("rarity")]))
	G.match_over.connect(func(w): _log("GAME OVER winner=%s" % G.TEAM_NAMES[w]); _summary(); get_tree().quit())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_start_watchdog()
	G.debug_sites = true


var _wd: Thread = null
var _wd_run := true


func _start_watchdog() -> void:
	_wd = Thread.new()
	_wd.start(_watchdog)


func _watchdog() -> void:
	var last := -1
	var stuck := 0
	while _wd_run:
		OS.delay_msec(1000)
		# hard memory cap: a runaway sim must never grow the pagefile / fill the disk
		var mem_mb := OS.get_static_memory_usage() / 1048576
		if mem_mb > 3000:
			print("WATCHDOG MEMORY CAP %d MB ctx=%s unit=%s | %s" % [mem_mb, G.ctx, G.ctx_unit, G.ctx2])
			for cr in G._ring:
				print("  crumb " + str(cr))
			OS.kill(OS.get_process_id())
		if G.beat == last:
			stuck += 1
			if stuck == 4:
				var f := FileAccess.open("user://watchdog.txt", FileAccess.WRITE)
				var msg := "HANG ctx=%s unit=%s | %s | %s" % [G.ctx, G.ctx_unit, G.ctx2, G.ctx3]
				f.store_line(msg)
				# read the ring directly (calling script functions from this thread corrupts the call stack)
				var ring: Array = G._ring
				var ri: int = G._ri
				for i in ring.size():
					var cr = ring[(ri + i) % ring.size()] if ring.size() == 64 else ring[i]
					f.store_line("  crumb " + str(cr))
					print("  crumb " + str(cr))
				f.flush()
				print("WATCHDOG " + msg)
		else:
			stuck = 0
		last = G.beat


func _exit_tree() -> void:
	_wd_run = false
	if _wd != null:
		_wd.wait_to_finish()


func _log(s: String) -> void:
	var t: float = match_ref.time if match_ref != null else 0.0
	print("[%5.1f] %s" % [t, s])


func _process(_delta: float) -> void:
	if match_ref == null:
		return
	var t: float = match_ref.time
	if bot_player and G.player != null and not (G.player.controller is BotBrain):
		var b := BotBrain.new()
		b.setup(G.player, match_ref)
		G.player.controller = b
		G.player.is_bot = true
		G.player.auto_level_abilities()
	if t >= _next_report:
		_next_report += report_every
		_report()
	if not shots.is_empty() and t >= shots[0]:
		shots.pop_front()
		_screenshot(t)
	if t >= limit:
		_summary()
		get_tree().quit()


func _report() -> void:
	var minions := [0, 0]
	for u in match_ref.units:
		if u.kind == G.Kind.MINION and not u.dead:
			minions[u.team] += 1
	var nb := 0
	var ne := 0
	for u in match_ref.units:
		nb += u.buffs.size()
		ne += u.effects.size()
	var diag := "units=%d buffs=%d effects=%d missiles=%d timers=%d tickers=%d fx=%d nodes=%d mem=%dMB" % [match_ref.units.size(), nb, ne,
			match_ref.missiles.size(), match_ref._timers.size(), match_ref.tickers.size(), match_ref.fx_root.get_child_count(),
			get_tree().get_node_count(), OS.get_static_memory_usage() / 1048576]
	var line := "STATE minions=%s kills=%s fps=%d %s |" % [str(minions), str(match_ref.kills), Engine.get_frames_per_second(), diag]
	for c in match_ref.champions:
		line += " %s L%d %d/%d/%d hp%d%% %s%s @%d,%d;" % [c.alias.substr(0, 5), c.level, c.kills, c.deaths, c.assists,
				int(c.hp_ratio() * 100), "DEAD" if c.dead else (c.controller.mode if c.controller is BotBrain else "pl"),
				"" if c.augments.is_empty() else " A%d" % c.augments.size(), int(c.global_position.x), int(c.global_position.z)]
	var ta0: TeamAI = match_ref.team_ai(0)
	var ta1: TeamAI = match_ref.team_ai(1)
	line += " | T0 %s f=%.0f ef=%.0f  T1 %s f=%.0f ef=%.0f" % [ta0.stance, ta0.front, ta0.enemy_front, ta1.stance, ta1.front, ta1.enemy_front]
	_log(line)


func _summary() -> void:
	_log("SUMMARY time=%.0f kills=%s" % [match_ref.time, str(match_ref.kills)])
	for s in match_ref.structures:
		if s.kind != G.Kind.TURRET or s.tier != Turret.Tier.FOUNTAIN:
			_log("  %s %-18s %s hp=%d" % [G.TEAM_NAMES[s.team], s.display_name, "DEAD" if s.dead else "alive", int(s.hp)])
	for c in match_ref.champions:
		_log("  %s %-12s L%d %d/%d/%d cs=%d gold=%d dmg=%d items=%d augs=%s" % [G.TEAM_NAMES[c.team], c.alias, c.level,
				c.kills, c.deaths, c.assists, c.cs, int(c.total_gold), int(c.champion_damage_total), c.items.size(),
				str(c.augments.map(func(a): return a.display_name))])


func _screenshot(t: float) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/shot_%04d.png" % [shot_dir, int(t)]
	img.save_png(path)
	_log("SHOT " + ProjectSettings.globalize_path(path))
