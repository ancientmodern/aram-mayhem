class_name ChampSelect
extends UIScreen
## ARAM champion select: a random champion, 2 rerolls, a shared bench to swap with,
## trades with allied bots, summoner spells and bot difficulty. Emits action("locked") / action("back").
## Styled after the League client's champ select (summoner objects, dice reroll, trapezoid lock-in art).

var team: Array = []            ## 5 aliases, [0] = player
var bench: Array = []
var rerolls := 2
var summoners := ["Flash", "Mark"]
var cfg := {}                   ## filled on lock-in
var _sum_popup := -1
var _sum_k := 0.0               ## popup open animation 0..1
var _prev_art: Texture2D = null
var _art_t := 10.0
var _locked_t := -1.0
var _champ_anim := 0.0
var _swap_t := {}               ## alias -> time of last swap-in (tile pop animation)
var _timer := 60.0              ## champion select countdown; at 0 the pick is locked automatically (League)
var _last_tick := 99
const TIMER_START := 60.0


func _ready() -> void:
	super._ready()
	var pool: Array = ChampionDB.ROSTER.duplicate()
	pool.shuffle()
	team = pool.slice(0, 5)
	bench = pool.slice(5)
	bench.sort()
	if G.next_match.has("player_summoners"):
		summoners = G.next_match.player_summoners.duplicate()
	var aram_music := Sfx.game_music("map12", "mus_map12_phase_select")
	if aram_music != "":
		Sfx.music(aram_music, 1.5)
	else:
		Sfx.music("music-cs-draft-pick-base-layer-01", 1.5, ["music-cs-draft-pick-intensity-layer-01"])
	Sfx.ui("pick_intro")
	_timer = TIMER_START
	_on_champ_changed(false)


func me() -> String:
	return team[0]


func _process(delta: float) -> void:
	super._process(delta)
	_art_t += delta
	_champ_anim = minf(1.0, _champ_anim + delta * 3.0)
	_sum_k = move_toward(_sum_k, 1.0 if _sum_popup >= 0 else 0.0, delta * 7.0)
	if _locked_t < 0.0 and _fade_done():
		_timer = maxf(0.0, _timer - delta)
		var sec := int(ceil(_timer))
		if sec != _last_tick:
			_last_tick = sec
			if sec <= 10 and sec > 0:
				Sfx.ui("countdown")
			elif sec == 0 and _timer <= 0.0:
				on_action("lock")   # time ran out: lock in the current champion like the client does
	if _locked_t >= 0.0:
		_locked_t += delta
		if _locked_t > 1.1:
			_locked_t = -100.0
			super.on_action("locked")


func _fade_done() -> bool:
	return fade >= 1.0


func _set_me(alias: String) -> void:
	_prev_art = Assets.champion_art(me(), 0, "splash")
	_art_t = 0.0
	team[0] = alias
	_swap_t[alias] = t
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
		tex_cover(_prev_art, ar, Color(1, 1, 1, 0.6))
	tex_cover(art, ar, Color(1, 1, 1, 0.6 * clampf(_art_t / 0.6, 0.0, 1.0)), Vector2(0.6, 0.3))
	smoke(vs, 0.07, 6.0)
	vignette(vs, 0.88)
	_vgrad(Rect2(0, vs.y * 0.52, vs.x, vs.y * 0.48), Color(0.004, 0.039, 0.075, 0.0), Color(0.004, 0.039, 0.075, 0.9))
	var top := ctex("lol-champ-select/images/top-darkening.png")
	if top != null:
		draw_texture_rect(top, Rect2(0, 0, vs.x, 150), false, Color(1, 1, 1, 0.9))
	# header
	var ha := appear(0.0)
	_draw_timer(Vector2(vs.x * 0.5, 62.0 - (1.0 - ha) * 10.0), ha)
	label("ARAM: Mayhem  ·  Howling Abyss", Vector2(vs.x * 0.5, 126 - (1.0 - ha) * 10), "sub", 1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ha), 18.0)
	label("Choose your champion", Vector2(vs.x * 0.5, 168 - (1.0 - ha) * 10), "h2", 1, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, ha), 42.0, true)
	divider(vs.x * 0.5, 204, 520.0 * ha, ha)
	_draw_bench(vs)
	_draw_team(vs)
	_draw_center(vs)
	_draw_right(vs)
	button("back", Rect2(44, vs.y - 92, 190, 58), "Back", "normal", _locked_t < 0.0, 22, "back")
	if _sum_k > 0.001:
		_draw_sum_popup(vs)
	if _locked_t >= 0.0:
		var k := clampf(_locked_t / 0.5, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.75, 0.95, 1.0, 0.3 * (1.0 - k)))
		# expanding ring from the lock-in button
		var rc := Vector2(vs.x - 36 - 190, vs.y - 120)
		draw_arc(rc, 40 + 520 * k, 0, TAU, 96, Color(0.5, 0.95, 1.0, 0.7 * (1.0 - k)), 4.0 * (1.0 - k) + 1.0, true)


