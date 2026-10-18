class_name CameraRig
extends Node3D
## League-style camera: fixed yaw, ~56 deg pitch, lock/unlock, edge pan, zoom, shake.

var cam: Camera3D
var target: Node3D = null
var locked := true
var focus := Vector3.ZERO
var distance := 21.0
var target_distance := 21.0
var pitch_deg := 56.0
var fov := 40.0
var edge_pan_speed := 34.0
var min_dist := 13.0
var max_dist := 27.0
var trauma := 0.0
var _mmb_drag := false
var _mmb_last := Vector2.ZERO
var bounds := Rect2(Vector2(5, -125), Vector2(122, 120))   ## x, z range in world


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = fov
	cam.near = 0.5
	cam.far = 400.0
	cam.current = true
	add_child(cam)


func shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func snap_to(p: Vector3) -> void:
	focus = p
	_apply(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_distance = maxf(min_dist, target_distance - 1.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_distance = minf(max_dist, target_distance + 1.5)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_drag = mb.pressed
			_mmb_last = mb.position
	elif event is InputEventMouseMotion and _mmb_drag:
		var mm := event as InputEventMouseMotion
		var d := mm.position - _mmb_last
		_mmb_last = mm.position
		var k := distance * 0.0018
		focus += Vector3(-d.x * k, 0.0, -d.y * k * 1.3)
		locked = false
	if event.is_action_pressed("toggle_camera_lock"):
		locked = not locked
		G.settings.camera_locked = locked


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	distance = lerpf(distance, target_distance, clampf(dt * 10.0, 0.0, 1.0))
	var centering := Input.is_action_pressed("center_camera")
	if target != null and is_instance_valid(target) and (locked or centering):
		var tp := target.global_position
		focus = focus.lerp(Vector3(tp.x, tp.y, tp.z), clampf(dt * (12.0 if centering else 8.0), 0.0, 1.0))
	elif not locked and G.settings.get("edge_pan", true):
		var vp := get_viewport()
		var mp := vp.get_mouse_position()
		var size := vp.get_visible_rect().size
		var margin := 6.0
		var pan := Vector3.ZERO
		if mp.x <= margin:
			pan.x -= 1.0
		elif mp.x >= size.x - margin:
			pan.x += 1.0
		if mp.y <= margin:
			pan.z -= 1.0
		elif mp.y >= size.y - margin:
			pan.z += 1.0
		if DisplayServer.window_is_focused() and pan != Vector3.ZERO:
			focus += pan.normalized() * edge_pan_speed * dt * (distance / 21.0)
	focus.x = clampf(focus.x, bounds.position.x, bounds.end.x)
	focus.z = clampf(focus.z, bounds.position.y, bounds.end.y)
	_apply(dt)


func _apply(dt: float) -> void:
	var p := deg_to_rad(pitch_deg)
	var offset := Vector3(0.0, sin(p), cos(p)) * distance
	var shake_off := Vector3.ZERO
	if trauma > 0.0:
		var s := trauma * trauma
		shake_off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * s * 0.45
		trauma = maxf(0.0, trauma - dt * 1.8)
	global_position = focus + offset + shake_off
	cam.global_position = global_position
	cam.look_at(focus + shake_off * 0.5, Vector3.UP)


## Ray from screen point against the terrain height field. Returns ground point.
func screen_to_ground(screen_pos: Vector2, nav: NavGrid) -> Vector3:
	var from := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var h := focus.y
	var p := from
	for i in 4:
		if absf(dir.y) < 0.0001:
			break
		var t := (h - from.y) / dir.y
		p = from + dir * t
		if nav != null:
			h = nav.height_at(p)
	return p
