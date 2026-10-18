class_name HudTooltip
extends RefCounted
## League-style tooltips (items, abilities, buffs, stats) shared by the HUD, shop and scoreboard.
## A tooltip is a Dictionary built once per hover target:
##   {title, icon, cost (int, -1 none), sub (String), lines: [[text, color, bold]], key (String)}
## and drawn with draw(); wrapped lines are cached inside the dictionary.

const C_BG := Color(0.004, 0.039, 0.075, 0.96)          # #010A13
const C_BORDER := Color(0.47, 0.35, 0.16)               # #785A28
const C_BORDER_HI := Color(0.784, 0.667, 0.431)         # #C8AA6E
const C_TITLE := Color(0.941, 0.902, 0.824)             # #F0E6D2
const C_TEXT := Color(0.647, 0.627, 0.588)              # body grey #A5A096
const C_STAT := Color(0.941, 0.902, 0.824)
const C_GOLD := Color(0.784, 0.667, 0.431)
const C_PASSIVE := Color(0.95, 0.92, 0.85)
const C_SUB := Color(0.42, 0.64, 0.87)                  # cooldown / cost line
const C_WARN := Color(0.92, 0.36, 0.3)

static var _re_tags: RegEx = null


static func clean(s: String) -> String:
	if _re_tags == null:
		_re_tags = RegEx.create_from_string("<[^>]+>")
	return _re_tags.sub(s.replace("<br>", "\n").replace("<br/>", "\n"), "", true)


static func item(id: int, champ = null, owned = null) -> Dictionary:
	var t := {"key": "item%d" % id, "title": ItemDB.name_of(id), "icon": Assets.item_icon(id) if id != 9999 else Assets.augment_icon("ARAM_Stats"),
		"cost": ItemDB.cost_of(id), "lines": [], "item_id": id, "owned": owned}   # [shop] item_id/owned -> ItemTip draws League's own text
	if champ != null and owned == null:
		var p := ItemDB.price_for(champ, id)
		t.cost = p[0]
		if p[0] != ItemDB.cost_of(id):
			t["sub"] = "Total cost %d" % ItemDB.cost_of(id)
	elif owned != null:
		t["sub"] = "Sells for %d" % int(owned.cost * 0.7)
	if not ItemDB.has(id):
		return t
	var st: Dictionary = ItemDB.CAT[id][2]
	for k in st:
		t.lines.append([ItemDB.stat_line(k, st[k]).substr(1), C_STAT, false])
	var desc: String = ItemDB.CAT[id][7]
	if desc != "":
		if not st.is_empty():
			t.lines.append(["", C_TEXT, false])
		# "Name: text" -> League puts the passive name on its own bold line
		var ci := desc.find(": ")
		if ci > 0 and ci < 32:
			t.lines.append([desc.substr(0, ci), C_PASSIVE, true])
			t.lines.append([desc.substr(ci + 2), C_TEXT, false])
		else:
			t.lines.append([desc, C_TEXT, false])
	if owned != null and owned.has_method("has_active") and owned.has_active():
		t.lines.append(["", C_TEXT, false])
		t.lines.append(["Active cooldown: %ds" % int(owned.active_cd), C_SUB, false])
	return t


static func ability(champ, key: String) -> Dictionary:
	if key == "P":
		var info: Dictionary = ChampionDB.client_data(champ.alias).get("passive", {})
		var p = champ.passive
		return {"key": "P", "title": info.get("name", "Passive"), "icon": p.icon if p != null and p.get("icon") != null else Assets.ability_icon(champ.alias, "p"),
			"cost": -1, "sub": "Passive", "lines": [[clean(info.get("description", "")), C_TEXT, false]]}
	var ab: Ability = champ.ability("QWER".find(key)) if key in ["Q", "W", "E", "R"] else champ.summoners[0 if key == "D" else 1]
	if ab == null:
		return {}
	var sub := ""
	if not ab.is_summoner:
		sub = "Rank %d/%d" % [ab.level, ab.max_level]
	var cdv := 0.0
	if ab.is_summoner:
		cdv = ab.base_cooldown()
	elif ab.level > 0:
		cdv = champ.stats.cooldown(ab.base_cooldown(), ab.is_ult)
	if cdv > 0.0:
		sub += ("   " if sub != "" else "") + "Cooldown: %s" % _num(cdv)
	if ab.cost() > 0.0 and champ.stats.uses_mana:
		sub += "   Cost: %d %s" % [int(ab.cost()), champ.resource_name]
	var lines := []
	for para in clean(ab.tooltip_text()).split("\n"):
		lines.append([para, C_TEXT, false])
	return {"key": key, "title": ab.display_name + ("  [%s]" % key), "icon": ab.icon, "cost": -1, "sub": sub, "lines": lines}


