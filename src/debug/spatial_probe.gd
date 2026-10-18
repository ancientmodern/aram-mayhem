extends Node
## [spatial] Camera calibration probe. Places the camera rig at fixed League-space focus points with given
## FOV / pitch / distance and saves screenshots, plus prints the screen position of every structure so the frame
## can be compared numerically with real League footage (docs/SPATIAL_AUDIT.md).
## Usage: tools/preview.sh 120 -- --champ=MissFortune --harness=res://src/debug/spatial_probe.gd --res=1280x720 \
##          --probe_focus=7300,7300 --probe_cams=50:56:22.5,40:56:22.5 --probe_dir=spatial
##   --probe_focus=x,z[;x,z...]  League coordinates of the camera focus (default: the player's spawn)
##   --probe_cams=fov:pitch:dist[,..]  vertical FOV (deg), pitch (deg), distance (m); default: the rig's own values
##   --probe_player=1            keep the camera on the player (default camera at game start) instead of a focus
var main = null
var match_ref = null


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _shot(dir: String, n: String) -> void:
	await RenderingServer.frame_post_draw
	var d := "user://%s" % dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [d, n])
	print("PROBESHOT ", ProjectSettings.globalize_path("%s/%s.png" % [d, n]))


func _ready() -> void:
	_run()


