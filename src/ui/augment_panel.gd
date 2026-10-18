class_name AugmentPanel
extends Control
## Augment selection screen (placeholder, replaced by the full implementation).

var hud = null


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func toggle() -> void:
	pass


func in_combat(c) -> bool:
	return c.match_ref != null and c.match_ref.time - c.last_combat_time < 4.0
