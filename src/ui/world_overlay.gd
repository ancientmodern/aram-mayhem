class_name WorldOverlay
extends Control
## Screen-space overlay drawn every frame: League floating health bars, floating combat text and the
## turret-aggro line. One Control draws everything (fixed pixel size, crisp, cheap).
##
## Health bars are rebuilt from League's own data: the LoLFloatingInfoBars UI scene (element rects + atlas UVs)
## and its 512x512 atlas, extracted by tools/lol/extract_world_ui.py into assets/ui/world/. Element positions
## are authored at the 1600x1200 UI reference and placed relative to each bar's AnchorBase element.
##
## Perf: every layout element is resolved once into an `El` (anchor-relative screen rect + atlas UV), per-unit
## state lives in a pooled `BarState` (drain/flash + shaped name/level TextLines), HP ticks are one multiline
## per champion, and nothing allocates strings per frame.

const REF_SCALE := 1080.0 / 1200.0   ## our canvas is 1080 tall (canvas_items stretch); League's UI ref is 1200

# minion/structure bar textures are grey; League tints them by team. Tints = the champion bar colour divided
# by the grey bar's mean (both sampled from the atlas): red 177,67,57 / blue 64,164,227 over grey ~188.
const TINT_ENEMY := Color(0.94, 0.36, 0.30)
const TINT_ALLY := Color(0.34, 0.87, 1.0)
const TICK_COL := Color(0.0, 0.0, 0.0, 0.85)
const MICRO_COL := Color(0.0, 0.0, 0.0, 0.7)
const NAME_OUTLINE := Color(0, 0, 0, 0.85)
const LEVEL_UP_FX := ["LevelUp", "Global_LevelUp", "LevelUp_Global", "Jade_LevelUp", "Global_Levelup"]
const CC_MASK := Buff.CC.STUN | Buff.CC.AIRBORNE | Buff.CC.SUPPRESS | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP

## One League FHB element, pre-placed relative to its bar's anchor at our canvas scale.
class El:
	var rel := Rect2()
	var uv := Rect2()
	var ok := false

	func at(sp: Vector2) -> Rect2:
		return Rect2(sp + rel.position, rel.size)

## Per-unit bar state (damage drain, flash) and cached shaped text.
class BarState:
	var trail := 1.0
	var last := 1.0
	var hold := 0.0
	var flash := 0.0
	var name_str := ""
	var name_line: TextLine
	var seen := 0
	var tick_total := -1
	var ticks := PackedVector2Array()
	var bigticks := PackedVector2Array()

var match_ref = null
var rig: CameraRig = null
var ft: FloatingTextSystem
var atlas: Texture2D
var L := {}                          ## fhb_layout.json: element name -> {pos, size, uv, color}
var font_name: Font
var font_level: Font
var _bars := {}                      ## unit instance id -> BarState
var _turret_rings: TurretRangeRings
var _name_col := Color8(185, 185, 185)
var _self_name_col := Color.WHITE
var _frame := 0
var _ci: RID

# ---- pre-resolved elements
var _c_border: Array[El] = []        ## [Default, Invuln]
var _c_levelbox: Array[El] = []      ## state * 3 + (Self, Blue, Red)
var _c_highlight: El
var _c_hp: El
var _c_hp_tex: Array[El] = []        ## Green (self), Blue, Red
var _c_hp_white: El
var _c_flash: El
var _c_shield: Array[El] = []        ## generic, physical, magic
var _c_micro: El
var _c_tick: El
var _c_par: El
var _c_par_tex := {}                 ## resource kind -> El
var _c_level: El
var _c_name: El
var _c_status: El
var _c_status_bar: El
var _c_fade_ally := Color(1, 0, 0)
var _c_fade_enemy := Color(1, 0, 0)
var _m_border: Array[El] = []        ## Small, Med, Large
var _m_highlight: Array[El] = []
var _m_hp: Array[El] = []
var _m_aggro: Array[El] = []
var _s_border: El
var _s_ob_ally: El
var _s_ob_enemy: El
var _s_highlight: El
var _s_hp: El
var _s_shield: El
var _s_flash: El
var _s_aggro: El
var _s_fade_ally := Color(1, 1, 0)
var _s_fade_enemy := Color(1, 1, 0)
var _s_shield_col := Color(0.73, 0.73, 0.73)
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
	font_name = Assets.font("spiegel", "Bold")      # HealthBarTitle: Spiegel Bold 12, rgb 185
	font_level = Assets.font("beaufort", "Bold")    # HealthBarLevel: Beaufort Bold 11, white
	var tn: Dictionary = ft.types.get("HealthBarTitle", {})
	_name_col = FloatingTextSystem._col(tn.get("color"), _name_col)
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
	r.ok = r.rel.size.x > 0.0
	return r


