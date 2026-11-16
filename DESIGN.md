---
name: "解压视频工作台"
description: "以画面为中心的矿物绿 Godot 原生创作工作台"
colors:
  mint: "#8de0c5"
  mint-hover: "#b5eedb"
  mint-pressed: "#69c7a8"
  on-mint: "#132a22"
  selected-text: "#c3f5e2"
  selected-surface: "#315448"
  selection: "#315f50"
  result: "#abd9bd"
  error: "#ff9d9d"
  canvas: "#111b18"
  panel: "#1c2825"
  field: "#121e1b"
  control: "#283633"
  control-hover: "#354641"
  control-pressed: "#284c40"
  control-disabled: "#202c29"
  popup: "#25332e"
  popup-hover: "#365346"
  ink: "#e8eeed"
  muted: "#a5b5b3"
  disabled-ink: "#71817f"
typography:
  title:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Noto Sans CJK SC, Arial"
    fontSize: "18px"
  body:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Noto Sans CJK SC, Arial"
    fontSize: "14px"
  label:
    fontFamily: "Microsoft YaHei UI, Microsoft YaHei, Noto Sans CJK SC, Arial"
    fontSize: "12px"
rounded:
  square: "0px"
  popup-hover: "3px"
  field: "4px"
  control: "5px"
  popup: "6px"
spacing:
  divider: "1px"
  row: "8px"
  stack: "9px"
  numeric-column: "10px"
  flow-column: "12px"
  panel-inline: "14px"
components:
  button-primary:
    backgroundColor: "{colors.mint}"
    textColor: "{colors.on-mint}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "7px 14px"
  button-primary-hover:
    backgroundColor: "{colors.mint-hover}"
    textColor: "{colors.on-mint}"
  button-primary-active:
    backgroundColor: "{colors.mint-pressed}"
    textColor: "{colors.on-mint}"
  button-secondary:
    backgroundColor: "{colors.control}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "6px 10px"
  button-secondary-hover:
    backgroundColor: "{colors.control-hover}"
    textColor: "{colors.ink}"
  button-secondary-active:
    backgroundColor: "{colors.control-pressed}"
    textColor: "{colors.mint}"
  button-disabled:
    backgroundColor: "{colors.control-disabled}"
    textColor: "{colors.disabled-ink}"
  button-flat:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "6px 10px"
  input:
    backgroundColor: "{colors.field}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.field}"
    padding: "7px 9px"
  input-read-only:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.ink}"
  numeric-input:
    backgroundColor: "{colors.field}"
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    rounded: "{rounded.field}"
    width: "88px"
  navigation:
    backgroundColor: "{colors.control}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "6px 10px"
  navigation-selected:
    backgroundColor: "{colors.control-pressed}"
    textColor: "{colors.mint}"
  object-list-selected:
    backgroundColor: "{colors.selected-surface}"
    textColor: "{colors.selected-text}"
    rounded: "{rounded.field}"
    padding: "7px"
  panel:
    backgroundColor: "{colors.panel}"
    rounded: "{rounded.square}"
    padding: "12px 14px"
  disclosure:
    textColor: "{colors.ink}"
    typography: "{typography.body}"
    padding: "6px 10px"
---

# Design System: 解压视频工作台

## Overview

**Creative North Star: "克制的矿物绿工作空间"**

矿物绿面板承载紧凑的原生工具，中央画面是持续可见的工作对象。薄荷色只承担主操作、选中和焦点反馈；界面保持安静，让可编辑的场景内容决定画面的色彩与表现。

系统中文字体、稳定输入宽度和按需展开的属性组，服务连续的布置、验证和输出。物体属性与全局设置用标题和作用范围区分；简短结果反馈留在滚动区外。这里记录的是已实现的 Godot Control 工作台，不约束视频内容中的字体、颜色、荧光或三维光照。

**Key Characteristics:**

- 矿物绿平面层次与薄荷色状态反馈。
- 系统中文字体与紧凑、稳定的原生输入。
- 中央画面扩展，物体与属性各有固定工作区。
- 低频选项逐级展开，状态与结果持续可见。

规范依据：`src/ui/workbench_theme.gd`、`workbench_layout.gd`、`form_helpers.gd`、`object_panel.gd`、`workbench_ui.gd`、`scene_bar.gd`、`production_panels.gd`；并核对 `docs/design/workbench-redesign-20261116/` 的物体、紧凑、宽屏、错误及焦点原生截图。前置方向来自同目录 `brief.md`；实际值以源码为准。文档头部的 token 是记录层，运行时仍由 Godot Theme 定义。配套 sidecar 的 HTML/CSS 是规范面板中的展示转译，色阶条为展示合成值，不是新增的运行时 token。

