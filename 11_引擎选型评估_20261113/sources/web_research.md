# Web 引擎与编辑器调研证据

核查日期：2026-11-13。本文是主评估的来源记录，区分已核实事实、工程判断和估算；未部署或实测候选编辑器，不把 README 宣传当成性能验收。

## 结论

最适合进入主比较的 Web 路线是 **扩展 Babylon.js Editor 5，复用 Babylon.js 渲染与官方 Havok 3D 物理集成**。它已有真正的桌面场景编辑器，可少造物体选择、位移旋转缩放、材质检查器等基础设施。它仍不是解压视频生产软件：碰撞规则编辑、可靠重放、竖屏文字版式、声音事件与逐帧视频导出需要专门开发。

若坚持浏览器里完全定制自己的工作台，**Three.js / React Three Fiber + Rapier + 自制场景编辑界面** 是可行替代，但工作量更大。Three.js 不是完整游戏引擎，Rapier 也不是可视化编辑器，二者安装完成不等于获得所需软件。

重要的现状纠正：

- `dimforge/rapier.js` 已归档，应该用仍活跃的 `dimforge/rapier` 主仓及其当前 `bindings/typescript/`；旧仓描述还写着迁移到 `/typescript`，主仓 README 的新目录优先。
- PlayCanvas Editor 前端当前是 **MIT 开源**，不能照旧说它闭源。但 README 的本地开发流程仍访问 playcanvas.com 场景并加载 localhost 前端，不能把这说成完整离线后端已开源、克隆即全自托管。
- `@babylonjs/havok` 分发包的 `packages/havok/LICENSE` 已读实文，为 **MIT**；可以免费商用并保留许可。它分发 WASM / JS 运行时，不代表底层 Havok C++ 引擎完整源码公开。也不能把 Babylon.js 的 Apache-2.0 许可证直接套给 Havok 包。

## GitHub 实时仓库状态

以下 pushed_at 为 GitHub API 返回 UTC，不等同于最近正式发布，也不保证稳定；星数仅辅助衡量生态规模。

