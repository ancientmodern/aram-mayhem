class_name ItemText
extends RefCounted
## League's item tooltip markup (<passive>, <attention>, <magicDamage>, <br>, <section> ...) -> coloured, word-wrapped rows.
## The markup itself comes from the game's own string table (data/items/items.json "text"), resolved by tools/lol/extract_items.py.
##
##   var rows := ItemText.rows(sections, f_body, f_bold, px, width)   # wrapped once, cache it
##   var h := ItemText.height(rows, px)
##   ItemText.draw(ci, rows, pos, px)                                   # y grows downwards from pos.y

const C_BODY := Color(0.78, 0.76, 0.71)
const C_ATTN := Color(1.0, 0.93, 0.66)
const C_PASSIVE := Color(1.0, 0.78, 0.36)
const C_ACTIVE := Color(1.0, 0.78, 0.36)
const C_MAGIC := Color(0.42, 0.72, 1.0)
const C_PHYS := Color(1.0, 0.55, 0.2)
const C_TRUE := Color(1.0, 1.0, 1.0)
const C_HEAL := Color(0.45, 0.92, 0.55)
const C_SHIELD := Color(0.82, 0.88, 0.95)
const C_SPEED := Color(1.0, 0.96, 0.45)
const C_STATUS := Color(0.9, 0.72, 0.45)
const C_RULES := Color(0.58, 0.56, 0.52)
const C_FLAVOR := Color(0.55, 0.53, 0.5)
const C_GOLD := Color(0.94, 0.8, 0.42)

## tag -> [colour, bold]
const STYLE := {
	"attention": [C_ATTN, true], "passive": [C_PASSIVE, true], "active": [C_ACTIVE, true], "unique": [C_PASSIVE, true],
	"magicDamage": [C_MAGIC, false], "physicalDamage": [C_PHYS, false], "trueDamage": [C_TRUE, false],
	"healing": [C_HEAL, false], "shield": [C_SHIELD, false], "speed": [C_SPEED, false], "status": [C_STATUS, false],
	"keyword": [C_STATUS, false], "keywordMajor": [C_STATUS, true], "keywordStealth": [C_STATUS, false],
	"rules": [C_RULES, false], "OnHit": [Color(1.0, 0.72, 0.3), true], "gold": [C_GOLD, true], "flavorText": [C_FLAVOR, false],
	"scaleAP": [C_MAGIC, false], "scaleAD": [C_PHYS, false], "scaleArmor": [Color(0.95, 0.8, 0.4), false],
	"scaleMR": [Color(0.7, 0.62, 1.0), false], "scaleHealth": [C_HEAL, false], "scaleMana": [Color(0.5, 0.65, 1.0), false],
	"scaleLevel": [C_ATTN, false], "lifeSteal": [Color(0.9, 0.35, 0.4), false], "recast": [C_PASSIVE, false],
}

static var _re_tag: RegEx = null


static func _tag_re() -> RegEx:
	if _re_tag == null:
		_re_tag = RegEx.create_from_string("<(/?)([A-Za-z0-9_]+)\\s*/?>")
	return _re_tag


## Markup -> plain text (paragraph breaks kept as "\n").
static func plain(s: String) -> String:
	var t := s.replace("<br>", "\n").replace("<br/>", "\n").replace("<li>", "\n- ").replace("</li>", "")
	t = _tag_re().sub(t, "", true)
	while t.contains("\n\n\n"):
		t = t.replace("\n\n\n", "\n\n")
	return t.strip_edges().replace("&nbsp;", " ")


