class_name PlayerController
extends Node
## Translates mouse/keyboard input into commands for the player's champion.

var champ: Champion = null
var match_ref = null
var rig: CameraRig = null
var mouse_ground := Vector3.ZERO
var hovered: Unit = null
var attack_move_armed := false
var aiming := -1                    ## slot being aimed (quick cast with indicator)
var _rmb_held := false
var _rmb_timer := 0.0
var _indicator_root: Node3D
var _ind_main: MeshInstance3D
var _ind_range: MeshInstance3D
var _ind_area: MeshInstance3D
var _hover_prev: Unit = null
var ui_blocking := false            ## HUD panels (shop) grabbing input
const CAST_ACTIONS := ["cast_q", "cast_w", "cast_e", "cast_r"]


func _ready() -> void:
	_indicator_root = Node3D.new()
	_indicator_root.name = "Indicators"
	match_ref.add_child(_indicator_root)
	_ind_range = Vfx.indicator_mesh(3, Color(0.35, 0.75, 1.0, 0.55))
	_ind_main = Vfx.indicator_mesh(1, Color(0.35, 0.75, 1.0, 0.45))
	_ind_area = Vfx.indicator_mesh(0, Color(0.35, 0.75, 1.0, 0.5))
	for n in [_ind_range, _ind_main, _ind_area]:
		_indicator_root.add_child(n)
		n.visible = false


func _process(_delta: float) -> void:
	if champ == null or rig == null:
		return
	var mp := get_viewport().get_mouse_position()
	mouse_ground = rig.screen_to_ground(mp, match_ref.nav)
	hovered = pick_unit(mp)
	_update_hover_glow()
	if _rmb_held and not champ.dead:
		_rmb_timer -= _delta
		if _rmb_timer <= 0.0:
			_rmb_timer = 0.09
			if hovered == null or not _is_enemy_target(hovered):
				champ.issue_move(mouse_ground)
	_update_indicator()


func _is_enemy_target(u: Unit) -> bool:
	return u != null and u.team != champ.team and u.is_targetable_by(champ.team)


## Screen-space unit picking (forgiving, like League).
func pick_unit(mp: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	var cam := rig.cam
	for u in match_ref.units:
		if u.dead or u == champ and false:
			continue
		if u.team != champ.team and not u.visible_to[champ.team]:
			continue
		var base_p: Vector3 = u.global_position
		var top := base_p + Vector3(0, u.height * 0.55, 0)
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		var edge := cam.unproject_position(top + cam.global_basis.x * u.selection_radius)
		var r := maxf(18.0, sp.distance_to(edge))
		var d := sp.distance_to(mp)
		var sp2 := cam.unproject_position(base_p + Vector3(0, u.height * 0.15, 0))
		d = minf(d, sp2.distance_to(mp) * 1.1)
		if d <= r * 1.15:
			var score := d / r
			if u == champ:
				score += 0.6
			if u.team != champ.team:
				score -= 0.2
			if score < best_d:
				best_d = score
				best = u
	return best


func _update_hover_glow() -> void:
	if _hover_prev == hovered:
		return
	if _hover_prev != null and is_instance_valid(_hover_prev):
		set_unit_glow(_hover_prev, Color(0, 0, 0, 0))
	if hovered != null and hovered != champ:
		var c := Color(1.0, 0.2, 0.15, 0.9) if hovered.team != champ.team else Color(0.25, 0.6, 1.0, 0.8)
		set_unit_glow(hovered, c)
	_hover_prev = hovered
	var shape := Input.CURSOR_ARROW
	if hovered != null and _is_enemy_target(hovered):
		shape = Input.CURSOR_CROSS
	Input.set_default_cursor_shape(shape)


static func set_unit_glow(u: Unit, c: Color) -> void:
	if u.model == null:
		return
	_set_glow_rec(u.model, c)


static func _set_glow_rec(n: Node, c: Color) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).set_instance_shader_parameter("glow", c)
	for ch in n.get_children():
		_set_glow_rec(ch, c)


