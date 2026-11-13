"""Normalize 50+50 public research cases and render the detailed analysis document."""

from __future__ import annotations

import csv
import json
import re
from collections import Counter
from datetime import datetime, timezone, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent


def first_value(item: dict, *keys, default=None):
    for key in keys:
        value = item.get(key)
        if value not in (None, "", []):
            return value
    return default


def usable(value):
    """Drop placeholders introduced by a lossy terminal/encoding export."""
    if value in (None, "", []):
        return None
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped or set(stripped) <= {"?", "�"}:
            return None
    return value


def published_value(value):
    if isinstance(value, (int, float)) and value > 10**9:
        try:
            return datetime.fromtimestamp(value, tz=timezone(timedelta(hours=8))).isoformat(timespec="seconds")
        except (OverflowError, OSError, ValueError):
            return value
    return value


def duration_seconds(value):
    if isinstance(value, (int, float)):
        return float(value)
    match = re.fullmatch(r"(?:(\d+):)?(\d+)", str(value or "").strip())
    return int(match.group(1) or 0) * 60 + int(match.group(2)) if match else None


def classify(text: str) -> tuple[str, str]:
    """Return a coarse mechanism and the visually dominant object."""
    text = text or ""
    if any(k in text for k in ("线条", "连线", "绳", "生命线", "扫线", "光束")):
        return "线条/连接资源", "线条"
    if any(k in text for k in ("粒子", "爆发", "烟雾", "碎片", "喷射")):
        return "粒子爆发/流场", "粒子"
    if any(k in text for k in ("长方形", "矩形", "砖块", "活塞", "方块", "门", "玻璃", "墙")):
        return "矩形/砖块/门", "长方形"
    if any(k in text for k in ("多边形", "几边形", "边界", "边数", "三消", "五角")):
        return "多边形边界/阶段", "多边形"
    if any(k in text for k in ("圆环", "圆圈", "缩圈", "同心", "缺口")):
        return "圆环/缺口逃逸", "圆环"
    if any(k in text for k in ("吞噬", "消灭", "清空", "吃完", "存活", "淘汰")):
        return "吞噬/消除/生存", "球"
    if any(k in text for k in ("翻倍", "增殖", "分裂", "碰撞", "反弹", "小球", "球")):
        return "球体碰撞/数量变化", "球"
    return "目标挑战/几何动画", "混合几何"


