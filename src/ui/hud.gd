class_name Hud
extends Control
## In-game HUD (League-like). Most of it is custom-drawn for crispness and speed.

signal open_shop
signal open_augments

var match_ref = null
var champ: Champion = null
var f_title: Font
var f_num: Font
var f_body: Font
var f_bold: Font
var announce_text := ""
var announce_sub := ""
var announce_color := Color.WHITE
var announce_t := 0.0
var feed: Array = []                ## kill feed entries {text_l, text_r, icon_l, icon_r, col, t}
var hover_tip := {}                 ## {title, body, pos}
var _slot_rects := {}               ## "Q" -> Rect2, "lvlQ" -> Rect2, "item0"...
var minimap_tex: Texture2D = null
var minimap_rect := Rect2()
var minimap_world := Rect2()        ## world x/z range shown
var augment_panel = null
var shop_panel = null
var scoreboard_visible := false
var fps_visible := false
var flash_cast := {}                ## slot -> time of last cast for button flash
var fail_msg := ""
var fail_t := 0.0

const C_PANEL := Color(0.02, 0.05, 0.08, 0.92)
const C_PANEL2 := Color(0.04, 0.08, 0.12, 0.95)
const C_GOLD := Color(0.78, 0.67, 0.43)
const C_GOLD_DARK := Color(0.47, 0.35, 0.16)
const C_TEXT := Color(0.94, 0.9, 0.82)
const C_DIM := Color(0.6, 0.62, 0.66)
const C_HP := Color(0.24, 0.72, 0.22)
const C_MP := Color(0.18, 0.45, 0.92)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	f_title = Assets.font("beaufort", "Bold")
	f_num = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_bold = Assets.font("spiegel", "Bold")
	champ = G.player
	G.announcement.connect(_on_announce)
	G.champion_killed.connect(_on_kill)
	G.structure_destroyed.connect(_on_structure)
	champ.cast_failed.connect(_on_cast_failed)
	_build_minimap()
	augment_panel = AugmentPanel.new()
	augment_panel.hud = self
	add_child(augment_panel)
	shop_panel = ShopPanel.new()
	shop_panel.hud = self
	add_child(shop_panel)
	shop_panel.visible = false


func _process(delta: float) -> void:
	announce_t = maxf(0.0, announce_t - delta)
	fail_t = maxf(0.0, fail_t - delta)
	for f in feed:
		f.t -= delta
	feed = feed.filter(func(f): return f.t > 0.0)
	scoreboard_visible = Input.is_action_pressed("scoreboard")
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop"):
		toggle_shop()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("augments"):
		augment_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fps"):
		fps_visible = not fps_visible


func toggle_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		shop_panel.refresh()


func _on_cast_failed(_ab, reason: String) -> void:
	match reason:
		"cooldown": fail_msg = "Ability on cooldown"
		"mana": fail_msg = "Not enough mana"
		"not learned": fail_msg = "Ability not learned"
		"no target": fail_msg = "No target"
		"cc": fail_msg = "Can't cast right now"
		_: fail_msg = ""
	fail_t = 1.2 if fail_msg != "" else 0.0
	if match_ref != null and match_ref.audio != null:
		var ev := {"cooldown": "Play_sfx_hud_base_SpellFail_Cooldown", "mana": "Play_sfx_hud_base_SpellFail_NoMana",
			"cc": "Play_sfx_hud_base_SpellFail_Silence"}.get(reason, "")
		match_ref.audio.play(ev, null, -6.0, 0.0)


func _on_announce(text: String, sub: String, col: Color) -> void:
	announce_text = text
	announce_sub = sub
	announce_color = col
	announce_t = 3.0


func _on_kill(victim, killer, assisters) -> void:
	var col := G.COLOR_ALLY if victim.team != champ.team else G.COLOR_ENEMY
	var ki = null
	if killer != null and is_instance_valid(killer) and killer.kind == G.Kind.CHAMPION:
		ki = Assets.champion_square(killer.alias)
	feed.append({"killer": killer.display_name if killer != null and is_instance_valid(killer) else "Executed",
		"victim": victim.display_name, "ki": ki, "vi": Assets.champion_square(victim.alias), "col": col, "t": 7.0,
		"assists": assisters.size()})
	if feed.size() > 6:
		feed.pop_front()


func _on_structure(s, _killer) -> void:
	pass