func _unhandled_input(event: InputEvent) -> void:
	if champ == null or match_ref == null or match_ref.over or match_ref.paused:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_held = mb.pressed
			if mb.pressed:
				if aiming >= 0:
					_cancel_aim()
				attack_move_armed = false
				_right_click()
				_rmb_timer = 0.25
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if aiming >= 0 and _cast_mode() == 2:
				_cast_slot(aiming)
				_cancel_aim()
				get_viewport().set_input_as_handled()
			elif attack_move_armed:
				attack_move_armed = false
				var t := hovered if hovered != null and _is_enemy_target(hovered) else _attack_move_target()
				if t != null:
					champ.issue_attack(t)
				else:
					champ.issue_attack_move(mouse_ground)
				_click_marker(mouse_ground, true)
				get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.echo:
		return
	for i in 4:
		var act: String = CAST_ACTIONS[i]
		if event.is_action_pressed(act, false, false) or (k.pressed and k.physical_keycode == [KEY_Q, KEY_W, KEY_E, KEY_R][i]):
			if k.ctrl_pressed or k.alt_pressed:
				if k.pressed:
					champ.level_ability(i)
				get_viewport().set_input_as_handled()
				return
			if k.pressed:
				if _cast_mode() == 0:
					_cancel_aim()
					if _can_begin(i):
						_cast_slot(i)
				else:
					_begin_aim(i)
			get_viewport().set_input_as_handled()
			return
		if (event.is_action_released(act) or (not k.pressed and k.physical_keycode == [KEY_Q, KEY_W, KEY_E, KEY_R][i])) and aiming == i:
			if _cast_mode() == 1:
				_cast_slot(i)
				_cancel_aim()
			get_viewport().set_input_as_handled()
			return
	if not k.pressed:
		return
	if event.is_action_pressed("summoner_d"):
		_cast_slot(5)
	elif event.is_action_pressed("summoner_f"):
		_cast_slot(6)
	elif event.is_action_pressed("attack_move"):
		attack_move_armed = true
	elif event.is_action_pressed("stop"):
		champ.issue_stop()
		attack_move_armed = false
	elif event.is_action_pressed("hold"):
		champ.issue_hold()
	elif event.is_action_pressed("dance"):
		champ.play_anim("dance" if not k.shift_pressed else "taunt", 1.0, 0.2)
		if match_ref.audio != null:
			match_ref.audio.emote(champ, "dance" if not k.shift_pressed else "taunt")
		champ.anim_lock = 6.0 if not k.shift_pressed else 2.5
		champ.issue_stop()
	elif k.keycode == KEY_ESCAPE:
		if aiming >= 0:
			_cancel_aim()
		elif attack_move_armed:
			attack_move_armed = false
		elif match_ref.pause_menu != null:
			match_ref.pause_menu.open()
		attack_move_armed = false
	for i in 6:
		if event.is_action_pressed("item_%d" % (i + 1)):
			_use_item(i)


func _right_click() -> void:
	if champ.dead:
		return
	if hovered != null and _is_enemy_target(hovered):
		champ.issue_attack(hovered)
		_click_marker(hovered.global_position, true)
		if hovered.kind == G.Kind.CHAMPION and match_ref.audio != null:
			match_ref.audio.player_order("attack")
	else:
		champ.issue_move(mouse_ground)
		_click_marker(mouse_ground, false)
		if match_ref.audio != null:
			match_ref.audio.player_order("move")


func _click_marker(pos: Vector3, attack: bool) -> void:
	if not attack and LolVfx.has("Cursor_Moveto"):
		LolVfx.spawn(match_ref, "Cursor_Moveto", pos + Vector3(0, 0.05, 0))
		return
	var col := Color(1.0, 0.25, 0.2) if attack else Color(0.35, 1.0, 0.45)
	Vfx.ring(match_ref, pos, col, 0.55, 0.35, 0.2, 0.0)


# ------------------------------------------------------------------ casting
func ability_for_slot(slot: int) -> Ability:
	return champ.ability(slot)


func _cast_mode() -> int:
	return int(G.settings.get("cast_mode", 0))


func _can_begin(slot: int) -> bool:
	var ab := ability_for_slot(slot)
	if ab == null:
		return false
	if ab.level <= 0:
		champ.on_cast_failed(ab, "not learned")
		return false
	return true


## A-click: the enemy closest to the cursor among those already in attack range (League behaviour).
func _attack_move_target() -> Unit:
	var best: Unit = null
	var bd := INF
	for u in match_ref.units_in_radius(champ.global_position, champ.attack_range_m() + champ.radius + 1.0, G.enemy_team(champ.team)):
		if not _is_enemy_target(u) or not champ.in_attack_range(u):
			continue
		var d := G.flat_dist(u.global_position, mouse_ground)
		if d < bd:
			bd = d
			best = u
	return best