def normalized(item: dict, platform: str) -> dict:
    identifier = first_value(item, "id", "bvid", "aweme_id", "video_id")
    title = first_value(item, "title", "title_clean", default="")
    description = first_value(item, "description", "desc", default="") or ""
    text = f"{title} {description} {item.get('mechanism_category', '')} {item.get('design_observation', '')}"
    inferred_mechanism, object_type = classify(text)
    mechanism = first_value(item, "mechanism_category", default=inferred_mechanism)
    if mechanism in ("", None):
        mechanism = inferred_mechanism
    duration = duration_seconds(first_value(item, "duration_seconds", "duration", "duration_display"))
    display = item.get("metrics_display") or {}
    views = item.get("views")
    likes = first_value(item, "likes", default=display.get("likes"))
    likes_display = display.get("likes", likes)
    comments = first_value(item, "comments", default=display.get("comments"))
    favorites = first_value(item, "favorites", default=display.get("favorites"))
    shares = first_value(item, "shares", default=display.get("shares"))
    url = first_value(item, "url", "public_url", default=f"https://www.{platform.lower()}.com/video/{identifier}")
    analysis = item.get("design_analysis") if isinstance(item.get("design_analysis"), dict) else {}
    observation = usable(first_value(item, "design_observation", "design_hypothesis", "core_design", default=None))
    if observation is None:
        observation = usable(analysis.get("core_design"))
    if not observation and isinstance(item.get("observation"), dict):
        observation = item["observation"].get("hypothesis") or item["observation"].get("mechanism", "")
    download_status = first_value(item, "download_status", "status", default="unknown")
    evidence_scope = first_value(item, "watch_scope", "design_observation_scope", "evidence_scope", default="公开页面或抽帧观察；未自动推断完整结尾或音效。")
    return {
        "platform": platform,
        "id": identifier,
        "title": title,
        "uploader": first_value(item, "uploader", "author", default=""),
        "published_at": published_value(first_value(item, "published_at", "upload_date", default="")),
        "duration_seconds": duration,
        "views": views,
        "likes": likes,
        "likes_display": likes_display,
        "comments": comments,
        "comments_display": display.get("comments", comments),
        "favorites": favorites,
        "favorites_display": display.get("favorites", favorites),
        "shares": shares,
        "shares_display": display.get("shares", shares),
        "like_view_ratio_percent": item.get("like_view_ratio_percent"),
        "mechanism_category": mechanism,
        "object_type": object_type,
        "description": description,
        "design_observation": observation,
        "url": url,
        "download_status": download_status,
        "download_file": first_value(item, "download_file", "video_file", "media_file"),
        "frame_file": first_value(item, "frame_file", "screenshot_file", "image_file"),
        "evidence_file": first_value(item, "page_evidence_file", "snapshot_file", "page_evidence_files"),
        "evidence_scope": evidence_scope,
        "source_file": item.get("source_file", ""),
        # Preserve per-item analysis supplied by the collectors so the report
        # does not replace it with a generic mechanism paragraph.
        "source_visual_order": usable(first_value(item, "visual_order", default=analysis.get("visual_order"))),
        "source_motion_flow": usable(first_value(item, "motion_flow", "motion_fluidity", default=analysis.get("motion_fluidity"))),
        "source_audio_design": usable(first_value(item, "audio_design", "sound_coordination", default=analysis.get("sound_coordination"))),
        "source_hook": usable(first_value(item, "hook", "attention_hook", default=analysis.get("attention_hook"))),
        "source_retention": usable(first_value(item, "retention", "retention_design", default=analysis.get("retention_design"))),
        "source_expectation": usable(first_value(item, "expectation", "audience_expectation", default=analysis.get("audience_expectation"))),
        "source_implementation": usable(first_value(item, "implementation", "implementation_process", default=analysis.get("implementation_process"))),
        "source_core_design": usable(first_value(item, "core_design", default=analysis.get("core_design"))),
        "source_effective_mechanism": usable(first_value(item, "effective_mechanism", default=analysis.get("effective_mechanism"))),
    }


def load_platform(name: str) -> list[dict]:
    folder = ROOT / name
    candidates = [folder / f"cases_{name}_50.json", folder / f"cases_{name}_56.json", folder / f"cases_{name}.json", folder / "cases_douyin_partial.json", folder / "cases_work.json", folder / "cases_additional.json"]
    # Bilibili's batch normalizer writes its merged file at the research root.
    if name == "bilibili":
        candidates.insert(0, ROOT / "cases_bilibili_56.json")
    paths = [path for path in candidates if path.is_file()]
    if not paths:
        paths = sorted(folder.glob("cases*.json"))
    # Keep the previous 15 verified Douyin records alongside the new public
    # records. Their evidence remains in the earlier dated research folder.
    source_paths = list(paths)
    if name == "douyin":
        previous = PROJECT / "08_同类作品扩展_20261111" / "cases_merged.json"
        if previous.is_file():
            source_paths.append(previous)
    if not source_paths:
        return []
    rows = []
    seen = set()
    for path in source_paths:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict):
            data = data.get("cases") or data.get("items") or []
        for item in data:
            if not isinstance(item, dict):
                continue
            if name == "douyin" and item.get("platform") not in (None, "Douyin"):
                continue
            row = normalized(item, "Bilibili" if name == "bilibili" else "Douyin")
            if row["id"] in seen:
                continue
            seen.add(row["id"])
            try:
                row["source_file"] = str(path.relative_to(ROOT))
            except ValueError:
                row["source_file"] = str(path)
            rows.append(row)
    return rows


