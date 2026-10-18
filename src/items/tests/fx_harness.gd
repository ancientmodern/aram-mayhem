extends Node
## Item behaviour test: equips the player champion with the given items (bypassing the shop), lets the bot-controlled
## champion fight an ordinary match, fires item actives periodically and prints what the items did.
##
##   tools/check.sh 3000 -- --sim --botplayer --time=60 --seed=3 --champ=Jinx \
##        --harness=res://src/items/tests/fx_harness.gd --items=3094,3095 [--level=13] [--fxtime=50]
## Output lines start with "FXTEST".  tools/check.sh also lists every SCRIPT ERROR (there must be none from your item).

var match_ref = null
var main = null
var _spy: Spy = null
var _items: Array = []
var _t := 0.0
var _next_active := 6.0
var _end := 50.0


class Spy extends Effect:
	var dealt := {}          ## tag -> [count, total]
	var taken := {}
	var heals := 0.0
	var shields := 0.0
	var casts := 0
	var attacks := 0
	var on_hits := 0

	func _init() -> void:
		id = "fx_spy"
		hidden = true

	func on_damage_dealt(info) -> void:
		var k: String = ("%s%s" % [info.tag if info.tag != "" else ("attack" if info.is_attack else ("spell" if info.is_spell else "other")), "(proc)" if info.is_proc else ""])
		var e: Array = dealt.get(k, [0, 0.0])
		e[0] += 1
		e[1] += info.final + info.absorbed
		dealt[k] = e

	func on_damage_taken(info) -> void:
		var k: String = info.tag if info.tag != "" else "hit"
		var e: Array = taken.get(k, [0, 0.0])
		e[0] += 1
		e[1] += info.final
		taken[k] = e

	func on_attack_hit(_t, _info) -> void:
		on_hits += 1

	func on_attack_launch(_t) -> void:
		attacks += 1

	func on_ability_cast(_a, _t) -> void:
		casts += 1

	func on_heal_dealt(_t, amount: float) -> void:
		heals += amount

	func on_shield_dealt(_t, amount: float) -> void:
		shields += amount


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--items="):
			for s in a.substr(8).split(","):
				_items.append(int(s))
		elif a.begins_with("--fxtime="):
			_end = float(a.substr(9))
	await get_tree().create_timer(0.3, true, false, true).timeout
	var c: Champion = G.player
	if c == null:
		print("FXTEST no player")
		return
	var lvl := 13
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			lvl = int(a.substr(8))
	while c.level < lvl:
		c.gain_xp(1000.0)
	_spy = Spy.new()
	c.add_effect(_spy)
	for id in _items:
		var it := ItemDB.create(id)
		if it == null:
			print("FXTEST unknown item ", id)
			continue
		c.add_item(it)
		print("FXTEST equipped %d %s (%s) active_cd=%.1f" % [id, it.display_name, it.get_script().resource_path.get_file(), it.active_cd])
	c.recompute_stats()
	print("FXTEST stats ad=%.0f ap=%.0f hp=%.0f armor=%.0f mr=%.0f as=%.2f crit=%.2f ms=%.0f ah=%.0f" % [c.stats.ad, c.stats.ap, c.stats.max_hp, c.stats.armor, c.stats.mr, c.stats.attack_speed, c.stats.crit_chance, c.stats.move_speed, c.stats.ability_haste])


func _process(dt: float) -> void:
	var c: Champion = G.player
	if c == null or _spy == null:
		return
	_t += dt
	if _t >= _next_active:
		_next_active += 6.0
		for it in c.items:
			if it.has_method("activate") and it.has_active():
				it.activate(c.global_position + Vector3(2, 0, 0), null)
	if _t >= _end:
		_report(c)
		_spy = null
		get_tree().quit()


func _report(c: Champion) -> void:
	print("FXTEST === report after %.0fs: attacks=%d on_hits=%d casts=%d heals=%.0f shields=%.0f" % [_t, _spy.attacks, _spy.on_hits, _spy.casts, _spy.heals, _spy.shields])
	for k in _spy.dealt:
		print("FXTEST dealt  %-28s n=%-4d total=%.0f" % [k, _spy.dealt[k][0], _spy.dealt[k][1]])
	for k in _spy.taken:
		print("FXTEST taken  %-28s n=%-4d total=%.0f" % [k, _spy.taken[k][0], _spy.taken[k][1]])
	for it in c.items:
		print("FXTEST item %s: active_left=%.1f stacks=%s" % [it.display_name, it.active_left, str(it.get("stacks"))])
