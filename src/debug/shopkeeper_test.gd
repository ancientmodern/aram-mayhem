extends Node
## Clicks the player's shopkeeper (Viking / Hermit) on screen and checks the shop opens.
## Usage: tools/preview.sh 120 -- --champ=Lux --harness=res://src/debug/shopkeeper_test.gd
var match_ref = null
var _done := false
var _t := 0.0


func _process(dt: float) -> void:
	_t += dt
	if _done or match_ref == null or _t < 3.0:
		return
	_done = true
	var cam: Camera3D = match_ref.camera_rig.cam
	var pc = match_ref.player_controller
	var sk = null
	for s in match_ref.shopkeepers:
		if s.team == G.player.team:
			sk = s
	if sk == null:
		print("SHOPKEEPER none for team ", G.player.team)
		get_tree().quit()
		return
	match_ref.camera_rig.locked = false
	match_ref.camera_rig.snap_to(sk.node.global_position)
	await get_tree().process_frame
	await get_tree().process_frame
	if match_ref.hud.shop_panel.visible:
		match_ref.hud.toggle_shop()
	print("SHOPKEEPER before click open=", match_ref.hud.shop_panel.visible)
	var sp := cam.unproject_position(sk.node.global_position + Vector3(0, 1.4, 0))
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	ev.position = sp
	ev.global_position = sp
	get_viewport().push_input(ev)
	await get_tree().process_frame
	print("SHOPKEEPER click at ", sp, " shop open=", match_ref.hud.shop_panel.visible)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shopkeeper_click.png")
	get_tree().quit()