## Parse one section's markup into paragraphs; each paragraph = Array of [text, colour, bold].
static func paragraphs(markup: String, base_col := C_BODY, base_bold := false) -> Array:
	var out := []
	var cur := []
	var stack: Array = []        # open tag names
	var pos := 0
	var re := _tag_re()
	for m in re.search_all(markup):
		var txt := markup.substr(pos, m.get_start() - pos)
		if txt != "":
			cur.append(_span(txt, stack, base_col, base_bold))
		pos = m.get_end()
		var closing := m.get_string(1) == "/"
		var name := m.get_string(2)
		if name == "br":
			out.append(cur)
			cur = []
		elif name == "li":
			if not closing:
				out.append(cur)
				cur = [["• ", base_col, false]]
		elif closing:
			var i := stack.rfind(name)
			if i >= 0:
				stack.remove_at(i)
		else:
			stack.append(name)
	var tail := markup.substr(pos)
	if tail != "":
		cur.append(_span(tail, stack, base_col, base_bold))
	out.append(cur)
	return out


static func _span(txt: String, stack: Array, base_col: Color, base_bold: bool) -> Array:
	var col := base_col
	var bold := base_bold
	for i in range(stack.size() - 1, -1, -1):
		var st = STYLE.get(stack[i])
		if st != null:
			col = st[0]
			bold = bold or st[1]
			break
	for tg in stack:
		var st2 = STYLE.get(tg)
		if st2 != null and st2[1]:
			bold = true
	return [txt.replace("&nbsp;", " "), col, bold]


## Wrap sections ([markup, ...]) into rows. Row = {"spans": [[text, colour, bold], ...], "gap": bool}.
## Empty sections are skipped; a gap row separates sections.
static func rows(sections: Array, f_body: Font, f_bold: Font, px: int, width: float) -> Array:
	var out := []
	var first := true
	for sec in sections:
		var s := String(sec).strip_edges()
		if s == "" or s == "<flavorText></flavorText>":
			continue
		if not first:
			out.append({"spans": [], "gap": true})
		first = false
		var base_col := C_BODY
		if s.begins_with("<flavorText>"):
			base_col = C_FLAVOR
		for para in paragraphs(s, base_col):
			if para.is_empty():
				out.append({"spans": [], "gap": true})
				continue
			_wrap_para(para, f_body, f_bold, px, width, out)
	# trim leading/trailing gaps
	while not out.is_empty() and out[out.size() - 1].gap:
		out.pop_back()
	return out


static func _wrap_para(para: Array, f_body: Font, f_bold: Font, px: int, width: float, out: Array) -> void:
	var line := []
	var x := 0.0
	for sp in para:
		var f: Font = f_bold if sp[2] else f_body
		# split into words keeping the trailing space
		var words: PackedStringArray = String(sp[0]).split(" ")
		for wi in words.size():
			var w: String = words[wi] + (" " if wi < words.size() - 1 else "")
			if w == "":
				continue
			var ww := f.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if x + f.get_string_size(w.strip_edges(false, true), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width and not line.is_empty():
				out.append({"spans": line, "gap": false})
				line = []
				x = 0.0
			if not line.is_empty() and line[line.size() - 1][1] == sp[1] and line[line.size() - 1][2] == sp[2]:
				line[line.size() - 1][0] += w
			else:
				line.append([w, sp[1], sp[2]])
			x += ww
	if not line.is_empty():
		out.append({"spans": line, "gap": false})


static func height(rws: Array, px: int) -> float:
	var lh := px * 1.4
	var h := 0.0
	for r in rws:
		h += lh * (0.45 if r.gap else 1.0)
	return h


## Draw rows with y = pos.y being the top of the first line. Returns the bottom y.
static func draw(ci: CanvasItem, rws: Array, pos: Vector2, px: int, f_body: Font, f_bold: Font, alpha := 1.0, max_y := 1e9) -> float:
	var lh := px * 1.4
	var y := pos.y
	for r in rws:
		if r.gap:
			y += lh * 0.45
			continue
		if y + lh > max_y:
			break
		var x := pos.x
		for sp in r.spans:
			var f: Font = f_bold if sp[2] else f_body
			var c: Color = sp[1]
			c.a *= alpha
			ci.draw_string(f, Vector2(x, y + px), sp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px, c)
			x += f.get_string_size(sp[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		y += lh
	return y
