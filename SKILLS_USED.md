# Skill 依赖

Godot 工作台运行不依赖额外 Skill。运行依赖为 Godot、FFmpeg、Python；来源与许可见 docs/依赖来源.md。中文系统字体从本机读取，不附带字体文件。

2026-11-16 原生界面重设计使用用户指定的 Taste 与 Impeccable 作为 AI 开发辅助。锁定来源、下载 ref、版本、许可和引擎校验见 `config/design-skill-lock.json`；上游许可保存在 `docs/third_party/taste-skill-LICENSE.txt` 和 `docs/third_party/impeccable-LICENSE.txt`。这些工具不进入成片、不增加 Godot 的运行依赖。

安装复现：使用 Codex 内置 skill-installer 的 `install-skill-from-github.py`，按锁定文件的 `repository`、`download_ref` 和 `path` 下载，`--dest` 指向目标机器非系统盘技能目录；再在目标 Codex 技能目录建立对应目录引用。Impeccable 原生 Windows 引擎放到该技能的 `scripts/bin/windows-x64/impeccable.exe`，按锁定 SHA256 校验。技能不随本工程全量复制；离线运行工作台无需安装它们。

本次按原生桌面工具处理：采用 Impeccable Operate 模式的任务优先级、渐进披露和控件状态；Taste 提供一致边距、真实画面、精简文案的原则，其营销网站章节/照片/动画门禁不套用到 Godot。原生 GDScript 不运行 HTML/CSS 检测器；实际 GPU 截图、功能回归和独立设计评审用于验收。产品约束见 `PRODUCT.md`，实现后的视觉规则见 `DESIGN.md`。

2026-11-16设计辅助：读取环境提供的`visualize`（1.0.91）界面原型约定及`browser/control-in-app-browser`（26.1106.51428）浏览器约定；均来自Codex内置插件包，没有新安装依赖。内置浏览器连接初始化不可用，本轮实际PNG由本机Edge无界面模式渲染本工程HTML，使用工程盘独立临时配置目录。离线原型本身不依赖这些辅助工具；普通浏览器即可查看。
