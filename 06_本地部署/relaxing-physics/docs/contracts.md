# 开发接口

配置结构（所有颜色为#RRGGBB，坐标与字号以720×1280逻辑画布计）：

```json
{
  "name":"碰撞增殖",
  "output":{"width":720,"height":1280,"fps":30,"duration":24},
  "simulation":{"mode":"multiply","seed":42,"sample_rate":60,"release_at":20,"initial_balls":6,"max_balls":460,"ball_radius":9.4,"rotation_speed":0.95,"birth_cooldown":1.1,"gravity":570},
  "appearance":{"background_top":"#0c1322","background_bottom":"#182338","ring_color":"#849dbc","rotor_color":"#7890b2","palette":["#74eabf","#ffb46f","#f5809f","#80baff","#cca5ff","#f8e188"]},
  "texts":[{"id":"title","text":"越碰，越多","x":360,"y":172,"size":46,"font":"auto","color":"#ebf0f8","is_visible":true}],
  "audio":{"is_enabled":true,"volume":1.0}
}
```

字体font取/api/fonts返回的ID或auto；不接受任意绝对文件路径。文本支持{count}、{remaining}、{escaped}、{time}、{phase}。versus另支持{left}、{right}、{margin}（可带.mf）、{winner}，以及规则占位符{capacity}、{seed_balls}、{left_burst}、{right_burst}（由config.versus提供，其余模式为空）。文字不强制缩小；越界时在预览和导出提示校验错误。各层不得把此模板作为实际默认值，默认配置以config/presets为准。

`versus` 的 `left_burst` / `right_burst` 表示子球总数，默认 4 / 2，原球从物理空间移除；取值分别为 2–12 / 2–6。容量不足时截断最后一次分裂，只补到每侧上限。墙、地面、顶部和球球接触均参与判定；球球接触对双方分别检查。`left_cooldown` / `right_cooldown` 为新生保护时长，默认均为 0.05 运动秒，不随机错峰；初始球默认就绪，`first_split_at` 单独控制左首球保护延迟，默认 0，范围 0–12 运动秒。

接触在 Pymunk `pre_solve` 中每个物理求解子步重新检查：子球在保护期中仍可正常碰撞，保护期满且仍接触时分裂；已经分离则等待下一次实际接触，不按历史碰撞定时补发。用待处理槽位集合去重，同一原球在一求解子步中只能替换一次；满容量或开闸后不分裂。`split_hitstop` 默认 0.06 秒（0–0.2，0 为关闭）；`split_hitstop_interval` 默认 0.25 运动秒（0.1–2），同一物理求解子步中的分裂合并顿帧。顿帧暂停物理求解、新生保护计时和出生年龄，视频时间继续推进；更改这些规则会重算轨迹。

外层按120Hz推进，内部自动细分 `substeps = ceil(max_speed / 120 / ball_radius)`，物理求解频率为 `120 × substeps` Hz。默认最高速度900、半径5.5时为2子步（240Hz），半径3时为3子步（360Hz）；每子步后立即处理分裂与顿帧。该规则用于减少高速直穿与擦碰漏判，属于离散子步改进，不是数学精确的连续碰撞检测，也不保证任意擦边都被捕获。它不改变SceneData采样率或导出FPS的含义。

`appearance.palette[0]` / `[1]` 为左右基色，默认绿色 `#22c55e` / 橙色 `#ff7a33`；`appearance.generation_fade` 默认 0.2（0–0.6）。第0代使用基色，每代逐渐向白色混合，最大混合比例渐近85%，保留色系。调色仅影响渲染，不重算运动。

## UI API

- GET /api/bootstrap → {presets:[{id,name,description,config}],fonts:[{id,name}],config:配置}
- POST /api/config {config} → {config:已校验配置}；保存当前配置。
- POST /api/preview {config,time} → {url:"/outputs/.../preview.png",data_key:"...",is_cache_hit:true/false,actual_time:秒,verdict:null|{decided_at,winner,margin,left_final,right_final,fits}}；verdict仅versus返回，fits=false表示判定后的停留被视频时长截断。
- POST /api/live-preview {config,session_id?:上次会话} → {session_id,data_key,is_cache_hit,duration,fps,width:360,height:640,verdict}；相同物理参数直接复用上次会话的轨迹，FPS最高30，输出配置不被修改。文字/外观调整创建新绘制实例，旧会话中的在途请求不受影响。
- GET /api/live-preview/{session_id}?time=秒 → image/png；直接返回与导出同源的无损帧，不写图片文件、不编码视频。时间必须有限且处于0..duration；未知或已回收会话返回404。内存最多保留4个会话，按最近访问回收；同一绘制实例串行使用。连续预览暂不包含声音。
- POST /api/render {config} → {job_id:"..."}
- GET /api/jobs/{id} → {state:"queued|running|completed|failed",progress:0到1,message,video_url,poster_url,scene_url,error}