func _run() -> void:
	await _wait(float(_arg("probe_wait", "2.5")))
	var rig: CameraRig = match_ref.camera_rig
	var dir := _arg("probe_dir", "spatial")
	var keep_player := _arg("probe_player", "0") == "1"
	var focuses: Array = []
	for f in _arg("probe_focus", "").split(";", false):
		var p := f.split(",")
		focuses.append(G.lol_pos(float(p[0]), 0.0, float(p[1])))
	if focuses.is_empty():
		focuses.append(G.player.global_position)
	var cams: Array = []
	for c in _arg("probe_cams", "").split(",", false):
		var p := c.split(":")
		cams.append([float(p[0]), float(p[1]), float(p[2])])
	if cams.is_empty():
		cams.append([rig.fov, rig.pitch_deg, rig.target_distance])
	# --probe_grid=fov0:fov1:step/pitch0:pitch1:step replaces --probe_cams (distance from --probe_span)
	var grid := _arg("probe_grid", "")
	if grid != "":
		cams.clear()
		var gp := grid.split("/")
		var fa := gp[0].split(":")
		var pa := gp[1].split(":")
		var fv := float(fa[0])
		while fv <= float(fa[1]) + 0.001:
			var pv := float(pa[0])
			while pv <= float(pa[1]) + 0.001:
				cams.append([fv, pv, 22.5])
				pv += float(pa[2])
			fv += float(fa[2])
	# --probe_span=m: distance chosen so the vertical view span through the focus is m metres
	var span := float(_arg("probe_span", "0"))
	# --probe_pin=x,z:px,py : solve the focus so League point (x, z) lands on that pixel
	var pin := _arg("probe_pin", "")
	var pin_w := Vector3.INF
	var pin_px := Vector2.ZERO
	if pin != "":
		var a := pin.split(":")
		var w := a[0].split(",")
		var s := a[1].split(",")
		pin_w = G.lol_pos(float(w[0]), 0.0, float(w[1]))
		pin_w.y = match_ref.nav.height_at(pin_w) if match_ref.nav != null else 0.0
		pin_px = Vector2(float(s[0]), float(s[1]))
	if _arg("probe_clean", "0") == "1":
		if match_ref.hud != null:
			match_ref.hud.visible = false
		for u in match_ref.units:
			if is_instance_valid(u) and u.kind != G.Kind.TURRET and u.kind != G.Kind.INHIBITOR and u.kind != G.Kind.NEXUS:
				u.visible = false
		for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(n as CanvasLayer).visible = false
	# --probe_rings=r1,r2 : thin reference rings (League units) around every relic pad and --probe_relicfx=scale
	# spawns the relic heal indicator there (looping) at that scale
	var rings := _arg("probe_rings", "")
	var relic_fx := float(_arg("probe_relicfx", "0"))
	if rings != "" or relic_fx > 0.0:
		LolVfx.load_set("shared")
		for rp in MapBuilder.relic_points(MapBuilder.load_layout()):
			var gp: Vector3 = rp
			gp.y = match_ref.nav.height_at(gp) if match_ref.nav != null else gp.y
			for rs in rings.split(",", false):
				var mi := Vfx.indicator_mesh(4, Color(1.0, 0.9, 0.1, 1.0))
				match_ref.add_child(mi)
				mi.global_position = gp + Vector3(0, 0.08, 0)
				mi.scale = Vector3(float(rs) * G.U * 2.0, 1.0, float(rs) * G.U * 2.0)
			if relic_fx > 0.0:
				LolVfx.spawn(match_ref, "HowlingAbyss_HealthPickup_Redemption_Indicator", gp, {"scale": relic_fx, "loop": true})
	var vp := get_viewport().get_visible_rect().size
	print("PROBE viewport ", vp)
	for fi in focuses.size():
		for cfg in cams:
			rig.fov = cfg[0]
			rig.cam.fov = cfg[0]
			rig.pitch_deg = cfg[1]
			if span > 0.0:
				cfg[2] = span / (2.0 * tan(deg_to_rad(cfg[0]) * 0.5))
			rig.distance = cfg[2]
			rig.target_distance = cfg[2]
			if not keep_player:
				rig.target = null
				rig.locked = true
				var fp: Vector3 = focuses[fi]
				fp.y = match_ref.nav.height_at(fp) if match_ref.nav != null else fp.y
				rig.snap_to(fp)
				if pin_w.is_finite():
					fp = pin_w
					for it in 12:
						rig.snap_to(fp)
						var err: Vector2 = rig.cam.unproject_position(pin_w) - pin_px
						if err.length() < 0.3:
							break
						var g0 := rig.screen_to_ground(vp * 0.5, null)
						var g1 := rig.screen_to_ground(vp * 0.5 + err, null)
						fp += Vector3(g1.x - g0.x, 0.0, g1.z - g0.z)
			await _wait(0.4)
			var tag := "f%d_fov%d_p%d_d%d" % [fi, int(cfg[0]), int(cfg[1]), int(cfg[2] * 100.0)]
			for s in match_ref.structures:
				var sp: Vector3 = s.global_position
				if rig.cam.is_position_behind(sp):
					continue
				var px: Vector2 = rig.cam.unproject_position(sp)
				if px.x > -200 and px.y > -200 and px.x < vp.x + 200 and px.y < vp.y + 200:
					print("PROBE %s %s lol(%.0f,%.0f) -> px(%.1f,%.1f)" % [tag, s.display_name, sp.x / G.U, -sp.z / G.U, px.x, px.y])
			if keep_player and G.player != null:
				var pp: Vector2 = rig.cam.unproject_position(G.player.global_position)
				print("PROBE %s player px(%.1f,%.1f) focus-offset(m)=%s" % [tag, pp.x, pp.y, str(G.player.global_position - rig.focus)])
			# on-screen size of every champion: feet -> top of its model height (unit.height), and its gameplay radius
			for ch in match_ref.champions:
				if not is_instance_valid(ch) or rig.cam.is_position_behind(ch.global_position):
					continue
				var f0: Vector2 = rig.cam.unproject_position(ch.global_position)
				var f1: Vector2 = rig.cam.unproject_position(ch.global_position + Vector3(0, ch.height, 0))
				var r1: Vector2 = rig.cam.unproject_position(ch.global_position + Vector3(ch.radius, 0, 0))
				if f0.x > 0 and f0.y > 0 and f0.x < vp.x and f0.y < vp.y:
					print("PROBE %s champ %s at px(%.0f,%.0f) height %.2fm -> %.0f px tall, gameplay radius %.0f px" % [tag, ch.display_name, f0.x, f0.y, ch.height, f0.y - f1.y, r1.x - f0.x])
			# ground footprint of the view (corner rays against the focus plane)
			var corners := []
			for c in [Vector2(0, 0), Vector2(vp.x, 0), Vector2(0, vp.y), Vector2(vp.x, vp.y), vp * 0.5]:
				var o := rig.cam.project_ray_origin(c)
				var dv := rig.cam.project_ray_normal(c)
				var t := (rig.focus.y - o.y) / dv.y
				var g := o + dv * t
				corners.append("(%.0f,%.0f)" % [g.x / G.U, -g.z / G.U])
			print("PROBE %s footprint TL,TR,BL,BR,C (lol units) %s" % [tag, " ".join(corners)])
			await _shot(dir, tag)
	get_tree().quit()