# ===================================================================== minimap
func _build_minimap() -> void:
	var nav: NavGrid = match_ref.nav
	if nav == null or nav.w == 0:
		return
	var img := Image.create(nav.w, nav.h, false, Image.FORMAT_RGBA8)
	for j in nav.h:
		for i in nav.w:
			var idx := j * nav.w + i
			var c := Color(0.05, 0.08, 0.12, 0.0)
			if nav.walk[idx] == 1:
				var hh := nav.heights[idx]
				c = Color(0.55, 0.62, 0.72, 1.0).lerp(Color(0.75, 0.82, 0.9, 1.0), clampf((hh + 2.0) / 2.0, 0.0, 1.0))
				if not nav.brush.is_empty() and nav.brush[idx] > 0:
					c = Color(0.3, 0.5, 0.42, 1.0)
			img.set_pixel(i, j, c)
	minimap_tex = ImageTexture.create_from_image(img)
	minimap_world = Rect2(nav.origin, Vector2(nav.w * nav.cell, nav.h * nav.cell))


func world_to_minimap(p: Vector3) -> Vector2:
	var u := (p.x - minimap_world.position.x) / minimap_world.size.x
	var v := (p.z - minimap_world.position.y) / minimap_world.size.y
	return minimap_rect.position + Vector2(u, v) * minimap_rect.size


