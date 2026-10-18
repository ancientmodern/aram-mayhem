class_name WorldOverlay
extends Control
## Screen-space overlay drawn every frame: League floating health bars, floating combat text and the
## turret-aggro line. One Control draws everything (fixed pixel size, crisp, cheap).
##
## Health bars are rebuilt from League's own data: the LoLFloatingInfoBars UI scene (element rects + atlas UVs)
## and its 512x512 atlas, extracted by tools/lol/extract_world_ui.py into assets/ui/world/. Element positions
## are authored at the 1600x1200 UI reference and placed relative to each bar's AnchorBase element.
##
## [healthbar] Bar behaviour is League's, not hand-tuned (sources: tools/lol/extract_world_ui.py, which writes
## assets/ui/world/fhb_behaviour.json):
##  * Style per unit = SkinCharacterDataProperties.HealthBarData.unitHealthBarStyle -> InfoBarStyleSourceMap
##    (champions 12 ChampBars, lane minions 0 MinionSmall, super minions 1 MinionMed, inhibitor 3 Structure,
##    turrets + nexus 8 EpicStructure, Tibbers 5 Obj).
##  * Lost-health chunk = HealthBarFadeData (hold fadeHoldTime, then drain at fadeSpeed accelerating by
##    fadeAcceleration, in bar fractions per second). Champion bars override fadeSpeed to 0.05; structures keep the
##    class defaults (0.05 s, 0.5, 5.0). Lane minion bars have no fadeData: they drop instantly.
##  * Burst = FloatingHealthBarBurstData: damage inside burstTimeWindow >= burstTriggerPercent of max HP shows the
##    BurstFadeMeter chunk (its own hold/speed/acceleration), flashTriggerPercent flashes the DamageFlashMeter for
##    flashDuration, shakeTriggerPercent shakes the bar inside shakeBox at shakeFrequency for shakeDuration.
##    Champions use the class defaults (35%), structures set 10%.
##  * Burst heal (champions) = FloatingHealthBarBurstHealData: >= 10% healed within 0.1 s glows for 0.2 s.
##  * Ticks = HealthBarTickStyleHero: a standard tick every 1000 HP, MicroTicksPerStandardTickData by max HP.
##  * Height = CharacterRecord.healthBarHeight (+ healthBarFullParallax) - see _anchor().
##  * Bar death = DeathAnimAlly/Enemy flipbooks (champions, structures).
##
## Perf: every layout element is resolved once into an `El` (anchor-relative screen rect + atlas UV), per-unit
## state lives in a pooled `BarState` (fade/burst/flash + shaped name TextLine), HP ticks are one multiline
## per champion, and nothing allocates strings per frame.

const REF_SCALE := 1080.0 / 1200.0   ## our canvas is 1080 tall (canvas_items stretch); League's UI ref is 1200
const TICK_COL := Color(0.0, 0.0, 0.0, 0.85)
const MICRO_COL := Color(0.0, 0.0, 0.0, 0.7)
const NAME_OUTLINE := Color(0, 0, 0, 0.85)
const LEVEL_UP_FX := ["LevelUp_glb", "LevelUp", "Global_LevelUp", "LevelUp_Global", "Jade_LevelUp", "Global_Levelup"]
const CC_MASK := Buff.CC.STUN | Buff.CC.AIRBORNE | Buff.CC.SUPPRESS | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP
const DEFAULT_HBH := 100.0           ## CharacterRecord.healthBarHeight class default (lol-meta-classes)

## One League FHB element, pre-placed relative to its bar's anchor at our canvas scale.
class El:
	var rel := Rect2()
	var uv := Rect2()
	var col := Color.WHITE
	var ok := false

	func at(sp: Vector2) -> Rect2:
		return Rect2(sp + rel.position, rel.size)

## League bar timing for one bar style (HealthBarFadeData + FloatingHealthBarBurstData + BurstHealData).
class Cfg:
	var fade := false
	var f_hold := 0.05
	var f_speed := 0.5
	var f_accel := 5.0
	var burst := false
	var b_window := 0.1
	var b_trig := 0.35
	var fl_trig := 0.35
	var sh_trig := 0.35
	var b_hold := 0.2
	var b_speed := 0.05
	var b_accel := 1.0
	var fl_dur := 0.3
	var sh_dur := 0.4
	var sh_freq := 10.0
	var sh_box := Vector2(8.0, 3.5)    ## canvas px (scaled from shakeReferenceResolution)
	var heal := false
	var h_window := 0.1
	var h_trig := 0.1
	var h_dur := 0.2

## Per-unit bar state (HP units) and cached shaped text.
class BarState:
	var inited := false
	var alive := true
	var last_hp := 0.0                ## HP + shields last frame
	var last_raw := 0.0
	var fade_hp := 0.0
	var fade_hold := 0.0
	var fade_vel := 0.0
	var burst_hp := 0.0
	var burst_hold := 0.0
	var burst_vel := 0.0
	var win_t0 := -10.0
	var win_hp0 := 0.0
	var hwin_t0 := -10.0
	var hwin_hp0 := 0.0
	var flash_t := 0.0
	var flash_hi := 0.0
	var shake_t := 0.0
	var heal_t := 0.0
	var heal_lo := 0.0
	var heal_hi := 0.0
	var hbh := -1.0                  ## healthBarHeight (League units)
	var full := false                ## healthBarFullParallax
	var name_str := ""
	var name_line: TextLine
	var seen := 0
	var tick_total := -1
	var ticks := PackedVector2Array()
	var bigticks := PackedVector2Array()

## A bar playing its League death flipbook after the unit died.
class DeathFx:
	var world := Vector3.ZERO
	var hbh := 0.0
	var full := false
	var t0 := 0.0
	var el: El
	var frames := 25
	var per_row := 5
	var fps := 40.0
	var tex: Texture2D

var match_ref = null
var rig: CameraRig = null
var ft: FloatingTextSystem
var atlas: Texture2D
var L := {}                          ## fhb_layout.json: element name -> {pos, size, uv, color}
var B := {}                          ## fhb_behaviour.json
var font_name: Font
var font_level: Font
var _bars := {}                      ## unit instance id -> BarState
var _deaths: Array[DeathFx] = []
var _turret_rings: TurretRangeRings
var _name_col := Color8(185, 185, 185)
var _self_name_col := Color.WHITE
var _frame := 0
var _time := 0.0
var _ci: RID
var _cam_up := Vector3.UP
var _cam: Camera3D

