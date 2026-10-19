class_name ChampSelect
extends UIScreen
## ARAM champion select: a random champion, 2 rerolls, a shared bench to swap with, summoner spells, and the whole
## lineup: all 9 bots (4 allies + 5 enemies) show a champion slot (click -> champion picker, no duplicates: picking a
## champion that is already in the game swaps places) and their own difficulty (4-step bar).
## Emits action("locked") / action("back"). On lock-in it builds cfg.lineup / G.lineup (10 {team, champion, difficulty}).
## Styled after the League client's champ select (summoner objects, dice reroll, trapezoid lock-in art).
## [champ-select] ids: "slot:N" (open picker for bot slot N 1..9), "pick:<alias>", "pick_close", "diff:N:L", "rand:ally",
## "rand:enemy", "all:L", "bench:<alias>", "reroll", "sum:N", "pick_sum:<name>", "lock", "back".

var slots: Array = []           ## 10 Dictionaries {team, champion, difficulty, pinned}; [0] = the player, 1..4 allied bots, 5..9 enemy bots
var bench: Array = []
var rerolls := 2
var summoners := ["Flash", "Mark"]
var cfg := {}                   ## filled on lock-in
var _sum_popup := -1
var _sum_k := 0.0               ## popup open animation 0..1
var _pick_slot := -1            ## slot the champion picker is open for (-1 = closed)
var _pick_k := 0.0
var _prev_art: Texture2D = null
var _art_t := 10.0
var _locked_t := -1.0
var _champ_anim := 0.0
var _swap_t := {}               ## slot index -> time of its last change (plate pop animation)
var _bench_t := {}              ## alias -> time it landed on the bench / was swapped in (tile pop animation)
var _timer := 60.0              ## champion select countdown; at 0 the pick is locked automatically (League)
var _last_tick := 99
const TIMER_START := 60.0
const COL_W := 380.0
const PLATE_H := 92.0
const PLATE_STEP := 100.0
const TIER_COLS := [Color("a09b8c"), Color("0ac8b9"), Color("c8aa6e"), Color("e84057")]
const TIER_DESC := [
	"Slow reactions and loose aim. Rarely dodges, hesitates a lot and often forgets to use abilities.",
	"Learning the ropes: moderate reactions, leads some skillshots and sometimes sidesteps yours.",
	"Solid player: quick reactions, decent aim, dodges often, last-hits and respects turrets.",
	"Sharp mechanics: near-instant reactions, accurate skillshots, kites, chains crowd control and dodges most of yours.",
]


func _ready() -> void:
	super._ready()
	_init_lineup()
	if G.next_match.has("player_summoners"):
		summoners = G.next_match.player_summoners.duplicate()
	var aram_music := Sfx.game_music("map12", "mus_map12_phase_select")
	if aram_music != "":
		Sfx.music(aram_music, 1.5)
	else:
		Sfx.music("music-cs-draft-pick-base-layer-01", 1.5, ["music-cs-draft-pick-intensity-layer-01"])
	Sfx.ui("pick_intro")
	_timer = TIMER_START
	_on_champ_changed(false)


## Random ARAM draw for the player and every bot slot the player has not pinned; bot levels and pinned champions come
## from the last setup (G.settings.lineup_prefs).
func _init_lineup() -> void:
	var dflt := clampi(int(G.settings.get("difficulty", 1)), 0, 3)
	var prefs = G.settings.get("lineup_prefs", {})
	if not (prefs is Dictionary):
		prefs = {}
	var pd: Array = prefs.get("diff", []) if prefs.get("diff", []) is Array else []
	var pp: Array = prefs.get("pin", []) if prefs.get("pin", []) is Array else []
	slots = []
	for i in 10:
		slots.append({"team": G.Team.ORDER if i < 5 else G.Team.CHAOS, "champion": "", "difficulty": -1 if i == 0 else dflt, "pinned": false})
	var used := {}
	for i in range(1, 10):
		var k := i - 1
		if k < pd.size():
			slots[i].difficulty = clampi(int(pd[k]), 0, 3)
		if k < pp.size():
			var a := str(pp[k])
			if a in ChampionDB.ROSTER and not used.has(a):
				slots[i].champion = a
				slots[i].pinned = true
				used[a] = true
	var pool: Array = ChampionDB.ROSTER.duplicate()
	pool.shuffle()
	for i in 10:
		if slots[i].champion == "":
			for a in pool:
				if not used.has(a):
					slots[i].champion = a
					used[a] = true
					break
	_rebuild_bench()


func _rebuild_bench() -> void:
	var used := {}
	for s in slots:
		used[s.champion] = true
	bench = []
	for a in ChampionDB.ROSTER:
		if not used.has(a):
			bench.append(a)
	bench.sort()


## Index of the slot holding `alias` (-1 = on the bench).
func _slot_of(alias: String) -> int:
	for i in slots.size():
		if slots[i].champion == alias:
			return i
	return -1


## The lineup handed to the match: 10 {team, champion, difficulty}, human first (difficulty -1).
func lineup() -> Array:
	var out := []
	for i in slots.size():
		var s: Dictionary = slots[i]
		out.append({"team": int(s.team), "champion": str(s.champion), "difficulty": -1 if i == 0 else int(s.difficulty)})
	return out


