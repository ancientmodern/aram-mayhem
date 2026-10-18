class_name Hud
extends Control
## In-game HUD rebuilt from League's own HUD (UI.wad.client): textures, atlas UVs, positions, anchors, font styles
## and flipbook effects come from assets/ui/hud/layout.json + fonts.json (tools/lol/extract_hud.py).
##
## Performance: the HUD is split into retained canvas layers (child Controls). Godot keeps each layer's draw
## commands until it is redrawn, so a layer is only re-recorded when the data it shows changes:
##   minimap (24 Hz) < static frame art (resize only) < info (header, team frames, stats; on change)
##   < player (portrait, bars, inventory, gold; on change, <=30 Hz) < one layer per spell slot (<=30 Hz while its
##   cooldown sweeps) < level-up buttons < buffs (<=15 Hz)
##   < target frame < feed (kill callouts + chat) < fx (flipbooks, banners, pings; only while something animates)
##   < top (tooltip, scoreboard, ping wheel, drag ghost).
## Each layer's draw function records its own hit regions; input walks them top-down.

signal open_shop
signal open_augments

const PF := "PlayerFrame:"
const INV := "Inventory:"
const C_TEXT := Color(0.941, 0.902, 0.824)
const C_DIM := Color(0.647, 0.627, 0.588)
const C_GOLD := Color(0.784, 0.667, 0.431)
const C_CD := Color(1, 1, 1)
const C_ALLY := Color(0.42, 0.72, 1.0)
const C_ENEMY := Color(0.95, 0.35, 0.32)
const ITEM_KEYS := ["1", "2", "3", "4", "5", "6"]
## League minimap world bounds for Map12 (League units, x / z)
const MM_MIN := Vector2(-28.0, -19.0)
const MM_MAX := Vector2(12849.0, 12858.0)
const ANN_TIME := 3.2
const ANN_K := 1.45                  ## [ui-polish] announcement banner scale
const SLOT_KEYS := ["Q", "W", "E", "R", "D", "F"]


## One retained draw layer.
class Canvas extends Control:
	var fn: Callable
	var hits: Array = []        ## [Rect2, key]
	var solid: Array = []       ## Rect2 regions that swallow world clicks
	var last_t := -100.0        ## time of the last redraw request
	var check_t := -100.0       ## time of the last signature check (staggered so layers don't all check on one frame)
	var sig = null              ## last data signature
	var _prof_key := ""

	func _init(p_fn: Callable, p_name: String) -> void:
		fn = p_fn
		name = p_name
		_prof_key = "hud." + p_name
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		var pt := Prof.t0()
		hits.clear()
		solid.clear()
		fn.call(self)
		Prof.add("draw.hud", pt)
		Prof.add(_prof_key, pt)


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
var chat: HudChat = null
var pings: HudPings = null
var target_frame: HudTarget = null
var scoreboard_visible := false
var fps_visible := false             ## [ui-polish] off by default like League; Ctrl+F (or F11) toggles, --fps starts it on
var advanced_stats := false
var fail_msg := ""
var fail_t := 0.0
var feed: Array = []                 ## kill callouts {killer, victim, assists, ally, t}
var ann_queue: Array = []            ## pending announcements
var ann: Dictionary = {}             ## current announcement {text, sub, col, t, kill?}
var _pending_kill := {}
var _pending_kill_frame := -10
var _mouse := Vector2(-1, -1)
var _hover_key := ""
var _tip: Dictionary = {}
var _tip_rect := Rect2()
var _tip_refresh := 0.0
var _tip_gen := 0
var _mm_drag := false
var _mm_rect := Rect2()
var minimap_tex: Texture2D = null
var _last_level := 0
var _level_flash := 0.0
var _now := 0.0
var _fps_shown := 0
var _fps_t := 0.0
var _size_seen := Vector2.ZERO
var _fx: Array = []                  ## running one-shot flipbooks {key, t0, off}
var _was_ready := [true, true, true, true, true, true]
var _could_level := [false, false, false, false]
var _ab_levels := [0, 0, 0, 0]
var _fail_snd_t := -10.0
var _item_cd := {}                   ## item instance id -> previous active cooldown (item-used sound)
var _glow_t0 := [0.0, 0.0, 0.0, 0.0]
var _drag := {}                      ## inventory drag {slot, start, active}
var _fx_was_active := false
var _vis_buffs: Array = []
var _vis_buffs_frame := -1

var cv_mm: Canvas
var cv_base: Canvas
var cv_info: Canvas
var cv_player: Canvas
var cv_bars: Canvas
var cv_slots: Array = []           ## 3 canvases per spell slot (icon / cooldown / frame), see _draw_spell_slot
var cv_levelup: Canvas
var cv_buffs: Canvas
var cv_target: Canvas
var cv_feed: Canvas
var cv_fx: Canvas
var cv_fxadd: Canvas               ## additive flipbooks (League UI effects are additive)
var cv_top: Canvas
var _layers: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	f_title = Assets.font("beaufort", "Bold")
	f_num = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_bold = Assets.font("spiegel", "Bold")
	champ = G.player
	fps_visible = "--fps" in OS.get_cmdline_user_args()
	_last_level = champ.level
	G.announcement.connect(_on_announce)
	G.champion_killed.connect(_on_kill)
	champ.cast_failed.connect(_on_cast_failed)
	minimap_tex = Assets.tex("res://assets/ui/hud/minimap_map12.png")
	scoreboard = HudScoreboard.new()
	scoreboard.hud = self
	chat = HudChat.new()
	chat.hud = self
	pings = HudPings.new()
	pings.hud = self
	target_frame = HudTarget.new()
	target_frame.hud = self
	cv_mm = _layer(_draw_minimap, "Minimap")
	cv_base = _layer(_draw_base, "Base")
	cv_info = _layer(_draw_info, "Info")
	cv_player = _layer(_draw_player, "Player")
	cv_bars = _layer(_draw_bars, "Bars")
	for part in 3:
		for si in 7:
			cv_slots.append(_layer(_draw_slot.bind(si - 1, part), "Slot%d_%s" % [si, ["Icon", "Cd", "Frame"][part]]))
	cv_levelup = _layer(_draw_levelup, "LevelUp")
	cv_buffs = _layer(_draw_buffs, "Buffs")
	cv_target = _layer(target_frame.draw, "Target")
	cv_feed = _layer(_draw_feed, "Feed")
	cv_fxadd = _layer(_draw_fx_add, "FxAdd")
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	cv_fxadd.material = add_mat
	cv_fx = _layer(_draw_fx, "Fx")
	cv_top = _layer(_draw_top, "Top")
	chat.setup(self)
	# augments are disabled (Rules.AUGMENTS_ENABLED); the panel is kept dormant for when they return
	if Rules.AUGMENTS_ENABLED:
		augment_panel = AugmentPanel.new()
		augment_panel.hud = self
		add_child(augment_panel)
	shop_panel = ShopPanel.new()
	shop_panel.hud = self
	add_child(shop_panel)
	shop_panel.visible = false
	for i in 4:
		var ab: Ability = champ.abilities[i]
		_ab_levels[i] = ab.level if ab != null else 0
	_warm_up()


## Load every texture the HUD can draw up front so the first kill / glint / ping doesn't hitch.
func _warm_up() -> void:
	var seen := {}
	for k in HudLayout.data():
		var t = HudLayout.data()[k].get("t")
		if t != null and not seen.has(t) and not (k as String).begins_with("Shop:") and not (k as String).begins_with("Scoreboard:"):
			seen[t] = true
			HudLayout.tex(t)
	for c in match_ref.champions:
		Assets.champion_square(c.alias)
	for n in HudPings.KINDS:
		HudPings._tex(HudPings.KINDS[n].icon)
		HudPings._tex(HudPings.KINDS[n].ring)


