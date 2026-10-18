class_name Hud
extends Control
## In-game HUD rebuilt from League's own HUD (UI.wad.client): textures, atlas UVs, positions and anchors come
## from assets/ui/hud/layout.json (tools/lol/extract_hud.py). Everything is drawn in _draw() through HudLayout.
## Pieces: player frame (portrait/XP/level, abilities, summoners, resource bars), inventory + gold/shop button,
## stats panel, buffs, top-right header, team frames, kill callouts, announcement banners, minimap,
## Tab scoreboard (hud/hud_scoreboard.gd) and League tooltips (hud/hud_tooltip.gd).

signal open_shop
signal open_augments

const PF := "PlayerFrame:"
const INV := "Inventory:"
const C_TEXT := Color(0.941, 0.902, 0.824)
const C_DIM := Color(0.647, 0.627, 0.588)
const C_GOLD := Color(0.784, 0.667, 0.431)
const C_GOLD_TXT := Color(0.98, 0.84, 0.42)
const C_CD := Color(1, 1, 1)
const C_MANA_TXT := Color(0.62, 0.8, 1.0)
const ITEM_KEYS := ["1", "2", "3", "4", "5", "6"]
## League minimap world bounds for Map12 (League units, x / z)
const MM_MIN := Vector2(-28.0, -19.0)
const MM_MAX := Vector2(12849.0, 12858.0)
const ANN_TIME := 3.2

