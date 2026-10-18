class_name ChampSelect
extends UIScreen
## ARAM champion select: a random champion, 2 rerolls, a shared bench to swap with,
## trades with allied bots, summoner spells and bot difficulty. Emits action("locked") / action("back").

var team: Array = []            ## 5 aliases, [0] = player
var bench: Array = []
var rerolls := 2
var summoners := ["Flash", "Mark"]
var cfg := {}                   ## filled on lock-in
var _sum_popup := -1
var _prev_art: Texture2D = null
var _art_t := 10.0
var _locked_t := -1.0
var _champ_anim := 0.0


func _ready() -> void:
	super._ready()
	var pool: Array = ChampionDB.ROSTER.duplicate()
	pool.shuffle()
	team = pool.slice(0, 5)
	bench = pool.slice(5)
	bench.sort()
	if G.next_match.has("player_summoners"):
		summoners = G.next_match.player_summoners.duplicate()
	Sfx.music("music-cs-draft-pick-base-layer-01", 1.5, ["music-cs-draft-pick-intensity-layer-01"])
	Sfx.ui("pick_intro")
	_on_champ_changed(false)


func me() -> String:
	return team[0]


func _process(delta: float) -> void:
	super._process(delta)
	_art_t += delta
	_champ_anim = minf(1.0, _champ_anim + delta * 3.0)
	if _locked_t >= 0.0:
		_locked_t += delta
		if _locked_t > 1.1:
			_locked_t = -100.0
			super.on_action("locked")


func _set_me(alias: String) -> void:
	_prev_art = Assets.champion_art(me(), 0, "splash")
	_art_t = 0.0
	team[0] = alias
	_on_champ_changed(true)


func _on_champ_changed(voice: bool) -> void:
	_champ_anim = 0.0
	if voice:
		Sfx.champ(me(), "choose_vo", -2.0)


# ===================================================================== draw
func draw_screen(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	var art := Assets.champion_art(me(), 0, "splash")
	var zoom := 1.04 + 0.02 * sin(t * 0.2)
	var ar := Rect2(vs * 0.5 - vs * zoom * 0.5, vs * zoom)
	if _prev_art != null and _art_t < 0.6:
		tex_cover(_prev_art, ar, Color(1, 1, 1, 0.55))
	tex_cover(art, ar, Color(1, 1, 1, 0.55 * clampf(_art_t / 0.6, 0.0, 1.0)), Vector2(0.6, 0.3))
	vignette(vs, 0.85)
	_vgrad(Rect2(0, vs.y * 0.55, vs.x, vs.y * 0.45), Color(0, 0.02, 0.04, 0.0), Color(0, 0.02, 0.04, 0.85))
	# header
	text_center("ARAM: MAYHEM  ·  HOWLING ABYSS", Vector2(vs.x * 0.5, 34), 15, C_GOLD, f_bold, false, 2.0)
	text_center("CHOOSE YOUR CHAMPION", Vector2(vs.x * 0.5, 72), 34, C_TEXT, f_bold, true, 4.0)
	_draw_bench(vs)
	_draw_team(vs)
	_draw_center(vs)
	_draw_right(vs)
	button("back", Rect2(36, vs.y - 70, 140, 42), "Back", "normal", _locked_t < 0.0, 16)
	if _sum_popup >= 0:
		_draw_sum_popup(vs)
	if _locked_t >= 0.0:
		var k := clampf(_locked_t / 0.5, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.6, 0.9, 1.0, 0.25 * (1.0 - k)))


func _draw_bench(vs: Vector2) -> void:
	var sz := 64.0
	var gap := 10.0
	var w := bench.size() * (sz + gap) - gap
	var x0 := vs.x * 0.5 - w * 0.5
	var y := 110.0
	text_center("BENCH  —  click to swap", Vector2(vs.x * 0.5, y + 4), 13, C_DIM, f_semi, false, 1.5)
	for i in bench.size():
		var a: String = bench[i]
		var r := Rect2(x0 + i * (sz + gap), y + 20, sz, sz)
		var id := "bench:" + a
		hit_area(id, r)
		var hov := is_hover(id)
		var rr := r.grow(3.0 if hov else 0.0)
		icon(Assets.champion_square(a), rr, C_GOLD if hov else C_GOLD_DARK)
		set_tip(id, ChampionDB.client_data(a).get("name", a), ChampionDB.display_title(a) + "\nRoles: " + ", ".join(ChampionDB.roles(a)))