func _layer(fn: Callable, nm: String) -> Canvas:
	var c := Canvas.new(fn, nm)
	c.check_t = -0.0071 * _layers.size()
	add_child(c)
	_layers.append(c)
	return c


func _process(delta: float) -> void:
	var ppt := Prof.t0()
	_process_frame(delta)
	Prof.add("proc.hud", ppt)


func _process_frame(delta: float) -> void:
	_now += delta
	L.begin(size)
	if size != _size_seen:
		_size_seen = size
		for c in _layers:
			c.sig = null
			c.queue_redraw()
	fail_t = maxf(0.0, fail_t - delta)
	_level_flash = maxf(0.0, _level_flash - delta)
	if champ.level != _last_level:
		_last_level = champ.level
		_level_flash = 1.0
	for f in feed:
		f.t -= delta
	if not feed.is_empty() and feed[feed.size() - 1].t <= 0.0:
		feed = feed.filter(func(f): return f.t > 0.0)
	if not ann.is_empty():
		ann.t -= delta
		if ann.t <= 0.0:
			ann = {}
	if ann.is_empty() and not ann_queue.is_empty():
		ann = ann_queue.pop_front()
	var sb: bool = Input.is_action_pressed("scoreboard") and not shop_panel.visible and not chat.typing
	if sb != scoreboard_visible:
		scoreboard_visible = sb
		cv_top.sig = null
		if sb:
			hud_sfx("Play_sfx_hud_base_Score_Open", -4.0)
	_fps_t -= delta
	if _fps_t <= 0.0:
		_fps_t = 1.0
		_fps_shown = int(Engine.get_frames_per_second())
	_track_fx()
	pings.process(delta)
	chat.process(delta)
	target_frame.process()
	_schedule()


## Request redraws for layers whose data changed (throttled per layer).
func _schedule() -> void:
	if _now - cv_mm.last_t >= 1.0 / 24.0:
		_redraw(cv_mm)
	_maybe(cv_info, 0.1, _sig_info)
	_maybe(cv_player, 1.0 / 30.0, _sig_player)
	_maybe(cv_bars, 1.0 / 30.0, _sig_bars)
	for part in 3:
		for si in 7:
			_maybe(cv_slots[part * 7 + si], 1.0 / 30.0, _sig_slot.bind(si - 1, part))
	_maybe(cv_levelup, 1.0 / 30.0, _sig_levelup)
	_maybe(cv_buffs, 1.0 / 15.0, _sig_buffs)
	_maybe(cv_target, 1.0 / 15.0, target_frame.sig)
	_maybe(cv_feed, 1.0 / 30.0, _sig_feed)
	var fx_active := _fx_active()
	if fx_active or _fx_was_active:
		_redraw(cv_fx)
		_redraw(cv_fxadd)
	_fx_was_active = fx_active
	_maybe(cv_top, 0.0, _sig_top)


func _redraw(c: Canvas) -> void:
	c.last_t = _now
	c.queue_redraw()


func _maybe(c: Canvas, min_dt: float, sig_fn: Callable) -> void:
	if _now - c.check_t < min_dt:
		return
	c.check_t = maxf(c.check_t + min_dt, _now - min_dt)
	var s = sig_fn.call()
	if s != c.sig:
		c.sig = s
		_redraw(c)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shop"):
		toggle_shop()
		get_viewport().set_input_as_handled()
	elif Rules.AUGMENTS_ENABLED and augment_panel != null and event.is_action_pressed("augments"):
		augment_panel.toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_fps"):
		fps_visible = not fps_visible
		cv_info.sig = null
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER) and not shop_panel.visible:
			chat.open()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_F and k.ctrl_pressed:
			fps_visible = not fps_visible
			cv_info.sig = null
		elif k.keycode == KEY_C and not k.ctrl_pressed:
			advanced_stats = not advanced_stats
			hud_sfx("Play_sfx_hud_base_champ_stats_open" if advanced_stats else "Play_sfx_hud_base_champ_stats_close", -8.0)
			cv_base.queue_redraw()
			cv_info.sig = null


## [ui-polish] League's in-game HUD sound events (data/audio/shared.json) through GameAudio, 2D, rate-limited there.
func hud_sfx(ev: String, vol_db: float = -4.0) -> void:
	if match_ref != null and match_ref.audio != null:
		match_ref.audio.play(ev, null, vol_db, 0.0)


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
	# [ui-polish] League's SpellFail sounds (on cooldown / no mana / silenced-CC / not learned), not spammed on key repeat
	var ev: String = {"cooldown": "Play_sfx_hud_base_SpellFail_Cooldown", "mana": "Play_sfx_hud_base_SpellFail_NoMana",
		"cc": "Play_sfx_hud_base_SpellFail_Silence", "not learned": "Play_sfx_hud_base_SpellFail_Cooldown"}.get(reason, "")
	if ev != "" and _now - _fail_snd_t > 0.35:
		_fail_snd_t = _now
		hud_sfx(ev, -5.0)


func _on_kill(victim, killer, assisters) -> void:
	var kv = killer if killer != null and is_instance_valid(killer) else null
	var ally: bool = kv != null and kv.team == champ.team
	if kv == null:
		ally = victim.team != champ.team
	feed.push_front({"killer": kv, "victim": victim, "assists": assisters.duplicate(), "ally": ally, "t": 10.0})
	if feed.size() > 5:
		feed.pop_back()
	_pending_kill = {"killer": kv, "victim": victim, "ally": ally}
	_pending_kill_frame = Engine.get_process_frames()
	var pc := Prof.t0()
	chat.kill(victim, kv)
	Prof.slow("death.hud_chat", pc, "")


func _on_announce(text: String, sub: String, col: Color) -> void:
	var a := {"text": text, "sub": sub, "col": col, "t": ANN_TIME}
	if Engine.get_process_frames() - _pending_kill_frame <= 1 and not _pending_kill.is_empty():
		a["kill"] = _pending_kill
		a.sub = ""
		_pending_kill = {}
	else:
		chat.announcement(text, col)
	if ann_queue.size() > 3:
		ann_queue.pop_front()
	ann_queue.append(a)


# ===================================================================== input
func _input(event: InputEvent) -> void:
	# pings and target selection see world clicks before the player controller (which only uses LMB for casts)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not chat.typing:
		var mb := event as InputEventMouseButton
		if pings.handle_button(mb):
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and not _over_ui(mb.position) and not shop_panel.visible:
			target_frame.on_world_click()
	elif event is InputEventMouseMotion:
		pings.handle_motion(event.position)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _mm_drag and _mm_rect.has_point(_mouse):
			_minimap_camera(_mouse)
		if not _drag.is_empty() and not _drag.active and _mouse.distance_to(_drag.start) > 6.0:
			_drag.active = true
			hud_sfx("Play_sfx_hud_base_item_slot_grab", -4.0)
		_update_hover()
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	var mp := mb.position
	if not mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mm_drag = false
			if not _drag.is_empty():
				_end_drag(mp)
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if chat.handle_wheel(mp, mb.button_index == MOUSE_BUTTON_WHEEL_UP):
			accept_event()
		return
	if _mm_rect.has_point(mp):
		var wp := minimap_to_world(mp)
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_mm_drag = true
			_minimap_camera(mp)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			champ.issue_move(match_ref.nav.nearest_walkable(wp))
		accept_event()
		return
	var hk := _hit_at(mp)
	if hk != "":
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if hk.begins_with("lvl"):
				if champ.level_ability(int(hk.substr(3))):
					hud_sfx("Play_sfx_hud_base_LevelUp_click", -3.0)
				else:
					Sfx.ui("locked")
			elif hk == "shop":
				toggle_shop()
			elif hk == "stats_btn":
				advanced_stats = not advanced_stats
				hud_sfx("Play_sfx_hud_base_champ_stats_open" if advanced_stats else "Play_sfx_hud_base_champ_stats_close", -8.0)
				cv_base.queue_redraw()
				cv_info.sig = null
			elif hk.begins_with("item") and not hk.begins_with("item_t"):
				_drag = {"slot": int(hk.substr(4)), "start": mp, "active": false}
		accept_event()
		return
	if _over_ui(mp):
		accept_event()


