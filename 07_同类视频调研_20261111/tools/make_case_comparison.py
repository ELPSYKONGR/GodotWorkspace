"""Build a six-case research figure from unchanged, previously saved screenshots."""
from __future__ import annotations

import json
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
FONT = Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts/msyh.ttc"
BOLD = FONT.with_name("msyhbd.ttc")
CASES = json.loads((ROOT / "bilibili/cases.json").read_text(encoding="utf-8"))
BY_ID = {case["bvid"]: case for case in CASES}
CARDS = [
    ("BV1THU3YuEJA", "失去所有线条的小球被淘汰", "线条是资源 · 阵营可识别", (324, 258, 553, 510)),
    ("BV192LazNEHW", "小球每次碰撞都会翻倍", "增长与吞噬 · 双向竞争", (320, 256, 558, 472)),
    ("BV1Rw411G73J", "每5次反弹，边界变换图形", "碰撞计数 · 阶段升级", (303, 230, 573, 570)),
    ("BV1ZPm8YBE3u", "连续击破圆环才有机会逃出", "一层一目标 · 复原时间窗", (324, 196, 553, 515)),
    ("7454633814921448761", "球能逃脱所有缩小的圆圈吗？", "收缩压力 · 逃逸缺口", (432, 184, 692, 535)),
    ("7547536054669299004", "游戏化视力训练（作品标题）", "单目标追踪 · 观众参与", (432, 111, 692, 535)),
]


def font(size: int, bold: bool = False):
    """Read installed Chinese fonts without copying or modifying font files."""
    return ImageFont.truetype(str(BOLD if bold else FONT), size)


def lines(draw, text: str, xy: tuple[int, int], size: int, width: int, fill: str, bold=False):
    """Wrap by measured glyph width, returning the next available baseline."""
    face = font(size, bold)
    x, y = xy
    current = ""
    for char in text:
        if char == "\n" or draw.textlength(current + char, font=face) > width:
            draw.text((x, y), current, font=face, fill=fill)
            current = "" if char == "\n" else char
            y += size + 10
        else:
            current += char
    if current:
        draw.text((x, y), current, font=face, fill=fill)
        y += size + 10
    return y


def main():
    """Crop only the report copies, add verified metrics, and export the figure."""
    canvas = Image.new("RGB", (1800, 1640), "#0d1524")
    draw = ImageDraw.Draw(canvas)
    draw.text((40, 25), "物理解压动画：6个实际案例", font=font(44, True), fill="#eef4ff")
    draw.text((42, 88), "观察规则、进度与目标；公开数据为抓取时累计表现", font=font(25), fill="#a9bad2")
    for index, (case_id, title, keywords, crop) in enumerate(CARDS):
        x = 36 + (index % 3) * 582
        y = 148 + (index // 3) * 668
        draw.rounded_rectangle((x, y, x + 562, y + 642), radius=18, fill="#172338", outline="#344764", width=2)
        platform = "B站" if index < 4 else "抖音"
        draw.text((x + 22, y + 18), f"{index + 1:02d}  {platform}", font=font(20, True), fill="#83d9cb")
        end_y = lines(draw, title, (x + 22, y + 53), 27, 518, "#f3f6fb", True)
        if end_y > y + 102:
            raise ValueError(f"Title too tall: {title}")
        if index < 4:
            record = BY_ID[case_id]
            metric = f"{record['views'] / 10000:.2f}万播放  ·  {record['likes'] / 10000:.2f}万赞"
            source = f"{record['uploader']} · {case_id}"
            note = "数据：B站公开API；画面：已存中途截图"
            path = ROOT / "bilibili" / f"{case_id}_frame.png"
        else:
            metric = ("38.0万" if index == 4 else "47.0万") + "赞  ·  播放量未公开"
            source = f"探索宇宙 · 抖音 {case_id}"
            note = "点赞为页面约数；画内文字不作参数核验"
            path = ROOT / "douyin" / f"{case_id}_additional.png"
        draw.text((x + 22, y + 102), metric, font=font(24, True), fill="#f0ca85")
        draw.rounded_rectangle((x + 22, y + 146, x + 540, y + 510), radius=10, fill="#05090f")
        with Image.open(path) as original:
            clipped = original.convert("RGB").crop(crop)
            fitted = ImageOps.contain(clipped, (506, 352), Image.Resampling.LANCZOS)
            canvas.paste(fitted, (x + 22 + (518 - fitted.width) // 2, y + 146 + (364 - fitted.height) // 2))
        lines(draw, keywords, (x + 22, y + 525), 27, 518, "#e4ecf8", True)
        draw.text((x + 22, y + 573), source, font=font(18), fill="#b3c2d8")
        lines(draw, note, (x + 22, y + 602), 17, 518, "#8eabc7")
    draw.text((40, 1504), "均为播放中途截图裁剪，不代表完整观看；未把弹幕当作作品设计。", font=font(25), fill="#e8effa")
    draw.text((40, 1548), "采样日期：2026-11-11。设计关键词是观察归纳，不能据此断言高播放的因果。", font=font(23), fill="#a9bad2")
    draw.text((40, 1588), "画内“120 FPS”及“视力训练”为作品文字，未验证实际帧率或训练效果。", font=font(21), fill="#a9bad2")
    canvas.save(ROOT / "案例画面设计对照.png")


if __name__ == "__main__":
    main()