func minimap_to_world(sp: Vector2) -> Vector3:
	var k := (sp - minimap_rect.position) / minimap_rect.size
	return Vector3(minimap_world.position.x + k.x * minimap_world.size.x, 0.0, minimap_world.position.y + k.y * minimap_world.size.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mp: Vector2 = event.position
		if minimap_rect.has_point(mp):
			var wp := minimap_to_world(mp)
			if event.button_index == MOUSE_BUTTON_LEFT:
				match_ref.camera_rig.locked = false
				match_ref.camera_rig.focus = Vector3(wp.x, match_ref.nav.height_at(wp), wp.z)
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				champ.issue_move(match_ref.nav.nearest_walkable(wp))
			accept_event()
			return
		for k in _slot_rects:
			var r: Rect2 = _slot_rects[k]
			if r.has_point(mp):
				if k.begins_with("lvl"):
					champ.level_ability("QWER".find(k.substr(3)))
					accept_event()
				elif k == "shop":
					toggle_shop()
					accept_event()
				elif k == "augbtn":
					augment_panel.toggle()
					accept_event()
				return
	elif event is InputEventMouseMotion:
		_update_tooltip(event.position)


func _has_point_ui(mp: Vector2) -> bool:
	for k in _slot_rects:
		if _slot_rects[k].has_point(mp):
			return true
	return minimap_rect.has_point(mp)


func _update_tooltip(mp: Vector2) -> void:
	hover_tip = {}
	for k in _slot_rects:
		var r: Rect2 = _slot_rects[k]
		if not r.has_point(mp):
			continue
		if k in ["P", "Q", "W", "E", "R", "D", "F"]:
			hover_tip = _ability_tip(k)
		elif k.begins_with("item"):
			var i := int(k.substr(4))
			if i < champ.items.size():
				var it = champ.items[i]
				hover_tip = {"title": it.display_name, "body": it.tooltip(), "icon": it.icon}
		elif k.begins_with("aug"):
			if k == "augbtn":
				continue
			var ai := int(k.substr(3))
			if ai < champ.augments.size():
				var a = champ.augments[ai]
				hover_tip = {"title": a.display_name, "body": a.tooltip(), "icon": a.icon, "rarity": a.get("rarity")}
		elif k.begins_with("buff"):
			var bi := int(k.substr(4))
			var vis := _visible_buffs()
			if bi < vis.size():
				hover_tip = {"title": vis[bi].display_name, "body": vis[bi].description}
		if not hover_tip.is_empty():
			hover_tip.pos = r.position + Vector2(r.size.x * 0.5, 0)
		return


func _ability_tip(k: String) -> Dictionary:
	if k == "P":
		var p = champ.passive
		var info: Dictionary = ChampionDB.client_data(champ.alias).get("passive", {})
		return {"title": info.get("name", "Passive"), "body": _clean(info.get("description", "")), "icon": p.icon if p else null}
	var ab: Ability = champ.ability("QWER".find(k)) if k in ["Q", "W", "E", "R"] else champ.summoners[0 if k == "D" else 1]
	if ab == null:
		return {}
	var cd_txt := ""
	if not ab.is_summoner and ab.level > 0:
		cd_txt = "Cooldown: %.1fs" % champ.stats.cooldown(ab.base_cooldown(), ab.is_ult)
	var cost_txt := ""
	if ab.cost() > 0.0 and champ.stats.uses_mana:
		cost_txt = "   Cost: %d %s" % [int(ab.cost()), champ.resource_name]
	var lvl := ""
	if not ab.is_summoner:
		lvl = "  (Rank %d/%d)" % [ab.level, ab.max_level]
	return {"title": ab.display_name + lvl, "body": _clean(ab.tooltip_text()), "sub": cd_txt + cost_txt, "icon": ab.icon}


static func _clean(s: String) -> String:
	var re := RegEx.create_from_string("<[^>]+>")
	return re.sub(s.replace("<br>", "\n"), "", true)


# ===================================================================== drawing
func _draw() -> void:
	if champ == null:
		return
	_slot_rects.clear()
	var vs := size
	_draw_top_bar(vs)
	_draw_bottom_panel(vs)
	_draw_minimap(vs)
	_draw_feed(vs)
	_draw_allies(vs)
	_draw_announce(vs)
	_draw_death(vs)
	if fail_t > 0.0:
		var a := minf(1.0, fail_t * 2.0)
		_text_center(fail_msg, Vector2(vs.x * 0.5, vs.y - 230), 18, Color(1, 0.4, 0.35, a), f_bold)
	if scoreboard_visible:
		_draw_scoreboard(vs)
	if fps_visible:
		draw_string(f_bold, Vector2(10, 20), "FPS %d" % Engine.get_frames_per_second(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	if not hover_tip.is_empty():
		_draw_tooltip(hover_tip)


func _frame(r: Rect2, fill: Color = C_PANEL, border: Color = C_GOLD_DARK, w: float = 1.5) -> void:
	draw_rect(r, fill)
	draw_rect(r, border, false, w)


func _text(s: String, p: Vector2, sz: int, col: Color, f: Font = null) -> void:
	draw_string(f if f else f_body, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_center(s: String, p: Vector2, sz: int, col: Color, f: Font = null, outline: bool = true) -> void:
	var font := f if f else f_body
	var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	var pos := p - Vector2(ts.x * 0.5, -sz * 0.35)
	if outline:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.85))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw_top_bar(vs: Vector2) -> void:
	var w := 300.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, 0, w, 40)
	_frame(r, C_PANEL, C_GOLD_DARK)
	var k: Array = match_ref.kills
	var my := champ.team
	_text_center(str(k[my]), Vector2(r.position.x + 55, 21), 24, G.COLOR_ALLY, f_num)
	_text_center(str(k[1 - my]), Vector2(r.end.x - 55, 21), 24, G.COLOR_ENEMY, f_num)
	var t: float = match_ref.time
	_text_center("%d:%02d" % [int(t / 60.0), int(t) % 60], Vector2(vs.x * 0.5, 21), 20, C_TEXT, f_num)
	# KDA / CS top right
	var kr := Rect2(vs.x - 250, 0, 250, 30)
	_frame(kr, C_PANEL, C_GOLD_DARK)
	_text("%d / %d / %d" % [champ.kills, champ.deaths, champ.assists], kr.position + Vector2(14, 21), 17, C_TEXT, f_num)
	_text("CS %d" % champ.cs, kr.position + Vector2(140, 21), 17, C_TEXT, f_num)


func _draw_bottom_panel(vs: Vector2) -> void:
	var pw := 720.0
	var ph := 150.0
	var base := Vector2(vs.x * 0.5 - pw * 0.5 + 60, vs.y - ph)
	var panel := Rect2(base, Vector2(pw, ph))
	_frame(panel, C_PANEL, C_GOLD_DARK, 2.0)
	# portrait
	var pc := base + Vector2(-58, ph * 0.5 + 6)
	draw_circle(pc, 62, C_PANEL2)
	var sq := Assets.champion_square(champ.alias)
	if sq != null:
		_draw_circle_tex(sq, pc, 52)
	# xp ring
	draw_arc(pc, 56, -PI * 0.5, -PI * 0.5 + TAU * champ.xp_ratio(), 48, Color(0.65, 0.4, 0.95), 5.0, true)
	draw_arc(pc, 59.5, 0, TAU, 64, C_GOLD, 2.0, true)
	var lb := Rect2(pc + Vector2(-17, 40), Vector2(34, 24))
	_frame(lb, Color(0.05, 0.05, 0.08), C_GOLD)
	_text_center(str(champ.level), lb.get_center() + Vector2(0, 0), 16, Color(1, 0.92, 0.7), f_num)
	# stats panel (left of portrait)
	var sr := Rect2(base + Vector2(-330, 22), Vector2(200, 128))
	_frame(sr, C_PANEL, C_GOLD_DARK)
	var st := champ.stats
	var rows := [
		["AD", str(int(st.ad)), "AP", str(int(st.ap))],
		["Armor", str(int(st.armor)), "MR", str(int(st.mr))],
		["AS", "%.2f" % st.attack_speed, "AH", str(int(st.ability_haste))],
		["Crit", "%d%%" % int(st.crit_chance * 100.0), "MS", str(int(st.move_speed))],
	]
	for i in rows.size():
		var y := sr.position.y + 26 + i * 27
		_text(rows[i][0], Vector2(sr.position.x + 10, y), 13, C_DIM, f_body)
		_text(rows[i][1], Vector2(sr.position.x + 55, y), 15, C_TEXT, f_bold)
		_text(rows[i][2], Vector2(sr.position.x + 105, y), 13, C_DIM, f_body)
		_text(rows[i][3], Vector2(sr.position.x + 145, y), 15, C_TEXT, f_bold)
	# abilities
	var ax := base.x + 28
	var ay := base.y + 18
	_draw_passive(Rect2(ax, ay + 10, 46, 46))
	ax += 58
	for i in 4:
		var r := Rect2(ax + i * 76, ay, 66, 66)
		_draw_ability(i, r)
	# summoners
	var sx := ax + 4 * 76 + 6
	for i in 2:
		var r2 := Rect2(sx + i * 52, ay + 10, 46, 46)
		_draw_summoner(i, r2)
	# hp / mana bars
	var bar_x := base.x + 28
	var bar_w := 480.0
	var hp_r := Rect2(bar_x, base.y + 104, bar_w, 20)
	_draw_bar(hp_r, champ.hp, champ.stats.max_hp, C_HP, champ.total_shield(), champ.stats.hp_regen)
	if champ.stats.max_mana > 0.0:
		var mp_r := Rect2(bar_x, base.y + 127, bar_w, 15)
		_draw_bar(mp_r, champ.mana, champ.stats.max_mana, C_MP, 0.0, champ.stats.mana_regen)
	# items (2x3) + gold
	var ix := base.x + pw - 168
	var iy := base.y + 14
	for i in 6:
		var r3 := Rect2(ix + (i % 3) * 50, iy + int(i / 3) * 50, 46, 46)
		_frame(r3, C_PANEL2, C_GOLD_DARK)
		if i < champ.items.size():
			var it = champ.items[i]
			if it.icon != null:
				draw_texture_rect(it.icon, r3.grow(-2), false)
			if it.has_method("cooldown_ratio") and it.cooldown_ratio() > 0.0:
				_draw_cd_sweep(r3.grow(-2), it.cooldown_ratio())
		_slot_rects["item%d" % i] = r3
	var gr := Rect2(ix, iy + 104, 146, 28)
	_frame(gr, C_PANEL2, C_GOLD if champ.can_shop() else C_GOLD_DARK)
	_text_center("%d" % int(champ.gold), gr.get_center() + Vector2(8, 0), 18, G.COLOR_GOLD, f_num)
	draw_circle(gr.position + Vector2(22, 14), 7, G.COLOR_GOLD)
	_slot_rects["shop"] = gr
	# augments row above the panel
	_draw_augment_row(Vector2(base.x + 30, base.y - 44))
	# buffs row
	_draw_buffs(Vector2(base.x + 260, base.y - 40))


func _draw_circle_tex(tex: Texture2D, center: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var d := Vector2(cos(a), sin(a))
		pts.append(center + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_colored_polygon(pts, Color.WHITE, uvs, tex)


func _draw_bar(r: Rect2, v: float, mx: float, col: Color, shield: float, regen: float) -> void:
	draw_rect(r, Color(0.08, 0.08, 0.1))
	var total := maxf(mx, v + shield)
	var w := r.size.x * clampf(v / maxf(total, 1.0), 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(w, r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(w, r.size.y * 0.4)), Color(1, 1, 1, 0.15))
	if shield > 0.0:
		var sw := r.size.x * clampf(shield / maxf(total, 1.0), 0.0, 1.0)
		draw_rect(Rect2(r.position + Vector2(w, 0), Vector2(sw, r.size.y)), Color(0.9, 0.9, 0.9))
	draw_rect(r, C_GOLD_DARK, false, 1.0)
	var t := "%d / %d" % [int(v), int(mx)]
	_text_center(t, r.get_center() + Vector2(0, -1), int(r.size.y * 0.72), C_TEXT, f_bold)
	if regen > 0.05:
		var rt := "+%.1f" % (regen * 5.0)
		var ts := f_body.get_string_size(rt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		_text(rt, Vector2(r.end.x - ts.x - 6, r.position.y + r.size.y * 0.75), 11, Color(0.85, 0.95, 0.85, 0.8), f_body)


func _draw_cd_sweep(r: Rect2, ratio: float) -> void:
	if ratio <= 0.0:
		return
	var c := r.get_center()
	var pts := PackedVector2Array([c])
	var steps := 32
	var start := -PI * 0.5
	var end := start + TAU * ratio
	for i in range(steps + 1):
		var a := lerpf(start, end, float(i) / steps)
		var d := Vector2(cos(a), sin(a)) * r.size.x
		var p := c + d
		p.x = clampf(p.x, r.position.x, r.end.x)
		p.y = clampf(p.y, r.position.y, r.end.y)
		pts.append(p)
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(0, 0, 0, 0.62))


func _draw_passive(r: Rect2) -> void:
	_frame(r, C_PANEL2, C_GOLD_DARK)
	var p = champ.passive
	var icon: Texture2D = p.icon if p != null else Assets.ability_icon(champ.alias, "p")
	if icon != null:
		draw_texture_rect(icon, r.grow(-2), false)
	if p != null and p.has_method("hud_counter"):
		var cnt: String = p.hud_counter()
		if cnt != "":
			_text_center(cnt, r.get_center() + Vector2(0, 12), 13, Color.WHITE, f_num)
	_slot_rects["P"] = r


func _draw_ability(i: int, r: Rect2) -> void:
	var ab: Ability = champ.abilities[i]
	var key: String = "QWER"[i]
	_frame(r, C_PANEL2, C_GOLD if ab != null and ab.is_ready() and ab.can_afford() else C_GOLD_DARK, 2.0)
	if ab == null:
		return
	if ab.icon != null:
		var mod := Color.WHITE
		if ab.level == 0:
			mod = Color(0.3, 0.3, 0.3)
		elif not ab.can_afford():
			mod = Color(0.45, 0.55, 1.0)
		draw_texture_rect(ab.icon, r.grow(-3), false, mod)
	if ab.level > 0 and not ab.is_ready() and ab.cd > 0.0:
		_draw_cd_sweep(r.grow(-3), ab.cd / maxf(ab.cd_total, 0.01))
		var cds := ("%.1f" % ab.cd) if ab.cd < 1.0 else str(int(ceil(ab.cd)))
		_text_center(cds, r.get_center(), 24, Color.WHITE, f_num)
	if ab.recast_window > 0.0:
		draw_rect(r.grow(-1), Color(1.0, 0.85, 0.3, 0.25 + 0.15 * sin(Time.get_ticks_msec() * 0.01)), false, 3.0)
	if ab.toggled:
		draw_rect(r.grow(-2), Color(0.4, 0.8, 1.0, 0.9), false, 3.0)
	if ab.max_charges > 0:
		_text_center(str(ab.charges), r.position + Vector2(r.size.x - 10, 12), 14, Color(1, 1, 0.8), f_num)
	# key label
	var kr := Rect2(r.position + Vector2(-2, r.size.y - 18), Vector2(18, 18))
	_frame(kr, Color(0.03, 0.03, 0.05), C_GOLD_DARK, 1.0)
	_text_center(key, kr.get_center(), 13, C_TEXT, f_bold)
	# mana cost
	if ab.cost() > 0.0 and champ.stats.uses_mana and ab.level > 0:
		_text_center(str(int(ab.cost())), r.position + Vector2(r.size.x * 0.5, r.size.y + 9), 11, Color(0.55, 0.75, 1.0), f_bold, true)
	# rank pips
	var pips := ab.max_level
	var pw := (r.size.x - 6) / pips
	for p in pips:
		var pr := Rect2(r.position.x + 3 + p * pw, r.position.y - 7, pw - 2, 4)
		draw_rect(pr, Color(0.9, 0.75, 0.35) if p < ab.level else Color(0.15, 0.15, 0.18))
	# level-up button
	if champ.can_level_ability(i):
		var lr := Rect2(r.position + Vector2(r.size.x * 0.5 - 13, -36), Vector2(26, 24))
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.006)
		_frame(lr, Color(0.25, 0.2, 0.05, 0.95), Color(1.0, 0.85, 0.35, pulse), 2.0)
		_text_center("+", lr.get_center() + Vector2(0, -1), 22, Color(1.0, 0.9, 0.5), f_num)
		_slot_rects["lvl" + key] = lr
	_slot_rects[key] = r


func _draw_summoner(i: int, r: Rect2) -> void:
	var ab: Ability = champ.summoners[i]
	_frame(r, C_PANEL2, C_GOLD_DARK)
	if ab == null:
		return
	if ab.icon != null:
		draw_texture_rect(ab.icon, r.grow(-2), false)
	if not ab.is_ready() and ab.cd > 0.0:
		_draw_cd_sweep(r.grow(-2), ab.cd / maxf(ab.cd_total, 0.01))
		_text_center(str(int(ceil(ab.cd))), r.get_center(), 17, Color.WHITE, f_num)
	if ab.recast_window > 0.0:
		draw_rect(r.grow(-1), Color(1.0, 0.85, 0.3, 0.6), false, 3.0)
	var key := "D" if i == 0 else "F"
	_text_center(key, r.position + Vector2(8, r.size.y - 8), 11, C_TEXT, f_bold)
	_slot_rects[key] = r


func _draw_augment_row(p: Vector2) -> void:
	var x := p.x
	for i in champ.augments.size():
		var a = champ.augments[i]
		var r := Rect2(x, p.y, 38, 38)
		var col: Color = G.RARITY_COLORS.get(a.get("rarity"), C_GOLD)
		draw_rect(r, Color(0.02, 0.03, 0.05, 0.95))
		if a.icon != null:
			draw_texture_rect(a.icon, r.grow(-2), false)
		draw_rect(r, col, false, 2.0)
		if a.has_method("hud_counter"):
			var cnt: String = a.hud_counter()
			if cnt != "":
				_text_center(cnt, r.get_center() + Vector2(0, 12), 12, Color.WHITE, f_num)
		_slot_rects["aug%d" % i] = r
		x += 44
	if champ.augments_pending > 0:
		var br := Rect2(x + 4, p.y, 140, 38)
		var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
		var can: bool = champ.can_shop() and not augment_panel.in_combat(champ)
		_frame(br, Color(0.18, 0.1, 0.28, 0.95), Color(0.85, 0.55, 1.0, pulse if can else 0.4), 2.0)
		_text_center("AUGMENT  [G]" if can else "AUGMENT (base)", br.get_center(), 14, Color(0.95, 0.85, 1.0, 1.0 if can else 0.6), f_bold)
		_slot_rects["augbtn"] = br


func _visible_buffs() -> Array:
	return champ.buffs.filter(func(b): return not b.hidden and b.display_name != "" and b.show_timer)


func _draw_buffs(p: Vector2) -> void:
	var vis := _visible_buffs()
	var x := p.x
	for i in mini(vis.size(), 10):
		var b: Buff = vis[i]
		var r := Rect2(x, p.y + 4, 30, 30)
		var col := Color(0.85, 0.3, 0.25) if b.is_debuff else Color(0.35, 0.8, 0.4)
		_frame(r, Color(0.04, 0.05, 0.07, 0.9), col, 1.5)
		if b.icon != null:
			draw_texture_rect(b.icon, r.grow(-2), false)
		else:
			_text_center(b.display_name.substr(0, 2), r.get_center(), 12, C_TEXT, f_bold)
		if not b.permanent and b.duration > 0.0:
			_draw_cd_sweep(r.grow(-2), 1.0 - b.remaining / b.duration)
		if b.stacks > 1:
			_text_center(str(b.stacks), r.position + Vector2(24, 24), 11, Color.WHITE, f_num)
		_slot_rects["buff%d" % i] = r
		x += 34


func _draw_minimap(vs: Vector2) -> void:
	var s := 270.0
	minimap_rect = Rect2(vs.x - s - 8, vs.y - s - 8, s, s)
	_frame(minimap_rect.grow(4), C_PANEL, C_GOLD_DARK, 2.0)
	if minimap_tex != null:
		draw_texture_rect(minimap_tex, minimap_rect, false)
	# structures
	for u in match_ref.structures:
		if u.dead:
			continue
		var p := world_to_minimap(u.global_position)
		var col := G.COLOR_ALLY if u.team == champ.team else G.COLOR_ENEMY
		var sz := 5.0 if u.kind == G.Kind.TURRET else 7.0
		if u.get("tier") != null and u.tier == Turret.Tier.FOUNTAIN:
			continue
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0, 0, 0, 0.6), false, 1.0)
	for u in match_ref.units:
		if u.dead or u.kind != G.Kind.MINION:
			continue
		if u.team != champ.team and not u.visible_to[champ.team]:
			continue
		var p2 := world_to_minimap(u.global_position)
		draw_rect(Rect2(p2 - Vector2(1.5, 1.5), Vector2(3, 3)), G.COLOR_ALLY if u.team == champ.team else G.COLOR_ENEMY)
	for r in match_ref.relics:
		if r.active:
			draw_circle(world_to_minimap(r.global_position), 3.5, Color(0.35, 1.0, 0.45))
	for c in match_ref.champions:
		if c.dead:
			continue
		if c.team != champ.team and not c.visible_to[champ.team]:
			continue
		var p3 := world_to_minimap(c.global_position)
		var col2 := G.COLOR_ALLY if c.team == champ.team else G.COLOR_ENEMY
		if c == champ:
			col2 = G.COLOR_SELF
		var sq := Assets.champion_square(c.alias)
		draw_circle(p3, 11, col2)
		if sq != null:
			_draw_circle_tex(sq, p3, 9)
	# camera frustum box
	var cam: CameraRig = match_ref.camera_rig
	var f: Vector3 = cam.focus
	var hw: float = cam.distance * 0.75
	var a := world_to_minimap(f + Vector3(-hw, 0, -hw * 0.55))
	var b := world_to_minimap(f + Vector3(hw, 0, hw * 0.45))
	draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.7), false, 1.0)