## Put `alias` into slot `i`. A champion already in the game swaps places with the slot's current one (no duplicates, League
## ARAM); one from the bench replaces it and the old one goes to the bench.
func assign(i: int, alias: String) -> void:
	var cur: String = slots[i].champion
	if alias == cur or not (alias in ChampionDB.ROSTER):
		return
	var j := _slot_of(alias)
	if i == 0:
		_prev_art = Assets.champion_art(cur, 0, "splash")
		_art_t = 0.0
	if j >= 0:
		slots[j].champion = cur
		_swap_t[j] = t
		if j != 0:
			slots[j].pinned = true
	else:
		_bench_t[cur] = t
	slots[i].champion = alias
	_swap_t[i] = t
	if i != 0:
		slots[i].pinned = true
	_rebuild_bench()
	if i == 0 or j == 0:
		_on_champ_changed(true)


## Randomize one team's bots from the champions the other team (and the player) does not hold.
func _randomize_team(enemy: bool) -> void:
	var lo := 5 if enemy else 1
	var hi := 10 if enemy else 5
	var taken := {}
	for i in slots.size():
		if i < lo or i >= hi:
			taken[slots[i].champion] = true
	var cand: Array = []
	for a in ChampionDB.ROSTER:
		if not taken.has(a):
			cand.append(a)
	cand.shuffle()
	for i in range(lo, hi):
		slots[i].champion = cand[i - lo]
		slots[i].pinned = false
		_swap_t[i] = t
	_rebuild_bench()


func me() -> String:
	return slots[0].champion


func _process(delta: float) -> void:
	super._process(delta)
	_art_t += delta
	_champ_anim = minf(1.0, _champ_anim + delta * 3.0)
	_sum_k = move_toward(_sum_k, 1.0 if _sum_popup >= 0 else 0.0, delta * 7.0)
	_pick_k = move_toward(_pick_k, 1.0 if _pick_slot >= 0 else 0.0, delta * 7.0)
	if _locked_t < 0.0 and _fade_done():
		_timer = maxf(0.0, _timer - delta)
		var sec := int(ceil(_timer))
		if sec != _last_tick:
			_last_tick = sec
			if sec <= 10 and sec > 0:
				Sfx.ui("countdown")
			elif sec == 0 and _timer <= 0.0:
				on_action("lock")   # time ran out: lock in the current champion like the client does
	if _locked_t >= 0.0:
		_locked_t += delta
		if _locked_t > 1.1:
			_locked_t = -100.0
			super.on_action("locked")


func _fade_done() -> bool:
	return fade >= 1.0


func _on_champ_changed(voice: bool) -> void:
	_champ_anim = 0.0
	if voice:
		Sfx.champ(me(), "choose_vo", -2.0)


# ===================================================================== draw
func draw_screen(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	var art := Assets.champion_art(me(), 0, "splash")
	var zoom := 1.04 + 0.02 * sin(t * 0.2)
	var ar := Rect2(vs * 0.5 - vs * zoom * 0.5, vs * zoom)
	if _prev_art != null and _art_t < 0.6:
		tex_cover(_prev_art, ar, Color(1, 1, 1, 0.6))
	tex_cover(art, ar, Color(1, 1, 1, 0.6 * clampf(_art_t / 0.6, 0.0, 1.0)), Vector2(0.6, 0.3))
	smoke(vs, 0.07, 6.0)
	vignette(vs, 0.88)
	_vgrad(Rect2(0, vs.y * 0.52, vs.x, vs.y * 0.48), Color(0.004, 0.039, 0.075, 0.0), Color(0.004, 0.039, 0.075, 0.9))
	var top := ctex("lol-champ-select/images/top-darkening.png")
	if top != null:
		draw_texture_rect(top, Rect2(0, 0, vs.x, 150), false, Color(1, 1, 1, 0.9))
	# header
	var ha := appear(0.0)
	_draw_timer(Vector2(vs.x * 0.5, 62.0 - (1.0 - ha) * 10.0), ha)
	label("ARAM: Mayhem  ·  Howling Abyss", Vector2(vs.x * 0.5, 126 - (1.0 - ha) * 10), "sub", 1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ha), 18.0)
	label("Choose your champion", Vector2(vs.x * 0.5, 168 - (1.0 - ha) * 10), "h2", 1, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, ha), 42.0, true)
	divider(vs.x * 0.5, 204, 520.0 * ha, ha)
	_draw_bench(vs)
	_draw_team(vs, false)
	_draw_team(vs, true)
	_draw_all_bots(vs)
	_draw_center(vs)
	_draw_summoners(vs)
	_draw_playstyle(vs)
	_draw_actions(vs)
	button("back", Rect2(44, vs.y - 92, 190, 58), "Back", "normal", _locked_t < 0.0, 22, "back")
	if _sum_k > 0.001:
		_draw_sum_popup(vs)
	if _pick_k > 0.001:
		_draw_pick_popup(vs)
	if _locked_t >= 0.0:
		var k := clampf(_locked_t / 0.5, 0.0, 1.0)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.75, 0.95, 1.0, 0.3 * (1.0 - k)))
		# expanding ring from the lock-in button
		var rc := Vector2(vs.x - 36 - 190, vs.y - 120)
		draw_arc(rc, 40 + 520 * k, 0, TAU, 96, Color(0.5, 0.95, 1.0, 0.7 * (1.0 - k)), 4.0 * (1.0 - k) + 1.0, true)


