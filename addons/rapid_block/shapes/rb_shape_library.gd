@tool
class_name RbShapeLibrary
extends RefCounted
## 白盒形状的静态数据与 CSG 节点构建逻辑（单一事实来源）。

const DISPLAY_NAMES: Dictionary = {
	RbShape.Type.BOX: "方块",
	RbShape.Type.CYLINDER: "圆柱",
	RbShape.Type.SPHERE: "球体",
	RbShape.Type.WEDGE: "斜坡",
	RbShape.Type.STAIRS: "台阶",
	RbShape.Type.PLANE: "平面",
	RbShape.Type.CAPSULE: "胶囊",
}

const DEFAULT_SIZES: Dictionary = {
	RbShape.Type.BOX: Vector3(2, 2, 2),
	RbShape.Type.CYLINDER: Vector3(1, 3, 1),
	RbShape.Type.SPHERE: Vector3(2, 2, 2),
	RbShape.Type.WEDGE: Vector3(3, 2, 2),
	RbShape.Type.STAIRS: Vector3(3, 1.5, 2),
	RbShape.Type.PLANE: Vector3(4, 0.1, 4),
	RbShape.Type.CAPSULE: Vector3(1.2, 2.5, 1.2),
}

enum DOOR_WINDOW { NONE, DOOR_HOLE, WINDOW_HOLE, DOOR, WINDOW }

const DOOR_WINDOW_NAMES: Dictionary = {
	DOOR_WINDOW.NONE: "无",
	DOOR_WINDOW.DOOR_HOLE: "门洞",
	DOOR_WINDOW.WINDOW_HOLE: "窗洞",
	DOOR_WINDOW.DOOR: "门（带框）",
	DOOR_WINDOW.WINDOW: "窗（带框）",
}

const DOOR_WIDTH := 0.9
const DOOR_HEIGHT := 2.1
const WINDOW_WIDTH := 1.5
const WINDOW_HEIGHT := 1.2
const WINDOW_SILL := 0.9
const FRAME_THICKNESS := 0.06


static func door_window_name(kind: int) -> String:
	return DOOR_WINDOW_NAMES.get(kind, "未知")


static func display_name(shape_type: int) -> String:
	return DISPLAY_NAMES.get(shape_type, "未知")


static func default_size(shape_type: int) -> Vector3:
	return DEFAULT_SIZES.get(shape_type, Vector3.ONE)


## 返回形状放在地面上时所需的高度偏移（原点在中心的形状抬高一半）。
static func origin_offset(shape: RbShape) -> float:
	if shape.shape_type == RbShape.Type.WEDGE or shape.shape_type == RbShape.Type.STAIRS:
		return 0.0
	return shape.size.y * 0.5


## 拖拽拉伸生成时的底平偏移：原点在底部（斜坡/台阶）为 0，其余抬高一半高度。
static func base_offset(shape_type: int, height: float) -> float:
	if shape_type == RbShape.Type.WEDGE or shape_type == RbShape.Type.STAIRS:
		return 0.0
	return height * 0.5


## 依据形状数据构建对应的 CSG 节点，并统一设置操作、材质与碰撞。
static func build_csg_shape(shape: RbShape, operation: int, material: Material) -> CSGShape3D:
	return _build_node(shape.shape_type, shape.size, operation, material)


## 按 类型/宽/深/高 构建形状（拖拽拉伸入口）。宽深映射到形状的地面投影尺寸。
static func build_csg_from_dims(shape_type: int, width: float, depth: float, height: float, operation: int, material: Material) -> CSGShape3D:
	var size := Vector3.ONE
	match shape_type:
		RbShape.Type.CYLINDER, RbShape.Type.CAPSULE:
			var radius := minf(width, depth) * 0.5
			size = Vector3(radius * 2.0, height, radius * 2.0)
		RbShape.Type.SPHERE:
			size = Vector3(minf(width, depth), minf(width, depth), minf(width, depth))
		RbShape.Type.WEDGE, RbShape.Type.STAIRS:
			size = Vector3(depth, height, width)
		_:
			size = Vector3(width, height, depth)
	return _build_node(shape_type, size, operation, material)


