"""Create a review contact sheet from unchanged public-page screenshots."""
from __future__ import annotations
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent
FONT = Path("C:/Windows/Fonts/msyh.ttc")
BOLD = Path("C:/Windows/Fonts/msyhbd.ttc")
CASES = json.loads((ROOT / "cases_additional.json").read_text(encoding="utf-8"))

def f(size, bold=False):
    return ImageFont.truetype(str(BOLD if bold else FONT), size)

def main():
    W, H = 1800, 1160
    canvas = Image.new("RGB", (W, H), "#0d1524")
    draw = ImageDraw.Draw(canvas)
    draw.text((32, 20), "抖音扩展样本：公开页面截图对照", font=f(38, True), fill="#f1f6ff")
    draw.text((34, 70), "10条新增作品；截图为页面观察证据，不代表完整观看，播放量未公开", font=f(22), fill="#aabbd1")
    for i, case in enumerate(CASES):
        x = 30 + (i % 5) * 354
        y = 120 + (i // 5) * 500
        draw.rounded_rectangle((x, y, x + 330, y + 460), 14, fill="#172338", outline="#354a6b", width=2)
        title = case["title_clean"]
        if len(title) > 18:
            title = title[:18] + "…"
        draw.text((x + 14, y + 14), f"{i+1:02d}  {case['metrics_display']['likes']}赞", font=f(20, True), fill="#f0ca85")
        draw.text((x + 14, y + 47), title, font=f(17), fill="#eef4ff")
        with Image.open(ROOT / case["screenshot_file"]) as source:
            crop = source.convert("RGB")
            crop = ImageOps.fit(crop, (300, 310), method=Image.Resampling.LANCZOS, centering=(0.5, 0.45))
            canvas.paste(crop, (x + 15, y + 84))
        tag = case["design_observation"].split("：")[0]
        draw.text((x + 14, y + 409), tag, font=f(18, True), fill="#83d9cb")
        status = "已下载" if case["download_status"] == "downloaded" else "未下载（保留证据）"
        draw.text((x + 14, y + 435), status, font=f(15), fill="#aabbd1")
    canvas.save(ROOT / "抖音扩展案例截图对照.png")

if __name__ == "__main__":
    main()
