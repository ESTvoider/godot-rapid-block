@tool
class_name RbExport
extends RefCounted
## 导出工具：将已渲染的 CSG 导出为 MeshLibrary 资源（供 GridMap 等复用）。

## 将 CSG 节点的每个子网格导出为 MeshLibrary 的一个 item。
## 返回 { "ok": bool, "error"?: String, "items"?: int, "path"?: String }
static func export_mesh_library(csg: CSGShape3D, save_path: String) -> Dictionary:
	_ensure_dir(save_path)
	var library := MeshLibrary.new()
	var meshes := csg.get_meshes()
	if meshes.is_empty():
		return {"ok": false, "error": "CSG 几何为空，请确认该节点已渲染至少一帧"}
	var index := 0
	for i in range(0, meshes.size(), 2):
		var mesh: Mesh = meshes[i + 1]
		if mesh == null:
			continue
		library.create_item(index)
		library.set_item_mesh(index, mesh)
		library.set_item_name(index, "%s_%d" % [csg.name, index])
		index += 1
	var err := ResourceSaver.save(library, save_path)
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	EditorInterface.get_resource_filesystem().scan()
	return {"ok": true, "items": index, "path": save_path}


static func _ensure_dir(save_path: String) -> void:
	var dir := save_path.get_base_dir()
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