# ---- League bar configs
var _cfg_hero := Cfg.new()
var _cfg_struct := Cfg.new()
var _cfg_obj := Cfg.new()
var _micro_table: Array = []          ## [[minHealth, microTicksBetween], ...] ascending
var _hp_per_tick := 1000.0
var _units := {}                      ## character -> [healthBarHeight, fullParallax, style]

# ---- team colours (HudColorData; the grey unit/structure bar textures are tinted with these)
var _lane_ally := Color8(85, 165, 230)
var _lane_enemy := Color8(230, 104, 104)
var _team_ally := Color8(81, 162, 230)
var _team_enemy := Color8(232, 61, 50)
var _lvl_self := Color.WHITE
var _lvl_ally := Color8(239, 251, 255)
var _lvl_enemy := Color8(255, 235, 235)

# ---- pre-resolved elements
var _c_border: Array[El] = []        ## [Default, Invuln]
var _c_levelbox: Array[El] = []      ## state * 3 + (Self, Blue, Red)
var _c_highlight: El
var _c_hp: El
var _c_hp_tex: Array[El] = []        ## Green (self), Blue, Red
var _c_fade: El                      ## ally/self chunk (red)
var _c_fade_enemy: El                ## enemy chunk (yellow)
var _c_burst_self: El                ## BurstFadeMeterSelf (red)
var _c_burst_other: El               ## BurstFadeMeterOther (orange gradient)
var _c_flash: El
var _c_heal: El
var _c_shield: Array[El] = []        ## generic, physical, magic
var _c_micro: El
var _c_tick: El
var _c_par: El
var _c_par_tex := {}                 ## resource kind -> El
var _c_level: El
var _c_name: El
var _c_status: El
var _c_status_bar: El
var _c_death: Array[El] = []         ## Blue (ally/self), Red (enemy)
var _m_border: Array[El] = []        ## Small, Med
var _m_highlight: Array[El] = []
var _m_hp: Array[El] = []
var _m_aggro: Array[El] = []
## structure styles: 0 = Structure (inhibitor), 1 = EpicStructure (turrets, nexus)
var _s_border: Array[El] = []
var _s_highlight: Array[El] = []
var _s_hp: Array[El] = []
var _s_shield: Array[El] = []
var _s_fade: Array[El] = []
var _s_fade_enemy: Array[El] = []
var _s_burst: Array[El] = []
var _s_flash: Array[El] = []
var _s_aggro: Array[El] = []
var _s_death: Array[El] = []         ## style * 2 + (Blue, Red)
var _o_border: El                    ## Obj (Tibbers)
var _o_highlight: El
var _o_hp: El
var _o_fade: El
var _o_fade_enemy: El
var _o_shield: El
var _tex_death_champ: Texture2D
var _tex_death_struct: Texture2D
var _level_lines: Array[TextLine] = []
var _champ_sp: Array[Vector3] = []   ## per frame: screen x, y, index into _champ_q
var _champ_q: Array = []
var _cc_lines := {}
var _level_fs := 11
var _name_fs := 12


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ft = FloatingTextSystem.new()
	atlas = load("res://assets/ui/world/fhb_atlas.png")
	var lp := "res://assets/ui/world/fhb_layout.json"
	if FileAccess.file_exists(lp):
		L = JSON.parse_string(FileAccess.get_file_as_string(lp))
	var bp := "res://assets/ui/world/fhb_behaviour.json"
	if FileAccess.file_exists(bp):
		B = JSON.parse_string(FileAccess.get_file_as_string(bp))
	for p in ["res://assets/ui/world/fhb_death_champ.png", "res://assets/ui/world/fhb_death_struct.png"]:
		if ResourceLoader.exists(p):
			if p.ends_with("champ.png"):
				_tex_death_champ = load(p)
			else:
				_tex_death_struct = load(p)
	font_name = Assets.font("spiegel", "Bold")      # HealthBarTitle: Spiegel Bold 12, rgb 185
	font_level = Assets.font("beaufort", "Bold")    # HealthBarLevel: Beaufort Bold 11, white
	var tn: Dictionary = ft.types.get("HealthBarTitle", {})
	_name_col = FloatingTextSystem._col(tn.get("color"), _name_col)
	_build_behaviour()
	_build_layout()
	_ci = get_canvas_item()
	if match_ref != null:
		_turret_rings = TurretRangeRings.new()
		_turret_rings.name = "TurretRangeRings"
		_turret_rings.match_ref = match_ref
		match_ref.add_child.call_deferred(_turret_rings)


func _el(n: String, anchor: String) -> El:
	var r := El.new()
	var e: Dictionary = L.get(n, {})
	var a: Dictionary = L.get(anchor, {})
	if e.is_empty() or a.is_empty():
		return r
	var p := (Vector2(e.pos[0] - a.pos[0], e.pos[1] - a.pos[1]) * REF_SCALE).round()
	r.rel = Rect2(p, (Vector2(e.size[0], e.size[1]) * REF_SCALE).round())
	if e.has("uv"):
		var u: Array = e.uv
		r.uv = Rect2(u[0], u[1], u[2] - u[0], u[3] - u[1])
	r.col = FloatingTextSystem._col(e.get("color"), Color.WHITE)
	r.ok = r.rel.size.x > 0.0
	return r


