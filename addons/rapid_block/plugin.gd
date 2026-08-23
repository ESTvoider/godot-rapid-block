@tool
class_name RapidBlockPlugin
extends EditorPlugin
## 快速白盒搭建：注册右侧 Dock 面板，并接管 3D 视口放置输入。

const DOCK_SCENE := preload("res://addons/rapid_block/dock/rapid_block_dock.tscn")
const PLACE_TOOL_SCRIPT := preload("res://addons/rapid_block/tools/rb_place_tool.gd")

var dock: RapidBlockDock
var dock_root: ScrollContainer
var place_tool: RbPlaceTool
var undo_redo: EditorUndoRedoManager
var editor_interface: EditorInterface

var current_shape: RbShape
## 当前结构预设名（"墙体"/"地板"），空表示普通几何；供放置命名体现语义。
var current_preset_name: String = ""
var current_operation: int = CSGShape3D.OPERATION_UNION
var grid_enabled := true
var grid_size := 0.5
var rotation_step := 90.0
## 固定步长缩放：勾选后缩放模式用滚轮按 scale_step 每档增减尺寸（米）。
var scale_step_enabled := false
var scale_step := 1.0
var place_active := false
var drag_enabled := true
var surface_snap_enabled := false
var door_window_kind: int = RbShapeLibrary.DOOR_WINDOW.NONE
var whitebox_opacity := 1.0
var _tracked_scene_root: Node = null
## 标记选中物体并显示尺寸功能开关（Dock CheckBox 控制）。
var mark_selection_enabled := false
## 选中物体标记的线框颜色（亮蓝，与放置高亮呼应）。
const MARK_COLOR := Color(0.2, 0.6, 1.0, 1.0)
## 当前选中标记的 CSG 引用缓存（避免每次绘制都遍历选中列表）。
var _marked_csg: CSGShape3D = null
## 材质基线缓存：材质资源 -> { "transparency": int, "alpha": float }，用于透明度预览的还原。
var _mat_baseline: Dictionary = {}
## 透明度淡出时被替换材质的形状映射：形状实例 -> 其原始共享材质（union_material / grid_material）。
## opacity 还原为 1.0 时据此把形状材质恢复为共享引用，避免独立副本被保存进场景。
var _opacity_original_material: Dictionary = {}
## 已执行过历史内联半透明材质清理的场景根（切换场景时对新场景重新清理）。
var _opacity_cleaned_scene: Node = null

var union_material: Material
## 默认灰色基础材质（whitebox_gray），供"默认"按钮切回。
var base_union_material: StandardMaterial3D
## 网格材质：灰底 + 深灰网格线，基于局部坐标每格 1m（随表面对齐、不随世界滑动），供"网格"按钮切换。
var grid_material: ShaderMaterial
var subtract_material: StandardMaterial3D
var intersect_material: StandardMaterial3D
var ghost_material: StandardMaterial3D
## 门窗放置预览用材质：框体半透明蓝色，勾勒开洞轮廓。
var door_preview_frame_material: StandardMaterial3D


func _enter_tree() -> void:
	editor_interface = get_editor_interface()
	undo_redo = get_undo_redo()
	current_shape = RbShape.new()
	_init_materials()
	place_tool = PLACE_TOOL_SCRIPT.new(self)
	## 无 `_handles()` 时编辑器不会把 3D 视口输入转发给 `_forward_3d_gui_input`。
	set_input_event_forwarding_always_enabled()
	## 监听选中变化，实时刷新 Dock 尺寸显示与标记对象缓存。
	editor_interface.get_selection().selection_changed.connect(_on_selection_changed)
	dock_root = DOCK_SCENE.instantiate()
	dock = dock_root.get_node("RapidBlockDockContent") as RapidBlockDock
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock_root)
	_connect_dock_signals()
	## 初始化 Dock 选中信息为"未选中"。
	_update_selection_info()


## 让插件处理 Node3D 类型对象（否则 `_forward_3d_gui_input` 不会被调用）。
func _handles(object: Object) -> bool:
	return object is Node3D


func _exit_tree() -> void:
	deactivate_place_mode()
	_free_mark_wireframe()
	_marked_csg = null
	## 断开选中变化监听，避免插件卸载后残留连接。
	var selection := editor_interface.get_selection()
	if selection != null and selection.is_connected("selection_changed", _on_selection_changed):
		selection.disconnect("selection_changed", _on_selection_changed)
	if dock_root != null and is_instance_valid(dock_root):
		remove_control_from_docks(dock_root)
		dock_root.queue_free()