## Colors

低饱和矿物绿负责界面结构，明亮薄荷负责操作，文字与状态保持可辨识。

### Primary

- **薄荷**（`mint`）：底部运行/暂停、导出入口与可执行的开始导出按钮；同时用于键盘焦点、光标和按下状态文字。
- **浅薄荷 / 深薄荷**（`mint-hover`、`mint-pressed`）：主按钮的悬停与按下反馈；深绿文字（`on-mint`）保持可读。
- **选中绿**（`selected-surface`、`selected-text`）：物体列表选中行。文本选择使用独立的 `selection` 色。
- **结果绿 / 错误粉**（`result`、`error`）：底部操作结果，必须配真实文字说明。错误粉不是第二套品牌强调色。

### Neutral

- **深矿物底**（`canvas`）：中央画面周围的工作背景及工作区之间的细缝。
- **矿物面板**（`panel`）：侧栏、页容器、顶栏、底栏以及只读输入底色。
- **内凹输入底**（`field`）：可编辑文本与数值输入。
- **控件绿**（`control`、`control-hover`、`control-pressed`、`control-disabled`）：普通按钮及选择控件的完整状态。
- **菜单绿**（`popup`、`popup-hover`）：弹出菜单及当前悬停项。
- **浅灰正文 / 灰绿辅助 / 失效灰绿**（`ink`、`muted`、`disabled-ink`）：正文、字段名与上下文、禁用控件文字。

**The State Color Rule.** 界面强调色说明可操作、选中、焦点或结果；场景自身的色彩不进入工作台主题。

## Typography

**Body Font:** Microsoft YaHei UI → Microsoft YaHei → Noto Sans CJK SC → Arial，由 Godot SystemFont 按系统可用字体回退。

**Character:** 单一系统字体适合中文属性表单；字号层次依赖用途，不靠装饰性展示字。源码未设置额外字重、字距或行高，不为它们发明固定值。

### Hierarchy

- **Title**（`title`）：属性面板主标题。
- **Body**（`body`）：按钮、正文、文本输入、菜单、物体列表、折叠组标题和上下文。
- **Label**（`label`）：数值字段上方标签、预览运行状态、底部操作结果。

**The Stable Type Rule.** 缩小窗口保留原字号与输入尺寸，以自动换行和属性区滚动适配，不整体缩放工作台。

## Layout

默认工作窗口（1440×900），最小窗口（1100×720），禁用内容整体缩放。横向主体包含左侧物体区（220px 最小宽度）、中央预览、右侧属性区（382px 最小宽度）；额外宽度交给中央预览。工作区以 `divider` 间隔分开，侧栏采用 `panel` 内边距。只有右侧属性内容纵向滚动，不开启水平滚动。

顶栏放文件与场景身份、保存、历史操作、应用运行和导出。左侧物体列表占用可用高度，六个设置入口构成两列网格，世界概览可折叠。中央预览有独立的返回布置入口和运行状态行。底部将运行、录制、逐帧、时间轴、时长及更多菜单放在同一行，操作结果另占固定可见的一行。

预览按内容比例居中完整显示：工作视口（720×1280），预览控件最小尺寸（310×300），不拉伸画面。界面中的视频标题及图像可随预览比例变化，工作台文字不随之缩放。上下文行和运行行各保留最小高度（22px）；操作结果行保留最小高度（20px），长文字裁切并由提示展示完整内容。

一般横排使用 `row`，纵向堆叠使用 `stack`；普通流式容器横向间隔（12px）、纵向间隔（10px）。连续数值字段放入自动换行容器：每个字段单元最小宽度（148px）、列间隔（10px）、数值框宽度（88px），采用上标签、下输入；文字、路径、选项和颜色按完整行展开，行标签最小宽度（84px）。

**The Canvas Space Rule.** 窗口变宽时扩展中央工作画面，保持两侧工具的稳定密度；窗口变矮时让属性内容滚动。

## Elevation & Depth

工作台主题不添加投影。深底、面板、输入底和控件底色构成平面层次，细缝区分相邻区域，单线薄荷描边表达键盘焦点。视频内容中的投影、荧光和三维光照属于用户作品，不适用这条界面规则。

**The Flat Workbench Rule.** 用色面和状态组织原生工作台；不要将视频中的光照与特效用作工具面板装饰。

## Shapes