## League's champ-select countdown: ring that drains over the phase with the remaining seconds in the middle.
func _draw_timer(c: Vector2, a: float) -> void:
	var frac := _timer / TIMER_START
	var urgent := _timer <= 10.0
	var col := Color(0.96, 0.4, 0.35) if urgent else C_GOLD
	if urgent:
		col = col.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(t * 8.0)))
	draw_circle(c, 36, Color(0.004, 0.039, 0.075, 0.85 * a))
	draw_arc(c, 36, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, Color(col.r, col.g, col.b, a), 4.0, true)
	draw_arc(c, 36, 0, TAU, 48, Color(0.78, 0.67, 0.43, 0.25 * a), 1.5, true)
	var sec := int(ceil(_timer))
	label("%d:%02d" % [sec / 60, sec % 60] if sec >= 60 else str(sec), c, "num", 1, Color(col.r, col.g, col.b, a).lerp(Color(1, 1, 1, a), 0.4), 28.0 if sec < 60 else 22.0)


func _draw_bench(vs: Vector2) -> void:
	var sz := 84.0
	var gap := 12.0
	var w := bench.size() * (sz + gap) - gap
	var x0 := vs.x * 0.5 - w * 0.5
	var y := 232.0
	var ba := appear(0.1)
	label("Bench  —  click to swap", Vector2(vs.x * 0.5, y), "sub", 1, Color(C_DIM.r, C_DIM.g, C_DIM.b, ba), 17.0)
	for i in bench.size():
		var a: String = bench[i]
		var ka := appear(0.12 + i * 0.03)
		var r := Rect2(x0 + i * (sz + gap), y + 22 + (1.0 - ka) * 14.0, sz, sz)
		var id := "bench:" + a
		hit_area(id, r, "grid_hover|")
		var h := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		var pop: float = maxf(0.0, 1.0 - (t - float(_swap_t.get(a, -10.0))) / 0.5)
		var rr := r.grow(5.0 * h + 4.0 * pop)
		if h > 0.0 or pop > 0.0:
			glow(rr, Color(0.9, 0.78, 0.45, 0.35 * maxf(h, pop)), 12)
		var tx := Assets.champion_square(a)
		icon(tx, rr, C_GOLD if h > 0.3 else C_GOLD_DARK, Color(1, 1, 1, ka * (0.8 + 0.2 * h)))
		set_tip(id, ChampionDB.client_data(a).get("name", a), ChampionDB.display_title(a) + "\nRoles: " + ", ".join(ChampionDB.roles(a)))


