class_name FloatingTextSystem
extends RefCounted
## League floating combat text, driven by League's own FloatingTextTypeData + font descriptions
## (UI.wad bins, extracted to assets/ui/world/floating_text.json by tools/lol/extract_world_ui.py).
## Motion is League's: screen-space start offset, random X/Y launch velocity (pixels/s at the 1600x1200 UI
## reference), a constant "ContinualForce" (gravity), alternating left/right per target, a short shrink-in,
## then a linear fade over `Decay` seconds after `DecayDelay`.

const MAX_TEXTS := 120
const REF_SCALE := 1080.0 / 1200.0   ## League UI reference is 1200 px tall; our canvas is 1080 tall

var types := {}
var texts: Array = []
var font: Font
var _alt := {}                      ## target instance id -> next horizontal direction
var _icons := {}


func _init() -> void:
	font = Assets.font("spiegel", "Bold")
	var path := "res://assets/ui/world/floating_text.json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			types = d
	for k in ["physical", "magic", "true"]:
		_icons["crit_" + k] = load("res://assets/ui/world/ft_crit_%s.png" % k)
	_icons["gold"] = load("res://assets/ui/world/ft_gold.png")


static func _col(a, fallback: Color = Color.WHITE) -> Color:
	if a is Array and a.size() >= 3:
		return Color8(int(a[0]), int(a[1]), int(a[2]), int(a[3]) if a.size() > 3 else 255)
	return fallback


## Spawn one text of League type `tname` (e.g. "PhysicalDamage", "MagicalDamageCritical", "Heal", "Gold").
func spawn(tname: String, text: String, unit: Node3D, world_pos: Vector3, icon: String = "") -> void:
	var t: Dictionary = types.get(tname, types.get("PhysicalDamage", {}))
	var dir := 1.0
	if t.get("AlternateRightLeft", false) and unit != null:
		var id := unit.get_instance_id()
		dir = _alt.get(id, 1.0)
		_alt[id] = -dir
	var vx := G.rng.randf_range(float(t.get("MinXVelocity", 0.0)), float(t.get("MaxXVelocity", 0.0))) * dir
	var vy := -G.rng.randf_range(float(t.get("MinYVelocity", 0.0)), float(t.get("MaxYVelocity", 0.0)))
	var e := {
		"text": text, "unit": unit, "anchor": world_pos, "age": 0.0,
		"off": Vector2(float(t.get("StartOffsetX", 0.0)) * dir, -float(t.get("StartOffsetY", 0.0))),
		"vel": Vector2(vx, vy),
		"acc": Vector2(float(t.get("ContinualForceX", 0.0)) * dir, float(t.get("ContinualForceY", 0.0))),
		"delay": float(t.get("DecayDelay", 0.4)), "decay": maxf(float(t.get("Decay", 0.45)), 0.05),
		"scale": float(t.get("Scale", 1.0)), "shrink_t": float(t.get("ShrinkTime", 0.0)),
		"shrink_s": float(t.get("ShrinkScale", 0.0)),
		"size": float(t.get("size", 27)), "color": _col(t.get("color")),
		"outline": _col(t.get("outline"), Color(0, 0, 0, 0)), "outline_size": int(t.get("outline_size", 1)),
		"shadow": _col(t.get("shadow"), Color(0, 0, 0, 0)), "follow": t.get("FollowSource", false),
		"icon": icon, "icon_size": t.get("icon_size", [36.0, 36.0]), "icon_off": t.get("icon_offset", [0.0, 0.0]),
		"prio": int(t.get("Priority", 6)),
	}
	if e.shadow.a > 0.0 and t.get("shadow_offset") is Array:
		e["shadow_off"] = Vector2(t.shadow_offset[0], t.shadow_offset[1])
	texts.append(e)
	if texts.size() > MAX_TEXTS:
		# drop the least important (highest Priority value), oldest first
		var worst := 0
		for i in texts.size():
			if texts[i].prio > texts[worst].prio:
				worst = i
		texts.remove_at(worst)


func update(dt: float) -> void:
	for e in texts:
		e.age += dt
		e.off += e.vel * dt + e.acc * (0.5 * dt * dt)
		e.vel += e.acc * dt
		if e.follow and e.unit != null and is_instance_valid(e.unit):
			e.anchor = e.unit.global_position + Vector3(0, e.anchor.y - e.unit.global_position.y, 0)
	texts = texts.filter(func(e): return e.age < e.delay + e.decay)


func draw(ci: CanvasItem, cam: Camera3D) -> void:
	for e in texts:
		if cam.is_position_behind(e.anchor):
			continue
		var p: Vector2 = cam.unproject_position(e.anchor) + e.off * REF_SCALE
		var a := 1.0 - clampf((e.age - e.delay) / e.decay, 0.0, 1.0)
		var s: float = e.scale
		if e.shrink_t > 0.0 and e.age < e.shrink_t:
			s *= 1.0 + e.shrink_s * (1.0 - e.age / e.shrink_t)
		var fs := maxi(int(round(e.size * s * REF_SCALE)), 6)
		var ts := font.get_string_size(e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var icon_w := 0.0
		var tex: Texture2D = _icons.get(e.icon) if e.icon != "" else null
		var isz := Vector2.ZERO
		if tex != null:
			isz = Vector2(e.icon_size[0], e.icon_size[1]) * REF_SCALE * s / maxf(e.scale, 0.01)
			icon_w = isz.x * 0.75
		var pos: Vector2 = (p - Vector2((ts.x + icon_w) * 0.5 - icon_w, -ts.y * 0.3)).round()
		if tex != null:
			var icon_on_right: bool = e.icon == "gold"
			var ip := Vector2(pos.x + ts.x + 2.0, pos.y - ts.y * 0.62 - isz.y * 0.5 + e.icon_off[1]) if icon_on_right \
					else Vector2(pos.x - isz.x * 0.82 + e.icon_off[0], pos.y - ts.y * 0.35 - isz.y * 0.5 + e.icon_off[1])
			ci.draw_texture_rect(tex, Rect2(ip.round(), isz), false, Color(1, 1, 1, a))
		var c: Color = e.color
		if e.has("shadow_off"):
			var sh: Color = e.shadow
			ci.draw_string(font, pos + e.shadow_off * REF_SCALE, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(sh.r, sh.g, sh.b, sh.a * a))
		if e.outline.a > 0.0:
			var o: Color = e.outline
			ci.draw_string_outline(font, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, e.outline_size * 3), Color(o.r, o.g, o.b, o.a * a))
		ci.draw_string(font, pos, e.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(c.r, c.g, c.b, c.a * a))
