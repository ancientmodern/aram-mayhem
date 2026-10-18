class_name WorldOverlay
extends Control
## Screen-space overlay drawn every frame: health bars, floating combat text,
## turret aggro lines. One Control draws everything for performance.

var match_ref = null
var rig: CameraRig = null
var texts: Array = []        ## floating texts
var font_num: Font
var font_name: Font
const MAX_TEXTS := 160

const C_FRAME := Color(0.03, 0.04, 0.06, 0.92)
const C_BACK := Color(0.12, 0.12, 0.14, 0.95)
const C_SELF := Color(0.36, 0.78, 0.22)
const C_ALLY := Color(0.22, 0.58, 0.95)
const C_ENEMY := Color(0.86, 0.2, 0.18)
const C_MANA := Color(0.2, 0.5, 0.95)
const C_SHIELD := Color(0.92, 0.92, 0.92)
const C_DMG_TRAIL := Color(0.95, 0.85, 0.5, 0.9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font_num = Assets.font("beaufort", "Bold")
	font_name = Assets.font("spiegel", "SemiBold")


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	for t in texts:
		t.age += dt
		t.pos += t.vel * dt
		t.vel.y -= t.get("grav", 0.0) * dt
	texts = texts.filter(func(t): return t.age < t.life)
	queue_redraw()


func _draw() -> void:
	if match_ref == null or rig == null or G.player == null:
		return
	var cam := rig.cam
	var my_team: int = G.player.team
	# turret aggro lines
	for s in match_ref.structures:
		if s.kind == G.Kind.TURRET and not s.dead and s.aggro_line_target != null and is_instance_valid(s.aggro_line_target):
			var tgt: Unit = s.aggro_line_target
			if tgt == G.player:
				var a := cam.unproject_position(s.global_position + Vector3(0, s.height * 0.9, 0))
				var b := cam.unproject_position(tgt.global_position + Vector3(0, 1.0, 0))
				draw_line(a, b, Color(1, 0.15, 0.1, 0.85), 3.0, true)
	for u in match_ref.units:
		if u.dead:
			continue
		if u.team != my_team and not u.visible_to[my_team]:
			continue
		if u.model != null and not u.model.visible:
			continue
		var top: Vector3 = u.global_position + Vector3(0, u.height * u.stats.size + u.airborne_height + 0.25, 0)
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		if sp.x < -100 or sp.y < -100 or sp.x > size.x + 100 or sp.y > size.y + 100:
			continue
		match u.kind:
			G.Kind.CHAMPION:
				_draw_champion_bar(u, sp, my_team)
			G.Kind.MINION, G.Kind.SUMMON:
				_draw_small_bar(u, sp, my_team)
			G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
				if u.get("tier") != null and u.tier == Turret.Tier.FOUNTAIN:
					continue
				_draw_structure_bar(u, sp, my_team)
	for t in texts:
		_draw_text(t, cam)


func _team_color(u, my_team: int) -> Color:
	if u == G.player:
		return C_SELF
	return C_ALLY if u.team == my_team else C_ENEMY


func _draw_hp_fill(r: Rect2, u, col: Color, tick_hp: float) -> void:
	var maxhp: float = maxf(u.stats.max_hp, 1.0)
	var sh: float = u.total_shield()
	var total := maxf(maxhp, u.hp + sh)
	var w_hp := r.size.x * clampf(u.hp / total, 0.0, 1.0)
	var w_sh := r.size.x * clampf(sh / total, 0.0, 1.0)
	draw_rect(r, C_BACK)
	# lingering damage trail
	var trail: float = u.get_meta("_hp_trail", u.hp)
	if trail > u.hp:
		trail = lerpf(trail, u.hp, 0.06)
	else:
		trail = u.hp
	u.set_meta("_hp_trail", trail)
	var w_trail := r.size.x * clampf(trail / total, 0.0, 1.0)
	if w_trail > w_hp:
		draw_rect(Rect2(r.position + Vector2(w_hp, 0), Vector2(w_trail - w_hp, r.size.y)), C_DMG_TRAIL)
	draw_rect(Rect2(r.position, Vector2(w_hp, r.size.y)), col)
	draw_rect(Rect2(r.position, Vector2(w_hp, r.size.y * 0.35)), Color(1, 1, 1, 0.18))
	if w_sh > 0.5:
		draw_rect(Rect2(r.position + Vector2(w_hp, 0), Vector2(w_sh, r.size.y)), C_SHIELD)
	# ticks every tick_hp (thicker every 10)
	if tick_hp > 0.0:
		var n := int(total / tick_hp)
		if n <= 120:
			for i in range(1, n + 1):
				var x := r.position.x + r.size.x * (i * tick_hp) / total
				if x >= r.end.x - 1:
					break
				var big := i % 10 == 0
				var hh := r.size.y if big else r.size.y * 0.55
				draw_line(Vector2(x, r.position.y), Vector2(x, r.position.y + hh), Color(0, 0, 0, 0.85 if big else 0.6), 1.5 if big else 1.0)


func _draw_champion_bar(u, sp: Vector2, my_team: int) -> void:
	var w := 112.0
	var h := 12.0
	var lvl_w := 20.0
	var origin := sp + Vector2(-w * 0.5 + lvl_w * 0.5, -10)
	var frame := Rect2(origin - Vector2(lvl_w + 2, 2), Vector2(w + lvl_w + 4, h + (7 if u.stats.max_mana > 0 else 4) + 2))
	draw_rect(frame, C_FRAME)
	# level badge
	var lr := Rect2(origin - Vector2(lvl_w, 0), Vector2(lvl_w - 2, h + 5))
	draw_rect(lr, Color(0.08, 0.08, 0.1))
	draw_rect(lr, Color(0.75, 0.62, 0.3, 0.9), false, 1.0)
	var lt := str(u.level)
	var ts := font_num.get_string_size(lt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	draw_string(font_num, lr.position + Vector2((lr.size.x - ts.x) * 0.5, lr.size.y * 0.5 + 5), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.6))
	var col := _team_color(u, my_team)
	_draw_hp_fill(Rect2(origin, Vector2(w, h)), u, col, 100.0)
	if u.stats.max_mana > 0.0:
		var mr := Rect2(origin + Vector2(0, h + 1), Vector2(w, 4))
		draw_rect(mr, C_BACK)
		draw_rect(Rect2(mr.position, Vector2(w * clampf(u.mana / u.stats.max_mana, 0.0, 1.0), 4)), C_MANA)
	# name
	if u != G.player:
		var nm: String = u.display_name
		var ns := font_name.get_string_size(nm, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
		var np := Vector2(sp.x - ns.x * 0.5, origin.y - 6)
		draw_string_outline(font_name, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 3, Color(0, 0, 0, 0.8))
		draw_string(font_name, np, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.95, 0.95))
	# channel / cast bar
	var ch: Dictionary = u.channel
	if not ch.is_empty():
		var k := 1.0 - clampf(ch.t / maxf(ch.total, 0.01), 0.0, 1.0)
		var cr := Rect2(origin + Vector2(0, h + 10), Vector2(w, 5))
		draw_rect(cr, C_FRAME)
		draw_rect(Rect2(cr.position, Vector2(w * k, 5)), Color(1.0, 0.8, 0.3))
	# respawn/CC hint: show "!" for CC
	if (u.cc & (Buff.CC.STUN | Buff.CC.AIRBORNE | Buff.CC.SUPPRESS | Buff.CC.CHARM | Buff.CC.FEAR | Buff.CC.TAUNT | Buff.CC.SLEEP)) != 0:
		var cc_text := _cc_name(u.cc)
		var cs := font_num.get_string_size(cc_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
		var cp := Vector2(sp.x - cs.x * 0.5, origin.y + h + 22)
		draw_string_outline(font_num, cp, cc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.9))
		draw_string(font_num, cp, cc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.85, 0.3))


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


