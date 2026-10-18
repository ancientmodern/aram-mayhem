extends Node
## Global constants, settings, event bus and references to the running match.
## Autoloaded as `G`.

const U := 0.01 ## League units -> meters

enum Team { ORDER = 0, CHAOS = 1, NEUTRAL = 2 }
enum DmgType { PHYSICAL = 0, MAGIC = 1, TRUE = 2 }
enum Kind { CHAMPION, MINION, TURRET, INHIBITOR, NEXUS, SUMMON, WARD, OTHER }

const TEAM_NAMES := ["Order", "Chaos", "Neutral"]
const COLOR_ALLY := Color(0.25, 0.65, 1.0)
const COLOR_ENEMY := Color(0.95, 0.25, 0.22)
const COLOR_SELF := Color(0.95, 0.85, 0.25)
const COLOR_PHYS := Color(1.0, 0.45, 0.2)
const COLOR_MAGIC := Color(0.55, 0.55, 1.0)
const COLOR_TRUE := Color(1.0, 1.0, 1.0)
const COLOR_HEAL := Color(0.35, 1.0, 0.35)
const COLOR_GOLD := Color(1.0, 0.82, 0.25)
const RARITY_COLORS := {
	"Silver": Color(0.75, 0.80, 0.86),
	"Gold": Color(1.0, 0.78, 0.30),
	"Prismatic": Color(0.85, 0.55, 1.0),
}

# ---------------------------------------------------------------- events
signal unit_spawned(unit)
signal unit_died(unit, killer)
signal champion_killed(victim, killer, assisters)
signal structure_destroyed(structure, killer)
signal level_up(champion, level)
signal gold_earned(champion, amount, source_unit)
signal augment_offer_ready(champion)
signal augment_chosen(champion, augment)
signal announcement(text, sub, color)
signal announcer_event(key, ally_side)   ## voice-line hook: "welcome", "first_blood", "ace", ...
signal match_started
signal match_over(winning_team)

# ---------------------------------------------------------------- runtime
var match: Node = null          ## current Match node
var player: Node = null         ## the human-controlled Champion
var rng := RandomNumberGenerator.new()
var time_scale_target := 1.0

# ---------------------------------------------------------------- settings
var settings := {
	"cast_mode": 0,              # 0 quick cast (press), 1 quick cast with indicator (release), 2 normal (click)
	"camera_locked": true,
	"edge_pan": true,
	"show_all_damage_numbers": false,
	"master_volume": 0.8,
	"sfx_volume": 0.9,
	"music_volume": 0.5,
	"difficulty": 1,             # 0 easy, 1 normal, 2 hard, 3 insane
	"fullscreen": true,
	"show_fps": false,
}

# Configuration for the next match, set by the menus.
var next_match := {
	"player_champion": "Ahri",
	"player_skin": 0,
	"ally_champions": [],
	"enemy_champions": [],
	"seed": 0,
}


signal flow_request(what: String)   ## "menu", "replay", "quit" (handled by Main)

const SETTINGS_PATH := "user://settings.cfg"


