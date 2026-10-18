class_name VfxNode
extends Node3D
## Container for an effect. Frees itself after `lifetime` (<= 0 = manual).
## Trails (GPUParticles3D) can linger after the owner is gone via detach_and_fade().

var lifetime := 0.0
var trails: Array = []
var _age := 0.0
var follow: Node3D = null
var follow_offset := Vector3.ZERO


func _process(delta: float) -> void:
	_age += delta
	if follow != null:
		if is_instance_valid(follow):
			global_position = follow.global_position + follow_offset
		else:
			follow = null
			detach_and_fade()
	if lifetime > 0.0 and _age >= lifetime:
		detach_and_fade()


## Stop emitting, hide meshes, free when the trails have died out.
func detach_and_fade() -> void:
	set_process(false)
	var max_life := 0.0
	for c in get_children():
		if c is GPUParticles3D:
			c.emitting = false
			max_life = maxf(max_life, c.lifetime)
		elif c is MeshInstance3D or c is Light3D:
			c.visible = false
	var parent := get_parent()
	if max_life > 0.0 and parent != null and G.match != null and parent != G.match.fx_root:
		var gp := global_transform
		parent.remove_child(self)
		G.match.fx_root.add_child(self)
		global_transform = gp
	if max_life <= 0.0:
		queue_free()
		return
	var t := get_tree().create_timer(max_life + 0.1)
	t.timeout.connect(queue_free)
