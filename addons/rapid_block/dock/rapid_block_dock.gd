@tool
class_name RapidBlockDock
extends VBoxContainer
## 快速白盒搭建控制面板：形状调色板、操作模式、吸附与尺寸设置。

signal place_toggled(active: bool)
signal shape_type_changed(shape_type: int)
signal size_changed(size: Vector3)
signal operation_changed(operation: int)
signal snap_changed(enabled: bool, size: float)
signal rotation_step_changed(degrees: float)
signal color_changed(color: Color)
signal drag_toggled(enabled: bool)
signal surface_snap_changed(enabled: bool)
signal drag_height_changed(height: float)
signal door_window_changed(kind: int)
signal bake_requested()
signal array_requested(rows: int, cols: int, spacing: float)
signal mirror_requested(flip_x: bool)

var _current_type: int = RbShape.Type.BOX
var _updating_size := false

@onready var place_button: Button = %PlaceButton
@onready var operation_box: OptionButton = %OperationBox
@onready var shape_grid: GridContainer = %ShapeGrid
@onready var size_preset_box: OptionButton = %SizePresetBox
@onready var size_x: SpinBox = %SizeX
@onready var size_y: SpinBox = %SizeY
@onready var size_z: SpinBox = %SizeZ
@onready var snap_enabled: CheckBox = %SnapEnabled
@onready var snap_size: SpinBox = %SnapSize
@onready var rotation_step: SpinBox = %RotationStep
@onready var angle_label: Label = %AngleLabel
@onready var drag_check: CheckBox = %DragCheck
@onready var surface_snap_check: CheckBox = %SurfaceSnapCheck
@onready var drag_height_spin: SpinBox = %DragHeightSpin
@onready var door_window_box: OptionButton = %DoorWindowBox
@onready var bake_button: Button = %BakeButton
@onready var array_rows: SpinBox = %ArrayRows
@onready var array_cols: SpinBox = %ArrayCols
@onready var array_spacing: SpinBox = %ArraySpacing
@onready var array_button: Button = %ArrayButton
@onready var mirror_button: Button = %MirrorButton
@onready var mirror_z_button: Button = %MirrorZButton
@onready var color_button: ColorPickerButton = %ColorButton


func _ready() -> void:
	_build_shape_buttons()
	_connect_ui()


## 供插件在外部退出放置模式时同步按钮状态。
func set_place_button_active(active: bool) -> void:
	if place_button.button_pressed != active:
		place_button.set_pressed_no_signal(active)


## 供插件同步当前旋转角度显示。
func set_rotation_angle(degrees: float) -> void:
	angle_label.text = "角度：%d°" % int(roundf(degrees))


func _build_shape_buttons() -> void:
	var types := [
		RbShape.Type.BOX,
		RbShape.Type.CYLINDER,
		RbShape.Type.SPHERE,
		RbShape.Type.PLANE,
		RbShape.Type.WEDGE,
		RbShape.Type.STAIRS,
		RbShape.Type.CAPSULE,
	]
	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	for shape_type in types:
		var button := Button.new()
		button.text = RbShapeLibrary.display_name(shape_type)
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func() -> void: _on_shape_button(shape_type))
		shape_grid.add_child(button)
		buttons.append(button)
	if not buttons.is_empty():
		buttons[0].button_pressed = true


func _connect_ui() -> void:
	place_button.toggled.connect(func(active: bool) -> void: place_toggled.emit(active))
	operation_box.item_selected.connect(func(index: int) -> void: operation_changed.emit(_operation_for_index(index)))
	size_preset_box.item_selected.connect(_on_preset_selected)
	size_x.value_changed.connect(_on_size_value_changed)
	size_y.value_changed.connect(_on_size_value_changed)
	size_z.value_changed.connect(_on_size_value_changed)
	snap_enabled.toggled.connect(func(_active: bool) -> void: snap_changed.emit(snap_enabled.button_pressed, snap_size.value))
	snap_size.value_changed.connect(func(_value: float) -> void: snap_changed.emit(snap_enabled.button_pressed, snap_size.value))
	rotation_step.value_changed.connect(func(value: float) -> void: rotation_step_changed.emit(value))
	drag_check.toggled.connect(func(enabled: bool) -> void: drag_toggled.emit(enabled))
	surface_snap_check.toggled.connect(func(enabled: bool) -> void: surface_snap_changed.emit(enabled))
	drag_height_spin.value_changed.connect(func(value: float) -> void: drag_height_changed.emit(value))
	door_window_box.item_selected.connect(func(index: int) -> void: door_window_changed.emit(index))
	bake_button.pressed.connect(func() -> void: bake_requested.emit())
	array_button.pressed.connect(func() -> void: array_requested.emit(
		int(array_rows.value), int(array_cols.value), array_spacing.value))
	mirror_button.pressed.connect(func() -> void: mirror_requested.emit(true))
	mirror_z_button.pressed.connect(func() -> void: mirror_requested.emit(false))
	color_button.color_changed.connect(func(color: Color) -> void: color_changed.emit(color))


func _on_shape_button(shape_type: int) -> void:
	_current_type = shape_type
	_apply_size(RbShapeLibrary.default_size(shape_type))
	shape_type_changed.emit(shape_type)
	size_changed.emit(_current_size())


func _on_size_value_changed(_value: float) -> void:
	if _updating_size:
		return
	size_changed.emit(_current_size())


func _on_preset_selected(index: int) -> void:
	match index:
		0:
			_apply_size(RbShapeLibrary.default_size(_current_type))
		1:
			_apply_size(Vector3(3.0, 2.8, 0.2))
		2:
			_apply_size(Vector3(4.0, 3.0, 0.2))
		3:
			_apply_size(Vector3(6.0, 0.1, 6.0))
	size_changed.emit(_current_size())


func _apply_size(size: Vector3) -> void:
	_updating_size = true
	size_x.value = size.x
	size_y.value = size.y
	size_z.value = size.z
	_updating_size = false


func _current_size() -> Vector3:
	return Vector3(size_x.value, size_y.value, size_z.value)


func _operation_for_index(index: int) -> int:
	match index:
		1:
			return CSGShape3D.OPERATION_SUBTRACTION
		2:
			return CSGShape3D.OPERATION_INTERSECTION
		_:
			return CSGShape3D.OPERATION_UNION
