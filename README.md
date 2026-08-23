# Rapid Block

A fast **3D whitebox / blockout tool** for the Godot editor. Place CSG shapes with a single click, carve holes with boolean subtraction, snap to grids and surfaces, generate doors & windows, bake CSG into meshes, and export a MeshLibrary for GridMap.

![Godot](https://img.shields.io/badge/Godot-4.7-blue)

## Features

- **Click to place** CSG shapes — box, cylinder, sphere, plane, ramp, stairs, capsule
- **Boolean operations** — Union / Subtract / Intersect with live color feedback
- **Grid snapping** — snap to any grid size (default 1 m)
- **Surface snapping** — place shapes flush against floors, walls, slopes, ceilings
- **Drag-to-scale** — drag a rectangle in the viewport to stretch a shape
- **Doors & windows** — click a wall to carve an opening, optionally add framed door/window
- **Transform tools** — array duplication, X/Z mirror, along-path duplication
- **Bake CSG → Mesh** — convert whitebox geometry into static MeshInstance3D + StaticBody3D with collision
- **Export MeshLibrary** — turn a combiner into a `.tres` for use with GridMap
- **Structure colors** — tint shapes to annotate walls / floors / structures / interactables

## Installation

1. Copy the `addons/rapid_block/` folder into your project's `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable **Rapid Block**.
3. A **Rapid Block** panel appears in the right-side dock.

> Requires **Godot 4.7**.

## Quick Start

1. Open any 3D scene (or the bundled demo at `scenes/dev_test.tscn`).
2. Click **开始放置** (Start Placing) in the dock panel.
3. Move the mouse over the 3D viewport to see a ghost preview, **left-click** to place.
4. **Right-click** or press **Esc** to exit placement mode.

## Documentation

- [English readme](README.md)
- [中文文档](README.zh-CN.md)
- In-plugin user guide: `addons/rapid_block/README.md`

## Development

This is an **editor plugin** project — there is no playable game or CLI build toolchain. Automated integration tests run inside the editor via scripts:

```gdscript
load("res://addons/rapid_block/tests/rb_integration_test.gd").test_phase4()
```

Results print to the editor Output with the `RB_TEST:` prefix. See [AGENTS.md](AGENTS.md) for conventions.

## License

[MIT](LICENSE) © ESTvoider