var match_ref = null
var champ: Champion = null
var L := HudLayout.new()
var f_title: Font
var f_num: Font
var f_body: Font
var f_bold: Font
var augment_panel = null
var shop_panel = null
var scoreboard: HudScoreboard = null
var scoreboard_visible := false
var fps_visible := true
var advanced_stats := false
var fail_msg := ""
var fail_t := 0.0
var feed: Array = []                 ## kill callouts {killer, victim, assists, ally, t}
var ann_queue: Array = []            ## pending announcements
var ann: Dictionary = {}             ## current announcement {text, sub, col, t, kill?}
var _pending_kill := {}
var _pending_kill_frame := -10
var _hits: Array = []                ## [Rect2, key] hover / click regions built while drawing
var _solid: Array = []               ## Rect2 regions that swallow world clicks
var _mouse := Vector2(-1, -1)
var _hover_key := ""
var _tip: Dictionary = {}
var _tip_rect := Rect2()
var _tip_t := 0.0
var _mm_drag := false
var _mm_rect := Rect2()
var minimap_tex: Texture2D = null
var _last_level := 0
var _level_flash := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	f_title = Assets.font("beaufort", "Bold")
	f_num = Assets.font("spiegel", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_bold = Assets.font("spiegel", "Bold")
	champ = G.player
	_last_level = champ.level
	G.announcement.connect(_on_announce)
	G.champion_killed.connect(_on_kill)
	champ.cast_failed.connect(_on_cast_failed)
	minimap_tex = Assets.tex("res://assets/ui/hud/minimap_map12.png")
	# augments are disabled (Rules.AUGMENTS_ENABLED); the panel is kept dormant for when they return
	if Rules.AUGMENTS_ENABLED:
		augment_panel = AugmentPanel.new()
		augment_panel.hud = self
		add_child(augment_panel)
	shop_panel = ShopPanel.new()
	shop_panel.hud = self
	add_child(shop_panel)
	shop_panel.visible = false
	scoreboard = HudScoreboard.new()
	scoreboard.hud = self


func _process(delta: float) -> void:
	var ppt := Prof.t0()
	_process_frame(delta)
	Prof.add("proc.hud", ppt)


func _process_frame(delta: float) -> void:
	fail_t = maxf(0.0, fail_t - delta)
	_tip_t -= delta
	_level_flash = maxf(0.0, _level_flash - delta)
	if champ.level != _last_level:
		_last_level = champ.level
		_level_flash = 1.0
	for f in feed:
		f.t -= delta
	feed = feed.filter(func(f): return f.t > 0.0)
	if not ann.is_empty():
		ann.t -= delta
		if ann.t <= 0.0:
			ann = {}
	if ann.is_empty() and not ann_queue.is_empty():
		ann = ann_queue.pop_front()
	scoreboard_visible = Input.is_action_pressed("scoreboard") and not shop_panel.visible
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop"):
		toggle_shop()
		get_viewport().set_input_as_handled()
	elif Rules.AUGMENTS_ENABLED and augment_panel != null and event.is_action_pressed("augments"):
		augment_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fps"):
		fps_visible = not fps_visible
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C and not event.ctrl_pressed:
		advanced_stats = not advanced_stats


func toggle_shop() -> void:
	shop_panel.visible = not shop_panel.visible
	if shop_panel.visible:
		shop_panel.refresh()
	Sfx.ui("gold_click")


## Static helper kept for other scripts (kit_util, champ select).
static func _clean(s: String) -> String:
	return HudTooltip.clean(s)


func _on_cast_failed(_ab, reason: String) -> void:
	match reason:
		"cooldown": fail_msg = "Ability on cooldown"
		"mana": fail_msg = "Not enough mana"
		"not learned": fail_msg = "Ability not learned"
		"no target": fail_msg = "No target"
		"cc": fail_msg = "Can't cast right now"
		_: fail_msg = ""
	fail_t = 1.5 if fail_msg != "" else 0.0
	if match_ref != null and match_ref.audio != null:
		var ev := {"cooldown": "Play_sfx_hud_base_SpellFail_Cooldown", "mana": "Play_sfx_hud_base_SpellFail_NoMana",
			"cc": "Play_sfx_hud_base_SpellFail_Silence"}.get(reason, "")
		match_ref.audio.play(ev, null, -6.0, 0.0)


func _on_kill(victim, killer, assisters) -> void:
	var ally: bool = killer != null and is_instance_valid(killer) and killer.team == champ.team
	if killer == null or not is_instance_valid(killer):
		ally = victim.team != champ.team
	feed.push_front({"killer": killer if killer != null and is_instance_valid(killer) else null, "victim": victim,
		"assists": assisters.duplicate(), "ally": ally, "t": 10.0})
	if feed.size() > 5:
		feed.pop_back()
	_pending_kill = {"killer": killer if killer != null and is_instance_valid(killer) else null, "victim": victim, "ally": ally}
	_pending_kill_frame = Engine.get_process_frames()


func _on_announce(text: String, sub: String, col: Color) -> void:
	var a := {"text": text, "sub": sub, "col": col, "t": ANN_TIME}
	if Engine.get_process_frames() - _pending_kill_frame <= 1 and not _pending_kill.is_empty():
		a["kill"] = _pending_kill
		a.sub = ""
		_pending_kill = {}
	if ann_queue.size() > 3:
		ann_queue.pop_front()
	ann_queue.append(a)


# ===================================================================== input
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _mm_drag and _mm_rect.has_point(_mouse):
			_minimap_camera(_mouse)
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mm_drag = false
		return
	var mp := mb.position
	if _mm_rect.has_point(mp):
		var wp := minimap_to_world(mp)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mm_drag = true
			_minimap_camera(mp)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			champ.issue_move(match_ref.nav.nearest_walkable(wp))
		accept_event()
		return
	for h in _hits:
		if not (h[0] as Rect2).has_point(mp):
			continue
		var k: String = h[1]
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if k.begins_with("lvl"):
				champ.level_ability(int(k.substr(3)))
				Sfx.ui("gold_click")
			elif k == "shop":
				toggle_shop()
			elif k == "stats_btn":
				advanced_stats = not advanced_stats
		accept_event()
		return
	for r in _solid:
		if (r as Rect2).has_point(mp):
			accept_event()
			return


func _minimap_camera(mp: Vector2) -> void:
	var wp := minimap_to_world(mp)
	match_ref.camera_rig.locked = false
	match_ref.camera_rig.focus = Vector3(wp.x, match_ref.nav.height_at(wp), wp.z)


func _has_point_ui(mp: Vector2) -> bool:
	if _mm_rect.has_point(mp):
		return true
	for r in _solid:
		if (r as Rect2).has_point(mp):
			return true
	return false


func _update_hover() -> void:
	var key := ""
	var rect := Rect2()
	for i in range(_hits.size() - 1, -1, -1):
		var h = _hits[i]
		if (h[0] as Rect2).has_point(_mouse):
			key = h[1]
			rect = h[0]
			break
	if key != _hover_key or _tip_t <= 0.0:
		_hover_key = key
		_tip_rect = rect
		_tip = _build_tip(key)
		_tip_t = 0.4


func _build_tip(k: String) -> Dictionary:
	if k == "":
		return {}
	if k in ["P", "Q", "W", "E", "R", "D", "F"]:
		return HudTooltip.ability(champ, k)
	if k.begins_with("item"):
		var i := int(k.substr(4))
		if i < champ.items.size():
			return HudTooltip.item(champ.items[i].item_id, champ, champ.items[i])
		return {}
	if k.begins_with("buff"):
		var vis := _visible_buffs()
		var bi := int(k.substr(4))
		return HudTooltip.buff(vis[bi]) if bi < vis.size() else {}
	if k.begins_with("lvl"):
		return HudTooltip.simple("Level Up", "Spend a skill point on this ability (Ctrl + key).")
	if k == "shop":
		return HudTooltip.simple("Shop [P]", "Buy items while dead or on the spawn platform." if not champ.can_shop()
			else "You are in base: you can buy items now.")
	if k.begins_with("stat:"):
		return HudTooltip.simple(k.substr(5), "")
	if k.begins_with("ally:"):
		var c = _ally_by_uid(int(k.substr(5)))
		if c != null:
			return HudTooltip.simple(c.display_name, "Level %d   %d / %d / %d" % [c.level, c.kills, c.deaths, c.assists])
	return {}


func _ally_by_uid(uid: int):
	for c in match_ref.champions:
		if c.uid == uid:
			return c
	return null


# ===================================================================== drawing
func _draw() -> void:
	var pt := Prof.t0()
	_draw_frame()
	Prof.add("draw.hud", pt)


func _draw_frame() -> void:
	if champ == null:
		return
	L.begin(size)
	_hits.clear()
	_solid.clear()
	_draw_header()
	_draw_team_frames()
	_draw_minimap()
	_draw_kill_feed()
	_draw_stats()
	_draw_player_frame()
	_draw_inventory()
	_draw_buffs()
	_draw_announcement()
	if fail_t > 0.0:
		var a := minf(1.0, fail_t * 2.5)
		L.text(self, PF + "StatusMessageToolTip", fail_msg, f_bold, 18, Color(1.0, 0.42, 0.36, a), 1)
	if scoreboard_visible:
		scoreboard.draw(self, L)
	elif not shop_panel.visible:
		_update_hover()
		if not _tip.is_empty():
			HudTooltip.draw(self, _tip, _tip_rect, size, size.y / 1080.0)


# --------------------------------------------------------------------- header (top right)
func _draw_header() -> void:
	var H := "Header:"
	L.draw(self, H + "TB_Frame")
	var my := champ.team
	var k: Array = match_ref.kills
	L.text(self, H + "TB_TeamKills_T1Score", str(k[my]), f_num, 15, Color(0.42, 0.72, 1.0), 2)
	L.draw(self, H + "TB_TeamKills_Icon1")
	L.text(self, H + "TB_TeamKills_T2Score", str(k[1 - my]), f_num, 15, Color(0.95, 0.35, 0.32), 0)
	L.draw(self, H + "TB_Player_KDA_Icon")
	L.text(self, H + "TB_Player_KDA_Text", "%d/%d/%d" % [champ.kills, champ.deaths, champ.assists], f_num, 15, C_TEXT, 0)
	L.draw(self, H + "TB_Player_CS_Icon")
	L.text(self, H + "TB_Player_CS_Text", str(champ.cs), f_num, 15, C_TEXT, 0)
	L.draw(self, H + "GameTimeIcon")
	var t: float = match_ref.time
	L.text(self, H + "GameTime", "%02d:%02d" % [int(t / 60.0), int(t) % 60], f_num, 15, C_TEXT, 0)
	if fps_visible:
		# League's FPS / latency readout under the header
		var fr := L.r(H + "GameTime")
		var y := fr.end.y + fr.size.y * 0.9
		var s := "FPS: %d     %d ms" % [Engine.get_frames_per_second(), 0]
		var px := maxi(10, int(13 * L.scale_of(L.e(H + "GameTime"))))
		var w := f_num.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		HudLayout.text_in(self, Rect2(size.x - w - 10.0, y - px * 0.5, w, px), s, f_num, px, Color(0.75, 0.9, 0.6), 0)


# --------------------------------------------------------------------- team frames (right, above minimap)
func _draw_team_frames() -> void:
	var T := "TeamFrames:"
	var i := 0
	for c in match_ref.champions:
		if c.team != champ.team or c == champ:
			continue
		var off := Vector2(0, -82.0 * i)
		var dead: bool = c.dead
		L.draw(self, T + ("TeamFrame0_FrameDeadUnderlay" if dead else "TeamFrame0_FrameUnderlay"), Color.WHITE, off)
		var ir := L.r(T + "TeamFrame0_Icon_Data", off)
		HudLayout.square_icon(self, Assets.champion_square(c.alias), ir, Color(0.4, 0.4, 0.4) if dead else Color.WHITE)
		L.draw(self, T + "TeamFrame0_HPBackdrop", Color.WHITE, off)
		_fill_h_off(T + "TeamFrame0_HPBarTextureGreen", c.hp_ratio(), off)
		if c.stats.max_mana > 0.0:
			_fill_h_off(T + "TeamFrame0_PARBarTextureBlue", c.mana / maxf(1.0, c.stats.max_mana), off)
		L.draw(self, T + "TeamFrame0_HPFrame", Color.WHITE, off)
		var fr := L.draw(self, T + ("TeamFrame0_FrameDead" if dead else "TeamFrame0_Frame"), Color.WHITE, off)
		var ult: Ability = c.abilities[3]
		if ult != null and ult.level > 0:
			L.draw(self, T + "TeamFrame0_UltBg", Color.WHITE, off)
			if ult.is_ready():
				L.draw(self, T + "TeamFrame0_Ult", Color.WHITE, off)
			else:
				var ur := L.r(T + "TeamFrame0_UltCooldownFX", off)
				HudLayout.radial(self, ur, ult.cd / maxf(ult.cd_total, 0.01), Color(0, 0, 0, 0.75))
		L.text(self, T + "TeamFrame0_Level", str(c.level), f_num, 11, C_TEXT, 1, off)
		if dead:
			L.text(self, T + "TeamFrame0_Timer", str(int(ceil(c.respawn_timer))), f_num, 20, Color(1, 1, 1), 1, off + Vector2(0, -30))
		_hits.append([fr, "ally:%d" % c.uid])
		i += 1


func _fill_h_off(key: String, frac: float, off: Vector2) -> void:
	var el := L.e(key)
	if el.is_empty():
		return
	var rc := L.rect_of(el, off)
	var uv: Array = el.uv
	frac = clampf(frac, 0.0, 1.0)
	HudLayout.region(self, el.t, Rect2(uv[0], uv[1], (uv[2] - uv[0]) * frac, uv[3] - uv[1]),
		Rect2(rc.position, Vector2(rc.size.x * frac, rc.size.y)))


# --------------------------------------------------------------------- kill callouts (right side)
func _draw_kill_feed() -> void:
	var K := "Kill:KillCallout0_"
	var i := 0
	for f in feed:
		var off := Vector2(0, 70.0 * i)
		var a := clampf(f.t / 0.6, 0.0, 1.0) * clampf((10.0 - f.t) / 0.15, 0.0, 1.0)
		var tint: Color = Color(0.12, 0.38, 0.78, 0.9 * a) if f.ally else Color(0.72, 0.14, 0.14, 0.9 * a)
		L.draw(self, K + "Background", tint, off)
		var w := Color(1, 1, 1, a)
		var killer = f.killer
		var kr := L.r(K + "KillerPortrait", off)
		if killer != null and killer.kind == G.Kind.CHAMPION:
			HudLayout.square_icon(self, Assets.champion_square(killer.alias), kr, w)
		else:
			_draw_unit_glyph(kr, killer, a)
		L.draw(self, K + "KillerFrame", w, off)
		L.draw(self, K + "KillIconNormal", w, off)
		HudLayout.square_icon(self, Assets.champion_square(f.victim.alias), L.r(K + "TargetPortrait", off), w)
		L.draw(self, K + "TargetFrame", w, off)
		var ai := 0
		for asst in f.assists:
			if ai > 3 or not is_instance_valid(asst):
				break
			HudLayout.square_icon(self, Assets.champion_square(asst.alias), L.r(K + "Assister%dPortrait" % ai, off), w)
			L.draw(self, K + "Assister%dFrame" % ai, w, off)
			ai += 1
		i += 1


func _draw_unit_glyph(r: Rect2, u, a: float) -> void:
	draw_rect(r, Color(0.05, 0.07, 0.09, a))
	var icon := "icon_ui_tower_minimap"
	if u != null and is_instance_valid(u) and u.kind == G.Kind.MINION:
		icon = "minionmapcircle"
	var t := Assets.tex("res://assets/ui/hud/icons/%s.png" % icon)
	if t != null:
		draw_texture_rect(t, r.grow(-r.size.x * 0.18), false, Color(0.9, 0.9, 0.9, a))


# --------------------------------------------------------------------- stats panel (left of portrait)
func _draw_stats() -> void:
	var st := champ.stats
	var S := "Stats:"
	var pr := L.draw(self, S + "StatsBg")
	_solid.append(pr)
	var rows := [
		["AD", str(int(st.ad)), "Attack Damage"], ["AP", str(int(st.ap)), "Ability Power"],
		["Armor", str(int(st.armor)), "Armor"], ["MR", str(int(st.mr)), "Magic Resist"],
		["AS", "%.2f" % st.attack_speed, "Attack Speed"], ["AH", str(int(st.ability_haste)), "Ability Haste"],
		["Crit", "%d%%" % int(round(st.crit_chance * 100.0)), "Critical Strike Chance"], ["MS", str(int(st.move_speed)), "Move Speed"],
	]
	for row in rows:
		L.draw(self, S + "Stats_%s_Icon" % row[0])
		L.text(self, S + "Stats_%s_Text" % row[0], row[1], f_num, 14, C_TEXT, 0)
		_hits.append([L.r(S + "Stats_%s_HitArea" % row[0]), "stat:%s: %s" % [row[2], row[1]]])
	var br := L.draw(self, PF + ("Stats_ButtonSelected" if advanced_stats else "Stats_ButtonDefault"))
	_hits.append([br, "stats_btn"])
	if advanced_stats:
		_solid.append(L.draw(self, S + "AdvancedStatsBg"))
		var adv := [
			["HPR", "%.1f" % (st.hp_regen * 5.0), "Health Regen (per 5s)"], ["HSP", "%d%%" % int(st.heal_power * 100.0), "Heal and Shield Power"],
			["APen", "%d | %d%%" % [int(st.lethality), int(st.armor_pen_pct * 100.0)], "Lethality | Armor Pen"],
			["MPen", "%d | %d%%" % [int(st.magic_pen), int(st.magic_pen_pct * 100.0)], "Magic Pen"],
			["LS", "%d%%" % int(st.lifesteal * 100.0), "Life Steal"], ["SV", "%d%%" % int(st.omnivamp * 100.0), "Omnivamp"],
			["AR", str(int(st.attack_range)), "Attack Range"], ["Ten", "%d%%" % int(st.tenacity * 100.0), "Tenacity"],
		]
		for row in adv:
			L.draw(self, S + "Stats_%s_Icon" % row[0])
			L.text(self, S + "Stats_%s_Text" % row[0], row[1], f_num, 14, C_TEXT, 0)
			_hits.append([L.r(S + "Stats_%s_HitArea" % row[0]), "stat:%s: %s" % [row[2], row[1]]])


# --------------------------------------------------------------------- player frame (portrait, spells, bars)
func _draw_player_frame() -> void:
	var cf := L.draw(self, PF + "HUDCenterFrame")
	_solid.append(cf)
	# portrait + XP
	L.draw(self, PF + "PortraitFrameUnderlay")
	var pr := L.r(PF + "PlayerIcon_Base")
	var sq := Assets.champion_square(champ.alias)
	HudLayout.circle_tex(self, sq, pr.get_center(), pr.size.x * 0.5, Color(0.38, 0.38, 0.38) if champ.dead else Color.WHITE, 1.08)
	L.draw(self, PF + "PlayerExp_Backdrop")
	L.fill_v(self, PF + "PlayerExp_BarTexture", champ.xp_ratio() if champ.level < 18 else 1.0)
	var frame := L.draw(self, PF + "PortraitFrame_Default")
	_solid.append(frame)
	var lvl_col := C_TEXT.lerp(Color(1.0, 0.9, 0.45), _level_flash)
	L.text(self, PF + "PlayerLevel", str(champ.level), f_num, 13, lvl_col, 1, Vector2.ZERO, 2.0)
	if champ.dead:
		L.text(self, PF + "PlayerRespawnTimer", str(int(ceil(champ.respawn_timer))), f_title, 40, Color(1, 1, 1), 1, Vector2(-13, 0))
	# abilities
	_draw_spell_slot("Passive", -1)
	for i in 4:
		_draw_spell_slot("Ability%d" % i, i)
	for i in 2:
		_draw_spell_slot("Summoner%d" % i, 4 + i)
	# level-up buttons
	for i in 4:
		if champ.can_level_ability(i):
			var key := PF + "LevelUp%d_Button" % i
			var r := L.r(key + "Default")
			var hov := r.has_point(_mouse)
			L.draw(self, key + ("Hover" if hov else "Default"))
			var pulse := 0.35 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
			L.draw(self, PF + "LevelUp%d_IdleGlow" % i, Color(1, 1, 1, pulse))
			_hits.append([r, "lvl%d" % i])
	_draw_resource_bars()


func _ability_for(slot: int) -> Ability:
	if slot < 0:
		return null
	if slot < 4:
		return champ.abilities[slot]
	return champ.summoners[slot - 4]


func _draw_spell_slot(base: String, slot: int) -> void:
	var P := PF + base
	var ab := _ability_for(slot)
	var icon_r := L.r(P + "_")
	var key: String = "P" if slot < 0 else ("QWER"[slot] if slot < 4 else ("D" if slot == 4 else "F"))
	var icon: Texture2D = null
	if slot < 0:
		icon = champ.passive.icon if champ.passive != null and champ.passive.get("icon") != null else Assets.ability_icon(champ.alias, "p")
	elif ab != null:
		icon = ab.icon
	var learned := slot < 0 or (ab != null and (ab.is_summoner or ab.level > 0))
	var on_cd := ab != null and learned and not ab.is_ready() and ab.cd > 0.0
	var oom := ab != null and learned and not on_cd and not ab.can_afford()
	if icon != null:
		var mod := Color.WHITE
		if not learned:
			mod = Color(0.35, 0.35, 0.35)
		elif oom:
			mod = Color(0.5, 0.62, 1.0)
		draw_texture_rect(icon, icon_r, false, mod)
	if not learned:
		L.draw(self, P + "_OverlayUnavailable")
	if oom:
		L.draw(self, P + "_IconOom", Color(1, 1, 1, 0.45))   # League's blue out-of-mana overlay
	if on_cd:
		var el := L.e(P + "_CooldownFX")
		var uv: Array = el.get("uv", [884, 955, 948, 1019])
		HudLayout.radial(self, L.rect_of(el), ab.cd / maxf(ab.cd_total, 0.01), Color(1, 1, 1, 0.92), el.get("t", ""),
			Rect2(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1]))
	if ab != null and ab.toggled:
		draw_rect(icon_r.grow(-1.0), Color(0.45, 0.85, 1.0, 0.85), false, maxf(2.0, icon_r.size.x * 0.05))
	var hov := icon_r.has_point(_mouse) and not scoreboard_visible
	if hov:
		L.draw(self, P + "_Mouseover", Color(1, 1, 1, 0.35))
	L.draw(self, P + ("_BorderAvailable" if learned and not on_cd else "_BorderUnavailable"))
	# recast window: League shows a timer bar above the slot and a gold sweep on the border
	if ab != null and ab.recast_window > 0.0:
		var tb := L.r(P + "_TimerBar_BarTexture")
		if tb.size.x > 0.0:
			L.draw(self, P + "_TimerBar_Backdrop")
			var frac := clampf(ab.recast_window / maxf(ab.get("recast_total") if ab.get("recast_total") != null else 3.0, 0.1), 0.0, 1.0)
			L.fill_h(self, P + "_TimerBar_BarTexture", frac)
		var pulse := 0.5 + 0.3 * sin(Time.get_ticks_msec() * 0.012)
		draw_rect(icon_r.grow(1.0), Color(1.0, 0.85, 0.35, pulse), false, 2.0)
	if on_cd:
		var cds := ("%.1f" % ab.cd) if ab.cd < 1.0 else str(int(ceil(ab.cd)))
		L.text(self, P + "_Cooldown", cds, f_num, 22 if slot >= 0 and slot < 4 else 17, C_CD, 1)
	if ab != null and ab.max_charges > 0 and learned:
		L.draw(self, P + ("_CooldownGemAvailable" if ab.charges > 0 else "_CooldownGemUnavailable"))
		L.text(self, P + "_CooldownGem", str(ab.charges), f_num, 12, Color(1, 1, 0.85), 1)
	# mana cost (top right chip) and hotkey (bottom left)
	if ab != null and slot >= 0 and slot < 4 and learned and ab.cost() > 0.0 and champ.stats.uses_mana:
		L.draw(self, P + "_CostBg")
		L.text(self, P + "_Cost", str(int(ab.cost())), f_num, 13, C_MANA_TXT if not oom else Color(0.55, 0.6, 1.0), 2, Vector2.ZERO, 2.0)
	if slot >= 0:
		L.text(self, P + "_HotKey", key, f_num, 12, C_TEXT, 1, Vector2.ZERO, 2.0)
	if slot >= 0 and slot < 4 and ab != null:
		_draw_pips(slot, ab)
	if slot < 0 and champ.passive != null and champ.passive.has_method("hud_counter"):
		var cnt: String = champ.passive.hud_counter()
		if cnt != "":
			HudLayout.text_in(self, Rect2(icon_r.position + Vector2(0, icon_r.size.y * 0.55), Vector2(icon_r.size.x, icon_r.size.y * 0.45)),
				cnt, f_num, maxi(10, int(icon_r.size.y * 0.32)), Color.WHITE, 1, 3.0)
	_hits.append([L.r(P + "_BorderAvailable"), key])