func _draw_team(vs: Vector2) -> void:
	var x := 48.0
	var y := 262.0
	label("Your team", Vector2(x + 4, y - 22), "h5", 0, C_GOLD, 20.0)
	for i in 5:
		var a: String = team[i]
		var ka := appear(0.15 + i * 0.07)
		var r := Rect2(x - (1.0 - ka) * 60.0, y + i * 116, 440, 104)
		var mine := i == 0
		var id := "trade:%d" % i
		var hov := (not mine) and is_hover(id) and _locked_t < 0.0
		var h := ease_to(id, "h", 1.0 if hov else 0.0, 12.0)
		# summoner-object plate
		var fill_a := 0.88 * ka
		vgrad_stops(r, [[0.0, Color(0.035, 0.078, 0.157, fill_a)], [1.0, Color(0.004, 0.039, 0.075, fill_a)]])
		if mine:
			var pulse := 0.5 + 0.5 * sin(t * 2.5)
			glow(r, Color(0.78, 0.67, 0.43, 0.18 + 0.12 * pulse), 12)
			grad_border(r, 3.0, [[0.0, Color("785a28")], [0.55, Color("c89b3c")], [1.0, Color("f0e6d2")]], ka)
			_hgrad(Rect2(r.position, Vector2(r.size.x, r.size.y)), Color(0.78, 0.67, 0.43, 0.10), Color(0.78, 0.67, 0.43, 0.0))
		else:
			grad_border(r, 2.0, [[0.0, Color("463714")], [1.0, Color("785a28").lerp(Color("c8aa6e"), h)]], ka)
			if h > 0.0:
				glow(r, Color(0.78, 0.67, 0.43, 0.2 * h), 10)
		var tr := Rect2(r.position + Vector2(10, 10), Vector2(84, 84))
		draw_rect(tr.grow(2), Color(0, 0, 0, 0.6 * ka))
		tex_cover(Assets.champion_art(a, 0, "tile"), tr, Color(1, 1, 1, ka))
		grad_border(tr, 2.0, [[0.0, Color("785a28")], [1.0, Color("c8aa6e")]] if mine else [[0.0, Color("463714")], [1.0, Color("785a28")]], ka)
		var nm: String = ChampionDB.client_data(a).get("name", a)
		label(nm, r.position + Vector2(112, 32), "h4", 0, C_GOLD_BRIGHT if mine else C_TEXT, 27.0, false, 0.0, 200.0)
		label("You" if mine else "%s Bot" % nm, r.position + Vector2(112, 62), "label", 0, C_TEAL if mine else C_DIM, 18.0)
		label(ChampionDB.display_title(a), r.position + Vector2(112, 86), "body", 0, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.85 * (1.0 - h)), 17.0, false, 0.0, 220.0)
		# summoner spells
		var sp: Array = summoners if mine else ["Flash", "Mark"]
		for s in 2:
			var ir := Rect2(r.end.x - 74 + 0.0, r.position.y + 12 + s * 40, 34, 34)
			icon(Assets.summoner_icon(str(sp[s]).to_lower()), ir, C_GOLD_DARK, Color(1, 1, 1, ka))
		if not mine and _locked_t < 0.0:
			hit_area(id, r, "grid_hover|")
			if h > 0.01:
				# hover: gold wash over the plate + "click to trade" hint next to the role line
				_hgrad(r, Color(0.78, 0.67, 0.43, 0.16 * h), Color(0.78, 0.67, 0.43, 0.0))
				label("Click to trade", r.position + Vector2(112, 86), "label", 0, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, h), 17.0)
			set_tip(id, "Trade with " + nm, "Swap champions with this bot. Bots always accept.")
		elif mine:
			# pointer wedge like the client's local-player marker
			draw_colored_polygon(PackedVector2Array([Vector2(r.end.x + 6, r.get_center().y - 10), Vector2(r.end.x + 18, r.get_center().y), Vector2(r.end.x + 6, r.get_center().y + 10)]), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ka))


