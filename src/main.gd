extends Node
## Entry point and game flow: main menu -> champion select -> loading -> match -> end screen.
## Command line (after `--`): --champ=<Alias> starts a match directly, --sim runs the QA harness,
## --seed=<n> fixes the RNG, --menu forces the menus.

var current: Node = null          ## running Match
var ui_layer: CanvasLayer
var screen: Control = null        ## current menu screen


func _ready() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	G.flow_request.connect(_on_flow)
	var args := OS.get_cmdline_user_args()
	if not ("--uitest" in args or "--windowed" in args):
		G.apply_window_mode()
	Sfx.apply_volumes()
	var direct := false
	for a in args:
		if a.begins_with("--champ="):
			G.next_match.player_champion = a.substr(8)
			direct = true
		elif a.begins_with("--trace="):
			G.set_meta("trace_from", float(a.substr(8)))
		elif a.begins_with("--seed="):
			G.rng.seed = int(a.substr(7))
			seed(int(a.substr(7)))
	if "--sim" in args:
		direct = true
	if "--menu" in args or "--uitest" in args:
		direct = false
	if direct:
		start_match(G.next_match)
		if "--sim" in args:
			var mon := SimMonitor.new()
			mon.match_ref = current
			add_child(mon)
	else:
		show_menu()
	for a in args:
		if a.begins_with("--vfxtest"):
			add_child(VfxTest.new())
	if "--ctrltest" in args:
		var ct := ControlTest.new()
		add_child(ct)
	if "--uitest" in args:
		var ut := UITest.new()
		ut.main = self
		add_child(ut)


# ===================================================================== screens
func _set_screen(s: Control) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = s
	if s != null:
		ui_layer.add_child(s)


func _end_match() -> void:
	if current != null:
		current.queue_free()
		current = null
	G.player = null
	G.match = null
	G.time_scale_target = 1.0
	Engine.time_scale = 1.0


func show_menu() -> void:
	_end_match()
	var m := MainMenu.new()
	m.action.connect(_on_menu_action)
	_set_screen(m)


func _on_menu_action(id: String) -> void:
	match id:
		"play":
			show_champ_select()
		"quit":
			get_tree().quit()


func show_champ_select() -> void:
	var cs := ChampSelect.new()
	cs.action.connect(_on_champ_select_action.bind(cs))
	_set_screen(cs)


func _on_champ_select_action(id: String, cs: ChampSelect) -> void:
	match id:
		"locked":
			show_loading(cs.cfg)
		"back":
			show_menu()


func show_loading(cfg: Dictionary) -> void:
	_end_match()
	var ls := LoadingScreen.new()
	ls.cfg = cfg
	ls.action.connect(_on_loading_action.bind(ls, cfg))
	_set_screen(ls)


func _on_loading_action(id: String, ls: LoadingScreen, cfg: Dictionary) -> void:
	if id == "loaded":
		start_match(cfg)
		ls.finish()
		screen = null


func start_match(cfg: Dictionary) -> void:
	_end_match()
	if cfg.get("seed", 0) != 0:
		G.rng.seed = int(cfg.seed)
	var m := Match.new()
	m.name = "Match"
	add_child(m)
	current = m
	m.start(cfg)
	if G.has_meta("trace_from"):
		m.trace_from = G.get_meta("trace_from")
	Sfx.music("", 1.0)


func _on_flow(what: String) -> void:
	match what:
		"menu":
			show_menu()
		"replay":
			# like ARAM: back to a fresh champion select with new random champions
			_end_match()
			show_champ_select()
		"quit":
			get_tree().quit()
