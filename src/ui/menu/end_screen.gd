class_name EndScreen
extends UIScreen
## End of game: slow-motion nexus explosion, VICTORY / DEFEAT banner, then the post-game scoreboard.
## Emits action("replay") / action("menu").

var match_ref = null
var victory := true
var _phase := 0               ## 0 = watching nexus, 1 = banner, 2 = stats
var _stats_t := 0.0
var _mvp = null
const BANNER_AT := 2.4


func _ready() -> void:
	super._ready()
	fade = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	victory = G.player != null and match_ref.winner == G.player.team
	_mvp = _find_mvp()


func _process(delta: float) -> void:
	super._process(delta)
	# runs on real time (the match is in slow motion)
	if _phase == 0 and t >= BANNER_AT:
		_phase = 1
		mouse_filter = Control.MOUSE_FILTER_STOP
		Sfx.ui("victory" if victory else "defeat")
		Sfx.ui("eog")
		G.announcer_event.emit("victory" if victory else "defeat", victory)
		var mus := Sfx.game_music("map12", "mus_map12_victory" if victory else "mus_map12_defeat")
		if mus != "":
			Sfx.music(mus, 0.5, [], false)
	if _phase == 2:
		_stats_t += delta / maxf(Engine.time_scale, 0.001)


func _find_mvp():
	var best = null
	var bs := -INF
	for c in match_ref.champions:
		var s: float = c.kills * 3.0 + c.assists * 1.5 - c.deaths * 1.5 + c.champion_damage_total / 1500.0 + c.cs * 0.02
		if s > bs and (c.kills + c.assists) > 0 and c.team == match_ref.winner:
			bs = s
			best = c
	return best


func draw_screen(vs: Vector2) -> void:
	if _phase == 0:
		return
	var k := clampf((t - BANNER_AT) / 0.5, 0.0, 1.0)
	if _phase == 1:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.5 * k))
		_draw_banner(vs, vs * Vector2(0.5, 0.42), k)
		if t > BANNER_AT + 1.4:
			var bk := appear(BANNER_AT + 1.4, 0.4)
			button("continue", Rect2(vs.x * 0.5 - 170, vs.y * 0.76 + (1.0 - bk) * 20.0, 340, 70), "Continue", "primary", true, 28)
	else:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.004, 0.039, 0.075, 0.9))
		smoke(vs, 0.08, 6.0)
		_draw_stats(vs)


func _team_tint() -> Array:
	return [Color("fff4cf"), Color("f0c25a"), Color("a8741e")] if victory else [Color("ffd9d2"), Color("e8574d"), Color("8e1c1c")]


func _draw_banner(vs: Vector2, c: Vector2, k: float) -> void:
	# League's in-game end-of-game art (UI.wad endofgame/): crest base + metallic lettering, same 512x256 canvas
	var crest := tex("res://assets/ui/eog/crest_victory.png" if victory else "res://assets/ui/eog/crest_defeat.png")
	var word := tex("res://assets/ui/eog/text_victory.png" if victory else "res://assets/ui/eog/text_defeat.png")
	var col := Color(1.0, 0.85, 0.45) if victory else Color(0.95, 0.3, 0.25)
	var age := maxf(t - BANNER_AT, 0.0)
	# crest: scale in with a little overshoot, fade in
	var ka := clampf(age / 0.45, 0.0, 1.0)
	var back := 1.0 + 2.2 * pow(ka - 1.0, 3.0) + 1.2 * pow(ka - 1.0, 2.0)
	var cs := lerpf(1.45, 1.0, back) if ka < 1.0 else 1.0
	var w := 860.0
	var h := 430.0
	var cc := c + Vector2(0, -20)
	# soft backlight + rays
	glow(Rect2(cc - Vector2(300, 90), Vector2(600, 180)), Color(col.r, col.g, col.b, 0.20 * ka), 90, true)
	for i in 16:
		var a := TAU * i / 16.0 + t * 0.08
		var len := 460.0 + 60.0 * sin(t * 1.7 + i * 1.3)
		draw_line(cc, cc + Vector2(cos(a), sin(a)) * len * ka, Color(col.r, col.g, col.b, 0.045 * ka), 26.0)
	if crest != null:
		var sz := Vector2(w, h) * cs
		draw_texture_rect(crest, Rect2(cc - sz * 0.5, sz), false, Color(1, 1, 1, ka))
	# lettering arrives slightly after the crest and settles from a larger size
	var kt := clampf((age - 0.18) / 0.5, 0.0, 1.0)
	var ts := lerpf(1.25, 1.0, 1.0 - pow(1.0 - kt, 3.0))
	if word != null:
		var wsz := Vector2(w, h) * ts
		draw_texture_rect(word, Rect2(cc - wsz * 0.5, wsz), false, Color(1, 1, 1, kt))
		# one flash as the lettering lands
		var fl := clampf(1.0 - absf(age - 0.32) / 0.22, 0.0, 1.0)
		if fl > 0.0:
			glow(Rect2(cc - Vector2(230, 40), Vector2(460, 80)), Color(1, 0.95, 0.8, 0.5 * fl), 60, true)
	divider(c.x, c.y + 215, 560.0 * kt, kt)
	label("ARAM: Mayhem  ·  %s" % _time_str(), c + Vector2(0, 250), "h5", 1, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, kt), 24.0, true)


