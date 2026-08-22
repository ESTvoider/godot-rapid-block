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
signal door_window_changed(kind: int)
signal preview_opacity_changed(opacity: float)
signal bake_requested()
signal array_requested(rows: int, cols: int, spacing: float)
signal mirror_requested(flip_x: bool)
signal path_copy_requested(end_offset: Vector3, count: int)
signal export_requested(path: String)
signal colorize_requested(kind: int)
## 结构预设名变更："" 表示普通几何，非空表示当前选中某结构预设（供放置命名体现语义）。
signal structure_preset_changed(preset_name: String)

## 放置激活时的高亮背景色（与幽灵预览材质呼应，保证"正在放置"一目了然）。
const PLACE_ACTIVE_COLOR := Color(0.2, 0.55, 0.95, 1.0)

var _current_type: int = RbShape.Type.BOX
var _updating_size := false

@onready var place_button: Button = %PlaceButton
@onready var operation_box: OptionButton = %OperationBox
@onready var shape_grid: GridContainer = %ShapeGrid
@onready var structure_grid: GridContainer = %StructureGrid
@onready var size_x: SpinBox = %SizeX
@onready var size_y: SpinBox = %SizeY
@onready var size_z: SpinBox = %SizeZ
@onready var snap_enabled: CheckBox = %SnapEnabled
@onready var snap_size: SpinBox = %SnapSize
@onready var rotation_step: SpinBox = %RotationStep
@onready var angle_label: Label = %AngleLabel
@onready var drag_check: CheckBox = %DragCheck
@onready var surface_snap_check: CheckBox = %SurfaceSnapCheck
@onready var door_window_box: OptionButton = %DoorWindowBox
@onready var opacity_slider: HSlider = %OpacitySlider
@onready var opacity_value: Label = %OpacityValue
@onready var bake_button: Button = %BakeButton
@onready var array_rows: SpinBox = %ArrayRows
@onready var array_cols: SpinBox = %ArrayCols
@onready var array_spacing: SpinBox = %ArraySpacing
@onready var array_button: Button = %ArrayButton
@onready var mirror_button: Button = %MirrorButton
@onready var mirror_z_button: Button = %MirrorZButton
@onready var path_count: SpinBox = %PathCount
@onready var path_offset_x: SpinBox = %PathOffsetX
@onready var path_offset_y: SpinBox = %PathOffsetY
@onready var path_offset_z: SpinBox = %PathOffsetZ
@onready var path_button: Button = %PathButton
@onready var export_path: LineEdit = %ExportPath
@onready var export_button: Button = %ExportButton
@onready var colorize_grid: GridContainer = %ColorizeGrid
@onready var color_button: ColorPickerButton = %ColorButton
@onready var color_preview: ColorRect = %ColorPreview
@onready var color_hex_label: Label = %ColorHexLabel


func _ready() -> void:
	## SpinBox 按 step 吸附数值，step 必须与 min_value 对齐（0.05 起始），
	## 否则预设尺寸（如 2.8 / 0.2）会被吸附偏移，放出的物体与预设严重不符。
	## 此处显式设置以绕过 tscn 资源缓存。
	size_x.step = 0.05
	size_y.step = 0.05
	size_z.step = 0.05
	_build_shape_buttons()
	_build_colorize_buttons()
	_connect_ui()
	_update_color_preview(color_button.color)
	_update_place_button_visual(place_button.button_pressed)


## 供插件在外部退出放置模式时同步按钮状态。
func set_place_button_active(active: bool) -> void:
	if place_button.button_pressed != active:
		place_button.set_pressed_no_signal(active)
	_update_place_button_visual(active)


## 供插件同步当前旋转角度显示。
func set_rotation_angle(degrees: float) -> void:
	angle_label.text = "角度：%d°" % int(roundf(degrees))


## 供插件/脚本外部回写透明度滑块（不触发 value_changed 信号）。
func set_preview_opacity(opacity: float) -> void:
	var value := clampf(opacity, 0.0, 1.0)
	opacity_slider.set_value_no_signal(value)
	opacity_value.text = "%d%%" % int(roundf(value * 100.0))


## 供插件在 R 键/滚轮循环门窗类型时同步选择框（不触发 item_selected 信号）。
func set_door_window_kind(kind: int) -> void:
	door_window_box.select(kind)


func _on_place_toggled(active: bool) -> void:
	place_toggled.emit(active)
	_update_place_button_visual(active)


## 放置按钮的状态化：激活时高亮背景、切换文字与提示，让用户随时能确认是否处于放置状态。
func _update_place_button_visual(active: bool) -> void:
	place_button.text = "停止放置" if active else "开始放置"
	place_button.tooltip_text = (
		"放置模式已开启：左键放置，拖拽拉伸，R 旋转，右键/Esc 退出"
		if active else
		"开启放置模式：在 3D 视口点击放置白盒"
	)
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = PLACE_ACTIVE_COLOR
		style.set_corner_radius_all(4)
		place_button.add_theme_stylebox_override("normal", style)
		place_button.add_theme_stylebox_override("hover", style)
		place_button.add_theme_stylebox_override("pressed", style)
		place_button.add_theme_color_override("font_color", Color.WHITE)
	else:
		place_button.remove_theme_stylebox_override("normal")
		place_button.remove_theme_stylebox_override("hover")
		place_button.remove_theme_stylebox_override("pressed")
		place_button.remove_theme_color_override("font_color")