func _draw_pips(slot: int, ab: Ability) -> void:
	var pr := L.r(PF + "Ability%d_PipRect" % slot)
	var n := ab.max_level
	if n <= 0 or pr.size.x <= 0.0:
		return
	var pe := L.e(PF + "Ability%d_EmptyPip0" % slot)
	var pip := Vector2(float(pe.s[0]), float(pe.s[1])) * L.scale_of(pe)
	var gap := (pr.size.x - pip.x * n) / maxf(1.0, n - 1) if n > 1 else 0.0
	gap = minf(gap, pip.x * 0.9)
	var total := pip.x * n + gap * (n - 1)
	var x := pr.get_center().x - total * 0.5
	for p in n:
		var rc := Rect2(Vector2(x + p * (pip.x + gap), pr.position.y), pip)
		L.draw_in(self, PF + ("Ability%d_FullPip0" % slot if p < ab.level else "Ability%d_EmptyPip0" % slot), rc)


func _draw_resource_bars() -> void:
	var H := PF + "PlayerHP_"
	L.draw(self, H + "Backdrop")
	var mx := champ.stats.max_hp
	var shield := champ.total_shield()
	var total := maxf(mx, champ.hp + shield)
	var hp_frac := champ.hp / maxf(total, 1.0)
	var hr := L.fill_h(self, H + "BarTextureGreen", hp_frac)
	if shield > 0.0:
		var el := L.e(PF + "PlayerPar_BarTextureWhite")
		var full := L.r(H + "BarTextureGreen")
		var sw := shield / maxf(total, 1.0)
		var uv: Array = el.uv
		HudLayout.region(self, el.t, Rect2(uv[0], uv[1], (uv[2] - uv[0]) * sw, uv[3] - uv[1]),
			Rect2(Vector2(hr.end.x if hr.size.x > 0 else full.position.x, full.position.y), Vector2(full.size.x * sw, full.size.y)))
	L.draw(self, H + "BookendLeft")
	L.draw(self, H + "BookendRight")
	L.text(self, H + "ValueText", "%d / %d" % [mini(int(ceil(champ.hp)), int(mx)), int(mx)], f_num, 13, C_TEXT, 1, Vector2.ZERO, 2.0)
	if champ.stats.hp_regen > 0.0 and champ.hp < mx and not champ.dead:
		L.text(self, H + "RegenText", "+%.1f" % (champ.stats.hp_regen * 5.0), f_body, 12, Color(0.8, 0.95, 0.8), 2, Vector2.ZERO, 2.0)
	var M := PF + "PlayerPar_"
	L.draw(self, M + "Backdrop")
	if champ.stats.max_mana > 0.0:
		var bar := "BarTextureBlue"
		match champ.resource_name:
			"Energy": bar = "BarTextureYellow"
			"Fury", "Rage", "Heat", "Bloodthirst": bar = "BarTextureRed"
			"Flow", "Courage": bar = "BarTextureWhite"
		L.fill_h(self, M + bar, champ.mana / champ.stats.max_mana)
		L.text(self, M + "ValueText", "%d / %d" % [int(champ.mana), int(champ.stats.max_mana)], f_num, 13, C_TEXT, 1, Vector2.ZERO, 2.0)
		if champ.stats.mana_regen > 0.0 and champ.mana < champ.stats.max_mana and not champ.dead:
			L.text(self, M + "RegenText", "+%.1f" % (champ.stats.mana_regen * 5.0), f_body, 12, Color(0.8, 0.88, 1.0), 2, Vector2.ZERO, 2.0)
	L.draw(self, M + "BookendLeft")
	L.draw(self, M + "BookendRight")