| 仓库 | 定位与核实内容 | 许可 | pushed_at / 星数 |
|---|---|---|---|
| [BabylonJS/Babylon.js](https://github.com/BabylonJS/Babylon.js) | 3D 渲染/游戏引擎；官方 Playground、Sandbox、GUI 和 Inspector 等生态，不是单独完整视频工作台 | Apache-2.0 | 2026-11-13T03:27:01Z / 26,335 |
| [BabylonJS/Editor](https://github.com/BabylonJS/Editor) | 社区维护的 Editor 5；README 明确 Windows / macOS / Linux 桌面 3D 场景编辑器，提供 5.5.3 下载 | Apache-2.0 | 2026-11-13T00:47:45Z / 1,124 |
| [BabylonJS/havok](https://github.com/BabylonJS/havok) | 官方 Havok for the Web 运行时；README 展示 HavokPlugin 初始化 | 包内 MIT，GitHub 根级识别为 null | 2026-07-27T10:10:31Z / 38 |
| [dimforge/rapier](https://github.com/dimforge/rapier) | 真正的 2D / 3D 物理引擎，Rust 核心；主仓现有 JS/TS、Python、Bevy 等 bindings | Apache-2.0 | 2026-11-01T21:48:29Z / 6,063 |
| [mrdoob/three.js](https://github.com/mrdoob/three.js) | 3D 渲染库；仓库提供 editor 示例，物理和内容规则需另接 | MIT | 2026-11-12T16:14:29Z / 118,265 |
| [pmndrs/react-three-rapier](https://github.com/pmndrs/react-three-rapier) | Three / R3F 与 Rapier 的物理封装；有碰撞、传感器、分组、手动步进、快照、调试显示 | MIT | 2026-10-12T05:06:24Z / 1,611 |
| [playcanvas/engine](https://github.com/playcanvas/engine) | WebGL2/WebGPU 引擎；README 核实内置 3D ammo.js 集成，并列 2D+3D 图形能力 | MIT | 2026-11-13T02:13:06Z / 17,281 |
| [playcanvas/editor](https://github.com/playcanvas/editor) | 真正的浏览器可视编辑器前端；本地开发流程依赖线上场景服务 | MIT | 2026-11-12T12:05:28Z / 1,373 |
| [liabru/matter-js](https://github.com/liabru/matter-js) | 明确为 2D 刚体物理；适合平面小球、约束、墙与传感器，不提供通用 3D 编辑能力 | MIT | 2026-09-30T17:14:46Z / 18,621 |
| [phaserjs/phaser](https://github.com/phaserjs/phaser) | 2D 框架；当前 README 已介绍 Phaser 4.2.1、新渲染器、Arcade/Matter 物理 | MIT | 2026-08-21T06:56:13Z / 40,706 |

另核实 [playcanvas/editor-mcp-server](https://github.com/playcanvas/editor-mcp-server)，MIT，pushed_at=2026-11-11T21:29:50Z，151 星；Editor README 直接链接它用于 AI 检查与修改开放的编辑会话。

## Babylon.js Editor 改造的具体边界

### 已有能力与依据

README 原文："The Babylon.js Editor is a desktop application used to create and edit 3D scenes using the Babylon.js 3D engine."；"The Editor is available on Windows, macOS and Linux."。主仓实际完整文件树 `truncated=false` 中进一步查到：

- [变换操作器](https://github.com/BabylonJS/Editor/blob/master/editor/src/editor/layout/preview/gizmo/gizmo.ts)、[吸附](https://github.com/BabylonJS/Editor/blob/master/editor/src/editor/layout/preview/gizmo/magnetism.ts)。
- [撤销重做](https://github.com/BabylonJS/Editor/blob/master/editor/src/tools/undoredo.ts) 及 `editor/test/tools/undoredo.test.mts`。
- [网格物理属性检查器](https://github.com/BabylonJS/Editor/blob/master/editor/src/editor/layout/inspector/mesh/physics.tsx)、[物理初始化](https://github.com/BabylonJS/Editor/blob/master/editor/src/tools/physics/init.ts)、物理形状和聚合序列化模块。
- [PBR 材质检查器](https://github.com/BabylonJS/Editor/blob/master/editor/src/editor/layout/inspector/material/pbr.tsx)、标准材质、节点材质、粒子和动画等目录。
- [GUI 导入](https://github.com/BabylonJS/Editor/blob/master/editor/src/editor/layout/preview/import/gui.ts) 与 [GUI 检查器](https://github.com/BabylonJS/Editor/blob/master/editor/src/editor/layout/inspector/gui/gui.tsx)；本次仅核实这些入口存在，未验收它们是否提供用户所需的完整中文标题/字幕字体编辑流程。
- [工程导出](https://github.com/BabylonJS/Editor/blob/master/editor/src/project/export/export.tsx) 和动画导出目录。**工程导出不等于 MP4 视频导出**；本次未核实 Editor 已自带满足需求的固定时间逐帧带音频视频导出功能。
- `editor/src/mcp/` 与 `mcp/src/tools/` 已存在；本次未读取接口契约，不把它等同于已验证的完整 AI 自动化工作流。

文件路径可追溯到真实源码树；除 README 外，上述多数文件本轮只核实路径与模块，不声称逐个阅读实现或完成运行测试。

### 2D / 2.5D / 3D 的区别

Babylon + Havok 主要满足真正 3D。正交镜头、限制深度位移可以做 2.5D，但这是 3D 物理世界的平面约束，不等于真正的 2D 求解器。

如果用户要求严格的 2D 碰撞，与 2.5D/3D 同时存在，需要增加 Rapier 2D、现有 Pymunk，或另一套 2D 物理后端，并在场景数据中明确每个场景选择哪个求解器。不建议同一物体既用 Pymunk 又用 Havok 同时决定位置。

官方 Babylon 物理文档目前列出的内置插件是 Havok：[Using A Physics Engine](https://doc.babylonjs.com/features/featuresDeepDive/physics/usingPhysicsEngine/)。文档原文："There is a plugin for the Havok Physics engine."。**Rapier + Babylon 不是本轮核实到的官方开箱组合**；如果选择此组合，需要自写适配层或额外审核第三方插件。

### 专用新增模块

1. 解压短视频的球、线、长方体、容器、缺口、闸门等预制物体库。
2. 事件规则：接触开始/持续/结束、速度或冲量阈值、出生保护、分裂、变色、计分、音效、顿帧；规则模块写操作进入求解结束后的队列，按稳定 ID 去重。
3. 固定物理步长、种子、规则版本、烘焙轨迹/事件和可重放快照；拖到历史时刻不是倒着积分。
4. 面向竖屏内容的文字层、字幕层、字体资源、位置对齐和画面安全区。
5. 逐帧导出：固定时间驱动场景，生成帧或视频编码输入，音效按记录事件离线合成，再合成 MP4；预览掉帧不影响最终导出帧数。
6. 自动化入口：用场景 JSON / 工程命令生成布局和规则，批量改种子、渲染、生成报告；可接编辑器 MCP，但不能只依赖 AI 点击 UI。

**工程判断**：优先做插件/扩展包与业务工程，不先长期 fork 渲染引擎；若必须修改 Editor 源码，改动集中在规则面板、输出面板和扩展入口，避免跟着上游全面改编辑器。

## 视频导出与可复现性的事实边界

- [Rapier JS 确定性文档](https://rapier.rs/docs/user_guides/javascript/determinism/) 明确称 WASM/TypeScript/JavaScript 版本支持跨平台确定性，但前提是**同版本、完全相同初始条件、完全相同增删顺序**。文档特别指出 Math.sin / Math.cos 等初始化运算可能跨平台不确定。这是有条件的物理结果承诺，不保证 WebGL/WebGPU 渲染像素也跨 GPU 相同。
- [Rapier 刚体文档](https://rapier.rs/docs/user_guides/javascript/rigid_bodies/) 真实提供 CCD 开关，默认关闭；文档解释通过对运动路径做碰撞查询避免高速 tunneling。新项目仍需配置并保留高速正碰/擦碰回归，换引擎不会自动纠正分裂规则。
- react-three-rapier README 有固定 timeStep、manual stepping、snapshots 和碰撞事件；同时明确 `timeStep="vary"` 会降低稳定性并破坏确定性。应接管步进，而非由屏幕帧率决定物理。
- 浏览器实时录屏只能是快捷预览方式，不能当成固定帧率离线渲染的替代。正式输出仍应固定时间步渲染并验证帧数/时长、声音同步、缺帧与异常退出。
- 字体和画面叠加不能只放在编辑器 HTML 层而不进导出画面。若 HTML 标题只盖在 canvas 上，直接捕获 canvas 将漏掉这些文字；应使用同源画布渲染、引擎 GUI 或明确的离线叠字阶段。

## Web 路线的工时估算

以下是本次工程估算，不是仓库作者的报价；1名熟练工程师、1人日按6–8小时，假设允许使用成熟依赖、不开发物理求解器内核。复杂软体、流体、高级破坏、多人协作、插件商店不包含。

| 路线 | 能制作首批视频的验证版 | 稳定专用工作台累计 | 关键额外代价 |
|---|---:|---:|---|
| 扩展 Babylon Editor + 原生 Havok，先3D/2.5D | 12–20人日 | 35–60人日 | 规则层、轨迹重放、文字包装、离线导出；完整真2D后端再加8–15人日 |
| Babylon 自建工作台 + Rapier 2D/3D | 20–35人日 | 50–85人日 | 除上述外，还需物理适配、拖拽选择、撤销、资源浏览与属性面板 |
| Three/R3F + react-three-rapier + 自建编辑器 | 20–35人日 | 55–90人日 | 物理3D封装较现成，但编辑器基础设施与严格2D后端仍需建设 |
| 改造 PlayCanvas Editor（允许线上服务） | 12–25人日 | 35–65人日 | 同样需规则/视频导出；线上项目服务依赖需接受 |
| 把 PlayCanvas Editor 改成完整本地离线系统 | 不给可信快速周期 | 至少在上项基础上增加后端替代工作 | 本轮未核实独立后端源码范围，不应把前端开源误判为克隆即部署 |
| Matter/Phaser 只做2D专用工作台 | 10–20人日 | 25–45人日 | 能做好2D，但将来增加完整3D需要另建渲染/物理路径，不能算已满足本轮完整目标 |

若按1,500–2,500元/人日计，35–60人日仅工程人力约5.25万–15万元；这不是开源许可费用，不含模型/字体/声音资产及维护，AI代写代码也不把集成、调试和验收工时降为零。

## 取证方式与限制

GitHub 元数据取自 `https://api.github.com/repos/{owner}/{repo}`，README 通过 `/readme` 的 base64 content 读取，源码树用 `/git/trees/{branch}?recursive=1`。本轮 `raw.githubusercontent.com` 多次连接重置；改用 GitHub API 后成功。部分 MDN、npm registry 请求握手超时，未用这些失败请求作为事实依据。

Havok MIT 原文取自 [packages/havok/LICENSE](https://github.com/BabylonJS/havok/blob/main/packages/havok/LICENSE)，包含 "Permission is hereby granted, free of charge" 和商用/分发权限，保留著作权及许可声明。

未核实每个项目最新 release 号，不把 pushed_at 当 release；未运行 GPU 大场景或导出 benchmark，因此没有臆测“几千球稳定60fps”或“4K导出具体分钟数”。

## 工时口径补充澄清

主报告整合时已将本笔记原估算统一解释为每人日8小时：Babylon Editor的35–60人日、Three/R3F的55–90人日均只含3D／2.5D与专用工作台，不含独立2D后端。两者分别追加8–15人日后，完整目标为43–75、63–105个8小时人日。主报告与CSV采用这一澄清口径，不使用上文“6–8小时”模糊范围。