func _ready() -> void:
	rng.randomize()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("settings", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("settings", k, settings[k])
	cf.save(SETTINGS_PATH)


func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if settings.get("fullscreen", true):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


var _trace_file: FileAccess = null
var ctx := ""          ## debug: current frame phase (read by the sim watchdog)
var ctx_unit := ""
var ctx2 := ""         ## debug: timer / missile creation site
var ctx3 := ""         ## debug: last damage event
var debug_sites := false
var _ring := []
var _ri := 0


## Debug breadcrumb (sims only): keeps the last 64 operations for the hang watchdog.
func crumb(s: String) -> void:
	if _ring.size() < 64:
		_ring.append(s)
	else:
		_ring[_ri % 64] = s
	_ri += 1


func crumbs() -> Array:
	var out := []
	var n := _ring.size()
	for i in n:
		out.append(_ring[(_ri - n + i) % 64] if n == 64 else _ring[i])
	return out


## "file:line function" of the code that called the caller (debug builds only).
func caller_site(depth: int = 2) -> String:
	var st := get_stack()
	var out := []
	for i in range(depth, mini(depth + 3, st.size())):
		out.append("%s:%d" % [str(st[i].source).get_file(), st[i].line])
	return ",".join(out)
var beat := 0


var _bad_vec_count := 0


## Report a non-finite position handed to a movement primitive (with the GDScript call stack).
func bad_vector(where: String, v: Vector3) -> void:
	_bad_vec_count += 1
	if _bad_vec_count > 20:
		return
	var frames := []
	for f in get_stack().slice(1, 7):
		frames.append("%s:%d %s" % [str(f.source).get_file(), f.line, f.function])
	push_warning("Non-finite vector %s in %s <- %s" % [str(v), where, " <- ".join(frames)])


## Debug tracing to a flushed file (survives a hard hang).
func trace(a = "", b = "", c = "", d = "") -> void:
	if _trace_file == null:
		_trace_file = FileAccess.open("user://trace.log", FileAccess.WRITE)
	_trace_file.store_line("%s %s %s %s" % [str(a), str(b), str(c), str(d)])
	_trace_file.flush()


func _exit_tree() -> void:
	# release static caches before the engine shuts down (avoids a crash on exit)
	Assets._scene_cache.clear()
	Assets._mat_cache.clear()
	Assets._tex_cache.clear()
	Assets._font_cache.clear()
	AugmentDB._impl.clear()
	AugmentDB._catalog.clear()
	LolVfx.clear_cache()
	LolVfx._shaders.clear()
	LolTrail._mats.clear()


func _process(delta: float) -> void:
	# smooth time-scale transitions (slow motion on game end etc.)
	if absf(Engine.time_scale - time_scale_target) > 0.001:
		Engine.time_scale = move_toward(Engine.time_scale, time_scale_target, delta * 2.0)


static func lol(v: float) -> float:
	return v * U


## League world position (x, y, z) -> Godot world position.
static func lol_pos(x: float, y: float, z: float) -> Vector3:
	return Vector3(x * U, y * U, -z * U)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func flat_dist(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


static func flat_dir(from: Vector3, to: Vector3) -> Vector3:
	var d := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var l := d.length()
	return d / l if l > 0.0001 else Vector3.FORWARD


static func enemy_team(team: int) -> int:
	return 1 - team if team < 2 else 2


func is_ally_of_player(team: int) -> bool:
	return player != null and player.team == team


func announce(text: String, sub: String = "", color: Color = Color.WHITE) -> void:
	announcement.emit(text, sub, color)


# ---------------------------------------------------------------- input
func _add_key(action: String, keys: Array, mods: Dictionary = {}) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		ev.ctrl_pressed = mods.get("ctrl", false)
		ev.shift_pressed = mods.get("shift", false)
		ev.alt_pressed = mods.get("alt", false)
		InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_add_key("cast_q", [KEY_Q])
	_add_key("cast_w", [KEY_W])
	_add_key("cast_e", [KEY_E])
	_add_key("cast_r", [KEY_R])
	_add_key("summoner_d", [KEY_D])
	_add_key("summoner_f", [KEY_F])
	_add_key("attack_move", [KEY_A])
	_add_key("stop", [KEY_S])
	_add_key("hold", [KEY_H])
	_add_key("center_camera", [KEY_SPACE])
	_add_key("toggle_camera_lock", [KEY_Y])
	_add_key("shop", [KEY_P])
	_add_key("scoreboard", [KEY_TAB])
	_add_key("augments", [KEY_G])
	_add_key("item_1", [KEY_1])
	_add_key("item_2", [KEY_2])
	_add_key("item_3", [KEY_3])
	_add_key("item_4", [KEY_4])
	_add_key("item_5", [KEY_5])
	_add_key("item_6", [KEY_6])
	_add_key("dance", [KEY_T])
	_add_key("toggle_fps", [KEY_F11])
