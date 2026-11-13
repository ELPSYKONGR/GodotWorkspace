# 原生引擎路线核查：Godot、Blender 与备选

调研日期：2026-11-13。只读在线调研，未安装、部署或替换当前工程。GitHub API 与官方文档源码已读取；官网文档网页及 raw 域名部分请求超时，因此使用官方 GitHub 仓库中的同源文档。下文分别标明已核实事实、工程判断和工期估算。

## 1. 核查范围与结论

用户需要的是制作解压短视频的编辑与运行工程：可视摆物、文字编辑、物理碰撞、事件机制、实时调试、2D/2.5D/3D、逐帧导出与可拓展机制。

**工程判断：Godot 项目加编辑器插件，是两条原生路线中最适合同时覆盖这些目标的底座。** 优先使用现成 Godot 编辑器、场景树、检查器、2D/3D 视口，专门开发“解压视频工具面板”和机制组件；不应先 fork Godot 引擎源码。

**Blender 更适合高质感 2.5D/3D 镜头与最终渲染。** 它自带强大的摆物、材质、相机、文字、动画和离线渲染，但不能把它等同于已经提供“碰撞就替换原球、动态增删、事件调试”的现成短视频机制引擎。若优先做此类机制，Godot 先产生位姿与事件缓存，Blender 读取缓存升级材质，更容易控制一致性。

## 2. GitHub 仓库与维护证据

以下状态来自 2026-11-13 的 GitHub API 实际读取。星数未用于决策，因为不能代表功能是否匹配。

