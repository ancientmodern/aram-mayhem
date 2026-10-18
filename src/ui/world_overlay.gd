class_name WorldOverlay
extends Control
## Screen-space overlay drawn every frame: League floating health bars, floating combat text and the
## turret-aggro line. One Control draws everything (fixed pixel size, crisp, cheap).
##
## Health bars are rebuilt from League's own data: the LoLFloatingInfoBars UI scene (element rects + atlas UVs)
## and its 512x512 atlas, extracted by tools/lol/extract_world_ui.py into assets/ui/world/. Element positions
## are authored at the 1600x1200 UI reference and placed relative to each bar's AnchorBase element.

const REF_SCALE := 1080.0 / 1200.0   ## our canvas is 1080 tall (canvas_items stretch); League's UI ref is 1200
const MAX_TEXTS := 160

var match_ref = null
var rig: CameraRig = null
var ft: FloatingTextSystem
var atlas: Texture2D
var L := {}                          ## fhb_layout.json: element name -> {pos, size, uv, color}
var font_name: Font
var font_level: Font
var _bars := {}                      ## unit instance id -> drain/flash state
var _turret_rings: TurretRangeRings
var _name_col := Color8(185, 185, 185)
var _self_name_col := Color.WHITE

# minion/structure bar textures are grey; League tints them by team. Tints = the champion bar colour divided
# by the grey bar's mean (both sampled from the atlas): red 177,67,57 / blue 64,164,227 over grey ~188.
const TINT_ENEMY := Color(0.94, 0.36, 0.30)
const TINT_ALLY := Color(0.34, 0.87, 1.0)
const TICK_COL := Color(0.0, 0.0, 0.0, 0.85)


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
	if match_ref != null:
		_turret_rings = TurretRangeRings.new()
		_turret_rings.name = "TurretRangeRings"
		_turret_rings.match_ref = match_ref
		match_ref.add_child.call_deferred(_turret_rings)


func _process(delta: float) -> void:
	var ppt := Prof.t0()
	_process_frame(delta)
	Prof.add("proc.overlay", ppt)


func _process_frame(delta: float) -> void:
	var dt := minf(delta, 0.05)
	ft.update(dt)
	var prune := Engine.get_process_frames() % 300 == 0
	for id in _bars.keys():
		if prune and not is_instance_id_valid(id):
			_bars.erase(id)
			continue
		var b: Dictionary = _bars[id]
		b.hold = maxf(b.hold - dt, 0.0)
		b.flash = maxf(b.flash - dt, 0.0)
	queue_redraw()


func _draw() -> void:
	var pt := Prof.t0()
	_draw_frame()
	Prof.add("draw.overlay", pt)


func _draw_frame() -> void:
	if match_ref == null or rig == null or G.player == null:
		return
	var cam := rig.cam
	var my_team: int = G.player.team
	# turret aggro line (League: thin red targeting line from the turret to the champion it attacks)
	for s in match_ref.structures:
		if s.kind == G.Kind.TURRET and not s.dead and s.aggro_line_target != null and is_instance_valid(s.aggro_line_target):
			var tgt: Unit = s.aggro_line_target
			if tgt == G.player:
				var a := cam.unproject_position(s.global_position + Vector3(0, s.height * 0.9, 0))
				var b := cam.unproject_position(tgt.global_position + Vector3(0, 1.0, 0))
				var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.012)
				draw_line(a, b, Color(1, 0.1, 0.05, 0.25 * pulse), 6.0, true)
				draw_line(a, b, Color(1, 0.25, 0.15, 0.9 * pulse), 2.0, true)
	var dt := minf(get_process_delta_time(), 0.05)
	for u in match_ref.units:
		if u.dead:
			continue
		if u.team != my_team and not u.visible_to[my_team]:
			continue
		if u.model != null and not u.model.visible:
			continue
		var top: Vector3 = u.global_position + Vector3(0, u.height * u.stats.size + u.airborne_height, 0)
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		if sp.x < -150 or sp.y < -100 or sp.x > size.x + 150 or sp.y > size.y + 150:
			continue
		sp = sp.round()
		match u.kind:
			G.Kind.CHAMPION:
				_draw_champion_bar(u, sp, my_team, dt)
			G.Kind.MINION, G.Kind.SUMMON:
				_draw_minion_bar(u, sp, my_team, dt)
			G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
				if u.get("tier") != null and u.tier == Turret.Tier.FOUNTAIN:
					continue
				_draw_structure_bar(u, sp, my_team, dt)
	ft.draw(self, cam)


