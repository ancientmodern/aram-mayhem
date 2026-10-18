class_name FowMap
extends Node
## [fow] League fog-of-war visibility map. Two 256x256 half-float SubViewports ping-pong a shader pass
## (fow_update.gdshader) that rasters the player's team sight sources (champions, minions, turrets, structures; brush and
## terrain rules) and steps the stored visibility toward it at asymmetric reveal / hide speeds. The latest result is the
## global texture `fow_vis` that map, character and particle shaders sample (src/render/fow.gdshaderinc).
## CPU cost per update: one pass over the team's units writing <= 64 vec4s; the raster itself runs on the GPU.

const EXTENT := 128.775          ## meters = League light-grid extent 12877.525 units (Godot (x, z) = League (x, -z) * 0.01)
const RES := 256                 ## 0.5 m per texel
const MAX_SRC := 64
const UPDATE_HZ := 20.0
const REVEAL_PER_SEC := 7.0      ## fade.ps PARAMETERS.x: vision appears over ~0.15 s
const HIDE_PER_SEC := 2.2        ## fade.ps PARAMETERS.y: the fog creeps back over ~0.45 s

var m = null
var _vps: Array[SubViewport] = []
var _mats: Array[ShaderMaterial] = []
var _src := PackedVector4Array()
var _cur := 0                    ## viewport that renders on the next update
var _acc := 0.0
var _ticks := 0
var _on := false


func setup(p_match) -> void:
	m = p_match
	if DisplayServer.get_name() == "headless" or m.nav == null or m.nav.w == 0:
		return   # no GPU in headless runs
	if OS.get_cmdline_user_args().has("--nofow"):
		return   # debug: judge the scene without fog (reference-frame comparisons)
	var shader: Shader = load("res://src/render/fow_update.gdshader")
	var nav_tex := _nav_texture(m.nav)
	_src.resize(MAX_SRC)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(RES, RES)
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.use_hdr_2d = true
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		var rect := ColorRect.new()
		rect.size = Vector2(RES, RES)
		var sm := ShaderMaterial.new()
		sm.shader = shader
		sm.set_shader_parameter("nav", nav_tex)
		sm.set_shader_parameter("nav_rect", Vector4(m.nav.origin.x, m.nav.origin.y,
				1.0 / (m.nav.w * m.nav.cell), 1.0 / (m.nav.h * m.nav.cell)))
		sm.set_shader_parameter("extent", EXTENT)
		sm.set_shader_parameter("src", _src)
		rect.material = sm
		vp.add_child(rect)
		add_child(vp)
		_vps.append(vp)
		_mats.append(sm)
	_mats[0].set_shader_parameter("prev", _vps[1].get_texture())
	_mats[1].set_shader_parameter("prev", _vps[0].get_texture())


static func _nav_texture(nav: NavGrid) -> ImageTexture:
	var n := nav.w * nav.h
	var data := PackedByteArray()
	data.resize(n * 2)
	var has_brush := nav.brush.size() == n
	for i in n:
		data[i * 2] = 255 if nav.walk[i] == 1 else 0
		data[i * 2 + 1] = nav.brush[i] * 50 if has_brush else 0
	return ImageTexture.create_from_image(Image.create_from_data(nav.w, nav.h, false, Image.FORMAT_RG8, data))


func _process(delta: float) -> void:
	if _vps.is_empty() or m == null or m.paused:
		return
	var pl = G.player
	var pt: int = pl.team if pl != null and is_instance_valid(pl) else 2
	if pt > 1:
		if _on:
			_on = false
			RenderingServer.global_shader_parameter_set("fow_on", 0.0)
		return
	_acc += minf(delta, 0.1)
	if _acc < 1.0 / UPDATE_HZ:
		return
	var pf := Prof.t0()
	var dt: float = _acc * m.game_speed
	_acc = 0.0
	var n := _gather(pt)
	var mat := _mats[_cur]
	mat.set_shader_parameter("src", _src)
	mat.set_shader_parameter("src_count", n)
	mat.set_shader_parameter("step_rate", Vector2(REVEAL_PER_SEC * dt, HIDE_PER_SEC * dt))
	mat.set_shader_parameter("reset", 1.0 if _ticks < 2 else 0.0)
	_vps[_cur].render_target_update_mode = SubViewport.UPDATE_ONCE
	if _ticks > 0:
		# the other viewport finished last update: it is the freshest map
		RenderingServer.global_shader_parameter_set("fow_vis", _vps[1 - _cur].get_texture())
	if _ticks == 1 and not _on:
		_on = true
		RenderingServer.global_shader_parameter_set("fow_on", 1.0)
	_cur = 1 - _cur
	_ticks += 1
	Prof.add("fow", pf)


## Fills _src with the team's sight sources (champions and structures first, then minions); returns the count.
func _gather(team: int) -> int:
	var n := 0
	for pass_i in 2:
		for u in (m.champions if pass_i == 0 else m.units):
			if n >= MAX_SRC:
				return n
			if u.team != team or u.dead or (pass_i == 1 and u.kind == G.Kind.CHAMPION):
				continue
			var p: Vector3 = u.global_position
			var sight: float = u.sight_range() if u.has_method("sight_range") else 12.0
			_src[n] = Vector4(p.x, p.z, sight, float(maxi(u.in_brush, 0)))
			n += 1
	return n