## League's champ-select countdown: ring that drains over the phase with the remaining seconds in the middle.
func _draw_timer(c: Vector2, a: float) -> void:
	var frac := _timer / TIMER_START
	var urgent := _timer <= 10.0
	var col := Color(0.96, 0.4, 0.35) if urgent else C_GOLD
	if urgent:
		col = col.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(t * 8.0)))
	draw_circle(c, 36, Color(0.004, 0.039, 0.075, 0.85 * a))
	draw_arc(c, 36, -PI * 0.5, -PI * 0.5 + TAU * frac, 64, Color(col.r, col.g, col.b, a), 4.0, true)
	draw_arc(c, 36, 0, TAU, 48, Color(0.78, 0.67, 0.43, 0.25 * a), 1.5, true)
	var sec := int(ceil(_timer))
	label("%d:%02d" % [sec / 60, sec % 60] if sec >= 60 else str(sec), c, "num", 1, Color(col.r, col.g, col.b, a).lerp(Color(1, 1, 1, a), 0.4), 28.0 if sec < 60 else 22.0)


func _draw_bench(vs: Vector2) -> void:
	var sz := 84.0
	var gap := 12.0
	var w := bench.size() * (sz + gap) - gap
	var x0 := vs.x * 0.5 - w * 0.5
	var y := 232.0
	var ba := appear(0.1)
	label("Bench  —  click to swap", Vector2(vs.x * 0.5, y), "sub", 1, Color(C_DIM.r, C_DIM.g, C_DIM.b, ba), 17.0)
	for i in bench.size():
		var a: String = bench[i]
		var ka := appear(0.12 + i * 0.03)
		var r := Rect2(x0 + i * (sz + gap), y + 22 + (1.0 - ka) * 14.0, sz, sz)
		var id := "bench:" + a
		hit_area(id, r, "grid_hover|")
		var h := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		var pop: float = maxf(0.0, 1.0 - (t - float(_bench_t.get(a, -10.0))) / 0.5)
		var rr := r.grow(5.0 * h + 4.0 * pop)
		if h > 0.0 or pop > 0.0:
			glow(rr, Color(0.9, 0.78, 0.45, 0.35 * maxf(h, pop)), 12)
		var tx := Assets.champion_square(a)
		icon(tx, rr, C_GOLD if h > 0.3 else C_GOLD_DARK, Color(1, 1, 1, ka * (0.8 + 0.2 * h)))
		set_tip(id, ChampionDB.client_data(a).get("name", a), ChampionDB.display_title(a) + "\nRoles: " + ", ".join(ChampionDB.roles(a)))


func _col_x(vs: Vector2, enemy: bool) -> float:
	return vs.x - 48.0 - COL_W if enemy else 48.0


## One team column: header + 5 summoner-object plates (champion tile, name, difficulty bar) + a randomize button.
func _draw_team(vs: Vector2, enemy: bool) -> void:
	var x := _col_x(vs, enemy)
	var y := 262.0
	var lo := 5 if enemy else 0
	var ha := appear(0.1 if not enemy else 0.18)
	label("Enemy team" if enemy else "Your team", Vector2(x + 4, y - 22), "h5", 0, Color(C_RED.r, C_RED.g, C_RED.b, ha) if enemy else Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ha), 20.0)
	for k in 5:
		var ka := appear((0.15 if not enemy else 0.24) + k * 0.07)
		var slide := (1.0 - ka) * 60.0 * (1.0 if enemy else -1.0)
		_draw_plate(lo + k, Rect2(x + slide, y + k * PLATE_STEP, COL_W, PLATE_H), ka)
	var by := y + 5 * PLATE_STEP + 4.0
	var bka := appear(0.5)
	button("rand:enemy" if enemy else "rand:ally", Rect2(x, by, COL_W, 46), "Randomize enemies" if enemy else "Randomize allies", "normal",
			_locked_t < 0.0 and _pick_slot < 0 and bka > 0.9, 19)


