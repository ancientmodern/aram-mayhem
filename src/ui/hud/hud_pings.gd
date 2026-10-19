class_name HudPings
extends RefCounted
## League pings: Alt / G + left click = smart ping (generic, or "attack" on an enemy / "assist" on an ally),
## Alt / G + drag = ping wheel (LoLPingRadial/UIBase: radialwheel atlases, RadialPing_* font styles),
## Ctrl + Alt + click or V + click = danger ping. Works on the world and on the minimap.
## Pings show League's ping icons (assets/ux/minimap/pings) with an expanding tinted ring at the world spot and on
## the minimap, play League's ping sounds (Play_sfx_hud_base_Pings_*), and are throttled like League (6 per 5 s).

## wheel order N, NE, E, SE, S, SW, W, NW (PingWheel_1N .. 8NW)
const WHEEL := ["danger", "push", "omw", "allin", "assist", "needvision", "mia", "enemyvision"]
const WHEEL_KEYS := ["1N", "2NE", "3E", "4SE", "5S", "6SW", "7W", "8NW"]
const WHEEL_TEXT := ["1N_Danger_Text", "2NE_Push_Text", "3E_OMW_Text", "4SE_All_In_Text", "5S_Assistme_Text",
	"6SW_NeedVision_Text", "7W_MIA_Text", "8NW_EnemyVision_Text"]
const WHEEL_LABEL := ["Danger", "Push", "On My Way", "All In", "Assist Me", "Need Vision", "Enemy Missing", "Enemy Vision"]
const KINDS := {
	"ping": {"icon": "ping", "ring": "ring2_yellow", "col": Color(1.0, 0.85, 0.3), "sfx": "Play_sfx_hud_base_Pings_Base"},
	"target": {"icon": "target", "ring": "ring2_red", "col": Color(1.0, 0.3, 0.3), "sfx": "Play_sfx_hud_base_Pings_Attack"},
	"danger": {"icon": "get_back_small", "ring": "ring2_danger", "col": Color(1.0, 0.25, 0.3), "sfx": "Play_sfx_hud_base_Pings_Danger"},
	"push": {"icon": "push", "ring": "ring2_green", "col": Color(0.2, 0.9, 0.6), "sfx": "Play_sfx_hud_base_Pings_Attack"},
	"omw": {"icon": "on_my_way_new", "ring": "ring_tintable", "col": Color(0.25, 0.7, 1.0), "sfx": "Play_sfx_hud_base_Pings_OnMyWay"},
	"allin": {"icon": "all_in", "ring": "ring2_yellow", "col": Color(1.0, 0.75, 0.1), "sfx": "Play_sfx_hud_base_Pings_Attack"},
	"assist": {"icon": "assist", "ring": "ring2_green", "col": Color(0.2, 0.9, 0.6), "sfx": "Play_sfx_hud_base_Pings_ComeHere"},
	"needvision": {"icon": "need_ward", "ring": "ring2_green", "col": Color(0.2, 0.9, 0.6), "sfx": "Play_sfx_hud_base_Pings_Base"},
	"mia": {"icon": "mia_new", "ring": "ring2_yellow", "col": Color(1.0, 0.8, 0.2), "sfx": "Play_sfx_hud_base_Pings_MIA"},
	"enemyvision": {"icon": "area_is_warded_small_red_new", "ring": "ring2_red", "col": Color(1.0, 0.3, 0.3), "sfx": "Play_sfx_hud_base_Pings_AreaIsWarded"},
}
const LIFE := 3.0
const WHEEL_DEADZONE := 22.0

var hud = null
var active_pings: Array = []    ## {world: Vector3, kind, t, unit}
var _press := {}                ## {screen, world, unit, minimap, t}
var _wheel_dir := -1
var _mouse := Vector2.ZERO
var _recent: Array = []         ## times of recent pings (throttle)


static func _tex(n: String) -> Texture2D:
	return Assets.tex("res://assets/ui/hud/pings/%s.png" % n)


