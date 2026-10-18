class_name HudScoreboard
extends RefCounted
## League's Tab scoreboard (Scoreboard/UIBase in UI.wad): your team on the left, enemies on the right,
## team kills / towers / minions header, and per-player rows with portrait, level, summoners, KDA, CS and items.

const S := "Scoreboard:"
const ROW_H := 84.0          # SB_PlayerSlotHeightRef height (source px)
const C_TEXT := Color(0.941, 0.902, 0.824)
const C_DIM := Color(0.647, 0.627, 0.588)
const C_ALLY := Color(0.42, 0.72, 1.0)
const C_ENEMY := Color(0.95, 0.35, 0.32)

var hud = null


func draw(ci: CanvasItem, L: HudLayout) -> void:
	var champ = hud.champ
	var m = hud.match_ref
	var f_num: Font = hud.f_num
	var f_title: Font = hud.f_title
	# [ui-fix] no full-screen dim: League never darkens the world behind the scoreboard; the 25% black rect that used
	# to be here popped the whole frame (minimap, HUD, world) 25% darker on Tab down and brighter again on release,
	# which read as a brightness flicker.
	L.draw(ci, S + "SB_BG")
	L.draw(ci, S + "SB_AllySide_Left", Color(1, 1, 1, 0.35))
	L.draw(ci, S + "SB_EnemySide_Right", Color(1, 1, 1, 0.35))
	L.draw(ci, S + "SB_DividerOverlay")
	var my: int = champ.team
	var k: Array = m.kills
	L.text(ci, S + "SB_TeamKills_T1Score", str(k[my]), f_num, 22, C_ALLY, 2)
	L.draw(ci, S + "SB_TeamKills_Icon1")
	L.text(ci, S + "SB_TeamKills_T2Score", str(k[1 - my]), f_num, 22, C_ENEMY, 0)
	# towers destroyed by each side
	var towers := [0, 0]
	var cs := [0, 0]
	for s in m.structures:
		if s.dead and s.kind == G.Kind.TURRET:
			towers[1 - s.team] += 1
	for c in m.champions:
		cs[c.team] += c.cs
	L.draw(ci, S + "SB_Towers_Icon1", Color(0.55, 0.75, 1.0))
	L.text(ci, S + "SB_Towers_T1Score", str(towers[my]), f_num, 17, C_TEXT, 0)
	L.draw(ci, S + "SB_Towers_Icon2", Color(1.0, 0.55, 0.5))
	L.text(ci, S + "SB_Towers_T2Score", str(towers[1 - my]), f_num, 17, C_TEXT, 0)
	L.draw(ci, S + "SB_MinionKills_Icon1")
	L.text(ci, S + "SB_MinionKills_Icon1", str(cs[my]), f_num, 17, C_TEXT, 0, Vector2(28, 0))
	L.draw(ci, S + "SB_MinionKills_Icon2")
	L.text(ci, S + "SB_MinionKills_Icon2", str(cs[1 - my]), f_num, 17, C_TEXT, 2, Vector2(-28, 0))
	var t: float = m.time
	var tr := L.r(S + "SB_TeamKills_Icon1", Vector2(0, -24))
	HudLayout.text_in(ci, Rect2(tr.position.x - 40, tr.position.y, tr.size.x + 80, tr.size.y), "%02d:%02d" % [int(t / 60.0), int(t) % 60],
		f_num, maxi(10, int(14 * L.s())), C_DIM, 1, 2.0)
	for side in 2:
		var team: int = my if side == 0 else 1 - my
		var i := 0
		for c in m.champions:
			if c.team != team:
				continue
			_row(ci, L, c, "SB_T%dP0_" % (side + 1), Vector2(0, ROW_H * i), c == champ, side == 0)
			i += 1


func _row(ci: CanvasItem, L: HudLayout, c, P: String, off: Vector2, me: bool, ally: bool) -> void:
	var f_num: Font = hud.f_num
	var f_bold: Font = hud.f_bold
	if me:
		L.draw(ci, S + P + "PlayerSlot_Self", Color.WHITE, off)
	elif c.dead:
		L.draw(ci, S + P + "PlayerSlot_Dead", Color(1, 1, 1, 0.8), off)
	var ir := L.r(S + P + "Icon_Data", off)
	HudLayout.square_icon(ci, Assets.champion_square(c.alias), ir, Color(0.4, 0.4, 0.4) if c.dead else Color.WHITE)
	L.draw(ci, S + P + ("FrameDead" if c.dead else ("FrameSelf" if me else "Frame")), Color.WHITE, off)
	L.text(ci, S + P + "Level", str(c.level), f_num, 13, C_TEXT, 1, off, 2.0)
	if c.dead:
		L.text(ci, S + P + "Timer", str(int(ceil(c.respawn_timer))), f_num, 20, Color.WHITE, 1, off)
	var ult = c.abilities[3]
	if ult != null and ult.level > 0:
		L.draw(ci, S + P + ("UltAlly" if ult.is_ready() else "UltBg"), Color.WHITE if ult.is_ready() else Color(0.45, 0.45, 0.45), off)
	for si in 2:
		var sp = c.summoners[si]
		var sr := L.r(S + P + "Spell%d_" % si, off)
		if sp != null and sp.icon != null:
			ci.draw_texture_rect(sp.icon, sr, false)
			if not sp.is_ready() and sp.cd > 0.0 and ally:
				HudLayout.radial(ci, sr, sp.cd / maxf(sp.cd_total, 0.01), Color(0, 0, 0, 0.65))
		ci.draw_rect(sr, Color(0.47, 0.35, 0.16), false, 1.0)
	L.text(ci, S + P + "SummonerName", c.display_name, f_bold, 15, C_TEXT if not me else Color(1.0, 0.9, 0.55), 0, off, 2.0)
	L.text(ci, S + P + "KDA_Text", "%d / %d / %d" % [c.kills, c.deaths, c.assists], f_num, 17, C_TEXT, 1, off, 2.0)
	L.text(ci, S + P + "CS_Text", str(c.cs), f_num, 17, C_DIM, 1, off, 2.0)
	for ii in 7:
		var key := S + P + "Item%d_Backdrop" % ii
		var r := L.draw(ci, key, Color.WHITE, off)
		if ii < 6 and ii < c.items.size() and c.items[ii].icon != null:
			ci.draw_texture_rect(c.items[ii].icon, r.grow(-r.size.x * 0.06), false)