# --------------------------------------------------------------------- inventory + gold
func _draw_inventory() -> void:
	_solid.append(L.draw(self, INV + "InventoryFrame"))
	for i in 7:
		var P := INV + "InventoryItem%d_" % i
		L.draw(self, P + "Backdrop")
		var r := L.r(P + "Backdrop")
		var it = champ.items[i] if i < 6 and i < champ.items.size() else null
		if it != null:
			var ir := L.r(P + "Border").grow(-L.s() * 2.0)
			if it.icon != null:
				draw_texture_rect(it.icon, ir, false)
			if it.has_method("cooldown_ratio") and it.cooldown_ratio() > 0.0:
				var el := L.e(P + "CooldownFX")
				var uv: Array = el.uv
				HudLayout.radial(self, ir, it.cooldown_ratio(), Color(1, 1, 1, 0.92), el.t, Rect2(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1]))
				L.text(self, P + "Cooldown", str(int(ceil(it.active_left))), f_num, 15, C_CD, 1)
			if r.has_point(_mouse):
				L.draw(self, P + "Mouseover", Color(1, 1, 1, 0.3))
			L.draw(self, P + ("Enabled" if it.has_method("has_active") and it.has_active() else "Border"))
			_hits.append([r, "item%d" % i])
		if i < 6:
			L.text(self, P + "HotKey", ITEM_KEYS[i], f_num, 11, C_DIM, 1, Vector2.ZERO, 2.0)
	# recall slot: no recall in ARAM, shown disabled like League's HUD frame
	L.draw(self, INV + "Recall_Disabled")
	L.text(self, INV + "Recall_HotKey", "B", f_num, 11, C_DIM, 1, Vector2.ZERO, 2.0)
	# shop / gold button (League's gold bar from the HUD atlas)
	var hr := L.r(INV + "Shop_HitArea")
	var can := champ.can_shop()
	var hov := hr.has_point(_mouse)
	var uv := Rect2(209, 603, 198, 33) if hov or shop_panel.visible else Rect2(6, 603, 198, 33)
	HudLayout.region(self, "clarity_hudatlas", uv, hr, Color.WHITE if can or hov else Color(0.85, 0.85, 0.85))
	if can:
		var pulse := 0.25 + 0.2 * sin(Time.get_ticks_msec() * 0.005)
		draw_rect(hr.grow(-1.0), Color(1.0, 0.85, 0.4, pulse), false, 1.5)
	L.text(self, INV + "Shop_GoldText", str(int(champ.gold)), f_num, 16, C_GOLD_TXT, 1, Vector2.ZERO, 2.0)
	L.text(self, INV + "Shop_HotKey", "P", f_num, 11, C_DIM, 1, Vector2.ZERO, 2.0)
	_hits.append([hr, "shop"])


