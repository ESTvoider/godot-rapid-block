@tool
class_name RbPlaceTool
extends RefCounted
## 视口放置引擎：点击放置 / 拖拽拉伸 / 门窗生成。
## 支持表面吸附（射线-全局 AABB 求交）与网格吸附，幽灵预览不设 owner 因此不会被保存。

enum ToolState { IDLE, DRAGGING }

const CLICK_THRESHOLD := 4.0

var plugin: RapidBlockPlugin
var ghost: CSGShape3D = null
var ghost_rotation_y := 0.0

var _state := ToolState.IDLE
var _drag_start_screen := Vector2.ZERO
var _drag_start_point := Vector3.ZERO
var _drag_end_point := Vector3.ZERO
var _drag_preview: CSGShape3D = null


func _init(p_plugin: RapidBlockPlugin) -> void:
	plugin = p_plugin


## 处理 3D 视口输入；返回 true 表示消费该事件。
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _state == ToolState.DRAGGING:
			_update_drag(camera, motion.position)
		else:
			_update_hover(camera, motion.position)
		return true
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_begin_drag(camera, mouse.position)
			return true
		if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			_end_drag(camera, mouse.position)
			return true
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			_rotate_ghost(true)
			return true
		if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			_rotate_ghost(false)
			return true
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			plugin.deactivate_place_mode()
			return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_R:
				_rotate_ghost(true)
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


func _begin_drag(camera: Camera3D, screen_pos: Vector2) -> void:
	var placement := _placement_point(camera, screen_pos)
	if placement.is_empty():
		return
	_state = ToolState.DRAGGING
	_drag_start_screen = screen_pos
	_drag_start_point = placement["pos"]
	_drag_end_point = placement["pos"]
	if ghost != null:
		ghost.visible = false


func _end_drag(camera: Camera3D, screen_pos: Vector2) -> void:
	if _state != ToolState.DRAGGING:
		return
	_state = ToolState.IDLE
	var moved := _drag_start_screen.distance_to(screen_pos) >= CLICK_THRESHOLD
	if plugin.drag_enabled and moved:
		if _update_drag(camera, screen_pos):
			_commit_drag()
	else:
		_commit_click(camera)
	if _drag_preview != null and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_drag_preview = null
	if ghost != null and is_instance_valid(ghost):
		ghost.visible = true


func _update_hover(camera: Camera3D, screen_pos: Vector2) -> void:
	if ghost == null:
		return
	var placement := _placement_point(camera, screen_pos)
	if placement.is_empty():
		return
	ghost.position = placement["pos"]
	ghost.rotation = Vector3(0, placement["rot"], 0)


func _update_drag(camera: Camera3D, screen_pos: Vector2) -> bool:
	var placement := _placement_point(camera, screen_pos)
	if placement.is_empty():
		return false
	_drag_end_point = placement["pos"]
	_update_drag_preview()
	return true


func _update_drag_preview() -> void:
	if _drag_preview != null and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_drag_preview = null
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var rect := _drag_rect()
	if rect.size.x < 0.05 or rect.size.y < 0.05:
		return
	var shape_type := plugin.current_shape.shape_type
	var node := RbShapeLibrary.build_csg_from_dims(
		shape_type, rect.size.x, rect.size.y, plugin.drag_height,
		CSGShape3D.OPERATION_UNION, plugin.ghost_material)
	node.name = "_rb_drag_preview"
	node.position = Vector3(
		rect.get_center().x,
		RbShapeLibrary.base_offset(shape_type, plugin.drag_height),
		rect.get_center().y)
	node.rotation = Vector3(0, ghost_rotation_y, 0)
	scene_root.add_child(node)
	_drag_preview = node


## 点击提交：优先门窗生成，否则普通放置。
func _commit_click(camera: Camera3D) -> void:
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		var hit := _surface_hit(camera, _drag_start_screen)
		if not hit.is_empty() and hit["normal"].y == 0.0:
			_commit_door_window(scene_root, hit)
			return
	var placement := _placement_point(camera, _drag_start_screen)
	if placement.is_empty():
		return
	var material := plugin.material_for_operation(plugin.current_operation)
	var node := RbShapeLibrary.build_csg_shape(plugin.current_shape, plugin.current_operation, material)
	_commit_node(scene_root, placement["pos"], placement["rot"], node)


## 拖拽拉伸提交：按拖拽矩形生成当前形状。
func _commit_drag() -> void:
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var rect := _drag_rect()
	if rect.size.x < 0.05 or rect.size.y < 0.05:
		return
	var shape_type := plugin.current_shape.shape_type
	var material := plugin.material_for_operation(plugin.current_operation)
	var node := RbShapeLibrary.build_csg_from_dims(
		shape_type, rect.size.x, rect.size.y, plugin.drag_height,
		plugin.current_operation, material)
	var pos := Vector3(
		rect.get_center().x,
		RbShapeLibrary.base_offset(shape_type, plugin.drag_height),
		rect.get_center().y)
	_commit_node(scene_root, pos, ghost_rotation_y, node)


