"""Download only the three requested public Douyin works; no browser credentials."""
from pathlib import Path
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from yt_dlp import YoutubeDL
import imageio_ffmpeg

sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
IDS = ["7705989678591395978", "7706445540791209254", "7705831565992955145"]


def download(item):
    number, video_id = item
    folder = ROOT / "01_参考视频" / f"{number:02d}_{video_id}"
    folder.mkdir(parents=True, exist_ok=True)
    result = {"id": video_id, "assumed_project_order": number,
              "original_url": f"https://www.douyin.com/user/self?from_tab_name=main&modal_id={video_id}&showTab=record",
              "public_url": f"https://www.douyin.com/video/{video_id}",
              "checked_date": "2026-11-11", "status": "pending"}
    try:
        options = {"outtmpl": str(folder / "reference.%(ext)s"),
                   "ffmpeg_location": imageio_ffmpeg.get_ffmpeg_exe(),
                   "noplaylist": True, "quiet": True, "socket_timeout": 25,
                   "retries": 1, "fragment_retries": 1,
                   "writesubtitles": True, "writeautomaticsub": True,
                   "subtitleslangs": ["all"], "merge_output_format": "mp4"}
        with YoutubeDL(options) as ydl:
            info = ydl.extract_info(result["public_url"], download=True)
        result.update({k: info.get(k) for k in ["title", "description", "uploader", "duration", "upload_date", "view_count", "like_count"]})
        result["status"] = "downloaded"
    except Exception as exc:
        result.update(status="blocked", error=str(exc))
    result["files"] = [{"name": p.name, "bytes": p.stat().st_size} for p in folder.iterdir() if p.is_file()]
    (folder / "extractor_attempt.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    return result


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(download, enumerate(IDS, 1)))
    (ROOT / "01_参考视频" / "downloader_attempt.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))
