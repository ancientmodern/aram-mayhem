extends "res://src/debug/kit_shots_a.gd"
## [motion3] cast-recovery timeline: logs the animation state every 0.1 s after casting each slot.
## tools/check.sh 3000 -- --champ=Sona --harness=res://src/debug/m3_cast_probe.gd --shotslots=Q,R


func _shot(_n: String) -> void:
	pass


func _shots(prefix: String) -> void:
	var t := 0.0
	var nxt := 0.0
	while t < 3.2:
		await _frame()
		t += 1.0 / 60.0
		if t >= nxt:
			nxt += 0.1
			var ap: AnimationPlayer = c.anim_player
			print("[cp] %s t=%.2f cur=%s top=%s cur_clip=%s pos=%.2f/%.2f lock=%.2f hold=%s casting=%s chan=%s moving=%s" % [prefix, t, c.cur_anim, c._g_top, ap.current_animation, ap.current_animation_position, ap.current_animation_length, c.anim_lock, c._g_hold, not c.casting.is_empty(), not c.channel.is_empty(), c.moving])
