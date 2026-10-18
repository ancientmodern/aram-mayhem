class_name Stats
extends RefCounted
## Stat calculation for a unit: base stats + per-level growth + modifiers from
## effects (items, augments, buffs). Values follow League conventions
## (ranges / speeds in League units; converted by users with G.U).
##
## Modifier keys (flat unless noted):
##  hp hp% hp_regen hp_regen% mana mana_regen mana_regen% ad ad% bonus_ad% ap ap%
##  armor armor% mr mr% as crit crit_dmg ms ms% range ah ult_ah basic_ah summoner_haste
##  lifesteal omnivamp spell_vamp armor_pen% lethality magic_pen magic_pen% tenacity slow_resist
##  heal_power size dmg_amp dmg_reduction as_cap adaptive base_ad% gold_gen

var unit = null
var base := {
	"base_hp": 600.0, "hp_per_level": 100.0, "base_hp_regen": 1.5, "hp_regen_per_level": 0.1,
	"mana_base": 300.0, "mana_per_level": 30.0, "mana_regen": 1.5, "mana_regen_per_level": 0.1,
	"base_ad": 60.0, "ad_per_level": 3.0, "base_armor": 30.0, "armor_per_level": 4.0,
	"base_mr": 30.0, "mr_per_level": 1.5, "base_ms": 330.0, "attack_range": 550.0,
	"attack_speed": 0.65, "attack_speed_ratio": 0.65, "attack_speed_per_level": 2.5,
}
var level := 1
var uses_mana := true

# final cached values
var max_hp := 0.0
var hp_regen := 0.0
var max_mana := 0.0
var mana_regen := 0.0
var base_ad := 0.0
var bonus_ad := 0.0
var ad := 0.0
var ap := 0.0
var base_armor := 0.0
var bonus_armor := 0.0
var armor := 0.0
var base_mr := 0.0
var bonus_mr := 0.0
var mr := 0.0
var attack_speed := 0.0
var bonus_as := 0.0          ## bonus attack speed fraction (incl. level growth)
var as_cap := 5.0
var crit_chance := 0.0
var crit_damage := 2.0
var move_speed := 0.0
var attack_range := 0.0
var ability_haste := 0.0
var ult_haste := 0.0
var basic_haste := 0.0
var summoner_haste := 0.0
var lifesteal := 0.0
var omnivamp := 0.0
var spell_vamp := 0.0
var armor_pen_pct := 0.0
var lethality := 0.0
var magic_pen := 0.0
var magic_pen_pct := 0.0
var tenacity := 0.0
var slow_resist := 0.0
var heal_power := 0.0
var size := 1.0
var dmg_amp := 0.0
var dmg_reduction := 0.0
var gold_gen := 0.0

var mods := {}               ## summed modifiers (last computation)
var slow := 0.0              ## strongest active slow (0..1), set by unit from buffs
var ms_override := -1.0      ## forced move speed (e.g. during charm), <0 = none

var _dirty := true


func _init(p_unit = null) -> void:
	unit = p_unit


func set_base(data: Dictionary) -> void:
	for k in data:
		base[k] = data[k]
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


static func growth(per_level: float, lvl: int) -> float:
	var n := float(lvl - 1)
	return per_level * n * (0.7025 + 0.0175 * n)


func m(key: String, default: float = 0.0) -> float:
	return mods.get(key, default)