func _modifier_down(mb: InputEventMouseButton) -> bool:
	return mb.alt_pressed or (not Rules.AUGMENTS_ENABLED and Input.is_physical_key_pressed(KEY_G)) or Input.is_physical_key_pressed(KEY_V)


## Returns true when the click was consumed by the ping system.
func handle_button(mb: InputEventMouseButton) -> bool:
	if mb.pressed:
		if not _modifier_down(mb):
			return false
		var sp := mb.position
		var on_mm: bool = hud._mm_rect.has_point(sp)
		if not on_mm and hud._over_ui(sp):
			return false
		var pc = hud.match_ref.player_controller if hud.match_ref != null else null
		var wp: Vector3 = hud.minimap_to_world(sp) if on_mm else hud.match_ref.camera_rig.screen_to_ground(sp, hud.match_ref.nav)
		if on_mm:
			wp.y = hud.match_ref.nav.height_at(wp)
		_press = {"screen": sp, "world": wp, "unit": null if on_mm or pc == null else pc.pick_unit(sp), "minimap": on_mm,
			"danger": (mb.ctrl_pressed and mb.alt_pressed) or Input.is_physical_key_pressed(KEY_V)}
		_mouse = sp
		_wheel_dir = -1
		return true
	if _press.is_empty():
		return false
	var p := _press
	_press = {}
	var kind := ""
	if _wheel_dir >= 0:
		kind = WHEEL[_wheel_dir]
	elif _mouse.distance_to(p.screen) <= WHEEL_DEADZONE:
		kind = "danger" if p.danger else _smart_kind(p.unit)
	_wheel_dir = -1
	if kind != "":
		ping(p.world, kind, p.unit)
	return true


func handle_motion(mp: Vector2) -> void:
	if _press.is_empty():
		return
	_mouse = mp
	var d: Vector2 = mp - _press.screen
	if d.length() <= WHEEL_DEADZONE:
		_wheel_dir = -1
		return
	# screen angle -> wedge (0 = north, clockwise)
	var ang := fposmod(atan2(d.x, -d.y), TAU)
	_wheel_dir = int(round(ang / (TAU / 8.0))) % 8


func _smart_kind(u) -> String:
	if u != null and is_instance_valid(u) and u != hud.champ:
		return "target" if u.team != hud.champ.team else "assist"
	return "ping"


func ping(world: Vector3, kind: String, unit = null) -> void:
	var now: float = hud._now
	_recent = _recent.filter(func(t): return now - t < 5.0)
	if _recent.size() >= 6:
		hud.fail_msg = "You must wait before pinging again"
		hud.fail_t = 1.2
		return
	_recent.append(now)
	active_pings.append({"world": world, "kind": kind, "t": now, "unit": unit})
	if active_pings.size() > 8:
		active_pings.pop_front()
	var info: Dictionary = KINDS.get(kind, KINDS.ping)
	hud.hud_sfx(info.sfx, 0.0, 250)   # [ui-feel] League's ping gain (Sfx.hud)


func process(_delta: float) -> void:
	if active_pings.is_empty():
		return
	var now: float = hud._now
	if now - active_pings[0].t > LIFE:
		active_pings = active_pings.filter(func(p): return now - p.t <= LIFE)


func active() -> bool:
	return not active_pings.is_empty()


func wheel_sig():
	if _press.is_empty() or _wheel_dir < 0 and _mouse.distance_to(_press.screen) <= WHEEL_DEADZONE:
		return null
	return [_wheel_dir, int(_press.screen.x), int(_press.screen.y)]


func _pos(p: Dictionary) -> Vector3:
	var u = p.unit
	if u != null and is_instance_valid(u) and not u.dead:
		return u.global_position
	return p.world