func _time_str() -> String:
	var tm: float = match_ref.time
	return "%d:%02d" % [int(tm / 60.0), int(tm) % 60]


func _draw_stats(vs: Vector2) -> void:
	var k := clampf(_stats_t * 3.0, 0.0, 1.0)
	var w := minf(vs.x - 100, 1700.0)
	var x := vs.x * 0.5 - w * 0.5
	var y := 34.0 + (1.0 - k) * 40.0
	var wt := tex("res://assets/ui/eog/text_victory.png" if victory else "res://assets/ui/eog/text_defeat.png")
	if wt != null:
		draw_texture_rect(wt, Rect2(x - 40, y - 28, 400, 200), false, Color(1, 1, 1, k))
	label("ARAM: Mayhem  ·  Howling Abyss  ·  %s" % _time_str(), Vector2(x + 560, y + 46), "sub", 0, Color(C_DIM.r, C_DIM.g, C_DIM.b, k), 21.0)
	var kills: Array = match_ref.kills
	label("%d  /  %d" % [kills[0], kills[1]], Vector2(x + w, y + 44), "h2", 2, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, k), 44.0)
	divider(vs.x * 0.5, y + 90, w * 0.9, k)
	y += 112
	var max_dmg := 1.0
	for c in match_ref.champions:
		max_dmg = maxf(max_dmg, c.champion_damage_total)
	var block_h := (vs.y - 220 - y) * 0.5
	for team in 2:
		var won: bool = match_ref.winner == team
		var tcol := G.COLOR_ALLY if team == G.player.team else G.COLOR_ENEMY
		var hy := y + team * (block_h + 10)
		# team header bar (client scoreboard team colour bar)
		_hgrad(Rect2(x, hy, w, 40), Color(tcol.r * 0.35, tcol.g * 0.35, tcol.b * 0.45, 0.9), Color(tcol.r * 0.1, tcol.g * 0.1, tcol.b * 0.14, 0.4))
		draw_rect(Rect2(x, hy, 5, 40), tcol)
		label(("Your team" if team == G.player.team else "Enemy team") + ("  —  Victory" if won else "  —  Defeat"), Vector2(x + 20, hy + 20), "h5", 0, C_TEXT, 21.0)
		var cols := [["KDA", 0.30], ["CS", 0.385], ["Damage to champions", 0.44], ["Taken", 0.585], ["Gold", 0.645], ["Items", 0.71], ["Augments", 0.87]]
		if not Rules.AUGMENTS_ENABLED:
			cols.pop_back()
		for cc in cols:
			label(cc[0], Vector2(x + w * cc[1], hy + 20), "h6", 0, C_DIM, 17.0)
		var ry := hy + 46
		var n := 0
		for c in match_ref.champions:
			if c.team == team:
				n += 1
		var row_h := minf(62.0, (block_h - 48) / maxf(n, 1))
		for c in match_ref.champions:
			if c.team != team:
				continue
			_draw_row(c, Rect2(x, ry, w, row_h - 4), max_dmg)
			ry += row_h
	var by := vs.y - 100.0
	var ba := appear(0.5 + 0.0)
	button("replay", Rect2(vs.x * 0.5 - 330, by, 310, 66), "Play again", "primary", true, 26)
	button("menu", Rect2(vs.x * 0.5 + 20, by, 310, 66), "Main menu", "normal", true, 26)