func _begin_aim(slot: int) -> void:
	if not _can_begin(slot):
		return
	aiming = slot


func _cancel_aim() -> void:
	aiming = -1
	_ind_main.visible = false
	_ind_range.visible = false
	_ind_area.visible = false


func _cast_slot(slot: int) -> void:
	var ab := ability_for_slot(slot)
	if ab == null or champ.dead:
		return
	var tgt := hovered
	if ab.target_type == Ability.Target.UNIT and not ab.valid_unit_target(tgt):
		tgt = _smart_unit_target(ab)
	var t := ab.make_target(mouse_ground, tgt)
	ab.try_cast(t)


## Nearest valid unit to the cursor (forgiving targeting for point-and-click spells).
func _smart_unit_target(ab: Ability) -> Unit:
	var best: Unit = null
	var bd := 3.0
	for u in match_ref.units:
		if not ab.valid_unit_target(u):
			continue
		var d := G.flat_dist(u.global_position, mouse_ground)
		if u.kind == G.Kind.CHAMPION:
			d -= 0.8
		if d < bd:
			bd = d
			best = u
	return best


func _use_item(i: int) -> void:
	if i < champ.items.size():
		var it = champ.items[i]
		if it.has_method("activate"):
			it.activate(mouse_ground, hovered)


func _update_indicator() -> void:
	if attack_move_armed and aiming < 0 and not champ.dead:
		var o0 := champ.global_position
		var ar := champ.attack_range_m() + champ.radius
		_ind_range.visible = true
		_ind_range.global_position = Vector3(o0.x, o0.y + 0.12, o0.z)
		_ind_range.scale = Vector3(ar * 2.0, 1, ar * 2.0)
		_ind_range.material_override.set_shader_parameter("color", Color(1.0, 0.35, 0.3, 0.4))
		return
	if aiming < 0 or champ.dead:
		if _ind_main.visible or _ind_range.visible or _ind_area.visible:
			_cancel_aim()
		return
	var ab := ability_for_slot(aiming)
	if ab == null:
		return
	var o := champ.global_position
	var y := o.y + 0.12
	var col := Color(0.35, 0.75, 1.0, 0.55)
	if not ab.is_ready() or not ab.can_afford():
		col = Color(0.7, 0.7, 0.7, 0.35)
	# range ring
	var rr := ab.range_m()
	_ind_range.visible = rr > 0.5
	if _ind_range.visible:
		_ind_range.global_position = Vector3(o.x, y, o.z)
		_ind_range.scale = Vector3(rr * 2.0 + champ.radius * 2.0, 1, rr * 2.0 + champ.radius * 2.0)
		_ind_range.material_override.set_shader_parameter("color", Color(col.r, col.g, col.b, 0.35))
	var dir := G.flat_dir(o, mouse_ground)
	_ind_main.visible = false
	_ind_area.visible = false
	match ab.indicator:
		Ability.Ind.LINE:
			var length := (ab.ind_length if ab.ind_length > 0.0 else ab.cast_range) * G.U
			var w := ab.ind_width * G.U
			_ind_main.visible = true
			_ind_main.material_override.set_shader_parameter("shape", 1)
			_ind_main.material_override.set_shader_parameter("color", col)
			_ind_main.global_position = Vector3(o.x, y, o.z) + dir * length * 0.5
			_ind_main.global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z)).scaled(Vector3(w, 1, length))
		Ability.Ind.CONE:
			var length2 := (ab.ind_length if ab.ind_length > 0.0 else ab.cast_range) * G.U
			_ind_main.visible = true
			_ind_main.material_override.set_shader_parameter("shape", 2)
			_ind_main.material_override.set_shader_parameter("cone_half", deg_to_rad(ab.ind_angle * 0.5))
			_ind_main.material_override.set_shader_parameter("color", col)
			_ind_main.global_position = Vector3(o.x, y, o.z) + dir * length2 * 0.5
			_ind_main.global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z)).scaled(Vector3(length2 * 2.0, 1, length2))
		Ability.Ind.CIRCLE:
			var t := ab.make_target(mouse_ground, hovered)
			var p: Vector3 = t.pos
			var r := ab.ind_radius * G.U
			_ind_area.visible = true
			_ind_area.material_override.set_shader_parameter("color", col)
			_ind_area.global_position = Vector3(p.x, match_ref.nav.height_at(p) + 0.12, p.z)
			_ind_area.scale = Vector3(r * 2.0, 1, r * 2.0)
		_:
			pass