func _draw_allies(vs: Vector2) -> void:
	var y := 120.0
	for c in match_ref.champions:
		if c.team != champ.team or c == champ:
			continue
		var r := Rect2(8, y, 52, 52)
		_frame(r, C_PANEL2, C_GOLD_DARK)
		var sq := Assets.champion_square(c.alias)
		if sq != null:
			draw_texture_rect(sq, r.grow(-2), false, Color(0.35, 0.35, 0.35) if c.dead else Color.WHITE)
		if c.dead:
			_text_center(str(int(ceil(c.respawn_timer))), r.get_center(), 20, Color.WHITE, f_num)
		var hb := Rect2(8, y + 54, 52, 5)
		draw_rect(hb, Color(0.1, 0.1, 0.1))
		draw_rect(Rect2(hb.position, Vector2(52 * c.hp_ratio(), 5)), C_HP)
		var ult: Ability = c.abilities[3]
		if ult != null and ult.level > 0:
			draw_circle(r.position + Vector2(48, 6), 5, Color(0.3, 0.9, 0.4) if ult.is_ready() else Color(0.4, 0.15, 0.15))
		_text("%d" % c.level, r.position + Vector2(3, 50), 12, C_TEXT, f_num)
		y += 70


func _draw_feed(vs: Vector2) -> void:
	var y := 52.0
	for f in feed:
		var a := clampf(f.t, 0.0, 1.0)
		var w := 300.0
		var r := Rect2(vs.x - w - 10, y, w, 36)
		draw_rect(r, Color(0.02, 0.03, 0.05, 0.75 * a))
		draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(f.col.r, f.col.g, f.col.b, a))
		if f.ki != null:
			draw_texture_rect(f.ki, Rect2(r.position + Vector2(8, 3), Vector2(30, 30)), false, Color(1, 1, 1, a))
		_text(f.killer, r.position + Vector2(44, 23), 14, Color(0.9, 0.9, 0.9, a), f_bold)
		_text("⚔", r.position + Vector2(w * 0.5 - 6, 24), 15, Color(1, 0.85, 0.5, a), f_body)
		if f.vi != null:
			draw_texture_rect(f.vi, Rect2(r.end.x - 38, r.position.y + 3, 30, 30), false, Color(1, 1, 1, a))
		var vs2 := f_bold.get_string_size(f.victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		_text(f.victim, Vector2(r.end.x - 44 - vs2.x, r.position.y + 23), 14, Color(0.9, 0.9, 0.9, a), f_bold)
		y += 40


func _draw_announce(vs: Vector2) -> void:
	if announce_t <= 0.0:
		return
	var a := clampf(announce_t, 0.0, 1.0) * clampf((3.0 - announce_t) * 6.0, 0.0, 1.0)
	var y := vs.y * 0.2
	var sc := 1.0 + maxf(0.0, (announce_t - 2.7)) * 1.5
	var w := 640.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, y - 34, w, 74)
	var grad_col := Color(announce_color.r * 0.3, announce_color.g * 0.3, announce_color.b * 0.3, 0.75 * a)
	draw_rect(r, grad_col)
	draw_line(r.position, r.position + Vector2(w, 0), Color(announce_color.r, announce_color.g, announce_color.b, a), 2.0)
	draw_line(r.position + Vector2(0, r.size.y), r.end, Color(announce_color.r, announce_color.g, announce_color.b, a), 2.0)
	_text_center(announce_text.to_upper(), Vector2(vs.x * 0.5, y - 4), int(34 * sc), Color(1, 0.95, 0.85, a), f_title)
	if announce_sub != "":
		_text_center(announce_sub, Vector2(vs.x * 0.5, y + 26), 16, Color(0.9, 0.9, 0.95, a), f_bold)


