@tool
class_name RapidBlockPlugin
extends EditorPlugin
## 快速白盒搭建：注册右侧 Dock 面板，并接管 3D 视口放置输入。

const DOCK_SCENE := preload("res://addons/rapid_block/dock/rapid_block_dock.tscn")
const PLACE_TOOL_SCRIPT := preload("res://addons/rapid_block/tools/rb_place_tool.gd")

var dock: RapidBlockDock
var place_tool: RbPlaceTool
var undo_redo: EditorUndoRedoManager
var editor_interface: EditorInterface

var current_shape: RbShape
var current_operation: int = CSGShape3D.OPERATION_UNION
var grid_enabled := true
var grid_size := 0.5
var rotation_step := 90.0
var place_active := false
var _tracked_scene_root: Node = null

var union_material: StandardMaterial3D
var subtract_material: StandardMaterial3D
var intersect_material: StandardMaterial3D
var ghost_material: StandardMaterial3D


func _enter_tree() -> void:
	editor_interface = get_editor_interface()
	undo_redo = get_undo_redo()
	current_shape = RbShape.new()
	_init_materials()
	place_tool = PLACE_TOOL_SCRIPT.new(self)
	dock = DOCK_SCENE.instantiate()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, dock)
	_connect_dock_signals()


func _exit_tree() -> void:
	deactivate_place_mode()
	if dock != null and is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()


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


func _on_place_toggled(active: bool) -> void:
	if active:
		activate_place_mode()
	else:
		deactivate_place_mode()


func _on_shape_type_changed(shape_type: int) -> void:
	current_shape.shape_type = shape_type as RbShape.Type
	if place_active:
		place_tool.rebuild_ghost()


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
	if union_material != null:
		union_material.albedo_color = color


func _init_materials() -> void:
	union_material = load("res://addons/rapid_block/materials/whitebox_gray.tres") as StandardMaterial3D
	if union_material == null:
		union_material = _make_material(Color(0.78, 0.78, 0.78, 1), false)
	subtract_material = _make_material(Color(0.85, 0.2, 0.2, 0.6), true)
	intersect_material = _make_material(Color(0.2, 0.8, 0.3, 0.6), true)
	ghost_material = _make_material(Color(0.3, 0.7, 1.0, 0.4), true)


func _make_material(color: Color, transparent: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
