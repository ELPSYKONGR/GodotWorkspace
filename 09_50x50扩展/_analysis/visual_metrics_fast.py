# -*- coding: utf-8 -*-
"""
visual_metrics_fast.py —— 同上的指标，但把「解码 + 缩放」交给 ffmpeg（SIMD 加速），
Python 只用 numpy 处理已经缩到 96x170、10fps 的 rawvideo 流。

PyAV 逐帧 to_image()+resize+HSV 的写法在 107 个 1080p 视频上要跑半小时；
换成 ffmpeg 管道后约 5 分钟。
"""
import json
import os
import subprocess
import sys

import imageio_ffmpeg
import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

FF = imageio_ffmpeg.get_ffmpeg_exe()
ROOT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\original_videos"
OUT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\_analysis\visual_metrics.json"
W, H, FPS = 96, 170, 10
FRAME = W * H * 3


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


def decode_small(path):
    """返回 (n, H, W, 3) uint8 数组；失败返回 None。"""
    cmd = [FF, "-v", "error", "-i", path,
           "-vf", f"fps={FPS},scale={W}:{H}", "-f", "rawvideo",
           "-pix_fmt", "rgb24", "-"]
    p = subprocess.run(cmd, capture_output=True)
    if p.returncode != 0 or len(p.stdout) < FRAME * 4:
        return None
    n = len(p.stdout) // FRAME
    return np.frombuffer(p.stdout[: n * FRAME], dtype=np.uint8).reshape(n, H, W, 3)


def analyze(path):
    a = decode_small(path)
    if a is None:
        return {"error": "解码失败或过短"}
    n = a.shape[0]
    f = a.astype(np.float32)

    gray = f.mean(axis=3)                       # (n,H,W)
    brightness = float(gray.mean())

    mx = f.max(axis=3)
    mn = f.min(axis=3)
    diff = mx - mn
    sat = np.where(mx > 1, diff / np.maximum(mx, 1), 0)
    saturation = float(sat.mean())

    # 显眼彩色像素（饱和度 >0.35 且不太暗）——用来看调色板宽度和主色相
    mask = (sat > 0.35) & (mx > 40)
    colored_ratio = float(mask.mean())
    r, g, b = f[..., 0], f[..., 1], f[..., 2]
    with np.errstate(divide="ignore", invalid="ignore"):
        h1 = (60 * ((g - b) / np.maximum(diff, 1e-6)) + 360) % 360
        h2 = (60 * ((b - r) / np.maximum(diff, 1e-6)) + 120) % 360
        h3 = (60 * ((r - g) / np.maximum(diff, 1e-6)) + 240) % 360
    hue = np.where(mx == r, h1, np.where(mx == g, h2, h3))
    if mask.sum() > 100:
        hist, _ = np.histogram(hue[mask], bins=12, range=(0, 360))
        hue_hist = (hist / hist.sum()).round(3).tolist()
        dom_hue = int(np.argmax(hist) * 30 + 15)
    else:
        hue_hist, dom_hue = [0.0] * 12, -1

    # 帧间差异（运动强度曲线）
    diffs = np.abs(np.diff(gray, axis=0)).mean(axis=(1, 2))
    motion_mean = float(diffs.mean())
    motion_std = float(diffs.std())
    shot_changes = int((diffs > 18).sum())     # 灰度 MAE>18 视为镜头突变
    static_ratio = float((diffs < 0.6).mean())

    # 边缘密度：几何体越多线条越密
    gx = np.abs(np.diff(gray, axis=2)).mean()
    gy = np.abs(np.diff(gray, axis=1)).mean()
    edge = float(gx + gy)

    # 中心 50% vs 外框的梯度比：判断主体是否居中
    cy0, cy1, cx0, cx1 = H // 4, H * 3 // 4, W // 4, W * 3 // 4
    gc = gray[:, cy0:cy1, cx0:cx1]
    ce = float(np.abs(np.diff(gc, axis=2)).mean() + np.abs(np.diff(gc, axis=1)).mean())
    center_weight = round(ce / (edge + 1e-6), 3)

    dark_ratio = float((gray < 40).mean())

    return {
        "frames": int(n),
        "brightness": round(brightness, 1),
        "saturation": round(saturation, 3),
        "colored_ratio": round(colored_ratio, 3),
        "dominant_hue_deg": dom_hue,
        "hue_hist": hue_hist,
        "edge_density": round(edge, 2),
        "bg_dark_ratio": round(dark_ratio, 3),
        "center_weight": center_weight,
        "motion_mean": round(motion_mean, 3),
        "motion_std": round(motion_std, 3),
        "motion_p95": round(float(np.percentile(diffs, 95)), 3),
        "shot_changes": shot_changes,
        "static_ratio": round(static_ratio, 3),
        "motion_profile": [round(float(v), 2) for v in
                           diffs[:: max(1, diffs.size // 40)][:40]],
    }


def main():
    vids = find_videos()
    print(f"[visual-fast] {len(vids)} 个视频")
    out = []
    for i, (p, src, vid) in enumerate(vids, 1):
        try:
            m = analyze(p)
        except Exception as e:
            m = {"error": f"{type(e).__name__}: {e}"[:160]}
        m.update({"source": src, "vid": vid})
        out.append(m)
        print(f"[{i}/{len(vids)}] {vid[:14]:<14} bright={m.get('brightness')} "
              f"dark={m.get('bg_dark_ratio')} mot={m.get('motion_mean')} "
              f"shots={m.get('shot_changes')}", flush=True)

    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"[done] {sum(1 for r in out if 'error' not in r)}/{len(out)} -> {OUT}")


if __name__ == "__main__":
    main()
