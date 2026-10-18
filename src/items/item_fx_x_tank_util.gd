extends RefCounted
## Helpers of the tank item family (item_fx_x_tank.gd).


static var _re_tags: RegEx = null
static var _re_scale: RegEx = null
static var _re_flat: RegEx = null


## Resolved passive text of an item without markup.
static func passive_text(item_id: int) -> String:
	if _re_tags == null:
		_re_tags = RegEx.new()
		_re_tags.compile("<[^>]*>")
	var t: Array = ItemDB.meta(item_id).get("text", [])
	return _re_tags.sub(String(t[2]) if t.size() > 2 else "", " ", true)


## nth "N (+ P% bonus Health)" (or plain "N magic damage") of the passive text as Vector2(N, P/100). The base numbers of
## several items only exist inside the resolved tooltip (their calculation is not part of the data values).
static func health_scaling(item_id: int, nth: int = 0, fallback := Vector2.ZERO) -> Vector2:
	if _re_scale == null:
		_re_scale = RegEx.new()
		_re_scale.compile("(\\d+(?:\\.\\d+)?)\\s*\\(\\+\\s*(\\d+(?:\\.\\d+)?)%\\s*bonus Health\\)")
		_re_flat = RegEx.new()
		_re_flat.compile("(\\d+(?:\\.\\d+)?)\\s*magic damage")
	var s := passive_text(item_id)
	var ms := _re_scale.search_all(s)
	if nth < ms.size():
		return Vector2(float(ms[nth].get_string(1)), float(ms[nth].get_string(2)) / 100.0)
	var mf := _re_flat.search_all(s)
	if nth < mf.size() and ms.is_empty():
		return Vector2(float(mf[nth].get_string(1)), 0.0)
	return fallback


static func owner_bonus_hp(u) -> float:
	return maxf(0.0, u.stats.max_hp - (u.stats.base.base_hp + Stats.growth(u.stats.base.hp_per_level, u.level)))


static func is_structure(u) -> bool:
	return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS


## Enemies whose CENTER is within r of pos (League auras reach the unit's center).
static func enemies_near(m, team: int, pos: Vector3, r: float, champs_only := false) -> Array:
	var out := []
	for e in m.enemies_in_radius(team, pos, r, champs_only):
		if G.flat_dist(e.global_position, pos) <= r:
			out.append(e)
	return out
