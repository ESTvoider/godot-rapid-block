@tool
class_name RbBake
extends RefCounted
## CSG 烘焙工具：将组合器/形状转换为带碰撞的 Mesh 节点，用于白盒转正式。

## 将 CSG 节点烘焙为 Node3D（含 MeshInstance3D 列表与 StaticBody3D + 碰撞）。
## 生成的节点全局变换与源 CSG 一致，不包含撤销逻辑（由调用方封装）。
## 若 csg 是组合器的子形状（非根形状），会自动向上取根 CSG 生成网格；
## 无可用几何时返回 null。
static func bake(csg: CSGShape3D) -> Node3D:
	var root_csg := resolve_root_csg(csg)
	var meshes := root_csg.get_meshes()
	if meshes.is_empty():
		return null
	var baked := Node3D.new()
	baked.name = "%s_Baked" % root_csg.name
	baked.global_transform = root_csg.global_transform
	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	baked.add_child(static_body)
	for i in range(0, meshes.size(), 2):
		var t: Transform3D = meshes[i]
		var mesh: Mesh = meshes[i + 1]
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = "Mesh_%d" % (i / 2)
		instance.transform = t
		instance.mesh = mesh
		baked.add_child(instance)
		var shape := mesh.create_trimesh_shape()
		if shape != null:
			var collider := CollisionShape3D.new()
			collider.name = "Collision_%d" % (i / 2)
			collider.transform = t
			collider.shape = shape
			static_body.add_child(collider)
	return baked


## 沿父链向上找到最近的根 CSG（父节点不是 CSGShape3D）。
## Godot 中只有根形状的 get_meshes() 才有网格，子形状会返回空数组。
static func resolve_root_csg(csg: CSGShape3D) -> CSGShape3D:
	var cur: CSGShape3D = csg
	while cur.get_parent() is CSGShape3D:
		cur = cur.get_parent() as CSGShape3D
	return cur