func _draw_plate(i: int, r: Rect2, ka: float) -> void:
	var sl: Dictionary = slots[i]
	var a: String = sl.champion
	var mine := i == 0
	var enemy: bool = sl.team == G.Team.CHAOS
	var id := "slot:%d" % i
	var active := _locked_t < 0.0 and _pick_slot < 0
	var hov := (not mine) and active and is_hover(id)
	var h := ease_to(id, "h", 1.0 if hov else 0.0, 12.0)
	var pop: float = clampf(1.0 - (t - float(_swap_t.get(i, -10.0))) / 0.5, 0.0, 1.0)
	var fill_a := 0.88 * ka
	var top := Color(0.035, 0.078, 0.157, fill_a)
	var bot := Color(0.004, 0.039, 0.075, fill_a)
	if enemy:
		top = Color(0.098, 0.039, 0.063, fill_a)
		bot = Color(0.043, 0.02, 0.043, fill_a)
	vgrad_stops(r, [[0.0, top], [1.0, bot]])
	if mine:
		var pulse := 0.5 + 0.5 * sin(t * 2.5)
		glow(r, Color(0.78, 0.67, 0.43, 0.18 + 0.12 * pulse), 12)
		grad_border(r, 3.0, [[0.0, Color("785a28")], [0.55, Color("c89b3c")], [1.0, Color("f0e6d2")]], ka)
		_hgrad(r, Color(0.78, 0.67, 0.43, 0.10), Color(0.78, 0.67, 0.43, 0.0))
	else:
		if enemy:
			grad_border(r, 2.0, [[0.0, Color("4a1d22")], [1.0, Color("8c3a3f").lerp(Color("d9645e"), h)]], ka)
		else:
			grad_border(r, 2.0, [[0.0, Color("463714")], [1.0, Color("785a28").lerp(Color("c8aa6e"), h)]], ka)
		if h > 0.0:
			glow(r, Color(0.78, 0.67, 0.43, 0.2 * h) if not enemy else Color(0.85, 0.4, 0.38, 0.2 * h), 10)
			_hgrad(r, Color(0.78, 0.67, 0.43, 0.14 * h), Color(0.78, 0.67, 0.43, 0.0))
	if pop > 0.0:
		glow(r, Color(0.9, 0.78, 0.45, 0.35 * pop * ka), 12)
	# team accent on the outer edge (blue allies, red enemies)
	var tc: Color = G.COLOR_ENEMY if enemy else G.COLOR_ALLY
	var ar := Rect2(r.end.x - 4, r.position.y + 4, 4, r.size.y - 8) if enemy else Rect2(r.position.x, r.position.y + 4, 4, r.size.y - 8)
	draw_rect(ar, Color(tc.r, tc.g, tc.b, 0.8 * ka))
	var tr := Rect2(r.position + Vector2(10, 8), Vector2(76, 76))
	draw_rect(tr.grow(2), Color(0, 0, 0, 0.6 * ka))
	tex_cover(Assets.champion_art(a, 0, "tile"), tr, Color(1, 1, 1, ka))
	grad_border(tr, 2.0, [[0.0, Color("785a28")], [1.0, Color("c8aa6e")]] if mine else [[0.0, Color("463714")], [1.0, Color("785a28")]], ka)
	var nm: String = ChampionDB.client_data(a).get("name", a)
	var tx := r.position.x + 100.0
	if mine:
		label(nm, Vector2(tx, r.position.y + 28), "h4", 0, C_GOLD_BRIGHT, 26.0, false, 0.0, 190.0)
		label("You", Vector2(tx, r.position.y + 58), "label", 0, C_TEAL, 18.0)
		for s in 2:
			var ir := Rect2(r.end.x - 52, r.position.y + 10 + s * 38, 34, 34)
			icon(Assets.summoner_icon(str(summoners[s]).to_lower()), ir, C_GOLD_DARK, Color(1, 1, 1, ka))
		var cy := r.get_center().y
		draw_colored_polygon(PackedVector2Array([Vector2(r.end.x + 6, cy - 10), Vector2(r.end.x + 18, cy), Vector2(r.end.x + 6, cy + 10)]), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ka))
		return
	label(nm, Vector2(tx, r.position.y + 24), "h4", 0, C_TEXT, 25.0, false, 0.0, 236.0)
	var lv: int = sl.difficulty
	label("%s Bot" % DIFFS[lv], Vector2(tx, r.position.y + 49), "label", 0, TIER_COLS[lv].lerp(Color.WHITE, 0.15), 17.0)
	_diff_bar(i, Rect2(tx, r.position.y + 62, r.end.x - tx - 16.0, 14.0), ka)
	# drop-down caret: this slot opens the champion picker
	var cc := Vector2(r.end.x - 26 - (4 if enemy else 0), r.position.y + 24)
	draw_colored_polygon(PackedVector2Array([cc + Vector2(-7, -3), cc + Vector2(7, -3), cc + Vector2(0, 5)]), C_GOLD_DARK.lerp(C_GOLD_BRIGHT, h) * Color(1, 1, 1, ka))
	if active:
		# the plate registers first so the difficulty segments (registered after) sit on top of it
		hit_area(id, r, "grid")
		set_tip(id, "Change champion", "Pick any champion for this slot. A champion already in the game swaps places with it.")


## Four-step difficulty bar for bot slot `i`: click a segment to set the level.
func _diff_bar(i: int, r: Rect2, ka: float) -> void:
	var lv: int = slots[i].difficulty
	var gap := 6.0
	var sw := (r.size.x - gap * 3.0) / 4.0
	var active := _locked_t < 0.0 and _pick_slot < 0
	for j in 4:
		var sr := Rect2(r.position.x + j * (sw + gap), r.position.y, sw, r.size.y)
		var id := "diff:%d:%d" % [i, j]
		if active:
			hit_area(id, sr.grow_individual(2, 9, 2, 9), "toggle")
		var h := ease_to(id, "h", 1.0 if (active and is_hover(id)) else 0.0, 14.0)
		var col: Color = TIER_COLS[lv]
		if j <= lv:
			_hgrad(sr, col.darkened(0.45), col.lerp(Color.WHITE, 0.1 * h))
			draw_rect(Rect2(sr.position, Vector2(sr.size.x, 2)), Color(1, 1, 1, 0.2 * ka))
		else:
			draw_rect(sr, Color(0.07, 0.09, 0.11, ka))
			if h > 0.0:
				var hc: Color = TIER_COLS[j]
				draw_rect(sr, Color(hc.r, hc.g, hc.b, 0.35 * h))
		grad_border(sr, 1.0, [[0.0, Color("463714")], [1.0, Color("5c4a24").lerp(Color("c8aa6e"), h)]], ka)
		if active:
			set_tip(id, DIFFS[j], TIER_DESC[j])


