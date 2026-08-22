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


## 阶段 3 集成测试：阵列复制、镜像复制、CSG 烘焙。
static func test_phase3() -> void:
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
	var combiner := CSGCombiner3D.new()
	combiner.name = "Whitebox"
	scene_root.add_child(combiner)
	var wall := CSGBox3D.new()
	wall.name = "RB_TEST_WALL"
	wall.size = Vector3(2, 2, 2)
	combiner.add_child(wall)
	editor.get_selection().clear()
	editor.get_selection().add_node(wall)
	plugin.array_selected(2, 3, 2.5)
	plugin.mirror_selected(true)
	editor.get_selection().clear()
	for k in scene_root.get_children():
		print("RB_TEST: child=", k.name, " / ", k.get_class())
		if k is CSGCombiner3D:
			for c in k.get_children():
				print("RB_TEST:   sub=", c.name, " / ", c.get_class())


## 烘焙测试：作用于已渲染的组合器（CSG 需编辑器处理一帧后才有几何）。
static func test_phase3_bake() -> void:
	var editor := EditorInterface
	var scene_root := editor.get_edited_scene_root()
	if scene_root == null:
		print("RB_TEST: no scene root")
		return
	var plugin := _find_plugin(editor)
	if plugin == null:
		print("RB_TEST: plugin not found")
		return
	var combiner := scene_root.find_child("Whitebox", true, false)
	if combiner == null:
		print("RB_TEST: no combiner")
		return
	editor.get_selection().clear()
	editor.get_selection().add_node(combiner)
	plugin.bake_selected()
	editor.get_selection().clear()
	for k in scene_root.get_children():
		print("RB_TEST: child=", k.name, " / ", k.get_class())
		if String(k.name).ends_with("_Baked"):
			for c in k.get_children():
				print("RB_TEST:   baked=", c.name, " / ", c.get_class())
				if c is StaticBody3D:
					for cc in c.get_children():
						print("RB_TEST:     col=", cc.name, " / ", cc.get_class())


static func debug_bake() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return
	for k in scene_root.get_children():
		scene_root.remove_child(k)
		k.free()
	var combiner := CSGCombiner3D.new()
	combiner.name = "Whitebox"
	scene_root.add_child(combiner)
	var wall := CSGBox3D.new()
	wall.name = "RB_TEST_WALL"
	wall.size = Vector3(2, 2, 2)
	combiner.add_child(wall)
	print("RB_DBG: combiner meshes = ", combiner.get_meshes())
	print("RB_DBG: wall meshes = ", wall.get_meshes())
	print("RB_DBG: wall aabb = ", wall.get_aabb(), " global=", wall.global_transform * wall.get_aabb())


## 阶段 4 集成测试：脚本化 API、路径复制、结构色。
static func test_phase4() -> void:
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
	var builder := load("res://addons/rapid_block/tools/rb_scene_builder.gd")
	var combiner: CSGCombiner3D = builder.find_or_create_combiner()
	var wall: CSGBox3D = builder.add_wall(6, 3, 0.2, Vector3.ZERO)
	var floor: CSGBox3D = builder.add_floor(6, 6)
	var pillar: CSGCylinder3D = builder.add_cylinder(Vector3(1, 3, 1), Vector3(2.5, 0, 2.5))
	var door: Array = builder.add_door(RbShapeLibrary.DOOR_WINDOW.DOOR, Vector3(0, 1.5, -0.1), Vector3(0, 0, 1), 0.2, combiner)
	builder.array_duplicate(pillar, 2, 2, 2.5)
	editor.get_selection().clear()
	editor.get_selection().add_node(wall)
	plugin.colorize_selected(RbColorize.STRUCTURE.WALL)
	var dup_count := combiner.get_child_count()
	var scene_child_count := scene_root.get_child_count()
	print("RB_TEST: wall=", wall != null, " floor=", floor != null,
		" door_nodes=", door.size(), " combiner_children=", dup_count,
		" scene_children=", scene_child_count)
	for k in scene_root.get_children():
		print("RB_TEST: ", k.name, " / ", k.get_class())
		for c in k.get_children():
			print("RB_TEST:   ", c.name, " / ", c.get_class(), " / op=", c.operation)