## Timing for one InfoBarStyleSourceMap entry (fhb_behaviour.json); the Cfg defaults are the class defaults.
func _cfg_from(style: String, c: Cfg) -> void:
	var s: Dictionary = B.get("styles", {}).get(style, {})
	var f: Dictionary = s.get("fade", {})
	c.fade = not f.is_empty()
	c.f_hold = float(f.get("fadeHoldTime", c.f_hold))
	c.f_speed = float(f.get("fadeSpeed", c.f_speed))
	c.f_accel = float(f.get("fadeAcceleration", c.f_accel))
	var b: Dictionary = s.get("burst", {})
	c.burst = not b.is_empty()
	c.b_window = float(b.get("burstTimeWindow", c.b_window))
	c.b_trig = float(b.get("burstTriggerPercent", c.b_trig))
	c.fl_trig = float(b.get("flashTriggerPercent", c.fl_trig))
	c.sh_trig = float(b.get("shakeTriggerPercent", c.sh_trig))
	c.b_hold = float(b.get("fadeHoldTime", c.b_hold))
	c.b_speed = float(b.get("fadeSpeed", c.b_speed))
	c.b_accel = float(b.get("fadeAcceleration", c.b_accel))
	c.fl_dur = float(b.get("flashDuration", c.fl_dur))
	c.sh_dur = float(b.get("shakeDuration", c.sh_dur))
	c.sh_freq = float(b.get("shakeFrequency", c.sh_freq))
	var box: Array = b.get("shakeBox", [8.0, 3.5])
	var ref: Array = b.get("shakeReferenceResolution", [1024.0, 768.0])
	c.sh_box = Vector2(box[0], box[1]) * (1080.0 / float(ref[1]))
	var h: Dictionary = s.get("heal", {})
	c.heal = not h.is_empty()
	c.h_window = float(h.get("healTimeWindow", c.h_window))
	c.h_trig = float(h.get("healTriggerPercent", c.h_trig))
	c.h_dur = float(h.get("healFadeDuration", c.h_dur))


func _build_behaviour() -> void:
	if B.is_empty():
		# extractor not re-run yet: League values (see the header) so behaviour stays correct
		B = {"styles": {
			"12": {"fade": {"fadeSpeed": 0.05}, "burst": {}, "heal": {},
					"ticks": {"per_standard": 1000.0, "micro": [[3000, 7], [3500, 6], [4000, 5], [5000, 4], [6000, 3],
							[7000, 2], [8000, 2], [9000, 1], [10000, 0]]}},
			"8": {"fade": {}, "burst": {"burstTriggerPercent": 0.1, "flashTriggerPercent": 0.1, "shakeTriggerPercent": 0.1}},
			"3": {"fade": {}, "burst": {"burstTriggerPercent": 0.1, "flashTriggerPercent": 0.1, "shakeTriggerPercent": 0.1}},
			"5": {"fade": {}}}}
	_cfg_from("12", _cfg_hero)
	_cfg_from("8", _cfg_struct)
	_cfg_from("5", _cfg_obj)
	var tk: Dictionary = B.get("styles", {}).get("12", {}).get("ticks", {})
	_hp_per_tick = float(tk.get("per_standard", 1000.0))
	_micro_table = tk.get("micro", [])
	_units = B.get("units", {
		"HA_OrderMinionMelee": [42, false, 0], "HA_ChaosMinionMelee": [37, false, 0],
		"HA_OrderMinionRanged": [41, false, 0], "HA_ChaosMinionRanged": [33, false, 0],
		"HA_OrderMinionSiege": [52, false, 0], "HA_ChaosMinionSiege": [52, false, 0],
		"HA_OrderMinionSuper": [68, false, 1], "HA_ChaosMinionSuper": [71, false, 1],
		"Turret": [525, true, 8], "Inhibitor": [370, true, 3], "Nexus": [500, true, 8], "AnnieTibbers": [92, false, 5]})
	var hc: Dictionary = B.get("hud_colors", {})
	_lane_ally = FloatingTextSystem._col(hc.get("mFriendlyLaneMinionBarColor"), _lane_ally)
	_lane_enemy = FloatingTextSystem._col(hc.get("mEnemyLaneMinionBarColor"), _lane_enemy)
	_team_ally = FloatingTextSystem._col(hc.get("mFriendlyColor"), _team_ally)
	_team_enemy = FloatingTextSystem._col(hc.get("mEnemyColor"), _team_enemy)
	var lt: Dictionary = B.get("styles", {}).get("12", {}).get("level_text", {})
	_lvl_self = FloatingTextSystem._col(lt.get("LevelTextColorSelf"), _lvl_self)
	_lvl_ally = FloatingTextSystem._col(lt.get("LevelTextColorAlly"), _lvl_ally)
	_lvl_enemy = FloatingTextSystem._col(lt.get("LevelTextColorEnemy"), _lvl_enemy)


func _build_layout() -> void:
	const A := "ChampFHB_AnchorBase"
	for st in ["Default", "Invuln"]:
		_c_border.append(_el("ChampFHB_Border_" + st, A))
		for sfx in ["Self", "Blue", "Red"]:
			_c_levelbox.append(_el("ChampFHB_LevelBox_%s_%s" % [st, sfx], A))
	_c_highlight = _el("ChampFHB_Highlight_Default", A)
	_c_hp = _el("ChampHP_BarTextureGreen", A)
	for t in ["Green", "Blue", "Red"]:
		_c_hp_tex.append(_el("ChampHP_BarTexture" + t, A))
	_c_fade = _el("ChampHP_BarFade", A)
	_c_fade_enemy = _el("ChampHP_BarFadeEnemy", A)
	_c_burst_self = _el("ChampHP_BarFadeBurstRed", A)
	_c_burst_other = _el("ChampHP_BarFadeBurst", A)
	_c_flash = _el("ChampHP_BarFlash", A)
	_c_heal = _el("ChampHP_BarFadeHealGreen", A)
	for t in ["A", "P", "M"]:
		_c_shield.append(_el("ChampHP_%sShieldBarTexture" % t, A))
	_c_micro = _el("ChampHP_MicroTick", A)
	_c_tick = _el("ChampHP_Tick", A)
	_c_par = _el("ChampPAR_BarTextureBlue", A)
	for t in ["Blue", "Yellow", "Red", "White"]:
		_c_par_tex[t] = _el("ChampPAR_BarTexture" + t, A)
	_c_level = _el("ChampFHB_Text_Level", A)
	_c_name = _el("ChampFHB_Text_Name", A)
	_c_status = _el("ChampFHB_Text_Status", A)
	_c_status_bar = _el("ChampFHB_BarTextureStatus", A)
	_c_death = [_el("ChampFHB_DeathBlue", A), _el("ChampFHB_DeathRed", A)]
	for sz in ["Small", "Med"]:
		var ma := "Minion%sFHB_AnchorBase" % sz
		_m_border.append(_el("Minion%sFHB_Border_Default" % sz, ma))
		_m_highlight.append(_el("Minion%sFHB_Highlight_Default" % sz, ma))
		_m_hp.append(_el("Minion%sHP_BarTexture" % sz, ma))
		_m_aggro.append(_el("Minion%sFHB_Aggro" % sz, ma))
	for pre in ["Structure", "EpicStructure"]:
		var sa: String = pre + "FHB_AnchorBase"
		_s_border.append(_el(pre + "FHB_Border_Default", sa))
		_s_highlight.append(_el(pre + "FHB_Highlight_Default", sa))
		_s_hp.append(_el(pre + "HP_BarTexture", sa))
		_s_shield.append(_el(pre + "HP_AShieldBarTexture", sa))
		_s_fade.append(_el(pre + "HP_BarFade", sa))
		_s_fade_enemy.append(_el(pre + "HP_BarFadeEnemy", sa))
		_s_burst.append(_el(pre + "HP_BarFadeBurst", sa))
		_s_flash.append(_el(pre + "HP_BarFlash", sa))
		_s_aggro.append(_el(pre + "FHB_Aggro", sa))
		_s_death.append(_el(pre + "FHB_DeathBlue", sa))
		_s_death.append(_el(pre + "FHB_DeathRed", sa))
	const O := "ObjFHB_AnchorBase"
	_o_border = _el("ObjFHB_Border_Default", O)
	_o_highlight = _el("ObjFHB_Highlight_Default", O)
	_o_hp = _el("ObjHP_BarTexture", O)
	_o_fade = _el("ObjHP_BarFade", O)
	_o_fade_enemy = _el("ObjHP_BarFadeEnemy", O)
	_o_shield = _el("ObjHP_AShieldBarTexture", O)
	# text: sizes fixed once, level digits shaped once (pre-warms the glyph cache too)
	_level_fs = maxi(int(round(11.0 * REF_SCALE * 1.15)), 9)
	_name_fs = maxi(int(round(12.0 * REF_SCALE * 1.1)), 9)
	for lv in 31:
		var tl := TextLine.new()
		tl.add_string(str(lv), font_level, _level_fs)
		_level_lines.append(tl)