## Left-bottom quick action: set every bot (both teams) to one level.
func _draw_all_bots(_vs: Vector2) -> void:
	var x := 48.0
	var y := 262.0 + 5 * PLATE_STEP + 4.0 + 46.0 + 14.0
	var ka := appear(0.55)
	var r := Rect2(x, y, COL_W, 122)
	panel(r, 0.9 * ka, 2.0, false)
	label("Set all bots to", Vector2(x + 20, y + 24), "h5", 0, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ka), 18.0)
	var all_lv := -2
	for i in range(1, 10):
		var d: int = slots[i].difficulty
		all_lv = d if all_lv == -2 or all_lv == d else -3
	for j in 4:
		var br := Rect2(x + 14 + (j % 2) * ((COL_W - 28) * 0.5), y + 42 + (j / 2) * 36, (COL_W - 28) * 0.5 - 6, 32)
		button("all:%d" % j, br, DIFFS[j], "primary" if all_lv == j else "normal", _locked_t < 0.0 and _pick_slot < 0 and ka > 0.9, 17)


## Centre-bottom left: summoner spells.
func _draw_summoners(vs: Vector2) -> void:
	var cx := vs.x * 0.5
	var ka := appear(0.25)
	var ay := vs.y - 352.0 + 154.0
	var isz := 72.0
	var x0 := cx - 216.0 - 40.0 - (isz * 2 + 18.0)
	label("Summoner spells", Vector2(x0 + (isz * 2 + 18.0) * 0.5, ay - 22), "h6", 1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ka), 17.0)
	for i in 2:
		var r := Rect2(x0 + i * (isz + 18.0), ay, isz, isz)
		var id := "sum:%d" % i
		if _locked_t < 0.0 and _pick_slot < 0:
			hit_area(id, r, "grid_hover|")
		var h := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		if h > 0.0:
			glow(r, Color(0.9, 0.78, 0.45, 0.3 * h), 10)
		icon(Assets.summoner_icon(str(summoners[i]).to_lower()), r.grow(2.0 * h), C_GOLD if h > 0.3 else C_GOLD_DARK, Color(1, 1, 1, ka))
		label("DF"[i], Vector2(r.get_center().x, r.end.y + 18), "h5", 1, C_GOLD.lerp(C_GOLD_BRIGHT, h), 20.0)
		set_tip(id, str(summoners[i]), "Click to change.")


## Centre-bottom right: the champion's playstyle bars.
func _draw_playstyle(vs: Vector2) -> void:
	var cx := vs.x * 0.5
	var ka := appear(0.25)
	var ay := vs.y - 352.0 + 154.0
	var x := cx + 216.0 + 44.0
	var ps: Dictionary = ChampionDB.client_data(me()).get("playstyleInfo", {})
	label("Playstyle", Vector2(x + 110, ay - 22), "h6", 1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, ka), 17.0)
	var labels := [["damage", "Damage"], ["durability", "Toughness"], ["crowdControl", "Control"], ["mobility", "Mobility"], ["utility", "Utility"]]
	for i in labels.size():
		var v := int(ps.get(labels[i][0], 0))
		var ly := ay - 6 + i * 29.0
		label(labels[i][1], Vector2(x, ly + 12), "label", 0, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, ka), 17.0)
		for sg in 3:
			var br := Rect2(x + 108 + sg * 42, ly + 5, 36, 13)
			if sg < v:
				_hgrad(br, Color("785a28"), Color("c8aa6e"))
				draw_rect(Rect2(br.position, Vector2(br.size.x, 2)), Color(1, 1, 1, 0.2))
			else:
				draw_rect(br, Color(0.07, 0.09, 0.11))
			grad_border(br, 1.0, [[0.0, Color("463714")], [1.0, Color("5c4a24")]])


## Bottom right: reroll (dice) + lock in.
func _draw_actions(vs: Vector2) -> void:
	var ka := appear(0.25)
	var bx := _col_x(vs, true)
	var by := vs.y - 214.0
	bx += (1.0 - ka) * 60.0
	_reroll_button(Rect2(bx, by + 18, 140, 100))
	_lockin_button(Rect2(bx + 152, by + 10, COL_W - 152, 120))


