# 属性界面设计原型

本目录为2026-11-16设计交付，不是工作台新版本。完整范围、Git证据与接入步骤见[方案](../../长场景与属性面板方案_20261116.md)。

双击 `index.html`，即可在普通浏览器离线查看九个属性面板。点击分类切换，数值框宽度常规88像素。颜色、标题、部分材质示意和深度可更新；“更新示意”只改变本页，不写场景、不调用引擎。试听为临时合成短音，不是现有素材的试听。

用户补充后已改为一行2～3个相关属性。新增 [shape-editor.html](shape-editor.html)：可绘制圆/矩形/简单多边形、拖顶点、赋属性、加入场景并拖动布置；正式工作台的物理接口尚未接入，模拟按钮禁用，导出为设计数据。完整说明见[形状编辑方案](../../形状编辑环境与多列属性方案_20261116.md)。

已有场景与新建物体是并列入口。从属性面板进入形状编辑环境时，默认显示内置示例场景，可直接选物体改属性/位置；“编辑所选轮廓”创建原对象的草稿，“应用回当前物体”更新同一ID，不增加物体，“放弃轮廓草稿”保留原对象。新建绘制和保存副本仍可用。这里只演示交互，不会读取/覆盖用户Godot场景；正式接入应保留现有工作台的表现即时更新、物理参数应用并重新运行的行为。

源文件职责：

- `index.html`：整体工作台布局，明确设计状态。
- `panels.js`：九类属性的示意数据，非当前场景schema。
- `preview.js`：本地表单草稿、分类、构图/外观示意和用户点击后的短音试听。
- `style.css`：紧凑输入、分组、固定画幅和响应式布局。
- `00-workbench.png`：完整布局；`01-*.png`至`09-*.png`：各属性面板截图。
- `validation.json`：本轮界面文件验证记录；不代表Godot功能验收。
- `shape-editor.html` / `shape-editor.css`：绘制/布置环境布局与紧凑属性。
- `shape-model.js`：独立形状源数据、轮廓校验和设计JSON序列化。
- `shape-editor.js`：新建绘制、已有物体轮廓草稿/应用/放弃、属性编辑、场景副本与拖动；不运行物理。
- `10-shape-editor.png` / `11-scene-layout.png` / `shape-editor-validation.json`：两种编辑状态的截图和交互验证。
- `native-shape-check.gd` / `native-shape-validation.json`：独立工程运行的原生凸分解/碰撞可行性检查与本轮9项结果；未接入正式工作台。

不依赖联网字体、第三方前端库或服务器。图片/音频路径是可编辑示例，本目录未捆绑这些媒体资源。

预览可使用查询参数：`index.html?panel=material&mode=panel`。面板ID依次为 `scene`、`object`、`material`、`physics`、`background`、`collision-audio`、`music`、`text-effects`、`output`。省略mode显示完整布局。

形状编辑器不带参数时进入新建草图；`shape-editor.html?mode=scene`进入已有示例场景。轮廓草稿在两个空间切换时保留；尚未闭合的绘制点在切换时取消。关闭页面后不保留数据，需手动导出设计JSON。

若轮廓草稿尚未应用，又回场景修改了同一个原物体，旧草稿会提示冲突并拒绝覆盖；可以放弃后重新编辑，或保存副本。正式工作台接入使用既有修订号命令校验。

重新生成截图时用临时浏览器配置目录，放在本工程的scratch下；不要占用用户日常浏览器配置。建议单页520像素宽、完整布局1440像素宽；使用浏览器的实际渲染结果，避免将设计图写成引擎截图。

复验原生物理样本：从项目根目录执行以下PowerShell，创建独立空工程。使用现有便携工具和重定向环境，不启动工作台；新报告写scratch，不覆盖随附证据。

```powershell
. .\tools\common.ps1
$probeRoot = Join-Path $LabRoot 'scratch\native_shape_recheck'
New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $probeRoot 'project.godot'), "config_version=5`n")
$probeScript = Join-Path $LabRoot 'docs\design\inspector-20261116\native-shape-check.gd'
$probeReport = Join-Path $probeRoot 'report.json'
& $Godot --headless --path $probeRoot --script $probeScript --max-fps 120 -- "--report=$probeReport"
```
