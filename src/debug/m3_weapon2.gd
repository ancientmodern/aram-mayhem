extends Node
## [motion3] which bone does the weapon bone stay near in a clip? (parent / space diagnosis)
## tools/check.sh 600 -- --champ=Lux --harness=res://src/debug/m3_weapon2.gd --mclip=spell4

var main
var match_ref
var _done := false
var _f := 0


func _process(_d: float) -> void:
	_f += 1
	if _done or match_ref == null or G.player == null or _f < 20:
		return
	_done = true
	var clip := "spell4"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mclip="):
			clip = a.substr(8)
	var u: Unit = G.player
	var ap: AnimationPlayer = u.anim_player
	var skel: Skeleton3D = u._skel
	var wep := -1
	for i in skel.get_bone_count():
		if skel.get_bone_name(i).to_lower() == "weapon":
			wep = i
	ap.active = true
	var a := ap.get_animation(clip)
	ap.play(clip, 0.0, 1.0)
	var n := skel.get_bone_count()
	var mn := []
	var mx := []
	mn.resize(n)
	mx.resize(n)
	for i in n:
		mn[i] = INF
		mx[i] = 0.0
	for s in 41:
		ap.seek(minf(a.length * float(s) / 40.0, a.length - 0.0001), true)
		var wp := skel.get_bone_global_pose(wep).origin
		for i in n:
			var d := (skel.get_bone_global_pose(i).origin - wp).length()
			mn[i] = minf(mn[i], d)
			mx[i] = maxf(mx[i], d)
	var rows := []
	for i in n:
		rows.append([mx[i] - mn[i], i])
	rows.sort_custom(func(x, y): return x[0] < y[0])
	for r in rows.slice(0, 12):
		print("[w2] %-32s range=%.3f min=%.3f max=%.3f" % [skel.get_bone_name(r[1]), r[0], mn[r[1]], mx[r[1]]])
	get_tree().quit()
