class_name Relic
extends Node3D
## ARAM health relic: pickup heal + delayed area heal beam, respawns.

var m = null
var active := false
var respawn_at := 0.0
var model: Node3D = null
var glow: VfxNode = null
const PICKUP_RADIUS := 1.1


func setup(p_match, first_spawn: float) -> void:
	m = p_match
	respawn_at = first_spawn


func tick(_dt: float) -> void:
	if not active:
		if m.time >= respawn_at:
			_spawn()
		return
	for c in m.champions:
		if c.dead:
			continue
		if G.flat_dist(c.global_position, global_position) <= PICKUP_RADIUS + c.radius:
			_pickup(c)
			return


var lol_fx: LolVfx = null


func _spawn() -> void:
	active = true
	# League's ARAM health pickup effect (floating health icon, glow, light beams)
	LolVfx.load_set("shared")
	lol_fx = LolVfx.attach(self, "ARAMHealthPickup_AOE", {"loop": true})
	if lol_fx != null:
		if model != null:
			model.visible = false
		return
	if model == null:
		model = Assets.unit_model("HA_AP_HealthRelic", 0)
		if model == null:
			model = Vfx.sprite(Color(0.4, 1.0, 0.5), 0.8)
		add_child(model)
	model.visible = true
	model.scale = Vector3.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3.ONE, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	glow = VfxNode.new()
	add_child(glow)
	glow.add_child(Vfx.sprite(Color(0.3, 1.0, 0.45), 1.6, 1.2))
	glow.position.y = 0.6
	var bob := glow.create_tween().set_loops()
	bob.tween_property(glow, "position:y", 0.9, 0.9).set_trans(Tween.TRANS_SINE)
	bob.tween_property(glow, "position:y", 0.6, 0.9).set_trans(Tween.TRANS_SINE)


func _pickup(c) -> void:
	active = false
	if lol_fx != null and is_instance_valid(lol_fx):
		lol_fx.stop()
		lol_fx = null
	if model != null:
		model.visible = false
	if glow != null:
		glow.queue_free()
		glow = null
	var team: int = c.team
	Combat.heal(null, c, (c.stats.max_hp - c.hp) * Rules.RELIC_PICKUP_HEAL)
	c.mana = minf(c.stats.max_mana, c.mana + (c.stats.max_mana - c.mana) * Rules.RELIC_PICKUP_HEAL)
	var pos := global_position
	var circle := Vfx.ground_circle(m, pos, Rules.RELIC_BEAM_RADIUS * G.U, Color(0.3, 1.0, 0.4, 0.8), Rules.RELIC_BEAM_DELAY + 0.3, 0.12)
	m.after(Rules.RELIC_BEAM_DELAY, func():
		Vfx.burst(m, pos, Color(0.35, 1.0, 0.45), 2.5, {"sparks": 40})
		Vfx.beam(m, pos + Vector3(0, 12, 0), pos, Color(0.4, 1.0, 0.5), 1.4, 0.5)
		for a in m.champions:
			if a.dead or a.team != team:
				continue
			if G.flat_dist(a.global_position, pos) <= Rules.RELIC_BEAM_RADIUS * G.U:
				Combat.heal(null, a, (a.stats.max_hp - a.hp) * Rules.RELIC_BEAM_HEAL)
				a.mana = minf(a.stats.max_mana, a.mana + (a.stats.max_mana - a.mana) * Rules.RELIC_BEAM_HEAL)
				Vfx.rising(a, Color(0.35, 1.0, 0.45), 0.6, 25)
		respawn_at = m.time + Rules.RELIC_RESPAWN)