func _draw_team(vs: Vector2) -> void:
	var x := 36.0
	var y := 200.0
	text("YOUR TEAM", Vector2(x, y - 14), 16, C_GOLD, f_bold)
	for i in 5:
		var a: String = team[i]
		var r := Rect2(x, y + i * 112, 380, 100)
		var mine := i == 0
		frame(r, Color(0.02, 0.08, 0.12, 0.85) if not mine else Color(0.05, 0.12, 0.16, 0.92), C_GOLD_DARK)
		if mine:
			ornate_frame(r, C_GOLD.lerp(C_GOLD_BRIGHT, 0.5 + 0.5 * sin(t * 2.5)), 2.0)
		var tr := Rect2(r.position + Vector2(8, 8), Vector2(84, 84))
		tex_cover(Assets.champion_art(a, 0, "tile"), tr)
		draw_rect(tr, C_GOLD_DARK, false, 1.5)
		var nm: String = ChampionDB.client_data(a).get("name", a)
		text(nm, r.position + Vector2(106, 40), 22, C_GOLD_BRIGHT if mine else C_TEXT, f_bold)
		text("You" if mine else "Bot", r.position + Vector2(106, 66), 15, C_TEAL if mine else C_DIM, f_semi)
		text(ChampionDB.display_title(a), r.position + Vector2(106, 86), 13, C_DIM.darkened(0.15), f_body)
		if not mine and _locked_t < 0.0:
			var br := Rect2(r.end.x - 92, r.position.y + 30, 80, 38)
			hit_area("trade:%d" % i, r)
			if is_hover("trade:%d" % i):
				button("trade:%d" % i, br, "Trade", "normal", true, 15)
				set_tip("trade:%d" % i, "Trade with " + nm, "Swap champions with this bot. Bots always accept.")


func _draw_center(vs: Vector2) -> void:
	var a := me()
	var cd := ChampionDB.client_data(a)
	var cx := vs.x * 0.5
	var y := vs.y - 330.0
	var k := _champ_anim
	var off := (1.0 - k) * 20.0
	var col := Color(C_GOLD_BRIGHT.r, C_GOLD_BRIGHT.g, C_GOLD_BRIGHT.b, k)
	text_center(str(cd.get("name", a)).to_upper(), Vector2(cx, y + off), 64, col, f_heavy, true, 6.0)
	text_center(ChampionDB.display_title(a), Vector2(cx, y + 52 + off), 22, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, k), f_semi, true)
	var roles := ChampionDB.roles(a)
	var rw := 120.0
	var rx := cx - roles.size() * rw * 0.5
	for i in roles.size():
		var rr := Rect2(rx + i * rw + 6, y + 80, rw - 12, 26)
		frame(rr, Color(0.03, 0.08, 0.1, 0.8), C_GOLD_DARK)
		text_center(str(roles[i]).to_upper(), rr.get_center(), 13, C_GOLD, f_bold, false, 1.5)
	# abilities
	var keys := ["P", "Q", "W", "E", "R"]
	var spells: Array = cd.get("spells", [])
	var isz := 60.0
	var ax := cx - (isz * 5 + 14 * 4) * 0.5
	var ay := y + 130
	for i in 5:
		var r := Rect2(ax + i * (isz + 14), ay, isz, isz)
		var id := "ab:%d" % i
		hit_area(id, r)
		icon(Assets.ability_icon(a, keys[i].to_lower()), r, C_GOLD if is_hover(id) else C_GOLD_DARK)
		text_center(keys[i], Vector2(r.get_center().x, r.end.y + 14), 14, C_GOLD, f_bold)
		var nm := ""
		var desc := ""
		if i == 0:
			var p: Dictionary = cd.get("passive", {})
			nm = str(p.get("name", "Passive"))
			desc = str(p.get("description", ""))
		elif i - 1 < spells.size():
			nm = str(spells[i - 1].get("name", ""))
			desc = str(spells[i - 1].get("description", ""))
		set_tip(id, "%s  [%s]" % [nm, keys[i]], Hud._clean(desc))