API错误统一{error:"可理解的消息"}并返回4xx/5xx。前端请求只传相对API路径，所有文字写DOM用textContent。只读取outputs下产物。

`src/ui/live-preview.js` 管理连续预览的播放、暂停、进度和循环。最多一个帧请求在途，用墙钟时间跳过迟帧以保持速度；配置编辑以400ms合并，版本号丢弃旧配置/旧进度的响应。物理变更期间暂停时钟，准备完毕后保持原播放状态。此模块只展示服务端帧，不实现另一套物理或绘制逻辑。

## SceneData（由物理与数据模块实现）

dataclass SceneData字段：metadata:dict，positions:float32[T,N,2]（该时刻未出生、已移除或已逃出的位置为NaN），counts:int32[T]（累计出生），remaining:int32[T]，escaped:int32[T]，rotor_angles:float32[T]，ring_angles:float32[T]，released:bool[T]，colors:uint8[N]，events:float32[M,3]（time,strength,pan），birth_times:float32[N]|None（每个槽位的视频出生时刻，未使用为NaN；仅`versus`提供，用于出生动画）。metadata包含duration、sample_rate、simulation、center:[360,664]、radius:263、summary。

分裂与顿帧的可选字段（旧NPZ缺少这些字段时仍可读取）：

| 字段 | 类型与含义 |
|---|---|
| `retired` | `int32[T]`，累计分裂移除的原球数；缺省全0，非负单调 |
| `generations` | `uint16[N] \| None`，每槽代数，初始0，子=父+1 |
| `motion_times` | `float32[T] \| None`，扣除顿帧的累计运动秒数，单调且不超过视频时间 |
| `birth_motion_times` | `float32[N] \| None`，每槽运动时钟下的出生时刻；未使用为NaN，初始球可为-1；填写时同时需要 `birth_times` 和 `motion_times` |

各帧账目为 `counts = remaining + escaped + retired`。`versus` 左右比分之和为 `counts - retired`；比分在开闸逃出后保持，不等于屏幕剩余数。父球退役后其槽不复用，子球使用新槽，保证历史出生时刻、代数和轨迹可追溯。`metadata.versus` 保存 `lane_slots`（每侧生命周期槽数）、`split_semantics`、`hitstop_windows`、逐帧左右比分和 `event_log`。详细 `split` 事件包含时间、侧别、原球槽、子球槽列表、子代数、分裂位置与请求子球总数；音效沿用限频 `birth` 事件，避免重复发声。

scene.frame_at(time) → SceneFrame字段：time:float, positions:ndarray[K,2]（该时刻仍存在的对象）,colors:ndarray[K]，count:int,remaining:int,escaped:int,rotor_angle:float,ring_angle:float,is_released:bool,ages:ndarray[K]（距出生秒数，缺省为空数组），generations:ndarray[K]（与可见槽对应的代数，缺省为空数组），retired:int（缺省0）；scene.save(path)；SceneData.load(path)。必须allow_pickle=False。`birth_times`与`ages`服务于渲染时序；存在运动时钟时，`ages = motion_times[index] - birth_motion_times[可见槽]`，否则使用视频出生时刻。因此顿帧期间位置、出生生长与光晕同步冻结。其他模式不填这些可选字段时保留原渲染行为。

基础三种模式multiply、escape、rain共用圆环/单根挡板；新增模式ring_escape、stack_domino、versus由独立生成器提供相同的SceneData合约，并在metadata中保存各自的事件和布局数据。escape圆环缺口40度，以角度0为右方向，缺口以90度方向为中心并随ring_angle转动；其他基础模式圆环完整，release后全部打开。数据帧含t=0与duration，frame_at采用最近的较早数据帧。

generate_scene(config, progress=None) → SceneData，progress接受一个0..1浮点数。物理配置来自config.simulation及各方案专属区块（如config.versus），时长来自config.output.duration，sample_rate独立于导出fps。缓存键包含这些物理参数及物理版本，排除文字、配色与输出fps；versus含高速子步修复的碰撞触发版本使用physics_revision=7，其余模式保留4。模拟模块不得读配置文件或调用渲染。每个函数提供说明注释。