# --------------------------------------------------------------------- buffs
func _visible_buffs() -> Array:
	return champ.buffs.filter(func(b): return not b.hidden and b.display_name != "" and b.show_timer)


## League shows the icon of the spell that applied a buff. Buffs created without an icon fall back to the
## source champion's matching ability (by id / name), then to the source champion's portrait.
func _buff_icon(b: Buff) -> Texture2D:
	if b.icon != null:
		return b.icon
	if b.has_meta("_hud_icon"):
		return b.get_meta("_hud_icon")
	var t: Texture2D = null
	var src = b.source
	if src != null and is_instance_valid(src) and src is Champion:
		var bid := (b.id + " " + b.display_name).to_lower()
		for ab in src.abilities:
			if ab != null and ab.icon != null and ((ab.id != "" and bid.contains(ab.id.to_lower())) or (ab.display_name != "" and bid.contains(ab.display_name.to_lower()))):
				t = ab.icon
				break
		if t == null:
			t = Assets.champion_square(src.alias)
	b.set_meta("_hud_icon", t)
	return t


func _draw_buffs() -> void:
	var vis := _visible_buffs()
	var pos_i := 0
	var neg_i := 0
	var B := PF + "PlayerBuff"
	for idx in mini(vis.size(), 16):
		var b: Buff = vis[idx]
		var off: Vector2
		if b.is_debuff:
			off = Vector2(500.0 - 44.0 * neg_i, 0)    # debuffs fill from the right end of the bar
			neg_i += 1
		else:
			off = Vector2(44.0 * pos_i, 0)
			pos_i += 1
		var ir := L.r(B + "Icon", off)
		draw_rect(ir, Color(0.02, 0.04, 0.06, 0.95))
		var bic := _buff_icon(b)
		if bic != null:
			draw_texture_rect(bic, ir, false)
		else:
			HudLayout.text_in(self, ir, b.display_name.substr(0, 2), f_bold, maxi(9, int(ir.size.y * 0.4)), C_TEXT, 1, 2.0)
		if not b.permanent and b.duration > 0.0:
			HudLayout.radial(self, ir, 1.0 - b.remaining / b.duration, Color(0, 0, 0, 0.6))
		L.draw(self, B + ("BorderNegative" if b.is_debuff else "BorderPositive"), Color.WHITE, off)
		if b.stacks > 1:
			L.text(self, B + "Stacks", str(b.stacks), f_num, 13, Color.WHITE, 2, off, 2.0)
		_hits.append([ir, "buff%d" % idx])


