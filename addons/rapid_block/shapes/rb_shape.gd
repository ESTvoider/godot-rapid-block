@tool
class_name RbShape
extends Resource
## 白盒形状数据：类型与尺寸，供放置工具与预设复用。

enum Type { BOX, CYLINDER, SPHERE, WEDGE, STAIRS, PLANE, CAPSULE }

@export var shape_type: Type = Type.BOX
@export var size: Vector3 = Vector3(2, 2, 2)