func _draw_center(vs: Vector2) -> void:
	var a := me()
	var cd := ChampionDB.client_data(a)
	var cx := vs.x * 0.5
	var y := vs.y - 352.0
	var k := _champ_anim
	var off := (1.0 - k) * 24.0
	var lock_pop := 0.0
	if _locked_t >= 0.0:
		lock_pop = sin(clampf(_locked_t / 0.5, 0.0, 1.0) * PI) * 0.06
	var nm := str(cd.get("name", a))
	grad_text("cs_name", nm, Rect2(cx - 520, y - 62 + off, 1040, 124), int(104 * (1.0 + lock_pop)), "Heavy", 0.09, 1,
			k * (1.0 - clampf(_sum_k * 4.0, 0.0, 1.0)), fmod(t, 6.0) / 1.5 if fmod(t, 6.0) < 1.5 else -1.0, [], 5)
	label(ChampionDB.display_title(a), Vector2(cx, y + 62 + off), "h4", 1, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, k), 28.0, true)
	var roles := ChampionDB.roles(a)
	var rw := 150.0
	var rx := cx - roles.size() * rw * 0.5
	for i in roles.size():
		var rr := Rect2(rx + i * rw + 8, y + 94 + off, rw - 16, 34)
		draw_rect(rr, Color(0.004, 0.039, 0.075, 0.75 * k))
		grad_border(rr, 1.5, [[0.0, Color("463714")], [1.0, Color("785a28")]], k)
		label(str(roles[i]), rr.get_center(), "h6", 1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, k), 17.0)
	# abilities
	var keys := ["P", "Q", "W", "E", "R"]
	var spells: Array = cd.get("spells", [])
	var isz := 72.0
	var gapx := 18.0
	var ax := cx - (isz * 5 + gapx * 4) * 0.5
	var ay := y + 154
	for i in 5:
		var r := Rect2(ax + i * (isz + gapx), ay, isz, isz)
		var id := "ab:%d" % i
		hit_area(id, r, "grid_hover|")
		var h := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		if h > 0.0:
			glow(r, Color(0.9, 0.78, 0.45, 0.3 * h), 10)
		icon(Assets.ability_icon(a, keys[i].to_lower()), r.grow(2.0 * h), C_GOLD if h > 0.3 else C_GOLD_DARK)
		# key badge
		var br := Rect2(r.get_center().x - 14, r.end.y + 6, 28, 24)
		label(keys[i], br.get_center(), "h5", 1, C_GOLD.lerp(C_GOLD_BRIGHT, h), 20.0)
		var nm2 := ""
		var desc := ""
		if i == 0:
			var p: Dictionary = cd.get("passive", {})
			nm2 = str(p.get("name", "Passive"))
			desc = str(p.get("description", ""))
		elif i - 1 < spells.size():
			nm2 = str(spells[i - 1].get("name", ""))
			desc = str(spells[i - 1].get("description", ""))
		set_tip(id, "%s  [%s]" % [nm2, keys[i]], Hud._clean(desc))


func _draw_right(vs: Vector2) -> void:
	var w := 440.0
	var x := vs.x - w - 48.0
	var y := 262.0
	var cd := ChampionDB.client_data(me())
	var ka := appear(0.25)
	x += (1.0 - ka) * 60.0
	# playstyle plate
	var ps: Dictionary = cd.get("playstyleInfo", {})
	var pr := Rect2(x, y - 34, w, 250)
	panel(pr, 0.9 * ka, 2.0, false)
	label("Playstyle", Vector2(x + 24, y - 4), "h5", 0, C_GOLD, 20.0)
	var labels := [["damage", "Damage"], ["durability", "Toughness"], ["crowdControl", "Control"], ["mobility", "Mobility"], ["utility", "Utility"]]
	for i in labels.size():
		var v := int(ps.get(labels[i][0], 0))
		var ly := y + 30 + i * 38
		label(labels[i][1], Vector2(x + 24, ly + 12), "label", 0, C_TEXT, 19.0)
		for s in 3:
			var br := Rect2(x + 178 + s * 80, ly + 3, 72, 17)
			if s < v:
				_hgrad(br, Color("785a28"), Color("c8aa6e"))
				draw_rect(Rect2(br.position, Vector2(br.size.x, 2)), Color(1, 1, 1, 0.2))
			else:
				draw_rect(br, Color(0.07, 0.09, 0.11))
			grad_border(br, 1.0, [[0.0, Color("463714")], [1.0, Color("5c4a24")]])
	# summoners
	y += 244
	var sr := Rect2(x, y, w, 150)
	panel(sr, 0.9 * ka, 2.0, false)
	label("Summoner spells", Vector2(x + 24, y + 30), "h5", 0, C_GOLD, 20.0)
	for i in 2:
		var r := Rect2(x + 24 + i * 100, y + 52, 80, 80)
		var id := "sum:%d" % i
		hit_area(id, r, "grid_hover|")
		var h := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		if h > 0.0:
			glow(r, Color(0.9, 0.78, 0.45, 0.3 * h), 10)
		icon(Assets.summoner_icon(str(summoners[i]).to_lower()), r.grow(2.0 * h), C_GOLD if h > 0.3 else C_GOLD_DARK)
		label("DF"[i], Vector2(r.end.x - 11, r.end.y - 11), "h6", 1, C_TEXT, 17.0, true)
		set_tip(id, str(summoners[i]), "Click to change.")
	label("Click to change", Vector2(x + 236, y + 96), "body_l", 0, C_DIM, 18.0)
	# difficulty
	y += 164
	var dr := Rect2(x, y, w, 112)
	panel(dr, 0.9 * ka, 2.0, false)
	label("Bot difficulty", Vector2(x + 24, y + 30), "h5", 0, C_GOLD, 20.0)
	radio_row("set:diff:", Rect2(x + 22, y + 52, w - 44, 44), DIFFS, int(G.settings.difficulty), 19.0)
	# reroll (dice) + lock in
	var bx := x
	var by := vs.y - 214.0
	_reroll_button(Rect2(bx + 6, by + 18, 150, 100))
	_lockin_button(Rect2(bx + 160, by, w - 160, 140))