# --------------------------------------------------------------------- announcement banners (top center)
func _draw_announcement() -> void:
	if ann.is_empty():
		return
	var t: float = ann.t
	var age := ANN_TIME - t
	var a := clampf(age / 0.18, 0.0, 1.0) * clampf(t / 0.45, 0.0, 1.0)
	var pop := 1.0 + maxf(0.0, 0.18 - age) * 1.4
	var B := "Banner:"
	var w := Color(1, 1, 1, a)
	var text: String = ann.text
	var up := text.to_upper()
	if ann.has("kill"):
		var k: Dictionary = ann.kill
		var ally: bool = k.ally
		var bg := ""
		if up.begins_with("DOUBLE"):
			bg = "DoubleKill"
		elif up.begins_with("TRIPLE"):
			bg = "TripleKill"
		elif up.begins_with("QUADRA"):
			bg = "QuadraKill"
		elif up.begins_with("PENTA"):
			bg = "Pentakill"
		if bg != "":
			L.draw(self, B + bg + ("BlueBG" if ally else "RedBG"), w)
		L.draw(self, B + ("AnnBannerBlue_Underline" if ally else "AnnBannerRed_Underline"), w)
		var killer = k.killer
		var victim = k.victim
		var lr := L.r(B + "AnnBannerLeftIcon_content")
		if killer != null and is_instance_valid(killer) and killer.kind == G.Kind.CHAMPION:
			HudLayout.circle_tex(self, Assets.champion_square(killer.alias), lr.get_center(), lr.size.x * 0.5 * pop, w, 1.1)
		else:
			draw_circle(lr.get_center(), lr.size.x * 0.5, Color(0.05, 0.07, 0.1, a))
			_draw_unit_glyph(lr.grow(-lr.size.x * 0.12), killer, a)
		var rr := L.r(B + "AnnBannerRightIcon_content")
		if victim != null and is_instance_valid(victim):
			HudLayout.circle_tex(self, Assets.champion_square(victim.alias), rr.get_center(), rr.size.x * 0.5 * pop, Color(0.85, 0.85, 0.85, a), 1.1)
		L.draw(self, B + ("AnnBannerLeftGlowBlue" if ally else "AnnBannerLeftGlowRed"), w)
		L.draw(self, B + ("RightIconGlowRed" if ally else "RightIconGlowBlue"), w)
		L.draw(self, B + "AnnBannerLeftIcon_gold_ring", w)
		L.draw(self, B + "AnnBannerRightIcon_gold_ring", w)
		_banner_text(up, 222.0, 30.0 * pop, a)
	else:
		L.draw(self, B + "AnnBannerGold_Underline", w)
		_banner_text(up, 176.0, 28.0 * pop, a)
		if ann.sub != "":
			_banner_text(String(ann.sub), 214.0, 16.0, a, f_bold, C_DIM)