func _end_drag(mp: Vector2) -> void:
	var d := _drag
	_drag = {}
	cv_top.sig = null
	if not d.active:
		return
	var from: int = d.slot
	if from >= champ.items.size():
		return
	# drop on the shop -> sell (League: drag an item onto the shop to sell it)
	if shop_panel.visible and shop_panel.panel.has_point(mp):
		shop_panel.sell_item(champ.items[from])
		return
	for i in 6:
		if L.r(INV + "InventoryItem%d_Backdrop" % i).has_point(mp):
			if i == from:
				return
			# items are stored packed: swapping with an empty slot moves the item to the end
			var it = champ.items[from]
			if i < champ.items.size():
				champ.items[from] = champ.items[i]
				champ.items[i] = it
			else:
				champ.items.remove_at(from)
				champ.items.append(it)
			champ.items_changed.emit()
			hud_sfx("Play_sfx_hud_base_item_slot_drop", -4.0)
			return


func _minimap_camera(mp: Vector2) -> void:
	var wp := minimap_to_world(mp)
	match_ref.camera_rig.locked = false
	match_ref.camera_rig.focus = Vector3(wp.x, match_ref.nav.height_at(wp), wp.z)


func _over_ui(mp: Vector2) -> bool:
	if _mm_rect.has_point(mp) or chat.has_point(mp):
		return true
	for c in _layers:
		for r in c.solid:
			if (r as Rect2).has_point(mp):
				return true
	return false


func _has_point_ui(mp: Vector2) -> bool:
	return _over_ui(mp)


func _hit_at(mp: Vector2) -> String:
	for li in range(_layers.size() - 1, -1, -1):
		var hits: Array = _layers[li].hits
		for i in range(hits.size() - 1, -1, -1):
			if (hits[i][0] as Rect2).has_point(mp):
				return hits[i][1]
	return ""


func _hit_rect(key: String) -> Rect2:
	for c in _layers:
		for h in c.hits:
			if h[1] == key:
				return h[0]
	return Rect2()


func _update_hover() -> void:
	var key := _hit_at(_mouse) if not shop_panel.visible or not shop_panel.panel.has_point(_mouse) else ""
	if key != _hover_key:
		_hover_key = key
		_tip_rect = _hit_rect(key)
		_tip = _build_tip(key)
		_tip_refresh = 0.5
		cv_top.sig = null


func _build_tip(k: String) -> Dictionary:
	if k == "":
		return {}
	if k in ["P", "Q", "W", "E", "R", "D", "F"]:
		return HudTooltip.ability(champ, k)
	if k.begins_with("item_t"):
		return target_frame.item_tip(int(k.substr(6)))
	if k.begins_with("item"):
		var i := int(k.substr(4))
		if i < champ.items.size():
			return HudTooltip.item(champ.items[i].item_id, champ, champ.items[i])
		return {}
	if k.begins_with("tbuff"):
		return target_frame.buff_tip(int(k.substr(5)))
	if k.begins_with("buff"):
		var vis := visible_buffs()
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


# ===================================================================== signatures (what each layer shows)
func _cd_q(ab) -> int:
	## cooldown state quantised to what the slot visibly shows (sweep at 30 steps/s, text per second / 0.1 s)
	if ab == null or ab.is_ready() or ab.cd <= 0.0:
		return -1
	return int(ab.cd * 30.0)


func _sig_info() -> Array:
	var st := champ.stats
	var k: Array = match_ref.kills
	var s := [k[0], k[1], champ.kills, champ.deaths, champ.assists, champ.cs, int(match_ref.time), _fps_shown if fps_visible else -1,
		int(st.ad), int(st.ap), int(st.armor), int(st.mr), int(st.attack_speed * 100.0), int(st.ability_haste),
		int(st.crit_chance * 100.0), int(st.move_speed), advanced_stats]
	if advanced_stats:
		s.append_array([int(st.hp_regen * 50.0), int(st.heal_power * 100.0), int(st.lethality), int(st.armor_pen_pct * 100.0),
			int(st.magic_pen), int(st.magic_pen_pct * 100.0), int(st.lifesteal * 100.0), int(st.omnivamp * 100.0),
			int(st.attack_range), int(st.tenacity * 100.0)])
	for c in match_ref.champions:
		if c.team != champ.team or c == champ:
			continue
		var ult: Ability = c.abilities[3]
		s.append_array([c.dead, int(ceil(c.respawn_timer)) if c.dead else 0, c.level, int(c.hp_ratio() * 60.0),
			int(c.mana / maxf(1.0, c.stats.max_mana) * 60.0), -2 if ult == null or ult.level <= 0 else _cd_q(ult) / 3])
	return s


func _sig_player() -> Array:
	var s := [int(champ.xp_ratio() * 120.0), champ.level, champ.dead, int(ceil(champ.respawn_timer)), int(champ.gold),
		champ.can_shop(), shop_panel.visible,
		_hover_key if _hover_key.begins_with("item") or _hover_key == "shop" else "", _drag.get("slot", -1) if _drag.get("active", false) else -1,
		int(_level_flash * 10.0)]
	for it in champ.items:
		s.append(it.item_id)
		s.append(int(it.active_left * 10.0) if it.active_left > 0.0 else -1)
	return s


func _sig_bars() -> Array:
	return [int(champ.hp), int(champ.stats.max_hp), int(champ.total_shield()), int(champ.mana), int(champ.stats.max_mana),
		champ.dead, int(champ.stats.hp_regen * 50.0), int(champ.stats.mana_regen * 50.0)]


func _sig_slot(slot: int, part: int) -> Array:
	var ab := _ability_for(slot)
	if part == 1:
		return [_cd_q(ab), int(ab.recast_window * 30.0) if ab != null else 0]
	var key: String = "P" if slot < 0 else SLOT_KEYS[slot]
	var learned := slot < 0 or (ab != null and (ab.is_summoner or ab.level > 0))
	var on_cd := ab != null and learned and not ab.is_ready() and ab.cd > 0.0
	var oom := ab != null and learned and not on_cd and not ab.can_afford()
	if part == 0:
		return [learned, oom, ab.icon if ab != null else (champ.passive.get("icon") if champ.passive != null else null)]
	var s := [learned, on_cd, oom, _hover_key == key]
	if slot < 0:
		if champ.passive != null and champ.passive.has_method("hud_counter"):
			s.append(champ.passive.hud_counter())
	elif ab != null:
		s.append_array([ab.level, ab.charges, ab.toggled, int(ab.cost()), ab.max_charges])
	return s