func _draw_death(vs: Vector2) -> void:
	if not champ.dead:
		return
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.05, 0.05, 0.08, 0.35))
	_text_center("RESPAWN IN", Vector2(vs.x * 0.5, vs.y * 0.36), 22, Color(0.85, 0.85, 0.9), f_title)
	_text_center(str(int(ceil(champ.respawn_timer))), Vector2(vs.x * 0.5, vs.y * 0.43), 64, Color(1, 0.9, 0.7), f_num)
	if champ.augments_pending > 0:
		_text_center("Augment available — press G", Vector2(vs.x * 0.5, vs.y * 0.5), 18, Color(0.9, 0.7, 1.0), f_bold)


func _draw_scoreboard(vs: Vector2) -> void:
	var w := 1100.0
	var h := 520.0
	var r := Rect2(vs.x * 0.5 - w * 0.5, vs.y * 0.5 - h * 0.5 - 60, w, h)
	_frame(r, Color(0.02, 0.04, 0.07, 0.95), C_GOLD, 2.0)
	_text_center("SCOREBOARD", Vector2(r.get_center().x, r.position.y + 24), 20, C_GOLD, f_title)
	for team in 2:
		var y := r.position.y + 60 + team * 230
		var col := G.COLOR_ALLY if team == champ.team else G.COLOR_ENEMY
		_text("ORDER" if team == 0 else "CHAOS", Vector2(r.position.x + 20, y), 16, col, f_title)
		var i := 0
		for c in match_ref.champions:
			if c.team != team:
				continue
			var ry := y + 14 + i * 42
			var row := Rect2(r.position.x + 14, ry, w - 28, 38)
			draw_rect(row, Color(col.r, col.g, col.b, 0.1 if c != champ else 0.25))
			var sq := Assets.champion_square(c.alias)
			if sq != null:
				draw_texture_rect(sq, Rect2(row.position + Vector2(4, 3), Vector2(32, 32)), false, Color(0.4, 0.4, 0.4) if c.dead else Color.WHITE)
			_text("%s" % c.display_name, row.position + Vector2(44, 17), 14, C_TEXT, f_bold)
			_text("Lv %d" % c.level, row.position + Vector2(44, 33), 12, C_DIM, f_body)
			_text("%d / %d / %d" % [c.kills, c.deaths, c.assists], row.position + Vector2(190, 25), 15, C_TEXT, f_num)
			_text("%d CS" % c.cs, row.position + Vector2(300, 25), 14, C_DIM, f_body)
			var ax := row.position.x + 380
			for a in c.augments:
				if a.icon != null:
					draw_texture_rect(a.icon, Rect2(ax, row.position.y + 3, 32, 32), false)
				draw_rect(Rect2(ax, row.position.y + 3, 32, 32), G.RARITY_COLORS.get(a.get("rarity"), C_GOLD), false, 1.5)
				ax += 36
			var ix := row.position.x + 620
			for it in c.items:
				if it.icon != null:
					draw_texture_rect(it.icon, Rect2(ix, row.position.y + 3, 32, 32), false)
				ix += 36
			_text("%d g" % int(c.total_gold), Vector2(row.end.x - 80, row.position.y + 25), 13, G.COLOR_GOLD, f_bold)
			i += 1


