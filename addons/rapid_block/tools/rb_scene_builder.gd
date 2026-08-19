@tool
class_name RbSceneBuilder
extends RefCounted
## 面向脚本/AI 驱动的白盒搭建 API，配合 godot_mcp 的编辑器脚本调用。
## 用法（在 godot_execute_editor_script 中）：
##   var b := load("res://addons/rapid_block/tools/rb_scene_builder.gd")
##   var c := b.find_or_create_combiner()
##   b.add_wall(6, 3, 0.2, Vector3.ZERO)
##   b.add_door(RbShapeLibrary.DOOR_WINDOW.DOOR, Vector3(0, 1.5, -2), Vector3.FORWARD, 0.2, c)

const NO_COLOR := Color(-1.0, -1.0, -1.0, 1.0)


static func scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()


## 在当前编辑场景中查找或创建白盒组合器。
static func find_or_create_combiner(name: String = "Whitebox") -> CSGCombiner3D:
	var root := _root()
	for child in root.get_children():
		if child is CSGCombiner3D and child.name == name:
			return child as CSGCombiner3D
	var combiner := CSGCombiner3D.new()
	combiner.name = name
	combiner.operation = CSGShape3D.OPERATION_UNION
	root.add_child(combiner)
	combiner.owner = root
	return combiner


## 添加任意类型形状，返回创建的 CSG 节点。
static func add_shape(shape_type: int, size: Vector3, position: Vector3 = Vector3.ZERO,
		operation: int = CSGShape3D.OPERATION_UNION, parent: Node = null,
		color: Color = NO_COLOR) -> CSGShape3D:
	var root := _root()
	var target := parent if parent != null else find_or_create_combiner()
	var shape := RbShape.new()
	shape.shape_type = shape_type as RbShape.Type
	shape.size = size
	var node := RbShapeLibrary.build_csg_shape(shape, operation, _make_material(color))
	node.position = position
	target.add_child(node)
	node.owner = root
	return node


static func add_box(size: Vector3, position: Vector3 = Vector3.ZERO,
		operation: int = CSGShape3D.OPERATION_UNION, parent: Node = null,
		color: Color = NO_COLOR) -> CSGBox3D:
	return add_shape(RbShape.Type.BOX, size, position, operation, parent, color) as CSGBox3D


static func add_cylinder(size: Vector3, position: Vector3 = Vector3.ZERO,
		operation: int = CSGShape3D.OPERATION_UNION, parent: Node = null,
		color: Color = NO_COLOR) -> CSGCylinder3D:
	return add_shape(RbShape.Type.CYLINDER, size, position, operation, parent, color) as CSGCylinder3D


static func add_sphere(size: Vector3, position: Vector3 = Vector3.ZERO,
		operation: int = CSGShape3D.OPERATION_UNION, parent: Node = null,
		color: Color = NO_COLOR) -> CSGSphere3D:
	return add_shape(RbShape.Type.SPHERE, size, position, operation, parent, color) as CSGSphere3D


static func add_wedge(size: Vector3, position: Vector3 = Vector3.ZERO,
		operation: int = CSGShape3D.OPERATION_UNION, parent: Node = null,
		color: Color = NO_COLOR) -> CSGPolygon3D:
	return add_shape(RbShape.Type.WEDGE, size, position, operation, parent, color) as CSGPolygon3D


## 便捷：添加一段墙（宽/高/厚）。
static func add_wall(width: float, height: float, thickness: float,
		position: Vector3 = Vector3.ZERO, color: Color = NO_COLOR) -> CSGBox3D:
	return add_box(Vector3(width, height, thickness), position, CSGShape3D.OPERATION_UNION, null, color)


## 便捷：添加一块地板。
static func add_floor(width: float, depth: float, thickness: float = 0.1,
		position: Vector3 = Vector3.ZERO, color: Color = NO_COLOR) -> CSGBox3D:
	return add_box(Vector3(width, thickness, depth), position, CSGShape3D.OPERATION_UNION, null, color)


## 在墙面添加门/窗（挖除洞 + 可选框），返回生成的节点列表。
static func add_door(kind: int, hit_pos: Vector3, normal: Vector3, wall_thickness: float,
		target: Node = null, color: Color = NO_COLOR) -> Array[CSGShape3D]:
	var root := _root()
	var combiner := target if target is CSGCombiner3D else find_or_create_combiner()
	var subtract_mat := _make_material(Color(0.85, 0.2, 0.2, 0.6)) as StandardMaterial3D
	var union_mat := _make_material(color) as StandardMaterial3D
	if subtract_mat != null:
		subtract_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var is_window: bool = kind == RbShapeLibrary.DOOR_WINDOW.WINDOW_HOLE or kind == RbShapeLibrary.DOOR_WINDOW.WINDOW
	var width := RbShapeLibrary.WINDOW_WIDTH if is_window else RbShapeLibrary.DOOR_WIDTH
	var height := RbShapeLibrary.WINDOW_HEIGHT if is_window else RbShapeLibrary.DOOR_HEIGHT
	var center_y := RbShapeLibrary.WINDOW_SILL + height * 0.5 if is_window else height * 0.5
	var yaw := atan2(normal.x, normal.z)
	var center := Vector3(hit_pos.x, center_y, hit_pos.z) - normal * (wall_thickness * 0.5)
	var nodes := RbShapeLibrary.build_door_window(kind, wall_thickness, subtract_mat, union_mat)
	for n in nodes:
		n.position = center
		n.rotation = Vector3(0, yaw, 0)
		combiner.add_child(n)
		n.owner = root
	return nodes


## 阵列复制源节点并挂入同一父节点。
static func array_duplicate(source: Node3D, rows: int, cols: int, spacing: float) -> Array[Node3D]:
	var parent := source.get_parent()
	var nodes := RbTransformTools.array_duplicate(source, rows, cols, spacing)
	for n in nodes:
		parent.add_child(n)
		n.owner = _root()
	return nodes


## 镜像复制源节点并挂入同一父节点。
static func mirror_duplicate(source: Node3D, flip_x: bool) -> Node3D:
	var parent := source.get_parent()
	var node := RbTransformTools.mirror_duplicate(source, flip_x)
	parent.add_child(node)
	node.owner = _root()
	return node


## 烘焙 CSG 为 Mesh 节点并隐藏原 CSG。
static func bake(csg: CSGShape3D) -> Node3D:
	var root := _root()
	var node := RbBake.bake(csg)
	root.add_child(node)
	node.owner = root
	csg.visible = false
	return node


## 为节点及其后代 CSG 设置独立材质颜色（不受 Dock 共享颜色影响）。
static func set_color(node: Node, color: Color) -> void:
	if node is CSGShape3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		(node as CSGShape3D).material = material
	for child in node.get_children():
		set_color(child, color)


static func _root() -> Node:
	var root := scene_root()
	assert(root != null, "需要先打开一个 3D 场景")
	return root


static func _make_material(color: Color) -> Material:
	if color.r < 0.0:
		return null
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
