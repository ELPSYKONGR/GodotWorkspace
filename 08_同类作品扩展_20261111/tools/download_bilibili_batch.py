"""Download public Bilibili low-resolution playback streams and save evidence.

This uses the public view and player endpoints with ordinary browser headers. It
does not attempt login, cookies, CAPTCHA, premium access, or a blocked source.
The saved MP4 is the publicly returned playback stream (usually 360p), not a
claim that the platform supplied the creator's master file.
"""

from __future__ import annotations

import datetime as dt
import json
import re
import subprocess
import urllib.error
import urllib.request
from pathlib import Path

import imageio_ffmpeg


BASE = next(p for p in Path("D:/codex/AGI").glob("AI视频三项目评估_*") if p.is_dir())
OUT = BASE / "08_同类作品扩展_20261111" / "bilibili"
VIDEO_DIR = OUT / "videos"
FRAME_DIR = OUT / "frames"
OUT.mkdir(parents=True, exist_ok=True)
VIDEO_DIR.mkdir(exist_ok=True)
FRAME_DIR.mkdir(exist_ok=True)

# New IDs copied from the earlier public Bilibili search snapshot. The six
# existing primary cases are intentionally excluded.
IDS = [
    "BV1VFWzeSEQJ", "BV1a4N1eDE9V", "BV1dW421976v", "BV1uAxLe7E99",
    "BV1VszzYBE7R", "BV13btHerEMN", "BV18nUsYjENb", "BV1D1KF6PEwV",
    "BV18JS9YYEho", "BV1jJD1YsEzi", "BV1MytUeLEQE", "BV1nXndeqExz",
    "BV1NSKGeSERv", "BV1NBAJe8Ero", "BV1tWsbe7EYm", "BV16PopBMEHP",
    "BV1TnFfeeEN9", "BV1Hg9FYyEcR", "BV1vqyAYnE3U", "BV1fQ1HY2E9h",
    "BV1TaSvYkE4K", "BV1pjyGYdEgG", "BV1waAVegEaT", "BV19M4m1y7Zm",
    "BV1s1VRz7EFY", "BV1haNfe9EiU", "BV1Xx411c7cH",
]

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131 Safari/537.36",
    "Accept": "application/json,text/plain,*/*",
}


def get_json(url: str, referer: str) -> dict:
    headers = {**HEADERS, "Referer": referer}
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def download(url: str, target: Path, referer: str) -> None:
    if target.exists() and target.stat().st_size > 10_000:
        return
    request = urllib.request.Request(url, headers={**HEADERS, "Referer": referer})
    with urllib.request.urlopen(request, timeout=90) as response, target.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            output.write(chunk)


def frame_from_video(video: Path, frame: Path, seconds: float) -> None:
    """Extract one middle frame for analysis; failure does not delete video."""
    if frame.exists():
        return
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    command = [ffmpeg, "-y", "-ss", f"{seconds:.3f}", "-i", str(video), "-frames:v", "1", "-q:v", "3", str(frame)]
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def design_note(title: str, description: str) -> tuple[str, str]:
    text = f"{title} {description}".lower()
    if any(k in text for k in ("逃出", "逃离", "逃脱")):
        return "逃逸/生存", "把出口或剩余层数作为目标；可观察的受阻与突破适合形成悬念。"
    if any(k in text for k in ("翻倍", "增加", "爆发", "繁殖", "增多")):
        return "数量增长", "用数量或密度变化制造从少到多的视觉升级；需让增长触发条件真实可见。"
    if any(k in text for k in ("边界", "多边形", "形状", "边", "圆环")):
        return "阶段变形", "重复碰撞触发边界/图形阶段变化；阶段提示让进展易读。"
    if any(k in text for k in ("消灭", "吃", "吞", "砖块")):
        return "消除/吞噬", "把碰撞和清除对象绑定，给单纯运动增加剩余目标与结果。"
    if any(k in text for k in ("冻结", "回溯", "时间")):
        return "时间规则", "用冻结、回溯或计时改变运动预期；时间窗口要在画面中可读。"
    return "几何碰撞", "先确认规则、目标和结果，再把重复运动当作可理解的阶段推进。"