## 统一的节点提交路径（含撤销封装）。
func _commit_node(scene_root: Node, position: Vector3, rotation_y: float, node: CSGShape3D) -> void:
	var target := _placement_target(scene_root)
	node.name = RbShapeLibrary.display_name(plugin.current_shape.shape_type)
	node.position = position
	node.rotation = Vector3(0, rotation_y, 0)
	var undo := plugin.undo_redo
	undo.create_action("放置 %s" % node.name)
	undo.add_do_method(target, "add_child", node)
	undo.add_do_method(node, "set_owner", scene_root)
	undo.add_undo_method(target, "remove_child", node)
	undo.add_undo_method(node, "queue_free")
	undo.commit_action()


## 门窗生成：挖除洞 + 可选门/窗框，挂入墙所属组合器。
func _commit_door_window(scene_root: Node, hit: Dictionary) -> void:
	var shape := hit["shape"] as CSGShape3D
	var normal: Vector3 = hit["normal"]
	var hit_pos: Vector3 = hit["position"]
	var target := _combiner_parent(scene_root, shape)
	var wall_thick := _wall_thickness(shape, normal)
	var kind := plugin.door_window_kind
	var is_window: bool = kind == RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE or kind == RbShapeLibrary.DOOR_WINDOW.WINDOW
	var width := RbShapeLibrary.WINDOW_WIDTH if is_window else RbShapeLibrary.DOOR_WIDTH
	var height := RbShapeLibrary.WINDOW_HEIGHT if is_window else RbShapeLibrary.DOOR_HEIGHT
	var center_y := RbShapeLibrary.WINDOW_SILL + height * 0.5 if is_window else height * 0.5
	var yaw := atan2(normal.x, normal.z)
	var center := Vector3(hit_pos.x, center_y, hit_pos.z) - normal * (wall_thick * 0.5)
	var nodes := RbShapeLibrary.build_door_window(kind, wall_thick, plugin.subtract_material, plugin.union_material)
	var undo := plugin.undo_redo
	undo.create_action("生成 %s" % RbShapeLibrary.door_window_name(kind))
	for i in nodes.size():
		var n := nodes[i]
		n.position = center
		n.rotation = Vector3(0, yaw, 0)
		undo.add_do_method(target, "add_child", n)
		undo.add_do_method(n, "set_owner", scene_root)
		undo.add_undo_method(target, "remove_child", n)
		undo.add_undo_method(n, "queue_free")
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


## 门窗应挂入命中形状所属的组合器，保证挖除对墙生效。
func _combiner_parent(scene_root: Node, shape: CSGShape3D) -> Node:
	var parent := shape.get_parent()
	while parent != null and parent != scene_root:
		if parent is CSGCombiner3D:
			return parent
		parent = parent.get_parent()
	return _placement_target(scene_root)


func _find_combiner(scene_root: Node) -> CSGCombiner3D:
	for child in scene_root.get_children():
		if child is CSGCombiner3D and child.name == "Whitebox":
			return child as CSGCombiner3D
	return null


## 计算放置变换：表面吸附优先，未命中回落到地面。
func _placement_point(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var hit := _surface_hit(camera, screen_pos)
	if not hit.is_empty():
		var normal: Vector3 = hit["normal"]
		var hit_pos: Vector3 = hit["position"]
		if normal.y == 0.0:
			var yaw := atan2(normal.x, normal.z)
			ghost_rotation_y = yaw
			return {"pos": hit_pos + normal * _wall_offset(), "rot": yaw}
		return {
			"pos": hit_pos + normal * RbShapeLibrary.origin_offset(plugin.current_shape),
			"rot": ghost_rotation_y,
		}
	var point := _ground_point(camera, screen_pos)
	if point == null:
		return {}
	return {"pos": _snapped_position(point), "rot": ghost_rotation_y}


func _surface_hit(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	if not plugin.surface_snap_enabled:
		return {}
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return {}
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	return RbSurfaceSnap.cast_surface(origin, direction, scene_root)


## 贴墙时沿法线方向的偏移：对称柱体取半径，其余取深度一半。
func _wall_offset() -> float:
	var shape_type := plugin.current_shape.shape_type
	if shape_type == RbShape.Type.CYLINDER or shape_type == RbShape.Type.SPHERE or shape_type == RbShape.Type.CAPSULE:
		return plugin.current_shape.size.x * 0.5
	return plugin.current_shape.size.z * 0.5


func _wall_thickness(shape: CSGShape3D, normal: Vector3) -> float:
	var aabb := RbSurfaceSnap._global_aabb(shape)
	if absf(normal.y) > 0.5:
		return aabb.size.y
	if absf(normal.x) > 0.5:
		return aabb.size.x
	return aabb.size.z


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


func _drag_rect() -> Rect2:
	var a := _drag_start_point
	var b := _drag_end_point
	var min_x := minf(a.x, b.x)
	var min_z := minf(a.z, b.z)
	return Rect2(
		Vector2(min_x, min_z),
		Vector2(maxf(absf(a.x - b.x), 0.05), maxf(absf(a.z - b.z), 0.05)))


func _rotate_ghost(clockwise: bool) -> void:
	var step := deg_to_rad(plugin.rotation_step)
	var delta := step if clockwise else -step
	ghost_rotation_y = snappedf(ghost_rotation_y + delta, step)
	if ghost != null and is_instance_valid(ghost):
		ghost.rotation = Vector3(0, ghost_rotation_y, 0)
	plugin.sync_rotation_angle()