func _draw_right(vs: Vector2) -> void:
	var w := 380.0
	var x := vs.x - w - 36.0
	var y := 200.0
	var cd := ChampionDB.client_data(me())
	# playstyle
	var ps: Dictionary = cd.get("playstyleInfo", {})
	frame(Rect2(x, y - 30, w, 210), Color(0.02, 0.07, 0.1, 0.85), C_GOLD_DARK)
	text("PLAYSTYLE", Vector2(x + 18, y - 4), 16, C_GOLD, f_bold)
	var labels := [["damage", "Damage"], ["durability", "Toughness"], ["crowdControl", "Control"], ["mobility", "Mobility"], ["utility", "Utility"]]
	for i in labels.size():
		var v := int(ps.get(labels[i][0], 0))
		var ly := y + 22 + i * 30
		text(labels[i][1], Vector2(x + 18, ly + 14), 15, C_TEXT, f_semi)
		for s in 3:
			var br := Rect2(x + 150 + s * 70, ly + 2, 62, 14)
			draw_rect(br, C_TEAL if s < v else Color(0.1, 0.13, 0.15))
	# summoners
	y += 220
	frame(Rect2(x, y, w, 128), Color(0.02, 0.07, 0.1, 0.85), C_GOLD_DARK)
	text("SUMMONER SPELLS", Vector2(x + 18, y + 26), 16, C_GOLD, f_bold)
	for i in 2:
		var r := Rect2(x + 18 + i * 92, y + 40, 72, 72)
		var id := "sum:%d" % i
		hit_area(id, r)
		icon(Assets.summoner_icon(str(summoners[i]).to_lower()), r, C_GOLD if is_hover(id) else C_GOLD_DARK)
		text_center("DF"[i], Vector2(r.end.x - 9, r.end.y - 9), 14, C_TEXT, f_bold, true)
		set_tip(id, str(summoners[i]), "Click to change.")
	text("Click to change", Vector2(x + 210, y + 84), 14, C_DIM, f_body)
	# difficulty
	y += 142
	frame(Rect2(x, y, w, 92), Color(0.02, 0.07, 0.1, 0.85), C_GOLD_DARK)
	text("BOT DIFFICULTY", Vector2(x + 18, y + 26), 16, C_GOLD, f_bold)
	var pw := (w - 36) / 4.0
	for i in 4:
		pill("set:diff:%d" % i, Rect2(x + 18 + i * pw, y + 42, pw - 6, 34), DIFFS[i], int(G.settings.difficulty) == i, 15)
	# reroll + lock
	var by := vs.y - 180.0
	button("reroll", Rect2(x, by, w, 50), "Reroll  (%d left)" % rerolls, "normal", rerolls > 0 and _locked_t < 0.0, 18)
	set_tip("reroll", "Reroll", "Trade your champion for a random one from the bench. Your current champion goes to the bench.")
	button("lock", Rect2(x, by + 66, w, 72), "Lock In", "primary", _locked_t < 0.0, 28)


func _draw_sum_popup(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.55))
	hit_area("sum_close", Rect2(Vector2.ZERO, vs))
	var n := Summoners.ALL.size()
	var cols := 4
	var sz := 80.0
	var w := cols * (sz + 16) + 32
	var h: float = ceil(n / float(cols)) * (sz + 40) + 80
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5, Vector2(w, h))
	frame(r, Color(0.01, 0.05, 0.08, 0.98), C_GOLD)
	hit_area("~popup", r)
	text_center("CHOOSE SUMMONER SPELL (%s)" % "DF"[_sum_popup], Vector2(r.get_center().x, r.position.y + 30), 18, C_GOLD_BRIGHT, f_bold)
	for i in n:
		var nm: String = Summoners.ALL[i]
		var cr := Rect2(r.position.x + 24 + (i % cols) * (sz + 16), r.position.y + 60 + (i / cols) * (sz + 40), sz, sz)
		var id := "pick_sum:" + nm
		hit_area(id, cr)
		var sel: bool = summoners[_sum_popup] == nm
		icon(Assets.summoner_icon(nm.to_lower()), cr, C_GOLD_BRIGHT if sel or is_hover(id) else C_GOLD_DARK)
		text_center(nm, Vector2(cr.get_center().x, cr.end.y + 16), 14, C_TEXT if not sel else C_GOLD_BRIGHT, f_semi)
		var sp = Summoners.make(nm, null)
		if sp != null:
			set_tip(id, nm, "%s\nCooldown: %ds" % [sp.description, int(sp.cooldowns[0]) if not sp.cooldowns.is_empty() else 0])


# ===================================================================== actions
func on_action(id: String) -> void:
	if _locked_t >= 0.0:
		return
	if handle_settings_action(id):
		return
	if id.begins_with("bench:"):
		var a := id.substr(6)
		var i := bench.find(a)
		if i >= 0:
			bench[i] = me()
			bench.sort()
			_set_me(a)
			Sfx.ui("swap")
	elif id.begins_with("trade:"):
		var i := int(id.substr(6))
		var a: String = team[i]
		team[i] = me()
		_set_me(a)
		Sfx.ui("swap")
	elif id == "reroll" and rerolls > 0:
		rerolls -= 1
		var a: String = bench[G.rng.randi() % bench.size()]
		bench[bench.find(a)] = me()
		bench.sort()
		_set_me(a)
		Sfx.ui("reroll")
	elif id.begins_with("sum:"):
		_sum_popup = int(id.substr(4))
		Sfx.ui("spells_open")
	elif id.begins_with("pick_sum:"):
		var nm := id.substr(9)
		var other := 1 - _sum_popup
		if summoners[other] == nm:
			summoners[other] = summoners[_sum_popup]
		summoners[_sum_popup] = nm
		_sum_popup = -1
	elif id == "sum_close":
		_sum_popup = -1
	elif id == "lock":
		var enemies := bench.duplicate()
		enemies.shuffle()
		cfg = {
			"player_champion": me(),
			"player_skin": 0,
			"ally_champions": team.slice(1),
			"enemy_champions": enemies.slice(0, 5),
			"player_summoners": summoners.duplicate(),
			"seed": G.rng.randi(),
		}
		G.next_match = cfg.duplicate(true)
		_locked_t = 0.0
		Sfx.ui("lockin")
		Sfx.ui("lock_confirm")
		Sfx.champ(me(), "choose_vo", 0.0)
	elif id == "back":
		super.on_action("back")