func _process(delta: float) -> void:
	var ppt := Prof.t0()
	_process_frame(delta)
	Prof.add("proc.overlay", ppt)


func _process_frame(delta: float) -> void:
	var dt := minf(delta, 0.05)
	ft.update(dt)
	_frame += 1
	_time += dt
	if _frame % 300 == 0:
		for id in _bars.keys():
			if not is_instance_id_valid(id) or _frame - _bars[id].seen > 600:
				_bars.erase(id)
	queue_redraw()


func _draw() -> void:
	var pt := Prof.t0()
	_draw_frame()
	Prof.add("draw.overlay", pt)


## healthBarHeight / healthBarFullParallax / style for a unit, cached on its BarState.
func _unit_info(u, b: BarState) -> void:
	var rec = null
	match u.kind:
		G.Kind.CHAMPION:
			var s: Dictionary = u.data.get("stats", {}) if u.data is Dictionary else {}
			rec = [float(s.get("healthBarHeight", DEFAULT_HBH)), false, 12]
		G.Kind.MINION:
			var side := "Order" if u.team == G.Team.ORDER else "Chaos"
			var nm: String = ["Melee", "Ranged", "Siege", "Super"][clampi(u.minion_type, 0, 3)]
			rec = _units.get("HA_%sMinion%s" % [side, nm])
		G.Kind.TURRET:
			rec = _units.get("Turret")
		G.Kind.INHIBITOR:
			rec = _units.get("Inhibitor")
		G.Kind.NEXUS:
			rec = _units.get("Nexus")
		G.Kind.SUMMON:
			rec = _units.get("AnnieTibbers")
	if rec == null:
		rec = [u.height / G.U * 0.5, false, 0]
	b.hbh = float(rec[0])
	b.full = bool(rec[1])


func _state(u) -> BarState:
	var id: int = u.get_instance_id()
	var b: BarState = _bars.get(id)
	if b == null:
		b = BarState.new()
		_bars[id] = b
	if b.hbh < 0.0:
		_unit_info(u, b)
	return b


## League bar anchor (the AnchorBase point = bottom centre of the frame). healthBarHeight lifts the bar along the
## camera's up axis in world space, so it scales with zoom (parallax); bars without healthBarFullParallax
## (champions, minions) add the same height again as a fixed screen offset at the 1200-px UI reference.
## The data has no formula for this: it was fitted to real ARAM frames (720p, default zoom: bar bottom above the
## unit's feet = Quinn 105 -> ~90 px, Brand 100 -> ~93 px, melee minion 42 -> ~42 px, outer turret 525 -> ~205 px).
func _anchor(world: Vector3, hbh: float, full: bool, scale: float) -> Vector2:
	var sp := _cam.unproject_position(world + _cam_up * (hbh * G.U * scale))
	if not full:
		sp.y -= hbh * REF_SCALE
	return sp


func _draw_frame() -> void:
	ft.prewarm(self)
	if match_ref == null or rig == null or G.player == null:
		return
	if _frame < 3:
		_prewarm_names()
	var cam := rig.cam
	_cam = cam
	_cam_up = cam.global_transform.basis.y
	var my_team: int = G.player.team
	var pc = match_ref.player_controller
	var hov: Unit = pc.hovered if pc != null else null
	# turret aggro line (League: thin red targeting line from the turret to the champion it attacks)
	for s in match_ref.structures:
		if s.kind == G.Kind.TURRET and not s.dead and s.aggro_line_target == G.player:
			var a := cam.unproject_position(s.global_position + Vector3(0, s.height * 0.9, 0))
			var b := cam.unproject_position(G.player.global_position + Vector3(0, 1.0, 0))
			var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
			draw_line(a, b, Color(1, 0.1, 0.05, 0.25 * pulse), 6.0, true)
			draw_line(a, b, Color(1, 0.25, 0.15, 0.9 * pulse), 2.0, true)
	var dt := minf(get_process_delta_time(), 0.05)
	var w := size.x + 150.0
	var h := size.y + 150.0
	for u in match_ref.units:
		if u.kind == G.Kind.TURRET and u.tier == Turret.Tier.FOUNTAIN:
			continue
		if u.dead:
			_on_dead(u, my_team)
			continue
		if u.team != my_team and not u.visible_to[my_team]:
			continue
		if u.model != null and not u.model.visible:
			continue
		var base: Vector3 = u.global_position
		base.y += u.airborne_height
		if cam.is_position_behind(base):
			continue
		var b := _state(u)
		if not b.alive:
			b.alive = true
			b.inited = false
		var sp := _anchor(base, b.hbh, b.full, u.stats.size)
		if sp.x < -150.0 or sp.y < -100.0 or sp.x > w or sp.y > h:
			continue
		sp = sp.round()
		b.seen = _frame
		match u.kind:
			G.Kind.CHAMPION:
				_champ_sp.append(Vector3(sp.x, sp.y, _champ_q.size()))
				_champ_q.append(u)
			G.Kind.MINION:
				_draw_minion_bar(u, sp, my_team, u == hov)
			G.Kind.SUMMON:
				_draw_obj_bar(u, b, sp, my_team, dt, u == hov)
			G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
				_draw_structure_bar(u, b, sp, my_team, dt, u == hov)
	# champion bars above minion/structure bars, back-to-front (lower on screen = nearer = drawn last)
	if not _champ_sp.is_empty():
		_champ_sp.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
		for e in _champ_sp:
			var cu: Unit = _champ_q[int(e.z)]
			_draw_champion_bar(cu, _bars[cu.get_instance_id()], Vector2(e.x, e.y), my_team, dt, cu == hov)
		_champ_sp.clear()
		_champ_q.clear()
	_draw_deaths()
	ft.draw(self, cam)


