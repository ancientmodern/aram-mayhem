class_name MayhemAura
extends Effect
## Howling Abyss / Mayhem global champion buffs (hidden):
## bonus base HP by level, +15 armor/MR for melee, +10% mana regen, +70 summoner haste.
## [kits2] Also League's per-champion ARAM balance modifiers (see ARAM_BALANCE below).

var melee := false
var bal := {}


## League ARAM per-champion balance modifiers for our roster, from the wiki's ARAM page / Module:ChampionData
## ("aram" tables): dealt = damage dealt, taken = damage received, heal = healing done, shield = shielding done,
## total_as = total attack speed. Champions not listed (Ezreal, Malphite, Master Yi, Sona) have none; their
## ability-specific ARAM changes (Sona, Veigar, Lux, Yasuo, Garen) live in their kits.
const ARAM_BALANCE := {
	"Ahri": {"heal": 0.9},
	"Annie": {"dealt": 0.95, "taken": 1.05, "shield": 0.9},
	"Darius": {"dealt": 1.05},
	"Garen": {"taken": 0.95},
	"Jinx": {"dealt": 0.9, "taken": 1.05},
	"Leona": {"dealt": 0.95, "taken": 1.05},
	"Lux": {"dealt": 0.9, "taken": 1.1, "shield": 0.9},
	"MissFortune": {"dealt": 0.95, "taken": 1.05},
	"Veigar": {"dealt": 0.93, "taken": 1.1},
	"Yasuo": {"total_as": 1.025},
}


func _init() -> void:
	id = "mayhem_aura"
	display_name = "Howling Abyss"
	hidden = true


func on_attach(u) -> void:
	melee = float(u.stats.base.get("attack_range", 550.0)) < 300.0
	bal = ARAM_BALANCE.get(str(u.get("alias")), {})


func get_stat_mods() -> Dictionary:
	var lvl: int = owner.level if owner != null else 1
	# classic ARAM: only the global +70 summoner haste; the HP/resist/mana bonuses are Mayhem-only
	var d := {"summoner_haste": Rules.SUMMONER_HASTE}
	# [numbers] wiki ARAM, Howling Abyss aura: +70 summoner spell haste, +0.1% max mana per second, melee champions +15 bonus
	# magic resist (the HP / armor / mana-regen% bonuses below are Mayhem-only)
	if owner != null and owner.stats.uses_mana:
		d["mana_regen"] = owner.stats.max_mana * 0.001
	if melee:
		d["mr"] = 15.0
	if Rules.MAYHEM_MODE:
		d["hp"] = Rules.mayhem_hp_bonus(lvl, melee)
		d["mana_regen%"] = 0.1
		if melee:
			d["armor"] = 15.0
	if bal.has("total_as"):
		# [numbers] League ARAM "total attack speed +x%": a multiplier on the whole attack speed (Stats "as_total%"); it used
		# to be folded into bonus AS, which under-counted it once the champion had attack speed items
		d["as_total%"] = float(bal.total_as) - 1.0
	return d


func on_pre_damage_dealt(info) -> void:
	if bal.has("dealt"):
		info.mult *= float(bal.dealt)


func on_pre_damage_taken(info) -> void:
	if bal.has("taken"):
		info.mult *= float(bal.taken)


func modify_heal_shield_dealt(amount: float, _target, is_shield: bool) -> float:
	var k := "shield" if is_shield else "heal"
	if bal.has(k):
		return amount * float(bal[k])
	return amount
