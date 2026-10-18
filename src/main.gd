extends Node
## Entry point: menus -> champion select -> match.

var current: Node = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--champ="):
			G.next_match.player_champion = a.substr(8)
		elif a.begins_with("--seed="):
			G.rng.seed = int(a.substr(7))
	start_match(G.next_match)
	if "--sim" in args:
		var mon := SimMonitor.new()
		mon.match_ref = current
		add_child(mon)


func start_match(cfg: Dictionary) -> void:
	if current != null:
		current.queue_free()
	var m := Match.new()
	m.name = "Match"
	add_child(m)
	current = m
	m.start(cfg)
