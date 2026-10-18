extends "res://src/debug/kit_shots_b.gd"
## [kitvfx-b] Timing probe for one League system on the player: attach, wait, stop(), and log the CPU cost of
## each step plus the worst frame afterwards. tools/preview.sh 120 -- --champ=Lux --harness=res://src/debug/fx_probe.gd
##   --fxname=Lux_Base_W_tar_shield [--fxhold=2.5]


func _shots() -> void:
	await _wait(1.0)
	_setup()
	var nm := "Lux_Base_W_tar_shield"
	var hold := 2.5
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fxname="):
			nm = a.substr(9)
		elif a.begins_with("--fxhold="):
			hold = float(a.substr(9))
	if "--fxcast" in OS.get_cmdline_user_args():
		Prof.enabled = true
		_place(5.0)
		for rep in 4:
			var t2 := Time.get_ticks_usec()
			_cast(1, foes[0].global_position, foes[0])
			print("FXPROBE cast %.2f ms" % [(Time.get_ticks_usec() - t2) / 1000.0])
			await _wait(4.0)
		print("KSHOT DONE")
		get_tree().quit()
		return
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		var fx := LolVfx.attach(foes[0], nm, {"height": 1.0})
		print("FXPROBE attach %.2f ms (ok=%s)" % [(Time.get_ticks_usec() - t0) / 1000.0, fx != null])
		await _wait(hold)
		var t1 := Time.get_ticks_usec()
		if fx != null:
			fx.stop()
		print("FXPROBE stop %.2f ms" % [(Time.get_ticks_usec() - t1) / 1000.0])
		var worst := 0.0
		for i in 120:
			var f0 := Time.get_ticks_usec()
			await get_tree().process_frame
			worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
		print("FXPROBE worst frame after stop %.2f ms" % worst)
	print("KSHOT DONE")
	get_tree().quit()
