class_name MayhemAura
extends Effect
## Howling Abyss / Mayhem global champion buffs (hidden):
## bonus base HP by level, +15 armor/MR for melee, +10% mana regen, +70 summoner haste.

var melee := false


func _init() -> void:
	id = "mayhem_aura"
	display_name = "Howling Abyss"
	hidden = true


func on_attach(u) -> void:
	melee = float(u.stats.base.get("attack_range", 550.0)) < 300.0


func get_stat_mods() -> Dictionary:
	var lvl: int = owner.level if owner != null else 1
	var d := {"hp": Rules.mayhem_hp_bonus(lvl, melee), "mana_regen%": 0.1, "summoner_haste": Rules.SUMMONER_HASTE}
	if melee:
		d["armor"] = 15.0
		d["mr"] = 15.0
	return d