func _banner_text(s_txt: String, y_src: float, size_src: float, a: float, font: Font = null, col := Color(0.97, 0.93, 0.84)) -> void:
	var sc := L.s()
	var px := maxi(12, int(size_src * sc))
	var f := font if font != null else f_title
	var c := Vector2(size.x * 0.5, L.pt("Banner:AnnBannerGold_Underline", Vector2(800, y_src)).y)
	var wdt := f.get_string_size(s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pos := Vector2(c.x - wdt * 0.5, c.y + px * 0.35)
	draw_string_outline(f, pos, s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, maxi(3, int(px * 0.16)), Color(0, 0, 0, 0.75 * a))
	draw_string(f, pos, s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(col.r, col.g, col.b, a))


# --------------------------------------------------------------------- minimap
func world_to_minimap(p: Vector3) -> Vector2:
	var lx := p.x / G.U
	var lz := -p.z / G.U
	var u := (lx - MM_MIN.x) / (MM_MAX.x - MM_MIN.x)
	var v := 1.0 - (lz - MM_MIN.y) / (MM_MAX.y - MM_MIN.y)
	return _mm_rect.position + Vector2(u, v) * _mm_rect.size


func minimap_to_world(sp: Vector2) -> Vector3:
	var k := (sp - _mm_rect.position) / _mm_rect.size
	var lx := MM_MIN.x + k.x * (MM_MAX.x - MM_MIN.x)
	var lz := MM_MIN.y + (1.0 - k.y) * (MM_MAX.y - MM_MIN.y)
	return Vector3(lx * G.U, 0.0, -lz * G.U)


func _icon(name: String) -> Texture2D:
	return Assets.tex("res://assets/ui/hud/icons/%s.png" % name)


func _draw_minimap() -> void:
	var M := "Minimap:"
	_mm_rect = L.r(M + "MinimapContent")
	if minimap_tex != null:
		draw_texture_rect(minimap_tex, _mm_rect, false)
	var u_scale := _mm_rect.size.x / 283.0
	# structures
	for s in match_ref.structures:
		if s.dead:
			continue
		if s.get("tier") != null and s.tier == Turret.Tier.FOUNTAIN:
			continue
		var p := world_to_minimap(s.global_position)
		var col := Color(0.35, 0.68, 1.0) if s.team == champ.team else Color(1.0, 0.33, 0.3)
		var ic := "icon_ui_tower_minimap"
		var sz := 22.0
		if s.kind == G.Kind.INHIBITOR:
			ic = "icon_ui_inhibitor_minimap_v2"
			sz = 22.0
		elif s.kind == G.Kind.NEXUS:
			ic = "icon_ui_nexus_minimap_v2"
			sz = 26.0
		elif s.has_method("hp_ratio"):
			var hr: float = s.hp_ratio()
			ic = "icon_ui_tower_minimap" if hr > 0.66 else ("icon_ui_tower_minimap_med" if hr > 0.33 else "icon_ui_tower_minimap_low")
		var t := _icon(ic)
		var d := sz * u_scale
		if t != null:
			draw_texture_rect(t, Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)), false, col)
	# relics (health packs)
	var hp_icon := _icon("healthpack")
	for r in match_ref.relics:
		if r.active and hp_icon != null:
			var d2 := 16.0 * u_scale
			draw_texture_rect(hp_icon, Rect2(world_to_minimap(r.global_position) - Vector2(d2, d2) * 0.5, Vector2(d2, d2)), false)
	# minions
	var dot := _icon("minionmapcircle")
	for u in match_ref.units:
		if u.dead or u.kind != G.Kind.MINION:
			continue
		if u.team != champ.team and not u.visible_to[champ.team]:
			continue
		var p2 := world_to_minimap(u.global_position)
		var d3 := 5.0 * u_scale
		var mc := Color(0.35, 0.65, 1.0) if u.team == champ.team else Color(1.0, 0.3, 0.28)
		if dot != null:
			draw_texture_rect(dot, Rect2(p2 - Vector2(d3, d3) * 0.5, Vector2(d3, d3)), false, mc)
		else:
			draw_circle(p2, d3 * 0.5, mc)
	# champions (enemies first, self last on top)
	var order: Array = match_ref.champions.duplicate()
	order.sort_custom(func(a, b): return (0 if a.team != champ.team else (2 if a == champ else 1)) < (0 if b.team != champ.team else (2 if b == champ else 1)))
	for c in order:
		if c.dead:
			continue
		if c.team != champ.team and not c.visible_to[champ.team]:
			continue
		var p3 := world_to_minimap(c.global_position)
		var rad := 12.0 * u_scale
		HudLayout.circle_tex(self, Assets.champion_square(c.alias), p3, rad, Color.WHITE, 1.12)
		var ring := Color(0.25, 0.62, 1.0) if c.team == champ.team else Color(0.95, 0.22, 0.2)
		if c == champ:
			ring = Color(1.0, 0.86, 0.3)
		draw_arc(p3, rad, 0.0, TAU, 32, ring, maxf(1.5, 2.2 * u_scale), true)
	_draw_camera_box()
	L.draw(self, M + "MinimapFrame")
	_solid.append(L.r(M + "MinimapFrame"))


func _draw_camera_box() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var pts := PackedVector2Array()
	for sp in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x, vp.y), Vector2(0, vp.y)]:
		var o := cam.project_ray_origin(sp)
		var d := cam.project_ray_normal(sp)
		if absf(d.y) < 0.0001:
			return
		var tt := (-1.0 - o.y) / d.y
		if tt < 0.0:
			return
		pts.append(world_to_minimap(o + d * tt))
	pts.append(pts[0])
	# clip to the minimap by drawing segments clamped into the rect
	var cl := PackedVector2Array()
	for p in pts:
		cl.append(Vector2(clampf(p.x, _mm_rect.position.x, _mm_rect.end.x), clampf(p.y, _mm_rect.position.y, _mm_rect.end.y)))
	draw_polyline(cl, Color(1, 1, 1, 0.85), 1.2, true)
