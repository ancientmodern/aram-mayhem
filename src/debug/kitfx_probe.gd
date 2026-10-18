extends "res://src/debug/kit_shots_a.gd"
## Probe League VFX systems on the player champion (attach at a bone / ground spawn), screenshot each.
## tools/preview.sh 200 -- --champ=Leona --harness=res://src/debug/kitfx_probe.gd --shotdir=fxp_leona \
##     --fx=Leona_Base_Idle_Sword@BUFFBONE_GLB_WEAPON_1,Leona_Base_W_buf_1@:ground,...
## Spec: Name[@bone][:flags]; flags (comma-free, '+' separated): ground (spawn at feet, not attached), once (no loop),
## front (spawn 2.5 m ahead), target (attach to the first dummy), hit (spawn at dummy chest).
## Files: user://<shotdir>/fx<idx>_<name>_<ms>.png

var specs: Array = []


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
		elif a.begins_with("--shottimes="):
			shot_times = []
			for t in a.substr(12).split(","):
				shot_times.append(float(t))
		elif a.begins_with("--shotdist="):
			shot_dist = float(a.substr(11))
		elif a.begins_with("--fx="):
			specs = Array(a.substr(5).split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	await _wait(1.0)
	_setup()
	await _wait(0.5)
	var i := 0
	for sp in specs:
		await _one(i, String(sp))
		i += 1
	print("KFXP DONE")
	get_tree().quit()


func _one(idx: int, sp: String) -> void:
	var flags := ""
	var nm := sp
	if sp.contains(":"):
		nm = sp.get_slice(":", 0)
		flags = sp.get_slice(":", 1)
	var bone := ""
	if nm.contains("@"):
		bone = nm.get_slice("@", 1)
		nm = nm.get_slice("@", 0)
	var d: Champion = dummies[0]
	_reset_positions(3.0)
	await _qwait(0.4)
	K.ensure_fx(nm)
	if not LolVfx.has(nm):
		print("KFXP missing ", nm)
		return
	var fl: PackedStringArray = flags.split("+")
	var opts := {"loop": not ("once" in fl), "dir": c.facing}
	if bone != "":
		opts["bone"] = bone
	var node: LolVfx = null
	if "ground" in fl or "front" in fl:
		var p: Vector3 = c.global_position + (c.facing * 2.5 if "front" in fl else Vector3.ZERO)
		node = LolVfx.spawn(m, nm, p, opts)
	elif "hit" in fl:
		node = LolVfx.spawn(m, nm, d.global_position, {"dir": c.facing, "center": d.height * 0.5})
	elif "target" in fl:
		node = LolVfx.attach(d, nm, opts)
	else:
		node = LolVfx.attach(c, nm, opts)
	print("KFXP ", idx, " ", nm, " bone=", bone, " flags=", flags, " ok=", node != null)
	_cam()
	await _shots("fx%02d_%s" % [idx, nm.right(24)])
	if node != null and is_instance_valid(node):
		node.stop()
		node.queue_free()
	await _qwait(0.3)