| 项目 | 已核实授权 | 维护状态事实 | 适用性判断 |
|---|---|---|---|
| [godotengine/godot](https://github.com/godotengine/godot) | MIT | 未归档；最近推送 2026-11-12；latest release 为 [4.7.2-stable](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)，API 发布日 2026-08-18 | 统一 2D/3D 编辑、物理、脚本和运行时的主候选 |
| [godotengine/godot-demo-projects](https://github.com/godotengine/godot-demo-projects) | MIT | 未归档；最近推送 2026-10-08 | 可从 2D/3D 物理、GUI、相机示例学习，不等于现成视频工作台 |
| [godot-jolt/godot-jolt](https://github.com/godot-jolt/godot-jolt) | MIT | 未归档；最近推送 2026-03-16；README 明示维护模式 | Godot 4.4 起已有内置 Jolt，不应默认再装独立扩展 |
| [blender/blender](https://github.com/blender/blender) | GPL；COPYING 指向 GPL v2 文本及“v2 或更晚”条款 | 官方镜像，未归档；最近推送 2026-11-12 | DCC、材质、灯光与离线渲染主候选 |
| [UPBGE/upbge](https://github.com/UPBGE/upbge) | Blender 衍生；此轮未完成全部衍生授权文件核查，不能仅凭 GitHub license API 定论 | 未归档；最近推送 2026-11-12 | 整合 Blender 与游戏运行的备选，导出管线仍需先验证 |
| [bevyengine/bevy](https://github.com/bevyengine/bevy) | README 核实 MIT / Apache-2.0 双授权，任选其一 | 未归档；最近推送 2026-11-13 | 更适合愿意自己构建 Rust 工具链与编辑器的团队 |
| [o3de/o3de](https://github.com/o3de/o3de) | 仓库描述为 Apache 2.0；此轮未核对其完整多组件授权 | 未归档；最近推送 2026-11-12 | 3D 引擎备选，短视频专用工具的工程负担偏大 |

说明：Blender、UPBGE、O3DE 的 GitHub API `license.spdx_id` 返回 `NOASSERTION`。这不等于无授权；Blender 已进一步读取 COPYING/GPL 文件，另两项没有把 API 值当成最终授权结论。

## 3. Godot：已经有的与必须开发的

### 已核实事实

1. 2D 和 3D 原生刚体均提供碰撞事件及 CCD。
   - [RigidBody2D 官方类文档源码](https://github.com/godotengine/godot/blob/master/doc/classes/RigidBody2D.xml)：`body_entered`、`body_shape_entered`；事件要求开启 `contact_monitor` 且 `max_contacts_reported` 足够大；`continuous_cd` 支持连续碰撞检测模式。
   - [RigidBody3D 官方类文档源码](https://github.com/godotengine/godot/blob/master/doc/classes/RigidBody3D.xml)：同样有接触监控、接触数量上限和 `continuous_cd`；`_integrate_forces` 提供物理处理期间安全读写状态的入口。
   - 因而“换引擎就绝对不漏碰”不能成立。接触报告、CCD、物理频率、对象尺寸、容差和用户自己的去重逻辑仍需设置、测试。
2. 可开发编辑器插件与自定义 Dock。
   - [官方插件文档](https://github.com/godotengine/godot-docs/blob/master/tutorials/plugins/editor/making_plugins.rst) 明示 `@tool extends EditorPlugin`、自定义节点、面板、自动加载及 Dock。
   - 这是“在 Godot 编辑器里提供解压视频工作流”的原生扩展点，不代表导出的普通应用会自动包含 Godot 整套场景编辑器。
3. 内置逐帧录制，适合自动化成片。
   - [4.7 录制文档](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/animation/creating_movies.rst) 提供 `--write-movie`、`--fixed-fps`；参数也可用于导出的项目。
   - [4.7.2 MovieWriter 源码文档](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/MovieWriter.xml) 列出 OGV、AVI、PNG 序列加 WAV；PNG/WAV 设计用途就是再交给 FFmpeg 等工具编码。
   - 4.7 文档说明 OGV 录制只在 editor builds 可用。AVI 有 4 GB 限制。优先选择 PNG 序列 + WAV → MP4，或按性能验证自定义 MovieWriter；不要把“运行时屏幕录制”当作逐帧导出的等价替代。
   - Movie Maker 不能在正在运行的实例里随时切换；可由工作台启动第二个导出实例，主实例继续保留编辑状态。
   - `MovieWriter` 保证导出固定帧节奏与 `_process` 的固定 delta，不保证物理仿真严格确定性。
4. 3D 物理可用内置 Jolt。
   - [Godot 4.7 Jolt 文档](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/physics/using_jolt_physics.rst)：4.4 起内置；4.7 文档称新项目默认使用 Jolt。部分关节属性等仍存在差异。
   - [独立 Jolt 扩展 README](https://github.com/godot-jolt/godot-jolt/blob/master/README.md)：自 Godot 4.4 起该集成已有内置模块，因此扩展进入仅接收 bugfix 的维护模式，且仍说明关节接口功能差异。
5. 官方明确不保证物理确定性。
   - [Godot 4.7 物理入门](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/physics/physics_introduction.rst) 原文：**“Physics in Godot, regardless of physics engine, is not deterministic”**，即使看似相同的情况也不保证完全相同结果。
   - 固定 seed 与固定步长可以降低差异，但不能据此承诺跨机器、版本或物理后端逐位一致。
6. 延后处理世界修改有正式入口。
   - [4.7.2 Object.call_deferred](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Object.xml) 说明 idle time 一般发生在 process/physics frame 末尾，延后调用会在那里执行。
   - 工程上应把碰撞记录为待处理动作，再进行原球替换、子球增删与场景更新，避免在碰撞回调中随意修改整个物理世界。

### 需要专门开发

- 解压视频对象库：球、矩形、墙、圆环、缺口、闸门、收集器、传感器、文字、相机、音源。
- 机制组件：碰撞分裂、倍率、变色、销毁、触发开闸、统计胜负、顿帧、碰撞音效。
- 机制语义：Enter/Stay/Exit 区分、是否对球球双方分别触发、每球/每对接触去重、出生保护、容量、父子 ID 与代数。
- 视频工作流：9:16 安全框、文字属性、分辨率/FPS/时长、批量种子、任务状态、文件整理。
- 可复现交付：一次仿真烘焙位姿与事件，导出读取烘焙结果；改文字/配色不重跑物理；必要时可指定重算。
- 交互调试：播放、暂停、单步、慢速、碰撞体显示、轨迹、接触点、事件日志和对象检查器。运行中改变布局或物理参数时明确“重置重算”，避免把任意时刻改初始条件混成同一条轨迹。

### 2.5D 的推荐定义（工程判断）

先明确两种不同模式，不能混称一个后端：

- **2D 物理 + 3D 外观**：Pymunk/Godot 2D 的 x/y 轨迹映射为球体/挤出图形的 3D 表现，固定相机，增加灯光、阴影和材质。机制保持平面规则。
- **真 3D 物理 + 正交相机**：3D 刚体、深度、真实遮挡、空间碰撞，画面采用正交/斜视角。看起来简洁，但结果与二维模型不能默认相同。

建议默认先支持第一种用于既有作品复用，再提供真正的 3D 项目类型。两个类型共享“编辑和机制描述”，不强求二维、三维仿真数值相同。

### 改造边界（工程判断）

最小风险是“Godot 工程 + addons 视频工具插件 + 机制脚本库”，不 fork Godot 本体。使用官方场景文件/Resource 保存引擎实例；另保留版本化的工程数据与事件缓存作为 AI、批处理和旧项目迁移入口。

若需要完全独立的中文专用软件，使用 Godot 导出一个含自制 Control 界面的工作台，但选择、拖动、吸附、撤销、资源浏览、3D Gizmo 等编辑行为仍要开发。**这条路线不能把原生 Godot 编辑器能力算成已经免费带进产品。**

## 4. Blender 插件：已经有的与缺口

### 已核实事实

- [官方 README](https://github.com/blender/blender/blob/main/README.md)：包含建模、绑定、动画、simulation、rendering、compositing、motion tracking、视频编辑等完整 3D 内容生产流程。
- [COPYING](https://github.com/blender/blender/blob/main/COPYING) 指定 GNU GPL，进一步指向 [GPL 文本](https://github.com/blender/blender/blob/main/doc/license/GPL-license.txt)。引擎不是 MIT 授权；商业制作视频不等于必须把成片开源，资产授权另计。
- [命令行参数实现](https://github.com/blender/blender/blob/main/source/creator/creator_args.cc) 注册 `--background`、`--python` / `-P`、`--render-anim` / `-a`，因此 Python 批处理、后台运行和离线动画渲染具有现成入口。
- [Rigid Body RNA 实现](https://github.com/blender/blender/blob/main/source/blender/makesrna/intern/rna_rigidbody.cc) 提供 `collision_shape`、`collision_collections`、`substeps_per_frame` 和 `solver_iterations`。对子步的官方属性说明明确“更多子步更准确但更慢”。

### 工程判断与待验证边界

- Blender 是强大的三维内容编辑器，可用正交相机制作平面风格，不应把这种呈现说成它已有独立成熟的 2D 刚体后端。
- Blender 标准刚体工作流更偏场景仿真与缓存。此次没有核实到与 Godot `body_entered` 等价、足以直接搭建用户所需所有“碰撞替换原球”机制的标准 Python 原生事件 API。不能把“Python 可控制 Blender”直接推导为“每种实时碰撞机制只加几行脚本”。
- 把当前 Pymunk/Godot 生成的二维/三维位姿与事件烘焙导入 Blender，避免在渲染阶段再次模拟，最适合保持赛果与动作一致。
- 物体几何真正改变时（分裂、挤压、破碎），需要预制体替换、可见性/实例调度或 Geometry Nodes 等方案；不是材质升级自动完成。
- EEVEE 与离线渲染器的画质/速度、复杂玻璃透明、多物体遮挡及具体镜头耗时需样片 benchmark，不能未经部署就给出每条几秒钟的承诺。
- 整个工作流强制以 Blender 为主也可行，但应将“实时碰撞机制编辑”列为二开重点，而非认为已有完整功能。

## 5. 工程成本估算（不是报价或实测）

单位为熟悉对应框架的单人有效工程日，按每日约 6 小时有效工作；包括必要测试与文档，不含复杂流体、软体、布料、任意网格破碎、账户协作或商用资产制作。AI 可以生成组件、脚本、测试与批处理，但不据此保证固定倍数提速。

| 路线与口径 | 首个可用版本估算 | 稳定工具估算 | 主要成本来源 |
|---|---:|---:|---|
| Godot 官方编辑器内的专用插件/工程；2D、基础3D、基础事件机制、视频导出 | 20–35 人日 | 40–70 人日 | 机制组件、烘焙重放、视频任务面板、现有模板迁移及物理测试 |
| Godot 导出独立中文编辑软件；与上行相同机制 | 35–55 人日 | 70–110 人日 | 另建运行时对象编辑、撤销、Gizmo、资源管理和交互细节 |
| Blender 插件；偏2.5D/3D画面、模板与烘焙导入导出 | 15–25 人日 | 30–50 人日 | Python工具面板、材质/相机模板、缓存导入、渲染任务与示例 |
| Blender 插件；要求对齐统一2D/3D机制编辑、碰撞分裂与实时调试 | 35–60 人日 | 60–100 人日 | 在DCC中额外构建事件机制运行与调试，并解决缓存/动态增删 |

纯许可证成本：Godot 和 Blender 都无需按视频条数向引擎支付费用。实现人力和导出机器时间仍有成本，不能称“整个生产免费”。

从当前项目迁移：可以复用规则设计、验收夹具、字段含义、模板参数、音效方法、FFmpeg编排和已有样片。Python 的 Pymunk 刚体、Pillow 绘制器不能原样变成 Godot 3D 场景运行代码；现有轨迹可作为二维烘焙输入与迁移对照。

## 6. 其他原生候选为何不排首选

- **UPBGE**：README 明确是 Blender 分支，并提供游戏运行方向。适合已经熟悉 Blender/BGE 的团队；本轮未验证稳定版本视频逐帧导出链、动态场景缓存和机制编辑体验。不能仅凭“Blender+Game Engine”标签就视为零改造满足全部需求。
- **Bevy**：仓库及 examples 显示 2D/3D 场景、UI、工具、远程检查等能力；双授权友好。但对这位用户的目标，仍需选物理插件、设计编辑器、场景存储、机制组件与视频输出。此轮没有核实其已有与 Godot 完整编辑器同等可直接使用的产品，所以不把它当作最快方案。
- **O3DE**：仓库 README 的工程配置涉及 CMake、Editor、Asset Processor、启动程序等多环节。即使不考虑机器配置，构建、资产处理和引擎专用开发仍是维护成本。以当前短视频与二维玩法目标，暂不值得承担这种复杂度。

以上“暂不首选”是需求适配判断，不是说项目不能实现；三者也都不应因星数更少或语言不同被简单判为不成熟。

## 7. 选择前最有价值的验证（建议，尚未实施）

用同一基准短片验收候选，不先建庞大编辑器：

1. 拖入球、墙、圆环、矩形、文字；改字/字号/颜色；保存再打开。
2. 搭建分裂、开闸、变色三种机制，检查双方碰撞、原球移除、出生保护、角落去重与数量账目。
3. 高速小球、擦碰、密集堆叠分别测试；显示碰撞体与事件，不能只看最终视频。
4. 同一场景切换平面显示与3D表现；真3D另设场景，区分物理空间。
5. 暂停、逐步、慢放、重置；修改物理参数后明确重算；改文字后只重渲染。
6. 烘焙位姿和事件后，以30/60fps导出；确认结果、音画同步、帧数及尾帧，不承诺仅靠随机种子重放相同物理结果。
7. 以100/500/1000物体测编辑、模拟、渲染三种耗时。GPU实例化能降低画面提交成本，不代表一千个独立物理刚体也自动零成本。

同一基准如果 Godot 插件路线在上述项目达标，才值得继续扩成独立工作台；如果只追求玻璃、金属、灯光成片，优先选择 Blender 模板路线会更直接。