## Godot 4.7 中返回 int：1 表示消费输入，0 表示放行给编辑器。
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not place_active:
		return 0
	return 1 if place_tool.handle_input(camera, event) else 0


## 全局快捷键：P 键切换「开始放置」/「停止放置」。
## 用 _shortcut_input 在编辑器内任意时刻触发（无需放置模式先激活），
## 与 place_tool 的 S/R/Esc 处理互不冲突；再按一次退出，右键/Esc 仍可退出。
func _shortcut_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_P:
		if place_active:
			deactivate_place_mode()
		else:
			activate_place_mode()
		if dock != null and is_instance_valid(dock):
			dock.set_place_button_active(place_active)
		get_viewport().set_input_as_handled()


## 轮询场景根：切换/关闭场景时自动退出放置模式，清理幽灵预览；维护选中标记线框。
func _process(_delta: float) -> void:
	## 标记线框独立于放置模式运行：功能开启时持续刷新选中物体的包围盒线框。
	_update_mark_wireframe()
	## 场景切换时对当前场景做一次历史内联半透明材质清理：每次进入新场景都检查，
	## 保证"非 100% 透明度保存后重开"的污染场景被自动恢复为共享引用。
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root != null and scene_root != _opacity_cleaned_scene:
		_opacity_cleaned_scene = scene_root
		_cleanup_inline_opacity_materials(scene_root)
	if not place_active:
		return
	if scene_root != _tracked_scene_root:
		deactivate_place_mode()


func activate_place_mode() -> void:
	if place_active:
		return
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null or not scene_root is Node3D:
		return
	place_active = true
	_tracked_scene_root = scene_root
	place_tool.rebuild_ghost()


func deactivate_place_mode() -> void:
	if not place_active:
		return
	place_active = false
	_tracked_scene_root = null
	place_tool.clear_ghost()
	_sync_place_button()


func material_for_operation(operation: int) -> Material:
	match operation:
		CSGShape3D.OPERATION_SUBTRACTION:
			return subtract_material
		CSGShape3D.OPERATION_INTERSECTION:
			return intersect_material
		_:
			return union_material


## 烘焙选中的 CSG 为 Mesh 节点（隐藏原 CSG），供白盒转正式。
func bake_selected() -> void:
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var csg := _selected_csg()
	if csg == null:
		return
	var baked := RbBake.bake(csg)
	if baked == null:
		editor_interface.get_selection().clear()
		editor_interface.get_selection().add_node(csg)
		print("RB: 未烘焙——所选 CSG 无可用几何（可能未选中根 CSG 或其网格尚未生成）")
		return
	var root_csg := RbBake.resolve_root_csg(csg)
	var undo := undo_redo
	undo.create_action("烘焙 %s" % root_csg.name)
	undo.add_do_method(scene_root, "add_child", baked)
	undo.add_do_method(baked, "set_owner", scene_root)
	undo.add_do_reference(baked)
	undo.add_do_method(root_csg, "set", "visible", false)
	undo.add_undo_method(scene_root, "remove_child", baked)
	undo.add_undo_method(root_csg, "set", "visible", true)
	undo.commit_action()


## 阵列复制选中的节点（沿 X 列 / Z 行）。
func array_selected(rows: int, cols: int, spacing: float) -> void:
	_run_duplicate(rows, cols, spacing)


## 镜像复制选中的节点。
func mirror_selected(flip_x: bool) -> void:
	_run_duplicate(1, 1, 0.0, true, flip_x)


## 沿直线路径复制选中的节点。
func path_copy_selected(end_offset: Vector3, count: int) -> void:
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var source := _selected_node3d()
	if source == null:
		return
	var parent := source.get_parent()
	var target := parent if parent != null else scene_root
	var nodes := RbTransformTools.path_duplicate(source, end_offset, count)
	var undo := undo_redo
	undo.create_action("路径复制 %s" % source.name)
	for node in nodes:
		undo.add_do_method(target, "add_child", node)
		undo.add_do_method(node, "set_owner", scene_root)
		undo.add_undo_method(target, "remove_child", node)
		undo.add_undo_method(node, "queue_free")
	undo.commit_action()


