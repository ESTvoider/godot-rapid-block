@tool
class_name RbIntegrationTest
extends RefCounted
## 插件集成测试：验证放置模式激活、幽灵预览、视口点击放置与布尔挖除全链路。
## 通过编辑器脚本调用：load("res://addons/rapid_block/tests/rb_integration_test.gd").run()


static func run() -> void:
	var editor := EditorInterface
	var scene_root := editor.get_edited_scene_root()
	if scene_root == null:
		print("RB_TEST: no scene root")
		return
	var plugin := _find_plugin(editor)
	if plugin == null:
		print("RB_TEST: plugin not found")
		return
	print("RB_TEST: plugin found, place_active = ", plugin.place_active)
	plugin.current_shape.shape_type = RbShape.Type.WEDGE
	plugin.current_shape.size = Vector3(3, 2, 2)
	plugin.current_operation = CSGShape3D.OPERATION_UNION
	plugin.grid_size = 0.5
	plugin.activate_place_mode()
	print("RB_TEST: ghost after activate = ", plugin.place_tool.ghost)
	var viewport := editor.get_editor_viewport_3d()
	var cam := viewport.get_camera_3d()
	var screen := viewport.size * 0.5
	print("RB_TEST: click1 handled = ", plugin._forward_3d_gui_input(cam, _click(screen)))
	plugin.current_operation = CSGShape3D.OPERATION_SUBTRACTION
	plugin.current_shape.shape_type = RbShape.Type.BOX
	plugin.current_shape.size = Vector3(1, 1, 1)
	print("RB_TEST: click2 handled = ", plugin._forward_3d_gui_input(cam, _click(screen + Vector2(30, 0))))
	plugin.deactivate_place_mode()
	print("RB_TEST: ghost after deactivate = ", plugin.place_tool.ghost)
	for k in scene_root.get_children():
		print("RB_TEST: scene child = ", k.name, " / ", k.get_class())


static func _find_plugin(editor) -> RapidBlockPlugin:
	var stack: Array[Node] = [editor.get_base_control().get_tree().root]
	while not stack.is_empty():
		var n := stack.pop_back()
		if n is RapidBlockPlugin:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


static func check_dock() -> void:
	var editor := EditorInterface
	var found: Array[String] = []
	var stack: Array[Node] = [editor.get_base_control().get_tree().root]
	while not stack.is_empty():
		var n := stack.pop_back()
		if n is RapidBlockDock:
			found.append("%s visible=%s size=%s" % [n.name, str(n.visible), str(n.size)])
		for c in n.get_children():
			stack.append(c)
	print("RB_TEST: dock nodes = ", found)


static func _click(position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	return event


static func inspect() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		print("RB_INSPECT: no scene root")
		return
	for k in scene_root.get_children():
		print("RB_INSPECT: top child = ", k.name, " / ", k.get_class())
		for c in k.get_children():
			print("RB_INSPECT:   sub = ", c.name, " / ", c.get_class(), " / op=", c.operation, " / pos=", c.position)
