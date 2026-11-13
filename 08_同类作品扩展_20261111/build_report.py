"""Render the expanded evidence-backed research report from cases_merged.json."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def fmt_count(value: int | None) -> str:
    return f"{value:,}" if isinstance(value, int) else "未公开"


def status_text(value: str | None) -> str:
    if value in {"downloaded_public_playback_stream", "downloaded", "downloaded_copy_for_research"}:
        return "已保存研究副本"
    if value == "failed_or_unavailable":
        return "页面证据已保存，媒体下载失败"
    return "页面/截图证据已保存"


def main() -> None:
    rows = json.loads((ROOT / "cases_merged.json").read_text(encoding="utf-8"))
    b_rows = [row for row in rows if row["platform"] == "Bilibili"]
    d_rows = [row for row in rows if row["platform"] == "Douyin"]
    categories = Counter(row["mechanism_category"] for row in rows)
    originals = json.loads((ROOT / "original_videos" / "download_manifest.json").read_text(encoding="utf-8"))
    original_count = sum(x["status"] == "downloaded_copy_for_research" for x in originals)

    top_b = sorted(b_rows, key=lambda row: row["views"] or 0, reverse=True)[:10]
    top_d = sorted(d_rows, key=lambda row: row["likes"] or 0, reverse=True)[:5]

    lines = [
        "# 47条同类型解压物理动画：案例分析与原视频归档",
        "",
        "调研日期：2026-11-11。用户要求至少分析30条；本轮形成 **47条主样本**：B站32条、抖音15条。另保存了 **40个可播放MP4研究副本** 到 `original_videos/`，并保留7条抖音页面证据但未能取得媒体文件。",
        "",
        "## 先给结论",
        "",
        "这类作品的爽感主要来自‘可理解的规则 + 可追踪的对象 + 可见的进展 + 真实的结果’。高量案例并不都靠复杂3D：B站最高样本是简单的圆环、球和线条。更值得复制的是机制结构，而不是外观、颜色或标题数字。",
        "",
        f"B站数据取自公开详情 API 的累计快照，最高播放样本为 {top_b[0]['views']:,} 播放、{top_b[0]['likes']:,} 赞。抖音详情页没有展示播放量，15条统一记为未公开；‘万’是页面约数。公开数据没有完播、留存或复看，因此下面的爽感解释是设计推断，不能写成流量因果。",
        "",
        f"原视频目录实际可播放副本：{original_count}个。B站下载工具还保留了1条后续排除的黑屏‘高级语言弹幕测试’原始播放流；它不进入47条主样本的设计分析。公开播放流用于内部研究，不代表创作者母版，也不自动产生转载、改编或商业发布许可。",
        "",
        "## 样本范围和证据限制",
        "",
        "- B站：公开搜索与详情接口；账号、作品标题、发布时间、时长、播放、点赞、评论、收藏、分享均按接口快照保存。",
        "- 抖音：从公开详情页、相关推荐和公开主页发现；页面显示点赞、评论、收藏、分享，播放量未公开，未从点赞反推。账号总获赞没有用作单条作品指标。",
        "- 观看范围：本轮多数条目保存中段抽帧或公开页面截图，未逐帧完整观看全部结尾，也未试听音轨；因此不声称竞品的完整结局、音效、完播或复看。",
        "- 样本偏差：B站样本按公开搜索和相关推荐获得；抖音样本有较多来自同一账号“探索宇宙”。这不是随机样本或全网榜单。",
        "",
        "## 最高量与高赞样本",
        "",
        "### B站：播放和点赞分开看",
        "",
        "|作品|发布账号|时长|累计播放|累计点赞|可借鉴结构|",
        "|---|---|---:|---:|---:|---|",
    ]
    for row in top_b:
        lines.append(f"|[{row['title']}]({row['url']})|{row['uploader']}|{row['duration_seconds'] or ''}秒|{fmt_count(row['views'])}|{fmt_count(row['likes'])}|{row['mechanism_category']}|")
    lines += [
        "",
        "其中‘30秒，能否吃完10083个小球？’有658,701播放但只有3,143赞，赞/播约0.477%，适合作为‘播放高不等于喜爱高’的对照。不能只挑最高播放作品来证明某个机制有效。",
        "",
        "### 抖音：只引用公开点赞显示值",
        "",
        "|作品|发布时间|时长|页面显示点赞|评论/收藏/分享|观察到的设计方向|",
        "|---|---|---:|---:|---|---|",
    ]
    for row in top_d:
        metrics = f"{row['comments_display']} / {row['favorites_display']} / {row['shares_display']}"
        lines.append(f"|[{row['title']}]({row['url']})|{row['published_at']}|{row['duration_seconds'] or ''}秒|{row['likes_display']}|{metrics}|{row['mechanism_category']}|")
    lines += [
        "",
        "## 47条案例的机制分析",
        "",
        "按保存记录的粗分类计数如下；同一作品可能同时包含多个机制，分类用于比较，不是作者公开的工程实现：",
        "",
    ]
    for category, count in categories.most_common():
        lines.append(f"- **{category}：{count}条**。关注的问题是：对象如何推进、什么算受阻、结果是否能在画面中核对。")
    lines += [
        "",
        "### 1. 数量增长、吞噬与爆发",
        "",
        "‘碰撞翻倍’、‘两个球相撞爆发’、‘碰到砖块获得对应数量’把数量变化变成叙事。爽点不是单纯更多，而是增长和清除形成竞争、最后几个对象有意义。实现时要显示真实数量或剩余目标，不能把冷却、上限和定时释放包装成‘每次必翻倍’。",
        "",
        "### 2. 逃逸、缩圈与多层突破",
        "",
        "‘只有一个小球能够逃出’、‘小球要多快才能逃出’、抖音的缩圈案例都把出口、剩余层数、缺口或倒计时作为目标。一个主角比几十个同等权重球更容易持续追踪。每突破一层就应出现下一层；错过窗口要有可见原因。",
        "",
        "### 3. 碰撞计数和阶段变形",
        "",
        "‘每5次反弹增加一条边’、‘每条边激活后增加边界’、‘三消减少多边形边数’把重复碰撞切成阶段。规则可预测但结果不能完全提前知道。一次试验只改一个主维度，避免球数、颜色、速度、边界和镜头一起变化。",
        "",
        "### 4. 时间规则、冻结、回溯和随机出口",
        "",
        "冻结、回溯、‘打开一扇门就关闭另一扇’会改变观众对下一步的预期。时间窗必须画面可读，随机也应有结果解释；否则观众只会看到球停住或突然消失。",
        "",
        "### 5. 阵营、生命线与颜色身份",
        "",
        "‘哪队能存活到最后’、‘失去所有线条被淘汰’把颜色变成身份和资源。线条既是装饰又是生命数，球可以抢回资源，因而比单向计数更容易产生站队和翻盘。自制版本要使用原创颜色、符号和素材，不直接复制他人画面。",
        "",
        "### 6. 同模板不保证稳定表现",
        "",
        "抖音同账号公开列表里的‘翻2倍、翻3倍、翻4倍’赞数差距很大。发布时间、曝光和分发未受控，不能归因于倍数。可得结论是：批量换颜色、换倍数、换数字不是稳定爆款方案；必须让每条有不同的目标、受阻和结果。",
        "",
        "## 对当前三个本地方案的直接改进",
        "",
        "|当前方案|本地抽帧/轨迹已核实的问题|下一步改法|",
        "|---|---|---|",
        "|碰撞增殖|20秒约353颗；后段更多是密度变化，没有唯一完成目标；末段约1.40秒无球|先做‘增殖 vs 吞噬’或真实目标数量；裁掉无球尾段；保持触发规则真实|",
        "|旋转逃逸|4秒已逃37颗，12–20秒仍为39；48颗中9颗靠最后全开释放|先修中段停滞，筛种子或调整缺口；显示‘39/48通过缺口’，不要把全开写成全部逃逸|",
        "|小球雨释放|副标题问‘何时溢出’，实际第20秒定时全开；末段约2.15秒无球|改成‘落球20秒，最后一起放开’，或实现真实到线/溢出判定；保留释放观察时间|",
        "",
        "这三点比先做复杂材质或上4080 SUPER更优先。现有数据层与渲染层分离仍然适合继续开发：数据层增加稳定球ID、出生/吞噬/淘汰事件、通过层数、资源转移、完成原因和结果时刻；渲染层负责颜色、拖尾、文字、计数和结果字幕。字体、字号、文案和帧率修改不应改变物理轨迹。",
        "",
        "## 建议的下一轮单因素实验",
        "",
        "1. 同一条逃逸轨迹，对照‘谁能逃出去？’和‘48颗球，能逃出几颗？’。",
        "2. 同一条轨迹只隐藏副标题，比较首屏理解与遮挡，不同时改字号和颜色。",
        "3. 只裁掉已经没有球的尾段，同时比较观看秒数、结尾退出和复看；完播率分母变短，不能单独看。",
        "4. 末段增加真实结果，例如‘39/48通过缺口’，不改变运动和结果。",
        "5. 有声与静音做对照，先试听实际混音；没有平台开声数据时不要推测音效因果。",
        "",
        "## 逐条分析索引（47条）",
        "",
        "每条下方的‘设计观察’来自保存的标题、简介、页面截图或机制字段；它是分析假设，未扩展成完整观看事实。",
        "",
    ]
    for index, row in enumerate(rows, 1):
        views = fmt_count(row["views"])
        likes = row["likes_display"]
        observation = (row.get("design_observation") or "未增加具体机制描述").replace("\n", " ").strip()
        if len(observation) > 140:
            observation = observation[:137] + "…"
        lines.append(f"{index}. **[{row['title']}]({row['url']})**（{row['platform']}，{row['uploader']}，{row['duration_seconds'] or '?'}秒；播放 {views}；赞 {likes}；{row['mechanism_category']}；{status_text(row.get('download_status'))}）。{observation}")
    lines += [
        "",
        "## 文件和复查",
        "",
        "- `cases_merged.json` / `cases_merged.csv`：47条合并结构化数据；CSV为UTF-8 BOM。",
        "- `original_videos/`：单独原视频研究副本目录；`download_manifest.json`记录每条状态、路径和大小。",
        "- `案例抽帧总览.png`：36张已保存画面抽帧索引，不代表完整观看。",
        "- `bilibili/cases_additional.json`、`douyin/cases_additional.json`：新增证据与逐条来源。",
        "- `bilibili/notes.md`、`douyin/notes.md`：下载口径、访问限制和单条观察。",
        "- `tools/download_bilibili_public.py`：只用公开 view/playurl API，检查 rights.download，不读取Cookies、不绕过验证码或付费限制。",
        "",
        "YouTube本轮仍未得到可核实的海外单片数据；抖音和B站公开作品也不等于取得改编权。报告只用于内部选题、技术验证和设计研究。",
        "",
    ]
    (ROOT / "00_47条同类作品分析.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"报告已生成：{len(rows)}条案例，{original_count}个可播放研究副本。")


if __name__ == "__main__":
    main()