func _col(n: String, fallback: Color) -> Color:
	var e: Dictionary = L.get(n, {})
	return FloatingTextSystem._col(e.get("color"), fallback)


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
	_c_hp_white = _el("ChampHP_BarTextureWhite", A)
	_c_flash = _el("ChampHP_BarFlash", A)
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
	_c_fade_ally = _col("ChampHP_BarFade", Color(1, 0, 0))
	_c_fade_enemy = _col("ChampHP_BarFadeEnemy", Color(1, 0, 0))
	for sz in ["Small", "Med", "Large"]:
		var ma := "Minion%sFHB_AnchorBase" % sz
		_m_border.append(_el("Minion%sFHB_Border_Default" % sz, ma))
		_m_highlight.append(_el("Minion%sFHB_Highlight_Default" % sz, ma))
		_m_hp.append(_el("Minion%sHP_BarTexture" % sz, ma))
		_m_aggro.append(_el("Minion%sFHB_Aggro" % sz, ma))
	const S := "StructureFHB_AnchorBase"
	_s_border = _el("StructureFHB_Border_Default", S)
	_s_ob_ally = _el("StructureFHB_OBAllied", S)
	_s_ob_enemy = _el("StructureFHB_OBEnemy", S)
	_s_highlight = _el("StructureFHB_Highlight_Default", S)
	_s_hp = _el("StructureHP_BarTexture", S)
	_s_shield = _el("StructureHP_AShieldBarTexture", S)
	_s_flash = _el("StructureHP_BarFlash", S)
	_s_aggro = _el("StructureFHB_Aggro", S)
	_s_fade_ally = _col("StructureHP_BarFade", Color(1, 1, 0))
	_s_fade_enemy = _col("StructureHP_BarFadeEnemy", Color(1, 1, 0))
	_s_shield_col = _col("StructureHP_AShieldBarTexture", Color(0.73, 0.73, 0.73))
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
	if _frame % 300 == 0:
		for id in _bars.keys():
			if not is_instance_id_valid(id) or _frame - _bars[id].seen > 600:
				_bars.erase(id)
	queue_redraw()


func _draw() -> void:
	var pt := Prof.t0()
	_draw_frame()
	Prof.add("draw.overlay", pt)


func _draw_frame() -> void:
	ft.prewarm(self)
	if match_ref == null or rig == null or G.player == null:
		return
	if _frame < 3:
		_prewarm_names()
	var cam := rig.cam
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
		if u.dead:
			continue
		if u.team != my_team and not u.visible_to[my_team]:
			continue
		if u.model != null and not u.model.visible:
			continue
		var top: Vector3 = u.global_position
		top.y += u.height * u.stats.size + u.airborne_height
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		if sp.x < -150.0 or sp.y < -100.0 or sp.x > w or sp.y > h:
			continue
		sp = sp.round()
		match u.kind:
			G.Kind.CHAMPION:
				_champ_sp.append(Vector3(sp.x, sp.y, _champ_q.size()))
				_champ_q.append(u)
			G.Kind.MINION, G.Kind.SUMMON:
				_draw_minion_bar(u, sp, my_team, dt, u == hov)
			G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
				if u.kind == G.Kind.TURRET and u.tier == Turret.Tier.FOUNTAIN:
					continue
				_draw_structure_bar(u, sp, my_team, dt, u == hov)
	# champion bars above minion/structure bars, back-to-front (lower on screen = nearer = drawn last)
	if not _champ_sp.is_empty():
		_champ_sp.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
		for e in _champ_sp:
			var cu: Unit = _champ_q[int(e.z)]
			_draw_champion_bar(cu, Vector2(e.x, e.y), my_team, dt, cu == hov)
		_champ_sp.clear()
		_champ_q.clear()
	ft.draw(self, cam)


