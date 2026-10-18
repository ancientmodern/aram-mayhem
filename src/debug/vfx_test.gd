class_name VfxTest
extends Node
## QA: spawn League VFX systems next to a champion and screenshot them.
## Usage: godot --path . -- --champ=Ahri --vfxtest[=Name1,Name2,...] [--vfxdir=NAME]
##   --vfxtimes=0.1,0.3,0.6   screenshot times (s after spawn)
##   --vfxdist=12             camera distance
##   --vfxsolo                one system per shot set (names run one after another, files prefixed by index)
## Names containing "_mis" fly on a moving carrier (trails), "_buf"/"_cas" attach to the champion (bones),
## everything else spawns at a point in front of the champion at chest height ("_tar" uses the hit bone).

var names: Array = []
var shot_dir := "user://vfxtest"
var times: Array = [0.12, 0.35, 0.7, 1.4]
var dist := 15.0
var solo := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfxtest="):
			names = Array(a.substr(10).split(","))
		elif a.begins_with("--vfxdir="):
			shot_dir = "user://" + a.substr(9)
		elif a.begins_with("--rotorder="):
			LolVfx.ROT_ORDER = int(a.substr(11))
		elif a.begins_with("--vfxtimes="):
			times = []
			for t in a.substr(11).split(","):
				times.append(float(t))
		elif a.begins_with("--vfxdist="):
			dist = float(a.substr(10))
		elif a == "--vfxsolo":
			solo = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("VFXTEST SHOT ", ProjectSettings.globalize_path(path))


func _spawn(m, c, n: String, pos: Vector3) -> void:
	var low := n.to_lower()
	if low.contains("_mis") or low.ends_with("_ba1"):
		# moving carrier so trails show (League missile speed ~1500-2000 u/s)
		var carrier := Node3D.new()
		m.fx_root.add_child(carrier)
		carrier.global_position = pos + Vector3(-4, 0, 0)
		var fx := LolVfx.attach(carrier, n, {"loop": true, "missile": true, "mis": {"start_h": 1.0}})
		carrier.look_at(carrier.global_position + Vector3.RIGHT, Vector3.UP)
		var tw := carrier.create_tween()
		tw.tween_property(carrier, "global_position", pos + Vector3(4, 0, 0), 0.5)
		tw.tween_callback(func(): fx.detach_and_fade())
	elif low.contains("_buf") or low.contains("_cas") or low.contains("avatar") or low.begins_with("loc_"):
		var opts := {"center": c.height * 0.5}
		if low.begins_with("loc_") or low.contains("overhead"):
			opts["bone"] = "C_BUFFBONE_GLB_OVERHEAD_LOC"
		elif low.contains("_cas"):
			var k := ""
			for s in ["_Q_", "_W_", "_E_", "_R_"]:
				if n.contains(s):
					k = s.substr(1, 1)
			var meta := LolVfx.spell_meta(c, k) if k != "" else {}
			if meta.has("start_bone"):
				opts["bone"] = meta.start_bone
		var fx2 := LolVfx.attach(c, n, opts)
		var b: String = String(fx2._opts.get("bone", "")) if fx2 != null else ""
		var off: Vector3 = (c.socket(b).global_position - c.global_position) if b != "" and c.has_method("socket") else Vector3.ZERO
		print("VFXTEST attach ", n, " bone=", b, " socket offset=", off, " ok=", fx2 != null)
	else:
		var p := pos - Vector3(0, 0.9, 0)
		var o := {"dir": Vector3.RIGHT, "center": c.height * 0.5}
		if low.contains("beam"):
			o["length"] = 10.0
		LolVfx.spawn(m, n, p, o)


func _run() -> void:
	await _wait(1.0)
	var m = G.match
	var c = G.player
	if c.get("augments_pending") != null and c.augments_pending > 0 and m.has_method("get_offer"):
		m.get_offer(c)
		m.choose_augment(c, 0)
	LolVfx.load_set(c.alias)
	LolVfx.load_set("shared")
	LolVfx.load_set("map12")
	if names.is_empty():
		var p := "%s_Base_" % c.alias
		names = [p + "BA_mis", p + "BA_tar", p + "Q_mis", p + "Q_tar", p + "W_cas", p + "E_mis", p + "R_cas", p + "Q_cas"]
	# park the champion in an open area and freeze the match so nothing walks into frame
	var spot: Vector3 = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	c.teleport(spot)
	m.camera_rig.locked = false
	m.camera_rig.focus = spot + Vector3(2.5, 0, 0)
	m.camera_rig.target_distance = dist
	await _wait(0.5)
	m.paused = true
	var groups: Array = []
	if solo:
		for n in names:
			groups.append([n])
	else:
		groups.append(names)
	var gi := 0
	for g in groups:
		var i := 0
		for n in g:
			LolVfx.load_set(n.get_slice("_", 0))   # systems of other champions ("Lux_Base_Q_mis")
			if not LolVfx.has(n):
				print("VFXTEST missing ", n)
				continue
			var pos: Vector3 = spot + Vector3(2.5 + (i % 4) * 3.2 - 4.0, 0.9, -2.0 + (i / 4) * 3.5)
			if solo:
				pos = spot + Vector3(3.0, 0.9, 0.0)
			pos.y = m.nav.height_at(pos) + 0.9
			_spawn(m, c, n, pos)
			i += 1
		var prev := 0.0
		for t in times:
			await _wait(maxf(t - prev, 0.0))
			prev = t
			var pre := ("%02d_" % gi) if solo else ""
			await _shot("%svfx_%04d" % [pre, int(t * 1000)])
		if solo:
			await _wait(2.5)   # let the previous system clear
		gi += 1
	print("VFXTEST DONE")
	get_tree().quit()
