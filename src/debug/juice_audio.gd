extends Node
## [juice] Drives GameAudio's announcer queue with scripted event bursts and prints what actually plays
## (priority, order, drops), plus a champion-by-champion routing check of the event maps.
## tools/preview.sh 120 -- --champ=Lux --harness=res://src/debug/juice_audio.gd --audiolog
## (needs a real audio server, so run it through preview.sh which passes --audio-driver Dummy: playback is simulated)

var main = null
var match_ref = null


func _ready() -> void:
	_run()


func _wait_ann(secs: float) -> void:
	await JuiceUtil.wait(self, secs)


func _push_kill(m, killer, victim) -> void:
	m.events.append({"killer": killer, "victim": victim, "assists": [], "time": m.time, "team": G.enemy_team(victim.team)})


func _run() -> void:
	await JuiceUtil.wait(self, 1.5)
	var m = G.match
	var a: GameAudio = m.audio
	var me = G.player
	var foe = m.champions.filter(func(x): return x.team != me.team)[0]
	var ally = m.champions.filter(func(x): return x.team == me.team and x != me)[0]
	print("JUICE-AUDIO routing check")
	for c in m.champions:
		var si: Dictionary = a._spell_events.get(c.alias, {})
		var ba: Dictionary = a._ba_events.get(c.alias, {})
		var row := "%-12s BA %d/%d crit %d/%d |" % [c.alias, ba.get("cast", []).size(), ba.get("hit", []).size(), ba.get("crit_cast", []).size(), ba.get("crit_hit", []).size()]
		for k in ["Q", "W", "E", "R"]:
			var d: Dictionary = si.get(k, {})
			row += " %s:%d/%d/%d/%d" % [k, d.get("cast", []).size(), d.get("launch", []).size(), d.get("act", []).size(), d.get("hit", []).size()]
		print("JUICE-AUDIO ", row)
	await JuiceUtil.wait(self, 8.0)   # let the welcome lines pass
	print("JUICE-AUDIO burst 1: 3x ally slain then a double kill by you (expect: ONE generic line max, then double kill)")
	_push_kill(m, foe, ally)
	G.announcer_event.emit("ally_slain", false)
	G.announcer_event.emit("ally_slain", false)
	_push_kill(m, me, foe)
	G.announcer_event.emit("double_kill", true)
	await _wait_ann(9.0)
	print("JUICE-AUDIO burst 2: shutdown, penta, ace queued together (expect penta, ace, shutdown by priority)")
	_push_kill(m, me, foe)
	G.announcer_event.emit("shutdown", true)
	G.announcer_event.emit("penta_kill", true)
	G.announcer_event.emit("ace", true)
	await _wait_ann(14.0)
	print("JUICE-AUDIO burst 3: stale low priority line (expect dropped after ttl) behind a long penta")
	_push_kill(m, foe, ally)
	G.announcer_event.emit("penta_kill", false)
	G.announcer_event.emit("enemy_slain", true)
	await _wait_ann(8.0)
	print("JUICE-AUDIO burst 4: structures")
	G.announcer_event.emit("turret_destroyed", true)
	G.announcer_event.emit("inhib_lost", false)
	await _wait_ann(10.0)
	print("JUICE-AUDIO burst 5: victory cuts everything")
	G.announcer_event.emit("ally_slain", false)
	G.announcer_event.emit("victory", true)
	await _wait_ann(4.0)
	print("JUICE-AUDIO played:")
	for r in a.play_log:
		if "announcer" in String(r[2]):
			print("JUICE-AUDIO   %6.1f %s %s" % [r[0], String(r[1]).replace("Play_vo_Announcer_", ""), r[2]])
	print("JUICE DONE")
	get_tree().quit()