# ------------------------------------------------------------------ atlas helpers
func _icon(e: El, sp: Vector2, mod := Color.WHITE) -> void:
	if e.ok:
		draw_texture_rect_region(atlas, Rect2(sp + e.rel.position, e.rel.size), e.uv, mod)


## Meter fill: the `f0..f1` fraction of the bar rect, cropping texture element `tex` the same way
## (League meters are PerPixelUvsX icons).
func _meter(tex: El, r: Rect2, f0: float, f1: float, mod := Color.WHITE) -> void:
	f0 = clampf(f0, 0.0, 1.0)
	f1 = clampf(f1, 0.0, 1.0)
	if f1 - f0 <= 0.0005:
		return
	var uv := tex.uv
	var x0 := roundf(r.position.x + r.size.x * f0)
	var x1 := roundf(r.position.x + r.size.x * f1)
	if x1 - x0 < 1.0:
		x1 = x0 + 1.0
	draw_texture_rect_region(atlas, Rect2(x0, r.position.y, x1 - x0, r.size.y),
			Rect2(uv.position.x + uv.size.x * f0, uv.position.y, uv.size.x * (f1 - f0), uv.size.y), mod)


## League bar animation state for one frame (HP units). `eff` = HP + shields (what the fill shows), `hp` = HP.
## Losing effective health (HP or shield) starts a lost-health chunk at the end of the fill (it holds, then drains
## with acceleration); a big loss inside the burst window also starts the burst chunk, the flash and the shake;
## a big heal inside the heal window glows. A chunk that is already draining keeps its speed when new damage lands.
func _track(b: BarState, hp: float, eff: float, maxhp: float, c: Cfg, dt: float) -> void:
	if not b.inited:
		b.inited = true
		b.last_hp = eff
		b.last_raw = hp
		b.fade_hp = eff
		b.burst_hp = eff
		b.flash_t = 0.0
		b.shake_t = 0.0
		b.heal_t = 0.0
	b.flash_t = maxf(b.flash_t - dt, 0.0)
	b.shake_t = maxf(b.shake_t - dt, 0.0)
	b.heal_t = maxf(b.heal_t - dt, 0.0)
	var eps := maxhp * 0.0005
	if eff < b.last_hp - eps:
		if _time - b.win_t0 > c.b_window:
			b.win_t0 = _time
			b.win_hp0 = b.last_hp
		var wd := (b.win_hp0 - eff) / maxhp
		if c.fade and b.fade_hp <= b.last_hp + eps:
			b.fade_hp = b.last_hp
			b.fade_hold = c.f_hold
			b.fade_vel = c.f_speed
		if b.burst_hp <= b.last_hp + eps:
			b.burst_hp = eff          # no burst chunk showing: it starts only when the trigger is met
		if c.burst:
			if wd >= c.b_trig and b.burst_hp < b.win_hp0 - eps:
				b.burst_hp = b.win_hp0
				b.burst_hold = c.b_hold
				b.burst_vel = c.b_speed
			if wd >= c.fl_trig:
				b.flash_hi = maxf(b.flash_hi, b.win_hp0) if b.flash_t > 0.0 else b.win_hp0
				b.flash_t = c.fl_dur
			if wd >= c.sh_trig and b.shake_t <= 0.0:
				b.shake_t = c.sh_dur
	if hp > b.last_raw + eps and c.heal:
		if _time - b.hwin_t0 > c.h_window:
			b.hwin_t0 = _time
			b.hwin_hp0 = b.last_raw
		if (hp - b.hwin_hp0) / maxhp >= c.h_trig:
			b.heal_t = c.h_dur
			b.heal_lo = b.hwin_hp0
			b.heal_hi = hp
	b.last_hp = eff
	b.last_raw = hp
	var total := maxf(maxhp, eff)
	hp = eff
	# drain (bar fractions per second -> HP)
	if b.fade_hp > hp:
		if b.fade_hold > 0.0:
			b.fade_hold -= dt
		else:
			b.fade_vel += c.f_accel * dt
			b.fade_hp = maxf(hp, b.fade_hp - b.fade_vel * dt * total)
	else:
		b.fade_hp = hp
	if b.burst_hp > hp:
		if b.burst_hold > 0.0:
			b.burst_hold -= dt
		else:
			b.burst_vel += c.b_accel * dt
			b.burst_hp = maxf(hp, b.burst_hp - b.burst_vel * dt * total)
	else:
		b.burst_hp = hp


## FloatingHealthBarBurstData shake: a new offset inside shakeBox shakeFrequency times per second.
func _shake(b: BarState, c: Cfg, id: int) -> Vector2:
	if b.shake_t <= 0.0:
		return Vector2.ZERO
	var k := int((c.sh_dur - b.shake_t) * c.sh_freq)
	var hx := float(absi(hash(id * 31 + k)) % 1000) / 999.0 - 0.5
	var hy := float(absi(hash(id * 17 + k * 7 + 3)) % 1000) / 999.0 - 0.5
	return Vector2(roundf(hx * c.sh_box.x), roundf(hy * c.sh_box.y))


