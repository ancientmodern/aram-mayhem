extends Node
## [motion] death animation check: kills an enemy champion in mid lane and logs its mixer state
## (screenshots when rendering). tools/preview.sh 120 -- --champ=Ezreal --harness=res://src/debug/motion_death.gd

var main
var match_ref
var _e = null
var _t_kill := -1.0
var _shots := [0.3, 1.0, 2.5]
var dir := "user://motion_death"


func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _process(_d: float) -> void:
	if match_ref == null or G.player == null or match_ref.time < 1.5:
		return
	var p = G.player
	if _e == null:
		for c in match_ref.champions:
			c.controller = null
			if _e == null and c.team != p.team:
				_e = c
		var mid: Vector3 = match_ref.nav.nearest_walkable((p.spawn_point + _e.spawn_point) * 0.5)
		p.teleport(mid)
		_e.teleport(mid + Vector3(2.5, 0, 0))
		_e.acquisition_range = 0.0
		p.acquisition_range = 0.0
		var rig = match_ref.camera_rig
		rig.target = _e
		rig.locked = true
		return
	var ap: AnimationPlayer = _e.anim_player
	if _t_kill < 0.0:
		if match_ref.time < 2.5:
			return
		print("[death] before kill vis=%s alpha=%.2f acc=%.3f cur=%s playing=%s dead=%s" % [_e.visible, _e._alpha,
			_e._anim_acc, ap.current_animation, ap.is_playing(), _e.dead])
		_e.die(p)
		_t_kill = match_ref.time
		return
	var t: float = match_ref.time - _t_kill
	if t < 3.0:
		print("[death] t=%.2f %s top=%s cur=%s pos=%.2f playing=%s vis=%s on=%s acc=%.3f" % [t, _e.display_name, _e._g_top,
			ap.current_animation, ap.current_animation_position if ap.current_animation != "" else -1.0, ap.is_playing(),
			_e.visible, _e._on_screen, _e._anim_acc])
		if not _shots.is_empty() and t >= _shots[0]:
			_shot("death_%.1f" % _shots.pop_front())
	else:
		get_tree().quit()
