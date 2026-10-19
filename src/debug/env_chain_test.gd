extends Node
## [env-look] Proves the 3D colour chain is exact: shader value == screenshot pixel.
## Usage: tools/preview.sh 120 -- --champ=Ezreal --nofow --harness=res://src/debug/env_chain_test.gd
## Puts patches in front of the camera (screen-space quads, no lighting from Godot):
##   A: unshaded quad that writes a known gamma colour (with gamma_out = 1 shaders write gamma values)
##   B: quads using the real map shader (map_lightmap.gdshader, league_exact) with 1x1 diffuse / lightmap textures
##      (lightmap alpha 0 = no sun term) -> expected League value overlay(d, 0.5) * lm * 2 = d * lm * 2
## Prints ENVCHAIN lines (expected vs read back, 0-255) and exits.
var match_ref = null
var main = null

const UNLIT := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, fog_disabled;
uniform vec3 col;
void vertex() { POSITION = vec4(VERTEX.xy, 0.0, 1.0); }
void fragment() { ALBEDO = col; }
"""

const MAP_SHADER := preload("res://src/vfx/shaders/map_lightmap.gdshader")


func _ready() -> void:
	_run()


func _tex(c: Color) -> ImageTexture:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


## screen rect quad (clip space) as a MeshInstance3D
func _quad(x0: float, y0: float, x1: float, y1: float, mat: Material, cam: Camera3D = null) -> MeshInstance3D:
	# with cam: real geometry 2 m in front of the camera covering that clip-space rect (for shaders without vertex())
	var hh := 1.0
	var hw := 1.0
	var z := 0.0
	if cam != null:
		z = -2.0
		hh = 2.0 * tan(deg_to_rad(cam.fov) * 0.5)
		var vs := get_viewport().get_visible_rect().size
		hw = hh * vs.x / vs.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y0), Vector2(x1, y1), Vector2(x0, y1)]:
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0.5, 0.5))
		st.set_uv2(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(v.x * hw, v.y * hh, z))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _run() -> void:
	await get_tree().create_timer(2.0, true, false, true).timeout
	if match_ref != null and match_ref.hud != null:
		match_ref.hud.visible = false
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := get_viewport().get_camera_3d()
	var holder := Node3D.new()
	cam.add_child(holder)
	var gammas := [Color8(20, 40, 60), Color8(64, 128, 192), Color8(200, 150, 100), Color8(250, 250, 250), Color8(128, 128, 128)]
	var cases: Array = []   # [px rect center, expected Color8]
	var sh := Shader.new()
	sh.code = UNLIT
	for i in gammas.size():
		var m := ShaderMaterial.new()
		m.shader = sh
		var g: Color = gammas[i]
		m.set_shader_parameter("col", Vector3(g.r, g.g, g.b))
		var x0 := -0.9 + i * 0.36
		holder.add_child(_quad(x0, 0.3, x0 + 0.3, 0.8, m))
		cases.append(["unlit", Vector2((x0 + 0.15 + 1.0) * 0.5, (0.55 + 1.0) * 0.5), g])   # clip y is flipped (Vulkan)
	# map shader, exact path: diffuse d, lightmap lm (alpha 0 = sun masked out)
	var pairs := [[Color8(100, 120, 140), Color8(70, 75, 85, 0)], [Color8(60, 110, 160), Color8(90, 95, 110, 0)],
		[Color8(180, 190, 200), Color8(110, 115, 125, 0)], [Color8(30, 60, 90), Color8(127, 127, 127, 0)]]
	for i in pairs.size():
		var m := ShaderMaterial.new()
		m.shader = MAP_SHADER
		m.set_shader_parameter("diffuse_tex", _tex(pairs[i][0]))
		m.set_shader_parameter("lightmap_tex", _tex(pairs[i][1]))
		m.set_shader_parameter("tint", Color(0.5, 0.5, 0.5, 1.0))
		var x0 := -0.9 + i * 0.45
		var mi := _quad(x0, 0.3, x0 + 0.35, 0.8, m, cam)
		mi.layers = 2
		holder.add_child(mi)
		var d: Color = pairs[i][0]
		var l: Color = pairs[i][1]
		var e := Color(minf(d.r * l.r * 2.0, 1.0), minf(d.g * l.g * 2.0, 1.0), minf(d.b * l.b * 2.0, 1.0))
		cases.append(["map", Vector2((x0 + 0.175 + 1.0) * 0.5, 1.0 - (0.55 + 1.0) * 0.5), e])
	for k in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sz := Vector2(img.get_width(), img.get_height())
	var worst := 0.0
	for c in cases:
		var p: Vector2 = c[1] * sz
		var got := img.get_pixelv(Vector2i(p))
		var e: Color = c[2]
		var dv := maxf(absf(got.r - e.r), maxf(absf(got.g - e.g), absf(got.b - e.b))) * 255.0
		worst = maxf(worst, dv)
		print("ENVCHAIN %s expected (%d,%d,%d) got (%d,%d,%d) diff %.1f" % [c[0], e.r8, e.g8, e.b8, got.r8, got.g8, got.b8, dv])
	print("ENVCHAIN worst diff %.1f (0-255)" % worst)
	var d := "user://envlook_chain"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	img.save_png(d + "/chain.png")
	get_tree().quit()
