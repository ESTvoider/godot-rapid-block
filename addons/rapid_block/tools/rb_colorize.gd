@tool
class_name RbColorize
extends RefCounted
## 结构类型着色：为选中节点及其后代 CSG 设置独立材质（不受 Dock 共享颜色影响）。

enum STRUCTURE { WALL, FLOOR, STRUCTURE, INTERACTABLE }

const STRUCTURE_NAMES: Dictionary = {
	STRUCTURE.WALL: "墙体",
	STRUCTURE.FLOOR: "地板",
	STRUCTURE.STRUCTURE: "结构",
	STRUCTURE.INTERACTABLE: "可交互",
}

const STRUCTURE_COLORS: Dictionary = {
	STRUCTURE.WALL: Color(0.75, 0.75, 0.75),
	STRUCTURE.FLOOR: Color(0.55, 0.55, 0.55),
	STRUCTURE.STRUCTURE: Color(0.85, 0.65, 0.3),
	STRUCTURE.INTERACTABLE: Color(0.3, 0.7, 0.7),
}


static func structure_name(kind: int) -> String:
	return STRUCTURE_NAMES.get(kind, "未知")


static func structure_color(kind: int) -> Color:
	return STRUCTURE_COLORS.get(kind, Color(0.75, 0.75, 0.75))


## 递归为节点与后代 CSG 设置独立材质颜色。
static func colorize(node: Node, kind: int) -> void:
	var color := structure_color(kind)
	_apply(node, color)


static func _apply(node: Node, color: Color) -> void:
	if node is CSGShape3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.9
		(node as CSGShape3D).material = material
	for child in node.get_children():
		_apply(child, color)
