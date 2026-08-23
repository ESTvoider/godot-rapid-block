# Rapid Block

Godot 编辑器下的**快速 3D 白盒搭建工具**：点击即可放置 CSG 形状，支持布尔挖除、网格/表面吸附、门窗生成、烘焙为 Mesh、导出 MeshLibrary 供 GridMap 使用。

![Godot](https://img.shields.io/badge/Godot-4.7-blue)

## 功能特性

- **点击放置** CSG 形状——方块、圆柱、球体、平面、斜坡、台阶、胶囊
- **布尔操作**——相加 / 挖除 / 相交，带实时颜色反馈
- **网格吸附**——吸附到任意网格大小（默认 1m）
- **表面吸附**——形状紧贴地板、墙面、斜坡、天花板放置
- **拖拽拉伸**——在视口中拖出矩形来拉伸形状
- **门窗生成**——点击墙面挖出洞口，可选带框门/窗
- **变换工具**——阵列复制、X/Z 镜像、沿路径复制
- **烘焙 CSG → Mesh**——把白盒几何转为带碰撞的静态网格
- **导出 MeshLibrary**——把组合器导出为 `.tres` 供 GridMap 使用
- **结构色**——给形状染色以标注墙体/地板/结构/可交互物

## 安装

1. 将 `addons/rapid_block/` 文件夹复制到你的项目 `addons/` 目录下。
2. 打开 **项目 → 项目设置 → 插件**，启用 **Rapid Block**。
3. 编辑器右侧 Dock 会多出 **Rapid Block** 面板。

> 需要 **Godot 4.7**。

## 快速上手

1. 打开任意 3D 场景（或本仓库内置的 `scenes/dev_test.tscn` 演示场景）。
2. 点击 Dock 面板上的 **开始放置**。
3. 在 3D 视口移动鼠标可看到半透明幽灵预览，**左键点击**放置。
4. **右键** 或按 **Esc** 退出放置模式。

## 文档

- [English readme](README.md)
- [中文文档](README.zh-CN.md)
- 插件内使用说明：`addons/rapid_block/README.md`

## 开发

这是一个**编辑器插件**项目——没有可玩的游戏、没有 CLI 构建工具链。自动化集成测试在编辑器内通过脚本执行：

```gdscript
load("res://addons/rapid_block/tests/rb_integration_test.gd").test_phase4()
```

结果打印到编辑器 Output（前缀 `RB_TEST:`）。约定详见 [AGENTS.md](AGENTS.md)。

## 许可证

[MIT](LICENSE) © ESTvoider
