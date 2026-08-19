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


## 阶段 2 集成测试：表面吸附、门窗生成、拖拽拉伸。
static func test_phase2() -> void:
	var editor := EditorInterface
	var scene_root := editor.get_edited_scene_root()
	if scene_root == null:
		print("RB_TEST: no scene root")
		return
	var plugin := _find_plugin(editor)
	if plugin == null:
		print("RB_TEST: plugin not found")
		return
	_clear_test_nodes(scene_root)
	plugin.current_shape = RbShape.new()
	plugin.current_operation = CSGShape3D.OPERATION_UNION
	plugin.surface_snap_enabled = true
	plugin.grid_enabled = false
	plugin.drag_enabled = true
	plugin.drag_height = 0.2
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.NONE
	var target: Node = plugin.place_tool.call("_placement_target", scene_root)
	var wall := CSGBox3D.new()
	wall.name = "RB_TEST_WALL"
	wall.size = Vector3(6, 3, 0.2)
	wall.position = Vector3(0, 1.5, -2)
	target.add_child(wall)
	wall.owner = scene_root
	var hit := RbSurfaceSnap.cast_surface(Vector3(0, 1.5, 0), Vector3(0, 0, -1), scene_root)
	print("RB_TEST: snap hit=", hit.has("position"),
		" normal=", hit.get("normal", Vector3.ZERO),
		" pos=", hit.get("position", Vector3.ZERO))
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.DOOR
	var door_hit := {"position": Vector3(0, 1.5, -2), "normal": Vector3(0, 0, 1), "shape": wall}
	plugin.place_tool.call("_commit_door_window", scene_root, door_hit)
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.NONE
	plugin.activate_place_mode()
	var viewport := editor.get_editor_viewport_3d()
	var cam := viewport.get_camera_3d()
	var screen := viewport.size * 0.5
	var press := _click(screen)
	print("RB_TEST: press handled=", plugin._forward_3d_gui_input(cam, press))
	var motion := InputEventMouseMotion.new()
	motion.position = screen + Vector2(120, 0)
	print("RB_TEST: motion handled=", plugin._forward_3d_gui_input(cam, motion))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = screen + Vector2(120, 0)
	print("RB_TEST: release handled=", plugin._forward_3d_gui_input(cam, release))
	plugin.deactivate_place_mode()
	for k in scene_root.get_children():
		print("RB_TEST: child=", k.name, " / ", k.get_class())
		if k is CSGCombiner3D:
			for c in k.get_children():
				print("RB_TEST:   sub=", c.name, " / ", c.get_class(), " / op=", c.operation)


static func _clear_test_nodes(scene_root: Node) -> void:
	for k in scene_root.get_children():
		scene_root.remove_child(k)
		k.free()


static func debug_snap() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	for k in scene_root.get_children():
		scene_root.remove_child(k)
		k.free()
	var wall := CSGBox3D.new()
	wall.name = "RB_TEST_WALL"
	wall.size = Vector3(6, 3, 0.2)
	wall.position = Vector3(0, 1.5, -2)
	scene_root.add_child(wall)
	var origin := Vector3(0, 1.5, 0)
	var dir := Vector3(0, 0, -1)
	print("RB_DBG: collected=", RbSurfaceSnap._collect_shapes(scene_root).size())
	var best_t := INF
	var best := {}
	for shape in RbSurfaceSnap._collect_shapes(scene_root):
		var aabb := shape.global_transform * shape.get_aabb()
		print("RB_DBG: shape=", shape.name, " aabb=", aabb)
		var t := RbSurfaceSnap._ray_aabb_enter(origin, dir, aabb)
		print("RB_DBG:   t=", t)
		if t < 0.0 or t >= best_t:
			continue
		best_t = t
		best = {"position": origin + dir * t, "normal": Vector3.UP}
	print("RB_DBG: best=", best)
