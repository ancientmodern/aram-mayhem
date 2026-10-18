extends SkeletonModifier3D
## [motion3] Keeps hand-held weapons in the hand.
## Several League cast clips (Lux R / Q, Darius Q / E, Sona R ...) key the weapon bone (a root-level or
## hand-child "Weapon" joint) far away from the hand for a few frames: League's runtime shows the weapon
## in the hand there, but straight FK from the exported keys leaves it floating a body-length away.
## This modifier measures, once per model, how far each weapon bone strays from its hand in the ordinary
## clips (idle / run / attack / crit), then eases the weapon back onto its idle grip (hand-local rest
## transform) whenever it strays well beyond that. Clips that behave are untouched (weight 0).

var skel: Skeleton3D
## [{w: bone idx, h: idle hand bone idx, hands: all hand bones, n: Transform3D (weapon in hand space at idle), t1: float, t2: float}]
var items: Array = []


func _process_modification_with_delta(_delta: float) -> void:
	_hold()


func _hold() -> void:
	if skel == null:
		return
	for it in items:
		var w: int = it.w
		var gh: Transform3D = skel.get_bone_global_pose(it.h)
		var gw: Transform3D = skel.get_bone_global_pose(w)
		var d := INF
		for h in it.hands:
			d = minf(d, (skel.get_bone_global_pose(h).origin - gw.origin).length())
		if d <= it.t1:
			continue
		var k := smoothstep(it.t1, it.t2, d)
		var target: Transform3D = gh * it.n
		var blended := gw.interpolate_with(target, k)
		var par := skel.get_bone_parent(w)
		var local := blended
		if par >= 0:
			local = skel.get_bone_global_pose(par).affine_inverse() * blended
		skel.set_bone_pose_position(w, local.origin)
		skel.set_bone_pose_rotation(w, local.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(w, local.basis.get_scale())