大面板直角，控件轻微圆角。输入、列表选中行和焦点使用 `field` 圆角；普通与主按钮使用 `control` 圆角；弹出菜单使用 `popup` 圆角，其悬停项使用 `popup-hover` 圆角。常规面板和输入没有额外装饰描边。焦点独立叠加一圈（1px）薄荷描边，透明内部保持原控件内容可见。

折叠图标为实际绘制的几何折线（16×16px 画布、1.5px 线宽），方向表示展开或收起。继续采用 Godot 原生控件及其内建功能图标，不用文字字符模拟图标。

## Components

### Buttons

直接、安静，以状态变化表达反馈。

- **Primary:** `button-primary` 用于运行/暂停及导出相关主操作；悬停与按下分别使用对应 token，键盘焦点增加独立描边。底部运行/暂停至少88px宽。
- **Secondary:** `button-secondary` 用于保存、撤销、应用等普通操作；悬停变亮，按下变为深绿底和薄荷字。
- **Flat:** 文件、物体操作和折叠标题等使用原生平面按钮，静止时不绘制实心普通底，悬停与按下仍有反馈。
- **Disabled:** 普通失效底与失效字；依据真实能力或当前状态禁用，不虚构可用操作。
- **Motion:** 主题未定义补间或过渡时长；交互反馈由原生控件状态直接切换。

### Cards / Containers

面板是工作区容器，不是浮动卡片。使用 `panel` 的方角色面和内边距，内部默认按纵向节奏排列；嵌套属性组保持透明层次，不添加重复卡片底。底部结果容器的纵向内边距缩为（5px）。

### Inputs / Fields

内凹、可读，尺寸与作用范围稳定。

- 文本输入使用 `input`，只读底使用 `input-read-only`；薄荷色插入光标，独立文本选中色，辅助灰绿占位文字。
- 数值输入使用 `numeric-input`，不因可用宽度增加而拉长；输入的范围与步长由字段业务定义。
- 颜色使用原生 ColorPickerButton，最小尺寸（80×28px）；不将当前场景颜色存成界面 token。
- 焦点由主题透明描边叠加；错误在底部结果行显示文字与错误色，没有实现独立的字段红框规范。
- 锁定对象令相关文本/数值不可编辑、按钮失效；通过原生状态表达。

### Navigation

六个可见设置入口使用两列原生切换按钮。普通状态遵循 `navigation`，选中状态遵循 `navigation-selected`，通过背景与文字共同标识当前项。它们只切换右侧上下文内容，保留未提交草稿；点击物体列表或画面中的初始物体，返回对应物体属性。此桌面布局没有另设移动导航。

### Object Browser

物体列表固定在左侧，名称按行呈现，选中行使用 `object-list-selected`，键盘焦点保持独立薄荷轮廓。列表垂直项间距（10px），水平间距（8px）。添加物体、绘制和物体操作属于列表工作区；非二维场景的绘制入口禁用。

右侧名称下直接显示只读、可复制的物体ID。二维镜头跟随通过名称与ID的下拉列表选择目标；空ID明确显示自动选择首个动态物体，已失效ID保留并标记缺失。

### Disclosure Groups

原生平面切换标题配几何折线；内容依展开状态显示，并保留用户的展开选择。高频几何与布置默认展开，物理、高级碰撞等低频设置默认收起。材质继承与维度过滤依据当前数据显示适用字段。

### Transport and Result Feedback

运行按钮切换为暂停；同一个录制按钮切换为停止录制。时间轴随录制与有效时长决定是否可操作；无轨迹、轨迹过期或正在导出时显示实际原因并限制导出。运行状态在预览下方，操作结果在最底部，均不依赖打开属性组才能看见。

## Do's and Don'ts

### Do:

- **Do** 复用原生主题的普通、悬停、按下、禁用与焦点状态。
- **Do** 保留数值框（88px）与系统字号，让字段换行、属性区滚动。
- **Do** 用短标题和上下文说明当前物体或全局设置的作用范围。
- **Do** 在滚动区外显示真实运行状态和操作结果，错误同时提供文字说明。
- **Do** 将新增低频设置归入可折叠属性组，并遵守维度与继承条件。

### Don't:

- **Don't** 把场景预览中的字体、颜色、荧光或三维阴影提升为工作台主题。
- **Don't** 用整体缩小字体与控件适配支持范围内的紧凑窗口。
- **Don't** 为工作面板添加装饰投影或重复浮动卡片层次。
- **Don't** 用普通按钮的颜色替代真实禁用状态，或只用颜色表达错误。
- **Don't** 以文字字符替代几何折叠图标或原生功能图标。