func _draw_tooltip(t: Dictionary) -> void:
	var w := 380.0
	var body: String = t.get("body", "")
	var lines := _wrap(body, w - 24, 14)
	var h := 54.0 + lines.size() * 18.0 + (18.0 if t.has("sub") and t.sub != "" else 0.0)
	var p: Vector2 = t.pos - Vector2(w * 0.5, h + 12)
	p.x = clampf(p.x, 4, size.x - w - 4)
	p.y = maxf(4, p.y)
	var r := Rect2(p, Vector2(w, h))
	var border := C_GOLD
	if t.has("rarity") and t.rarity != null:
		border = G.RARITY_COLORS.get(t.rarity, C_GOLD)
	_frame(r, Color(0.01, 0.03, 0.06, 0.97), border, 2.0)
	var tx := r.position.x + 12
	if t.get("icon") != null:
		draw_texture_rect(t.icon, Rect2(r.position + Vector2(10, 10), Vector2(34, 34)), false)
		tx += 42
	_text(t.get("title", ""), Vector2(tx, r.position.y + 32), 17, Color(0.95, 0.88, 0.65), f_title)
	var y := r.position.y + 62
	if t.has("sub") and t.sub != "":
		_text(t.sub, Vector2(r.position.x + 12, y - 4), 12, Color(0.6, 0.75, 0.95), f_bold)
		y += 18
	for ln in lines:
		_text(ln, Vector2(r.position.x + 12, y), 14, C_TEXT, f_body)
		y += 18


func _wrap(text: String, width: float, sz: int) -> Array:
	var out := []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" "):
			var test := word if line == "" else line + " " + word
			if f_body.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width and line != "":
				out.append(line)
				line = word
			else:
				line = test
		out.append(line)
	return out