def enrich_download_status(rows: list[dict]) -> None:
    media = list(ROOT.rglob("*.mp4")) + list((ROOT.parent / "08_同类作品扩展_20261111").rglob("*.mp4"))
    evidence = list(ROOT.rglob("*_snapshot.txt")) + list(ROOT.rglob("*.png")) + list(ROOT.rglob("*.jpg")) + list((ROOT.parent / "08_同类作品扩展_20261111").rglob("*_snapshot.txt")) + list((ROOT.parent / "08_同类作品扩展_20261111").rglob("*.png")) + list((ROOT.parent / "08_同类作品扩展_20261111").rglob("*.jpg"))
    for row in rows:
        hits = [path for path in media if row["id"] in path.name]
        if hits:
            row["download_status"] = "downloaded_public_research_copy"
            try:
                row["download_file"] = str(hits[0].relative_to(ROOT))
            except ValueError:
                # Previous-round media lives beside this round; keep a project-relative path.
                row["download_file"] = str(hits[0].relative_to(PROJECT))
        evidence_hits = [path for path in evidence if row["id"] in path.name]
        if evidence_hits:
            try:
                row["evidence_file"] = str(evidence_hits[0].relative_to(ROOT))
            except ValueError:
                row["evidence_file"] = str(evidence_hits[0].relative_to(PROJECT))
        elif row["download_status"] in (None, "unknown", ""):
            row["download_status"] = "evidence_only_or_failed"


def choose(rows: list[dict], limit: int = 50) -> list[dict]:
    """Prefer downloaded records, then use stable public metric ordering."""
    def score(row):
        downloaded = row["download_status"] == "downloaded_public_research_copy"
        views = row["views"] if isinstance(row["views"], int) else 0
        likes = row["likes"] if isinstance(row["likes"], int) else 0
        return (downloaded, views, likes, row["id"] or "")
    return sorted(rows, key=score, reverse=True)[:limit]


def fmt(value):
    if value is None or value == "":
        return "未公开/未知"
    if isinstance(value, int):
        return f"{value:,}"
    return str(value)


def visual_notes(row: dict) -> tuple[str, str, str]:
    category = row["mechanism_category"] + " " + row["object_type"]
    if "线条" in category:
        return ("线宽、交叉层级和同色资源决定整齐度；节点与球体需要明确前后层级。", "碰撞/连接事件驱动线条转移、断裂或激活；避免线条交叉后目标不可追踪。", "用稳定颜色表示阵营或资源，首屏先展示一条可理解的连接关系。")
    if "圆环" in category:
        return ("同心环半径、间距和缺口角度形成规则网格；缺口不可被文字遮挡。", "缺口旋转、缩圈和突破窗口应连续；记录每层通过与复原事件。", "用环层数、倒计时或距离出口作为期待锚点。")
    if "长方形" in category:
        return ("矩形边框、网格和条带对齐更容易读；状态变化集中在门/砖块/活塞。", "碰撞法线、活塞周期和门开闭状态要连续，避免穿透和突然跳位。", "首屏用一个明显挡板或目标墙，随后让每次碰撞改变可见状态。")
    if "多边形" in category:
        return ("边数、角点和线宽保持一致，阶段变化只改一个主维度。", "角点反弹和边界变化需要事件时间线；避免碰撞穿透。", "用当前边数或剩余边界作为中段进度，让观众等待下一阶段。")
    if "粒子" in category:
        return ("粒子密度和主对象要分层，爆发不应遮住结果。", "爆发、消散和聚合应由事件触发，并限制数量与持续时间。", "从稀疏对象到密集粒子形成规模反差，标题数字必须兑现。")
    return ("球体大小、颜色、轨迹和背景对比决定层级；主球或吞噬者要突出。", "碰撞、反弹、生成和吞噬用连续轨迹表现，避免长时间无进展。", "首屏先展示一次规则事件，中段通过数量、剩余目标或生存状态维持期待。")


def per_case(row: dict) -> dict:
    visual, motion, hook = visual_notes(row)
    observation = row["design_observation"] or "标题和机制字段提供初步设计线索；需通过完整视频复核。"
    visual = row.get("source_visual_order") or visual
    motion = row.get("source_motion_flow") or motion
    audio = row.get("source_audio_design") or "已确认媒体文件存在；本轮未逐条试听，具体音色、节拍和音画延迟标为待验证。实现时从 collision/spawn/consume/escape/ring_break/result 事件生成短音。"
    hook = row.get("source_hook") or hook
    return {
        "visual_order": visual,
        "motion_flow": motion,
        "audio_design": audio,
        "hook": hook,
        "retention": row.get("source_retention") or "规则→目标→进展→受阻/反转→结果；建议记录最长无进展间隔、首次事件时间和结果时刻。",
        "expectation": row.get("source_expectation") or f"标题/简介提出‘{row['title'][:32]}’，是否在结尾兑现需完整观看或逐帧复核。",
        "implementation": row.get("source_implementation") or "数据层固定随机种子、稳定对象ID和事件时间线；物理层实现碰撞/边界/生成/吞噬或形状状态机；渲染层配置字体、字号、颜色、拖尾和30/60fps；音频层读取事件时间戳。",
        "core_design": row.get("source_core_design") or observation,
        "effective_mechanism": row.get("source_effective_mechanism") or f"{row['mechanism_category']}：可预测规则 + 可见进度 + 事件反馈；需用真实结果验证有效性。",
    }