def main() -> None:
    rows = []
    fetched_at = dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()
    for bvid in IDS:
        item = {
            "platform": "Bilibili",
            "bvid": bvid,
            "url": f"https://www.bilibili.com/video/{bvid}/",
            "fetched_at": fetched_at,
            "download_status": "failed",
            "download_file": None,
            "frame_file": None,
        }
        try:
            data = get_json(f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}&jsonp=jsonp", item["url"])
            (OUT / f"{bvid}_api.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            if data.get("code") != 0:
                item["error"] = f"view API code={data.get('code')}: {data.get('message')}"
                rows.append(item)
                continue
            d = data["data"]
            page = d.get("pages", [{}])[0]
            item.update({
                "title": re.sub(r"\s+", " ", d.get("title", "")).strip(),
                "description": d.get("desc", ""),
                "uploader": d.get("owner", {}).get("name", ""),
                "published_at": dt.datetime.fromtimestamp(d.get("pubdate", 0), dt.timezone(dt.timedelta(hours=8))).isoformat(),
                "duration_seconds": d.get("duration"),
                "views": d.get("stat", {}).get("view"),
                "likes": d.get("stat", {}).get("like"),
                "comments": d.get("stat", {}).get("reply"),
                "favorites": d.get("stat", {}).get("favorite"),
                "shares": d.get("stat", {}).get("share"),
                "cid": page.get("cid"),
                "metric_source": f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}&jsonp=jsonp",
            })
            item["mechanism_category"], item["design_hypothesis"] = design_note(item["title"], item["description"])
            # fnval=0 returns a public MP4 durl. Use the lowest offered qn to
            # keep the evidence archive manageable and reproducible.
            play_url = f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={page.get('cid')}&qn=16&fourk=0&platform=html5&fnval=0"
            player = get_json(play_url, item["url"])
            (OUT / f"{bvid}_playurl.json").write_text(json.dumps(player, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            urls = player.get("data", {}).get("durl", []) if player.get("code") == 0 else []
            if not urls:
                raise RuntimeError(f"public player stream unavailable: {player.get('message')}")
            video = VIDEO_DIR / f"{bvid}.mp4"
            # Most qn=16 records are one segment. If segmented, append the
            # returned segments in order; the result remains the public stream.
            with video.open("wb") as output:
                for segment in urls:
                    request = urllib.request.Request(segment["url"], headers={**HEADERS, "Referer": item["url"]})
                    with urllib.request.urlopen(request, timeout=90) as response:
                        while chunk := response.read(1024 * 1024):
                            output.write(chunk)
            item["download_status"] = "downloaded_public_playback_stream"
            item["download_file"] = f"videos/{video.name}"
            # Media duration is available from the public player response.
            milliseconds = player.get("data", {}).get("timelength", 0)
            frame = FRAME_DIR / f"{bvid}.jpg"
            frame_from_video(video, frame, max(0.2, min(float(milliseconds) / 2000 - 0.1, float(milliseconds) / 1000 / 2)))
            if frame.exists():
                item["frame_file"] = f"frames/{frame.name}"
            item["public_stream_note"] = "公开qn=16播放流（通常360p），不是创作者母版声明。"
        except Exception as error:  # preserve failure evidence for review
            item["error"] = f"{type(error).__name__}: {error}"
        rows.append(item)
        print(json.dumps({k: item.get(k) for k in ("bvid", "title", "views", "likes", "download_status", "error")}, ensure_ascii=False))
    (OUT / "cases_additional.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"completed {len(rows)} records; downloaded {sum(x['download_status'].startswith('downloaded') for x in rows)}")


if __name__ == "__main__":
    main()
