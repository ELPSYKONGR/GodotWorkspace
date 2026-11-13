# 解压动画本地工作台

本机 CPU 生成二维物理动画，提供六种方案、文字编辑、连续画面预览、高清单帧和 MP4 导出。项目位于 D 盘，Python 运行时、依赖、缓存、日志和输出均放在项目内，无需 NVIDIA 显卡或付费视频生成接口。

## 启动与操作

双击 **`studio.cmd`**，浏览器会打开 **http://127.0.0.1:8765**。保持启动窗口运行；在窗口按 `Ctrl+C` 停止服务。

1. 选择六种方案之一：“碰撞增殖”“旋转逃逸”“小球雨释放”“环形缺口逃逸”“倍增链路·破碎多米诺”或“双通道指数赛”。
2. 调整输出尺寸、帧率、时长、释放时间或随机种子。
3. 选择文字层，修改内容、字体、字号、位置、颜色及显隐，也可增删文字层。
4. 点击右侧“播放预览”直接观看连续动画，可暂停、拖动进度或循环；文字编辑会自动更新。点击“高清单帧”查看输出分辨率的静帧；点击“导出视频”生成带声成片。
5. 点击“保存配置”，将当前参数写入 `config/current.json`，下次启动继续使用。

连续预览无需导出 MP4，使用与导出相同的轨迹和绘制程序，以 360×640 显示，目标为输出帧率与 30fps 中的较小值，并显示实际播放帧率。连续预览暂时无声；导出视频包含配置的音轨。修改文字、字体、字号、位置和颜色后约 0.4 秒自动刷新；修改物理参数、时长或种子后需要等待重新模拟，然后保留原播放状态继续预览。实际刷新速度取决于模拟和绘制耗时。默认服务只监听本机地址，不接受局域网远程访问。

## 六种已实现方案

| 方案 | 机制 | 主要观看变化 |
|---|---|---|
| 碰撞增殖 `multiply` | 符合冷却与空间条件的碰撞产生新球 | 从少量到密集，末段集中释放 |
| 旋转逃逸 `escape` | 固定数量的小球寻找旋转圆环的缺口 | 观察谁能逃出、剩余多少 |
| 小球雨释放 `rain` | 持续尝试从上方投球，拥堵时跳过投放 | 堆积、翻动，然后清空 |
| 环形缺口逃逸 `ring_escape` | 多层固定半径环的旋转缺口，小球受碰撞后寻找出口 | 观察穿环、碰撞和最终逃逸数 |
| 倍增链路 `stack_domino` | 主球触发机械闸门，释放预装球并触发多米诺和玻璃 | 观察释放规模、链式破碎和真实计数 |
| 双通道指数赛 `versus` | 两条同尺寸通道同时接触分裂，先到容量的一侧获胜 | 观察单球能否追上群球、领先多少秒 |

基础三种方案默认均为 24 秒，20 秒时打开边界；新增三种方案使用各自的阶段和结果规则。六种方案共用数据层、文字渲染、事件音效和导出流程。详细机制、调参方法与后续扩展方向见 [方案设计](docs/方案设计.md)。

## 已生成样片

| 产物 | 规格与用途 |
|---|---|
| `outputs/examples/multiply/final.mp4` | 碰撞增殖，24 秒、720×1280、30fps |
| `outputs/examples/escape/final.mp4` | 旋转逃逸，24 秒、720×1280、30fps |
| `outputs/examples/rain/final.mp4` | 小球雨释放，24 秒、720×1280、30fps |
| `outputs/examples/three_schemes.png` | 三种基础方案画面对照 |
| `outputs/implemented_ring_escape/final.mp4` | 环形缺口逃逸·多层旋转缺口，19.6 秒、1080×1920、60fps |
| `outputs/implemented_stack_domino/final.mp4` | 机械闸门·预装球·破碎多米诺，18 秒、720×1280、30fps |
| `outputs/versus_demo/final.mp4` | 保留的旧规则双通道指数赛，18 秒、720×1280、30fps |
| `outputs/versus_split_v2/final.mp4` | 双通道分裂新版：原球移除、分裂顿帧、同色系逐代变浅，18 秒、720×1280、30fps |
| `outputs/versus_collision_fix/final.mp4` | 碰撞触发修正版：墙、地面、顶部与球球接触均可分裂，原球移除与代际颜色保留 |
| `outputs/sample_1080p_seed42/` | 保留的旧原型 1080p 样片与原运行报告 |