## 将选中的 CSG 导出为 MeshLibrary 资源。
func export_selected(save_path: String) -> void:
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var csg := _selected_csg()
	if csg == null:
		print("RB: 请先选中一个 CSG 节点")
		return
	var result := RbExport.export_mesh_library(csg, save_path)
	print("RB: 导出结果 = ", result)


## 为选中的节点设置结构色。
func colorize_selected(kind: int) -> void:
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var node := _selected_node3d()
	if node == null:
		return
	RbColorize.colorize(node, kind)
	## 结构色创建独立材质，透明度预览开启时重新套用，保持整体淡出。
	if whitebox_opacity < 1.0:
		set_whitebox_opacity(whitebox_opacity)


func _run_duplicate(rows: int, cols: int, spacing: float, mirror: bool = false, flip_x: bool = false) -> void:
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	var source := _selected_node3d()
	if source == null:
		return
	var parent := source.get_parent()
	var target := parent if parent != null else scene_root
	var undo := undo_redo
	var title := "镜像复制 %s" % source.name if mirror else "阵列复制 %s" % source.name
	undo.create_action(title)
	var nodes: Array[Node3D]
	if mirror:
		nodes = [RbTransformTools.mirror_duplicate(source, flip_x)]
	else:
		nodes = RbTransformTools.array_duplicate(source, rows, cols, spacing)
	for node in nodes:
		undo.add_do_method(target, "add_child", node)
		undo.add_do_method(node, "set_owner", scene_root)
		undo.add_undo_method(target, "remove_child", node)
		undo.add_undo_method(node, "queue_free")
	undo.commit_action()


func _selected_csg() -> CSGShape3D:
	var node := _selected_node3d()
	if node is CSGShape3D:
		return node as CSGShape3D
	return null


func _selected_node3d() -> Node3D:
	var selection := editor_interface.get_selection().get_selected_nodes()
	if selection.is_empty():
		return null
	var first := selection[0]
	if first is Node3D:
		return first as Node3D
	return null


## Dock 开关切换「标记选中并显示尺寸」。
func _on_selection_mark_toggled(enabled: bool) -> void:
	mark_selection_enabled = enabled
	## 关闭功能时移除旧选中物体的线框标记。
	if not enabled:
		_free_mark_wireframe()
		_marked_csg = null
	_on_selection_changed()


## 选中变化时刷新标记对象缓存与 Dock 尺寸显示。
func _on_selection_changed() -> void:
	## 先清理旧选中物体的线框（避免残留），再指向新选中。
	_free_mark_wireframe()
	_marked_csg = _selected_csg() if mark_selection_enabled else null
	_update_selection_info()


## 更新 Dock 的选中物体信息：名称 + 尺寸；未选中显示"未选中"。
func _update_selection_info() -> void:
	if dock == null or not is_instance_valid(dock):
		return
	var info := ""
	if mark_selection_enabled:
		var csg := _selected_csg()
		if csg != null:
			var size := _marked_size(csg)
			info = "%s：%.2f × %.2f × %.2f m" % [csg.name, size.x, size.y, size.z]
	dock.set_selection_info(info)


## 计算选中 CSG 的局部尺寸（按节点类型推导，不依赖 get_aabb 的退化返回值）。
func _marked_size(csg: CSGShape3D) -> Vector3:
	return RbSurfaceSnap._local_aabb(csg).size


