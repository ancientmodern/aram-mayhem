class_name FloatingTextSystem
extends RefCounted
## League floating combat text, driven by League's own FloatTextFormattingData + GameFontDescription
## (UI.wad bins, extracted to assets/ui/world/floating_text.json by tools/lol/extract_world_ui.py).
## Motion is League's: screen-space start offset (+ random start offset), random X/Y launch velocity
## (pixels/s at the 1600x1200 UI reference), a constant "ContinualForce" (gravity), alternating left/right per
## target, a short shrink-in, then a linear fade over `Decay` seconds after `DecayDelay`.
## FloatingTextTunables: at most 20 items alive (least important dropped), and queued (non-IgnoreQueue) texts on
## the same target are staggered by mAnimatedTextQueueDelay (0.2 s).
## Fonts: solid fill (League's floating text has NO fill gradient - the second colour in the font bin is the
## colourblind palette, used when G.settings.colorblind is on), 1 px outline, and the default black drop shadow
## at shadowDepth 2,2.
##
## Perf: entries are pooled objects (no per-frame allocation), each text is drawn at a fixed font size chosen at
## spawn (the shrink-in is a canvas transform, so no new glyph sizes get rasterised mid-fight) and the glyph
## caches are pre-warmed on the first draw.

const REF_SCALE := 1080.0 / 1200.0   ## League UI reference is 1200 px tall; our canvas is 1080 tall
const OUTLINE_PX := 3                ## Godot outline size for League's outlineSize 1 (stroke ~1 px each side)
const MAX_QUEUE_WAIT := 0.6          ## don't let queued texts lag more than three slots behind

class Entry:
	var text := ""
	var unit: Node3D
	var anchor := Vector3.ZERO
	var age := 0.0
	var off := Vector2.ZERO
	var vel := Vector2.ZERO
	var acc := Vector2.ZERO
	var delay := 0.4
	var decay := 0.45
	var shrink_t := 0.0
	var shrink_s := 0.0
	var fs := 24
	var color := Color.WHITE
	var outline := Color.BLACK
	var has_outline := true
	var shadow := Color.BLACK
	var shadow_off := Vector2(2, 2)
	var follow := false
	var follow_dy := 0.0
	var icon: Texture2D
	var icon_size := Vector2.ZERO
	var icon_off := Vector2.ZERO
	var icon_right := false
	var prio := 6
	var tw := 0.0                    ## text width at fs
	var asc := 0.0                   ## font ascent at fs
	var line := TextLine.new()       ## shaped once at spawn, reused by the pool

var types := {}
var texts: Array[Entry] = []
var font: Font
var max_items := 20
var queue_delay := 0.2
var _pool: Array[Entry] = []
var _alt := {}                      ## target instance id -> next horizontal direction
var _queue_t := {}                  ## target instance id -> time the last queued text starts
var _clock := 0.0
var _icons := {}
var _warm := false


func _init() -> void:
	font = Assets.font("spiegel", "Bold")
	var path := "res://assets/ui/world/floating_text.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			types = d
	var tun: Dictionary = types.get("_tunables", {})
	max_items = int(tun.get("mMaxFloatingTextItems", 20))
	queue_delay = float(tun.get("mAnimatedTextQueueDelay", 0.2))
	for k in ["physical", "magic", "true"]:
		_icons["crit_" + k] = load("res://assets/ui/world/ft_crit_%s.png" % k)
	_icons["gold"] = load("res://assets/ui/world/ft_gold.png")


static func _col(a, fallback: Color = Color.WHITE) -> Color:
	if a is Array and a.size() >= 3:
		return Color8(int(a[0]), int(a[1]), int(a[2]), int(a[3]) if a.size() > 3 else 255)
	return fallback


static func _font_px(t: Dictionary) -> int:
	return maxi(int(round(float(t.get("size", 27)) * float(t.get("Scale", 1.0)) * REF_SCALE)), 6)


