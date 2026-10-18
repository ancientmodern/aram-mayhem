class_name Item
extends Effect
## An item in a champion's inventory. Stats come from ItemDB; passives/actives override hooks.

var item_id := 0
var cost := 0                 ## total cost
var components: Array = []    ## item ids this is built from
var unique_group := ""        ## e.g. "boots", "hydra" (only one per group)
var active_cd := 0.0          ## seconds (0 = no active)
var active_left := 0.0
var item_tags: Array = []


func on_tick(_u, dt: float) -> void:
	if active_left > 0.0:
		active_left = maxf(0.0, active_left - dt * (1.0 + owner.stats.m("item_haste") / 100.0))


func cooldown_ratio() -> float:
	return active_left / active_cd if active_cd > 0.0 else 0.0


func has_active() -> bool:
	return active_cd > 0.0


## Activate (number keys). Override use_active() in subclasses.
func activate(pos: Vector3, hovered) -> void:
	if active_cd <= 0.0 or active_left > 0.0 or owner.dead:
		return
	if use_active(pos, hovered):
		active_left = active_cd


func use_active(_pos: Vector3, _hovered) -> bool:
	return false


## Bot helper: when to use the active. Return true to fire.
func ai_should_activate(_ctx) -> bool:
	return false


func tooltip() -> String:
	var s := ""
	var keys := stats.keys()
	for k in keys:
		var v: float = stats[k]
		s += ItemDB.stat_line(k, v) + "\n"
	if description != "":
		s += "\n" + description
	return s.strip_edges()


func proc(target, amount: float, type: int, tag: String = "") -> DamageInfo:
	return Combat.deal(owner, target, amount, type, {"is_proc": true, "tag": tag if tag != "" else "item"})


func lvl_lerp(a: float, b: float) -> float:
	return lerpf(a, b, clampf((owner.level - 1) / 17.0, 0.0, 1.0))


func is_melee() -> bool:
	return float(owner.stats.base.get("attack_range", 550.0)) < 300.0