# ------------------------------------------------------------------ atlas helpers
## Screen rect of layout element `n`, placed relative to anchor element `anchor` at screen point `sp`.
func _r(n: String, anchor: String, sp: Vector2) -> Rect2:
	var e: Dictionary = L.get(n, {})
	var a: Dictionary = L.get(anchor, {})
	if e.is_empty() or a.is_empty():
		return Rect2()
	var p := Vector2(e.pos[0] - a.pos[0], e.pos[1] - a.pos[1]) * REF_SCALE
	return Rect2((sp + p).round(), (Vector2(e.size[0], e.size[1]) * REF_SCALE).round())


func _uv(n: String) -> Rect2:
	var e: Dictionary = L.get(n, {})
	if not e.has("uv"):
		return Rect2()
	var u: Array = e.uv
	return Rect2(u[0], u[1], u[2] - u[0], u[3] - u[1])


func _icon(n: String, anchor: String, sp: Vector2, mod := Color.WHITE) -> Rect2:
	var r := _r(n, anchor, sp)
	if r.size.x > 0.0 and atlas != null:
		draw_texture_rect_region(atlas, r, _uv(n), mod)
	return r


## Meter fill: the left `f0..f1` fraction of the bar rect, cropping the texture the same way.
func _meter(tex_el: String, r: Rect2, f0: float, f1: float, mod := Color.WHITE) -> void:
	f0 = clampf(f0, 0.0, 1.0)
	f1 = clampf(f1, 0.0, 1.0)
	if f1 - f0 <= 0.0005 or atlas == null:
		return
	var uv := _uv(tex_el)
	var x0 := roundf(r.position.x + r.size.x * f0)
	var x1 := roundf(r.position.x + r.size.x * f1)
	if x1 - x0 < 1.0:
		x1 = x0 + 1.0
	var dst := Rect2(x0, r.position.y, x1 - x0, r.size.y)
	var src := Rect2(uv.position.x + uv.size.x * f0, uv.position.y, uv.size.x * (f1 - f0), uv.size.y)
	draw_texture_rect_region(atlas, dst, src, mod)


func _col(n: String, fallback: Color) -> Color:
	var e: Dictionary = L.get(n, {})
	return FloatingTextSystem._col(e.get("color"), fallback)


## Lingering damage chunk (League "BarFade"): holds briefly, then drains to the current value.
func _drain(u, frac: float, dt: float) -> Dictionary:
	var id: int = u.get_instance_id()
	var b: Dictionary = _bars.get(id, {})
	if b.is_empty():
		b = {"trail": frac, "last": frac, "hold": 0.0, "flash": 0.0}
		_bars[id] = b
	if frac < b.last - 0.0005:
		if b.trail < b.last:
			b.trail = maxf(b.trail, b.last)
		else:
			b.trail = b.last
		b.hold = 0.45
		b.flash = 0.12
	b.last = frac
	if b.trail < frac:
		b.trail = frac
	elif b.hold <= 0.0:
		b.trail = move_toward(b.trail, frac, dt * maxf(0.35, (b.trail - frac) * 3.0))
	return b