func _draw_row(c, r: Rect2, max_dmg: float) -> void:
	var me: bool = c == G.player
	var h := r.size.y
	vgrad_stops(r, [[0.0, Color(0.06, 0.1, 0.14, 0.9) if me else Color(0.03, 0.06, 0.09, 0.8)], [1.0, Color(0.02, 0.04, 0.07, 0.9)]])
	if me:
		grad_border(r, 2.0, [[0.0, Color("785a28")], [1.0, Color("c8aa6e")]])
	else:
		grad_border(r, 1.0, [[0.0, Color("1e2328")], [1.0, Color("3c3c41")]])
	var x := r.position.x
	var w := r.size.x
	var cy := r.get_center().y
	var isz := h - 12
	icon(Assets.champion_square(c.alias), Rect2(x + 8, r.position.y + 6, isz, isz), C_GOLD_DARK)
	var lc := Vector2(x + 8 + isz - 6, r.end.y - 9)
	draw_circle(lc, 12, Color(0, 0, 0, 0.9))
	draw_arc(lc, 12, 0, TAU, 24, Color(0.78, 0.67, 0.43, 0.9), 1.5, true)
	label(str(c.level), lc, "num", 1, C_TEXT, 15.0)
	label(c.display_name, Vector2(x + 24 + isz, cy - 10), "h4", 0, C_GOLD_BRIGHT if me else C_TEXT, 23.0, false, 0.0, w * 0.17)
	label("You" if me else "Bot", Vector2(x + 24 + isz, cy + 14), "label", 0, C_TEAL if me else C_DIM, 17.0)
	if c == _mvp:
		var mr := Rect2(x + w * 0.225, cy - 14, 64, 28)
		draw_rect(mr, Color(0.28, 0.2, 0.04, 0.95))
		grad_border(mr, 2.0, [[0.0, Color("785a28")], [1.0, Color("f0e6d2")]])
		label("MVP", mr.get_center(), "h6", 1, C_GOLD_BRIGHT, 18.0)
	label("%d / %d / %d" % [c.kills, c.deaths, c.assists], Vector2(x + w * 0.30, cy), "num", 0, C_TEXT, 24.0)
	label(str(c.cs), Vector2(x + w * 0.385, cy), "num", 0, C_TEXT, 22.0)
	var dr := Rect2(x + w * 0.44, cy + 6, w * 0.125, 9)
	draw_rect(dr, Color(0.1, 0.12, 0.14))
	var df: float = dr.size.x * c.champion_damage_total / max_dmg
	_hgrad(Rect2(dr.position, Vector2(df, dr.size.y)), Color("8e2d22"), Color("e8574d"))
	label(_k(c.champion_damage_total), Vector2(dr.position.x, cy - 10), "label", 0, C_TEXT, 19.0)
	label(_k(c.damage_taken_total), Vector2(x + w * 0.585, cy), "label", 0, C_TEXT, 20.0)
	label(_k(c.total_gold), Vector2(x + w * 0.645, cy), "label", 0, C_GOLD, 20.0)
	var isl := minf(h - 14, 40.0)
	for i in 6:
		var ir := Rect2(x + w * 0.71 + i * (isl + 5), cy - isl * 0.5, isl, isl)
		if i < c.items.size():
			icon(Assets.item_icon(c.items[i].item_id), ir, C_GOLD_DARK)
			var id := "it:%d:%d" % [c.get_instance_id(), i]
			hit_area(id, ir, "silent")
			set_tip(id, c.items[i].display_name, c.items[i].tooltip())
		else:
			draw_rect(ir, Color(0.04, 0.06, 0.08))
			draw_rect(ir, Color("1e2328"), false, 1.0)
	var ax := x + w * 0.87
	for i in mini(c.augments.size(), 6):
		var a = c.augments[i]
		var ar := Rect2(ax + i * (isl * 0.8 + 4), cy - isl * 0.4, isl * 0.8, isl * 0.8)
		var rc: Color = G.RARITY_COLORS.get(a.rarity, C_GOLD)
		icon(Assets.augment_icon(a.id), ar, rc)
		var id := "au:%d:%d" % [c.get_instance_id(), i]
		hit_area(id, ar, "silent")
		set_tip(id, a.display_name, a.description)


func _k(v: float) -> String:
	return "%.1fk" % (v / 1000.0) if v >= 1000.0 else str(int(v))


func on_action(id: String) -> void:
	match id:
		"continue":
			_phase = 2
			Sfx.ui("flare")
			Sfx.ui("postgame_level", -4.0)
		"replay", "menu":
			super.on_action(id)
