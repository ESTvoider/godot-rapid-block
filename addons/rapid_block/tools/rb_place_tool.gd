@tool
class_name RbPlaceTool
extends RefCounted
## 视口放置引擎：处理点击/按键输入、地面求交、网格吸附与 CSG 生成。
## 幽灵预览节点不设 owner，因此不会被保存进场景。

var plugin: RapidBlockPlugin
var ghost: CSGShape3D = null
var ghost_rotation_y := 0.0


func _init(p_plugin: RapidBlockPlugin) -> void:
	plugin = p_plugin


## 处理 3D 视口输入；返回 true 表示消费该事件。
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		_update_ghost_position(camera, motion.position)
		return true
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_commit_placement(camera, mouse.position)
			return true
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			plugin.deactivate_place_mode()
			return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_R:
				_rotate_ghost()
				return true
			if key.keycode == KEY_ESCAPE:
				plugin.deactivate_place_mode()
				return true
	return false


## 重建幽灵预览（形状类型或尺寸变化时调用）。
func rebuild_ghost() -> void:
	clear_ghost()
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := RbShapeLibrary.build_csg_shape(plugin.current_shape, CSGShape3D.OPERATION_UNION, plugin.ghost_material)
	node.name = "_rb_ghost"
	scene_root.add_child(node)
	ghost = node


func clear_ghost() -> void:
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null


func _rotate_ghost() -> void:
	var step := deg_to_rad(plugin.rotation_step)
	ghost_rotation_y = snappedf(ghost_rotation_y + step, step)
	_apply_ghost_rotation()


func _update_ghost_position(camera: Camera3D, screen_pos: Vector2) -> void:
	if ghost == null:
		return
	var point := _ground_point(camera, screen_pos)
	if point == null:
		return
	ghost.position = _snapped_position(point)
	_apply_ghost_rotation()


func _apply_ghost_rotation() -> void:
	if ghost == null:
		return
	ghost.rotation = Vector3(0, ghost_rotation_y, 0)


func _commit_placement(camera: Camera3D, screen_pos: Vector2) -> void:
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var point := _ground_point(camera, screen_pos)
	if point == null:
		return
	var target := _placement_target(scene_root)
	var material := plugin.material_for_operation(plugin.current_operation)
	var node := RbShapeLibrary.build_csg_shape(plugin.current_shape, plugin.current_operation, material)
	node.name = RbShapeLibrary.display_name(plugin.current_shape.shape_type)
	node.position = _snapped_position(point)
	node.rotation = Vector3(0, ghost_rotation_y, 0)
	var undo := plugin.undo_redo
	undo.create_action("放置 %s" % RbShapeLibrary.display_name(plugin.current_shape.shape_type))
	undo.add_do_method(target, "add_child", node)
	undo.add_do_method(node, "set_owner", scene_root)
	undo.add_undo_method(target, "remove_child", node)
	undo.add_undo_method(node, "queue_free")
	undo.commit_action()


## 放置目标：优先选中的 CSG 节点，其次已有组合器，最后自动新建组合器。
func _placement_target(scene_root: Node) -> Node:
	var selection := plugin.editor_interface.get_selection().get_selected_nodes()
	if not selection.is_empty():
		var first := selection[0]
		if first is CSGShape3D:
			return first
	var existing := _find_combiner(scene_root)
	if existing != null:
		return existing
	var combiner := CSGCombiner3D.new()
	combiner.name = "Whitebox"
	var undo := plugin.undo_redo
	undo.create_action("创建白盒组合器")
	undo.add_do_method(scene_root, "add_child", combiner)
	undo.add_do_method(combiner, "set_owner", scene_root)
	undo.add_undo_method(scene_root, "remove_child", combiner)
	undo.add_undo_method(combiner, "queue_free")
	undo.commit_action()
	return combiner


func _find_combiner(scene_root: Node) -> CSGCombiner3D:
	for child in scene_root.get_children():
		if child is CSGCombiner3D and child.name == "Whitebox":
			return child as CSGCombiner3D
	return null


func _ground_point(camera: Camera3D, screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(origin, direction)


func _snapped_position(point: Vector3) -> Vector3:
	var offset := RbShapeLibrary.origin_offset(plugin.current_shape)
	if plugin.grid_enabled:
		return Vector3(
			snappedf(point.x, plugin.grid_size),
			offset,
			snappedf(point.z, plugin.grid_size),
		)
	return Vector3(point.x, offset, point.z)
