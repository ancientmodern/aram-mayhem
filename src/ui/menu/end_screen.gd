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
		if s > bs:
			bs = s
			best = c
	return best


func draw_screen(vs: Vector2) -> void:
	if _phase == 0:
		return
	var k := clampf((t - BANNER_AT) / 0.5, 0.0, 1.0)
	if _phase == 1:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45 * k))
		_draw_banner(vs, vs * Vector2(0.5, 0.42), k)
		if t > BANNER_AT + 1.4:
			button("continue", Rect2(vs.x * 0.5 - 140, vs.y * 0.68, 280, 58), "Continue", "primary", true, 22)
	else:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.02, 0.04, 0.88))
		_draw_stats(vs)


func _draw_banner(vs: Vector2, c: Vector2, k: float) -> void:
	var col := Color(1.0, 0.85, 0.45) if victory else Color(0.95, 0.3, 0.25)
	var word := "VICTORY" if victory else "DEFEAT"
	var s := lerpf(1.6, 1.0, ease(k, 0.3))
	# radiant rays
	for i in 24:
		var a := TAU * i / 24.0 + t * 0.15
		var len := 260.0 + 60.0 * sin(t * 2.0 + i)
		draw_line(c, c + Vector2(cos(a), sin(a)) * len * k, Color(col.r, col.g, col.b, 0.08 * k), 18.0)
	draw_circle(c, 210.0 * k, Color(col.r * 0.25, col.g * 0.2, col.b * 0.15, 0.55 * k))
	draw_arc(c, 214.0 * k, 0, TAU, 96, Color(col.r, col.g, col.b, 0.6 * k), 3.0)
	draw_arc(c, 230.0 * k, t * 0.5, t * 0.5 + PI * 1.4, 64, Color(col.r, col.g, col.b, 0.35 * k), 2.0)
	var sz := int(110 * s)
	text_center(word, c + Vector2(0, 6), sz, Color(col.r, col.g, col.b, k), f_heavy, true, 10.0 * s)
	text_center("ARAM: MAYHEM  ·  %s" % _time_str(), c + Vector2(0, 92), 18, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, k), f_semi, true, 2.0)


func _time_str() -> String:
	var tm: float = match_ref.time
	return "%d:%02d" % [int(tm / 60.0), int(tm) % 60]


func _draw_stats(vs: Vector2) -> void:
	var k := clampf(_stats_t * 3.0, 0.0, 1.0)
	var w := minf(vs.x - 80, 1500.0)
	var x := vs.x * 0.5 - w * 0.5
	var y := 50.0 + (1.0 - k) * 40.0
	var col := Color(1.0, 0.85, 0.45) if victory else Color(0.95, 0.3, 0.25)
	text("VICTORY" if victory else "DEFEAT", Vector2(x, y + 40), 48, col, f_heavy, true)
	text("ARAM: MAYHEM  ·  HOWLING ABYSS  ·  %s" % _time_str(), Vector2(x + 290, y + 34), 17, C_DIM, f_semi)
	var kills: Array = match_ref.kills
	text_right("%d  /  %d" % [kills[0], kills[1]], Vector2(x + w, y + 38), 30, C_TEXT, f_bold)
	y += 70
	var max_dmg := 1.0
	for c in match_ref.champions:
		max_dmg = maxf(max_dmg, c.champion_damage_total)
	for team in 2:
		var won: bool = match_ref.winner == team
		var tcol := G.COLOR_ALLY if team == G.player.team else G.COLOR_ENEMY
		var hy := y + team * 330.0
		draw_rect(Rect2(x, hy, w, 34), Color(tcol.r * 0.2, tcol.g * 0.2, tcol.b * 0.25, 0.9))
		draw_rect(Rect2(x, hy, 4, 34), tcol)
		text(("YOUR TEAM" if team == G.player.team else "ENEMY TEAM") + ("  —  VICTORY" if won else "  —  DEFEAT"), Vector2(x + 14, hy + 23), 16, C_TEXT, f_bold)
		var cols := [["KDA", 0.30], ["CS", 0.38], ["DAMAGE TO CHAMPIONS", 0.43], ["TAKEN", 0.58], ["GOLD", 0.64], ["ITEMS", 0.70], ["AUGMENTS", 0.86]]
		if not Rules.AUGMENTS_ENABLED:
			cols.pop_back()
		for cc in cols:
			text(cc[0], Vector2(x + w * cc[1], hy + 23), 12, C_DIM, f_bold)
		var ry := hy + 40
		for c in match_ref.champions:
			if c.team != team:
				continue
			_draw_row(c, Rect2(x, ry, w, 54), max_dmg)
			ry += 58
	var by := vs.y - 90.0
	button("replay", Rect2(vs.x * 0.5 - 300, by, 280, 58), "Play Again", "primary", true, 22)
	button("menu", Rect2(vs.x * 0.5 + 20, by, 280, 58), "Main Menu", "normal", true, 20)


