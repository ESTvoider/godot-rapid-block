# AGENTS.md

Godot 4.7（`config/features="4.7"`）编辑器插件项目——Rapid Block，3D 白盒搭建工具。核心开发发生在**编辑器内**：没有可玩的游戏、没有 CLI 构建/测试工具链。

## 结构

- `addons/rapid_block/` — 项目自身代码（EditorPlugin）。`addons/godot_mcp/` 是 MCP 桥接基础设施，**不要**在其中改业务逻辑。
- `plugin.gd` — `RapidBlockPlugin`，持有全部状态、注册右侧 Dock、通过 `_forward_3d_gui_input` 转发 3D 视口输入。
- `tools/`（`rb_` 前缀文件 / `Rb*` 类）：
  - `rb_scene_builder.gd` — **面向脚本/AI 的静态构建 API**（看文件头注释），AI 驱动建场景的标准入口。
  - `rb_place_tool.gd` 视口放置 / `rb_bake.gd` CSG→Mesh / `rb_transform_tools.gd` 阵列·镜像·路径复制 / `rb_export.gd` MeshLibrary 导出 / `rb_colorize.gd` 结构色 / `rb_surface_snap.gd` 表面吸附。
- `shapes/` — `RbShape`（数据）+ `RbShapeLibrary`（生成 CSG 节点、门窗尺寸常量）。
- `tests/rb_integration_test.gd` — 集成测试（编辑器脚本，**非测试框架**）。
- `scenes/test_whitebox.tscn` — 主场景，仅作自动化测试画布（空 Node3D；`test_phase2/3/4` 运行时会清空场景，勿预置内容）。
- `scenes/dev_test.tscn` — **手工开发测试场景**：预置地板/双墙/圆柱/斜坡/台阶 + 环境光与相机，用于开发时直接验证放置、表面吸附、门窗、复制、烘焙、导出。
- `whitebox_meshes/` — MeshLibrary 导出输出目录。

## 验证与测试

无 GUT/gdUnit、无 CLI 运行器。唯一验证方式：**Godot 编辑器必须开着**（已启用 godot_mcp + rapid_block 插件），通过 MCP 执行编辑器脚本，例如：

```
load("res://addons/rapid_block/tests/rb_integration_test.gd").test_phase4()
```

结果打印到编辑器 Output（前缀 `RB_TEST:`）。可用：`run` / `test_phase2` / `test_phase3` / `test_phase3_bake` / `test_phase4` / `test_phase4_export` / `test_phase4_path` / `check_dock` / `inspect`。

MCP 桥接由 `opencode.json` 配置的 `npx @keeveeg/godot-mcp` 提供；运行时工具（`godot_play_scene` 等）需先启动游戏，但插件测试基本只用编辑器上下文。

## 关键约定

- **语言**：代码注释、print 消息、git 提交信息一律简体中文；提交用 Conventional Commits（如 `feat(rb): ...`），当前分支 `develop`。
- **Godot 4.7 API 注意**：`EditorPlugin._forward_3d_gui_input` 返回 `int`（1=消费输入，0=放行），这是 4.7 相对旧版的改动，勿写成 `bool`。
- **撤销模式**：一切场景修改走 `EditorUndoRedoManager`：`create_action()` + `add_do/add_undo`，新节点 `owner` 设为场景根。样板见 `plugin.gd` 的 `bake_selected()`。
- 形状统一挂在名为 `Whitebox` 的 `CSGCombiner3D` 下，用 `RbSceneBuilder.find_or_create_combiner()` 获取。
- 材质：union 用共享 `addons/rapid_block/materials/whitebox_gray.tres`；subtract/intersect/ghost 是 `_init_materials()` 运行时生成——**不要**改共享 tres 当减法色。
- `@tool` + `class_name Rb*` 是标准写法，保证脚本在编辑器内可直接运行。
