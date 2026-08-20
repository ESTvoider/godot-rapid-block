@tool
class_name RbSurfaceSnap
extends RefCounted
## 表面吸附工具：射线与场景内 CSG 全局 AABB 求交，推导命中面外向法线。
## 对轴对齐白盒足够精确，且不依赖编辑器物理空间中 CSG 碰撞体的注册。

const GHOST_NAME := "_rb_ghost"
const DRAG_PREVIEW_NAME := "_rb_drag_preview"
const RAY_EPSILON := 0.0001


## 对场景内所有非幽灵 CSG 形状做射线-AABB 求交，返回最近命中。
## 返回值：{} 表示未命中；否则 { "position": Vector3, "normal": Vector3, "shape": CSGShape3D }
static func cast_surface(origin: Vector3, direction: Vector3, scene_root: Node) -> Dictionary:
	var best_t := INF
	var best_hit := {}
	for shape in _collect_shapes(scene_root):
		var aabb := _global_aabb(shape)
		if aabb.size.x <= 0.0 or aabb.size.y <= 0.0 or aabb.size.z <= 0.0:
			continue
		var t := _ray_aabb_enter(origin, direction, aabb)
		if t < 0.0 or t >= best_t:
			continue
		best_t = t
		best_hit = {
			"position": origin + direction * t,
			"normal": _aabb_face_normal(aabb, origin + direction * t),
			"shape": shape,
		}
	return best_hit


## 递归收集场景内的 CSG 形状（跳过组合器与幽灵预览节点）。
static func _collect_shapes(root: Node) -> Array[CSGShape3D]:
	var out: Array[CSGShape3D] = []
	var stack: Array[Node] = root.get_children()
	while not stack.is_empty():
		var n := stack.pop_back()
		if n is CSGShape3D and not n is CSGCombiner3D and n.name != GHOST_NAME \
				and n.name != DRAG_PREVIEW_NAME:
			out.append(n as CSGShape3D)
		for c in n.get_children():
			stack.append(c)
	return out


static func _global_aabb(shape: CSGShape3D) -> AABB:
	return shape.global_transform * _local_aabb(shape)


## 按节点类型计算局部 AABB。不依赖 get_aabb()：CSG 形状若不是组合器的直接子节点，
## get_aabb() 会返回退化的零尺寸 AABB（几何未初始化）。
static func _local_aabb(shape: CSGShape3D) -> AABB:
	if shape is CSGBox3D:
		var box := shape as CSGBox3D
		return AABB(box.size * -0.5, box.size)
	if shape is CSGCylinder3D:
		var cylinder := shape as CSGCylinder3D
		return AABB(
			Vector3(-cylinder.radius, -cylinder.height * 0.5, -cylinder.radius),
			Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0))
	if shape is CSGSphere3D:
		var sphere := shape as CSGSphere3D
		return AABB(-Vector3.ONE * sphere.radius, Vector3.ONE * sphere.radius * 2.0)
	if shape is CSGPolygon3D:
		var polygon := shape as CSGPolygon3D
		var min_v := Vector2(INF, INF)
		var max_v := Vector2(-INF, -INF)
		for pt in polygon.polygon:
			min_v = Vector2(minf(min_v.x, pt.x), minf(min_v.y, pt.y))
			max_v = Vector2(maxf(max_v.x, pt.x), maxf(max_v.y, pt.y))
		return AABB(
			Vector3(min_v.x, min_v.y, -polygon.depth * 0.5),
			Vector3(max_v.x - min_v.x, max_v.y - min_v.y, polygon.depth))
	if shape is CSGMesh3D:
		var mesh_shape := shape as CSGMesh3D
		if mesh_shape.mesh != null:
			return mesh_shape.mesh.get_aabb()
	return AABB()


## 射线与 AABB 求交（Slab 法），返回进入距离；未命中或从内部穿过返回 -1。
static func _ray_aabb_enter(origin: Vector3, direction: Vector3, aabb: AABB) -> float:
	var tmin := -INF
	var tmax := INF
	for i in 3:
		var o := origin[i]
		var d := direction[i]
		var min_v := aabb.position[i]
		var max_v := aabb.position[i] + aabb.size[i]
		if absf(d) < RAY_EPSILON:
			if o < min_v or o > max_v:
				return -1.0
			continue
		var inv := 1.0 / d
		var t1 := (min_v - o) * inv
		var t2 := (max_v - o) * inv
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmin >= 0.0:
		return tmin
	if tmax >= 0.0:
		return tmax
	return -1.0


## 由命中点确定命中面并返回外向法线（离哪面最近取哪面）。
## 命中棱/角（两个面距离相等）时优先水平面法线（x/z），避免把墙面顶部/底部
## 的棱判成 UP/DOWN，导致门窗等贴墙操作无法生效。
static func _aabb_face_normal(aabb: AABB, hit: Vector3) -> Vector3:
	var min_v := aabb.position
	var max_v := aabb.position + aabb.size
	var nx := minf(hit.x - min_v.x, max_v.x - hit.x)
	var ny := minf(hit.y - min_v.y, max_v.y - hit.y)
	var nz := minf(hit.z - min_v.z, max_v.z - hit.z)
	if ny < nx and ny < nz:
		return Vector3.DOWN if hit.y - min_v.y < max_v.y - hit.y else Vector3.UP
	if nz <= nx:
		return Vector3.BACK if hit.z - min_v.z < max_v.z - hit.z else Vector3.FORWARD
	return Vector3.LEFT if hit.x - min_v.x < max_v.x - hit.x else Vector3.RIGHT
