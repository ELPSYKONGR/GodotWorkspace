"""Download publicly exposed Bilibili DASH media for research evidence.

This uses the platform's public view and playurl APIs only. It refuses entries
whose view API does not expose ``rights.download == 1`` and records every
attempt in a manifest. It does not use cookies, login, CAPTCHA bypasses, or
third-party mirrors.

Example:
    py tools/download_bilibili_public.py --ids-file bvids.txt
    py tools/download_bilibili_public.py BVxxxxxxxxx --max-height 480
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "original_videos" / "bilibili"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131 Safari/537.36"


def now() -> str:
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()


def get_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://www.bilibili.com/"})
    with urllib.request.urlopen(request, timeout=25) as response:
        return json.load(response)


def download(urls: list[str], path: Path) -> int:
    """Download the first working signed URL, returning bytes written."""
    last_error: Exception | None = None
    for url in urls:
        try:
            request = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://www.bilibili.com/"})
            with urllib.request.urlopen(request, timeout=40) as response, path.open("wb") as output:
                size = 0
                while True:
                    block = response.read(1024 * 1024)
                    if not block:
                        break
                    output.write(block)
                    size += len(block)
            return size
        except (OSError, urllib.error.URLError) as error:
            last_error = error
            if path.exists():
                path.unlink()
    raise RuntimeError(f"all signed media URLs failed: {last_error}")


def ffmpeg_path() -> str | None:
    found = shutil.which("ffmpeg")
    if found:
        return found
    try:
        import imageio_ffmpeg  # type: ignore

        return imageio_ffmpeg.get_ffmpeg_exe()
    except Exception:
        return None


def choose(streams: list[dict], max_height: int, *, video: bool) -> dict:
    # DASH returns the same metadata keys for audio and video; audio has a
    # zero height/width, so presence of ``height`` alone is insufficient.
    is_video = lambda stream: int(stream.get("height", 0) or 0) > 0
    usable = [x for x in streams if video == is_video(x) and (not video or int(x.get("height", 0)) <= max_height)]
    if not usable:
        usable = [x for x in streams if video == is_video(x)]
    if not usable:
        raise RuntimeError("playurl returned no usable media stream")
    return sorted(usable, key=lambda x: (int(x.get("height", 0)), int(x.get("bandwidth", 0))))[-1]


def urls(stream: dict) -> list[str]:
    return [stream.get("baseUrl") or stream.get("base_url"), *(stream.get("backupUrl") or stream.get("backup_url") or [])]


def fetch_one(bvid: str, max_height: int) -> dict:
    record: dict = {"bvid": bvid, "public_url": f"https://www.bilibili.com/video/{bvid}/", "checked_at": now()}
    work = OUT / bvid
    work.mkdir(parents=True, exist_ok=True)
    try:
        view_url = "https://api.bilibili.com/x/web-interface/view?" + urllib.parse.urlencode({"bvid": bvid})
        view = get_json(view_url)
        record["view_api"] = view_url
        if view.get("code") != 0:
            raise RuntimeError(f"view API code={view.get('code')}: {view.get('message')}")
        data = view["data"]
        record.update({"title": data.get("title"), "uploader": (data.get("owner") or {}).get("name"),
                       "duration_seconds": data.get("duration"), "views": (data.get("stat") or {}).get("view"),
                       "likes": (data.get("stat") or {}).get("like"), "rights": data.get("rights")})
        if (data.get("rights") or {}).get("download") != 1:
            record.update(status="blocked_rights", reason="view API rights.download is not 1")
            return record
        page = (data.get("pages") or [{}])[0]
        cid = page.get("cid")
        if not cid:
            raise RuntimeError("view API has no page cid")
        query = urllib.parse.urlencode({"bvid": bvid, "cid": cid, "fnval": 16, "fnver": 0, "fourk": 1})
        playurl = "https://api.bilibili.com/x/player/playurl?" + query
        response = get_json(playurl)
        record["playurl_api"] = playurl
        if response.get("code") != 0:
            raise RuntimeError(f"playurl API code={response.get('code')}: {response.get('message')}")
        dash = (response.get("data") or {}).get("dash") or {}
        video = choose(dash.get("video") or [], max_height, video=True)
        audio = choose(dash.get("audio") or [], max_height, video=False)
        record["selected_streams"] = {"video_id": video.get("id"), "video_height": video.get("height"),
                                       "video_bandwidth": video.get("bandwidth"), "audio_id": audio.get("id"),
                                       "audio_bandwidth": audio.get("bandwidth")}
        with tempfile.TemporaryDirectory(prefix=f"{bvid}_", dir=OUT) as temporary:
            temporary_path = Path(temporary)
            video_path = temporary_path / "video.m4s"
            audio_path = temporary_path / "audio.m4s"
            record["video_bytes"] = download(urls(video), video_path)
            record["audio_bytes"] = download(urls(audio), audio_path)
            ffmpeg = ffmpeg_path()
            final = work / f"{bvid}.mp4"
            if ffmpeg:
                command = [ffmpeg, "-y", "-loglevel", "error", "-i", str(video_path), "-i", str(audio_path),
                           "-c", "copy", "-movflags", "+faststart", str(final)]
                completed = subprocess.run(command, capture_output=True, text=True, timeout=120)
                if completed.returncode != 0:
                    record["merge_error"] = completed.stderr[-1000:]
                    shutil.copyfile(video_path, work / f"{bvid}.video.m4s")
                    shutil.copyfile(audio_path, work / f"{bvid}.audio.m4s")
                    record["media_files"] = [f"{bvid}.video.m4s", f"{bvid}.audio.m4s"]
                else:
                    record["media_files"] = [final.name]
            else:
                shutil.copyfile(video_path, work / f"{bvid}.video.m4s")
                shutil.copyfile(audio_path, work / f"{bvid}.audio.m4s")
                record["media_files"] = [f"{bvid}.video.m4s", f"{bvid}.audio.m4s"]
        record["status"] = "downloaded"
        return record
    except Exception as error:  # record failure per item so a batch continues
        record.update(status="failed", error=str(error))
        return record
    finally:
        (work / "manifest.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bvid", nargs="*", help="one or more public BVIDs")
    parser.add_argument("--ids-file", type=Path, help="UTF-8 text file, one BVID per line")
    parser.add_argument("--max-height", type=int, default=720, help="maximum selected video height (default 720)")
    args = parser.parse_args()
    ids = list(args.bvid)
    if args.ids_file:
        ids.extend(line.strip() for line in args.ids_file.read_text(encoding="utf-8").splitlines()
                   if line.strip() and not line.lstrip().startswith("#"))
    ids = list(dict.fromkeys(ids))
    if not ids:
        parser.error("provide BVIDs or --ids-file")
    OUT.mkdir(parents=True, exist_ok=True)
    results = [fetch_one(bvid, args.max_height) for bvid in ids]
    manifest = OUT / "download_manifest.json"
    previous = []
    if manifest.exists():
        try:
            previous = json.loads(manifest.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            previous = []
    by_id = {x.get("bvid"): x for x in previous if x.get("bvid")}
    by_id.update({x["bvid"]: x for x in results})
    manifest.write_text(json.dumps(list(by_id.values()), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0 if all(x.get("status") == "downloaded" for x in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