## Champion picker for one bot slot (modal, like the summoner popup): every champion with its team tag.
func _draw_pick_popup(vs: Vector2) -> void:
	var ez := 1.0 - pow(1.0 - _pick_k, 3.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03, 0.66 * ez))
	if _pick_slot < 0:
		return
	hit_area("pick_close", Rect2(Vector2.ZERO, vs), "silent")
	var roster: Array = ChampionDB.ROSTER
	var n := roster.size()
	var cols := 7
	var sz := 100.0
	var cw := sz + 24.0
	var rh := sz + 66.0
	var w := cols * cw + 64.0
	var h: float = ceil(n / float(cols)) * rh + 170.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - ez) * 24.0), Vector2(w, h))
	panel(r, 0.98)
	hit_area("~popup", r, "silent")
	var sl: Dictionary = slots[_pick_slot]
	var who := ("Enemy %d" % (_pick_slot - 4)) if sl.team == G.Team.CHAOS else ("Ally %d" % _pick_slot)
	label("Choose champion  ·  %s" % who, Vector2(r.get_center().x, r.position.y + 48), "h4", 1, C_GOLD_BRIGHT, 28.0)
	divider(r.get_center().x, r.position.y + 82, r.size.x * 0.6)
	for i in n:
		var a: String = roster[i]
		var cr := Rect2(r.position.x + 32 + (i % cols) * cw + 12, r.position.y + 106 + (i / cols) * rh, sz, sz)
		var id := "pick:" + a
		var j := _slot_of(a)
		var cur: bool = a == sl.champion
		hit_area(id, cr, "grid")
		var hh := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		var tag := "Bench"
		var tcol := C_DIM
		if j == 0:
			tag = "You"
			tcol = C_TEAL
		elif j >= 0:
			tag = "Enemy" if slots[j].team == G.Team.CHAOS else "Ally"
			tcol = G.COLOR_ENEMY if slots[j].team == G.Team.CHAOS else G.COLOR_ALLY
		if cur:
			tag = "Selected"
			tcol = C_GOLD_BRIGHT
			glow(cr, Color(0.9, 0.78, 0.45, 0.45), 12)
		elif hh > 0.0:
			glow(cr, Color(0.9, 0.78, 0.45, 0.3 * hh), 12)
		var dim := 0.6 if (j >= 0 and not cur) else 1.0
		icon(Assets.champion_square(a), cr.grow(3.0 * hh), C_GOLD if cur or hh > 0.3 else C_GOLD_DARK, Color(1, 1, 1, lerpf(dim, 1.0, hh)))
		if j >= 0 and not cur:
			draw_rect(Rect2(cr.position.x, cr.end.y - 4, cr.size.x, 4), Color(tcol.r, tcol.g, tcol.b, 0.9))
		var nm: String = ChampionDB.client_data(a).get("name", a)
		label(nm, Vector2(cr.get_center().x, cr.end.y + 20), "label", 1, C_GOLD_BRIGHT if cur else C_TEXT.lerp(C_GOLD_BRIGHT, hh), 18.0, false, 0.0, cw - 6)
		label(tag, Vector2(cr.get_center().x, cr.end.y + 42), "body", 1, tcol, 15.0)
		var body := ChampionDB.display_title(a)
		if j >= 0 and not cur:
			body += "\nCurrently: %s. Picking swaps places." % tag
		elif not cur:
			body += "\nOn the bench."
		set_tip(id, nm, body)
	label("A champion that is already in the game swaps places with this slot's champion.", Vector2(r.get_center().x, r.end.y - 38), "body_l", 1, C_DIM, 18.0)


func _draw_center(vs: Vector2) -> void:
	var a := me()
	var cd := ChampionDB.client_data(a)
	var cx := vs.x * 0.5
	var y := vs.y - 352.0
	var k := _champ_anim
	var off := (1.0 - k) * 24.0
	var lock_pop := 0.0
	if _locked_t >= 0.0:
		lock_pop = sin(clampf(_locked_t / 0.5, 0.0, 1.0) * PI) * 0.06
	var nm := str(cd.get("name", a))
	grad_text("cs_name", nm, Rect2(cx - 520, y - 62 + off, 1040, 124), int(104 * (1.0 + lock_pop)), "Heavy", 0.09, 1,
			k * (1.0 - clampf(maxf(_sum_k, _pick_k) * 4.0, 0.0, 1.0)), fmod(t, 6.0) / 1.5 if fmod(t, 6.0) < 1.5 else -1.0, [], 5)
	label(ChampionDB.display_title(a), Vector2(cx, y + 62 + off), "h4", 1, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, k), 28.0, true)
	var roles := ChampionDB.roles(a)
	var rw := 150.0
	var rx := cx - roles.size() * rw * 0.5
	for i in roles.size():
		var rr := Rect2(rx + i * rw + 8, y + 94 + off, rw - 16, 34)
		draw_rect(rr, Color(0.004, 0.039, 0.075, 0.75 * k))
		grad_border(rr, 1.5, [[0.0, Color("463714")], [1.0, Color("785a28")]], k)
		label(str(roles[i]), rr.get_center(), "h6", 1, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, k), 17.0)
	# abilities
	var keys := ["P", "Q", "W", "E", "R"]
	var spells: Array = cd.get("spells", [])
	var isz := 72.0
	var gapx := 18.0
	var ax := cx - (isz * 5 + gapx * 4) * 0.5
	var ay := y + 154
	for i in 5:
		var r := Rect2(ax + i * (isz + gapx), ay, isz, isz)
		var id := "ab:%d" % i
		hit_area(id, r, "grid_hover|")
		var h := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		if h > 0.0:
			glow(r, Color(0.9, 0.78, 0.45, 0.3 * h), 10)
		icon(Assets.ability_icon(a, keys[i].to_lower()), r.grow(2.0 * h), C_GOLD if h > 0.3 else C_GOLD_DARK)
		# key badge
		var br := Rect2(r.get_center().x - 14, r.end.y + 6, 28, 24)
		label(keys[i], br.get_center(), "h5", 1, C_GOLD.lerp(C_GOLD_BRIGHT, h), 20.0)
		var nm2 := ""
		var desc := ""
		if i == 0:
			var p: Dictionary = cd.get("passive", {})
			nm2 = str(p.get("name", "Passive"))
			desc = str(p.get("description", ""))
		elif i - 1 < spells.size():
			nm2 = str(spells[i - 1].get("name", ""))
			desc = str(spells[i - 1].get("description", ""))
		set_tip(id, "%s  [%s]" % [nm2, keys[i]], Hud._clean(desc))