# ------------------------------------------------------------------ champion
func _draw_champion_bar(u, sp: Vector2, my_team: int, dt: float) -> void:
	const A := "ChampFHB_AnchorBase"
	var is_self: bool = u == G.player
	var ally: bool = u.team == my_team
	var sfx := "Self" if is_self else ("Blue" if ally else "Red")
	var hovered: bool = match_ref.player_controller != null and match_ref.player_controller.hovered == u
	var state := "Invuln" if u.is_invulnerable() else "Default"
	# level box under the border, then the border/frame
	_icon("ChampFHB_LevelBox_%s_%s" % [state, sfx], A, sp)
	_icon("ChampFHB_Border_%s" % state, A, sp)
	if hovered:
		_icon("ChampFHB_Highlight_Default", A, sp)
	# health meter: fill scales to max(maxHP, HP + shields), shields appended after HP (League)
	var hr := _r("ChampHP_BarTextureGreen", A, sp)
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var sh_all: float = u.total_shield(-2)
	var sh_p: float = 0.0
	var sh_m: float = 0.0
	for s in u.shields:
		if s.type == G.DmgType.PHYSICAL:
			sh_p += s.amount
		elif s.type == G.DmgType.MAGIC:
			sh_m += s.amount
	var total := maxf(maxhp, u.hp + sh_all)
	var f_hp: float = clampf(u.hp / total, 0.0, 1.0)
	var b := _drain(u, f_hp, dt)
	var bar_tex := "ChampHP_BarTexture" + ("Green" if is_self else ("Blue" if ally else "Red"))
	if b.trail > f_hp:
		var fade_col := _col("ChampHP_BarFadeEnemy" if not ally else "ChampHP_BarFade", Color(1, 0, 0))
		_meter("ChampHP_BarTextureWhite", hr, f_hp, b.trail, fade_col)
	_meter(bar_tex, hr, 0.0, f_hp)
	if b.flash > 0.0:
		_meter("ChampHP_BarFlash", hr, 0.0, f_hp, Color(1, 1, 1, b.flash / 0.12 * 0.55))
	var f := f_hp
	var sh_gen := sh_all - sh_p - sh_m
	if sh_gen > 0.5:
		_meter("ChampHP_AShieldBarTexture", hr, f, f + sh_gen / total)
		f += sh_gen / total
	if sh_p > 0.5:
		_meter("ChampHP_PShieldBarTexture", hr, f, f + sh_p / total)
		f += sh_p / total
	if sh_m > 0.5:
		_meter("ChampHP_MShieldBarTexture", hr, f, f + sh_m / total)
	# HP ticks: micro tick every 100 HP (top of bar), full tick every 1000 HP
	var n := int(total / 100.0)
	if n <= 200:
		var micro := _r("ChampHP_MicroTick", A, sp)
		var big := _r("ChampHP_Tick", A, sp)
		for i in range(1, n + 1):
			var x := roundf(hr.position.x + hr.size.x * (i * 100.0) / total)
			if x >= hr.end.x - 1.0:
				break
			if i % 10 == 0:
				draw_rect(Rect2(x - 1.0, big.position.y, maxf(big.size.x, 2.0), big.size.y), TICK_COL)
			else:
				draw_rect(Rect2(x, micro.position.y, 1.0, micro.size.y), Color(0, 0, 0, 0.7))
	# resource (PAR) bar
	if u.stats.max_mana > 0.0:
		var pr := _r("ChampPAR_BarTextureBlue", A, sp)
		var rn: String = str(u.get("resource_name")) if u.get("resource_name") != null else "Mana"
		var ptex := "ChampPAR_BarTextureBlue"
		match rn.to_lower():
			"energy":
				ptex = "ChampPAR_BarTextureYellow"
			"fury", "rage", "bloodthirst", "heat":
				ptex = "ChampPAR_BarTextureRed"
			"flow", "courage", "ferocity", "grit", "frenzy":
				ptex = "ChampPAR_BarTextureWhite"
		_meter(ptex, pr, 0.0, u.mana / u.stats.max_mana)
	# level
	var lr := _r("ChampFHB_Text_Level", A, sp)
	var lt := str(u.level)
	var lfs := maxi(int(round(11.0 * REF_SCALE * 1.15)), 9)
	var ls := font_level.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs)
	draw_string(font_level, Vector2(roundf(lr.get_center().x - ls.x * 0.5), roundf(lr.get_center().y + ls.y * 0.32)),
			lt, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color.WHITE)
	# name above the frame (League: Spiegel Bold 12, grey 185; own name white)
	var nr := _r("ChampFHB_Text_Name", A, sp)
	var nm: String = u.display_name
	var nfs := maxi(int(round(12.0 * REF_SCALE * 1.1)), 9)
	var ns := font_name.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs)
	var npos := Vector2(roundf(nr.get_center().x - ns.x * 0.5), roundf(nr.end.y - 1.0))
	draw_string_outline(font_name, npos, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, 3, Color(0, 0, 0, 0.85))
	draw_string(font_name, npos, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, nfs, _self_name_col if is_self else _name_col)
	# channel / cast bar (League draws it under the frame)
	var ch: Dictionary = u.channel
	if not ch.is_empty():
		var k := 1.0 - clampf(ch.t / maxf(ch.total, 0.01), 0.0, 1.0)
		var cr := Rect2(hr.position + Vector2(0, roundf(30 * REF_SCALE)), Vector2(hr.size.x, roundf(5 * REF_SCALE)))
		draw_rect(cr.grow(1.0), Color(0.02, 0.03, 0.04, 0.9))
		_meter("ChampPAR_BarTextureYellow", cr, 0.0, k)
	# CC status text above the name slot (HealthBarStatusTitle: Beaufort Bold 11 white)
	if (u.cc & (Buff.CC.STUN | Buff.CC.AIRBORNE | Buff.CC.SUPPRESS | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP)) != 0:
		var cc_text := _cc_name(u.cc)
		var sfs := maxi(int(round(11.0 * REF_SCALE * 1.15)), 9)
		var cs := font_level.get_string_size(cc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs)
		var cp := Vector2(roundf(nr.get_center().x - cs.x * 0.5), roundf(nr.position.y - 3.0))
		draw_string_outline(font_level, cp, cc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, 3, Color(0, 0, 0, 0.9))
		draw_string(font_level, cp, cc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sfs, Color.WHITE)


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
func _draw_minion_bar(u, sp: Vector2, my_team: int, dt: float) -> void:
	var sz := "Small"
	if u.kind == G.Kind.MINION and u.get("minion_type") != null:
		if u.minion_type == Minion.Type.SIEGE:
			sz = "Med"
		elif u.minion_type == Minion.Type.SUPER:
			sz = "Large"
	var A := "Minion%sFHB_AnchorBase" % sz
	var tint := TINT_ALLY if u.team == my_team else TINT_ENEMY
	_icon("Minion%sFHB_Border_Default" % sz, A, sp)
	if match_ref.player_controller != null and match_ref.player_controller.hovered == u:
		_icon("Minion%sFHB_Highlight_Default" % sz, A, sp)
	var hr := _r("Minion%sHP_BarTexture" % sz, A, sp)
	var f: float = u.hp_ratio()
	var b := _drain(u, f, dt)
	if b.trail > f:
		_meter("Minion%sHP_BarTexture" % sz, hr, f, b.trail, Color(1.0, 0.9, 0.6, 0.85))
	_meter("Minion%sHP_BarTexture" % sz, hr, 0.0, f, tint)
	# minion aggro icon (League shows it on minions that are attacking you)
	if u.get("attack_target") == G.player and u.team != my_team:
		_icon("Minion%sFHB_Aggro" % sz, A, sp)


