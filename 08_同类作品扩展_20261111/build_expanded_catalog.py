"""Build a reproducible 42-case catalogue and a separate research-video folder."""

from __future__ import annotations

import csv
import json
import re
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent
BASE = PROJECT / "07_同类视频调研_20261111"
BILIBILI = ROOT / "bilibili"
DOUYIN = ROOT / "douyin"
ORIGINALS = ROOT / "original_videos"


def parse_seconds(value: str | int | float | None) -> float | None:
    """Parse a page display duration such as 01:05 without inventing precision."""
    if value is None or isinstance(value, (int, float)):
        return float(value) if value is not None else None
    match = re.fullmatch(r"(?:(\d+):)?(\d+)", str(value).strip())
    if not match:
        return None
    return int(match.group(1) or 0) * 60 + int(match.group(2))


def load_cases() -> list[dict]:
    """Normalize existing and expanded evidence records into one list."""
    existing = json.loads((BASE / "cases.json").read_text(encoding="utf-8"))
    expanded_b = json.loads((BILIBILI / "cases_additional.json").read_text(encoding="utf-8"))
    expanded_d = json.loads((DOUYIN / "cases_additional.json").read_text(encoding="utf-8"))
    rows: list[dict] = []
    for item in existing:
        item = dict(item)
        item["source_group"] = "previously_verified"
        item["download_status"] = "previous_reference_or_evidence"
        item["download_file"] = None
        rows.append(item)
    for item in expanded_b:
        # This is a black-screen interactive danmaku test, not a physical/geometry
        # relaxation animation. Keep its raw evidence in place but exclude it from
        # the same-type catalogue and counts.
        if item["bvid"] == "BV1Xx411c7cH":
            continue
        item = dict(item)
        item["id"] = item["bvid"]
        item["source_group"] = "expanded_public_bilibili"
        rows.append(item)
    for item in expanded_d:
        item = dict(item)
        item["source_group"] = "expanded_public_douyin"
        rows.append(item)
    # A stable order makes the CSV, report and later refreshes diffable.
    return sorted(rows, key=lambda x: (x.get("platform", ""), -(x.get("views") or 0), x.get("id", x.get("bvid", ""))))


def normalized(item: dict) -> dict:
    """Flatten a source record while preserving display metrics and caveats."""
    platform = item.get("platform", "")
    identifier = item.get("id") or item.get("bvid")
    display = item.get("metrics_display", {})
    likes_display = display.get("likes", item.get("likes"))
    views = item.get("views")
    if platform == "Douyin":
        duration = parse_seconds(item.get("duration_display"))
        category = item.get("design_observation", "")
        metric_source = "公开抖音详情页；播放量未展示"
        likes_approximate = isinstance(likes_display, str) and likes_display.endswith("万")
        likes = item.get("likes")
        comments = item.get("comments")
        favorites = item.get("favorites")
        shares = item.get("shares")
    else:
        duration = item.get("duration_seconds") or item.get("duration_seconds_api")
        category = item.get("mechanism_category") or item.get("observation", {}).get("mechanism", "")
        metric_source = item.get("metric_source", "B站公开详情 API")
        likes = item.get("likes")
        comments = item.get("comments")
        favorites = item.get("favorites")
        shares = item.get("shares")
        likes_approximate = False
    title = item.get("title") or item.get("title_clean") or ""
    all_text = f"{title} {item.get('description', '')} {item.get('observation', {}).get('mechanism', '')}"
    category = item.get("mechanism_category")
    if not category:
        # Existing 11 records predate the category field. Keep this intentionally
        # coarse: it is an editorial grouping for comparison, not a claim about
        # the creator's implementation.
        if any(token in all_text for token in ("线条", "资源")):
            category = "资源争夺"
        elif any(token in all_text for token in ("吞噬", "爆发", "翻倍", "增殖", "粒子", "小球相撞")):
            category = "数量增长/吞噬"
        elif any(token in all_text for token in ("逃", "圆环", "击破", "缩小")):
            category = "逃逸/生存"
        elif any(token in all_text for token in ("反弹", "边界", "图形")):
            category = "阶段变形"
        elif any(token in all_text for token in ("胜利", "谁能", "队")):
            category = "阵营竞争"
        elif any(token in all_text for token in ("视力", "游戏化", "训练")):
            category = "追踪任务"
        elif any(token in all_text for token in ("溢出", "堆积", "释放")):
            category = "堆积/释放"
        else:
            category = "目标挑战"
    url = item.get("url") or f"https://www.{platform.lower()}.com/video/{identifier}"
    return {
        "platform": platform,
        "id": identifier,
        "title": title,
        "uploader": item.get("uploader"),
        "published_at": item.get("published_at"),
        "duration_seconds": duration,
        "views": views,
        "likes": likes,
        "likes_display": likes_display,
        "likes_approximate": likes_approximate,
        "comments": comments,
        "comments_display": display.get("comments", comments),
        "favorites": favorites,
        "favorites_display": display.get("favorites", favorites),
        "shares": shares,
        "shares_display": display.get("shares", shares),
        "like_view_ratio_percent": item.get("like_view_ratio_percent"),
        "mechanism_category": category,
        "design_observation": item.get("design_observation") or item.get("design_hypothesis") or item.get("observation", {}).get("hypothesis", ""),
        "description": item.get("description", ""),
        "url": url,
        "metric_source": metric_source,
        "source_group": item.get("source_group"),
        "download_status": item.get("download_status"),
        "download_file": item.get("download_file"),
        "frame_file": item.get("frame_file") or item.get("screenshot_file"),
        "evidence_scope": item.get("watch_scope") or item.get("design_observation_scope") or "公开页面抽看；未据此声称完整观看、音效或因果。",
        "public_stream_note": item.get("public_stream_note"),
    }