# ------------------------------------------------------------------ atlas helpers
func _icon(e: El, sp: Vector2, mod := Color.WHITE) -> void:
	if e.ok:
		draw_texture_rect_region(atlas, Rect2(sp + e.rel.position, e.rel.size), e.uv, mod)


## Meter fill: the `f0..f1` fraction of the bar rect, cropping texture element `tex` the same way.
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


## Lingering damage chunk (League "BarFade"): holds briefly, then drains to the current value.
func _drain(u, frac: float, dt: float) -> BarState:
	var id: int = u.get_instance_id()
	var b: BarState = _bars.get(id)
	if b == null:
		b = BarState.new()
		b.trail = frac
		b.last = frac
		_bars[id] = b
	b.seen = _frame
	b.hold = maxf(b.hold - dt, 0.0)
	b.flash = maxf(b.flash - dt, 0.0)
	if frac < b.last - 0.0005:
		# a new hit while the chunk is still holding grows it (burst); otherwise a fresh chunk starts
		if b.hold <= 0.0:
			b.trail = maxf(b.trail, b.last)
			b.hold = 0.45
		b.flash = 0.12
	b.last = frac
	if b.trail < frac:
		b.trail = frac
	elif b.hold <= 0.0:
		b.trail = move_toward(b.trail, frac, dt * maxf(0.35, (b.trail - frac) * 3.0))
	return b


# ------------------------------------------------------------------ champion
func _draw_champion_bar(u, sp: Vector2, my_team: int, dt: float, hovered: bool) -> void:
	var is_self: bool = u == G.player
	var ally: bool = u.team == my_team
	var si := 0 if is_self else (1 if ally else 2)
	var st := 1 if u.is_invulnerable() else 0
	# level box under the border, then the border/frame
	_icon(_c_levelbox[st * 3 + si], sp)
	_icon(_c_border[st], sp)
	if hovered:
		_icon(_c_highlight, sp)
	# health meter: fill scales to max(maxHP, HP + shields), shields appended after HP (League)
	var hr := _c_hp.at(sp)
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
	var total := maxf(maxhp, u.hp + sh_p + sh_m + sh_gen)
	var f_hp: float = clampf(u.hp / total, 0.0, 1.0)
	var b := _drain(u, f_hp, dt)
	if b.trail > f_hp:
		_meter(_c_hp_white, hr, f_hp, b.trail, _c_fade_enemy if not ally else _c_fade_ally)
	_meter(_c_hp_tex[si], hr, 0.0, f_hp)
	if b.flash > 0.0:
		_meter(_c_flash, hr, 0.0, f_hp, Color(1, 1, 1, b.flash / 0.12 * 0.55))
	var f := f_hp
	if sh_gen > 0.5:
		_meter(_c_shield[0], hr, f, f + sh_gen / total)
		f += sh_gen / total
	if sh_p > 0.5:
		_meter(_c_shield[1], hr, f, f + sh_p / total)
		f += sh_p / total
	if sh_m > 0.5:
		_meter(_c_shield[2], hr, f, f + sh_m / total)
	# HP ticks: micro tick every 100 HP (top of bar), full tick every 1000 HP. The anchor-relative tick lines are
	# rebuilt only when the bar's total changes; per frame it is two multilines under a translate.
	var tot_key := int(total)
	if tot_key != b.tick_total:
		b.tick_total = tot_key
		_build_ticks(b, total)
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
	# level (Beaufort Bold, white), centred in the level box
	var lv: int = clampi(u.level, 0, 30)
	var tl: TextLine = _level_lines[lv]
	var lr := _c_level.at(sp)
	var lsz := tl.get_size()
	tl.draw(_ci, (lr.get_center() - lsz * 0.5).round(), Color.WHITE)
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