func _sig_levelup() -> Array:
	return [champ.can_level_ability(0), champ.can_level_ability(1), champ.can_level_ability(2), champ.can_level_ability(3),
		_hover_key if _hover_key.begins_with("lvl") else ""]


func _sig_buffs() -> Array:
	var s := [_hover_key if _hover_key.begins_with("buff") else ""]
	for b in visible_buffs():
		s.append_array([b.get_instance_id(), b.stacks, int(b.remaining * 15.0) if not b.permanent else -1])
	return s


func _sig_feed() -> Array:
	var s := [feed.size(), chat.sig()]
	for f in feed:
		s.append(int(clampf(f.t / 0.6, 0.0, 1.0) * clampf((10.0 - f.t) / 0.15, 0.0, 1.0) * 20.0))
	return s


func _sig_top() -> Array:
	if scoreboard_visible:
		return [true, int(_now * 4.0)]
	if not _tip.is_empty():
		# tooltips show live numbers (cooldowns, buff timers): rebuild a few times per second
		_tip_refresh -= get_process_delta_time()
		if _tip_refresh <= 0.0:
			_tip_refresh = 0.25
			_tip = _build_tip(_hover_key)
			_tip_gen += 1
	return [false, _hover_key, _tip_gen, pings.wheel_sig(), _drag_sig(), shop_panel.visible]


func _drag_sig():
	if _drag.is_empty() or not _drag.active:
		return null
	return [_drag.slot, int(_mouse.x), int(_mouse.y)]


func _fx_active() -> bool:
	return not _fx.is_empty() or fail_t > 0.0 or not ann.is_empty() or pings.active() or champ.ability_points > 0 \
		or (champ.can_shop() and not champ.dead)


# ===================================================================== drawing: static frame art
func _draw_base(ci: Canvas) -> void:
	L.begin(size)
	L.draw(ci, "Header:TB_Frame")
	ci.solid.append(L.draw(ci, "Stats:StatsBg"))
	if advanced_stats:
		ci.solid.append(L.draw(ci, "Stats:AdvancedStatsBg"))
	ci.solid.append(L.draw(ci, PF + "HUDCenterFrame"))
	L.draw(ci, PF + "PortraitFrameUnderlay")
	ci.solid.append(L.draw(ci, INV + "InventoryFrame"))
	for i in 7:
		L.draw(ci, INV + "InventoryItem%d_Backdrop" % i)
	L.draw(ci, INV + "Recall_Disabled")
	L.ltext(ci, INV + "Recall_HotKey", "B")
	for i in 6:
		L.ltext(ci, INV + "InventoryItem%d_HotKey" % i, ITEM_KEYS[i])
	L.ltext(ci, INV + "Shop_HotKey", "P")
	# minimap frame sits above the minimap layer
	L.draw(ci, "Minimap:MinimapFrame")
	ci.solid.append(L.r("Minimap:MinimapFrame"))
	var fr := L.r("Minimap:MinimapFrame")
	_mm_rect = L.r("Minimap:MinimapContent")
	if fr.size.x <= 0.0:
		_mm_rect = Rect2()
	chat.layout()


# ===================================================================== drawing: header, team frames, stats
func _draw_info(ci: Canvas) -> void:
	L.begin(size)
	_draw_header(ci)
	_draw_team_frames(ci)
	_draw_stats(ci)


func _draw_header(ci: Canvas) -> void:
	var H := "Header:"
	var my := champ.team
	var k: Array = match_ref.kills
	L.ltext(ci, H + "TB_TeamKills_T1Score", str(k[my]), C_ALLY, 2)
	L.draw(ci, H + "TB_TeamKills_Icon1")
	L.ltext(ci, H + "TB_TeamKills_T2Score", str(k[1 - my]), C_ENEMY, 0)
	L.draw(ci, H + "TB_Player_KDA_Icon")
	L.ltext(ci, H + "TB_Player_KDA_Text", "%d/%d/%d" % [champ.kills, champ.deaths, champ.assists], Color(0, 0, 0, 0), 0)
	L.draw(ci, H + "TB_Player_CS_Icon")
	L.ltext(ci, H + "TB_Player_CS_Text", str(champ.cs), Color(0, 0, 0, 0), 0)
	L.draw(ci, H + "GameTimeIcon")
	var t: float = match_ref.time
	L.ltext(ci, H + "GameTime", "%02d:%02d" % [int(t / 60.0), int(t) % 60], Color(0, 0, 0, 0), 0)
	if fps_visible:
		# League's FPS / latency readout under the header (HUD_Metrics style), refreshed once per second
		var fr := L.r(H + "GameTime")
		var st := L.style("HUD_Metrics")
		var s := "FPS: %d     %d ms" % [_fps_shown, 0]
		var px: int = st.px
		var w: float = (st.font as Font).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		HudLayout.styled_in(ci, Rect2(size.x - w - 10.0, fr.end.y + fr.size.y * 0.4, w, px), s, st, px, Color(0.8, 0.8, 0.8), 0)


func _draw_team_frames(ci: Canvas) -> void:
	var T := "TeamFrames:"
	var i := 0
	for c in match_ref.champions:
		if c.team != champ.team or c == champ:
			continue
		var off := Vector2(0, -82.0 * i)
		var dead: bool = c.dead
		L.draw(ci, T + ("TeamFrame0_FrameDeadUnderlay" if dead else "TeamFrame0_FrameUnderlay"), Color.WHITE, off)
		var ir := L.r(T + "TeamFrame0_Icon_Data", off)
		HudLayout.square_icon(ci, Assets.champion_square(c.alias), ir, Color(0.4, 0.4, 0.4) if dead else Color.WHITE)
		L.draw(ci, T + "TeamFrame0_HPBackdrop", Color.WHITE, off)
		_fill_h_off(ci, T + "TeamFrame0_HPBarTextureGreen", c.hp_ratio(), off)
		if c.stats.max_mana > 0.0:
			_fill_h_off(ci, T + "TeamFrame0_PARBarTextureBlue", c.mana / maxf(1.0, c.stats.max_mana), off)
		L.draw(ci, T + "TeamFrame0_HPFrame", Color.WHITE, off)
		var fr := L.draw(ci, T + ("TeamFrame0_FrameDead" if dead else "TeamFrame0_Frame"), Color.WHITE, off)
		var ult: Ability = c.abilities[3]
		if ult != null and ult.level > 0:
			L.draw(ci, T + "TeamFrame0_UltBg", Color.WHITE, off)
			if ult.is_ready():
				L.draw(ci, T + "TeamFrame0_Ult", Color.WHITE, off)
			else:
				var ur := L.r(T + "TeamFrame0_UltCooldownFX", off)
				HudLayout.radial(ci, ur, ult.cd / maxf(ult.cd_total, 0.01), Color(0, 0, 0, 0.75))
		L.ltext(ci, T + "TeamFrame0_Level", str(c.level), Color(0, 0, 0, 0), 1, off)
		if dead:
			L.ltext(ci, T + "TeamFrame0_Timer", str(int(ceil(c.respawn_timer))), Color.WHITE, 1, off + Vector2(0, -30))
		ci.hits.append([fr, "ally:%d" % c.uid])
		i += 1


func _fill_h_off(ci: CanvasItem, key: String, frac: float, off: Vector2) -> void:
	L.fill_h(ci, key, frac, Color.WHITE, 0.0, off)


