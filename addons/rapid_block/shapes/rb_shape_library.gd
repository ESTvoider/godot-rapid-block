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


static func display_name(shape_type: int) -> String:
	return DISPLAY_NAMES.get(shape_type, "未知")


static func default_size(shape_type: int) -> Vector3:
	return DEFAULT_SIZES.get(shape_type, Vector3.ONE)


## 返回形状放在地面上时所需的高度偏移（原点在中心的形状抬高一半）。
static func origin_offset(shape: RbShape) -> float:
	if shape.shape_type == RbShape.Type.WEDGE or shape.shape_type == RbShape.Type.STAIRS:
		return 0.0
	return shape.size.y * 0.5


## 依据形状数据构建对应的 CSG 节点，并统一设置操作、材质与碰撞。
static func build_csg_shape(shape: RbShape, operation: int, material: Material) -> CSGShape3D:
	var node: CSGShape3D
	match shape.shape_type:
		RbShape.Type.BOX:
			var box := CSGBox3D.new()
			box.size = shape.size
			node = box
		RbShape.Type.CYLINDER:
			var cylinder := CSGCylinder3D.new()
			cylinder.radius = shape.size.x * 0.5
			cylinder.height = shape.size.y
			node = cylinder
		RbShape.Type.SPHERE:
			var sphere := CSGSphere3D.new()
			sphere.radius = shape.size.x * 0.5
			node = sphere
		RbShape.Type.PLANE:
			var plane := CSGBox3D.new()
			plane.size = Vector3(shape.size.x, 0.1, shape.size.z)
			node = plane
		RbShape.Type.WEDGE:
			var wedge := CSGPolygon3D.new()
			wedge.polygon = PackedVector2Array([
				Vector2(0, 0),
				Vector2(shape.size.z, 0),
				Vector2(shape.size.z, shape.size.y),
			])
			wedge.depth = shape.size.x
			node = wedge
		RbShape.Type.STAIRS:
			var stairs := CSGPolygon3D.new()
			stairs.polygon = _stairs_polygon(shape.size)
			stairs.depth = shape.size.x
			node = stairs
		RbShape.Type.CAPSULE:
			var capsule := CSGMesh3D.new()
			var mesh := CapsuleMesh.new()
			mesh.radius = shape.size.x * 0.5
			mesh.height = shape.size.y
			capsule.mesh = mesh
			node = capsule
		_:
			var fallback := CSGBox3D.new()
			fallback.size = shape.size
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