func _reroll_button(r: Rect2) -> void:
	var en := rerolls > 0 and _locked_t < 0.0
	if en:
		hit_area("reroll", r, "reroll")
	var s := _bs("reroll")
	var hov := en and hover_id == "reroll"
	var down := hov and press_id == "reroll"
	s.hov = move_toward(s.hov, 1.0 if hov else 0.0, _dt * 8.0)
	var tx := ctex("lol-champ-select/images/config/dice-disable.png") if not en else (ctex("lol-champ-select/images/config/dice-click.png") if down else (ctex("lol-champ-select/images/config/dice-hover.png") if hov else ctex("lol-champ-select/images/config/dice.png")))
	var wob := 0.0
	if s.click_t >= 0.0 and s.click_t < 0.6:
		wob = sin(s.click_t * 22.0) * 0.12 * (1.0 - s.click_t / 0.6)
	var c := r.get_center() + Vector2(0, -8)
	if tx != null:
		var ds := tx.get_size() * 1.05
		draw_set_transform(c, wob, Vector2.ONE * (1.0 + 0.06 * s.hov))
		draw_texture_rect(tx, Rect2(-ds * 0.5, ds), false, Color(1, 1, 1, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hov:
		glow(Rect2(c - Vector2(30, 24), Vector2(60, 48)), Color(0.55, 0.9, 1.0, 0.22), 14)
	# counter badge
	var bc := Vector2(r.end.x - 6, r.position.y + 6)
	draw_circle(bc, 19, Color(0.004, 0.039, 0.075, 0.95))
	draw_arc(bc, 19, 0, TAU, 32, C_GOLD if en else C_DISABLED, 2.0, true)
	label(str(rerolls), bc, "num", 1, C_GOLD_BRIGHT if en else C_DISABLED, 24.0)
	label("Reroll", Vector2(r.get_center().x, r.end.y + 12), "h6", 1, (C_BTN.lerp(C_TEXT, s.hov)) if en else C_DISABLED, 19.0)
	set_tip("reroll", "Reroll", "Trade your champion for a random one from the bench. Your current champion goes to the bench.")


func _lockin_button(r: Rect2) -> void:
	var en := _locked_t < 0.0
	if en:
		hit_area("lock", r, "lockin")
	var s := _bs("lock")
	var hov := en and hover_id == "lock"
	var down := hov and press_id == "lock"
	s.hov = move_toward(s.hov, 1.0 if hov else 0.0, _dt * 7.0)
	var base := ctex("lol-champ-select/images/action-button/button-lockin.png")
	var over := ctex("lol-champ-select/images/action-button/button-lockin-hover.png")
	var clk := ctex("lol-champ-select/images/action-button/button-lockin-click.png")
	var dis := ctex("lol-champ-select/images/action-button/button-lockin-disable.png")
	var rr := r
	if down:
		rr = Rect2(r.get_center() - r.size * 0.97 * 0.5, r.size * 0.97)
	if not en:
		draw_texture_rect(dis if _locked_t < 0.0 else clk, rr, false)
		if _locked_t >= 0.0:
			draw_texture_rect(over, rr, false, Color(1, 1, 1, 0.8))
	elif down:
		draw_texture_rect(clk, rr, false)
	else:
		draw_texture_rect(base, rr, false)
		if s.hov > 0.0:
			draw_texture_rect(over, rr, false, Color(1, 1, 1, s.hov))
	var tc := Color("cdfafa").lerp(Color.WHITE, s.hov)
	if _locked_t >= 0.0:
		tc = Color("e8ffff")
	label("Lock in" if _locked_t < 0.0 else "Locked", rr.get_center() + Vector2(0, -rr.size.y * 0.06), "btn", 1, tc, 46.0, true)


func _draw_sum_popup(vs: Vector2) -> void:
	var ez := 1.0 - pow(1.0 - _sum_k, 3.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03, 0.62 * ez))
	if _sum_popup < 0:
		return
	hit_area("sum_close", Rect2(Vector2.ZERO, vs), "silent")
	var n := Summoners.ALL.size()
	var cols := 4
	var sz := 96.0
	var cw := sz + 32.0
	var w := cols * cw + 64
	var h: float = ceil(n / float(cols)) * (sz + 56) + 130
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - ez) * 24.0), Vector2(w, h))
	panel(r, 0.98)
	hit_area("~popup", r, "silent")
	label("Choose summoner spell  (%s)" % "DF"[_sum_popup], Vector2(r.get_center().x, r.position.y + 48), "h4", 1, C_GOLD_BRIGHT, 28.0)
	divider(r.get_center().x, r.position.y + 82, r.size.x * 0.6)
	for i in n:
		var nm: String = Summoners.ALL[i]
		var cr := Rect2(r.position.x + 32 + (i % cols) * cw + 8, r.position.y + 112 + (i / cols) * (sz + 56), sz, sz)
		var id := "pick_sum:" + nm
		hit_area(id, cr, "grid")
		var sel: bool = summoners[_sum_popup] == nm
		var hh := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		if sel or hh > 0.0:
			glow(cr, Color(0.9, 0.78, 0.45, 0.3 * maxf(hh, 1.0 if sel else 0.0)), 12)
		icon(Assets.summoner_icon(nm.to_lower()), cr.grow(3.0 * hh), C_GOLD if sel or hh > 0.3 else C_GOLD_DARK)
		label(nm, Vector2(cr.get_center().x, cr.end.y + 24), "label", 1, C_GOLD_BRIGHT if sel else C_TEXT.lerp(C_GOLD_BRIGHT, hh), 19.0)
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
			Sfx.ui("bench")
	elif id.begins_with("trade:"):
		var i := int(id.substr(6))
		var a: String = team[i]
		team[i] = me()
		_swap_t[team[i]] = t
		_set_me(a)
		Sfx.ui("swap")
		Sfx.ui("swap_accepted")
	elif id == "reroll" and rerolls > 0:
		rerolls -= 1
		var a: String = bench[G.rng.randi() % bench.size()]
		bench[bench.find(a)] = me()
		bench.sort()
		_set_me(a)
		get_tree().create_timer(0.35).timeout.connect(func(): Sfx.ui("bench"))
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
		Sfx.ui("flyout_close")
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
		Sfx.ui("lock_confirm")
		Sfx.champ(me(), "choose_vo", 0.0)
		get_tree().create_timer(0.55).timeout.connect(func(): Sfx.ui("lock_done"))
	elif id == "back":
		super.on_action("back")