## 在场景中创建/更新选中物体的包围盒线框节点（挂在选中 CSG 下，跟随其变换）。
## 线框用 ImmediateMesh 的 PRIMITIVE_LINES 画 12 条棱，网格材质用无光照的 MARK_COLOR 线框。
func _update_mark_wireframe() -> void:
	var target: Node3D = _marked_csg
	if target == null or not is_instance_valid(target) or not target is CSGShape3D:
		_free_mark_wireframe()
		return
	var existing := target.get_node_or_null("_rb_mark_wireframe") as MeshInstance3D
	var mesh: ImmediateMesh
	if existing == null:
		existing = MeshInstance3D.new()
		existing.name = "_rb_mark_wireframe"
		existing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = MARK_COLOR
		mat.vertex_color_use_as_albedo = true
		existing.material_override = mat
		mesh = ImmediateMesh.new()
		existing.mesh = mesh
		target.add_child(existing)
		## 编辑场景中创建的子节点需设置 owner，避免保存时丢失；标记节点不设为场景内容。
		## 用 owner=null 使其成为非持久预览节点，与 _rb_ghost 一致。
	else:
		mesh = existing.mesh as ImmediateMesh
	## 按类型算局部尺寸（_marked_size 已含旋转场景的全局 AABB，此处用局部 AABB 保证跟随物体坐标系）。
	var aabb := RbSurfaceSnap._local_aabb(target as CSGShape3D)
	var center := aabb.get_center()
	var extents := aabb.size * 0.5
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	## 12 条棱，8 个角（在物体局部坐标）。
	var corners := [
		center + Vector3(-extents.x, -extents.y, -extents.z),
		center + Vector3(extents.x, -extents.y, -extents.z),
		center + Vector3(extents.x, -extents.y, extents.z),
		center + Vector3(-extents.x, -extents.y, extents.z),
		center + Vector3(-extents.x, extents.y, -extents.z),
		center + Vector3(extents.x, extents.y, -extents.z),
		center + Vector3(extents.x, extents.y, extents.z),
		center + Vector3(-extents.x, extents.y, extents.z),
	]
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0], ## 底
		[4, 5], [5, 6], [6, 7], [7, 4], ## 顶
		[0, 4], [1, 5], [2, 6], [3, 7], ## 竖
	]
	for e in edges:
		mesh.surface_add_vertex(corners[e[0]])
		mesh.surface_add_vertex(corners[e[1]])
	mesh.surface_end()


## 移除标记线框节点（物体取消选中或功能关闭时调用）。
func _free_mark_wireframe() -> void:
	if _marked_csg != null and is_instance_valid(_marked_csg):
		var node := _marked_csg.get_node_or_null("_rb_mark_wireframe") as Node
		if node != null:
			_marked_csg.remove_child(node)
			node.queue_free()


func _sync_place_button() -> void:
	if dock != null and is_instance_valid(dock):
		dock.set_place_button_active(false)


func _connect_dock_signals() -> void:
	dock.place_toggled.connect(_on_place_toggled)
	dock.shape_type_changed.connect(_on_shape_type_changed)
	dock.size_changed.connect(_on_size_changed)
	dock.operation_changed.connect(_on_operation_changed)
	dock.snap_changed.connect(_on_snap_changed)
	dock.rotation_step_changed.connect(_on_rotation_step_changed)
	dock.color_changed.connect(_on_color_changed)
	dock.drag_toggled.connect(_on_drag_toggled)
	dock.surface_snap_changed.connect(_on_surface_snap_changed)
	dock.structure_preset_changed.connect(_on_structure_preset_changed)
	dock.door_window_changed.connect(_on_door_window_changed)
	dock.preview_opacity_changed.connect(_on_preview_opacity_changed)
	dock.bake_requested.connect(bake_selected)
	dock.array_requested.connect(array_selected)
	dock.mirror_requested.connect(mirror_selected)
	dock.path_copy_requested.connect(path_copy_selected)
	dock.export_requested.connect(export_selected)
	dock.colorize_requested.connect(colorize_selected)
	dock.grid_material_requested.connect(apply_grid_material)
	dock.selection_mark_toggled.connect(_on_selection_mark_toggled)
	dock.fixed_step_changed.connect(_on_fixed_step_changed)
	## 连接后主动同步 dock 当前固定步长设置（编辑器重启后 dock 勾选状态可能已持久化，
	## 但不会重新触发信号，需在插件侧读取一次）。
	_sync_fixed_step_from_dock()


## 读取 dock 当前固定步长设置并同步到插件状态，保证 UI 与插件一致。
func _sync_fixed_step_from_dock() -> void:
	if dock == null or not is_instance_valid(dock):
		return
	scale_step_enabled = dock.fixed_step_scale_check.button_pressed
	scale_step = maxf(dock.scale_step_spin.value, 0.05)

func _on_drag_toggled(enabled: bool) -> void:
	drag_enabled = enabled


func _on_surface_snap_changed(enabled: bool) -> void:
	surface_snap_enabled = enabled


func _on_door_window_changed(kind: int) -> void:
	door_window_kind = kind
	## 选择门窗类型后自动激活放置模式：用户直接点击墙面即可，
	## 否则未激活时点击会被编辑器接管并选中 CSG，造成"无法放置门窗"。
	if kind != RbShapeLibrary.DOOR_WINDOW.NONE:
		activate_place_mode()