## Lost-health chunk, burst chunk and damage flash under the HP fill (League layers 4 / 5 / 6 under 10).
func _chunks(b: BarState, hr: Rect2, hp: float, total: float, fade: El, burst: El, flash: El, c: Cfg) -> void:
	var f := hp / total
	if c.fade and b.fade_hp > hp:
		_meter(fade, hr, f, b.fade_hp / total, fade.col)
	if c.burst and b.burst_hp > hp:
		_meter(burst, hr, f, b.burst_hp / total, burst.col)
	if b.flash_t > 0.0 and b.flash_hi > hp:
		var fc := flash.col
		fc.a = b.flash_t / c.fl_dur
		_meter(flash, hr, f, b.flash_hi / total, fc)


# ------------------------------------------------------------------ champion
func _draw_champion_bar(u, b: BarState, sp: Vector2, my_team: int, dt: float, hovered: bool) -> void:
	var is_self: bool = u == G.player
	var ally: bool = u.team == my_team
	var si := 0 if is_self else (1 if ally else 2)
	var st := 1 if u.is_invulnerable() else 0
	# health meter: fill scales to max(maxHP, HP + shields), shields appended after HP (League)
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var sh_p := 0.0
	var sh_m := 0.0
	var sh_gen := 0.0
	for s in u.shields:
		if s.type == G.DmgType.PHYSICAL:
			sh_p += s.amount
		elif s.type == G.DmgType.MAGIC:
			sh_m += s.amount
		else:
			sh_gen += s.amount
	var hp: float = clampf(u.hp, 0.0, maxhp)
	var total := maxf(maxhp, hp + sh_p + sh_m + sh_gen)
	var eff := hp + sh_p + sh_m + sh_gen
	_track(b, hp, eff, maxhp, _cfg_hero, dt)
	sp += _shake(b, _cfg_hero, u.get_instance_id())
	# level box under the border, then the border/frame
	_icon(_c_levelbox[st * 3 + si], sp)
	_icon(_c_border[st], sp)
	if hovered:
		_icon(_c_highlight, sp)
	var hr := _c_hp.at(sp)
	_chunks(b, hr, eff, total, _c_fade if ally else _c_fade_enemy, _c_burst_self if is_self else _c_burst_other,
			_c_flash, _cfg_hero)
	var f_hp := hp / total
	_meter(_c_hp_tex[si], hr, 0.0, f_hp)
	var f := f_hp
	if sh_gen > 0.5:
		_meter(_c_shield[0], hr, f, f + sh_gen / total)
		f += sh_gen / total
	if sh_p > 0.5:
		_meter(_c_shield[1], hr, f, f + sh_p / total)
		f += sh_p / total
	if sh_m > 0.5:
		_meter(_c_shield[2], hr, f, f + sh_m / total)
	# burst heal glow over the healed segment (League layer 11, above the fill)
	if b.heal_t > 0.0:
		var hc := _c_heal.col
		hc.a = b.heal_t / _cfg_hero.h_dur
		_meter(_c_heal, hr, b.heal_lo / total, minf(b.heal_hi, hp) / total, hc)
	# HP ticks (HealthBarTickStyleHero): standard tick every HealthPerstandardTick, micro ticks between them by
	# max HP. The anchor-relative tick lines are rebuilt only when the bar's total changes.
	var tot_key := int(total)
	if tot_key != b.tick_total:
		b.tick_total = tot_key
		_build_ticks(b, total, maxhp)
	if not b.ticks.is_empty() or not b.bigticks.is_empty():
		draw_set_transform(sp)
		if not b.ticks.is_empty():
			draw_multiline(b.ticks, MICRO_COL, 1.0)
		if not b.bigticks.is_empty():
			draw_multiline(b.bigticks, TICK_COL, maxf(_c_tick.rel.size.x, 2.0))
		draw_set_transform(Vector2.ZERO)
	# resource (PAR) bar
	if u.stats.max_mana > 0.0:
		var kind := "Blue"
		match u.resource_name:
			"Energy":
				kind = "Yellow"
			"Fury", "Rage", "Bloodthirst", "Heat":
				kind = "Red"
			"Flow", "Courage", "Ferocity", "Grit", "Frenzy":
				kind = "White"
		_meter(_c_par_tex[kind], _c_par.at(sp), 0.0, u.mana / u.stats.max_mana)
	# level (Beaufort Bold; LevelTextColorSelf / Ally / Enemy), centred in the level box
	var lv: int = clampi(u.level, 0, 30)
	var tl: TextLine = _level_lines[lv]
	var lr := _c_level.at(sp)
	var lsz := tl.get_size()
	tl.draw(_ci, (lr.get_center() - lsz * 0.5).round(), _lvl_self if is_self else (_lvl_ally if ally else _lvl_enemy))
	var nr := _c_name.at(sp)
	# League: while hard-CC'd the name slot shows the status text (HealthBarStatusTitle, Beaufort Bold, white)
	# with a thin CC-duration bar (BarTextureStatus) under it, instead of the name
	var cc_frac := -1.0
	if (u.cc & CC_MASK) != 0:
		cc_frac = 0.0
		for bf in u.buffs:
			if (bf.cc & CC_MASK) != 0 and bf.duration > 0.0:
				cc_frac = maxf(cc_frac, bf.remaining / bf.duration)
	if cc_frac >= 0.0:
		var cl := _cc_line(_cc_name(u.cc))
		var srr := _c_status.at(sp)
		var cp := Vector2(srr.position.x, roundf(srr.end.y - 1.0 - cl.get_line_ascent()))
		cl.draw_outline(_ci, cp, 3, Color(0, 0, 0, 0.9))
		cl.draw(_ci, cp, Color.WHITE)
		_meter(_c_status_bar, _c_status_bar.at(sp), 0.0, cc_frac)
	else:
		# name above the frame (League: Spiegel Bold 12, grey 185; own name white) - shaped once per unit
		var nm: String = u.display_name
		if b.name_str != nm or b.name_line == null:
			b.name_str = nm
			b.name_line = TextLine.new()
			b.name_line.add_string(nm, font_name, _name_fs)
		var nsz := b.name_line.get_size()
		var npos := Vector2(roundf(nr.get_center().x - nsz.x * 0.5), roundf(nr.end.y - 1.0 - b.name_line.get_line_ascent()))
		b.name_line.draw_outline(_ci, npos, 3, NAME_OUTLINE)
		b.name_line.draw(_ci, npos, _self_name_col if is_self else _name_col)
	# channel / cast bar (League draws it under the frame)
	var ch: Dictionary = u.channel
	if not ch.is_empty():
		var k := 1.0 - clampf(ch.t / maxf(ch.total, 0.01), 0.0, 1.0)
		var cr := Rect2(hr.position + Vector2(0, roundf(30 * REF_SCALE)), Vector2(hr.size.x, roundf(5 * REF_SCALE)))
		draw_rect(cr.grow(1.0), Color(0.02, 0.03, 0.04, 0.9))
		_meter(_c_par_tex["Yellow"], cr, 0.0, k)


