extends Node
## [bot-diff] Checks BotBrain.level_for() against G.lineup (per-bot levels), --botlevels and the settings fallback.
## godot --headless --path . --fixed-fps 60 --quit-after 60 -- --sim --time=3 --harness=res://src/debug/bot_lineup_test.gd

var main = null
var match_ref = null
var fails := 0


func _check(name: String, got, want) -> void:
	if got == want:
		print("LINEUP PASS ", name)
	else:
		fails += 1
		print("LINEUP FAIL %s got=%s want=%s" % [name, str(got), str(want)])


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var m = match_ref
	var order_bot: Champion = null
	var chaos_bot: Champion = null
	for c in m.champions:
		if c.controller is BotBrain and c != G.player:
			if c.team == G.Team.ORDER and order_bot == null:
				order_bot = c
			elif c.team == G.Team.CHAOS and chaos_bot == null:
				chaos_bot = c
	G.lineup = []
	G.settings.difficulty = 1
	_check("no lineup -> settings.difficulty", BotBrain.level_for(order_bot), 1)
	G.lineup = [
		{"team": G.Team.ORDER, "champion": order_bot.alias, "difficulty": 3},
		{"team": G.Team.CHAOS, "champion": chaos_bot.alias, "difficulty": 0},
		{"team": G.Team.CHAOS, "champion": order_bot.alias, "difficulty": 2},
		{"team": G.Team.ORDER, "champion": G.player.alias, "difficulty": -1}]
	_check("lineup order bot", BotBrain.level_for(order_bot), 3)
	_check("lineup chaos bot", BotBrain.level_for(chaos_bot), 0)
	_check("same alias other team", BotBrain.lineup_difficulty(G.Team.CHAOS, order_bot.alias), 2)
	_check("human entry falls back to settings", BotBrain.level_for(G.player), 1)
	_check("missing entry -> -2", BotBrain.lineup_difficulty(G.Team.ORDER, "NoSuchChamp"), -2)
	var b: BotBrain = order_bot.controller
	b.set_level(0)
	_check("set_level(0) reaction", b.reaction, BotBrain.LV.reaction[0])
	b.set_level(3)
	_check("set_level(3) dodge", b.dodge_chance, BotBrain.LV.dodge[3])
	G.lineup = []
	print("LINEUP DONE fails=%d" % fails)