## R 键/滚轮在门窗模式下于 门洞→窗洞→门→窗 间循环切换。
func cycle_door_window(forward: bool = true) -> void:
	const CYCLE := [
		RbShapeLibrary.DOOR_WINDOW.DOOR_HOLE,
		RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE,
		RbShapeLibrary.DOOR_WINDOW.DOOR,
		RbShapeLibrary.DOOR_WINDOW.WINDOW,
	]
	var index := CYCLE.find(door_window_kind)
	if index == -1:
		index = 0
	else:
		index = (index + (1 if forward else -1)) % CYCLE.size()
	if index < 0:
		index += CYCLE.size()
	var next: int = CYCLE[index]
	door_window_kind = next
	if dock != null and is_instance_valid(dock):
		dock.set_door_window_kind(next)
	## 类型变化后重建（隐藏的）普通幽灵并清空旧预览，下次 hover 显示新类型预览。
	if place_active:
		place_tool.clear_ghost()
		place_tool.rebuild_ghost()


## 同步旋转角度到 Dock 显示（R 键/滚轮旋转后调用）。
func sync_rotation_angle() -> void:
	if dock != null and is_instance_valid(dock):
		dock.set_rotation_angle(rad_to_deg(place_tool.ghost_rotation_y))


func _on_place_toggled(active: bool) -> void:
	if active:
		activate_place_mode()
	else:
		deactivate_place_mode()


func _on_shape_type_changed(shape_type: int) -> void:
	current_shape.shape_type = shape_type as RbShape.Type
	if place_active:
		place_tool.rebuild_ghost()


func _on_structure_preset_changed(preset_name: String) -> void:
	current_preset_name = preset_name


func _on_size_changed(size: Vector3) -> void:
	current_shape.size = size
	if place_active:
		place_tool.rebuild_ghost()


func _on_operation_changed(operation: int) -> void:
	current_operation = operation


func _on_snap_changed(enabled: bool, size: float) -> void:
	grid_enabled = enabled
	grid_size = size


func _on_rotation_step_changed(degrees: float) -> void:
	rotation_step = degrees


func _on_fixed_step_changed(enabled: bool, step: float) -> void:
	scale_step_enabled = enabled
	scale_step = maxf(step, 0.05)


func _on_color_changed(color: Color) -> void:
	## 若当前是网格材质，改色即切回默认灰色基础材质再设色（需 StandardMaterial3D）。
	if union_material == grid_material or not union_material is StandardMaterial3D:
		union_material = base_union_material
	if union_material != null:
		## 仅改共享材质的颜色；透明度始终由形状级独立材质控制，共享材质保持不透明。
		var std := union_material as StandardMaterial3D
		std.albedo_color = Color(color.r, color.g, color.b, 1.0)
		std.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	## 改色会重置 alpha，透明度预览开启时重新对形状应用淡出（不污染共享材质）。
	if whitebox_opacity < 1.0:
		set_whitebox_opacity(whitebox_opacity)


## 一键切换为网格材质（灰底 + 深灰网格线，基于局部坐标每格 1m，随表面对齐）。
func apply_grid_material() -> void:
	union_material = grid_material
	if place_active:
		place_tool.rebuild_ghost()


func _on_preview_opacity_changed(opacity: float) -> void:
	set_whitebox_opacity(opacity)


## 设置所有白盒形状的透明度（均匀淡出）。opacity 取值 0.0~1.0。
## 关键：绝不直接修改共享材质（whitebox_gray.tres）。对使用共享材质的形状，
## 先复制出独立材质再应用透明度，保证共享资源保持不透明、不影响后续放置的物体。
func set_whitebox_opacity(opacity: float) -> void:
	whitebox_opacity = clampf(opacity, 0.0, 1.0)
	## 同步脚本构建 API 的静态透明度，使 AI/脚本后续创建的节点也跟随淡出。
	RbSceneBuilder.set_whitebox_opacity(whitebox_opacity)
	if dock != null and is_instance_valid(dock):
		dock.set_preview_opacity(whitebox_opacity)
	var scene_root := editor_interface.get_edited_scene_root()
	if scene_root == null:
		return
	for shape in RbSurfaceSnap.collect_shapes(scene_root):
		_apply_shape_opacity(shape, whitebox_opacity)
	## 还原阶段：基线缓存里记录过的材质即使当前无形状引用也要一并还原，
	## 否则后续新放置的节点会残留淡出效果。
	if whitebox_opacity >= 1.0:
		for material in _mat_baseline.keys():
			_apply_material_opacity(material, 1.0)
		_mat_baseline.clear()
		## 恢复被替换材质的形状为共享引用：丢弃运行时创建的独立副本，
		## 使保存场景时材质始终外联共享资源，避免半透明副本被持久化到 .tscn。
		for shape in _opacity_original_material.keys():
			if shape != null and is_instance_valid(shape):
				(shape as CSGShape3D).material = _opacity_original_material[shape]
		_opacity_original_material.clear()