func _draw_row(c, r: Rect2, max_dmg: float) -> void:
	var me: bool = c == G.player
	frame(r, Color(0.05, 0.1, 0.13, 0.9) if me else Color(0.02, 0.05, 0.08, 0.8), C_GOLD if me else Color(0.12, 0.16, 0.2))
	var x := r.position.x
	var w := r.size.x
	icon(Assets.champion_square(c.alias), Rect2(x + 8, r.position.y + 5, 44, 44), C_GOLD_DARK)
	draw_circle(Vector2(x + 52, r.end.y - 8), 10, Color(0, 0, 0, 0.85))
	text_center(str(c.level), Vector2(x + 52, r.end.y - 8), 12, C_TEXT, f_bold)
	text(c.display_name, Vector2(x + 64, r.position.y + 24), 18, C_GOLD_BRIGHT if me else C_TEXT, f_bold)
	text("You" if me else "Bot", Vector2(x + 64, r.position.y + 44), 13, C_TEAL if me else C_DIM, f_semi)
	if c == _mvp:
		var mr := Rect2(x + w * 0.22, r.position.y + 14, 52, 24)
		frame(mr, Color(0.35, 0.25, 0.05, 0.95), C_GOLD_BRIGHT)
		text_center("MVP", mr.get_center(), 14, C_GOLD_BRIGHT, f_heavy)
	text("%d / %d / %d" % [c.kills, c.deaths, c.assists], Vector2(x + w * 0.30, r.position.y + 33), 18, C_TEXT, f_bold)
	text(str(c.cs), Vector2(x + w * 0.38, r.position.y + 33), 17, C_TEXT, f_semi)
	var dr := Rect2(x + w * 0.43, r.position.y + 30, w * 0.12, 8)
	draw_rect(dr, Color(0.1, 0.12, 0.14))
	draw_rect(Rect2(dr.position, Vector2(dr.size.x * c.champion_damage_total / max_dmg, dr.size.y)), Color(0.9, 0.35, 0.25))
	text(_k(c.champion_damage_total), Vector2(dr.position.x, r.position.y + 22), 15, C_TEXT, f_semi)
	text(_k(c.damage_taken_total), Vector2(x + w * 0.58, r.position.y + 33), 15, C_TEXT, f_semi)
	text(_k(c.total_gold), Vector2(x + w * 0.64, r.position.y + 33), 15, C_GOLD, f_semi)
	for i in 6:
		var ir := Rect2(x + w * 0.70 + i * 36, r.position.y + 11, 32, 32)
		if i < c.items.size():
			icon(Assets.item_icon(c.items[i].item_id), ir, C_GOLD_DARK)
			var id := "it:%d:%d" % [c.get_instance_id(), i]
			hit_area(id, ir)
			set_tip(id, c.items[i].display_name, c.items[i].tooltip())
		else:
			draw_rect(ir, Color(0.04, 0.06, 0.08))
	var ax := x + w * 0.86
	for i in mini(c.augments.size(), 6):
		var a = c.augments[i]
		var ar := Rect2(ax + i * 34, r.position.y + 12, 30, 30)
		var rc: Color = G.RARITY_COLORS.get(a.rarity, C_GOLD)
		icon(Assets.augment_icon(a.id), ar, rc)
		var id := "au:%d:%d" % [c.get_instance_id(), i]
		hit_area(id, ar)
		set_tip(id, a.display_name, a.description)


func _k(v: float) -> String:
	return "%.1fk" % (v / 1000.0) if v >= 1000.0 else str(int(v))


func on_action(id: String) -> void:
	match id:
		"continue":
			_phase = 2
			Sfx.ui("flare")
		"replay", "menu":
			super.on_action(id)