def copy_originals(rows: list[dict]) -> list[dict]:
    """Copy fetched media into one separate folder and record each disposition."""
    records = []
    (ORIGINALS / "bilibili").mkdir(parents=True, exist_ok=True)
    (ORIGINALS / "douyin").mkdir(parents=True, exist_ok=True)
    for row in rows:
        identifier = row["id"]
        if row["platform"] == "Bilibili":
            source = BILIBILI / "videos" / f"{identifier}.mp4"
            if not source.is_file():
                # The download utility has one tested item under its own layout.
                source = ORIGINALS / "bilibili" / identifier / f"{identifier}.mp4"
            folder = ORIGINALS / "bilibili" / identifier
        else:
            source = DOUYIN / f"{identifier}.mp4"
            # The three originally requested public works were archived before
            # this expansion folder was created. Include the two MP4s here too.
            legacy = {
                "7706445540791209254": PROJECT / "01_参考视频" / "02_7706445540791209254" / "reference.mp4",
                "7705831565992955145": PROJECT / "01_参考视频" / "03_7705831565992955145" / "reference.mp4",
            }
            if not source.is_file() and identifier in legacy:
                source = legacy[identifier]
            folder = ORIGINALS / "douyin" / identifier
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / f"{identifier}.mp4"
        status = row.get("download_status") or "not_requested"
        if source.is_file():
            if source.resolve() != target.resolve():
                shutil.copy2(source, target)
            status = "downloaded_copy_for_research"
            bytes_size = target.stat().st_size
        else:
            bytes_size = None
            if status == "downloaded_public_playback_stream":
                status = "download_manifest_says_downloaded_source_missing"
        records.append({"platform": row["platform"], "id": identifier, "url": row["url"],
                        "status": status, "source_path": str(source) if source.exists() else None,
                        "relative_path": str(target.relative_to(ROOT)) if target.exists() else None,
                        "bytes": bytes_size,
                        "rights_note": "仅供内部研究与设计分析；下载的公开播放流不等于创作者母版或再发布许可。"})
    (ORIGINALS / "download_manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return records


def write_catalog(rows: list[dict]) -> None:
    """Write JSON/CSV with exactly the same normalized rows."""
    normalized_rows = [normalized(row) for row in rows]
    (ROOT / "cases_merged.json").write_text(json.dumps(normalized_rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    columns = list(normalized_rows[0])
    with (ROOT / "cases_merged.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=columns)
        writer.writeheader()
        writer.writerows(normalized_rows)


def contact_sheet(rows: list[dict]) -> None:
    """Make a compact visual index from saved evidence frames, not a video claim."""
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    bold_path = Path("C:/Windows/Fonts/msyhbd.ttc")
    regular = ImageFont.truetype(str(font_path), 20)
    bold = ImageFont.truetype(str(bold_path), 22)
    cards = []
    for row in rows:
        if row["platform"] == "Bilibili":
            path = BILIBILI / "frames" / f"{row['id']}.jpg"
        else:
            path = DOUYIN / f"{row['id']}.png"
        if path.is_file():
            cards.append((row, path))
    width, card_w, card_h, gap = 1800, 340, 285, 16
    columns = 5
    height = 90 + ((len(cards) + columns - 1) // columns) * (card_h + gap)
    canvas = Image.new("RGB", (width, height), "#0b1220")
    draw = ImageDraw.Draw(canvas)
    draw.text((28, 20), f"同类物理/几何解压动画证据索引：{len(rows)}条案例，{len(cards)}张抽帧", font=bold, fill="#f2f5fa")
    draw.text((30, 52), "截图仅作画面证据；B站指标为API累计快照，抖音播放未公开。", font=regular, fill="#a8b8ce")
    for index, (row, path) in enumerate(cards):
        x = 20 + (index % columns) * (card_w + gap)
        y = 90 + (index // columns) * (card_h + gap)
        draw.rounded_rectangle((x, y, x + card_w, y + card_h), radius=10, fill="#172337", outline="#344a67")
        with Image.open(path) as image:
            fitted = ImageOps.contain(image.convert("RGB"), (card_w - 20, 190), Image.Resampling.LANCZOS)
            canvas.paste(fitted, (x + (card_w - fitted.width) // 2, y + 8))
        title = str(row["title"] or "")[:19]
        metric = f"{row['platform']} {row['views'] or '播放未公开'} / {row['likes_display']}赞"
        draw.text((x + 10, y + 204), title, font=regular, fill="#edf3fc")
        draw.text((x + 10, y + 232), metric, font=regular, fill="#f1c97c")
        draw.text((x + 10, y + 258), row["id"], font=ImageFont.truetype(str(font_path), 16), fill="#9eb2cb")
    canvas.save(ROOT / "案例抽帧总览.png")


def main() -> None:
    rows = load_cases()
    write_catalog(rows)
    copied = copy_originals(rows)
    contact_sheet([normalized(row) for row in rows])
    downloaded = sum(1 for item in copied if item["status"] == "downloaded_copy_for_research")
    print(f"案例 {len(rows)} 条；独立原视频目录实际复制 {downloaded} 条；索引抽帧 {sum(1 for x in rows if x.get('frame_file'))} 条。")


if __name__ == "__main__":
    main()
