class_name ChampionDB
extends RefCounted
## Loads champion data (extracted from the game) and creates kits.

const ROSTER := ["Ahri", "Garen", "Darius", "Yasuo", "MasterYi", "Malphite", "Leona", "Lux", "Jinx",
		"Ezreal", "MissFortune", "Annie", "Sona", "Veigar"]

static var _game := {}
static var _client := {}
static var _skins := {}


static func _load_json(path: String):
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func game_data(alias: String) -> Dictionary:
	if not _game.has(alias):
		var d = _load_json("res://data/champions/%s_game.json" % alias.to_lower())
		_game[alias] = d if d != null else {}
	return _game[alias]


static func client_data(alias: String) -> Dictionary:
	if not _client.has(alias):
		var d = _load_json("res://data/champions/%s_client.json" % alias.to_lower())
		_client[alias] = d if d != null else {}
	return _client[alias]


static func skins(alias: String) -> Array:
	if not _skins.has(alias):
		var d = _load_json("res://data/champions/%s_skins.json" % alias.to_lower())
		_skins[alias] = d if d != null else []
	return _skins[alias]


static func available_skins(alias: String) -> Array:
	## skins that have a converted model on disk
	var out := []
	for s in skins(alias):
		if ResourceLoader.exists(Assets.champion_model_path(alias, int(s.num))):
			out.append(s)
	return out


static func make_kit(alias: String):
	var path := "res://src/champions/kits/%s.gd" % alias.to_lower()
	if ResourceLoader.exists(path):
		var scr = load(path)
		return scr.new()
	return ChampionKit.new()


static func title(alias: String) -> String:
	return client_data(alias).get("title", "")


static func roles(alias: String) -> Array:
	return client_data(alias).get("roles", [])