## Micro ticks between standard ticks for this max HP (MicroTicksPerStandardTickData: the last entry whose
## minHealth <= max HP; below the first entry the class default, 9).
func _micro_between(maxhp: float) -> int:
	var n := 9
	for e in _micro_table:
		if maxhp >= float(e[0]):
			n = int(e[1])
	return n


func _build_ticks(b: BarState, total: float, maxhp: float) -> void:
	b.ticks = PackedVector2Array()
	b.bigticks = PackedVector2Array()
	var micro := _hp_per_tick / float(_micro_between(maxhp) + 1)
	var n := int(total / micro)
	if n <= 0 or n > 400:
		return
	var hr := _c_hp.rel
	var my := _c_micro.rel.position.y
	var mh := _c_micro.rel.size.y
	var by := _c_tick.rel.position.y
	var bh := _c_tick.rel.size.y
	var step := hr.size.x * micro / total
	var per := _micro_between(maxhp) + 1
	for i in range(1, n + 1):
		var x := roundf(hr.position.x + step * i)
		if x >= hr.end.x - 1.0:
			break
		if i % per == 0:
			b.bigticks.append(Vector2(x, by))
			b.bigticks.append(Vector2(x, by + bh))
		else:
			b.ticks.append(Vector2(x + 0.5, my))
			b.ticks.append(Vector2(x + 0.5, my + mh))


## Shape every champion name (and rasterise its glyphs off-canvas) before the first fight.
func _prewarm_names() -> void:
	for c in match_ref.champions:
		var b := _state(c)
		if b.name_line != null:
			continue
		b.name_str = c.display_name
		b.name_line = TextLine.new()
		b.name_line.add_string(b.name_str, font_name, _name_fs)
		b.name_line.draw_outline(_ci, Vector2(-4000, -4000), 3, NAME_OUTLINE)
		b.name_line.draw(_ci, Vector2(-4000, -4000))
	for t in ["STUNNED", "AIRBORNE", "SUPPRESSED", "CHARMED", "FEARED", "TAUNTED", "ASLEEP"]:
		var cl := _cc_line(t)
		cl.draw_outline(_ci, Vector2(-4000, -4000), 3, Color.BLACK)
		cl.draw(_ci, Vector2(-4000, -4000))


func _cc_line(t: String) -> TextLine:
	var tl: TextLine = _cc_lines.get(t)
	if tl == null:
		tl = TextLine.new()
		tl.add_string(t, font_level, maxi(int(round(13.0 * REF_SCALE * 1.1)), 9))   # fits the 13 px Text_Status slot
		_cc_lines[t] = tl
	return tl


func _cc_name(c: int) -> String:
	if c & Buff.CC.SUPPRESS:
		return "SUPPRESSED"
	if c & Buff.CC.STUN:
		return "STUNNED"
	if c & Buff.CC.AIRBORNE:
		return "AIRBORNE"
	if c & Buff.CC.CHARM:
		return "CHARMED"
	if c & Buff.CC.FEAR:
		return "FEARED"
	if c & Buff.CC.TAUNT:
		return "TAUNTED"
	if c & Buff.CC.SLEEP:
		return "ASLEEP"
	return ""


# ------------------------------------------------------------------ minions
## Lane minions: MinionSmall (melee, caster, siege) / MinionMed (super), grey fill tinted with HudColorData's
## lane-minion colours. Their bar data has no fadeData or burstData, so the fill drops instantly.
func _draw_minion_bar(u, sp: Vector2, my_team: int, hovered: bool) -> void:
	var si := 1 if u.minion_type == Minion.Type.SUPER else 0
	var enemy: bool = u.team != my_team
	_icon(_m_border[si], sp)
	if hovered:
		_icon(_m_highlight[si], sp)
	var tex: El = _m_hp[si]
	_meter(tex, tex.at(sp), 0.0, u.hp_ratio(), _lane_enemy if enemy else _lane_ally)
	# minion aggro icon (League shows it on minions that are attacking you)
	if enemy and u.attack_target == G.player:
		_icon(_m_aggro[si], sp)


## Summons (Tibbers: AnnieTibbers skin unitHealthBarStyle 5 = FHBObj).
func _draw_obj_bar(u, b: BarState, sp: Vector2, my_team: int, dt: float, hovered: bool) -> void:
	var ally: bool = u.team == my_team
	_icon(_o_border, sp)
	if hovered:
		_icon(_o_highlight, sp)
	var hr := _o_hp.at(sp)
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var hp: float = clampf(u.hp, 0.0, maxhp)
	var sh: float = u.total_shield()
	var total := maxf(maxhp, hp + sh)
	_track(b, hp, hp + sh, maxhp, _cfg_obj, dt)
	var fe := _o_fade if ally else _o_fade_enemy
	if b.fade_hp > hp + sh:
		_meter(fe, hr, (hp + sh) / total, b.fade_hp / total, fe.col)
	_meter(_o_hp, hr, 0.0, hp / total, _team_ally if ally else _team_enemy)
	if sh > 0.5:
		_meter(_o_shield, hr, hp / total, (hp + sh) / total, _o_shield.col)