func _draw_stats(ci: Canvas) -> void:
	var st := champ.stats
	var S := "Stats:"
	var rows := [
		["AD", str(int(st.ad)), "Attack Damage"], ["AP", str(int(st.ap)), "Ability Power"],
		["Armor", str(int(st.armor)), "Armor"], ["MR", str(int(st.mr)), "Magic Resist"],
		["AS", "%.2f" % st.attack_speed, "Attack Speed"], ["AH", str(int(st.ability_haste)), "Ability Haste"],
		["Crit", "%d%%" % int(round(st.crit_chance * 100.0)), "Critical Strike Chance"], ["MS", str(int(st.move_speed)), "Move Speed"],
	]
	if advanced_stats:
		rows.append_array([
			["HPR", "%.1f" % (st.hp_regen * 5.0), "Health Regen (per 5s)"], ["HSP", "%d%%" % int(st.heal_power * 100.0), "Heal and Shield Power"],
			["APen", "%d | %d%%" % [int(st.lethality), int(st.armor_pen_pct * 100.0)], "Lethality | Armor Pen"],
			["MPen", "%d | %d%%" % [int(st.magic_pen), int(st.magic_pen_pct * 100.0)], "Magic Pen"],
			["LS", "%d%%" % int(st.lifesteal * 100.0), "Life Steal"], ["SV", "%d%%" % int(st.omnivamp * 100.0), "Omnivamp"],
			["AR", str(int(st.attack_range)), "Attack Range"], ["Ten", "%d%%" % int(st.tenacity * 100.0), "Tenacity"],
		])
	for row in rows:
		L.draw(ci, S + "Stats_%s_Icon" % row[0])
		L.ltext(ci, S + "Stats_%s_Text" % row[0], row[1], Color(0, 0, 0, 0), 0)
		ci.hits.append([L.r(S + "Stats_%s_HitArea" % row[0]), "stat:%s: %s" % [row[2], row[1]]])
	var br := L.draw(ci, PF + ("Stats_ButtonSelected" if advanced_stats else "Stats_ButtonDefault"))
	ci.hits.append([br, "stats_btn"])


# ===================================================================== drawing: portrait, bars, inventory, gold
func _draw_player(ci: Canvas) -> void:
	L.begin(size)
	var pr := L.r(PF + "PlayerIcon_Base")
	var sq := Assets.champion_square(champ.alias)
	HudLayout.circle_tex(ci, sq, pr.get_center(), pr.size.x * 0.5, Color(0.38, 0.38, 0.38) if champ.dead else Color.WHITE, 1.08)
	L.draw(ci, PF + "PlayerExp_Backdrop")
	L.fill_v(ci, PF + "PlayerExp_BarTexture", champ.xp_ratio() if champ.level < 18 else 1.0)
	var frame := L.draw(ci, PF + "PortraitFrame_Default")
	ci.solid.append(frame)
	var lvl_col := Color.WHITE.lerp(Color(1.0, 0.9, 0.45), _level_flash)
	L.ltext(ci, PF + "PlayerLevel", str(champ.level), lvl_col, 1)
	if champ.dead:
		L.ltext(ci, PF + "PlayerRespawnTimer", str(int(ceil(champ.respawn_timer))), Color.WHITE, 1, Vector2(-13, 0))
	_draw_inventory(ci)


func _draw_bars(ci: Canvas) -> void:
	L.begin(size)
	_draw_resource_bars(ci)


func _draw_resource_bars(ci: Canvas) -> void:
	var H := PF + "PlayerHP_"
	L.draw(ci, H + "Backdrop")
	var mx := champ.stats.max_hp
	var shield := champ.total_shield()
	var total := maxf(mx, champ.hp + shield)
	var hp_frac := champ.hp / maxf(total, 1.0)
	var hr := L.fill_h(ci, H + "BarTextureGreen", hp_frac)
	if shield > 0.0:
		var el := L.e(PF + "PlayerPar_BarTextureWhite")
		var full := L.r(H + "BarTextureGreen")
		var sw := shield / maxf(total, 1.0)
		var u := L.uv_of(PF + "PlayerPar_BarTextureWhite")
		HudLayout.region(ci, el.t, Rect2(u.position, Vector2(u.size.x * sw, u.size.y)),
			Rect2(Vector2(hr.end.x if hr.size.x > 0 else full.position.x, full.position.y), Vector2(full.size.x * sw, full.size.y)))
	L.draw(ci, H + "BookendLeft")
	L.draw(ci, H + "BookendRight")
	L.ltext(ci, H + "ValueText", "%d / %d" % [mini(int(ceil(champ.hp)), int(mx)), int(mx)], Color(0, 0, 0, 0), 1)
	if champ.stats.hp_regen > 0.0 and champ.hp < mx and not champ.dead:
		L.ltext(ci, H + "RegenText", "+%.1f" % (champ.stats.hp_regen * 5.0), Color(0.8, 0.95, 0.8), 2)
	var M := PF + "PlayerPar_"
	L.draw(ci, M + "Backdrop")
	if champ.stats.max_mana > 0.0:
		var bar := "BarTextureBlue"
		match champ.resource_name:
			"Energy": bar = "BarTextureYellow"
			"Fury", "Rage", "Heat", "Bloodthirst": bar = "BarTextureRed"
			"Flow", "Courage": bar = "BarTextureWhite"
		L.fill_h(ci, M + bar, champ.mana / champ.stats.max_mana)
		L.ltext(ci, M + "ValueText", "%d / %d" % [int(champ.mana), int(champ.stats.max_mana)], Color(0, 0, 0, 0), 1)
		if champ.stats.mana_regen > 0.0 and champ.mana < champ.stats.max_mana and not champ.dead:
			L.ltext(ci, M + "RegenText", "+%.1f" % (champ.stats.mana_regen * 5.0), Color(0.8, 0.88, 1.0), 2)
	L.draw(ci, M + "BookendLeft")
	L.draw(ci, M + "BookendRight")


func _draw_inventory(ci: Canvas) -> void:
	var dslot: int = _drag.slot if _drag.get("active", false) else -1
	for i in 6:
		var P := INV + "InventoryItem%d_" % i
		var r := L.r(P + "Backdrop")
		var it = champ.items[i] if i < champ.items.size() else null
		if it == null:
			continue
		var ir := L.r(P + "Border").grow(-L.s() * 2.0)
		if it.icon != null:
			ci.draw_texture_rect(it.icon, ir, false, Color(1, 1, 1, 0.35) if i == dslot else Color.WHITE)
		if it.active_left > 0.0 and it.cooldown_ratio() > 0.0:
			var el := L.e(P + "CooldownFX")
			HudLayout.radial(ci, ir, it.cooldown_ratio(), Color(1, 1, 1, 0.92), el.get("t", ""), L.uv_of(P + "CooldownFX"))
			L.ltext(ci, P + "Cooldown", str(int(ceil(it.active_left))), C_CD, 1)
		if _hover_key == "item%d" % i:
			L.draw(ci, P + "Mouseover", Color(1, 1, 1, 0.3))
		L.draw(ci, P + ("Enabled" if it.has_active() else "Border"))
		ci.hits.append([r, "item%d" % i])
	for i in 6:
		if i >= champ.items.size():
			ci.hits.append([L.r(INV + "InventoryItem%d_Backdrop" % i), "item%d" % i])
	# gold / shop button: League's real goldframe art (default / hover / click / glow from the inventory auto atlas)
	var hr := L.r(INV + "Shop_HitArea")
	var can := champ.can_shop()
	var hov := _hover_key == "shop"
	var key := "Shop_ButtonDisabled"
	if shop_panel.visible:
		key = "Shop_ButtonClicked"
	elif hov:
		key = "Shop_ButtonHover"
	elif can:
		key = "Shop_ButtonDefault"
	L.draw(ci, INV + key)
	L.ltext(ci, INV + "Shop_GoldText", str(int(champ.gold)), Color(0, 0, 0, 0), 1)
	ci.hits.append([hr, "shop"])