func _on_color_changed(color: Color) -> void:
	color_changed.emit(color)
	_update_color_preview(color)


## 白盒透明度滑块：更新百分比显示并转发给插件。
func _on_opacity_changed(value: float) -> void:
	opacity_value.text = "%d%%" % int(roundf(value * 100.0))
	preview_opacity_changed.emit(value)


## 同步色块预览与十六进制值，让用户随时能看清当前选择的添加颜色。
func _update_color_preview(color: Color) -> void:
	color_preview.color = color
	color_hex_label.text = "#%s" % color.to_html(false).to_upper()


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
	## 结构预设与几何形状同组互斥，但独立分块展示：选中即切到对应形状+默认尺寸。
	## 几何按钮放入 shape_grid，结构按钮放入 structure_grid，视觉上单独标出。
	for preset_name in RbShapeLibrary.STRUCTURE_PRESETS:
		var preset: Dictionary = RbShapeLibrary.STRUCTURE_PRESETS[preset_name]
		var button := Button.new()
		button.text = preset_name
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = "预设尺寸：%.2f × %.2f × %.2f" % [preset["size"].x, preset["size"].y, preset["size"].z]
		button.pressed.connect(func() -> void: _on_structure_button(preset_name))
		structure_grid.add_child(button)
		buttons.append(button)
	if not buttons.is_empty():
		buttons[0].button_pressed = true


func _connect_ui() -> void:
	place_button.toggled.connect(_on_place_toggled)
	operation_box.item_selected.connect(func(index: int) -> void: operation_changed.emit(_operation_for_index(index)))
	size_x.value_changed.connect(_on_size_value_changed)
	size_y.value_changed.connect(_on_size_value_changed)
	size_z.value_changed.connect(_on_size_value_changed)
	snap_enabled.toggled.connect(func(_active: bool) -> void: snap_changed.emit(snap_enabled.button_pressed, snap_size.value))
	snap_size.value_changed.connect(func(_value: float) -> void: snap_changed.emit(snap_enabled.button_pressed, snap_size.value))
	rotation_step.value_changed.connect(func(value: float) -> void: rotation_step_changed.emit(value))
	drag_check.toggled.connect(func(enabled: bool) -> void: drag_toggled.emit(enabled))
	surface_snap_check.toggled.connect(func(enabled: bool) -> void: surface_snap_changed.emit(enabled))
	door_window_box.item_selected.connect(func(index: int) -> void: door_window_changed.emit(index))
	opacity_slider.value_changed.connect(_on_opacity_changed)
	bake_button.pressed.connect(func() -> void: bake_requested.emit())
	array_button.pressed.connect(func() -> void: array_requested.emit(
		int(array_rows.value), int(array_cols.value), array_spacing.value))
	mirror_button.pressed.connect(func() -> void: mirror_requested.emit(true))
	mirror_z_button.pressed.connect(func() -> void: mirror_requested.emit(false))
	path_button.pressed.connect(func() -> void: path_copy_requested.emit(
		Vector3(path_offset_x.value, path_offset_y.value, path_offset_z.value),
		int(path_count.value)))
	export_button.pressed.connect(func() -> void: export_requested.emit(export_path.text))
	color_button.color_changed.connect(_on_color_changed)


func _build_colorize_buttons() -> void:
	var kinds := [
		RbColorize.STRUCTURE.WALL,
		RbColorize.STRUCTURE.FLOOR,
		RbColorize.STRUCTURE.STRUCTURE,
		RbColorize.STRUCTURE.INTERACTABLE,
	]
	for kind in kinds:
		var button := Button.new()
		button.text = RbColorize.structure_name(kind)
		button.tooltip_text = "将选中节点着色为：%s" % RbColorize.structure_name(kind)
		button.pressed.connect(func() -> void: colorize_requested.emit(kind))
		colorize_grid.add_child(button)


func _on_shape_button(shape_type: int) -> void:
	_current_type = shape_type
	_apply_size(RbShapeLibrary.default_size(shape_type))
	structure_preset_changed.emit("")
	shape_type_changed.emit(shape_type)
	size_changed.emit(_current_size())


func _on_size_value_changed(_value: float) -> void:
	if _updating_size:
		return
	size_changed.emit(_current_size())


func _on_structure_button(preset_name: String) -> void:
	var preset: Dictionary = RbShapeLibrary.STRUCTURE_PRESETS.get(preset_name, {})
	if preset.is_empty():
		return
	var shape_type: int = preset["shape_type"]
	var size: Vector3 = preset["size"]
	_current_type = shape_type
	_apply_size(size)
	structure_preset_changed.emit(preset_name)
	shape_type_changed.emit(shape_type)
	size_changed.emit(_current_size())


func _apply_size(size: Vector3) -> void:
	_updating_size = true
	## 每次设尺寸前确保 step 与 min_value 对齐（0.05 起始），
	## 否则预设尺寸（如 2.8 / 0.2）会被 SpinBox 吸附偏移。
	size_x.step = 0.05
	size_y.step = 0.05
	size_z.step = 0.05
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
