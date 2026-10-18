class_name Augment
extends Effect
## Base class for ARAM: Mayhem augments. Subclasses implement Effect hooks.
## Registration happens in AugmentDB (src/augments/augment_db.gd).

var rarity := "Silver"            ## Silver / Gold / Prismatic
var power := 2.0                  ## 0..4 general strength for bot scoring (S+=4 ... D=0)
var counter_text := ""


func _init() -> void:
	pass


## Whether this augment should be offered to a champion.
func fits(_c) -> bool:
	return true


## Extra bot preference for a champion (added to power). Use champion tags.
func synergy(_c) -> float:
	return 0.0


## One-time effect when acquired (gold, granting things...). Called after on_attach.
func on_acquire(_c) -> void:
	pass


func hud_counter() -> String:
	return counter_text


# ------------------------------------------------------------------ helpers for subclasses
func m():
	return owner.match_ref if owner != null else null


func now() -> float:
	return owner.match_ref.time if owner != null and owner.match_ref != null else 0.0


func lvl_lerp(a: float, b: float) -> float:
	var l: int = owner.level if owner != null else 1
	return lerpf(a, b, clampf((l - 1) / 17.0, 0.0, 1.0))


func is_melee(c = null) -> bool:
	var u = c if c != null else owner
	return float(u.stats.base.get("attack_range", 550.0)) < 300.0


func has_tag(c, t: String) -> bool:
	return t in AugmentDB.champion_tags(c)


## Adaptive damage type: physical if bonus AD > AP else magic.
func adaptive_type() -> int:
	return G.DmgType.PHYSICAL if owner.stats.bonus_ad > owner.stats.ap else G.DmgType.MAGIC


## Sum of a stat key from every effect on u except `skip` (for stat conversions).
static func sum_other(u, key: String, skip) -> float:
	var t := 0.0
	for e in u.effects.duplicate():
		if e == skip:
			continue
		t += float(e.get_stat_mods().get(key, 0.0))
	return t


static func is_support(c) -> bool:
	var tags := AugmentDB.champion_tags(c)
	return "heal" in tags or "shield" in tags or "support" in tags


## Pick an ability slot for an ability augment: "short" lowest cooldown, "long" highest cooldown.
static func pick_slot(c, mode: String = "short") -> int:
	var best := 0
	var best_v := INF if mode == "short" else -INF
	for i in 3:
		var ab = c.abilities[i]
		if ab == null:
			continue
		var cdv: float = float(ab.cooldowns[0]) if not ab.cooldowns.is_empty() else 10.0
		if (mode == "short" and cdv < best_v) or (mode != "short" and cdv > best_v):
			best_v = cdv
			best = i
	return best


func proc(target, amount: float, type: int, tag: String = "") -> DamageInfo:
	return Combat.deal(owner, target, amount, type, {"is_proc": true, "tag": tag if tag != "" else id, "no_hooks": false})