# ------------------------------------------------------------------ structures
## Inhibitor = FHBStructure (style 3); turrets and nexus = FHBEpicStructure (style 8). Grey fill tinted with
## HudColorData mFriendlyColor / mEnemyColor; fade, 10% burst / flash / shake from the structure bar data.
func _draw_structure_bar(u, b: BarState, sp: Vector2, my_team: int, dt: float, hovered: bool) -> void:
	var si := 0 if u.kind == G.Kind.INHIBITOR else 1
	var ally: bool = u.team == my_team
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var hp: float = clampf(u.hp, 0.0, maxhp)
	var sh: float = u.total_shield()
	var total := maxf(maxhp, hp + sh)
	_track(b, hp, hp + sh, maxhp, _cfg_struct, dt)
	sp += _shake(b, _cfg_struct, u.get_instance_id())
	_icon(_s_border[si], sp)
	if hovered:
		_icon(_s_highlight[si], sp)
	var hr := _s_hp[si].at(sp)
	_chunks(b, hr, hp + sh, total, _s_fade[si] if ally else _s_fade_enemy[si], _s_burst[si], _s_flash[si], _cfg_struct)
	_meter(_s_hp[si], hr, 0.0, hp / total, _team_ally if ally else _team_enemy)
	if sh > 0.5:
		_meter(_s_shield[si], hr, hp / total, (hp + sh) / total, _s_shield[si].col)
	if u.kind == G.Kind.TURRET and u.aggro_line_target == G.player:
		_icon(_s_aggro[si], sp)


# ------------------------------------------------------------------ bar death (DeathAnimAlly / DeathAnimEnemy)
func _on_dead(u, my_team: int) -> void:
	var b: BarState = _bars.get(u.get_instance_id())
	if b == null or not b.alive:
		return
	b.alive = false
	b.inited = false
	if b.seen < _frame - 2:
		return      # the bar was not on screen (fogged / off-screen) when the unit died
	var el: El = null
	var tex: Texture2D = null
	var enemy: bool = u.team != my_team
	match u.kind:
		G.Kind.CHAMPION:
			el = _c_death[1 if enemy else 0]
			tex = _tex_death_champ
		G.Kind.TURRET, G.Kind.NEXUS:
			el = _s_death[2 + (1 if enemy else 0)]
			tex = _tex_death_struct
		G.Kind.INHIBITOR:
			el = _s_death[1 if enemy else 0]
			tex = _tex_death_struct
	if el == null or not el.ok or tex == null:
		return
	var d := DeathFx.new()
	d.world = u.global_position
	d.hbh = b.hbh
	d.full = b.full
	d.t0 = _time
	d.el = el
	d.tex = tex
	var key := "ChampFHB_DeathBlue" if u.kind == G.Kind.CHAMPION else "StructureFHB_DeathBlue"
	var an: Array = L.get(key, {}).get("anim", [40.0, 25.0, 5.0])
	if an.size() == 3 and an[0] != null:
		d.fps = float(an[0])
		d.frames = int(an[1])
		d.per_row = int(an[2])
	_deaths.append(d)


func _draw_deaths() -> void:
	var i := 0
	while i < _deaths.size():
		var d := _deaths[i]
		var fr := int((_time - d.t0) * d.fps)
		if fr >= d.frames:
			_deaths.remove_at(i)
			continue
		i += 1
		if _cam.is_position_behind(d.world):
			continue
		var sp := _anchor(d.world, d.hbh, d.full, 1.0).round()
		var fw := d.el.uv.size
		var src := Rect2(d.el.uv.position + Vector2((fr % d.per_row) * fw.x, (fr / d.per_row) * fw.y), fw)
		draw_texture_rect_region(d.tex, d.el.at(sp), src)


# ------------------------------------------------------------------ floating text API (called by Match)
func _visible_for_player(u) -> bool:
	return u != null and is_instance_valid(u) and (u.team == G.player.team or u.visible_to[G.player.team])


func _text_anchor(u) -> Vector3:
	return u.global_position + Vector3(0, u.height * u.stats.size * 0.75 + u.airborne_height, 0)


func damage_number(info: DamageInfo) -> void:
	if G.player == null or info.target == null:
		return
	var involve_player: bool = info.source == G.player or info.target == G.player
	if info.source != null and info.source.get("summoner") == G.player:
		involve_player = true
	var show_all: bool = G.settings.get("show_all_damage_numbers", false)
	if not involve_player and not (show_all and info.target.kind == G.Kind.CHAMPION):
		return
	if not _visible_for_player(info.target):
		return
	var amt := info.mitigated
	if amt < 1.0:
		return
	var base := "PhysicalDamage"
	var icon := "crit_physical"
	if info.type == G.DmgType.MAGIC:
		base = "MagicalDamage"
		icon = "crit_magic"
	elif info.type == G.DmgType.TRUE:
		base = "TrueDamage"
		icon = "crit_true"
	if info.target == G.player:
		base = "Enemy" + base       # damage taken: League's Enemy* types (smaller, 19 px)
	if info.is_crit:
		ft.spawn(base + "Critical", str(int(round(amt))), info.target, _text_anchor(info.target), icon)
	else:
		ft.spawn(base, str(int(round(amt))), info.target, _text_anchor(info.target))


func heal_number(u, amount: float) -> void:
	if G.player == null or not (u == G.player or (u.team == G.player.team and amount > 40.0)):
		return
	if amount < 1.0:
		return
	ft.spawn("Heal", "+" + str(int(round(amount))), u, _text_anchor(u))


func gold_number(u, amount: float) -> void:
	if u == null or not is_instance_valid(u):
		return
	ft.spawn("Gold", "+" + str(int(round(amount))), u, _text_anchor(u), "gold")


func float_text(u, text: String, color: Color) -> void:
	if u == null or not is_instance_valid(u):
		return
	var e := ft.spawn("Special", text, u, _text_anchor(u))
	if e != null:
		e.color = color


func level_up_fx(c) -> void:
	if c == G.player:
		# League's "Level" text rises slowly from just above the health bar
		ft.spawn("Level", "Level Up!", c, c.global_position + Vector3(0, c.height * c.stats.size + 0.9, 0))
	if match_ref == null:
		return
	# League's own level-up burst once the vfx extraction provides it (data/vfx/shared.json), else ours
	LolVfx.load_set("shared")
	for nm in LEVEL_UP_FX:
		if LolVfx.has(nm):
			LolVfx.attach(c, nm)
			return
	Vfx.rising(c, Color(1.0, 0.8, 0.3), 0.6, 40, 0.7)
	Vfx.ring(match_ref, c.global_position, Color(1.0, 0.8, 0.3), 1.6, 0.6, 0.08, 0.1)
