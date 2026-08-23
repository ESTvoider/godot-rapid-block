@tool
class_name RbPlaceTool
extends RefCounted
## 视口放置引擎：点击放置 / 拖拽拉伸 / 门窗生成。
## 支持表面吸附（射线-全局 AABB 求交）与网格吸附，幽灵预览不设 owner 因此不会被保存。

enum ToolState { IDLE, DRAGGING }

## 单击与拖拽的像素阈值：过小会导致点击放置时轻微手抖就被当成拖拽拉伸，
## 放出与预设尺寸无关的薄板。
const CLICK_THRESHOLD := 8.0
## 缩放模式下鼠标水平位移到缩放因子的灵敏度（每像素变化量）。
const SCALE_SENSITIVITY := 0.004

var plugin: RapidBlockPlugin
var ghost: CSGShape3D = null
var ghost_rotation_y := 0.0
## 门窗放置预览节点组（无 owner，不保存）。仅门窗模式 hover 墙面时存在。
var door_preview: Array[CSGShape3D] = []
## 门窗预览缓存键：命中位置/朝向/类型不变时跳过重建，避免拖动时每帧销毁重建节点。
var _door_preview_key := ""

var _state := ToolState.IDLE
var _drag_start_screen := Vector2.ZERO
var _drag_start_point := Vector3.ZERO
var _drag_end_point := Vector3.ZERO
var _drag_preview: CSGShape3D = null
## 门窗拖拽拉伸锚点：按下时墙面命中点（无偏移），用于沿墙面切向计算拖拽宽度。
var _door_anchor := Vector3.ZERO
## 缩放模式状态：按 S 进入，鼠标水平位移调比例，再按 S 确认退出。
var _scaling := false
## 进入缩放时的基准尺寸与起始鼠标 X，用于计算缩放因子。
var _scale_base := Vector3.ZERO
var _scale_start_x := 0.0
var _last_mouse_x := 0.0
## 进入缩放时的幽灵位置/朝向，缩放重建幽灵后恢复，避免物体被重置到原点。
var _scale_pos := Vector3.ZERO
var _scale_rot := 0.0


func _init(p_plugin: RapidBlockPlugin) -> void:
	plugin = p_plugin


