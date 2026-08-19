@tool
class_name RbBake
extends RefCounted
## CSG 烘焙工具：将组合器/形状转换为带碰撞的 Mesh 节点，用于白盒转正式。

## 将 CSG 节点烘焙为 Node3D（含 MeshInstance3D 列表与 StaticBody3D + 碰撞）。
## 生成的节点全局变换与源 CSG 一致，不包含撤销逻辑（由调用方封装）。
static func bake(csg: CSGShape3D) -> Node3D:
	var baked := Node3D.new()
	baked.name = "%s_Baked" % csg.name
	baked.global_transform = csg.global_transform
	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	baked.add_child(static_body)
	var meshes := csg.get_meshes()
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
