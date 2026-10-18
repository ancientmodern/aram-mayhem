class_name LoadingScreen
extends UIScreen
## Loading screen with the ten champion loading-art cards. Loads the champion models and the map on
## background threads (real per-card progress), emits action("loaded"), then fades out via finish().

var cfg := {}
var _paths := {}                 ## card index -> resource path (champions), -1 -> map
var _progress := {}              ## path -> 0..1
var _held: Array = []            ## loaded resources (kept referenced so the match reuses them)
var _done := false
var _emitted := false
var _finishing := -1.0
var _tip := ""
var _cards: Array = []           ## [{alias, team, is_player, summoners}]
var _disp := {}                  ## card index -> displayed progress (eases toward the real load, at its own pace like each client in League)
var _speed := {}                 ## card index -> max progress per second

const TIPS := [
	"Health relics heal on pickup, then pulse a second, larger heal around them shortly after.",
	"You can only shop while dead or standing on your spawn platform.",
	"Mark throws a snowball — recast it to dash to whatever it hit.",
	"Poro snax are for poros. Everything else is for the enemy Nexus.",
	"Turrets hit harder with every consecutive shot on a champion. Let your minions tank.",
	"Ctrl + Q/W/E/R levels up an ability. Your ultimate unlocks at level 6.",
	"Hold Tab for the scoreboard.",
	"Hold A and left-click to attack-move: you'll attack the closest enemy on the way.",
	"Long-range pokes deal reduced damage on the Howling Abyss. Commit to fights!",
]


func _ready() -> void:
	super._ready()
	_tip = TIPS[G.rng.randi() % TIPS.size()]
	var order: Array = [cfg.get("player_champion", "Ahri")] + cfg.get("ally_champions", [])
	var chaos: Array = cfg.get("enemy_champions", [])
	for i in order.size():
		_cards.append({"alias": order[i], "team": 0, "is_player": i == 0,
				"summoners": cfg.get("player_summoners", ["Flash", "Mark"]) if i == 0 else []})
	for a in chaos:
		_cards.append({"alias": a, "team": 1, "is_player": false, "summoners": []})
	for i in _cards.size():
		_disp[i] = 0.0
		_speed[i] = G.rng.randf_range(0.34, 0.62)
	for i in _cards.size():
		var p := Assets.champion_model_path(_cards[i].alias, cfg.get("player_skin", 0) if i == 0 else 0)
		_paths[i] = p
	_paths[-1] = "res://assets/map/howling_abyss.glb"
	for k in _paths:
		var p: String = _paths[k]
		if ResourceLoader.exists(p):
			ResourceLoader.load_threaded_request(p, "", true)
			_progress[p] = 0.0
		else:
			_progress[p] = 1.0
	Sfx.music("", 1.5)
	Sfx.ui("to_lobby", -2.0)   # [ui-polish] League's transition whoosh as the loading screen opens


func _process(delta: float) -> void:
	super._process(delta)
	if not _done:
		var all := true
		for p in _progress.keys():
			if _progress[p] >= 1.0:
				continue
			var arr := []
			var st := ResourceLoader.load_threaded_get_status(p, arr)
			match st:
				ResourceLoader.THREAD_LOAD_LOADED:
					_held.append(ResourceLoader.load_threaded_get(p))
					_progress[p] = 1.0
				ResourceLoader.THREAD_LOAD_IN_PROGRESS:
					_progress[p] = maxf(_progress[p], float(arr[0]) if not arr.is_empty() else 0.0)
					all = false
				_:
					_progress[p] = 1.0
		# displayed per-card progress climbs independently (never ahead of the real load) so the screen reads as loading
		for i in _cards.size():
			var real: float = _progress.get(_paths[i], 1.0)
			var cap := clampf((t - 0.35) * float(_speed[i]), 0.0, 1.0)
			_disp[i] = move_toward(_disp[i], minf(real, cap), delta * 0.9)
			if _disp[i] < 1.0:
				all = false
		if all and _progress.get(_paths[-1], 1.0) >= 1.0:
			_done = true
			Sfx.ui("accept", -4.0)   # [ui-polish] ready cue
	elif not _emitted:
		_emitted = true
		# give one frame to render 100% before the (blocking) match build
		await get_tree().process_frame
		await get_tree().process_frame
		super.on_action("loaded")
	if _finishing >= 0.0:
		_finishing += delta
		modulate.a = 1.0 - clampf(_finishing / 0.6, 0.0, 1.0)
		if _finishing > 0.6:
			queue_free()


func finish() -> void:
	_finishing = 0.0
	_held.clear()


