extends "res://src/debug/kit_shots_b.gd"
## [anim-events] Visual QA for data-driven animation events: drives the player's kit like kit_shots_b and, whenever
## one of the player's clip events spawns a particle, screenshots it a moment later with the camera on the
## champion (so the effect is seen at its League bone and frame).
##   tools/preview.sh 240 -- --champ=Ezreal --harness=res://src/debug/anim_ev_shots.gd --kshots=P2,A,Q,W,R
##     --kdir=ae_ezreal [--aedelay=0.06] [--kdist=6]
## --aeworld: no kit steps; screenshots the first minion particle event and a turret's idle glow instead.
## --aepose: no kit steps; screenshots the champion idling, running and dancing (idle particles, joint snaps).
## Files: user://<kdir>/ev_<n>_<system>.png (+ the usual timed kit_shots_b frames).

var ae_delay := 0.06
var ae_n := 0
var ae_busy := false
var ae_seen := {}
var ae_world := false
var ae_focus: Node3D = null
var ae_pose := false
var ae_skip := 3.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--aedelay="):
			ae_delay = float(a.substr(10))
		elif a == "--aeworld":
			ae_world = true
		elif a == "--aepose":
			ae_pose = true
		elif a.begins_with("--aeskip="):
			ae_skip = float(a.substr(9))
	AnimEvents.debug_hook = _on_event
	if ae_world or ae_pose:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--kdir="):
				kdir = "user://" + a.substr(7)
			elif a.begins_with("--kdist="):
				kdist = float(a.substr(8))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(kdir))
		get_tree().create_timer(400.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
		if ae_pose:
			_pose()
		else:
			_world()
		return
	super._ready()


func _on_event(u, nm: String, bone: String) -> void:
	if ae_busy or u == null or not is_instance_valid(u):
		return
	if not ae_world and (G.match == null or G.match.time < ae_skip):
		return   # the level-up burst of the harness setup would cover the first events
	if ae_world:
		if u.kind != G.Kind.MINION or ae_seen.size() >= 3:
			return
	elif u != G.player:
		return
	var key := nm + "@" + bone
	if ae_seen.has(key):
		return
	ae_seen[key] = true
	ae_busy = true
	_ae_shot(u, nm)


func _ae_shot(u, nm: String) -> void:
	var t := 0.0
	while t < ae_delay:
		_ae_cam(u)
		await get_tree().process_frame
		t += get_process_delta_time()
	_ae_cam(u)
	await RenderingServer.frame_post_draw
	var path := "%s/ev_%02d_%s.png" % [kdir, ae_n, nm]
	get_viewport().get_texture().get_image().save_png(path)
	print("AESHOT ", ProjectSettings.globalize_path(path))
	ae_n += 1
	ae_busy = false


func _ae_cam(u) -> void:
	var m2 = G.match
	if m2 == null or m2.camera_rig == null or not is_instance_valid(u):
		return
	m2.camera_rig.locked = false
	m2.camera_rig.focus = u.global_position + Vector3(0, 1.0, 0)
	m2.camera_rig.target_distance = kdist
	m2.camera_rig.distance = kdist


func _world() -> void:
	# a turret's idle glow first (before the camera gets busy), then the first minion clashes (hook shots)
	await get_tree().create_timer(9.0, true, false, true).timeout
	var m2 = G.match
	if m2 != null:
		var best = null
		for u in m2.units:
			if is_instance_valid(u) and u.kind == G.Kind.TURRET and not u.dead and u.team == G.Team.ORDER:
				if best == null or u.global_position.length() < best.global_position.length():
					best = u
		if best != null:
			ae_busy = true
			for i in 30:
				m2.camera_rig.locked = false
				m2.camera_rig.focus = best.global_position + Vector3(0, 3.0, 0)
				m2.camera_rig.target_distance = 16.0
				m2.camera_rig.distance = 16.0
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/turret_glow.png" % kdir
			get_viewport().get_texture().get_image().save_png(path)
			print("AESHOT ", ProjectSettings.globalize_path(path))
			ae_busy = false
	var t := 0.0
	while t < 150.0 and ae_n < 3:
		await get_tree().create_timer(0.5, true, false, true).timeout
		t += 0.5
	print("AESHOT DONE")
	get_tree().quit()

func _pose_shot(u, n: String, frames: int = 20) -> void:
	for i in frames:
		_ae_cam(u)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [kdir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("AESHOT ", ProjectSettings.globalize_path(path))


func _pose() -> void:
	ae_busy = true   # no event shots
	await get_tree().create_timer(4.0, true, false, true).timeout
	var u = G.player
	if u == null:
		get_tree().quit(2)
		return
	await _pose_shot(u, "pose_idle", 30)
	u.issue_move(u.global_position + Vector3(6, 0, 3))
	await _pose_shot(u, "pose_run", 24)
	u.issue_stop()
	await get_tree().create_timer(0.8, true, false, true).timeout
	u.play_anim("dance", 1.0, 0.2)
	u.anim_lock = 6.0
	await _pose_shot(u, "pose_dance", 70)
	print("AESHOT DONE")
	get_tree().quit()
