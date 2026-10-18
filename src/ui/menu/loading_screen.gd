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

const TIPS := [
	"Health relics heal on pickup, then pulse a second, larger heal around them shortly after.",
	"You can only shop and choose augments while dead or standing on your spawn platform.",
	"Mark throws a snowball — recast it to dash to whatever it hit.",
	"Augments arrive at levels 3, 7, 11 and 15. Each card can be rerolled once.",
	"Turrets hit harder with every consecutive shot on a champion. Let your minions tank.",
	"Ctrl + Q/W/E/R levels up an ability. Your ultimate unlocks at level 6.",
	"Tab shows the scoreboard. G reopens pending augment choices.",
	"Hold A and left-click to attack-move: you'll attack the closest enemy on the way.",
	"Champions take reduced damage from long-range pokes in ARAM: Mayhem. Commit to fights!",
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
		# keep the screen up at least a moment so it reads as a loading screen
		if all and t > 1.6:
			_done = true
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
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.03, 0.05))
	# faint diagonal hextech pattern
	for i in range(-20, 60):
		var x := i * 60.0 + fmod(t * 6.0, 60.0)
		draw_line(Vector2(x, 0), Vector2(x - vs.y * 0.6, vs.y), Color(0.1, 0.25, 0.3, 0.05), 1.0)
	text_center("HOWLING ABYSS", Vector2(vs.x * 0.5, 36), 26, C_GOLD_BRIGHT, f_bold, false, 5.0)
	text_center("ARAM: MAYHEM", Vector2(vs.x * 0.5, 66), 15, Color(0.8, 0.55, 1.0), f_bold, false, 3.0)
	var card_h := minf((vs.y - 230) * 0.5, 420.0)
	var card_w := card_h * 0.55
	var gap := 22.0
	var row_w := card_w * 5 + gap * 4
	var x0 := vs.x * 0.5 - row_w * 0.5
	for row in 2:
		var y := 92.0 + row * (card_h + 44)
		var idx := 0
		for i in _cards.size():
			if _cards[i].team != row:
				continue
			var r := Rect2(x0 + idx * (card_w + gap), y, card_w, card_h)
			_draw_card(i, r)
			idx += 1
	text_center("VS", Vector2(vs.x * 0.5, 92.0 + card_h + 22), 22, C_GOLD, f_heavy, true)
	var ty := vs.y - 40.0
	text_center("TIP:  " + _tip, Vector2(vs.x * 0.5, ty), 17, C_TEXT.darkened(0.1), f_semi)


func _draw_card(i: int, r: Rect2) -> void:
	var c: Dictionary = _cards[i]
	var p: String = _paths[i]
	var prog: float = _progress.get(p, 1.0)
	var team_col := G.COLOR_ALLY if c.team == 0 else G.COLOR_ENEMY
	var appear := clampf((t - i * 0.06) * 3.0, 0.0, 1.0)
	var rr := Rect2(r.position + Vector2(0, (1.0 - appear) * 30.0), r.size)
	tex_cover(Assets.champion_art(c.alias, 0, "load"), rr, Color(1, 1, 1, appear * (0.55 + 0.45 * prog)))
	_vgrad(Rect2(rr.position.x, rr.end.y - 110, rr.size.x, 110), Color(0, 0, 0, 0), Color(0, 0, 0, 0.9 * appear))
	draw_rect(Rect2(rr.position, Vector2(rr.size.x, 4)), team_col)
	if c.is_player:
		ornate_frame(rr, C_GOLD.lerp(C_GOLD_BRIGHT, 0.5 + 0.5 * sin(t * 3.0)), 2.5)
	else:
		draw_rect(rr, C_GOLD_DARK, false, 1.5)
	var nm: String = ChampionDB.client_data(c.alias).get("name", c.alias)
	text_center(nm.to_upper(), Vector2(rr.get_center().x, rr.end.y - 56), 20, C_GOLD_BRIGHT if c.is_player else C_TEXT, f_bold, true, 1.5)
	text_center("You" if c.is_player else "Bot", Vector2(rr.get_center().x, rr.end.y - 32), 14, C_TEAL if c.is_player else C_DIM, f_semi, true)
	if not c.summoners.is_empty():
		for s in 2:
			icon(Assets.summoner_icon(str(c.summoners[s]).to_lower()), Rect2(rr.position.x + 8 + s * 30, rr.position.y + 12, 26, 26), C_GOLD_DARK)
	# progress
	var pr := Rect2(rr.position.x, rr.end.y + 8, rr.size.x, 5)
	draw_rect(pr, Color(0.08, 0.1, 0.12))
	draw_rect(Rect2(pr.position, Vector2(pr.size.x * prog, pr.size.y)), C_TEAL if prog < 1.0 else C_GOLD)
	text_right("%d%%" % int(prog * 100), Vector2(rr.end.x, rr.end.y + 30), 13, C_DIM, f_semi)
