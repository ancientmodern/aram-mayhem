extends "res://src/debug/kit_shots_a.gd"
## [motion3] close-up variant of kit_shots_a: the camera follows the player's champion (for weapon / pose checks).
##   tools/preview.sh 200 -- --champ=Lux --harness=res://src/debug/m3_close.gd --shotslots=R --shottimes=0.2,0.4 --shotdist=4.5 --shotdir=NAME


func _cam() -> void:
	m.camera_rig.locked = false
	m.camera_rig.focus = c.global_position + Vector3(0, 0.9, 0)
	m.camera_rig.target_distance = shot_dist
	m.camera_rig.distance = shot_dist