# ===================================================================== drawing: abilities, summoners, buffs
func _ability_for(slot: int) -> Ability:
	if slot < 0:
		return null
	if slot < 4:
		return champ.abilities[slot]
	return champ.summoners[slot - 4]


func _draw_slot(ci: Canvas, slot: int, part: int) -> void:
	L.begin(size)
	if slot < 0:
		_draw_spell_slot(ci, "Passive", -1, part)
	elif slot < 4:
		_draw_spell_slot(ci, "Ability%d" % slot, slot, part)
	else:
		_draw_spell_slot(ci, "Summoner%d" % (slot - 4), slot, part)


func _draw_levelup(ci: Canvas) -> void:
	L.begin(size)
	for i in 4:
		if champ.can_level_ability(i):
			var key := PF + "LevelUp%d_Button" % i
			var r := L.r(key + "Default")
			L.draw(ci, key + ("Hover" if _hover_key == "lvl%d" % i else "Default"))
			ci.hits.append([r, "lvl%d" % i])


## A spell slot is drawn in three retained parts so a ticking cooldown only re-records the sweep:
## part 0 = icon + unavailable / out-of-mana overlays, 1 = cooldown sweep, cooldown number, recast timer bar,
## 2 = toggle, mouse-over, border, ammo gem, cost, hotkey, rank pips (and the slot's hit region).
func _draw_spell_slot(ci: Canvas, base: String, slot: int, part: int) -> void:
	var P := PF + base
	var ab := _ability_for(slot)
	var icon_r := L.r(P + "_")
	var key: String = "P" if slot < 0 else SLOT_KEYS[slot]
	var learned := slot < 0 or (ab != null and (ab.is_summoner or ab.level > 0))
	var on_cd := ab != null and learned and not ab.is_ready() and ab.cd > 0.0
	var oom := ab != null and learned and not on_cd and not ab.can_afford()
	if part == 0:
		var icon: Texture2D = null
		if slot < 0:
			icon = champ.passive.icon if champ.passive != null and champ.passive.get("icon") != null else Assets.ability_icon(champ.alias, "p")
		elif ab != null:
			icon = ab.icon
		if icon != null:
			var mod := Color.WHITE
			if not learned:
				mod = Color(0.35, 0.35, 0.35)
			elif oom:
				mod = Color(0.5, 0.62, 1.0)
			ci.draw_texture_rect(icon, icon_r, false, mod)
		if not learned:
			L.draw(ci, P + "_OverlayUnavailable")
		if oom:
			L.draw(ci, P + "_IconOom", Color(1, 1, 1, 0.45))   # League's blue out-of-mana overlay
		return
	if part == 1:
		if on_cd:
			var el := L.e(P + "_CooldownFX")
			var uv := L.uv_of(P + "_CooldownFX")
			if uv.size.x <= 0.0:
				uv = Rect2(884, 955, 64, 64)
			HudLayout.radial(ci, L.r(P + "_CooldownFX"), ab.cd / maxf(ab.cd_total, 0.01), Color(1, 1, 1, 0.92), el.get("t", ""), uv)
			var cds := ("%.1f" % ab.cd) if ab.cd < 1.0 else str(int(ceil(ab.cd)))
			L.ltext(ci, P + "_Cooldown", cds, C_CD, 1)
		# recast window: League shows a timer bar above the slot
		if ab != null and ab.recast_window > 0.0:
			var tb := L.r(P + "_TimerBar_BarTexture")
			if tb.size.x > 0.0:
				L.draw(ci, P + "_TimerBar_Backdrop")
				var frac := clampf(ab.recast_window / maxf(ab.get("recast_total") if ab.get("recast_total") != null else 3.0, 0.1), 0.0, 1.0)
				L.fill_h(ci, P + "_TimerBar_BarTexture", frac)
		return
	if ab != null and ab.toggled:
		draw_toggle(ci, P, icon_r)
	if _hover_key == key:
		L.draw(ci, P + "_Mouseover", Color(1, 1, 1, 0.35))
	L.draw(ci, P + ("_BorderAvailable" if learned and not on_cd else "_BorderUnavailable"))
	if ab != null and ab.max_charges > 0 and learned:
		L.draw(ci, P + ("_CooldownGemAvailable" if ab.charges > 0 else "_CooldownGemUnavailable"))
		L.ltext(ci, P + "_CooldownGem", str(ab.charges), Color(1, 1, 0.85), 1)
	# mana cost chip and hotkey
	if ab != null and slot >= 0 and slot < 4 and learned and ab.cost() > 0.0 and champ.stats.uses_mana:
		L.draw(ci, P + "_CostBg")
		L.ltext(ci, P + "_Cost", str(int(ab.cost())), Color(0, 0, 0, 0) if not oom else Color(0.55, 0.6, 1.0), 1)
	if slot >= 0:
		L.ltext(ci, P + "_HotKey", key, Color(0, 0, 0, 0), 1)
	if slot >= 0 and slot < 4 and ab != null:
		_draw_pips(ci, slot, ab)
	if slot < 0 and champ.passive != null and champ.passive.has_method("hud_counter"):
		var cnt: String = champ.passive.hud_counter()
		if cnt != "":
			var st := L.style("HUD_CounterMedium", L.hud_scale)
			HudLayout.styled_in(ci, Rect2(icon_r.position + Vector2(0, icon_r.size.y * 0.55), Vector2(icon_r.size.x, icon_r.size.y * 0.45)),
				cnt, st, st.px, Color.WHITE, 1)
	ci.hits.append([L.r(P + "_BorderAvailable"), key])


## Toggle border (League ToggleFX: a looping gold flipbook; static frame here, the fx layer animates nothing for it).
func draw_toggle(ci: CanvasItem, P: String, icon_r: Rect2) -> void:
	if L.has(P + "_ToggleFX"):
		L.draw_fx(ci, P + "_ToggleFX", 0)
	else:
		ci.draw_rect(icon_r.grow(-1.0), Color(0.45, 0.85, 1.0, 0.85), false, maxf(2.0, icon_r.size.x * 0.05))


func _draw_pips(ci: CanvasItem, slot: int, ab: Ability) -> void:
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
		L.draw_in(ci, PF + ("Ability%d_FullPip0" % slot if p < ab.level else "Ability%d_EmptyPip0" % slot), rc)


func visible_buffs() -> Array:
	var fr := Engine.get_process_frames()
	if fr != _vis_buffs_frame:
		_vis_buffs_frame = fr
		_vis_buffs = champ.buffs.filter(func(b): return not b.hidden and b.display_name != "" and b.show_timer)
	return _vis_buffs


func _draw_buffs(ci: Canvas) -> void:
	L.begin(size)
	var vis := visible_buffs()
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
		draw_buff(ci, b, ir, B, off)
		ci.hits.append([ir, "buff%d" % idx])


