# -*- coding: utf-8 -*-
"""
audio_spectra.py —— 生成代表样本的频谱图（ffmpeg showspectrumpic）+ 波形，拼成对照图

为什么这么干：我听不到声音，但频谱图能读出四件事——
  1) 有没有持续的低频铺底（BGM 的 bass）
  2) 高频是否有规律脉冲（滴答/硬币/玻璃类音效）
  3) 声谱是不是宽带瞬态（爆炸/碰撞的低频冲击）
  4) 是否有人声段（200-1000Hz 的谐波条纹）
"""
import os
import subprocess
import sys

import imageio_ffmpeg
from PIL import Image, ImageDraw

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

FF = imageio_ffmpeg.get_ffmpeg_exe()
ROOT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\original_videos"
OUT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\_analysis\spectra"

SAMPLES = [
    ("douyin", r"douyin\7454633814921448761.mp4", "穿环逃出(38万赞)"),
    ("douyin", r"douyin\7701554015183905979.mp4", "表情包合并"),
    ("douyin", r"douyin\7684444900621264485.mp4", "扇区争夺"),
    ("bilibili", r"bilibili\BV16PopBMEHP\BV16PopBMEHP.mp4", "活塞翻倍"),
    ("bilibili", r"bilibili\BV19YZ5BuEPS\BV19YZ5BuEPS.mp4", "石头剪刀布"),
    ("bilibili", r"bilibili\BV1iME1zJESv\BV1iME1zJESv.mp4", "1945道环"),
]

W, H = 760, 260


def run(src, dst):
    cmd = [FF, "-y", "-v", "error", "-i", src,
           "-lavfi", f"showspectrumpic=s={W}x{H}:legend=0:scale=log:color=intensity",
           "-frames:v", "1", dst]
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if p.returncode != 0 or not os.path.exists(dst):
        return False, (p.stderr or "")[-200:]
    return True, ""


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for src_tag, rel, label in SAMPLES:
        src = os.path.join(ROOT, rel)
        vid = os.path.splitext(os.path.basename(rel))[0]
        dst = os.path.join(OUT, f"{src_tag}__{vid}.png")
        if not os.path.exists(src):
            print(f"[skip] 缺文件 {rel}")
            continue
        ok, err = run(src, dst)
        print(f"[{'ok' if ok else 'FAIL'}] {vid} {err if not ok else ''}")
        if ok:
            made.append((dst, f"{label} / {src_tag}"))

    if not made:
        sys.exit("没有生成任何频谱图")

    # 拼成 2 列 × N 行的对照图
    cols = 2
    rows = (len(made) + cols - 1) // cols
    pad, bar = 10, 26
    sheet = Image.new("RGB", (cols * W + pad * (cols + 1),
                              rows * (H + bar) + pad * (rows + 1)), (14, 15, 17))
    d = ImageDraw.Draw(sheet)
    for i, (p, label) in enumerate(made):
        im = Image.open(p).convert("RGB")
        x = pad + (i % cols) * (W + pad)
        y = pad + (i // cols) * (H + bar + pad)
        d.text((x, y), label, fill=(235, 235, 235))
        sheet.paste(im, (x, y + bar))
    out = os.path.join(OUT, "_compare.jpg")
    sheet.save(out, quality=90)
    print(f"[done] {len(made)} 张 -> {out}")


if __name__ == "__main__":
    main()