func _draw_small_bar(u, sp: Vector2, my_team: int) -> void:
	var w := 46.0 if u.kind == G.Kind.MINION and u.get("minion_type") != null and u.minion_type < 2 else 60.0
	var h := 5.0
	var r := Rect2(sp + Vector2(-w * 0.5, 0), Vector2(w, h))
	draw_rect(r.grow(1.0), C_FRAME)
	var col := C_ALLY if u.team == my_team else C_ENEMY
	draw_rect(r, C_BACK)
	draw_rect(Rect2(r.position, Vector2(w * u.hp_ratio(), h)), col)
	draw_rect(Rect2(r.position, Vector2(w * u.hp_ratio(), h * 0.4)), Color(1, 1, 1, 0.15))


func _draw_structure_bar(u, sp: Vector2, my_team: int) -> void:
	var w := 150.0
	var h := 11.0
	var r := Rect2(sp + Vector2(-w * 0.5, 0), Vector2(w, h))
	draw_rect(r.grow(2.0), C_FRAME)
	var col := C_ALLY if u.team == my_team else C_ENEMY
	_draw_hp_fill(r, u, col, 1000.0)
	if u.is_invulnerable():
		draw_rect(r, Color(0.6, 0.6, 0.7, 0.35))
		var lock := "INVULNERABLE"
		var ls := font_name.get_string_size(lock, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
		draw_string(font_name, Vector2(sp.x - ls.x * 0.5, r.position.y - 3), lock, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.9, 0.8))


