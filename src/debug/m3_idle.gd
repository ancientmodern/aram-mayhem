extends Node
## [motion3] idle-fidget check: parks the player's champion and logs idle / idle_var transitions.
## tools/check.sh 6000 -- --champ=Lux --harness=res://src/debug/m3_idle.gd

var main
var match_ref
var _f := 0
var _last := ""
var _t0 := -1.0


func _process(_d: float) -> void:
	_f += 1
	if match_ref == null or G.player == null or _f < 30:
		return
	var u: Unit = G.player
	if _t0 < 0.0:
		_t0 = match_ref.time
		u.controller = null
		match_ref.game_speed = 4.0
	var state := "%s/%s" % [u.cur_anim, u.anim_player.current_animation]
	if state != _last:
		_last = state
		print("[idle] t=%.1f %s hold=%s" % [match_ref.time - _t0, state, u._g_hold])
	if match_ref.time - _t0 > 60.0:
		get_tree().quit()
