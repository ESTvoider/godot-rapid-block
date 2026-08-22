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
var place_active := false
var drag_enabled := true
var surface_snap_enabled := false
var door_window_kind: int = RbShapeLibrary.DOOR_WINDOW.NONE
var whitebox_opacity := 1.0
var _tracked_scene_root: Node = null
## 材质基线缓存：材质资源 -> { "transparency": int, "alpha": float }，用于透明度预览的还原。
var _mat_baseline: Dictionary = {}

var union_material: Material
## 默认灰色基础材质（whitebox_gray），供"默认"按钮切回。
var base_union_material: StandardMaterial3D
## 网格材质：默认灰底 + 深灰 1m 网格线（世界坐标），供"网格"按钮切换。
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
	dock_root = DOCK_SCENE.instantiate()
	dock = dock_root.get_node("RapidBlockDockContent") as RapidBlockDock
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock_root)
	_connect_dock_signals()


## 让插件处理 Node3D 类型对象（否则 `_forward_3d_gui_input` 不会被调用）。
func _handles(object: Object) -> bool:
	return object is Node3D


func _exit_tree() -> void:
	deactivate_place_mode()
	if dock_root != null and is_instance_valid(dock_root):
		remove_control_from_docks(dock_root)
		dock_root.queue_free()


## Godot 4.7 中返回 int：1 表示消费输入，0 表示放行给编辑器。
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not place_active:
		return 0
	return 1 if place_tool.handle_input(camera, event) else 0


## 轮询场景根：切换/关闭场景时自动退出放置模式，清理幽灵预览。
func _process(_delta: float) -> void:
	if not place_active:
		return
	if editor_interface.get_edited_scene_root() != _tracked_scene_root:
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


func _on_color_changed(color: Color) -> void:
	## 若当前是网格材质，改色即切回默认灰色基础材质再设色（需 StandardMaterial3D）。
	if union_material is not StandardMaterial3D:
		union_material = base_union_material
	if union_material != null:
		(union_material as StandardMaterial3D).albedo_color = color
	## 改色会重置 alpha，透明度预览开启时重新套用，保持淡出效果。
	if whitebox_opacity < 1.0:
		_apply_shape_opacity(union_material, whitebox_opacity)


## 一键切换为网格材质（默认灰底 + 深灰世界坐标 1m 网格线）。
func apply_grid_material() -> void:
	union_material = grid_material
	if place_active:
		place_tool.rebuild_ghost()


func _on_preview_opacity_changed(opacity: float) -> void:
	set_whitebox_opacity(opacity)


## 设置所有白盒形状的透明度（均匀淡出）。opacity 取值 0.0~1.0。
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
		_apply_shape_opacity(shape.material, whitebox_opacity)
	## 还原阶段：基线缓存里记录过的材质即使当前无形状引用（如共享 union 材质被结构色替换）
	## 也要一并还原，否则后续新放置的节点会残留淡出效果。
	if whitebox_opacity >= 1.0:
		for material in _mat_baseline.keys():
			_apply_shape_opacity(material, 1.0)
		_mat_baseline.clear()


## 对单个材质应用透明度：首次见时记录基线（原 transparency/alpha），
## opacity<1 开启 ALPHA 透明并按基线等比淡出，opacity==1 还原基线。
func _apply_shape_opacity(material: Material, opacity: float) -> void:
	if material == null or not material is StandardMaterial3D:
		return
	var std := material as StandardMaterial3D
	if not _mat_baseline.has(std):
		_mat_baseline[std] = {
			"transparency": std.transparency,
			"alpha": std.albedo_color.a,
		}
	var baseline: Dictionary = _mat_baseline[std]
	if opacity < 1.0:
		std.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		std.albedo_color.a = baseline["alpha"] * opacity
	else:
		std.transparency = baseline["transparency"]
		std.albedo_color.a = baseline["alpha"]


func _init_materials() -> void:
	union_material = load("res://addons/rapid_block/materials/whitebox_gray.tres") as StandardMaterial3D
	if union_material == null:
		union_material = _make_material(Color(0.78, 0.78, 0.78, 1), false)
	base_union_material = union_material
	grid_material = _make_grid_material()
	subtract_material = _make_material(Color(0.85, 0.2, 0.2, 0.6), true)
	intersect_material = _make_material(Color(0.2, 0.8, 0.3, 0.6), true)
	ghost_material = _make_material(Color(0.3, 0.7, 1.0, 0.4), true)
	door_preview_frame_material = _make_material(Color(0.2, 0.6, 1.0, 0.5), true)


## 构建网格材质：默认灰底 + 深灰网格线，每格 1m（世界坐标，固定不随物体移动/旋转/缩放）。
## 网格基于世界坐标 MODEL_MATRIX*VERTEX；关闭金属度与镜面反射避免反光。
func _make_grid_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.78, 0.78, 0.78, 1.0);
uniform vec4 line_color : source_color = vec4(0.35, 0.35, 0.35, 1.0);
void fragment() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 g = abs(fract(wp - 0.5) - 0.5) / fwidth(wp);
	float line = 1.0 - min(min(g.x, g.y), g.z);
	ALBEDO = mix(base_color.rgb, line_color.rgb, clamp(line, 0.0, 1.0));
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
