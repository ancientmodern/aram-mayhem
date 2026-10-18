extends Node
## [motion] mixer micro-benchmark: microseconds per AnimationPlayer.advance() for every champion /
## minion model, with deterministic on/off.
## tools/check.sh 300 -- --harness=res://src/debug/motion_bench.gd

var main
var match_ref
var _done := false


func _process(_d: float) -> void:
	if _done or match_ref == null or match_ref.time < 0.5:
		return
	_done = true
	for u in match_ref.units:
		if u.anim_player == null or not (u is Champion or u is Minion):
			continue
		var ap: AnimationPlayer = u.anim_player
		var a := ap.get_animation(ap.current_animation) if ap.current_animation != "" else null
		var tracks := a.get_track_count() if a != null else 0
		var res := []
		for det in [true, false]:
			ap.deterministic = det
			var t0 := Time.get_ticks_usec()
			for i in 200:
				ap.advance(1.0 / 120.0)
			res.append((Time.get_ticks_usec() - t0) / 200.0)
		ap.deterministic = true
		var bones: int = u._skel.get_bone_count() if u._skel != null else 0
		print("[bench] %-16s anim=%-14s assigned=%s playing=%s dead=%s tracks=%d bones=%d us/advance det=%.1f nondet=%.1f" % [u.display_name,
			ap.current_animation, ap.assigned_animation, ap.is_playing(), u.dead, tracks, bones, res[0], res[1]])
		# same unit playing its idle loop
		u.play_anim("idle", 1.0, 0.0)
		ap.advance(0.5)
		var t1 := Time.get_ticks_usec()
		for i in 200:
			ap.advance(1.0 / 120.0)
		print("        idle %s: %.1f us/advance" % [ap.current_animation, (Time.get_ticks_usec() - t1) / 200.0])
