class_name Relic
extends Node3D
## ARAM health relic (League HowlingAbyssRelicAura_AOE): walking within TriggerRadius (150 u) heals the picker for
## 8% of their missing health / mana at once, then 2.5 s later a pulse over HealingRadius (850 u) heals every allied
## champion in it for MissingHealthRestoreMult of their missing health (0.16; Mayhem/"Kiwi" mode 0.22, see Rules).
## The relic respawns 90 s after the pulse. Visuals are League's own systems (data/vfx/shared.json):
##   idle      ARAMHealthPickup_AOE (floating heart, light beams, ground glow; its ArrivalFlash is the respawn pop)
##   pickup    HA_Health_PickUp on the picker + HA_HealthPickup_AOE_Cast at the pad, sound healthpickup_cast
##   2.5 s     HowlingAbyss_HealthPickup_Redemption_Indicator over the 850 u radius
##   pulse     HowlingAbyss_HealthPickup_Redemption_Heal_AOE at the pad + HA_Health_Hit on each healed ally
## The HA_AP_HealthRelic character itself is a 26-vertex placeholder cube (its old Odin particles are replaced by the
## systems above), so no model is drawn.

const PICKUP_RADIUS := 1.5            ## TriggerRadius 150 u
const MANA_MULT := 0.08               ## ManaRestoreMult
const AOE_SCALE := 1.45               ## [spatial] the Redemption ring art (quad half-extent 685 u, ring at 0.84-0.88)
                                     ## sits at ~590 u; x1.45 puts it on HealingRadius 850 (2.48 drew it at ~1460 u)
const EV_PICKUP := "Play_sfx_Env_Map12_Crepe_healthpickup_cast"

var m = null
var active := false
var respawn_at := 0.0
var lol_fx: LolVfx = null


func setup(p_match, first_spawn: float) -> void:
	m = p_match
	respawn_at = first_spawn
	LolVfx.load_set("shared")


func tick(_dt: float) -> void:
	if not active:
		if m.time >= respawn_at:
			_spawn()
		return
	for c in m.champions:
		if c.dead:
			continue
		if G.flat_dist(c.global_position, global_position) <= PICKUP_RADIUS + c.radius * 0.5:
			_pickup(c)
			return


func _spawn() -> void:
	active = true
	lol_fx = LolVfx.attach(self, "ARAMHealthPickup_AOE", {"loop": true, "face": false})


func _pickup(c) -> void:
	active = false
	respawn_at = INF   # re-armed 90 s after the pulse (it used to keep its old value and respawn at once)
	if lol_fx != null and is_instance_valid(lol_fx):
		lol_fx.stop()
	lol_fx = null
	var team: int = c.team
	var pos := global_position
	_heal(c, Rules.RELIC_PICKUP_HEAL, MANA_MULT)
	LolVfx.attach(c, "HA_Health_PickUp", {})
	LolVfx.spawn(m, "HA_HealthPickup_AOE_Cast", pos, {})
	LolVfx.spawn(m, "HowlingAbyss_HealthPickup_Redemption_Indicator", pos, {"scale": AOE_SCALE, "max_life": Rules.RELIC_BEAM_DELAY + 0.2})
	if m.audio != null:
		m.audio.play(EV_PICKUP, pos)
	m.after(Rules.RELIC_BEAM_DELAY, func():
		LolVfx.spawn(m, "HowlingAbyss_HealthPickup_Redemption_Heal_AOE", pos, {"scale": AOE_SCALE, "max_life": 3.0})
		var r: float = Rules.RELIC_BEAM_RADIUS * G.U
		for a in m.champions:
			if a.dead or a.team != team:
				continue
			if G.flat_dist(a.global_position, pos) <= r:
				_heal(a, Rules.RELIC_BEAM_HEAL, MANA_MULT)
				LolVfx.attach(a, "HA_Health_Hit", {})
		respawn_at = m.time + Rules.RELIC_RESPAWN)


func _heal(c, hp_mult: float, mana_mult: float) -> void:
	Combat.heal(null, c, (c.stats.max_hp - c.hp) * hp_mult)
	if c.stats.uses_mana:
		c.mana = minf(c.stats.max_mana, c.mana + (c.stats.max_mana - c.mana) * mana_mult)