每次完整导出目录包含带声 `final.mp4`、无声 `video_only.mp4`、`sound.wav`、`poster.png`、`contact_sheet.jpg`、运动数据 `scene.npz`、配置 `config.json` 和导出报告。工作台自动为每次导出新建目录；命令行指定同一 `--output` 目录时会覆盖其中同名产物。

## 可修改参数

界面提供常用参数；完整参数保存在 `config/current.json` 或 `config/presets/{multiply,escape,rain,ring_escape,stack_domino,versus}.json`。项目根目录不再使用旧的 `config.json`。修改当前配置后重新加载页面；修改预设后刷新并重新选择对应方案。也可通过命令行 `--config` 读取指定 JSON。

左侧面板按**当前机制**生成参数控件：换方案或换机制时，属于该机制的旋钮自动出现（`versus` 是容量、起始球数、分裂颗数、两侧新生保护、左首球保护延迟、判定后停留、分裂顿帧与代际颜色）。修改后自动准备连续预览；`versus` 还会回报判定时刻、胜负与比分，若「判定时刻 + 停留」超过视频时长会直接提示加长时长。

双通道的分裂数字表示**子球总数**：默认左侧 1→4、右侧 1→2，原球移除，分别净增 3 颗与 1 颗。墙、地面、顶部及球球碰撞都可触发；球球碰撞时双方分别检查，已就绪的球各自分裂。初始球默认就绪，子球统一经过 0.05 运动秒的新生保护后才可分裂，不再随机等待数秒。保护期内的碰撞只有在保护结束时仍接触才触发；已经分离的碰撞不延后补发。每颗原球在同一求解步最多替换一次，撞到墙角也不会重复分裂。满容量或开闸后停止分裂，临近上限时最后一次只补足容量。

默认顿帧 0.06 秒，期间暂停球运动、新生保护计时和出生生长动画；同一物理求解子步中的分裂合并一次，至少运动 0.25 秒后才再次触发，避免密集分裂造成连续停住。面板中可调顿帧时长（0 为关闭）与间隔。两侧新生保护对应 `left_cooldown` / `right_cooldown`，默认均为 0.05 秒；左首球保护延迟 `first_split_at` 默认 0，可设为 0–12 运动秒。

高速碰撞会根据球半径与最高速度自动细分物理步进，减少小球直穿或擦碰漏判。默认半径5.5、最高速度900时内部为240Hz，半径3时为360Hz；每个子步后立即处理分裂和顿帧。轨迹采样率与导出帧率仍可独立设置。

左侧默认绿色、右侧默认橙色；每颗初始球为第 0 代，子球比父球高一代，越往后分裂颜色越浅，同一代颜色相同。可修改左右基色和“逐代变浅强度” `appearance.generation_fade`，默认 0.2，设为 0 则保留基色。颜色调整只重新绘图，不影响运动与赛果。

| 配置部分 | 主要内容 |
|---|---|
| `output` | 宽高、帧率、时长；尺寸支持 360×640、540×960、720×1280、1080×1920；帧率支持 24、25、30、50、60；时长 1–60 秒 |
| `simulation` | 方案、种子、初始球数、数量上限、球半径、挡板转速、重力、增殖冷却、释放时间、数据采样率 |
| `texts` | 文字层 ID、内容、字体 ID、字号、X/Y、颜色、显隐；JSON 可设置 `anchor` 对齐方式 |
| `appearance` | 背景渐变、圆环、挡板、小球调色板与 `versus` 逐代变浅强度 |
| `audio` | 程序音效开关与音量；可选低频铺底 `bgm`/`bgm_level` 与总增益 `gain` |

文字位置与字号使用 **720×1280 逻辑画布**，随输出分辨率等比缩放。字号范围为 8–180；文字越界会报错，需调整位置、字号或内容。字体来自已安装字体或 `assets/fonts/`，页面选择字体 ID，不能传入任意文件路径。

基于同类样本分析重新设计的两个首发方案已经接入工作台：`ring_escape`（环形缺口逃逸）和 `stack_domino`（倍增链路与破碎多米诺）。它们与 `multiply`、`escape`、`rain` 一样可以从页面预览、修改文字并导出视频；完整规格见 `09_50x50扩展/scheme_A_ring_escape.md` 和 `02_项目方案/03_爽感解压动画/scheme_b_stack_domino.md`。

动态文字支持 `{count}`、`{remaining}`、`{escaped}`、`{time}`、`{phase}`；`versus` 另支持 `{left}`、`{right}`、`{winner}`、`{margin}`（可用 `{margin:.2f}`）与规则占位符 `{capacity}`、`{seed_balls}`、`{left_burst}`、`{right_burst}`——改参数时标题和规则文案会自己跟着换数字。其中 `count` 为累计出生数，`remaining` 为仍保留在模拟中的对象数，`escaped` 为从缺口逃出的数量。`versus` 的累计出生数包含已分裂移除的原球，左右赛果计数不包含这些原球；具体账目与配置结构见 [开发接口](docs/contracts.md)。