## World pings: icon pops in, ring expands twice, then everything fades (League ping update VFX timing).
func draw_world(ci: CanvasItem) -> void:
	if active_pings.is_empty():
		return
	var cam: Camera3D = hud.get_viewport().get_camera_3d()
	if cam == null:
		return
	var k: float = hud.L.s()
	for p in active_pings:
		var wp := _pos(p) + Vector3(0, 0.15, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp)
		var age: float = hud._now - p.t
		var info: Dictionary = KINDS.get(p.kind, KINDS.ping)
		var a := clampf((LIFE - age) / 0.5, 0.0, 1.0)
		for ring_i in 2:
			var rt := fmod(age - ring_i * 0.35, 1.2)
			if age - ring_i * 0.35 < 0.0 or age > 2.4:
				continue
			var rr := (20.0 + rt * 70.0) * k
			var ra := (1.0 - rt / 1.2) * a
			var ring := _tex(info.ring)
			if ring != null:
				ci.draw_texture_rect(ring, Rect2(sp - Vector2(rr, rr * 0.55), Vector2(rr * 2.0, rr * 1.1)), false, Color(1, 1, 1, ra))
		var pop := 1.0 + maxf(0.0, 0.2 - age) * 2.5
		var isz := 46.0 * k * pop
		var ic := _tex(info.icon)
		if ic != null:
			ci.draw_texture_rect(ic, Rect2(sp - Vector2(isz * 0.5, isz * 1.05), Vector2(isz, isz)), false, Color(1, 1, 1, a))


func draw_minimap(ci: CanvasItem) -> void:
	if active_pings.is_empty():
		return
	var mm: Rect2 = hud._mm_rect
	var u := mm.size.x / 283.0
	for p in active_pings:
		var sp: Vector2 = hud.world_to_minimap(_pos(p))
		var age: float = hud._now - p.t
		var info: Dictionary = KINDS.get(p.kind, KINDS.ping)
		var a := clampf((LIFE - age) / 0.5, 0.0, 1.0)
		var rt := fmod(age, 0.9)
		var rr := (6.0 + rt * 22.0) * u
		var ring := _tex(info.ring)
		if ring != null and age < 2.7:
			ci.draw_texture_rect(ring, Rect2(sp - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1, 1, 1, (1.0 - rt / 0.9) * a))
		var isz := 18.0 * u
		var ic := _tex(info.icon)
		if ic != null:
			ci.draw_texture_rect(ic, Rect2(sp - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, a))


## League's radial ping wheel around the press point; the hovered wedge lights up with its label.
func draw_wheel(ci: CanvasItem) -> void:
	if wheel_sig() == null:
		return
	var L: HudLayout = hud.L
	var k: float = L.vs.y / 1200.0 * 0.6 * L.hud_scale
	var origin: Vector2 = _press.screen - Vector2(382.0, 382.0) * k
	L.ldraw(ci, "Ping:PingWheel_BG_0", origin, k, Color(1, 1, 1, 0.9))
	for i in 8:
		var base: String = "Ping:PingWheel_" + WHEEL_KEYS[i]
		L.ldraw(ci, base + ("_ButtonHover" if i == _wheel_dir else "_ButtonDefault"), origin, k)
	L.ldraw(ci, "Ping:PingWheel_0C_ButtonDefault" if _wheel_dir >= 0 else "Ping:PingWheel_0C_ButtonHover", origin, k)
	if _wheel_dir >= 0:
		var tk: String = "Ping:PingWheel_" + WHEEL_TEXT[_wheel_dir]
		L.ltext_in(ci, tk, L.lr(tk, origin, k), WHEEL_LABEL[_wheel_dir].to_upper(), Color(0, 0, 0, 0), 1, L.hud_scale)
		# selection line from the centre to the cursor
		var c: Vector2 = _press.screen
		ci.draw_line(c, _mouse, Color(1, 1, 1, 0.6), maxf(1.5, 3.0 * k))
	else:
		var tk2 := "Ping:PingWheel_0C_Ping_Text"
		L.ltext_in(ci, tk2, L.lr(tk2, origin, k), "PING", Color(0, 0, 0, 0), 1, L.hud_scale)