## 对单个形状应用透明度：使用共享材质（StandardMaterial3D 或 ShaderMaterial）的形状
## 先复制为独立材质，避免污染共享资源；再应用透明度淡出。
## 共享判断含 resource_path 为空（内联污染/历史副本）与共享引用比较，确保旧实例也被识别。
func _apply_shape_opacity(shape: CSGShape3D, opacity: float) -> void:
	var material: Material = shape.get("material") as Material
	if material == null:
		return
	## 仅当形状引用共享材质（union/网格）时复制独立副本，保护共享资源不被污染。
	## 独立材质（含历史内联副本，已在插件启动时清理）直接淡出，不重复替换。
	var is_shared := (
		material == union_material
		or material == base_union_material
		or material == grid_material)
	if is_shared:
		## 记录形状的原始共享材质，供 opacity==1.0 时恢复为共享引用。
		if not _opacity_original_material.has(shape):
			_opacity_original_material[shape] = material
		var fresh: Material
		if material is ShaderMaterial:
			fresh = (material as ShaderMaterial).duplicate() as ShaderMaterial
		else:
			fresh = (material as StandardMaterial3D).duplicate() as StandardMaterial3D
		## 记录基线 alpha=1.0：副本源自不透明共享材质，淡出/还原始终以 1.0 为基准。
		fresh.set_meta("rb_opacity_baseline", 1.0)
		shape.material = fresh
		material = fresh
	_apply_material_opacity(material, opacity)


## 对单个材质应用透明度：首次见时记录基线 alpha，
## opacity<1 开启 ALPHA 透明并按基线等比淡出，opacity==1 还原基线。
## 兼容 StandardMaterial3D（albedo_color.a + transparency）与网格 ShaderMaterial（alpha uniform）。
## 基线修正：无路径材质（内联污染副本）的原始 alpha 必为 1.0，避免把污染值当基线导致无法复原。
func _apply_material_opacity(material: Material, opacity: float) -> void:
	if material == null:
		return
	if material is ShaderMaterial:
		var shader_mat := material as ShaderMaterial
		if not _mat_baseline.has(shader_mat):
			var base_alpha: float = _baseline_alpha(shader_mat)
			_mat_baseline[shader_mat] = {"alpha": base_alpha}
		var baseline: Dictionary = _mat_baseline[shader_mat]
		shader_mat.set_shader_parameter("alpha", baseline["alpha"] * opacity)
		return
	if not material is StandardMaterial3D:
		return
	var std := material as StandardMaterial3D
	if not _mat_baseline.has(std):
		_mat_baseline[std] = {
			"transparency": BaseMaterial3D.TRANSPARENCY_DISABLED if _is_inline_or_runtime(std) else std.transparency,
			"alpha": _baseline_alpha(std),
		}
	var baseline: Dictionary = _mat_baseline[std]
	if opacity < 1.0:
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		std.albedo_color.a = baseline["alpha"] * opacity
	else:
		std.transparency = baseline["transparency"]
		std.albedo_color.a = baseline["alpha"]


## 判定材质是否为"内联副本或运行时副本"（非独立 .tres 资源）：
## 无资源路径，或路径是场景内联 SubResource（res://xxx.tscn::SubResourceID）。
## 这类材质源自共享材质副本，原始 alpha 应为 1.0，避免把污染值当基线导致无法复原。
func _is_inline_or_runtime(material: Material) -> bool:
	if material.has_meta("rb_opacity_baseline"):
		return true
	var path: String = material.resource_path
	return path.is_empty() or path.ends_with(".tscn") or ".tscn::" in path


