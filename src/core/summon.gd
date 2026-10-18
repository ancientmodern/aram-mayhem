class_name Summon
extends Unit
## Pet / summoned unit (Tibbers, augment summons). AI: fight near the summoner, follow otherwise.

var summoner = null           ## owning Champion
var lifetime := 45.0
var leash := 9.0
var follow_dist := 2.5
var controlled_target: Unit = null   ## set by the owner's ability (redirect)
var _think := 0.0
var on_expire := Callable()


func _init() -> void:
	super._init()
	kind = G.Kind.SUMMON
	stats.uses_mana = false
	mass = 1.2
	acquisition_range = 7.0


## data keys: hp, ad, armor, mr, as, range, ms, radius, height, model, skin, scale, missile_speed
func setup(owner_champ, p_name: String, data: Dictionary) -> void:
	summoner = owner_champ
	team = owner_champ.team
	display_name = p_name
	radius = data.get("radius", 0.8)
	path_radius = radius * 0.7
	height = data.get("height", 2.4)
	selection_radius = radius + 0.4
	lifetime = data.get("lifetime", 45.0)
	attack_missile_speed = data.get("missile_speed", 0.0)
	windup_pct = data.get("windup", 0.3)
	stats.set_base({
		"base_hp": data.get("hp", 1000.0), "hp_per_level": 0.0, "base_hp_regen": 0.0, "hp_regen_per_level": 0.0,
		"base_ad": data.get("ad", 50.0), "ad_per_level": 0.0, "base_armor": data.get("armor", 30.0), "armor_per_level": 0.0,
		"base_mr": data.get("mr", 30.0), "mr_per_level": 0.0, "base_ms": data.get("ms", 350.0),
		"attack_range": data.get("range", 175.0), "attack_speed": data.get("as", 0.8), "attack_speed_ratio": data.get("as", 0.8),
		"attack_speed_per_level": 0.0, "mana_base": 0.0, "mana_per_level": 0.0, "mana_regen": 0.0, "mana_regen_per_level": 0.0,
	})
	recompute_stats()
	hp = stats.max_hp
	var m: Node3D = null
	if data.has("model"):
		m = Assets.unit_model(data.model, data.get("skin", 0))
	if m == null:
		m = Assets.placeholder_model(team, height, radius * 0.8)
	set_model(m)
	display_scale = data.get("scale", 1.0)
	anim_map = Assets.build_anim_map(anim_player, data.get("anims", {}))
	recompute_stats()


func sight_range() -> float:
	return 10.0


func auto_attacks_when_idle() -> bool:
	return false


func think(dt: float) -> void:
	lifetime -= dt
	if lifetime <= 0.0 or summoner == null or not is_instance_valid(summoner):
		_expire()
		return
	_think -= dt
	if _think > 0.0:
		return
	_think = 0.2
	var sp: Vector3 = summoner.global_position
	if attack_valid(controlled_target):
		issue_attack(controlled_target)
		return
	controlled_target = null
	# fight what the summoner fights, else the nearest enemy near the summoner
	var tgt: Unit = null
	if summoner.attack_target != null and attack_valid(summoner.attack_target) and summoner.attack_target.team != team:
		tgt = summoner.attack_target
	if tgt == null:
		var best_d := INF
		for u in match_ref.units_in_radius(global_position, acquisition_range, G.enemy_team(team)):
			if not u.is_targetable_by(team) or u.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
				continue
			var d := G.flat_dist(global_position, u.global_position) + (0.0 if u.kind == G.Kind.CHAMPION else 2.0)
			if d < best_d and G.flat_dist(sp, u.global_position) < leash:
				best_d = d
				tgt = u
	if tgt != null:
		if attack_target != tgt:
			issue_attack(tgt)
		return
	if G.flat_dist(global_position, sp) > follow_dist + 1.0 and not summoner.dead:
		issue_move(sp + G.flat_dir(sp, global_position) * follow_dist)
	elif cmd == Cmd.ATTACK:
		issue_stop()


func _expire() -> void:
	if dead:
		return
	if on_expire.is_valid():
		on_expire.call(self)
	dead = true
	hp = 0.0
	play_anim("death", 1.0, 0.1)
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(func():
		if match_ref != null:
			match_ref.remove_unit(self))


func on_died(_killer) -> void:
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_callback(func():
		if match_ref != null:
			match_ref.remove_unit(self))