def main() -> None:
    rows = load_platform("bilibili") + load_platform("douyin")
    enrich_download_status(rows)
    selected = choose([row for row in rows if row["platform"] == "Bilibili"]) + choose([row for row in rows if row["platform"] == "Douyin"])
    for row in selected:
        row.update(per_case(row))
    (ROOT / "cases_50x50.json").write_text(json.dumps(selected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    columns = list(selected[0]) if selected else []
    with (ROOT / "cases_50x50.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=columns)
        writer.writeheader()
        writer.writerows(selected)

    counts = Counter(row["mechanism_category"] for row in selected)
    b_count = sum(row["platform"] == "Bilibili" for row in selected)
    d_count = sum(row["platform"] == "Douyin" for row in selected)
    downloaded = Counter(row["platform"] for row in selected if row["download_status"] == "downloaded_public_research_copy")
    lines = [
        "# 50×50同类型解压物理动画综合分析",
        "",
        f"本报告基于当前证据目录生成：B站选入 {b_count} 条、抖音选入 {d_count} 条，共 {len(selected)} 条。下载状态、标题、指标、页面证据和设计分析均逐条保存于 `cases_50x50.json/csv`。当前实际可识别的本地MP4数量为：B站 {downloaded['Bilibili']}、抖音 {downloaded['Douyin']}；若平台公开媒体接口失败，条目保留失败原因或证据状态，不把失败写成成功。",
        "",
        "抖音50条中有13条保存为本地MP4，37条仅保留公开页面快照/证据；失败或不可用通常来自公开播放器使用blob/MSE、媒体接口未暴露或页面权限限制。本报告没有绕过登录、验证码、签名或权限。",
        "抖音50条均为本轮筛选的几何/物理/解压同类型页面样本；新增候选来自公开搜索并保留页面证据。",
        "",
        "## 口径与限制",
        "",
        "B站播放、点赞等来自公开详情接口的累计快照；抖音播放量通常未公开，不能由点赞估算。页面约数保留原字符串。‘视觉整齐度、流畅度、抓人和留存’是基于可见画面、标题和机制的设计分析，不是平台后台完播或留存证明。声音只有在实际试听后才能下定论；本报告对未逐条试听的作品统一标记为待验证，并给出事件音实现建议。",
        "",
        "## 机制总览",
        "",
    ]
    for category, count in counts.most_common():
        lines.append(f"- **{category}：{count}条**。重点看对象、触发事件、可见进度、受阻原因和结果兑现。")
    lines += [
        "",
        "### 球体机制",
        "",
        "碰撞反弹、增殖/翻倍/分裂、吞噬/消除、逃逸/到达、堆积/溢出、阵营身份和冻结/回溯是主要分支。实现时必须记录稳定球ID、碰撞法线、生成/吞噬/淘汰事件、剩余目标和结果原因。数量变多不等于进展，只有和清空、逃逸或生存条件绑定才形成观看目标。",
        "",
        "### 线条机制",
        "",
        "线条可作为生命线、连接网络、路径、扫线光束或弹性绳。视觉整齐度取决于线宽、端点、交叉层级、节点间距和色彩语义。建议把资源转移、断线、激活、开闭和扫描窗口做成事件，渲染层只解释事件，避免用装饰线冒充状态。",
        "",
        "### 圆环机制",
        "",
        "圆环可以是边界容器、缩小压力、多层突破、旋转缺口、同心图案或脉冲波纹。最有效的观看结构通常是‘剩余层数/倒计时→缺口出现→球接近→成功或复原’，而不是让球长时间在环内随机运动。",
        "",
        "### 长方形、砖块、门与条带",
        "",
        "矩形对象适合承担活塞、挡板、砖块耐久度、滑动门、网格消除和容器平台。直角、间距和对齐让状态更容易识别；每次碰撞应减少真实耐久、改变门状态或产生可见路径变化。",
        "",
        "### 多边形与粒子",
        "",
        "多边形适合边数升级、角点反弹、旋转缺口和形状生存赛；粒子适合爆发、流场、消散、聚合和规模反差。两者都需要限制密度，保证主对象、目标和结果不被装饰遮住。",
        "",
        "## 统一实现方案",
        "",
        "1. **数据层**：固定种子、对象ID、几何参数、状态机、事件时间线、目标、进度、受阻、完成原因和结果时刻。",
        "2. **物理层**：碰撞、边界、重力/阻尼、生成、吞噬、线条资源、环/门/多边形状态；物理步长和渲染帧率分离。",
        "3. **渲染层**：背景、几何对象、颜色语义、线宽、拖尾、标题、计数、结果卡片；字体、字号、文字内容、布局和帧率可配置。",
        "4. **音频层**：从事件总线生成碰撞、生成、吞噬、突破、淘汰、释放和结果短音；支持静音和音量/音色配置。",
        "5. **验收层**：标题与真实结果一致；无穿透；最长无进展区间可解释；结果可见；尾段无球可裁；音画同步和编码通过检查。",
        "",
        "## 逐条分析",
        "",
    ]
    for index, row in enumerate(selected, 1):
        lines.extend([
            f"### {index}. [{row['platform']}] [{row['id']}] {row['title']}",
            "",
            f"- 指标：播放 **{fmt(row['views'])}**；点赞 **{fmt(row['likes_display'])}**；评论 **{fmt(row['comments_display'])}**；收藏 **{fmt(row['favorites_display'])}**；分享 **{fmt(row['shares_display'])}**。发布时间：{row['published_at'] or '未知'}；时长：{fmt(row['duration_seconds'])}秒。",
            f"- 机制分类：**{row['mechanism_category']}**；主要对象：**{row['object_type']}**；账号：{row['uploader']}；[原页面]({row['url']})。",
            f"- 页面证据：{row['evidence_scope']}；证据文件：`{row.get('evidence_file') or '未保存'}`；下载状态：**{row['download_status']}**；媒体：`{row['download_file'] or '无可用媒体文件'}`；抽帧/截图：`{row['frame_file'] or '未保存'}`。",
            "",
            "**核心设计**",
            f"- 核心规则与观看方向：{row['core_design'] or '需完整视频复核；当前只保留标题/页面线索。'}",
            f"- 有效机制：{row['effective_mechanism']}",
            f"- 抓人眼球：{row['hook']}",
            f"- 视觉整齐度与构图：{row['visual_order']}（这是设计审阅意见，不是平台指标。）",
            f"- 运动流畅度：{row['motion_flow']}；完整帧率、掉帧和最长无进展间隔需由媒体逐帧测量。",
            f"- 声音配合：{row['audio_design']}",
            f"- 注意力留存：{row['retention']}",
            f"- 观众期待与结果：{row['expectation']}",
            f"- 实现过程：{row['implementation']}",
            "",
        ])
    lines += [
        "## 发布前验证",
        "",
        "对自制版本逐条测量首个事件时间、事件间最长停滞、目标达成时间、最后可见对象时间、结果时刻、编码帧率、音频事件延迟和标题兑现。每次AB只改一个因素：目标文案、字幕密度、声音存在性、尾段长度、唯一主角或机制参数。平台公开点赞/播放不能替代完播、留存和复看数据。",
        "",
        "## 文件",
        "",
        "- `cases_50x50.json/csv`：统一逐条数据和分析字段。",
        "- `original_videos/`：独立原视频研究副本及下载清单。",
        "- `analysis_framework.md`：评分口径、对象机制词典和逐条模板。",
        "- `bilibili/`、`douyin/`：原始API/页面、截图、抽帧、媒体和失败记录。",
        "",
    ]
    (ROOT / "analysis_50x50.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"生成 {len(selected)} 条报告：B站 {b_count}，抖音 {d_count}；本地下载副本 B站 {downloaded['Bilibili']}，抖音 {downloaded['Douyin']}。")


if __name__ == "__main__":
    main()