static func buff(b) -> Dictionary:
	var lines := []
	if b.description != "":
		lines.append([clean(b.description), C_TEXT, false])
	if not b.permanent and b.duration > 0.0:
		lines.append(["%.1fs remaining" % b.remaining, C_SUB, false])
	return {"key": "buff" + b.id, "title": b.display_name, "icon": b.icon, "cost": -1, "lines": lines,
		"border": C_WARN if b.is_debuff else C_BORDER}


static func simple(title: String, body: String) -> Dictionary:
	return {"key": title, "title": title, "cost": -1, "lines": [[body, C_TEXT, false]] if body != "" else []}


static func _num(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.05 else "%.1f" % v


## Draw `t` above (or below) `anchor` (screen rect of the hovered element), clamped to the viewport.
static func draw(ci: CanvasItem, t: Dictionary, anchor: Rect2, vs: Vector2, k: float, above := true) -> void:
	if t.is_empty():
		return
	if t.has("item_id") and ItemDB.has(int(t.item_id)):   # [shop] rich League item tooltip (src/items/item_tip.gd)
		ItemTip.draw(ci, int(t.item_id), G.player, anchor, vs, k, t.get("owned"), above)
		return
	var f_title := Assets.font("beaufort", "Bold")
	var f_body := Assets.font("spiegel", "Regular")
	var f_bold := Assets.font("spiegel", "Bold")
	k = clampf(k, 0.75, 1.6)
	var w := roundf(340.0 * k)
	var pad := roundf(12.0 * k)
	var px := maxi(11, int(13.0 * k))
	var tpx := maxi(13, int(16.0 * k))
	var lh := roundf(px * 1.42)
	var icon_sz := roundf(44.0 * k) if t.get("icon") != null else 0.0
	var wkey := "_wrap%d" % px
	if not t.has(wkey):
		var out := []
		for ln in t.lines:
			var f: Font = f_bold if ln[2] else f_body
			if String(ln[0]) == "":
				out.append(["", ln[1], f])
				continue
			for wl in wrap_text(String(ln[0]), f, px, w - pad * 2.0):
				out.append([wl, ln[1], f])
		t[wkey] = out
	var lines: Array = t[wkey]
	var head := maxf(icon_sz, tpx + (lh if t.get("sub", "") != "" or t.get("cost", -1) >= 0 else 0.0))
	var h := pad * 2.0 + head + (pad * 0.8 + lines.size() * lh if not lines.is_empty() else 0.0)
	var pos := Vector2(anchor.get_center().x - w * 0.5, anchor.position.y - h - 8.0 if above else anchor.end.y + 8.0)
	if above and pos.y < 4.0:
		pos.y = anchor.end.y + 8.0
	pos.x = clampf(pos.x, 4.0, vs.x - w - 4.0)
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vs.y - h - 4.0))
	var r := Rect2(pos, Vector2(w, h))
	ci.draw_rect(r, C_BG)
	ci.draw_rect(r, t.get("border", C_BORDER), false, 1.0)
	ci.draw_rect(r.grow(-2.0), Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.35), false, 1.0)
	var x := r.position.x + pad
	var y := r.position.y + pad
	if icon_sz > 0.0:
		var ir := Rect2(x, y, icon_sz, icon_sz)
		ci.draw_texture_rect(t.icon, ir, false)
		ci.draw_rect(ir, C_BORDER, false, 1.0)
		x += icon_sz + pad * 0.8
	var ty := y + f_title.get_ascent(tpx)
	ci.draw_string(f_title, Vector2(x, ty), String(t.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - x - pad, tpx, C_TITLE)
	var sy := ty + lh
	var sx := x
	if t.get("cost", -1) >= 0:
		var coin := Rect2(sx, sy - px * 0.85, px * 0.95, px * 0.85)
		HudLayout.region(ci, "itemshop_texture_atlas", Rect2(2, 2, 32, 28), coin)
		sx += coin.size.x + 4.0
		var cs := str(t.cost)
		ci.draw_string(f_bold, Vector2(sx, sy), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, px, C_GOLD)
		sx += f_bold.get_string_size(cs, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 10.0
	if t.get("sub", "") != "":
		ci.draw_string(f_body, Vector2(sx, sy), String(t.sub), HORIZONTAL_ALIGNMENT_LEFT, r.end.x - sx - pad, px, C_SUB)
	y = r.position.y + pad + head + pad * 0.8
	if not lines.is_empty():
		ci.draw_line(Vector2(r.position.x + pad, y - pad * 0.45), Vector2(r.end.x - pad, y - pad * 0.45), Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.6), 1.0)
	for ln in lines:
		y += lh
		if ln[0] != "":
			ci.draw_string(ln[2], Vector2(r.position.x + pad, y - lh * 0.28), ln[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px, ln[1])


static func wrap_text(text: String, f: Font, px: int, width: float) -> Array:
	var out := []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" "):
			var test := word if line == "" else line + " " + word
			if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width and line != "":
				out.append(line)
				line = word
			else:
				line = test
		out.append(line)
	return out