## 数据层与渲染层

物理层先生成 `SceneData`，以压缩 NPZ 保存位置、颜色编号、数量、角度、释放状态和碰撞事件；`versus` 另记录分裂移除数、代数和扣除顿帧后的运动时钟。数据默认按 **60 Hz** 采样，可在 JSON 中改为 30、60 或 120 Hz。渲染层读取已有数据生成画面和音频，不在绘图时运行物理世界。

运动缓存键包含时长、`simulation` 参数和各方案专属参数（包括 `versus` 分裂规则及顿帧），缓存位于 `.cache/scenes/`。代际配色属于 `appearance`，不进入运动缓存键。

| 改动 | 是否重算运动 |
|---|---|
| 文字、字体、字号、位置、颜色、显隐、背景与小球配色 | 否，重新绘图与编码 |
| 输出尺寸、输出 FPS、音量与音效开关 | 否，复用同一份轨迹 |
| 时长、释放时间、种子、方案、分裂规则、顿帧或其他物理参数 | 是 |

例如，同一份 60 Hz 轨迹可导出 30fps 和 60fps 两个版本；提高输出 FPS 不会提高已有运动数据的采样率。模块职责与依赖图见 [文件索引](FILE_INDEX.md)。

## 命令行与批量生成

在本项目目录运行：

```powershell
# 启动编辑器；--open 自动打开浏览器
.\.venv\Scripts\python.exe -B -m src.cli studio --open

# 选择预设，修改帧率与种子并导出
.\.venv\Scripts\python.exe -B -m src.cli render --preset escape --fps 60 --seed 73 --output outputs/escape_seed73

# 使用编辑器保存的完整配置
.\.venv\Scripts\python.exe -B -m src.cli render --config config/current.json

# 只生成运动数据
.\.venv\Scripts\python.exe -B -m src.cli simulate --preset rain --output outputs/data/rain.npz

# 读取既有运动数据，仅重新渲染；使用与数据匹配的原配置
.\.venv\Scripts\python.exe -B -m src.cli render --scene outputs/examples/escape/scene.npz --config outputs/examples/escape/config.json --fps 60 --output outputs/escape_60fps

# 同一方案批量更换种子
powershell -NoProfile -ExecutionPolicy Bypass -File batch.ps1 -Preset multiply -Width 720
```

`render.py` 现在只是转交给 `src.cli` 的兼容启动器。`run.cmd` 导出当前配置，`preview.cmd` 导出 12 秒、360×640 的低清视频，`watch.cmd` 打开保留的旧样片。这里的 `preview.cmd` 是短视频导出，与编辑器的单帧预览不同。

## D 盘环境与检查

```text
relaxing-physics/
  .runtime/python/       项目内 Python 3.12.13
  .venv/                 运行依赖、开发工具与随包 FFmpeg
  .cache/                下载缓存、临时文件、字节码目录、运动轨迹缓存
  config/                当前配置和六个 JSON 预设
  src/                   数据、物理、渲染、服务与界面
  outputs/               样片、预览、运动数据和运行报告
  logs/                  应用日志
```

运行依赖包括 Pymunk 7.3.1、Pillow **13.0.0**、NumPy 2.5.4、imageio-ffmpeg 0.6.0；精确版本以 `requirements.lock` 为准。本轮已将 Pillow 升级到 13。FFmpeg 随依赖提供，系统字体与已有 `uv` 只用于读取或启动。

重建环境需要已有 `uv`，在项目目录执行：

```powershell
# 按 requirements.lock 安装运行环境
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1

# 额外安装 Ruff 与 pip-audit 开发工具
powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Dev

# 单元/集成测试、Ruff 和运行依赖审计
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check.ps1
```

安装和双击启动脚本将 Python、虚拟环境、下载缓存及临时目录定向到本项目，不注册全局 Python。`requirements-dev.txt` 是可选开发工具范围，运行依赖使用 `requirements.lock` 固定版本。具体检查与实测记录保存在 `outputs/` 的验证报告和各导出目录的报告中。

当前 CPU 路线不需要连接远程 4080 SUPER。若后续增加三维渲染或生成式模型，再单独评估远程 GPU 部署，并按要求使用远程 C、D 盘之外的目录。本工作台尚未接入平台发布或收益统计。
