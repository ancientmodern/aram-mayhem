extends Node
## [world-ui] Teamfight QA + overlay perf: all 10 champions + two minion waves brawl around the player.
## Prints draw.overlay / proc.overlay (avg ms / worst-frame ms) every 3 s and saves teamfight screenshots.
## tools/preview.sh 300 -- --champ=Ezreal --res=2560x1440 --harness=res://src/ui/world/wui_fight.gd --shotdir=wui_fight

var match_ref = null
var main = null
var shot_dir := "user://wui_fight"
var _frames := 0
var _t := 0.0
var _measuring := false
var _reports := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	process_priority = 1000
	Prof.enabled = true
	G.settings["show_all_damage_numbers"] = "--alltext" in OS.get_cmdline_user_args()
	_run()


func _process(delta: float) -> void:
	Prof.end_frame()
	if not _measuring:
		Prof.acc.clear()
		Prof.peak.clear()
		return
	_frames += 1
	_t += delta
	if _t >= 3.0:
		var fps := _frames / _t
		var acc: Dictionary = Prof.acc.duplicate()
		var pk: Dictionary = Prof.peak.duplicate()
		var parts := []
		var keys := ["draw.overlay", "proc.overlay", "draw.overlay_old", "proc.overlay_old"]
		for k in acc:
			if str(k).begins_with("ov."):
				keys.append(k)
		for k in keys:
			parts.append("%s=%.3f/%.2f" % [k, acc.get(k, 0) / 1000.0 / _frames, pk.get(k, 0) / 1000.0])
		var n_units := 0
		for u in match_ref.units:
			if not u.dead:
				n_units += 1
		print("WUIPERF fps=%.0f units=%d texts=%d %s" % [fps, n_units, match_ref.overlay.ft.texts.size(), " ".join(parts)])
		Prof.report(_frames)
		_frames = 0
		_t = 0.0
		_reports += 1
		_ab_swap()


## --ab: A/B the previous overlay implementation (tools/extracted/_wui_old_overlay.gd) against the current one
## in the same fight, alternating every 3 s window.
var _old: Control = null


func _ab_setup() -> void:
	if not "--ab" in OS.get_cmdline_user_args() or not ResourceLoader.exists("res://tools/extracted/_wui_old_overlay.gd"):
		return
	var ov: Control = match_ref.overlay
	_old = load("res://tools/extracted/_wui_old_overlay.gd").new()
	ov.get_parent().add_child(_old)
	_old.match_ref = match_ref
	_old.rig = ov.rig
	_old.ft = ov.ft
	_old.visible = false
	_old.set_process(false)


func _ab_swap() -> void:
	if _old == null:
		return
	var ov: Control = match_ref.overlay
	var use_old := not _old.visible
	_old.visible = use_old
	_old.set_process(use_old)
	ov.visible = not use_old
	ov.set_process(not use_old)


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, n])
	print("WUI SHOT ", n)


func _run() -> void:
	await _wait(1.0)
	var c: Champion = G.player
	for ch in match_ref.champions:
		if ch.augments_pending > 0:
			match_ref.get_offer(ch)
			match_ref.choose_augment(ch, 0)
	# two extra waves straight away so ~40 minions meet near mid
	match_ref.spawner._spawn_wave()
	Engine.time_scale = 8.0
	# fast-forward until the two waves meet; the clash point is between the closest opposing minions
	var mid := Vector3.ZERO
	for k in 400:
		await _wait(0.1)
		var best := INF
		for a in match_ref.units:
			if a.kind != G.Kind.MINION or a.dead or a.team != 0:
				continue
			for b in match_ref.units:
				if b.kind == G.Kind.MINION and not b.dead and b.team == 1:
					var d := G.flat_dist(a.global_position, b.global_position)
					if d < best:
						best = d
						mid = (a.global_position + b.global_position) * 0.5
		if best < 9.0:
			break
	Engine.time_scale = 1.0
	await _wait(1.0)
	mid = match_ref.nav.nearest_walkable(mid)
	var i := 0
	for ch in match_ref.champions:
		var side := -1.0 if ch.team == c.team else 1.0
		var off := Vector3(side * 3.0 + G.rng.randf_range(-1.5, 1.5), 0, (i % 5 - 2) * 1.6)
		ch.teleport(match_ref.nav.nearest_walkable(mid + off))
		ch.level = 9
		i += 1
	match_ref.camera_rig.snap_to(c.global_position)
	await _wait(0.3)
	c.issue_attack_move(mid + Vector3(3, 0, 0))   # the player joins in (damage numbers)
	await _wait(0.2)
	_ab_setup()
	_measuring = true
	await _wait(1.5)
	await _shot("fight_1")
	await _wait(2.0)
	await _shot("fight_2")
	await _wait(6.0)
	await _shot("fight_3")
	await _wait(3.5)
	if _old != null:
		await _wait(12.0)
	print("WUI DONE")
	get_tree().quit()