func recompute(sources: Array) -> void:
	mods.clear()
	for s in sources:
		if s == null:
			continue
		var d: Dictionary = s.get_stat_mods()
		for k in d:
			mods[k] = mods.get(k, 0.0) + d[k]
	var L := level
	# health / mana
	var hp_base: float = base.base_hp + growth(base.hp_per_level, L)
	max_hp = (hp_base + m("hp")) * (1.0 + m("hp%"))
	hp_regen = (base.base_hp_regen + growth(base.hp_regen_per_level, L)) * (1.0 + m("hp_regen%")) + m("hp_regen")
	if uses_mana:
		max_mana = base.mana_base + growth(base.mana_per_level, L) + m("mana")
		mana_regen = (base.mana_regen + growth(base.mana_regen_per_level, L)) * (1.0 + m("mana_regen%")) + m("mana_regen")
	else:
		max_mana = 0.0
		mana_regen = 0.0
	# offense
	base_ad = (base.base_ad + growth(base.ad_per_level, L)) * (1.0 + m("base_ad%"))
	var adaptive := m("adaptive")
	var raw_bonus_ad := m("ad")
	var raw_ap := m("ap")
	var raw_crit := m("crit")
	if raw_crit > 1.0:
		# Mayhem: each 1% crit above 100% -> 0.45 bonus AD or 0.75 AP (adaptive)
		var over := (raw_crit - 1.0) * 100.0
		if raw_bonus_ad >= raw_ap:
			raw_bonus_ad += over * 0.45
		else:
			raw_ap += over * 0.75
	if adaptive != 0.0:
		# adaptive force -> AD if the unit has more bonus AD than AP, else AP
		if raw_bonus_ad > raw_ap:
			raw_bonus_ad += adaptive * 0.6
		else:
			raw_ap += adaptive
	bonus_ad = raw_bonus_ad * (1.0 + m("bonus_ad%"))
	ad = (base_ad + bonus_ad) * (1.0 + m("ad%"))
	bonus_ad = ad - base_ad
	ap = maxf(0.0, raw_ap * (1.0 + m("ap%")))
	# defense
	base_armor = base.base_armor + growth(base.armor_per_level, L)
	bonus_armor = m("armor") + base_armor * m("base_armor%")
	armor = (base_armor + bonus_armor) * (1.0 + m("armor%"))
	bonus_armor = armor - base_armor
	base_mr = base.base_mr + growth(base.mr_per_level, L)
	bonus_mr = m("mr") + base_mr * m("base_mr%")
	mr = (base_mr + bonus_mr) * (1.0 + m("mr%"))
	bonus_mr = mr - base_mr
	# attack speed: base + ratio * bonus%
	bonus_as = growth(base.attack_speed_per_level, L) / 100.0 + m("as")
	as_cap = Rules.AS_CAP + m("as_cap")
	attack_speed = clampf(base.attack_speed + base.attack_speed_ratio * bonus_as, 0.2, as_cap)
	crit_chance = clampf(raw_crit, 0.0, 1.0)
	crit_damage = Rules.CRIT_DAMAGE + m("crit_dmg")
	attack_range = base.attack_range + m("range")
	ability_haste = m("ah")
	ult_haste = m("ult_ah")
	basic_haste = m("basic_ah")
	summoner_haste = m("summoner_haste")
	lifesteal = m("lifesteal")
	omnivamp = m("omnivamp")
	spell_vamp = m("spell_vamp")
	armor_pen_pct = clampf(m("armor_pen%"), 0.0, 1.0)
	lethality = m("lethality")
	magic_pen = m("magic_pen")
	magic_pen_pct = clampf(m("magic_pen%"), 0.0, 1.0)
	tenacity = clampf(m("tenacity"), 0.0, 0.9)
	slow_resist = clampf(m("slow_resist"), 0.0, 1.0)
	heal_power = m("heal_power")
	size = maxf(0.25, 1.0 + m("size"))
	dmg_amp = m("dmg_amp")
	dmg_reduction = clampf(m("dmg_reduction"), -2.0, 0.9)
	gold_gen = m("gold_gen")
	_compute_ms()
	_dirty = false


func _compute_ms() -> void:
	if ms_override >= 0.0:
		move_speed = ms_override
		return
	var raw: float = (base.base_ms + m("ms")) * (1.0 + m("ms%"))
	raw *= 1.0 - clampf(slow * (1.0 - slow_resist), 0.0, 0.99)
	# League soft caps
	if raw > 490.0:
		raw = raw * 0.5 + 230.0
	elif raw > 415.0:
		raw = raw * 0.8 + 83.0
	elif raw < 220.0:
		raw = raw * 0.5 + 110.0
	move_speed = maxf(raw, 110.0)


## Cooldown after ability haste.
func cooldown(base_cd: float, is_ult: bool = false, is_basic: bool = true) -> float:
	var ah := ability_haste + (ult_haste if is_ult else (basic_haste if is_basic else 0.0))
	return base_cd * 100.0 / (100.0 + maxf(ah, -50.0))


func attack_period() -> float:
	return 1.0 / maxf(attack_speed, 0.05)