## 构建门/窗组合节点（挖除洞 + 可选门/窗框），整体作为独立子节点使用。
## 调用方负责设置 position/rotation 并挂入墙所属的组合器。
static func build_door_window(kind: int, wall_thickness: float, subtract_material: Material, union_material: Material) -> Array[CSGShape3D]:
	var nodes: Array[CSGShape3D] = []
	var is_window: bool = kind == DOOR_WINDOW.WINDOW_HOLE or kind == DOOR_WINDOW.WINDOW
	var is_framed: bool = kind == DOOR_WINDOW.DOOR or kind == DOOR_WINDOW.WINDOW
	var width := WINDOW_WIDTH if is_window else DOOR_WIDTH
	var height := WINDOW_HEIGHT if is_window else DOOR_HEIGHT
	var hole := CSGBox3D.new()
	hole.size = Vector3(width, height, wall_thickness + 0.4)
	hole.operation = CSGShape3D.OPERATION_SUBTRACTION
	hole.material = subtract_material
	hole.use_collision = true
	nodes.append(hole)
	if not is_framed:
		return nodes
	var frame := FRAME_THICKNESS
	var vpost := CSGBox3D.new()
	vpost.size = Vector3(frame, height, frame)
	vpost.operation = CSGShape3D.OPERATION_UNION
	vpost.material = union_material
	vpost.use_collision = true
	var hpost := CSGBox3D.new()
	hpost.size = Vector3(width + frame * 2.0, frame, frame)
	hpost.operation = CSGShape3D.OPERATION_UNION
	hpost.material = union_material
	hpost.use_collision = true
	var side_offset := width * 0.5 + frame * 0.5
	nodes.append(vpost.duplicate() as CSGShape3D)
	nodes[1].position = Vector3(side_offset, 0, 0)
	var vpost2 := vpost.duplicate() as CSGShape3D
	vpost2.position = Vector3(-side_offset, 0, 0)
	nodes.append(vpost2)
	nodes.append(hpost.duplicate() as CSGShape3D)
	nodes[3].position = Vector3(0, height * 0.5 + frame * 0.5, 0)
	if is_window:
		var bottom := hpost.duplicate() as CSGShape3D
		bottom.position = Vector3(0, -height * 0.5 - frame * 0.5, 0)
		nodes.append(bottom)
	return nodes


static func _build_node(shape_type: int, size: Vector3, operation: int, material: Material) -> CSGShape3D:
	var node: CSGShape3D
	match shape_type:
		RbShape.Type.BOX:
			var box := CSGBox3D.new()
			box.size = size
			node = box
		RbShape.Type.CYLINDER:
			var cylinder := CSGCylinder3D.new()
			cylinder.radius = size.x * 0.5
			cylinder.height = size.y
			node = cylinder
		RbShape.Type.SPHERE:
			var sphere := CSGSphere3D.new()
			sphere.radius = size.x * 0.5
			node = sphere
		RbShape.Type.PLANE:
			var plane := CSGBox3D.new()
			plane.size = Vector3(size.x, 0.1, size.z)
			node = plane
		RbShape.Type.WEDGE:
			var wedge := CSGPolygon3D.new()
			wedge.polygon = PackedVector2Array([
				Vector2(0, 0),
				Vector2(size.z, 0),
				Vector2(size.z, size.y),
			])
			wedge.depth = size.x
			node = wedge
		RbShape.Type.STAIRS:
			var stairs := CSGPolygon3D.new()
			stairs.polygon = _stairs_polygon(size)
			stairs.depth = size.x
			node = stairs
		RbShape.Type.CAPSULE:
			var capsule := CSGMesh3D.new()
			var mesh := CapsuleMesh.new()
			mesh.radius = size.x * 0.5
			mesh.height = size.y
			capsule.mesh = mesh
			node = capsule
		_:
			var fallback := CSGBox3D.new()
			fallback.size = size
			node = fallback
	node.operation = operation
	node.material = material
	node.use_collision = true
	return node


## 由尺寸推导台阶轮廓（多边形位于 XY 平面，宽度沿 X，高度沿 Y，长度沿挤出轴）。
static func _stairs_polygon(size: Vector3) -> PackedVector2Array:
	var width := size.z
	var height := size.y
	var steps := maxi(1, int(round(height / 0.2)))
	var run := width / steps
	var rise := height / steps
	var points := PackedVector2Array()
	points.append(Vector2(0, 0))
	for i in range(steps):
		points.append(Vector2(run * (i + 1), rise * i))
		points.append(Vector2(run * (i + 1), rise * (i + 1)))
	return points
