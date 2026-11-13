# AI 控制的 Godot 解压视频验证工程

Godot 4.7.2 便携版，已部署在本工程 `.runtime/`。本轮跑通 AI 改场景数据 → 真实物理 → 实时预览 → PNG → MP4 的流程。引擎免费开源，使用本地运行不产生模型 API 费用。

## 使用

- 双击 `preview.cmd`：启动二维场景；按 `1` / `2` / `3` 切换二维、正交三维、透视三维。
- 空格暂停；`R` 重放；`F5` 重载。修改当前 JSON 并保存，预览每0.5秒检查一次，成功加载后重放。
- 双击 `editor.cmd`：打开原生 Godot 编辑器。
- 在工程目录运行 `render.cmd`：生成8秒、30fps、720×1280二维视频。

```powershell
# 三维样片；输出文件夹名称必须未使用，避免覆盖已有成片。
.\render.cmd -Config config/demo_3d.json -Name my_3d -Frames 180 -Fps 30
# 修改后的配置，用60fps导出3秒。
.\render.cmd -Config config/demo_custom.json -Name my_custom -Frames 180 -Fps 60
# 重复机制验收。
powershell -NoProfile -ExecutionPolicy Bypass -File tools/validate.ps1
```

成片在 `outputs/<Name>/final.mp4`，同目录保留原始帧、日志、配置副本（报告内）和碰撞事件。样片目前无声。

## AI 可以修改什么

| 配置项 | 作用 |
|---|---|
| title / subtitle | 视频内文字 |
| title_size / subtitle_size / font_family / text_color | 字号、系统字体名称、文字颜色 |
| preview_fps / physics_hz | 预览帧率上限、物理求解频率 |
| spawns[].position / velocity | 二维球初始位置、速度（720×1280逻辑坐标） |
| gravity / restitution / radius / color | 二维重力、弹性、球大小、基础色 |
| split_children / max_balls / protection | 子球总数、球数上限、新生保护秒数 |
| generation_fade / hitstop_seconds | 同色逐代变浅、分裂顿帧秒数 |
| count / palette / ramp | 三维物体数量、颜色、是否有斜坡 |
| projection / camera_size | 三维正交或透视相机、正交视野 |
| 导出 -Fps / -Frames | 成片帧率、帧数；时长=帧数÷帧率 |

例如把 `config/demo_2d.json` 的 `title` 改成“绿色小球能填满吗”，将 `title_size` 改成40，保存即可在运行预览里看到。新玩法通过独立物理脚本增加，现有入口负责加载与导出。JSON不需要直接引用渲染对象。

## 当前范围

- 二维：真实 RigidBody2D，地面/墙/球接触触发分裂，原球退役，子球接替；0.08秒默认新生保护，48球默认上限。分裂是人为定义的玩法，不声称质量或能量守恒。
- 三维：真实 RigidBody3D 的球、长方体、斜坡、容器；正交相机提供2.5D观感，透视相机提供3D画面。当前三维场景没有分裂规则。
- 文字直接进入 Godot 画面及成片；字体使用系统字体，不复制或分发 Windows 字体文件。
- 当前由对话中的AI编辑JSON/GDScript和执行运行命令，没有另做聊天界面。动态生成的物体在运行场景树中可查看；场景暂未制作成完整的手工布置编辑器。
- 还未实现运动烘焙回放、跨机器严格确定性、声音设计、时间线、撤销重做和独立成品编辑器。相同种子不等于不同平台逐帧完全一致。

## 本地存储与恢复

必须通过这三个启动入口运行。启动器把 `APPDATA`、`LOCALAPPDATA`、`TEMP`、`TMP` 指向工程 `.runtime/`，Godot编辑器也启用 `_sc_` 便携模式。直接双击引擎EXE或直接在资源管理器中打开项目可能绕过这些环境设置。

工程可以整体移动到其他非系统盘。源码使用相对路径；旧报告记录运行当时的绝对路径。如果缺失 `.runtime/`，运行 `tools/setup.ps1` 下载相同Godot并导入工程；FFmpeg可用 `-FFmpegSource` 提供本地路径。媒体检查另需Python和Pillow，本机已复用同级旧工程的环境。所有结果与实际限制见 `docs/验证报告.md`。
