class_name Effect
extends RefCounted
## Base class for anything that hooks into a unit's combat events:
## items, augments, champion passives, buffs. Override what you need.

var id := ""
var display_name := ""
var description := ""
var icon: Texture2D = null
var owner = null            ## Unit this effect is attached to
var source = null           ## Unit that created it (may equal owner)
var stats := {}             ## static stat modifiers (see Stats)
var tags := []
var hidden := false         ## don't show in UI
var removed := false
var priority := 0           ## dispatch order (lower first)


func get_stat_mods() -> Dictionary:
	return stats


## Mark the owner's stats dirty (call after changing `stats` or dynamic values).
func refresh_stats() -> void:
	if owner != null:
		owner.stats.mark_dirty()


# ------------------------------------------------------------- lifecycle
func on_attach(_unit) -> void:
	pass


func on_detach(_unit) -> void:
	pass


func on_tick(_unit, _dt: float) -> void:
	pass


# ------------------------------------------------------------- combat hooks
## Before mitigation. info.amount may be modified. Called on the SOURCE's effects.
func on_pre_damage_dealt(_info) -> void:
	pass


## Before mitigation. Called on the TARGET's effects.
func on_pre_damage_taken(_info) -> void:
	pass


## After damage is applied (info.final set). Source side.
func on_damage_dealt(_info) -> void:
	pass


## After damage is applied. Target side.
func on_damage_taken(_info) -> void:
	pass


## A basic attack finished its windup and was launched at target.
func on_attack_launch(_target) -> void:
	pass


## Basic attack landed (on-hit). `info` is the attack's DamageInfo (already applied).
func on_attack_hit(_target, _info) -> void:
	pass


## The owner cast an ability (after windup, when it takes effect).
func on_ability_cast(_ability, _target_info) -> void:
	pass


## The owner killed something.
func on_kill(_victim) -> void:
	pass


## The owner got a kill or assist on an enemy champion.
func on_takedown(_victim) -> void:
	pass


## The owner died.
func on_death(_killer) -> void:
	pass


func on_respawn() -> void:
	pass


func on_level_up(_level: int) -> void:
	pass


## The owner healed `target` (could be self) for amount.
func on_heal_dealt(_target, _amount: float) -> void:
	pass


## The owner shielded `target` for amount.
func on_shield_dealt(_target, _amount: float) -> void:
	pass


## The owner received a shield.
func on_shield_received(_amount: float) -> void:
	pass


## The owner applied crowd control (buff with cc flags) to target.
func on_cc_applied(_target, _buff) -> void:
	pass


## The owner dashed/blinked.
func on_dash(_from: Vector3, _to: Vector3) -> void:
	pass


## The owner used a summoner spell.
func on_summoner_cast(_spell) -> void:
	pass


## Modify the cooldown about to be applied to an ability (return new value).
func modify_cooldown(_ability, cd: float) -> float:
	return cd


## Modify incoming healing to the owner (return new value).
func modify_heal_received(amount: float, _healer) -> float:
	return amount


## Modify an outgoing heal/shield amount from the owner (return new value).
func modify_heal_shield_dealt(amount: float, _target, _is_shield: bool) -> float:
	return amount


## Return true to prevent death (e.g. revive / guardian angel style effects).
func prevent_death(_info) -> bool:
	return false


func tooltip() -> String:
	return description
