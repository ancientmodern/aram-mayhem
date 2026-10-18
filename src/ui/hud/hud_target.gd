class_name HudTarget
extends RefCounted
## League's target frame (TargetFrame/UIBase in UI.wad), top-left of the screen: portrait, level, HP / resource
## bars with values, the eight combat stats, CS and KDA (champions), items and buffs of the selected unit.
## Selection: left-click a unit (League select); with AutoDisplayTarget (League default) the champion you are
## attacking is shown when nothing is selected. Clicking the ground clears the selection.

const T := "Target:"
const STATS := [["AD", "TargetAD"], ["AP", "TargetAP"], ["Armor", "TargetArmor"], ["MR", "TargetMR"],
	["AS", "TargetAS"], ["AH", "TargetAH"], ["Crit", "TargetCrit"], ["MS", "TargetMS"]]

var hud = null
var selected = null
var unit = null                  ## unit currently shown
var origin := Vector2.ZERO
var k := 1.0


func on_world_click() -> void:
	var pc = hud.match_ref.player_controller if hud.match_ref != null else null
	if pc == null or pc.aiming >= 0 or pc.attack_move_armed:
		return
	var h = pc.hovered
	selected = h if h != null and h != hud.champ else null


func process() -> void:
	var u = selected
	if u != null and (not is_instance_valid(u) or u.dead or (u.team != hud.champ.team and not u.visible_to[hud.champ.team])):
		selected = null
		u = null
	if u == null:
		var at = hud.champ.attack_target
		if at != null and is_instance_valid(at) and not at.dead and at.kind == G.Kind.CHAMPION:
			u = at
	unit = u


func _st(u, n: String) -> float:
	var s = u.stats
	match n:
		"AD": return s.ad
		"AP": return s.ap
		"Armor": return s.armor
		"MR": return s.mr
		"AS": return s.attack_speed
		"AH": return s.ability_haste
		"Crit": return s.crit_chance
		"MS": return s.move_speed
	return 0.0


func sig():
	var u = unit
	if u == null or not is_instance_valid(u):
		return null
	var s := [u.get_instance_id(), int(u.hp), int(u.stats.max_hp), int(u.mana), int(u.stats.max_mana), u.level,
		int(u.total_shield())]
	for st in STATS:
		s.append(int(_st(u, st[0]) * 100.0))
	if u is Champion:
		s.append_array([u.kills, u.deaths, u.assists, u.cs, u.items.size()])
		for it in u.items:
			s.append(it.item_id)
	for b in _buffs(u):
		s.append_array([b.get_instance_id(), b.stacks, int(b.remaining * 8.0)])
	return s


func _buffs(u) -> Array:
	return u.buffs.filter(func(b): return not b.hidden and b.display_name != "" and b.show_timer)