## 阶段 4 导出测试：作用于已渲染的组合器。
static func test_phase4_export() -> void:
	var editor := EditorInterface
	var scene_root := editor.get_edited_scene_root()
	if scene_root == null:
		print("RB_TEST: no scene root")
		return
	var plugin := _find_plugin(editor)
	if plugin == null:
		print("RB_TEST: plugin not found")
		return
	var combiner := scene_root.find_child("Whitebox", true, false)
	if combiner == null:
		print("RB_TEST: no combiner")
		return
	editor.get_selection().clear()
	editor.get_selection().add_node(combiner)
	var path := "res://whitebox_meshes/test_export.tres"
	plugin.export_selected(path)
	print("RB_TEST: export exists = ", FileAccess.file_exists(path))
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 阶段 4 路径复制测试。
static func test_phase4_path() -> void:
	var editor := EditorInterface
	var scene_root := editor.get_edited_scene_root()
	if scene_root == null:
		print("RB_TEST: no scene root")
		return
	var plugin := _find_plugin(editor)
	if plugin == null:
		print("RB_TEST: plugin not found")
		return
	var combiner := scene_root.find_child("Whitebox", true, false)
	if combiner == null:
		print("RB_TEST: no combiner")
		return
	var before := combiner.get_child_count()
	var source := combiner.get_child(0)
	editor.get_selection().clear()
	editor.get_selection().add_node(source)
	plugin.path_copy_selected(Vector3(10, 0, 0), 5)
	editor.get_selection().clear()
	var added := combiner.get_child_count() - before
	print("RB_TEST: path_copy added = ", added)