## 处理 3D 视口输入；返回 true 表示消费该事件。
func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		## 鼠标中键按住拖动是编辑器旋转 3D 视角，必须放行（消费会给视角旋转的信号被吞掉）。
		if bool(motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
			return false
		_last_mouse_x = motion.position.x
		## 缩放模式：鼠标水平位移实时调整缩放比例并刷新预览。
		if _scaling:
			_update_scale(motion.position.x)
			return true
		if _state == ToolState.DRAGGING:
			## 门窗模式且命中墙：刷新门窗拖拽宽度预览；其余情形走普通形状的拖拽拉伸。
			var door_mode := plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE
			if door_mode and _is_wall_hit(camera, motion.position):
				_update_hover(camera, motion.position)
			else:
				_update_drag(camera, motion.position)
		else:
			_update_hover(camera, motion.position)
		return true
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		## 缩放模式下：左键按下结束缩放并在按 S 时的锚点位置放置；滚轮放行编辑器视角缩放。
		if _scaling and mouse.button_index == MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				_scaling = false
				_commit_scaled_click()
			return true
		if _scaling and (mouse.button_index == MOUSE_BUTTON_WHEEL_UP or mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			return false
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_begin_drag(camera, mouse.position)
			return true
		if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			_end_drag(camera, mouse.position)
			return true
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			## 门窗模式下滚轮放行给编辑器做视角缩放；R 键仍循环门窗种类。
			if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
				return false
			_cycle_or_rotate(true)
			return true
		if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
				return false
			_cycle_or_rotate(false)
			return true
		if mouse.button_index == MOUSE_BUTTON_RIGHT and mouse.pressed:
			plugin.deactivate_place_mode()
			return true
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_S:
				_toggle_scale()
				return true
			if key.keycode == KEY_R:
				## 缩放模式下忽略旋转，避免与缩放操作冲突。
				if _scaling:
					return true
				_cycle_or_rotate(true)
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
	## 门窗模式初始隐藏普通幽灵；未命中墙面时由 hover 逻辑重新显示，命中墙面则显示门窗预览。
	if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		ghost.visible = false


func clear_ghost() -> void:
	_scaling = false
	if ghost != null and is_instance_valid(ghost):
		ghost.queue_free()
	ghost = null
	_clear_door_preview()


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
	## 门窗拖拽：仅命中墙面时记录锚点并重建门窗预览；未命中墙面回落到普通形状拖拽。
	if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		if _is_wall_hit(camera, screen_pos):
			var hit := _surface_hit(camera, screen_pos)
			_door_anchor = hit["position"]
			_build_door_preview(hit)
		else:
			_clear_door_preview()
	else:
		_clear_door_preview()


func _end_drag(camera: Camera3D, screen_pos: Vector2) -> void:
	if _state != ToolState.DRAGGING:
		return
	_state = ToolState.IDLE
	var moved := _drag_start_screen.distance_to(screen_pos) >= CLICK_THRESHOLD
	## 门窗模式下禁用拖拽拉伸：点击墙即生成门窗，避免轻微拖动被当成拉伸、
	## 结果放出了当前形状而不是门窗。
	var door_mode := plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE
	var wall_hit := door_mode and _is_wall_hit(camera, screen_pos)
	if wall_hit:
		## 门窗模式命中墙面：用当前鼠标位置提交（_commit_click 内部按拖拽距离决定门窗宽度）。
		_commit_click(camera, screen_pos)
	elif plugin.drag_enabled and moved:
		if _update_drag(camera, screen_pos):
			_commit_drag()
	else:
		## 普通模式用按下位置提交（点击放置）。
		_commit_click(camera, Vector2.INF)
	if _drag_preview != null and is_instance_valid(_drag_preview):
		_drag_preview.queue_free()
	_drag_preview = null
	## 命中墙时门窗预览接管、普通幽灵隐藏；未命中墙（普通放置）恢复普通幽灵显示。
	if ghost != null and is_instance_valid(ghost):
		ghost.visible = not wall_hit


func _update_hover(camera: Camera3D, screen_pos: Vector2) -> void:
	## 门窗模式：命中墙面显示洞+框门窗预览；未命中墙面回落到普通形状幽灵预览。
	if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		if _is_wall_hit(camera, screen_pos):
			if ghost != null and is_instance_valid(ghost):
				ghost.visible = false
			_update_door_preview(camera, screen_pos)
			return
		_clear_door_preview()
	if ghost == null:
		return
	var placement := _placement_point(camera, screen_pos)
	if placement.is_empty():
		return
	ghost.visible = true
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
	var dims := _drag_dims()
	if dims["width"] < 0.05 or dims["depth"] < 0.05:
		return
	var shape_type := plugin.current_shape.shape_type
	var height: float = dims["height"]
	var node := RbShapeLibrary.build_csg_from_dims(
		shape_type, dims["width"], dims["depth"], height,
		CSGShape3D.OPERATION_UNION, plugin.ghost_material)
	node.name = "_rb_drag_preview"
	var center: Vector2 = dims["center"]
	node.position = Vector3(
		center.x,
		RbShapeLibrary.base_offset(shape_type, height),
		center.y)
	node.rotation = Vector3(0, ghost_rotation_y, 0)
	scene_root.add_child(node)
	_drag_preview = node


## 门窗放置预览：命中墙面时生成洞+框半透明幽灵，跟随墙面朝向与位置。
## 拖拽时按墙面切向计算宽度（锚点固定、一端伸展）；命中未变且宽度未变时跳过重建（缓存）。
func _update_door_preview(camera: Camera3D, screen_pos: Vector2) -> void:
	var hit := _surface_hit(camera, screen_pos)
	if hit.is_empty() or hit["normal"].y != 0.0:
		if not door_preview.is_empty():
			_clear_door_preview()
		return
	var shape := hit["shape"] as CSGShape3D
	var wall_thick := _wall_thickness(shape, hit["normal"])
	var yaw := atan2(hit["normal"].x, hit["normal"].z)
	var width := 0.0
	var center_override := Vector3.INF
	if _state == ToolState.DRAGGING:
		var geo := _door_drag_geometry(hit)
		if geo.is_empty():
			_clear_door_preview()
			return
		width = geo["width"]
		center_override = geo["center"]
	var key := "%d|%.2f|%.2f|%.2f|%.2f" % [
		plugin.door_window_kind,
		snappedf(hit["position"].x, 0.02),
		snappedf(hit["position"].z, 0.02),
		snappedf(yaw, 0.02),
		snappedf(width, 0.02),
	]
	if key == _door_preview_key and not door_preview.is_empty():
		return
	_door_preview_key = key
	_build_door_preview(hit, width, center_override)


## 门窗拖拽几何：沿墙面切向计算拖拽宽度与中心。
## 锚点为按下时的墙面命中点，当前点为鼠标命中点；中心取锚点与当前点中点（贴墙、y 定高）。
func _door_drag_geometry(hit: Dictionary) -> Dictionary:
	var normal: Vector3 = hit["normal"]
	var cur: Vector3 = hit["position"]
	var tangent := Vector3(normal.z, 0.0, -normal.x)
	var dist := (cur - _door_anchor).dot(tangent)
	var w := maxf(absf(dist), 0.2)
	var shape := hit["shape"] as CSGShape3D
	var wall_thick := _wall_thickness(shape, normal)
	var kind := plugin.door_window_kind
	var is_window: bool = kind == RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE or kind == RbShapeLibrary.DOOR_WINDOW.WINDOW
	var height := RbShapeLibrary.WINDOW_HEIGHT if is_window else RbShapeLibrary.DOOR_HEIGHT
	var center_y := RbShapeLibrary.WINDOW_SILL + height * 0.5 if is_window else height * 0.5
	var dir := signf(dist)
	var center_wall := _door_anchor + tangent * (dir * w * 0.5)
	var center := Vector3(center_wall.x, center_y, center_wall.z) - normal * (wall_thick * 0.5)
	return {"width": w, "center": center}


## 依据墙面命中信息生成门窗预览节点（无 owner 不保存）。供测试直接复用。
## width<=0 用标准宽；center_override 非 Vector2.INF 时（拖拽）用其作为中心。
## 框体按局部偏移定位（保留门/窗框形状），挖除洞改为线框轮廓而非实心块。
func _build_door_preview(hit: Dictionary, width := 0.0, center_override: Vector3 = Vector3.INF) -> void:
	_clear_door_preview()
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var normal: Vector3 = hit["normal"]
	var hit_pos: Vector3 = hit["position"]
	var shape := hit["shape"] as CSGShape3D
	var wall_thick := _wall_thickness(shape, normal)
	var kind := plugin.door_window_kind
	var is_window: bool = kind == RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE or kind == RbShapeLibrary.DOOR_WINDOW.WINDOW
	var is_framed: bool = kind == RbShapeLibrary.DOOR_WINDOW.DOOR or kind == RbShapeLibrary.DOOR_WINDOW.WINDOW
	if width <= 0.0:
		width = RbShapeLibrary.WINDOW_WIDTH if is_window else RbShapeLibrary.DOOR_WIDTH
	var height := RbShapeLibrary.WINDOW_HEIGHT if is_window else RbShapeLibrary.DOOR_HEIGHT
	var center_y := RbShapeLibrary.WINDOW_SILL + height * 0.5 if is_window else height * 0.5
	var yaw := atan2(normal.x, normal.z)
	ghost_rotation_y = yaw
	var center := Vector3(hit_pos.x, center_y, hit_pos.z) - normal * (wall_thick * 0.5)
	if center_override != Vector3.INF:
		center = center_override
	var nodes := RbShapeLibrary.build_door_window(
		kind, wall_thick, plugin.ghost_material, plugin.door_preview_frame_material, width)
	RbShapeLibrary.position_door_window(nodes, center, yaw)
	for i in nodes.size():
		var n := nodes[i]
		## 跳过实心挖除洞节点：开洞区域交给线框轮廓表达，避免预览变成实心块。
		if i == 0:
			n.queue_free()
			continue
		n.name = "_rb_door_preview_%d" % door_preview.size()
		n.operation = CSGShape3D.OPERATION_UNION
		scene_root.add_child(n)
		door_preview.append(n)
	## 仅洞类型（无框）：用开洞矩形线框表达挖空区域。
	if not is_framed:
		_build_hole_outline(width, height, center, yaw)


## 生成开洞矩形线框（顶/底横梁 + 左/右竖梁），清晰表达挖空区域而不产生实心块。
func _build_hole_outline(width: float, height: float, center: Vector3, yaw: float) -> void:
	var thin := RbShapeLibrary.FRAME_THICKNESS
	_add_preview_edge(Vector3(width, thin, thin), Vector3(0, height * 0.5, 0), center, yaw)
	_add_preview_edge(Vector3(width, thin, thin), Vector3(0, -height * 0.5, 0), center, yaw)
	_add_preview_edge(Vector3(thin, height, thin), Vector3(-width * 0.5, 0, 0), center, yaw)
	_add_preview_edge(Vector3(thin, height, thin), Vector3(width * 0.5, 0, 0), center, yaw)


## 添加单条预览梁节点（UNION 半透明，无 owner），按 中心+局部偏移绕 Y 旋转定位。
func _add_preview_edge(size: Vector3, local_offset: Vector3, center: Vector3, yaw: float) -> void:
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var box := CSGBox3D.new()
	box.size = size
	box.material = plugin.door_preview_frame_material
	box.operation = CSGShape3D.OPERATION_UNION
	box.name = "_rb_door_preview_%d" % door_preview.size()
	box.position = center + local_offset.rotated(Vector3.UP, yaw)
	box.rotation = Vector3(0, yaw, 0)
	scene_root.add_child(box)
	door_preview.append(box)


func _clear_door_preview() -> void:
	for n in door_preview:
		if is_instance_valid(n):
			n.queue_free()
	door_preview.clear()
	_door_preview_key = ""


## 点击提交：优先门窗生成，否则普通放置。
## screen_pos_override 非 Vector2.INF 时（门窗模式拖动提交）改用该屏幕位置，
## 且若发生了拖拽（按下与提交点距离超过阈值）则按拖拽宽度提交门窗。
func _commit_click(camera: Camera3D, screen_pos_override: Vector2 = Vector2.INF) -> void:
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var click_pos := _drag_start_screen
	if screen_pos_override != Vector2.INF:
		click_pos = screen_pos_override
	if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		var hit := _surface_hit(camera, click_pos)
		if not hit.is_empty() and hit["normal"].y == 0.0:
			if _drag_start_screen.distance_to(click_pos) >= CLICK_THRESHOLD:
				var geo := _door_drag_geometry(hit)
				if not geo.is_empty():
					_commit_door_window(scene_root, hit, geo["width"], geo["center"])
					return
			_commit_door_window(scene_root, hit)
			return
	var placement := _placement_point(camera, click_pos)
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
	var dims := _drag_dims()
	if dims["width"] < 0.05 or dims["depth"] < 0.05:
		return
	var shape_type := plugin.current_shape.shape_type
	var height: float = dims["height"]
	var material := plugin.material_for_operation(plugin.current_operation)
	var node := RbShapeLibrary.build_csg_from_dims(
		shape_type, dims["width"], dims["depth"], height,
		plugin.current_operation, material)
	var center: Vector2 = dims["center"]
	var pos := Vector3(
		center.x,
		RbShapeLibrary.base_offset(shape_type, height),
		center.y)
	_commit_node(scene_root, pos, ghost_rotation_y, node)


## 统一的节点提交路径（含撤销封装）。
func _commit_node(scene_root: Node, position: Vector3, rotation_y: float, node: CSGShape3D) -> void:
	var target := _placement_target(scene_root)
	node.name = _sequenced_name(target, _base_name())
	## position 是场景空间坐标（与幽灵预览一致），挂入 target 前转为 target 局部坐标，
	## 否则选中非原点节点（如某面墙）时放置位置会整体偏移。
	node.position = target.to_local(position)
	node.rotation = Vector3(0, rotation_y, 0)
	var undo := plugin.undo_redo
	undo.create_action("放置 %s" % node.name)
	undo.add_do_method(target, "add_child", node)
	undo.add_do_method(node, "set_owner", scene_root)
	undo.add_do_reference(node)
	undo.add_undo_method(target, "remove_child", node)
	undo.commit_action()


## 放置命名基础名：结构预设用预设名（墙体/地板），普通几何用形状显示名。
func _base_name() -> String:
	if plugin.current_preset_name != "":
		return plugin.current_preset_name
	return RbShapeLibrary.display_name(plugin.current_shape.shape_type)


## 生成"基础名 + 序号"的名称：取放置目标下同基础名节点的最大序号 + 1。
func _sequenced_name(target: Node, base: String) -> String:
	var max_n := 0
	for c in target.get_children():
		var cname: String = c.name
		if cname == base:
			max_n = maxi(max_n, 1)
		elif cname.begins_with(base + " "):
			var tail := cname.substr(base.length() + 1)
			if tail.is_valid_int():
				max_n = maxi(max_n, int(tail))
	return "%s %d" % [base, max_n + 1]


## 门窗生成：挖除洞 + 可选门/窗框，挂入墙所属组合器。
## width<=0 用标准宽；center_override 非 Vector2.INF 时（拖拽）用其作为中心。
func _commit_door_window(scene_root: Node, hit: Dictionary, width := 0.0, center_override: Vector3 = Vector3.INF) -> void:
	var shape := hit["shape"] as CSGShape3D
	var normal: Vector3 = hit["normal"]
	var hit_pos: Vector3 = hit["position"]
	var target := _combiner_parent(scene_root, shape)
	var wall_thick := _wall_thickness(shape, normal)
	var kind := plugin.door_window_kind
	var is_window: bool = kind == RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE or kind == RbShapeLibrary.DOOR_WINDOW.WINDOW
	if width <= 0.0:
		width = RbShapeLibrary.WINDOW_WIDTH if is_window else RbShapeLibrary.DOOR_WIDTH
	var height := RbShapeLibrary.WINDOW_HEIGHT if is_window else RbShapeLibrary.DOOR_HEIGHT
	var center_y := RbShapeLibrary.WINDOW_SILL + height * 0.5 if is_window else height * 0.5
	var yaw := atan2(normal.x, normal.z)
	var center := Vector3(hit_pos.x, center_y, hit_pos.z) - normal * (wall_thick * 0.5)
	if center_override != Vector3.INF:
		center = center_override
	var nodes := RbShapeLibrary.build_door_window(kind, wall_thick, plugin.subtract_material, plugin.union_material, width)
	## 保留 build_door_window 的框体局部偏移，仅平移旋转到命中位置，避免框体塌缩。
	RbShapeLibrary.position_door_window(nodes, center, yaw)
	var undo := plugin.undo_redo
	undo.create_action("生成 %s" % RbShapeLibrary.door_window_name(kind))
	for i in nodes.size():
		var n := nodes[i]
		undo.add_do_method(target, "add_child", n)
		undo.add_do_method(n, "set_owner", scene_root)
		undo.add_do_reference(n)
		undo.add_undo_method(target, "remove_child", n)
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
	undo.add_do_reference(combiner)
	undo.add_undo_method(scene_root, "remove_child", combiner)
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
	## 门窗模式必须做墙面检测（不依赖表面吸附开关），否则选中门窗类型后点击墙体
	## 会退回普通放置，把形状盖在墙上。
	var door_window_mode := plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE
	if not plugin.surface_snap_enabled and not door_window_mode:
		return {}
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return {}
	var origin := camera.project_ray_origin(screen_pos)
	var direction := camera.project_ray_normal(screen_pos)
	return RbSurfaceSnap.cast_surface(origin, direction, scene_root)


## 判断屏幕位置是否命中墙面（法线水平 y≈0）。门窗模式强制表面检测，否则依赖表面吸附开关。
func _is_wall_hit(camera: Camera3D, screen_pos: Vector2) -> bool:
	var hit := _surface_hit(camera, screen_pos)
	return not hit.is_empty() and hit["normal"].y == 0.0


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


## 计算拖拽生成的尺寸与中心（与 S 键缩放语义一致）。
## 把拖拽起点/终点投影到物体局部空间（按 ghost_rotation_y 反向旋转），再按预设类型取尺寸：
## 墙体只变长度（局部 X），厚度/高度保持基准；地板只变长宽（局部 X/Z），厚度不变；
## 其余形状在局部空间取 X/Z 跨度作为宽/深。center 为拖拽两点（世界坐标）的中点。
func _drag_dims() -> Dictionary:
	var a := _drag_start_point
	var b := _drag_end_point
	## 反向旋转到物体局部空间，使"长度"与预设朝向对齐。
	var yaw := ghost_rotation_y
	var ca := cos(yaw)
	var sa := sin(yaw)
	var la_x := a.x * ca + a.z * sa
	var la_z := -a.x * sa + a.z * ca
	var lb_x := b.x * ca + b.z * sa
	var lb_z := -b.x * sa + b.z * ca
	var span_x := maxf(absf(lb_x - la_x), 0.05)
	var span_z := maxf(absf(lb_z - la_z), 0.05)
	var base: Vector3 = plugin.current_shape.size
	var width := span_x
	var depth := span_z
	match plugin.current_preset_name:
		"墙体":
			width = span_x
			depth = base.z
		"地板":
			width = span_x
			depth = span_z
	return {
		"center": Vector2((a.x + b.x) * 0.5, (a.z + b.z) * 0.5),
		"width": width,
		"depth": depth,
		"height": base.y,
	}


## 进入/退出缩放模式：进入时记录基准尺寸与起始鼠标 X，退出时保留缩放后的尺寸。
## 缩放结束放置：在按 S 时的锚点位置放置当前缩放后的形状（非鼠标点击位置）。
func _commit_scaled_click() -> void:
	var scene_root := plugin.editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var material := plugin.material_for_operation(plugin.current_operation)
	var node := RbShapeLibrary.build_csg_shape(plugin.current_shape, plugin.current_operation, material)
	_commit_node(scene_root, _scale_pos, _scale_rot, node)


func _toggle_scale() -> void:
	if _scaling:
		_scaling = false
		return
	_scale_base = plugin.current_shape.size
	_scale_start_x = _last_mouse_x
	## 记录缩放前的幽灵位置/朝向，重建后恢复，避免缩放后物体被重置到原点。
	_scale_pos = ghost.position if ghost != null and is_instance_valid(ghost) else Vector3.ZERO
	_scale_rot = ghost_rotation_y
	## 缩放模式显示缩放后的普通形状预览，隐藏门窗预览。
	## 注意：_scaling=true 须在 rebuild_ghost（内部 clear_ghost 会复位缩放状态）之后设置，否则被清空。
	_clear_door_preview()
	rebuild_ghost()
	if ghost != null and is_instance_valid(ghost):
		ghost.position = _scale_pos
		ghost.rotation = Vector3(0, _scale_rot, 0)
		ghost.visible = true
	_scaling = true


## 缩放模式：鼠标水平位移换算缩放因子，按形状类型应用并刷新预览与 Dock 尺寸。
## 常规形状等比缩放所有边；墙体只变长度（X），高度/厚度不变；地板只变长宽（X/Z），厚度不变。
func _update_scale(mouse_x: float) -> void:
	_last_mouse_x = mouse_x
	var dx := mouse_x - _scale_start_x
	var factor := clampf(1.0 + dx * SCALE_SENSITIVITY, 0.1, 10.0)
	var base := _scale_base
	match plugin.current_preset_name:
		"墙体":
			plugin.current_shape.size = Vector3(base.x * factor, base.y, base.z)
		"地板":
			plugin.current_shape.size = Vector3(base.x * factor, base.y, base.z * factor)
		_:
			plugin.current_shape.size = base * factor
	if plugin.dock != null and is_instance_valid(plugin.dock):
		plugin.dock.set_size_values(plugin.current_shape.size)
	rebuild_ghost()
	if ghost != null and is_instance_valid(ghost):
		ghost.position = _scale_pos
		ghost.rotation = Vector3(0, _scale_rot, 0)
		ghost.visible = true
	## clear_ghost 在重建时复位了缩放状态，此处恢复，保证拖动过程中保持缩放模式。
	_scaling = true


## 门窗模式下 R 键/滚轮用于循环切换门/窗类型，普通模式保持形状旋转。
func _cycle_or_rotate(forward: bool) -> void:
	if plugin.door_window_kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		plugin.cycle_door_window(forward)
	else:
		_rotate_ghost(forward)


func _rotate_ghost(clockwise: bool) -> void:
	var step := deg_to_rad(plugin.rotation_step)
	var delta := step if clockwise else -step
	ghost_rotation_y = snappedf(ghost_rotation_y + delta, step)
	if ghost != null and is_instance_valid(ghost):
		ghost.rotation = Vector3(0, ghost_rotation_y, 0)
	plugin.sync_rotation_angle()
