"""整理公开抖音详情页快照和已完成的媒体下载。"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IDS = [
    "7704133249187461051", "7704294817710948795", "7704436390604788346",
    "7704445194561393329", "7704675328098129571", "7704781461614983418",
    "7706016277194605307", "7703445198211466937", "7706430031651966309",
    "7703418568550085041",
]


def parse_snapshot(case_id: str) -> dict:
    """Extract visible title, four metric strings, publication time and duration."""
    text = (ROOT / f"{case_id}_snapshot.txt").read_text(encoding="utf-8")
    heading = re.search(r'heading "(.+?)" \[level=1\]', text)
    title = heading.group(1) if heading else ""
    start = heading.start() if heading else 0
    block = text[start : start + 2500]
    values = re.findall(r"- generic: (?:\"([^\"]+)\"|([^\r\n]+))", block)
    metric_values = []
    for a, b in values:
        value = (a or b).strip()
        if re.fullmatch(r"(?:\d+(?:\.\d+)?万|\d+)", value):
            metric_values.append(value)
    published = re.search(r"发布时间：([^\r\n]+)", block)
    duration = re.search(r"- generic: 00:\d{2}\r?\n- generic: /\r?\n- generic: (00:\d{2})", block)
    if not duration:
        duration = re.search(r"- generic: 00:\d{2}\r?\n- generic: /\r?\n- generic: (\d{2}:\d{2})", text)
    metric_names = ["likes", "comments", "favorites", "shares"]
    metrics = {name: (metric_values[i] if i < len(metric_values) else None) for i, name in enumerate(metric_names)}
    title_clean = title.split("#")[0].strip()
    if "逃" in title_clean or "中心" in title_clean or "玻璃" in title_clean:
        design = "逃逸/到达目标类：标题给出路径或目标，适合观察剩余障碍、缺口与最终是否到达。"
    elif "翻" in title_clean or "倍" in title_clean:
        design = "增殖类：标题给出倍数变化，适合观察单次触发、数量增长与密度高潮。"
    elif "堆积" in title_clean or "进化" in title_clean or "集合" in title_clean:
        design = "堆积/进化类：标题给出积累或阶段变化，适合观察空间压力与阶段节点。"
    else:
        design = "几何解压类：仅按公开标题归类；未把未完整观看的结局写成事实。"
    return {
        "platform": "Douyin",
        "id": case_id,
        "title": title,
        "title_clean": title_clean,
        "url": f"https://www.douyin.com/video/{case_id}",
        "uploader": "探索宇宙",
        "published_at": published.group(1).strip() if published else None,
        "duration_display": duration.group(1) if duration else None,
        "views": None,
        "views_status": "公开详情页未展示，未推算",
        "metrics_display": metrics,
        "metrics_are_page_display_values": True,
        "screenshot_file": f"{case_id}.png",
        "page_evidence_file": f"{case_id}_snapshot.txt",
        "download_file": f"{case_id}.mp4" if (ROOT / f"{case_id}.mp4").is_file() else None,
        "download_status": "downloaded" if (ROOT / f"{case_id}.mp4").is_file() else "failed_or_unavailable",
        "download_failure_reason": None if (ROOT / f"{case_id}.mp4").is_file() else "公开页面存在播放器但本次浏览器媒体下载失败；未绕过访问限制或改用登录接口。",
        "design_observation_scope": "根据公开详情页标题、可见页面和保存截图做初步归类；未完整逐帧观看，未试听音轨，不断言完整结尾、完播或因果。",
        "design_observation": design,
    }


def main() -> None:
    cases = [parse_snapshot(case_id) for case_id in IDS]
    (ROOT / "cases_additional.json").write_text(json.dumps(cases, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    downloaded = sum(item["download_status"] == "downloaded" for item in cases)
    lines = [
        "# 抖音扩展样本（公开详情页）",
        "",
        "采集日期：2026-11-11。共10条新增作品，均来自同一公开账号的作品合集/推荐链接，属于方便获取的定向样本，不是抖音全网榜单。页面未公开播放量，未从点赞估算。",
        "",
        f"原视频：正常保存 {downloaded} 条，{len(cases)-downloaded} 条下载失败或页面媒体链接失效。失败条目仍保留页面快照和截图，未绕过登录、验证码、付费或访问限制。",
        "下载失败条目：7704781461614983418、7706430031651966309、7703418568550085041。",
        "",
        "详情页四个数字按页面图标顺序保存为点赞、评论、收藏、分享；带‘万’的值是页面约数。大面积弹幕不当作作者字幕，标题归类也不等于完整观看结论。",
        "",
        "文件：`cases_additional.json` 为结构化记录；`<ID>_snapshot.txt` 为公开DOM；`<ID>.png` 为页面截图；`<ID>.mp4` 为通过公开页面媒体资源正常下载的本地文件。",
    ]
    (ROOT / "notes.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"cases={len(cases)}, downloaded={downloaded}, unavailable={len(cases)-downloaded}")


if __name__ == "__main__":
    main()
