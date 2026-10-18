extends Node
## [env3] hexgate / relic visual + behaviour harness.
## tools/preview.sh 120 -- --champ=Ezreal --harness=res://src/env/hexgate_test.gd --hextest=use --hexlog --shotdir=hex_use
## Plans: use (player walks into the Order gate: idle, click, channel, travel, arrival, cooldown ring),
##        interrupt (damage during the channel), enemy (Chaos champion uses the Order gate), exitswap (outer turret
##        falls: exit moves to the inhibitor turret), idle (all gates + relics, close shots)

var match_ref = null
var main = null
var _t := 0.0
var _steps: Array = []
var _dir := "user://hex_shots"
var _plan := "use"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hextest="):
			_plan = a.substr(10)
		elif a.begins_with("--shotdir="):
			_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	G.settings.edge_pan = false
	call_deferred("_build")


func _at(time: float, fn: Callable) -> void:
	_steps.append([time, fn])


func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [_dir, nm])
	print("SHOT ", ProjectSettings.globalize_path(_dir), "/", nm, ".png fps=", Engine.get_frames_per_second())


func _cam(p: Vector3, dist: float = 11.0) -> void:
	var rig = match_ref.camera_rig
	rig.target = null
	rig.locked = false
	rig.focus = p
	rig.snap_to(p)
	rig.target_distance = dist
	rig.distance = dist


