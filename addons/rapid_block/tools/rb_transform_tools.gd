@tool
class_name RbTransformTools
extends RefCounted
## 复制工具：阵列复制与镜像复制，返回已设置相对父位置的新节点。
## 不包含撤销逻辑（由调用方封装）。

## 沿 X（列）与 Z（行）阵列复制源节点，跳过源本身。
static func array_duplicate(source: Node3D, rows: int, cols: int, spacing: float) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for r in rows:
		for c in cols:
			if r == 0 and c == 0:
				continue
			var dup := source.duplicate(true) as Node3D
			dup.name = "%s_%d_%d" % [source.name, r, c]
			dup.position = source.position + Vector3(c * spacing, 0, r * spacing)
			out.append(dup)
	return out


## 沿 X 或 Z 轴镜像复制源节点（位置与缩放取反）。
static func mirror_duplicate(source: Node3D, flip_x: bool) -> Node3D:
	var dup := source.duplicate(true) as Node3D
	dup.name = "%s_Mirror" % source.name
	var mirror := Vector3(-1.0, 1.0, 1.0) if flip_x else Vector3(1.0, 1.0, -1.0)
	dup.position = source.position * mirror
	dup.scale = source.scale * mirror
	return dup


## 沿直线路径复制：从源位置到 源+end_offset 均匀等分 count 个副本（不含源）。
static func path_duplicate(source: Node3D, end_offset: Vector3, count: int) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if count <= 1:
		return out
	for i in range(1, count):
		var dup := source.duplicate(true) as Node3D
		dup.name = "%s_%d" % [source.name, i]
		var f := float(i) / float(count - 1)
		dup.position = source.position + end_offset * f
		out.append(dup)
	return out