func _build_ticks(b: BarState, total: float) -> void:
	b.ticks = PackedVector2Array()
	b.bigticks = PackedVector2Array()
	var n := int(total / 100.0)
	if n <= 0 or n > 200:
		return
	var hr := _c_hp.rel
	var my := _c_micro.rel.position.y
	var mh := _c_micro.rel.size.y
	var by := _c_tick.rel.position.y
	var bh := _c_tick.rel.size.y
	var step := hr.size.x * 100.0 / total
	for i in range(1, n + 1):
		var x := roundf(hr.position.x + step * i)
		if x >= hr.end.x - 1.0:
			break
		if i % 10 == 0:
			b.bigticks.append(Vector2(x, by))
			b.bigticks.append(Vector2(x, by + bh))
		else:
			b.ticks.append(Vector2(x + 0.5, my))
			b.ticks.append(Vector2(x + 0.5, my + mh))


## Shape every champion name (and rasterise its glyphs off-canvas) before the first fight.
func _prewarm_names() -> void:
	for c in match_ref.champions:
		var id: int = c.get_instance_id()
		if _bars.has(id):
			continue
		var b := BarState.new()
		b.name_str = c.display_name
		b.name_line = TextLine.new()
		b.name_line.add_string(b.name_str, font_name, _name_fs)
		b.trail = c.hp_ratio()
		b.last = b.trail
		_bars[id] = b
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


# ------------------------------------------------------------------ minions / summons
func _draw_minion_bar(u, sp: Vector2, my_team: int, dt: float, hovered: bool) -> void:
	var si := 0
	if u.kind == G.Kind.MINION:
		if u.minion_type == Minion.Type.SIEGE:
			si = 1
		elif u.minion_type == Minion.Type.SUPER:
			si = 2
	var enemy: bool = u.team != my_team
	_icon(_m_border[si], sp)
	if hovered:
		_icon(_m_highlight[si], sp)
	var tex: El = _m_hp[si]
	var hr := tex.at(sp)
	var f: float = u.hp_ratio()
	var b := _drain(u, f, dt)
	if b.trail > f:
		_meter(tex, hr, f, b.trail, Color(1.0, 0.9, 0.6, 0.85))
	_meter(tex, hr, 0.0, f, TINT_ENEMY if enemy else TINT_ALLY)
	# minion aggro icon (League shows it on minions that are attacking you)
	if enemy and u.kind == G.Kind.MINION and u.attack_target == G.player:
		_icon(_m_aggro[si], sp)


# ------------------------------------------------------------------ structures
func _draw_structure_bar(u, sp: Vector2, my_team: int, dt: float, hovered: bool) -> void:
	var ally: bool = u.team == my_team
	_icon(_s_border, sp)
	_icon(_s_ob_ally if ally else _s_ob_enemy, sp)
	if hovered:
		_icon(_s_highlight, sp)
	var hr := _s_hp.at(sp)
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var sh: float = u.total_shield()
	var total := maxf(maxhp, u.hp + sh)
	var f: float = clampf(u.hp / total, 0.0, 1.0)
	var b := _drain(u, f, dt)
	if b.trail > f:
		_meter(_s_hp, hr, f, b.trail, _s_fade_ally if ally else _s_fade_enemy)
	_meter(_s_hp, hr, 0.0, f, TINT_ALLY if ally else TINT_ENEMY)
	if sh > 0.5:
		_meter(_s_shield, hr, f, f + sh / total, _s_shield_col)
	if b.flash > 0.0:
		_meter(_s_flash, hr, 0.0, f, Color(1, 1, 1, b.flash / 0.12 * 0.5))
	if u.is_invulnerable():
		draw_rect(hr, Color(0.55, 0.55, 0.62, 0.45))
	if u.kind == G.Kind.TURRET and u.aggro_line_target == G.player:
		_icon(_s_aggro, sp)


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