## 取透明度基线：副本材质（meta 标记或内联/运行时）强制 1.0；独立 .tres 材质取当前值。
func _baseline_alpha(material: Material) -> float:
	if material.has_meta("rb_opacity_baseline"):
		return float(material.get_meta("rb_opacity_baseline"))
	if _is_inline_or_runtime(material):
		return 1.0
	if material is ShaderMaterial:
		var cur := (material as ShaderMaterial).get_shader_parameter("alpha")
		return cur if cur != null else 1.0
	return (material as StandardMaterial3D).albedo_color.a


## 一次性清理历史污染：把场景中"内联半透明材质"替换回共享引用。
## 历史版本透明度淡出会把运行时副本保存进 .tscn（内联 SubResource），
## 此处识别并恢复为 union/grid 共享材质，让旧场景打开后恢复正常（不透明、可随滑块淡出）。
## 判定依据：非共享引用 + StandardMaterial3D ALPHA 透明 + alpha<1（共享材质强制不透明）。
func _cleanup_inline_opacity_materials(scene_root: Node) -> void:
	if scene_root == null:
		return
	var fixed := 0
	for shape in RbSurfaceSnap.collect_shapes(scene_root):
		var material := shape.get("material")
		if material == null:
			continue
		## 已是共享引用的形状无需处理。
		if material == union_material or material == base_union_material or material == grid_material:
			continue
		if material is StandardMaterial3D:
			var std := material as StandardMaterial3D
			if std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and std.albedo_color.a < 1.0:
				shape.material = union_material
				fixed += 1
		elif material is ShaderMaterial:
			var shader_mat := material as ShaderMaterial
			var cur := shader_mat.get_shader_parameter("alpha")
			if cur != null and float(cur) < 1.0:
				shape.material = grid_material
				fixed += 1
	if fixed > 0:
		print("RB: 已清理 %d 个历史半透明材质，恢复为共享材质" % fixed)
		editor_interface.mark_scene_as_unsaved()


func _init_materials() -> void:
	## 强制绕过资源缓存重载共享灰色材质：防止历史透明度操作污染资源后，缓存实例
	## 仍带半透明残留（transparency=ALPHA / alpha<1），导致新放置的物体都半透明。
	union_material = ResourceLoader.load(
		"res://addons/rapid_block/materials/whitebox_gray.tres",
		"", ResourceLoader.CACHE_MODE_REPLACE) as StandardMaterial3D
	if union_material == null:
		union_material = _make_material(Color(0.78, 0.78, 0.78, 1), false)
	else:
		## 兜底：共享 union 材质必须始终不透明，透明度只由形状级独立材质控制。
		union_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		union_material.albedo_color.a = 1.0
	base_union_material = union_material
	grid_material = _make_grid_material()
	subtract_material = _make_material(Color(0.85, 0.2, 0.2, 0.6), true)
	intersect_material = _make_material(Color(0.2, 0.8, 0.3, 0.6), true)
	ghost_material = _make_material(Color(0.3, 0.7, 1.0, 0.4), true)
	door_preview_frame_material = _make_material(Color(0.2, 0.6, 1.0, 0.5), true)


## 构建网格材质：灰底 + 深灰网格线，基于物体局部坐标每格 1m。
## 局部坐标在 vertex 阶段捕获（fragment 的 VERTEX 是视图空间，会随相机/世界滑动），
## 经 varying 传给 fragment，网格固定在模型表面、随物体对齐，格子物理尺寸约 1m。
## 按表面法线排除主轴：每个面只用其两个切向轴画网格，避免法线方向恒定分量（0/极小值）
## 污染 min 值，导致顶/底面无网格且整面泛灰。线宽用屏幕导数自适应，避免摩尔纹。
func _make_grid_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque;
uniform vec4 base_color : source_color = vec4(0.78, 0.78, 0.78, 1.0);
uniform vec4 line_color : source_color = vec4(0.35, 0.35, 0.35, 1.0);
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex() {
	local_pos = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec3 n = abs(normalize(local_normal));
	vec3 wp = local_pos;
	vec3 g = abs(fract(wp - 0.5) - 0.5) / fwidth(wp);
	float d;
	if (n.x >= n.y && n.x >= n.z) {
		d = min(g.y, g.z);
	} else if (n.y >= n.x && n.y >= n.z) {
		d = min(g.x, g.z);
	} else {
		d = min(g.x, g.y);
	}
	float line = 1.0 - clamp(d, 0.0, 1.0);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