## One buff icon with League's border, cooldown sweep and stack count (shared with the target frame).
func draw_buff(ci: CanvasItem, b: Buff, ir: Rect2, B: String, off: Vector2) -> void:
	ci.draw_rect(ir, Color(0.02, 0.04, 0.06, 0.95))
	var bic := HudBuffIcons.icon_for(b)
	if bic != null:
		ci.draw_texture_rect(bic, ir, false)
	else:
		HudLayout.text_in(ci, ir, b.display_name.substr(0, 2), f_bold, maxi(9, int(ir.size.y * 0.4)), C_TEXT, 1, 2.0)
	if not b.permanent and b.duration > 0.0:
		HudLayout.radial(ci, ir, 1.0 - b.remaining / b.duration, Color(0, 0, 0, 0.6))
	L.draw(ci, B + ("BorderNegative" if b.is_debuff else "BorderPositive"), Color.WHITE, off)
	if b.stacks > 1:
		L.ltext(ci, B + "Stacks", str(b.stacks), Color.WHITE, 2, off)


# ===================================================================== drawing: kill callouts + chat
func _draw_feed(ci: Canvas) -> void:
	L.begin(size)
	_draw_kill_feed(ci)
	chat.draw(ci)


func _draw_kill_feed(ci: CanvasItem) -> void:
	var K := "Kill:KillCallout0_"
	var i := 0
	for f in feed:
		var off := Vector2(0, 58.0 * i)   # [ui-polish] tighter pitch so 5 rows never reach the ally portrait column
		var a := clampf(f.t / 0.6, 0.0, 1.0) * clampf((10.0 - f.t) / 0.15, 0.0, 1.0)
		var tint: Color = Color(0.12, 0.38, 0.78, 0.9 * a) if f.ally else Color(0.72, 0.14, 0.14, 0.9 * a)
		L.draw(ci, K + "Background", tint, off)
		var w := Color(1, 1, 1, a)
		var killer = f.killer
		var kr := L.r(K + "KillerPortrait", off)
		if killer != null and is_instance_valid(killer) and killer.kind == G.Kind.CHAMPION:
			HudLayout.square_icon(ci, Assets.champion_square(killer.alias), kr, w)
		else:
			draw_unit_glyph(ci, kr, killer, a)
		L.draw(ci, K + "KillerFrame", w, off)
		L.draw(ci, K + "KillIconNormal", w, off)
		HudLayout.square_icon(ci, Assets.champion_square(f.victim.alias), L.r(K + "TargetPortrait", off), w)
		L.draw(ci, K + "TargetFrame", w, off)
		var ai := 0
		for asst in f.assists:
			if ai > 1 or not is_instance_valid(asst):
				break
			HudLayout.square_icon(ci, Assets.champion_square(asst.alias), L.r(K + "Assister%dPortrait" % ai, off), w)
			L.draw(ci, K + "Assister%dFrame" % ai, w, off)
			ai += 1
		i += 1


func draw_unit_glyph(ci: CanvasItem, r: Rect2, u, a: float) -> void:
	ci.draw_rect(r, Color(0.05, 0.07, 0.09, a))
	var icon := "icon_ui_tower_minimap"
	if u != null and is_instance_valid(u) and u.kind == G.Kind.MINION:
		icon = "minionmapcircle"
	var t := Assets.tex("res://assets/ui/hud/icons/%s.png" % icon)
	if t != null:
		ci.draw_texture_rect(t, r.grow(-r.size.x * 0.18), false, Color(0.9, 0.9, 0.9, a))


# ===================================================================== drawing: animated effects
## Detect HUD events that start League's flipbook effects.
func _track_fx() -> void:
	for i in 6:
		var ab := _ability_for(i)
		var ready := ab == null or ab.is_ready() or (i < 4 and ab.level <= 0)
		if ready and not _was_ready[i] and ab != null:
			# cooldown finished: League's GlintFX + SheenFX flash over the slot
			var P := PF + ("Ability%d" % i if i < 4 else "Summoner%d" % (i - 4))
			_fx.append({"key": P + "_SheenFX", "t0": _now})
			_fx.append({"key": P + "_GlintFX", "t0": _now})
		_was_ready[i] = ready
	var point_ready := false
	for i in 4:
		var can := champ.can_level_ability(i)
		if can and not _could_level[i]:
			_fx.append({"key": PF + "LevelUp%d_ButtonIn" % i, "t0": _now})
			_glow_t0[i] = _now
			point_ready = true
		_could_level[i] = can
		var ab: Ability = champ.abilities[i]
		var lv := ab.level if ab != null else 0
		if lv > _ab_levels[i]:
			_fx.append({"key": PF + "LevelUp%d_AbilityIn" % i, "t0": _now})
			hud_sfx("Play_sfx_hud_base_spell_levelup", -7.0)
		_ab_levels[i] = lv
	# skill point available (not for the free first point at match start; the level-up sting itself is GameAudio's)
	if point_ready and match_ref != null and match_ref.time > 2.0:
		hud_sfx("Play_sfx_hud_base_LevelUp_layer", -8.0)
	# item active used (its cooldown just started)
	for it in champ.items:
		var iid: int = it.get_instance_id()
		var al: float = it.active_left
		if _item_cd.has(iid) and al > float(_item_cd[iid]) + 0.5 and it.has_active():
			hud_sfx("Play_sfx_hud_base_spell_generic_use", -6.0)
		_item_cd[iid] = al
	for j in range(_fx.size() - 1, -1, -1):
		var f: Dictionary = _fx[j]
		if L.fx_frame(f.key, _now - f.t0) < 0:
			_fx.remove_at(j)


func _draw_fx_add(ci: Canvas) -> void:
	L.begin(size)
	for f in _fx:
		var fr := L.fx_frame(f.key, _now - f.t0)
		if fr >= 0:
			L.draw_fx(ci, f.key, fr)
	# skill point available: League's looping idle glow + sheen on the level-up buttons
	for i in 4:
		if _could_level[i]:
			var age: float = _now - _glow_t0[i]
			if L.fx_frame(PF + "LevelUp%d_ButtonIn" % i, age) < 0:
				L.draw_fx(ci, PF + "LevelUp%d_IdleGlow" % i, L.fx_frame(PF + "LevelUp%d_IdleGlow" % i, age, true))


func _draw_fx(ci: Canvas) -> void:
	L.begin(size)
	# gold button: in base League lights the frame (gold-glow); a soft breathing glow on top
	if champ.can_shop() and not champ.dead and not shop_panel.visible:
		var a := 0.25 + 0.25 * sin(_now * 3.2)
		L.draw(ci, INV + "Shop_ButtonDefault", Color(1, 1, 1, a))
	_draw_announcement(ci)
	if fail_t > 0.0:
		var a2 := minf(1.0, fail_t * 2.5)
		L.ltext(ci, PF + "StatusMessageToolTip", fail_msg, Color(1.0, 0.42, 0.36, a2), 1, Vector2.ZERO, 18.0)
	pings.draw_world(ci)


