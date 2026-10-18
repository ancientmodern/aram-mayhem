extends Node
## Prints every champion's items, gold and level every 60 s of match time ("BOTBUILD ..."), to check the bots buy sensible builds:
##   godot --headless --path . --fixed-fps 60 -- --sim --time=720 --seed=3 --harness=res://src/items/tests/bot_builds.gd

var match_ref = null
var main = null
var _next := 60.0


func _process(_dt: float) -> void:
	if match_ref == null or match_ref.time < _next:
		return
	_next += 120.0
	print("BOTBUILD t=%.0f" % match_ref.time)
	for c in match_ref.champions:
		var names := []
		for it in c.items:
			var st = it.get("stacks")
			names.append(it.display_name + ("x%d" % int(st) if st != null and int(st) > 1 else ""))
		print("BOTBUILD   %-12s L%-2d gold=%-5d total=%-6d [%d] %s" % [c.alias, c.level, int(c.gold), int(c.total_gold), c.items.size(), ", ".join(PackedStringArray(names))])
