extends Node
## [fow] Fog-of-war probe: dumps the visibility texture and takes wide zoomed-out shots.
## tools/preview.sh 120 -- --champ=Ezreal --sim --botplayer --time=20 --harness=res://src/debug/fow_probe.gd --res=2560x1440
var match_ref = null
var _t := 0.0
var _step := 0


func _process(delta: float) -> void:
	_t += delta
	var rig = match_ref.camera_rig
	if _step == 0 and _t > 4.0:
		_step = 1
		rig.target_distance = 110.0
		rig.distance = 110.0
	elif _step == 1 and _t > 6.0:
		_step = 2
		_shot("fow_wide")
		var fm = match_ref.get_node("FowMap")
		for i in 2:
			var img: Image = fm._vps[i].get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img.save_png("user://fow_vis_%d.png" % i)
		print("FOWPROBE saved ticks=%d" % fm._ticks)
	elif _step == 2 and _t > 12.0:
		_step = 3
		_shot("fow_wide2")
		get_tree().quit()


func _shot(n: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % n)
	print("FOWPROBE shot ", n)