## Rasterise the digits of every combat-text size once, off-canvas, so the first fight has no glyph hitch.
func prewarm(ci: CanvasItem) -> void:
	if _warm:
		return
	_warm = true
	var seen := {}
	for k in ["PhysicalDamage", "MagicalDamage", "TrueDamage", "PhysicalDamageCritical", "Heal", "Gold", "Level",
			"Special", "EnemyPhysicalDamage"]:
		var t: Dictionary = types.get(k, {})
		var fs := _font_px(t)
		if seen.has(fs):
			continue
		seen[fs] = true
		var s := "0123456789+-Level Up!"
		ci.draw_string_outline(font, Vector2(-4000, -4000), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, OUTLINE_PX, Color.BLACK)
		ci.draw_string(font, Vector2(-4000, -4000), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _new_entry() -> Entry:
	if _pool.is_empty():
		return Entry.new()
	return _pool.pop_back()


## Spawn one text of League type `tname` (e.g. "PhysicalDamage", "MagicalDamageCritical", "Heal", "Gold").
## Returns the entry (or null when it lost the priority contest for one of the 20 slots).
func spawn(tname: String, text: String, unit: Node3D, world_pos: Vector3, icon: String = "") -> Entry:
	var t: Dictionary = types.get(tname, types.get("PhysicalDamage", {}))
	var prio := int(t.get("Priority", 6))
	if texts.size() >= max_items:
		# League keeps the most important texts (lower Priority value wins), oldest dropped first
		var worst := -1
		for i in texts.size():
			if worst < 0 or texts[i].prio > texts[worst].prio or (texts[i].prio == texts[worst].prio and texts[i].age > texts[worst].age):
				worst = i
		if texts[worst].prio < prio:
			return null
		_pool.append(texts[worst])
		texts.remove_at(worst)
	var id := unit.get_instance_id() if unit != null else 0
	var start := 0.0
	if not t.get("IgnoreQueue", false) and unit != null:
		var q: float = maxf(float(_queue_t.get(id, -1.0)) + queue_delay, _clock)
		if q - _clock > MAX_QUEUE_WAIT:
			return null
		_queue_t[id] = q
		start = q - _clock
	var dir := 1.0
	if t.get("AlternateRightLeft", false) and unit != null:
		dir = _alt.get(id, 1.0)
		_alt[id] = -dir
	var e := _new_entry()
	e.text = text
	e.unit = unit
	e.anchor = world_pos
	e.age = -start
	e.off = Vector2(float(t.get("StartOffsetX", 0.0)) * dir + G.rng.randf_range(float(t.get("RandomStartOffsetMinX", 0.0)), float(t.get("RandomStartOffsetMaxX", 0.0))),
			-float(t.get("StartOffsetY", 0.0)) + G.rng.randf_range(float(t.get("RandomStartOffsetMinY", 0.0)), float(t.get("RandomStartOffsetMaxY", 0.0))))
	e.vel = Vector2(G.rng.randf_range(float(t.get("MinXVelocity", 0.0)), float(t.get("MaxXVelocity", 0.0))) * dir,
			-G.rng.randf_range(float(t.get("MinYVelocity", 0.0)), float(t.get("MaxYVelocity", 0.0))))
	e.acc = Vector2(float(t.get("ContinualForceX", 0.0)) * dir, float(t.get("ContinualForceY", 0.0)))
	e.delay = float(t.get("DecayDelay", 0.4))
	e.decay = maxf(float(t.get("Decay", 0.45)), 0.05)
	e.shrink_t = float(t.get("ShrinkTime", 0.0))
	e.shrink_s = float(t.get("ShrinkScale", 0.0))
	e.fs = _font_px(t)
	var cb: bool = G.settings.get("colorblind", false)
	e.color = _col(t.get("colorblind") if cb and t.get("colorblind") != null else t.get("color"))
	e.outline = _col(t.get("colorblind_outline") if cb and t.get("colorblind_outline") != null else t.get("outline"), Color(0, 0, 0, 0))
	e.has_outline = e.outline.a > 0.0
	e.shadow = _col(t.get("shadow"), Color.BLACK)
	var so = t.get("shadow_offset", [2, 2])
	e.shadow_off = Vector2(so[0], so[1]) * REF_SCALE if so is Array else Vector2.ZERO
	e.follow = t.get("FollowSource", false)
	if e.follow and unit != null:
		e.follow_dy = world_pos.y - unit.global_position.y
	e.icon = _icons.get(icon) if icon != "" else null
	var isz = t.get("icon_size", [36.0, 36.0])
	var ioff = t.get("icon_offset", [0.0, 0.0])
	e.icon_size = (Vector2(isz[0], isz[1]) * REF_SCALE).round()
	e.icon_off = Vector2(ioff[0], ioff[1]) * REF_SCALE
	e.icon_right = icon == "gold"
	e.prio = prio
	e.line.clear()
	e.line.add_string(text, font, e.fs)
	e.tw = e.line.get_size().x
	e.asc = e.line.get_line_ascent()
	texts.append(e)
	return e


func update(dt: float) -> void:
	_clock += dt
	var n := texts.size()
	var w := 0
	for i in n:
		var e: Entry = texts[i]
		e.age += dt
		if e.age >= e.delay + e.decay:
			e.unit = null
			e.icon = null
			_pool.append(e)
			continue
		if e.age > 0.0:
			var t := minf(e.age, dt)
			e.off += e.vel * t + e.acc * (0.5 * t * t)
			e.vel += e.acc * t
			if e.follow and e.unit != null and is_instance_valid(e.unit):
				e.anchor = e.unit.global_position + Vector3(0, e.follow_dy, 0)
		texts[w] = e
		w += 1
	texts.resize(w)
	if _queue_t.size() > 64:
		for k in _queue_t.keys():
			if _queue_t[k] < _clock:
				_queue_t.erase(k)


func draw(ci: CanvasItem, cam: Camera3D) -> void:
	var rid := ci.get_canvas_item()
	for e in texts:
		if e.age < 0.0 or cam.is_position_behind(e.anchor):
			continue
		var p: Vector2 = cam.unproject_position(e.anchor) + e.off * REF_SCALE
		var a := 1.0 - clampf((e.age - e.delay) / e.decay, 0.0, 1.0)
		var s := 1.0
		if e.shrink_t > 0.0 and e.age < e.shrink_t:
			s = 1.0 + e.shrink_s * (1.0 - e.age / e.shrink_t)
		# text centred on p (icon included), baseline ~1/3 of the ascent below p
		var iw := e.icon_size.x * 0.75 if e.icon != null else 0.0
		var lx := -(e.tw + iw) * 0.5 + (0.0 if e.icon_right else iw)
		var base := Vector2(lx, e.asc * 0.35)
		ci.draw_set_transform(p.round(), 0.0, Vector2(s, s))
		if e.icon != null:
			var ip := Vector2(base.x + e.tw + 2.0 + e.icon_off.x, base.y - e.asc * 0.62 - e.icon_size.y * 0.5 + e.icon_off.y) if e.icon_right \
					else Vector2(base.x - e.icon_size.x * 0.82 + e.icon_off.x, base.y - e.asc * 0.4 - e.icon_size.y * 0.5 + e.icon_off.y)
			ci.draw_texture_rect(e.icon, Rect2(ip.round(), e.icon_size), false, Color(1, 1, 1, a))
		var sh := e.shadow
		sh.a *= a
		var top := base - Vector2(0, e.asc)   # TextLine draws from the top of the line box
		if e.has_outline:
			e.line.draw_outline(rid, top + e.shadow_off, OUTLINE_PX, sh)
			var o := e.outline
			o.a *= a
			e.line.draw_outline(rid, top, OUTLINE_PX, o)
		else:
			e.line.draw(rid, top + e.shadow_off, sh)
		var c := e.color
		c.a *= a
		e.line.draw(rid, top, c)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