# ------------------------------------------------------------------ structures
func _draw_structure_bar(u, sp: Vector2, my_team: int, dt: float) -> void:
	const A := "StructureFHB_AnchorBase"
	var ally: bool = u.team == my_team
	var tint := TINT_ALLY if ally else TINT_ENEMY
	_icon("StructureFHB_Border_Default", A, sp)
	_icon("StructureFHB_OBAllied" if ally else "StructureFHB_OBEnemy", A, sp)
	if match_ref.player_controller != null and match_ref.player_controller.hovered == u:
		_icon("StructureFHB_Highlight_Default", A, sp)
	var hr := _r("StructureHP_BarTexture", A, sp)
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var sh: float = u.total_shield()
	var total := maxf(maxhp, u.hp + sh)
	var f: float = clampf(u.hp / total, 0.0, 1.0)
	var b := _drain(u, f, dt)
	if b.trail > f:
		_meter("StructureHP_BarTexture", hr, f, b.trail, _col("StructureHP_BarFadeEnemy" if not ally else "StructureHP_BarFade", Color(1, 1, 0)))
	_meter("StructureHP_BarTexture", hr, 0.0, f, tint)
	if sh > 0.5:
		_meter("StructureHP_AShieldBarTexture", hr, f, f + sh / total, _col("StructureHP_AShieldBarTexture", Color(0.73, 0.73, 0.73)))
	if b.flash > 0.0:
		_meter("StructureHP_BarFlash", hr, 0.0, f, Color(1, 1, 1, b.flash / 0.12 * 0.5))
	if u.is_invulnerable():
		draw_rect(hr, Color(0.55, 0.55, 0.62, 0.45))
	if u.get("aggro_line_target") == G.player:
		_icon("StructureFHB_Aggro", A, sp)


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
	if info.target == G.player and not info.is_crit:
		base = "Enemy" + base
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
	ft.spawn("Special", text, u, _text_anchor(u))
	ft.texts[-1].color = color


func level_up_fx(c) -> void:
	if c == G.player:
		# League's "Level" text rises slowly from just above the health bar
		ft.spawn("Level", "Level Up!", c, c.global_position + Vector3(0, c.height * c.stats.size + 0.9, 0))
	if match_ref != null:
		Vfx.rising(c, Color(1.0, 0.8, 0.3), 0.6, 40, 0.7)
		Vfx.ring(match_ref, c.global_position, Color(1.0, 0.8, 0.3), 1.6, 0.6, 0.08, 0.1)
