extends Node
## Micro-benchmark: cost of LolVfx.spawn per system (first spawn = cold, then warm average), CPU only.
## Usage: godot --path . --audio-driver Dummy -- --champ=Ezreal --harness=res://src/debug/vfx_bench.gd

var match_ref = null
var _done := false
var _t := 0.0


func _process(dt: float) -> void:
	_t += dt
	if _done or _t < 3.0 or match_ref == null:
		return
	_done = true
	for f in ["ezreal", "lux", "jinx", "annie", "yasuo", "shared"]:
		LolVfx.load_set(f)
	var names := []
	for set_name in ["Ezreal_Base_Q_mis", "Ezreal_Base_Q_tar", "Ezreal_Base_W_mis", "Ezreal_Base_R_mis", "Lux_Base_Q_mis",
			"Lux_Base_E_tar_aoe_green", "Jinx_Base_W_mis", "Annie_Base_R_cas", "Yasuo_Base_Q3_wind_mis", "Cursor_Moveto"]:
		if LolVfx.has(set_name):
			names.append(set_name)
	var pos: Vector3 = G.player.global_position if G.player != null else Vector3.ZERO
	var tot_cold := 0.0
	var tot_warm := 0.0
	for n in names:
		var t0 := Time.get_ticks_usec()
		var v = LolVfx.spawn(match_ref, n, pos, {})
		var cold := (Time.get_ticks_usec() - t0) / 1000.0
		var warm := 0.0
		for i in 10:
			var t1 := Time.get_ticks_usec()
			var v2 = LolVfx.spawn(match_ref, n, pos, {})
			warm += (Time.get_ticks_usec() - t1) / 1000.0
		warm /= 10.0
		tot_cold += cold
		tot_warm += warm
		print("VFXBENCH %-28s cold=%.2fms warm=%.2fms" % [n, cold, warm])
	print("VFXBENCH TOTAL systems=%d cold=%.1fms warm_avg=%.2fms" % [names.size(), tot_cold, tot_warm / maxf(names.size(), 1)])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