func draw(ci) -> void:
	var u = unit
	if u == null or not is_instance_valid(u):
		return
	var L: HudLayout = hud.L
	L.begin(hud.size)
	k = L.s()
	origin = Vector2.ZERO
	var fr := L.ldraw(ci, T + "TargetBarFrame", origin, k)
	ci.solid.append(fr)
	var pr := L.lr(T + "TargetPortrait", origin, k)
	if u.kind == G.Kind.CHAMPION:
		HudLayout.circle_tex(ci, Assets.champion_square(u.alias), pr.get_center(), pr.size.x * 0.5, Color.WHITE, 1.08)
	else:
		ci.draw_circle(pr.get_center(), pr.size.x * 0.5, Color(0.04, 0.06, 0.08))
		hud.draw_unit_glyph(ci, pr.grow(-pr.size.x * 0.12), u, 1.0)
	L.ldraw(ci, T + "TargetBarPortraitFrame", origin, k)
	L.ltext_in(ci, T + "TargetLevel", L.lr(T + "TargetLevel", origin, k), str(u.level), Color(0, 0, 0, 0), 1, L.hud_scale)
	# health (green ally, red enemy) and resource bars
	var hp_key := T + ("TargetHP_BarTextureGreen" if u.team == hud.champ.team else "TargetHP_BarTextureRed")
	_bar(ci, L, hp_key, u.hp / maxf(1.0, u.stats.max_hp))
	L.ltext_in(ci, T + "TargetHP_ValueText", L.lr(T + "TargetHP_ValueText", origin, k), "%d / %d" % [mini(int(ceil(u.hp)), int(u.stats.max_hp)), int(u.stats.max_hp)],
		Color(0, 0, 0, 0), 1, L.hud_scale)
	if u.stats.max_mana > 0.0:
		var bar := "TargetPar_BarTextureBlue"
		if u is Champion:
			match u.resource_name:
				"Energy": bar = "TargetPar_BarTextureYellow"
				"Fury", "Rage", "Heat", "Bloodthirst": bar = "TargetPar_BarTextureRed"
				"Flow", "Courage": bar = "TargetPar_BarTextureWhite"
		_bar(ci, L, T + bar, u.mana / maxf(1.0, u.stats.max_mana))
		L.ltext_in(ci, T + "TargetPar_ValueText", L.lr(T + "TargetPar_ValueText", origin, k), "%d / %d" % [int(u.mana), int(u.stats.max_mana)],
			Color(0, 0, 0, 0), 1, L.hud_scale)
	# stats
	for st in STATS:
		L.ldraw(ci, T + st[1] + "_Icon", origin, k)
		var v := _st(u, st[0])
		var txt := str(int(v))
		if st[0] == "AS":
			txt = "%.2f" % v
		elif st[0] == "Crit":
			txt = "%d%%" % int(round(v * 100.0))
		L.ltext_in(ci, T + st[1] + "_Text", L.lr(T + st[1] + "_Text", origin, k), txt, Color(0, 0, 0, 0), 0, L.hud_scale)
	if u is Champion:
		L.ldraw(ci, T + "Target_CS_Icon", origin, k)
		L.ltext_in(ci, T + "Target_CS_Text", L.lr(T + "Target_CS_Text", origin, k), str(u.cs), Color(0, 0, 0, 0), 0, L.hud_scale)
		L.ldraw(ci, T + "Target_KDA_Icon", origin, k)
		L.ltext_in(ci, T + "Target_KDA_Text", L.lr(T + "Target_KDA_Text", origin, k), "%d/%d/%d" % [u.kills, u.deaths, u.assists],
			Color(0, 0, 0, 0), 0, L.hud_scale)
		for i in 7:
			var br := L.ldraw(ci, T + "TargetItem%d_Backdrop" % i, origin, k)
			if i < 6 and i < u.items.size() and u.items[i].icon != null:
				ci.draw_texture_rect(u.items[i].icon, L.lr(T + "TargetItem%d_" % i, origin, k).grow(-k), false)
				ci.hits.append([br, "item_t%d" % i])
	# buffs: positives fill from the left, negatives from the right half (League layout regions)
	var pos_i := 0
	var neg_i := 0
	var bl := _buffs(u)
	for bi in mini(bl.size(), 12):
		var b: Buff = bl[bi]
		var off := Vector2(212.0 + 36.0 * neg_i, 0) if b.is_debuff else Vector2(36.0 * pos_i, 0)
		if b.is_debuff:
			neg_i += 1
		else:
			pos_i += 1
		var ir := L.lr(T + "TargetBuffIcon", origin, k, off)
		ci.draw_rect(ir, Color(0.02, 0.04, 0.06, 0.95))
		var ic := HudBuffIcons.icon_for(b)
		if ic != null:
			ci.draw_texture_rect(ic, ir, false)
		if not b.permanent and b.duration > 0.0:
			HudLayout.radial(ci, ir, 1.0 - b.remaining / b.duration, Color(0, 0, 0, 0.6))
		L.ldraw(ci, T + ("TargetBuffBorderNegative" if b.is_debuff else "TargetBuffBorderPositive"), origin, k, Color.WHITE, off)
		if b.stacks > 1:
			L.ltext_in(ci, T + "TargetBuffStacks", L.lr(T + "TargetBuffStacks", origin, k, off), str(b.stacks), Color.WHITE, 2, L.hud_scale)
		ci.hits.append([ir, "tbuff%d" % bi])


func _bar(ci: CanvasItem, L: HudLayout, key: String, frac: float) -> void:
	var rc := L.lr(key, origin, k)
	var el := L.e(key)
	if rc.size.x <= 0.0 or not el.has("t"):
		return
	var u := L.uv_of(key)
	frac = clampf(frac, 0.0, 1.0)
	HudLayout.region(ci, el.t, Rect2(u.position, Vector2(u.size.x * frac, u.size.y)), Rect2(rc.position, Vector2(rc.size.x * frac, rc.size.y)))


func item_tip(i: int) -> Dictionary:
	var u = unit
	if u == null or not is_instance_valid(u) or not (u is Champion) or i >= u.items.size():
		return {}
	return HudTooltip.item(u.items[i].item_id, null, u.items[i])


func buff_tip(i: int) -> Dictionary:
	var u = unit
	if u == null or not is_instance_valid(u):
		return {}
	var bl := _buffs(u)
	return HudTooltip.buff(bl[i]) if i < bl.size() else {}
