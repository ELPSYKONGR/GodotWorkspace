# 从这里接手：AI解压视频工作台与研究归档

交接日期：2026-11-13。这是同一任务的完整资料目录：前期三个AI视频项目评估、原始参考素材、同类视频研究、早期原型和当前Godot工作台。**当前开发主线是 `06_本地部署/godot-video-lab/`。**

## 在另一台电脑使用

1. 将整个交接包解压到Windows x64电脑的非系统盘，例如`E:\AIProjects\RelaxVideo`，保留内部目录结构。用户指定的远程4080 SUPER电脑不能放C盘或D盘。本次没有登录或部署远程电脑。
2. 双击`VERIFY_PACKAGE.cmd`，核对随包文件大小和SHA-256；它会检查`MANIFEST.json`，无需安装Python。
3. 双击`START_WORKBENCH.cmd`启动工作台，双击`OPEN_EDITOR.cmd`查看/修改源码、设置断点，F5运行。
4. 运行包自带Godot、独立Python/Pillow、FFmpeg、MinGit及锁定安装缓存。正常启动和制作视频无需联网，不借用其它目录的虚拟环境。

包中`06_本地部署/godot-video-lab/config/handoff_current_scene.json`保留的是最近确认保存的**初始布局**，不是求解器运行中间状态、编辑撤销历史或正在录制的轨迹。已有2D/3D Take和成片另行保留。启动器优先打开这个交接场景，随后可在顶部切换预设。

运行范围是Windows x64；系统、显卡驱动、PowerShell 5.1以上和可用中文字体仍由目标电脑提供。当前预览用OpenGL，生产可选Vulkan；本包未验证Linux/macOS，也不承诺不同显卡/字体像素相同。

## 给接手AI的阅读顺序

1. 本目录[AGENTS.md](AGENTS.md)、[FILE_INDEX.md](FILE_INDEX.md)。
2. Godot工程[AI交接](06_本地部署/godot-video-lab/docs/AI交接.md)、[需求与对话决策](06_本地部署/godot-video-lab/docs/需求与对话决策.md)、[工程知识与决策](06_本地部署/godot-video-lab/LESSONS.md)。
3. [工作台使用说明](06_本地部署/godot-video-lab/docs/工作台使用说明.md)、工程[FILE_INDEX](06_本地部署/godot-video-lab/FILE_INDEX.md)和[验收报告](06_本地部署/godot-video-lab/docs/工作台验收报告.md)。
4. [视频研究交接](06_本地部署/godot-video-lab/docs/视频研究交接.md)、[破坏与参考渲染选项](06_本地部署/godot-video-lab/docs/破坏机制与参考渲染选项.md)。
5. [迁移与打包说明](06_本地部署/godot-video-lab/docs/迁移与打包说明.md)、[迁移验收](06_本地部署/godot-video-lab/docs/迁移验收.md)。
6. 必要时查[对话文字导出](docs/conversation_readback/对话文字导出.md)与结构化JSON，回溯具体需求。它包含接口可读的32个回合，导出时本轮打包尚未结束；命令/工具输出未导出，单项上限12000字符，不能称为完整原始日志。

不要要求用户重新讲完整历史。用户提供想法，由AI操作数据、机制、界面和代码；当前没有内嵌聊天服务或自动发布到平台。

## 此刻已完成与未完成

- 已完成：2D/3D真实物理，正交三维的2.5D观感，八个面板，物体布置，文字/渲染/声音/屏幕特效，AI命令桥，录制/回放和独立带声音视频生产。
- 分裂语义：原球移除；数字为子球总数，默认1→2；同色逐代变浅；短暂新生保护；“子球继续分裂”默认开，可关闭为只分裂一代。容量/出生空间限制始终生效。
- 未完成：真实形状碎裂、耐久与裂纹、环形扇区、二维物理驱动三维外观、复杂约束/软体、严格四层接口解耦。参考破坏文档是具体方案，不是已实现功能。
- 下一步：按用户新指令继续。若继续破坏方向，先做矩形/盒体规则预切分、计次耐久、同色视觉碎屑的小场景，验证真实物理、生命周期和Take后再扩展。

## 视频和历史工程

主原片目录`09_50x50扩展/original_videos/`有B站57条、抖音50条；主50＋50样本均有本地文件。完整研究归档有189份媒体文件、109个作品ID，其中含1个图文故事，存在重复副本。旧报告“抖音13成功/37失败”已过时；新[媒体清单](06_本地部署/godot-video-lab/docs/reference_media_inventory.json)保留当前事实和历史声明。

原片、抽帧、页面/API证据、标题和指标保留，但没有逐条重新完整观看或试听。不要根据成片外观把作者工具鉴定为Blender/代码，也不要把制作建议写成已观察到的算法。

`06_本地部署/relaxing-physics/`保留旧Python原型源码、锁定依赖和主要成片，旧venv与缓存未复制；它不属于当前离线可直接运行承诺。历史研究脚本也可能依赖requests、yt-dlp、OpenCV、python-docx、openpyxl等，重跑时按用途建立新环境，不能把这些当成Godot核心依赖。

## 版本与完整性

`MANIFEST.json`记录本包每个文件的相对路径、大小、SHA-256、源码提交和场景来源；清单自身不自哈希。压缩包旁的`.zip.sha256`用于核对整个压缩包。校验后开始编辑/运行，部分生成文件或源码会改变，再次校验会如实报告变化。

`version_history/`保留研究交接、Godot和旧Python仓库的Git bundle；存在未提交历史改动时另带patch。可用随包MinGit恢复历史，具体命令见迁移说明。当前工作目录已经包含对应源码，不需要先克隆才能运行。

工程标准原文随包保存：[ENGINEERING_STANDARD_ENHANCED_v2.1.md](06_本地部署/godot-video-lab/docs/standards/ENGINEERING_STANDARD_ENHANCED_v2.1.md)。后续改动必须同步索引、CHANGELOG和有意义的验证，区分已实现、设计和历史记录。