func _draw_announcement(ci: CanvasItem) -> void:
	if ann.is_empty():
		return
	var t: float = ann.t
	var age := ANN_TIME - t
	var a := clampf(age / 0.18, 0.0, 1.0) * clampf(t / 0.45, 0.0, 1.0)
	var pop := 1.0 + maxf(0.0, 0.18 - age) * 1.4
	var B := "Banner:"
	var w := Color(1, 1, 1, a)
	var text: String = ann.text
	# [ui-polish] League's banner is drawn larger than the raw layout rects (about a fifth of the screen height with the
	# kill portraits): scale the art about the top-centre, text is re-rasterised at the larger size below.
	ci.draw_set_transform(Vector2(size.x * 0.5 * (1.0 - ANN_K), 0.0), 0.0, Vector2(ANN_K, ANN_K))
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
			L.draw(ci, B + bg + ("BlueBG" if ally else "RedBG"), w)
		L.draw(ci, B + ("AnnBannerBlue_Underline" if ally else "AnnBannerRed_Underline"), w)
		var killer = k.killer
		var victim = k.victim
		var lr := L.r(B + "AnnBannerLeftIcon_content")
		if killer != null and is_instance_valid(killer) and killer.kind == G.Kind.CHAMPION:
			HudLayout.circle_tex(ci, Assets.champion_square(killer.alias), lr.get_center(), lr.size.x * 0.5 * pop, w, 1.1)
		else:
			ci.draw_circle(lr.get_center(), lr.size.x * 0.5, Color(0.05, 0.07, 0.1, a))
			draw_unit_glyph(ci, lr.grow(-lr.size.x * 0.12), killer, a)
		var rr := L.r(B + "AnnBannerRightIcon_content")
		if victim != null and is_instance_valid(victim):
			HudLayout.circle_tex(ci, Assets.champion_square(victim.alias), rr.get_center(), rr.size.x * 0.5 * pop, Color(0.85, 0.85, 0.85, a), 1.1)
		L.draw(ci, B + ("AnnBannerLeftGlowBlue" if ally else "AnnBannerLeftGlowRed"), w)
		L.draw(ci, B + ("RightIconGlowRed" if ally else "RightIconGlowBlue"), w)
		L.draw(ci, B + "AnnBannerLeftIcon_gold_ring", w)
		L.draw(ci, B + "AnnBannerRightIcon_gold_ring", w)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_banner_text(ci, up, 222.0, "AnnouncementMajor", pop * ANN_K, a)
	else:
		L.draw(ci, B + "AnnBannerGold_Underline", w)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_banner_text(ci, up, 176.0, "AnnouncementMajor", pop * ANN_K, a)
		if ann.sub != "":
			_banner_text(ci, String(ann.sub), 214.0, "AnnouncementMinor", 0.75 * ANN_K, a, C_DIM)


## Banner text in League's Announcement* font style (Beaufort Bold, size / shadow from fonts.json).
func _banner_text(ci: CanvasItem, s_txt: String, y_src: float, style: String, k: float, a: float, col := Color(0.97, 0.93, 0.84)) -> void:
	var st := L.style(style, L.hud_scale * k)
	var px: int = st.px
	var c := Vector2(size.x * 0.5, L.pt("Banner:AnnBannerGold_Underline", Vector2(800, y_src)).y * ANN_K)
	HudLayout.styled_in(ci, Rect2(c.x - 400.0, c.y - px, 800.0, px * 2.0), s_txt, st, px, Color(col.r, col.g, col.b, a), 1)


# ===================================================================== drawing: tooltip, scoreboard, wheel, drag
func _draw_top(ci: Canvas) -> void:
	L.begin(size)
	if scoreboard_visible:
		scoreboard.draw(ci, L)
		return
	pings.draw_wheel(ci)
	if not _drag.is_empty() and _drag.active and _drag.slot < champ.items.size():
		var it = champ.items[_drag.slot]
		var sz := L.r(INV + "InventoryItem0_Border").size
		if it.icon != null:
			ci.draw_texture_rect(it.icon, Rect2(_mouse - sz * 0.5, sz), false, Color(1, 1, 1, 0.85))
		return
	if not _tip.is_empty() and not shop_panel.visible:
		HudTooltip.draw(ci, _tip, _tip_rect, size, size.y / 1080.0)


# ===================================================================== minimap
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


func _draw_minimap(ci: Canvas) -> void:
	L.begin(size)
	_mm_rect = L.r("Minimap:MinimapContent")
	if minimap_tex != null:
		ci.draw_texture_rect(minimap_tex, _mm_rect, false)
	var u_scale := _mm_rect.size.x / 283.0
	var my_team := champ.team
	# structures
	for s in match_ref.structures:
		if s.dead:
			continue
		if s.get("tier") != null and s.tier == Turret.Tier.FOUNTAIN:
			continue
		var p := world_to_minimap(s.global_position)
		var col := Color(0.35, 0.68, 1.0) if s.team == my_team else Color(1.0, 0.33, 0.3)
		var ic := "icon_ui_tower_minimap"
		var sz := 22.0
		if s.kind == G.Kind.INHIBITOR:
			ic = "icon_ui_inhibitor_minimap_v2"
		elif s.kind == G.Kind.NEXUS:
			ic = "icon_ui_nexus_minimap_v2"
			sz = 26.0
		elif s.has_method("hp_ratio"):
			var hr: float = s.hp_ratio()
			ic = "icon_ui_tower_minimap" if hr > 0.66 else ("icon_ui_tower_minimap_med" if hr > 0.33 else "icon_ui_tower_minimap_low")
		var t := _icon(ic)
		var d := sz * u_scale
		if t != null:
			ci.draw_texture_rect(t, Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)), false, col)
	# relics (health packs)
	var hp_icon := _icon("healthpack")
	for r in match_ref.relics:
		if r.active and hp_icon != null:
			var d2 := 16.0 * u_scale
			ci.draw_texture_rect(hp_icon, Rect2(world_to_minimap(r.global_position) - Vector2(d2, d2) * 0.5, Vector2(d2, d2)), false)
	# minions
	var dot := _icon("minionmapcircle")
	var d3 := 5.0 * u_scale
	var ally_c := Color(0.35, 0.65, 1.0)
	var enemy_c := Color(1.0, 0.3, 0.28)
	for u in match_ref.units:
		if u.dead or u.kind != G.Kind.MINION:
			continue
		if u.team != my_team and not u.visible_to[my_team]:
			continue
		var p2 := world_to_minimap(u.global_position)
		var mc := ally_c if u.team == my_team else enemy_c
		if dot != null:
			ci.draw_texture_rect(dot, Rect2(p2 - Vector2(d3, d3) * 0.5, Vector2(d3, d3)), false, mc)
		else:
			ci.draw_circle(p2, d3 * 0.5, mc)
	# champions (enemies first, allies, self last on top)
	var rad := 12.0 * u_scale
	for pass_i in 3:
		for c in match_ref.champions:
			if c.dead:
				continue
			var grp := 0 if c.team != my_team else (2 if c == champ else 1)
			if grp != pass_i:
				continue
			if c.team != my_team and not c.visible_to[my_team]:
				continue
			var p3 := world_to_minimap(c.global_position)
			HudLayout.circle_tex(ci, Assets.champion_square(c.alias), p3, rad, Color.WHITE, 1.12)
			var ring := Color(0.25, 0.62, 1.0) if c.team == my_team else Color(0.95, 0.22, 0.2)
			if c == champ:
				ring = Color(1.0, 0.86, 0.3)
			ci.draw_arc(p3, rad, 0.0, TAU, 20, ring, maxf(1.5, 2.2 * u_scale), false)
	pings.draw_minimap(ci)
	_draw_camera_box(ci)


func _draw_camera_box(ci: CanvasItem) -> void:
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
	# clip to the minimap by clamping into the rect
	var cl := PackedVector2Array()
	for p in pts:
		cl.append(Vector2(clampf(p.x, _mm_rect.position.x, _mm_rect.end.x), clampf(p.y, _mm_rect.position.y, _mm_rect.end.y)))
	ci.draw_polyline(cl, Color(1, 1, 1, 0.85), 1.2, true)