# ------------------------------------------------------------------ floating text
func _push(t: Dictionary) -> void:
	texts.append(t)
	if texts.size() > MAX_TEXTS:
		texts.pop_front()


func _visible_for_player(u) -> bool:
	return u != null and is_instance_valid(u) and (u.team == G.player.team or u.visible_to[G.player.team])


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
	var col := G.COLOR_PHYS
	if info.type == G.DmgType.MAGIC:
		col = G.COLOR_MAGIC
	elif info.type == G.DmgType.TRUE:
		col = G.COLOR_TRUE
	var sz := 18.0
	if info.target == G.player:
		col = Color(1.0, 0.25, 0.2)
		sz = 16.0
	var txt := str(int(round(amt)))
	if info.is_crit:
		sz = 26.0
		txt += "!"
	elif info.is_attack:
		sz = 18.0
	elif info.is_dot or info.is_proc:
		sz = 14.0
	if info.target.kind == G.Kind.MINION:
		sz *= 0.82
	var spread := Vector3(G.rng.randf_range(-0.5, 0.5), 0, G.rng.randf_range(-0.3, 0.3))
	_push({"text": txt, "color": col, "pos": info.target.global_position + Vector3(0, info.target.height * 0.9, 0) + spread,
		"vel": Vector3(spread.x * 1.2, 3.0 if not info.is_crit else 3.6, 0), "grav": 4.5, "age": 0.0,
		"life": 0.95 if not info.is_crit else 1.2, "size": sz, "pop": info.is_crit})


func heal_number(u, amount: float) -> void:
	if G.player == null or not (u == G.player or (u.team == G.player.team and amount > 40.0)):
		return
	_push({"text": "+" + str(int(round(amount))), "color": G.COLOR_HEAL, "pos": u.global_position + Vector3(0.3, u.height * 0.8, 0),
		"vel": Vector3(0, 1.4, 0), "grav": 0.0, "age": 0.0, "life": 1.1, "size": 16.0, "pop": false})


func gold_number(u, amount: float) -> void:
	_push({"text": "+" + str(int(round(amount))) + "g", "color": G.COLOR_GOLD, "pos": u.global_position + Vector3(0, u.height * 0.6, 0),
		"vel": Vector3(0, 1.6, 0), "grav": 0.0, "age": 0.0, "life": 1.2, "size": 17.0, "pop": false})


func float_text(u, text: String, color: Color) -> void:
	_push({"text": text, "color": color, "pos": u.global_position + Vector3(0, u.height * 1.0, 0),
		"vel": Vector3(0, 1.2, 0), "grav": 0.0, "age": 0.0, "life": 1.2, "size": 16.0, "pop": false})


func level_up_fx(c) -> void:
	if c == G.player:
		_push({"text": "LEVEL UP!", "color": Color(1.0, 0.85, 0.35), "pos": c.global_position + Vector3(0, c.height + 0.4, 0),
			"vel": Vector3(0, 1.0, 0), "grav": 0.0, "age": 0.0, "life": 1.6, "size": 24.0, "pop": true})
	if match_ref != null:
		Vfx.rising(c, Color(1.0, 0.8, 0.3), 0.6, 40, 0.7)
		Vfx.ring(match_ref, c.global_position, Color(1.0, 0.8, 0.3), 1.6, 0.6, 0.08, 0.1)


func _draw_text(t: Dictionary, cam: Camera3D) -> void:
	if cam.is_position_behind(t.pos):
		return
	var p := cam.unproject_position(t.pos)
	var k: float = t.age / t.life
	var a := 1.0 - smoothstep(0.65, 1.0, k)
	var s: float = t.size
	if t.pop:
		s *= 1.0 + 0.6 * maxf(0.0, 1.0 - t.age * 6.0)
	var fs := int(s)
	var ts := font_num.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := p - Vector2(ts.x * 0.5, 0)
	var c: Color = t.color
	draw_string_outline(font_num, pos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.85 * a))
	draw_string(font_num, pos, t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c.r, c.g, c.b, a))
