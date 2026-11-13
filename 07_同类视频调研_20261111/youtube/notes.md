# YouTube 案例核实结果

调研日期：2026-11-11。当前网络不能直接读取 YouTube：终端官方页连接被关闭，内置浏览器官方搜索页超时，错误为 ERR_CONNECTION_TIMED_OUT。这不是登录提示；本轮没有尝试登录、改变网络设置或绕过访问限制。

因此 `cases.json` 为空。没有将搜索摘要、B站搬运播放量或频道累计播放冒充为 YouTube 单条视频的当前播放/点赞数据。

Bing 对精确 Shorts 查询未返回案例；转向相邻的 MIKAN 弹珠赛道类别后，视频索引主要返回 Bilibili 镜像。检索证据保存在 `bing_video_snapshot.txt`、`bing_video_search.png`、`access_evidence.json`。下面仅为线索，非本轮可核实的 YouTube 高播放案例：

| 搜索索引候选 | 索引显示播放 | 索引显示时长 | 链接 |
|---|---:|---:|---|
| 解压视频：小球赛跑Marble race V14 | 225.3K | 3:32 | https://www.bilibili.com/video/BV1Si421m7Jq/ |
| mikan/经典弹珠竞速 | 115.4K | 6:03 | https://www.bilibili.com/video/BV1zP411C7HN/ |
| 小球繁殖生存比赛：液压机碾压小球的ASMR解压视频 | 48.1K | 4:50 | https://www.bilibili.com/video/BV15WzQBKEQa/ |

未实际观看这些视频，不对其具体节奏或音效作事实描述。国内调研代理已经找到更高播放且更匹配的官方可核实案例，建议总体报告优先采用那些案例；海外数据暂列未核实，不据此扩张结论。

追加核对：已读取本轮国内代理的 9 份官方详情 API 公开 `desc`，未发现 YouTube URL 或海外频道署名，无法据此继续定位海外原片。结构化记录见 `bilibili_source_clues.json`。这些投稿的 `copyright=1` 是平台投稿字段，不单独证明素材原创或权利归属。
