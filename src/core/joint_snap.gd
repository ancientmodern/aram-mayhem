extends SkeletonModifier3D
## [anim-events] League JointSnapEventData: while the event is active, a joint (mJointNameToOverride, e.g. Yasuo's
## Sword / Sheath, Ahri's orb Weapon, Leona's sword) takes the pose of an animated snap joint
## (mJointNameToSnapTo, e.g. Sword2LHandSheath, Weapon_World_Snap). The clips key those snap joints exactly where
## League's runtime puts the prop; plain FK of the overridden joint would leave it where its own keys say.
## Created on a unit's skeleton the first time one of its clips snaps a joint; runs after WeaponHold.

var skel: Skeleton3D
var pairs: Array = []         ## [override bone idx, snap bone idx, owner key]


func add(over: int, snap: int, key) -> void:
	pairs.append([over, snap, key])
	active = true


func remove_key(key) -> void:
	var i := 0
	while i < pairs.size():
		if is_same(pairs[i][2], key):
			pairs.remove_at(i)
		else:
			i += 1
	active = not pairs.is_empty()


func clear() -> void:
	pairs.clear()
	active = false


func _process_modification_with_delta(_delta: float) -> void:
	if skel == null:
		return
	for p in pairs:
		var over: int = p[0]
		var g: Transform3D = skel.get_bone_global_pose(int(p[1]))
		var par := skel.get_bone_parent(over)
		var local := g
		if par >= 0:
			local = skel.get_bone_global_pose(par).affine_inverse() * g
		skel.set_bone_pose_position(over, local.origin)
		skel.set_bone_pose_rotation(over, local.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(over, local.basis.get_scale())
