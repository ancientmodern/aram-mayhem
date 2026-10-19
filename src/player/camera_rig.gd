class_name CameraRig
extends Node3D
## League camera. Values (League units = cm, / 100 -> meters):
##  [spatial] calibrated against League's data and real ARAM footage (docs/SPATIAL_AUDIT.md):
##  - 50 deg vertical field of view: Global.wad Globals/CameraConfig_ARAM and CameraConfig_KIWI (ARAM Mayhem) set
##    ZoomFov = 50 (CameraConfig_CLASSIC leaves it at the engine default); fixed yaw, 56 deg pitch below horizontal
##  - zoom = camera distance to the focus point. At max zoom the real ARAM view spans ~1890 units vertically through
##    the focus (fit to a 900-unit Brand W range ring and an image registration of a turret shot, two videos);
##    with FOV 50 / pitch 56 that is 2020 units of eye distance (the fit gives pitch 56.0 at FOV 50). The old
##    40 deg / 2250 setup spanned 1638 units: 15% too close, which also made every range look 15% longer.
##    Games start fully zoomed out. Min zoom keeps the old 2:3 ratio (no data found).
##  - mouse wheel zooms in steps with smoothing (League "ScrollSmoothingEnabled")
##  - locked camera is rigidly centred on the champion (no lag); Y toggles lock; holding Space keeps the camera
##    snapped on your champion; F1 = own champion, F2-F5 = allies (hold to follow, like League)
##  - edge pan / middle-mouse drag when unlocked

const LEAGUE_FOV := 50.0         ## CameraConfig_ARAM / _KIWI ZoomFov
const LEAGUE_PITCH := 56.0
const MAX_ZOOM := 20.2           ## 2020 units (view spans ~1890 units through the focus, measured)
const MIN_ZOOM := 13.5           ## estimate, same 2:3 ratio as before
const ZOOM_STEP := 1.1           ## ~6 wheel notches from max to min

var cam: Camera3D
var target: Node3D = null
var locked := true
var focus := Vector3.ZERO
var distance := MAX_ZOOM
var target_distance := MAX_ZOOM
var pitch_deg := LEAGUE_PITCH
var fov := LEAGUE_FOV
var edge_pan_speed := 34.0       ## m/s at default zoom (MapScrollSpeed 0.5)
var min_dist := MIN_ZOOM
var max_dist := MAX_ZOOM
var trauma := 0.0
var _mmb_drag := false
var _mmb_last := Vector2.ZERO
var _follow_override: Node3D = null   ## F2-F5 ally being followed while the key is held
var spectate: Node3D = null           ## [hud-ref] ally followed from the dead player's BACK IN portraits (HUD clears it)
var _relock_t := 1.0                  ## 0..1 blend after re-locking so the jump is not a hard cut
var bounds := Rect2(Vector2(5, -125), Vector2(122, 120))   ## x, z range in world


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = fov
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 1.0
	cam.far = 300.0
	cam.current = true
	add_child(cam)


func shake(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


func snap_to(p: Vector3) -> void:
	focus = p
	_apply(0.0)


## [path] League: when your champion respawns the camera centres on it at once, free camera or not, and any ally you
## were watching from the death screen is dropped.
func on_player_respawn(p: Vector3) -> void:
	spectate = null
	_follow_override = null
	_mmb_drag = false
	_relock_t = 1.0
	snap_to(p)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			target_distance = maxf(min_dist, target_distance - ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			target_distance = minf(max_dist, target_distance + ZOOM_STEP)
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
	elif event is InputEventKey and not event.echo:
		var ke := event as InputEventKey
		var idx := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5].find(ke.keycode)
		if idx >= 0:
			if ke.pressed:
				_follow_override = _ally_by_index(idx)
			else:
				_follow_override = null
	if event.is_action_pressed("toggle_camera_lock"):
		locked = not locked
		G.settings.camera_locked = locked
		if locked:
			_relock_t = 0.0


func _ally_by_index(idx: int) -> Node3D:
	if target == null or not is_instance_valid(target) or G.match == null:
		return target
	if idx == 0:
		return target
	var allies: Array = []
	for c in G.match.champions:
		if c != target and c.team == target.team:
			allies.append(c)
	return allies[idx - 1] if idx - 1 < allies.size() else null


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	# smoothed zoom (exponential, ~0.15 s to settle)
	distance = lerpf(distance, target_distance, clampf(dt * 14.0, 0.0, 1.0))
	var centering := Input.is_action_pressed("center_camera")
	var follow: Node3D = null
	if _follow_override != null and is_instance_valid(_follow_override):
		follow = _follow_override
	elif spectate != null and is_instance_valid(spectate):
		follow = spectate
	elif target != null and is_instance_valid(target) and (locked or centering):
		follow = target
	if follow != null:
		var tp := follow.global_position
		if centering or _follow_override != null or follow == spectate:
			focus = tp
		else:
			# rigid lock like League; right after re-locking, glide in for a moment
			_relock_t = minf(1.0, _relock_t + dt * 6.0)
			focus = tp if _relock_t >= 1.0 else focus.lerp(tp, clampf(dt * 18.0, 0.0, 1.0))
	elif not locked and G.settings.get("edge_pan", true):
		_relock_t = 0.0
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
			focus += pan.normalized() * edge_pan_speed * dt * (distance / MAX_ZOOM)
	else:
		_relock_t = 0.0
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