func _build() -> void:
	var m = match_ref
	var net: HexgateNet = m.hexgate_net
	var pl = G.player
	var entry = net.entries[0]
	var t := 1.0
	match _plan:
		"idle":
			var i := 0
			for g in net.gates:
				var gg = g
				_at(t, func(): _cam(gg.pos, 9.0))
				_at(t + 1.2, _shot.bind("gate_%d_%s_t%d" % [i, gg.kind, gg.team]))
				i += 1
				t += 1.6
			for r in m.relics:
				var rr = r
				_at(t, func(): _cam(rr.global_position, 9.0))
				_at(t + 1.2, _shot.bind("relic_%d" % i))
				i += 1
				t += 1.6
		"fx":
			# each gate system alone on the Order entry gate (--hexfx=A,B to choose)
			var names := ["HA_Hexgate_Base_Portal", "HA_Hexgate_Base_PortalOpen", "HA_Hexgate_Base_OpenLoop", "HA_Hexgate_Base_PortalSpawn",
				"HA_Hexgate_Base_PortalOutgoing", "HA_Hexgate_Base_Outgoing_Arrow", "HA_Hexgate_Base_ClosePortal", "HA_Hexgate_Base_Timer_Ring_10s",
				"HA_Hexgate_Base_PortalIncoming", "HA_Hexgate_Base_PortalGroundLoop"]
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--hexfx="):
					names = a.substr(8).split(",")
			t = 16.0   # bots have left through the gate by now
			_at(t, func():
				pl.teleport(entry.pos + entry.fwd * 14.0)
				_cam(entry.pos, 6.5))
			var fi := 0
			for nm in names:
				var nn: String = nm
				var idx := fi
				_at(t + 0.5 + fi * 3.0, func():
					print("FX ", nn, " has=", LolVfx.has(nn))
					var yaw := 0.0
					for a in OS.get_cmdline_user_args():
						if a.begins_with("--hexyaw="):
							yaw = deg_to_rad(float(a.substr(9)))
					LolVfx.spawn(m, nn, entry.pos, {"dir": entry.fwd.rotated(Vector3.UP, yaw), "loop": nn.contains("Open") or nn.contains("Arrow")}))
				_at(t + 1.6 + fi * 3.0, _shot.bind("fx_%02d_%s" % [idx, nn.trim_prefix("HA_Hexgate_")]))
				fi += 1
		"relic":
			# the Order inner relic: spawn, idle, pickup, delayed AoE heal pulse, respawn
			var rl = m.relics[0]
			for r in m.relics:
				if r.global_position.distance_to(Vector3(46.0, 0, -35.0)) < 12.0:
					rl = r
			print("RELIC at ", rl.global_position)
			_at(t, func():
				for r in m.relics:
					r.respawn_at = 0.0
				pl.teleport(rl.global_position + Vector3(4.0, 0, 0))
				pl.hp = pl.stats.max_hp * 0.4
				_cam(rl.global_position, 9.0))
			_at(t + 1.0, func(): _shot("r0_idle_far"))
			_at(t + 1.1, func(): _cam(rl.global_position, 5.5))
			_at(t + 2.0, func(): _shot("r1_idle_near"))
			_at(t + 2.4, func(): _shot("r1b_idle_near"))
			_at(t + 2.6, func():
				_cam(rl.global_position, 9.0)
				pl.issue_move(rl.global_position))
			for dt in [0.9, 1.3, 1.8, 2.6, 3.2, 3.8, 4.4]:
				_at(t + 2.6 + dt, _shot.bind("r2_pick_%02d" % int(dt * 10)))
			_at(t + 2.6 + 4.0, func():
				_cam(rl.global_position, 9.0)
				print("RELIC hp=", pl.hp / pl.stats.max_hp, " active=", rl.active))
			_at(t + 2.6 + 6.0, func(): print("RELIC hp after pulse=", pl.hp / pl.stats.max_hp))
		"use":
			_at(t, func():
				pl.teleport(entry.pos + entry.fwd * 6.0)
				_cam(entry.pos, 12.0))
			_at(t + 1.0, func(): _shot("u0_idle"))
			_at(t + 1.2, func():
				pl.issue_move(entry.pos)
				m.camera_rig.target = pl
				m.camera_rig.locked = true)
			var k := 0
			for dt in [0.6, 1.4, 2.1, 2.6, 3.2, 4.2, 5.2, 6.2, 7.2, 8.2, 9.5]:
				_at(t + 1.2 + dt, _shot.bind("u%d_%03d" % [k + 1, int(dt * 10)]))
				k += 1
			_at(t + 14.0, func():
				pl.issue_move(entry.pos)
				print("HEXTEST retry cd=", net.cooldown_left(pl)))
			_at(t + 15.0, func(): _shot("u_cooldown"))
		"interrupt":
			_at(t, func():
				pl.teleport(entry.pos + entry.fwd * 5.0)
				_cam(entry.pos, 12.0))
			_at(t + 1.0, func():
				pl.issue_move(entry.pos)
				m.camera_rig.locked = true)
			_at(t + 2.9, func():
				print("HEXTEST channel=", not pl.channel.is_empty(), " pos=", pl.global_position)
				_shot("i_channel"))
			_at(t + 3.2, func():
				Combat.deal(null, pl, 40.0, G.DmgType.TRUE, {}))
			_at(t + 3.6, func(): _shot("i_after_hit"))
			_at(t + 4.0, func():
				print("HEXTEST after interrupt channel=", not pl.channel.is_empty(), " lockout; pos=", pl.global_position)
				pl.issue_move(entry.pos))
			_at(t + 7.0, func(): _shot("i_retry"))
		"enemy":
			var foe = null
			for c in m.champions:
				if c.team == 1:
					foe = c
					break
			_at(t, func():
				foe.teleport(entry.pos + entry.fwd * 4.0)
				pl.teleport(entry.pos + entry.fwd * 6.0)
				_cam(entry.pos, 12.0))
			_at(t + 1.0, func():
				foe.issue_move(entry.pos)
				# the engine only auto-handles bots/human; an enemy champion uses it through the same click path
				net._pending[foe] = {"gate": entry, "goal": entry.pos, "t": m.time})
			for dt in [1.5, 3.0, 5.0, 8.0]:
				_at(t + 1.0 + dt, _shot.bind("e_%d" % int(dt * 10)))
		"exitswap":
			var outer = m.outer_turrets[0]
			var ex0 = net.exits[0][0]
			var ex1 = net.exits[0][1]
			_at(t, func(): _cam(ex0.pos, 12.0))
			_at(t + 1.2, func(): _shot("x0_outer_exit"))
			_at(t + 1.5, func(): outer.die(null))
			_at(t + 2.5, func(): _shot("x1_swap_a"))
			_at(t + 3.5, func(): _shot("x2_swap_b"))
			_at(t + 4.0, func(): _cam(ex1.pos, 12.0))
			_at(t + 5.5, func(): _shot("x3_inhib_exit"))
	_at(t + 60.0, func(): get_tree().quit())


func _process(dt: float) -> void:
	_t += dt
	var i := 0
	while i < _steps.size():
		if _t >= _steps[i][0]:
			var fn: Callable = _steps[i][1]
			_steps.remove_at(i)
			fn.call()
		else:
			i += 1