func _reroll_button(r: Rect2) -> void:
	var en := rerolls > 0 and _locked_t < 0.0
	if en:
		hit_area("reroll", r, "reroll")
	var s := _bs("reroll")
	var hov := en and hover_id == "reroll"
	var down := hov and press_id == "reroll"
	s.hov = move_toward(s.hov, 1.0 if hov else 0.0, _dt * 8.0)
	var tx := ctex("lol-champ-select/images/config/dice-disable.png") if not en else (ctex("lol-champ-select/images/config/dice-click.png") if down else (ctex("lol-champ-select/images/config/dice-hover.png") if hov else ctex("lol-champ-select/images/config/dice.png")))
	var wob := 0.0
	if s.click_t >= 0.0 and s.click_t < 0.6:
		wob = sin(s.click_t * 22.0) * 0.12 * (1.0 - s.click_t / 0.6)
	var c := r.get_center() + Vector2(0, -8)
	if tx != null:
		var ds := tx.get_size() * 1.05
		draw_set_transform(c, wob, Vector2.ONE * (1.0 + 0.06 * s.hov))
		draw_texture_rect(tx, Rect2(-ds * 0.5, ds), false, Color(1, 1, 1, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hov:
		glow(Rect2(c - Vector2(30, 24), Vector2(60, 48)), Color(0.55, 0.9, 1.0, 0.22), 14)
	# counter badge
	var bc := Vector2(r.end.x - 6, r.position.y + 6)
	draw_circle(bc, 19, Color(0.004, 0.039, 0.075, 0.95))
	draw_arc(bc, 19, 0, TAU, 32, C_GOLD if en else C_DISABLED, 2.0, true)
	label(str(rerolls), bc, "num", 1, C_GOLD_BRIGHT if en else C_DISABLED, 24.0)
	label("Reroll", Vector2(r.get_center().x, r.end.y + 12), "h6", 1, (C_BTN.lerp(C_TEXT, s.hov)) if en else C_DISABLED, 19.0)
	set_tip("reroll", "Reroll", "Trade your champion for a random one from the bench. Your current champion goes to the bench.")


func _lockin_button(r: Rect2) -> void:
	var en := _locked_t < 0.0
	if en:
		hit_area("lock", r, "lockin")
	var s := _bs("lock")
	var hov := en and hover_id == "lock"
	var down := hov and press_id == "lock"
	s.hov = move_toward(s.hov, 1.0 if hov else 0.0, _dt * 7.0)
	var base := ctex("lol-champ-select/images/action-button/button-lockin.png")
	var over := ctex("lol-champ-select/images/action-button/button-lockin-hover.png")
	var clk := ctex("lol-champ-select/images/action-button/button-lockin-click.png")
	var dis := ctex("lol-champ-select/images/action-button/button-lockin-disable.png")
	var rr := r
	if down:
		rr = Rect2(r.get_center() - r.size * 0.97 * 0.5, r.size * 0.97)
	if not en:
		draw_texture_rect(dis if _locked_t < 0.0 else clk, rr, false)
		if _locked_t >= 0.0:
			draw_texture_rect(over, rr, false, Color(1, 1, 1, 0.8))
	elif down:
		draw_texture_rect(clk, rr, false)
	else:
		draw_texture_rect(base, rr, false)
		if s.hov > 0.0:
			draw_texture_rect(over, rr, false, Color(1, 1, 1, s.hov))
	var tc := Color("cdfafa").lerp(Color.WHITE, s.hov)
	if _locked_t >= 0.0:
		tc = Color("e8ffff")
	label("Lock in" if _locked_t < 0.0 else "Locked", rr.get_center() + Vector2(0, -rr.size.y * 0.06), "btn", 1, tc, 46.0, true)


func _draw_sum_popup(vs: Vector2) -> void:
	var ez := 1.0 - pow(1.0 - _sum_k, 3.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03, 0.62 * ez))
	if _sum_popup < 0:
		return
	hit_area("sum_close", Rect2(Vector2.ZERO, vs), "silent")
	var n := Summoners.ALL.size()
	var cols := 4
	var sz := 96.0
	var cw := sz + 32.0
	var w := cols * cw + 64
	var h: float = ceil(n / float(cols)) * (sz + 56) + 130
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, (1.0 - ez) * 24.0), Vector2(w, h))
	panel(r, 0.98)
	hit_area("~popup", r, "silent")
	label("Choose summoner spell  (%s)" % "DF"[_sum_popup], Vector2(r.get_center().x, r.position.y + 48), "h4", 1, C_GOLD_BRIGHT, 28.0)
	divider(r.get_center().x, r.position.y + 82, r.size.x * 0.6)
	for i in n:
		var nm: String = Summoners.ALL[i]
		var cr := Rect2(r.position.x + 32 + (i % cols) * cw + 8, r.position.y + 112 + (i / cols) * (sz + 56), sz, sz)
		var id := "pick_sum:" + nm
		hit_area(id, cr, "grid")
		var sel: bool = summoners[_sum_popup] == nm
		var hh := ease_to(id, "h", 1.0 if is_hover(id) else 0.0, 12.0)
		if sel or hh > 0.0:
			glow(cr, Color(0.9, 0.78, 0.45, 0.3 * maxf(hh, 1.0 if sel else 0.0)), 12)
		icon(Assets.summoner_icon(nm.to_lower()), cr.grow(3.0 * hh), C_GOLD if sel or hh > 0.3 else C_GOLD_DARK)
		label(nm, Vector2(cr.get_center().x, cr.end.y + 24), "label", 1, C_GOLD_BRIGHT if sel else C_TEXT.lerp(C_GOLD_BRIGHT, hh), 19.0)
		var sp = Summoners.make(nm, null)
		if sp != null:
			set_tip(id, nm, "%s\nCooldown: %ds" % [sp.description, int(sp.cooldowns[0]) if not sp.cooldowns.is_empty() else 0])