func draw_screen(vs: Vector2) -> void:
	vgrad_stops(Rect2(Vector2.ZERO, vs), [[0.0, Color("091428")], [0.5, Color("050d1a")], [1.0, Color("010a13")]])
	smoke(vs, 0.12, 8.0)
	# faint hextech diagonals
	for i in range(-20, 60):
		var x := i * 60.0 + fmod(t * 6.0, 60.0)
		draw_line(Vector2(x, 0), Vector2(x - vs.y * 0.6, vs.y), Color(0.1, 0.25, 0.3, 0.04), 1.0)
	vignette(vs, 0.55)
	var ha := appear(0.0)
	label("Howling Abyss", Vector2(vs.x * 0.5, 42 - (1.0 - ha) * 12), "h3", 1, Color(C_GOLD_BRIGHT.r, C_GOLD_BRIGHT.g, C_GOLD_BRIGHT.b, ha), 38.0, true)
	label("ARAM: Mayhem", Vector2(vs.x * 0.5, 80 - (1.0 - ha) * 12), "sub", 1, Color(0.82, 0.58, 1.0, ha), 20.0)
	divider(vs.x * 0.5, 106, 460.0 * ha, ha)
	var card_h := minf((vs.y - 350) * 0.5, 420.0)
	var card_w := card_h * 0.55
	var gap := 24.0
	var row_w := card_w * 5 + gap * 4
	var x0 := vs.x * 0.5 - row_w * 0.5
	for row in 2:
		var y := 128.0 + row * (card_h + 56)
		var idx := 0
		for i in _cards.size():
			if _cards[i].team != row:
				continue
			var r := Rect2(x0 + idx * (card_w + gap), y, card_w, card_h)
			_draw_card(i, r)
			idx += 1
	# VS medallion between the rows
	var vy := 128.0 + card_h + 28.0
	_hgrad(Rect2(x0, vy, row_w * 0.5 - 34, 2), Color(0.78, 0.67, 0.43, 0.0), Color(0.78, 0.67, 0.43, 0.6))
	_hgrad(Rect2(vs.x * 0.5 + 34, vy, row_w * 0.5 - 34, 2), Color(0.78, 0.67, 0.43, 0.6), Color(0.78, 0.67, 0.43, 0.0))
	label("VS", Vector2(vs.x * 0.5, vy), "h3", 1, C_GOLD, 30.0, true)
	# tip (separate from the per-card progress, centred at the bottom)
	var tip_w := label_w(_tip, "body_l", 21.0) + 70.0
	var tx := vs.x * 0.5 - tip_w * 0.5
	label("Tip", Vector2(tx, vs.y - 48), "h6", 0, C_GOLD, 19.0)
	label(_tip, Vector2(tx + 58, vs.y - 48), "body_l", 0, Color("cdbe91"), 21.0, false, 0.0, vs.x - 260.0)


func _draw_card(i: int, r: Rect2) -> void:
	var c: Dictionary = _cards[i]
	var p: String = _paths[i]
	var prog: float = _disp.get(i, 1.0)
	var team_col := G.COLOR_ALLY if c.team == 0 else G.COLOR_ENEMY
	var appear_k := appear(0.12 + (i % 5) * 0.07 + c.team * 0.1, 0.5)
	var rr := Rect2(r.position + Vector2(0, (1.0 - appear_k) * 36.0), r.size)
	var a := appear_k
	glow(rr, Color(team_col.r, team_col.g, team_col.b, 0.14 * a), 14)
	tex_cover(Assets.champion_art(c.alias, 0, "load"), rr, Color(1, 1, 1, a * (0.5 + 0.5 * prog)))
	_vgrad(Rect2(rr.position.x, rr.end.y - 150, rr.size.x, 150), Color(0, 0, 0, 0), Color(0.004, 0.039, 0.075, 0.95 * a))
	# team colour cap
	_hgrad(Rect2(rr.position, Vector2(rr.size.x, 5)), Color(team_col.r, team_col.g, team_col.b, a), Color(team_col.r, team_col.g, team_col.b, a * 0.55))
	if c.is_player:
		var pulse := 0.5 + 0.5 * sin(t * 3.0)
		glow(rr, Color(0.78, 0.67, 0.43, 0.25 + 0.2 * pulse), 12)
		grad_border(rr, 3.0, [[0.0, Color("785a28")], [0.55, Color("c89b3c")], [1.0, Color("f0e6d2")]], a)
	else:
		grad_border(rr, 2.0, [[0.0, Color("463714")], [1.0, Color("785a28")]], a)
	var nm: String = ChampionDB.client_data(c.alias).get("name", c.alias)
	label(nm, Vector2(rr.get_center().x, rr.end.y - 84), "h4", 1, Color(C_GOLD_BRIGHT.r, C_GOLD_BRIGHT.g, C_GOLD_BRIGHT.b, a) if c.is_player else Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, a), 25.0, true, 0.0, rr.size.x - 12)
	label("You" if c.is_player else "%s Bot" % nm, Vector2(rr.get_center().x, rr.end.y - 56), "label", 1, Color(C_TEAL.r, C_TEAL.g, C_TEAL.b, a) if c.is_player else Color(C_DIM.r, C_DIM.g, C_DIM.b, a), 18.0, true)
	var sp: Array = c.summoners if not c.summoners.is_empty() else ["Flash", "Mark"]
	for s in 2:
		icon(Assets.summoner_icon(str(sp[s]).to_lower()), Rect2(rr.position.x + 10 + s * 40, rr.position.y + 16, 34, 34), C_GOLD_DARK, Color(1, 1, 1, a))
	# level ring
	var lc := Vector2(rr.end.x - 26, rr.position.y + 34)
	draw_circle(lc, 18, Color(0.004, 0.039, 0.075, 0.9 * a))
	draw_arc(lc, 18, 0, TAU, 32, Color(0.78, 0.67, 0.43, a), 2.0, true)
	label("1", lc, "num", 1, Color(C_GOLD_BRIGHT.r, C_GOLD_BRIGHT.g, C_GOLD_BRIGHT.b, a), 21.0)
	# per-card progress bar + percent inside the card (rises independently per player, like League)
	var pr := Rect2(rr.position.x + 10, rr.end.y - 16, rr.size.x - 20, 5)
	draw_rect(pr.grow(1.5), Color(0.004, 0.039, 0.075, 0.9 * a))
	draw_rect(pr, Color(0.08, 0.1, 0.12, a))
	var pw := pr.size.x * prog
	if pw > 0.5:
		_hgrad(Rect2(pr.position, Vector2(pw, pr.size.y)), C_BLUE if prog < 1.0 else C_GOLD_DARK, C_TEAL if prog < 1.0 else C_GOLD)
	label("%d%%" % int(prog * 100), Vector2(rr.end.x - 12, rr.end.y - 32), "label", 2, Color(C_DIM.r, C_DIM.g, C_DIM.b, a), 16.0)
