class_name ItemTip
extends RefCounted
## League-style item tooltip (shop hover, details, HUD inventory hover): header with icon / name / brief / price, then the
## item's own tooltip text from League's string table with coloured keywords (ItemText).

const C_BG := Color(0.004, 0.039, 0.075, 0.97)
const C_BORDER := Color(0.47, 0.35, 0.16)
const C_TITLE := Color(0.941, 0.902, 0.824)
const C_BRIEF := Color(0.42, 0.64, 0.87)
const C_GOLD := Color(0.94, 0.8, 0.42)
const C_GOLD_DIM := Color(0.62, 0.55, 0.42)
const C_RED := Color(0.92, 0.36, 0.3)

static var _rows: Dictionary = {}


static func rows_for(id: int, champ, px: int, width: float) -> Array:
	var ranged := ItemDB.champ_ranged(champ)
	var key := "%d_%d_%d_%d" % [id, 1 if ranged else 0, px, int(width)]
	if _rows.has(key):
		return _rows[key]
	var r := ItemText.rows(ItemDB.sections(id, ranged), Assets.font("spiegel", "Regular"), Assets.font("spiegel", "Bold"), px, width)
	_rows[key] = r
	return r


## Height of the description rows for the shop's details pane.
static func clear_cache() -> void:
	_rows.clear()


## Draw the tooltip for `id` next to `anchor`. `owned` = the owned Item (shows its sell value instead of the buy price).
static func draw(ci: CanvasItem, id: int, champ, anchor: Rect2, vs: Vector2, k: float, owned = null, above := true) -> void:
	if not ItemDB.has(id):
		return
	var f_title := Assets.font("beaufort", "Bold")
	var f_body := Assets.font("spiegel", "Regular")
	var f_bold := Assets.font("spiegel", "Bold")
	k = clampf(k, 0.75, 1.6)
	var w := roundf(360.0 * k)
	var pad := roundf(12.0 * k)
	var px := maxi(11, int(13.0 * k))
	var tpx := maxi(13, int(16.0 * k))
	var lh := px * 1.4
	var icon_sz := roundf(44.0 * k)
	var rws := rows_for(id, champ, px, w - pad * 2.0)
	var body_h := ItemText.height(rws, px)
	var head := maxf(icon_sz, tpx * 2.2)
	var h := pad * 2.0 + head + (pad * 0.7 + body_h if not rws.is_empty() else 0.0)
	var pos := Vector2(anchor.get_center().x - w * 0.5, anchor.position.y - h - 8.0 if above else anchor.end.y + 8.0)
	if above and pos.y < 4.0:
		pos.y = anchor.end.y + 8.0
	pos.x = clampf(pos.x, 4.0, vs.x - w - 4.0)
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vs.y - h - 4.0))
	var r := Rect2(pos, Vector2(w, h))
	ci.draw_rect(r, C_BG)
	ci.draw_rect(r, C_BORDER, false, 1.0)
	var icon := Assets.item_icon(id) if id != 9999 else Assets.augment_icon("ARAM_Stats")
	if icon != null:
		var ir := Rect2(pos + Vector2(pad, pad), Vector2(icon_sz, icon_sz))
		ci.draw_texture_rect(icon, ir, false)
		ci.draw_rect(ir, C_BORDER, false, 1.0)
	var tx := pos.x + pad + icon_sz + pad * 0.7
	ci.draw_string(f_title, Vector2(tx, pos.y + pad + tpx), ItemDB.name_of(id), HORIZONTAL_ALIGNMENT_LEFT, w - (tx - pos.x) - pad, tpx, C_TITLE)
	var brief := ItemDB.brief(id)
	var line2_y := pos.y + pad + tpx + lh
	if brief != "":
		ci.draw_string(f_body, Vector2(tx, line2_y), brief, HORIZONTAL_ALIGNMENT_LEFT, -1, px, C_BRIEF)
	# price (right aligned, coin icon)
	var price := ItemDB.cost_of(id)
	var label := ""
	var col := C_GOLD
	if owned != null:
		price = ItemDB.sell_price(owned)
		label = "Sells for "
	elif champ != null:
		var p := ItemDB.price_for(champ, id)
		price = p[0]
		col = C_GOLD if champ.gold >= price else C_GOLD_DIM
	var ptxt := "%s%d" % [label, price]
	var pw := f_bold.get_string_size(ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var coin := Vector2(px * 0.95, px * 0.85)
	var px_right := pos.x + w - pad
	ci.draw_string(f_bold, Vector2(px_right - pw, line2_y), ptxt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	HudLayout.region(ci, "itemshop_texture_atlas", Rect2(2, 2, 32, 28), Rect2(Vector2(px_right - pw - coin.x - 4, line2_y - coin.y + 1), coin))
	if owned == null and champ != null and price != ItemDB.cost_of(id):
		var tot := "Total cost %d" % ItemDB.cost_of(id)
		ci.draw_string(f_body, Vector2(px_right - f_body.get_string_size(tot, HORIZONTAL_ALIGNMENT_LEFT, -1, px - 1).x, line2_y + lh), tot, HORIZONTAL_ALIGNMENT_LEFT, -1, px - 1, C_GOLD_DIM)
	if not rws.is_empty():
		var by := pos.y + pad * 1.4 + head
		ci.draw_line(Vector2(pos.x + pad, by - pad * 0.45), Vector2(pos.x + w - pad, by - pad * 0.45), Color(C_BORDER.r, C_BORDER.g, C_BORDER.b, 0.6), 1.0)
		ItemText.draw(ci, rws, Vector2(pos.x + pad, by), px, f_body, f_bold)