# ===================================================================== actions
func on_action(id: String) -> void:
	if _locked_t >= 0.0:
		return
	if handle_settings_action(id):
		return
	if id.begins_with("bench:"):
		var a := id.substr(6)
		if a in bench:
			assign(0, a)
			Sfx.ui("swap")
			Sfx.ui("bench")
	elif id.begins_with("slot:"):
		_pick_slot = int(id.substr(5))
		Sfx.ui("spells_open")
	elif id.begins_with("pick:"):
		if _pick_slot >= 0:
			var a := id.substr(5)
			if a != slots[_pick_slot].champion:
				var from_slot := _slot_of(a) >= 0
				assign(_pick_slot, a)
				Sfx.ui("swap")
				Sfx.ui("swap_accepted" if from_slot else "bench")
			_pick_slot = -1
	elif id == "pick_close":
		_pick_slot = -1
		Sfx.ui("flyout_close")
	elif id.begins_with("diff:"):
		var p := id.split(":")
		if p.size() == 3:
			var i := int(p[1])
			if i >= 1 and i < slots.size():
				slots[i].difficulty = clampi(int(p[2]), 0, 3)
	elif id.begins_with("all:"):
		var lv := clampi(int(id.substr(4)), 0, 3)
		for i in range(1, 10):
			slots[i].difficulty = lv
	elif id == "rand:ally" or id == "rand:enemy":
		_randomize_team(id == "rand:enemy")
		Sfx.ui("swap")
	elif id == "reroll" and rerolls > 0:
		rerolls -= 1
		var a: String = bench[G.rng.randi() % bench.size()]
		assign(0, a)
		get_tree().create_timer(0.35).timeout.connect(func(): Sfx.ui("bench"))
	elif id.begins_with("sum:"):
		_sum_popup = int(id.substr(4))
		Sfx.ui("spells_open")
	elif id.begins_with("pick_sum:"):
		var nm := id.substr(9)
		var other := 1 - _sum_popup
		if summoners[other] == nm:
			summoners[other] = summoners[_sum_popup]
		summoners[_sum_popup] = nm
		_sum_popup = -1
	elif id == "sum_close":
		_sum_popup = -1
		Sfx.ui("flyout_close")
	elif id == "lock":
		_pick_slot = -1
		var lu := lineup()
		var allies: Array = []
		var enemies: Array = []
		for i in range(1, 10):
			(enemies if i >= 5 else allies).append(slots[i].champion)
		cfg = {
			"player_champion": me(),
			"player_skin": 0,
			"ally_champions": allies,
			"enemy_champions": enemies,
			"lineup": lu,
			"player_summoners": summoners.duplicate(),
			"seed": G.rng.randi(),
		}
		G.next_match = cfg.duplicate(true)
		G.lineup = lu.duplicate(true)
		_save_prefs()
		_locked_t = 0.0
		Sfx.ui("lock_confirm")
		Sfx.champ(me(), "choose_vo", 0.0)
		get_tree().create_timer(0.55).timeout.connect(func(): Sfx.ui("lock_done"))
	elif id == "back":
		_save_prefs()
		super.on_action("back")


## Remember bot levels and pinned (hand-picked) champions for the next champion select.
func _save_prefs() -> void:
	var diff: Array = []
	var pin: Array = []
	for i in range(1, 10):
		diff.append(int(slots[i].difficulty))
		pin.append(str(slots[i].champion) if slots[i].pinned else "")
	G.settings.lineup_prefs = {"diff": diff, "pin": pin}
	G.save_settings()