## 阶段 5 集成测试：白盒透明度预览 + 门窗放置预览。
static func test_phase5() -> void:
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
	var combiner := CSGCombiner3D.new()
	combiner.name = "Whitebox"
	scene_root.add_child(combiner)
	var wall := CSGBox3D.new()
	wall.name = "RB_TEST_WALL"
	wall.size = Vector3(6, 3, 0.2)
	wall.position = Vector3(0, 1.5, -2)
	wall.material = plugin.union_material
	combiner.add_child(wall)
	var custom_mat := StandardMaterial3D.new()
	custom_mat.albedo_color = Color(0.75, 0.75, 0.75)
	custom_mat.roughness = 0.9
	var custom := CSGBox3D.new()
	custom.name = "RB_TEST_CUSTOM"
	custom.size = Vector3(1, 1, 1)
	custom.position = Vector3(0, 0.5, 0)
	custom.material = custom_mat
	combiner.add_child(custom)
	## --- 透明度预览 ---
	## 复位共享材质与基线缓存，保证测试可重复（避免上次运行残留的淡出状态被当作基线）。
	## 复位共享材质与基线缓存，保证测试可重复（避免上次运行残留的淡出状态被当作基线）。
	plugin.union_material = plugin.base_union_material
	var um := plugin.union_material as StandardMaterial3D
	um.albedo_color.a = 1.0
	um.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	plugin._mat_baseline.clear()
	plugin.whitebox_opacity = 1.0
	RbSceneBuilder.set_whitebox_opacity(1.0)
	var union_base_a: float = um.albedo_color.a
	var union_base_t: int = um.transparency
	plugin.set_whitebox_opacity(0.4)
	var a1: float = um.albedo_color.a
	var t1: int = um.transparency
	var a2: float = custom_mat.albedo_color.a
	var t2: int = custom_mat.transparency
	print("RB_TEST: opacity0.4 union_a=", a1, " trans=", t1,
		" custom_a=", a2, " trans=", t2,
		" expect_a=", union_base_a * 0.4,
		" expect_trans=", BaseMaterial3D.TRANSPARENCY_ALPHA)
	print("RB_TEST: scene_builder opacity sync=", RbSceneBuilder.whitebox_opacity,
		" expect=", 0.4)
	## 结构色独立材质应跟随透明度。
	editor.get_selection().clear()
	editor.get_selection().add_node(wall)
	plugin.colorize_selected(RbColorize.STRUCTURE.WALL)
	editor.get_selection().clear()
	var colored := false
	for c in combiner.get_children():
		if c is CSGShape3D and (c as CSGShape3D).material != null \
				and (c as CSGShape3D).material != plugin.union_material \
				and (c as CSGShape3D).material != custom_mat:
			colored = true
			var cm := (c as CSGShape3D).material as StandardMaterial3D
			print("RB_TEST: colorize opacity a=", cm.albedo_color.a,
				" trans=", cm.transparency, " expect_a=", 1.0 * 0.4,
				" expect_trans=", BaseMaterial3D.TRANSPARENCY_ALPHA)
	print("RB_TEST: colorize shape found=", colored)
	plugin.set_whitebox_opacity(1.0)
	print("RB_TEST: opacity1 union_a=", um.albedo_color.a,
		" trans=", um.transparency,
		" custom_a=", custom_mat.albedo_color.a,
		" trans=", custom_mat.transparency,
		" expect_a=", union_base_a, " expect_trans=", union_base_t)
	## Dock 滑块外部回写同步。
	var dock := _find_dock(editor)
	if dock != null:
		print("RB_TEST: dock slider sync=", dock.opacity_slider.value,
			" label=", dock.opacity_value.text)
	## --- 门窗放置预览 ---
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.DOOR
	plugin.place_tool.call("_build_door_preview", {
		"position": Vector3(0, 1.5, -2),
		"normal": Vector3(0, 0, 1),
		"shape": wall,
	})
	var preview_count := plugin.place_tool.door_preview.size()
	var names: Array[String] = []
	for n in plugin.place_tool.door_preview:
		names.append(String(n.name))
	print("RB_TEST: door preview count=", preview_count, " names=", names,
		" ghost_rot=", plugin.place_tool.ghost_rotation_y, " expect=3")
	plugin.place_tool.call("_clear_door_preview")
	print("RB_TEST: door preview cleared=", plugin.place_tool.door_preview.size())
	## 各类门窗预览节点数量：门带框=3（洞改线框不渲染），窗带框=4，门/窗洞=4（线框）。
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.WINDOW
	plugin.place_tool.call("_build_door_preview", {
		"position": Vector3(0, 1.5, -2), "normal": Vector3(0, 0, 1), "shape": wall})
	print("RB_TEST: window preview count=", plugin.place_tool.door_preview.size(), " expect=4")
	plugin.place_tool.call("_clear_door_preview")
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.DOOR_HOLE
	plugin.place_tool.call("_build_door_preview", {
		"position": Vector3(0, 1.5, -2), "normal": Vector3(0, 0, 1), "shape": wall})
	print("RB_TEST: door_hole preview count=", plugin.place_tool.door_preview.size(), " expect=4")
	plugin.place_tool.call("_clear_door_preview")
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE
	plugin.place_tool.call("_build_door_preview", {
		"position": Vector3(0, 1.5, -2), "normal": Vector3(0, 0, 1), "shape": wall})
	print("RB_TEST: window_hole preview count=", plugin.place_tool.door_preview.size(), " expect=4")
	plugin.place_tool.call("_clear_door_preview")
	## R 键循环门窗类型。
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.DOOR_HOLE
	plugin.cycle_door_window(true)
	print("RB_TEST: cycle door_hole->", plugin.door_window_kind, " expect=", RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE,
		" dock=", dock.door_window_box.selected if dock != null else -1)
	plugin.cycle_door_window(false)
	print("RB_TEST: cycle back->", plugin.door_window_kind, " expect=", RbShapeLibrary.DOOR_WINDOW.DOOR_HOLE)
	plugin.door_window_kind = RbShapeLibrary.DOOR_WINDOW.NONE


static func _find_dock(editor) -> RapidBlockDock:
	var stack: Array[Node] = [editor.get_base_control().get_tree().root]
	while not stack.is_empty():
		var n := stack.pop_back()
		if n is RapidBlockDock:
			return n
		for c in n.get_children():
			stack.append(c)
	return null


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
	print("RB_DBG: collected=", RbSurfaceSnap.collect_shapes(scene_root).size())
	var best_t := INF
	var best := {}
	for shape in RbSurfaceSnap.collect_shapes(scene_root):
		var aabb := shape.global_transform * shape.get_aabb()
		print("RB_DBG: shape=", shape.name, " aabb=", aabb)
		var t := RbSurfaceSnap._ray_aabb_enter(origin, dir, aabb)
		print("RB_DBG:   t=", t)
		if t < 0.0 or t >= best_t:
			continue
		best_t = t
		best = {"position": origin + dir * t, "normal": Vector3.UP}
	print("RB_DBG: best=", best)
