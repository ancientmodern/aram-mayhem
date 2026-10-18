class_name ShopSfx
extends RefCounted
## League's item-shop sounds (extracted from the game's HUD_Global / ITEMS_Global Wwise banks, see tools/lol/extract_shop_audio.py).
## data/audio/shop.json maps each shop action ("open", "buy_basic", "sell", "undo" ...) to its League event and the WAV variants.
##   ShopSfx.cue("buy_legendary")       -> UI sound (2D, UI bus) through Sfx.ui_file
##   ShopSfx.world(unit, "potion")      -> in-match item cue through GameAudio (3D at the unit), falling back to the UI bus

const DATA := "res://data/audio/shop.json"
static var _actions: Dictionary = {}
static var _events: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DATA):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if d is Dictionary:
		_actions = d.get("actions", {})
		_events = d.get("events", {})


static func event_of(action: String) -> String:
	_load()
	return String(_actions.get(action, ""))


static func files_of(action: String) -> Array:
	_load()
	var ev := event_of(action)
	return _events.get(ev, [])


## Play a shop action's sound (random variant). `min_gap_ms` rate-limits repeats of the same file.
static func cue(action: String, volume_db := 0.0, min_gap_ms := 60) -> void:
	var files := files_of(action)
	if files.is_empty():
		return
	var path: String = files[G.rng.randi() % files.size()]
	Sfx.ui_file(path, volume_db, min_gap_ms)


## An item sound that happens in the world (drinking a potion ...).
static func world(u, action: String, volume_db := 0.0) -> void:
	var ev := event_of(action)
	if u != null and ev != "" and u.match_ref != null and u.match_ref.get("audio") != null and u.match_ref.audio.has(ev):
		u.match_ref.audio.play(ev, u.global_position, volume_db)
		return
	cue(action, volume_db)
