class_name TurretRangeRings
extends Node3D
## League's turret range indicator: a thin, smooth red ring that fades in only while the player is near an
## ENEMY turret (no filled disc). When that turret is targeting the player the ring brightens and thickens
## (League's turret-aggro warning; the targeting line itself is drawn by WorldOverlay).

const SHOW_MARGIN := 4.0      ## metres outside the range where the ring starts fading in
const POOL := 3

var match_ref = null
var _rings: Array = []


func _ready() -> void:
	for i in POOL:
		var mi := Vfx.indicator_mesh(4, Color(1.0, 0.16, 0.1, 0.0))
		mi.visible = false
		add_child(mi)
		_rings.append(mi)


func _process(dt: float) -> void:
	var p: Unit = G.player
	var used := 0
	if match_ref != null and p != null and not p.dead:
		for s in match_ref.structures:
			if used >= POOL:
				break
			if s.kind != G.Kind.TURRET or s.dead or s.team == p.team or s.get("tier") == Turret.Tier.FOUNTAIN:
				continue
			var r: float = s.attack_range_m() + s.radius
			var d := G.flat_dist(p.global_position, s.global_position)
			if d > r + SHOW_MARGIN:
				continue
			var mi: MeshInstance3D = _rings[used]
			used += 1
			var aggro: bool = s.aggro_line_target == p
			var a := clampf((r + SHOW_MARGIN - d) / (SHOW_MARGIN * 0.6), 0.0, 1.0)
			var k: float = mi.get_meta("aggro_k", 0.0)
			k = move_toward(k, 1.0 if aggro else 0.0, dt * 6.0)
			mi.set_meta("aggro_k", k)
			var mat: ShaderMaterial = mi.material_override
			mat.set_shader_parameter("color", Color(1.0, lerpf(0.18, 0.08, k), lerpf(0.12, 0.05, k), a * lerpf(0.75, 1.0, k)))
			mat.set_shader_parameter("energy", lerpf(1.0, 1.8, k))
			mat.set_shader_parameter("ring_px", lerpf(1.6, 2.6, k))
			mat.set_shader_parameter("ring_glow", lerpf(0.08, 0.3, k))
			var gp: Vector3 = s.global_position
			mi.global_position = Vector3(gp.x, p.global_position.y + 0.08, gp.z)
			mi.scale = Vector3(r * 2.0, 1.0, r * 2.0)
			mi.visible = true
	for i in range(used, POOL):
		_rings[i].visible = false
