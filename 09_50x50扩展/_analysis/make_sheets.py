# -*- coding: utf-8 -*-
"""
make_sheets.py —— 为每个视频生成 contact sheet（3x3 均匀抽帧 + 时间戳 + 首尾差异）

为什么 3x3 而不是更多：抖音这类视频 20-70 秒，9 帧足以看清「场景 / 物体 / 规则 / 结尾」四件事，
再多会把一张图撑到看不清单帧细节。

输出：_analysis/sheets/<source>__<vid>.jpg
"""
import os
import sys

import av
import numpy as np
from PIL import Image, ImageDraw

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\original_videos"
OUTDIR = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\_analysis\sheets"
COLS, ROWS = 3, 3
TW, TH = 240, 426          # 单格目标尺寸（9:16）


def find_videos():
    out = []
    for dirpath, _, files in os.walk(ROOT):
        for fn in files:
            if fn.lower().endswith(".mp4"):
                p = os.path.join(dirpath, fn)
                rel = os.path.relpath(p, ROOT).replace("\\", "/")
                src = "bilibili" if rel.startswith("bilibili/") else "douyin"
                out.append((p, src, os.path.splitext(fn)[0]))
    return sorted(out)


def grab(path, n=COLS * ROWS):
    """按时间均匀抽 n 帧，返回 [(PIL.Image, t_seconds)]。"""
    container = av.open(path, metadata_errors="ignore")
    try:
        st = container.streams.video[0]
        dur = float(container.duration / av.time_base) if container.duration else 0.0
        if not dur:
            dur = float(st.duration * st.time_base) if st.duration else 10.0
        # 跳过片头 2%、停在 96%，避开黑场与结尾留白
        lo, hi = dur * 0.02, dur * 0.96
        targets = [lo + (hi - lo) * i / (n - 1) for i in range(n)]

        got = []
        ti = 0
        st.thread_type = "AUTO"
        for frame in container.decode(st):
            t = float(frame.pts * st.time_base) if frame.pts is not None else 0.0
            while ti < n and t >= targets[ti]:
                img = frame.to_image().resize((TW, TH), Image.LANCZOS)
                got.append((img, t))
                ti += 1
            if ti >= n:
                break
        while len(got) < n and got:      # 帧数不足时用最后一帧补齐
            got.append((got[-1][0], got[-1][1]))
        return got, dur
    finally:
        container.close()


def build(path, src, vid, outdir):
    frames, dur = grab(path)
    if not frames:
        return None
    W, H = COLS * TW, ROWS * TH + 22
    sheet = Image.new("RGB", (W, H), (16, 17, 19))
    d = ImageDraw.Draw(sheet)
    for i, (img, t) in enumerate(frames[: COLS * ROWS]):
        x, y = (i % COLS) * TW, (i // COLS) * TH
        sheet.paste(img, (x, y))
        d.text((x + 6, y + 6), f"{t:.1f}s", fill=(255, 235, 120))
    d.text((6, ROWS * TH + 5), f"{src} / {vid}  dur={dur:.1f}s", fill=(200, 200, 200))
    out = os.path.join(outdir, f"{src}__{vid}.jpg")
    sheet.save(out, quality=88)
    return out


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    vids = find_videos()
    print(f"[sheets] {len(vids)} 个视频")
    for i, (p, src, vid) in enumerate(vids, 1):
        try:
            out = build(p, src, vid, OUTDIR)
            print(f"[{i}/{len(vids)}] {os.path.basename(out or 'skip')}", flush=True)
        except Exception as e:
            print(f"[{i}/{len(vids)}] FAIL {vid} {type(e).__name__}: {e}", flush=True)
    print("[done]")


if __name__ == "__main__":
    main()
