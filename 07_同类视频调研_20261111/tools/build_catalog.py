"""将人工核实的抖音页面记录与 B 站官方指标汇总为可复查目录。"""

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

# “万”为网页约数；保存原始字符串，不将换算值误写成后台精确值。
DOUYIN_ROWS = [
    {
        "id": "7432370127951236412",
        "title": "吞噬完小球的圈圈是个无底洞吗？（第30集）",
        "uploader": "探索宇宙",
        "published_at": "2024-11-02T01:53:00+08:00",
        "duration_seconds": 60.683332,
        "duration_source": "video DOM duration",
        "metrics_display": {"likes": "35.8万", "comments": "1.2万", "favorites": "5.9万", "shares": "5.1万"},
        "observation": {
            "mechanism": "标题提出吞噬与无底洞的问题；截图未完整核实吞噬全过程。",
            "visible_design": "竖屏中央圆形主体，深色星空底；较晚两张截图可见绿色密集同心环与蓝紫色螺旋状密集图案。大面积白字为平台弹幕，不应当作作品字幕。",
            "hypothesis": "重复圆环和高密度图案可能提供秩序感与视觉变化；问题式标题提供等待对象。不能仅凭晚段截图确定具体增殖或吞噬算法。",
        },
        "frame_times_dom_before_capture": [53.027, 49.691705],
    },
    {
        "id": "7454633814921448761",
        "title": "球能逃脱所有缩小的圆圈吗？（第31集）",
        "uploader": "探索宇宙",
        "published_at": "2025-01-01T01:46:00+08:00",
        "duration_seconds": 45.486009,
        "duration_source": "video DOM duration",
        "metrics_display": {"likes": "38.0万", "comments": "2.1万", "favorites": "2.5万", "shares": "15.4万"},
        "observation": {
            "mechanism": "标题提出缩圈逃脱；中段可见单个白色亮球、粉色拖尾、多层带缺口圆环和Countdown倒计时。未核实完整结局。",
            "visible_design": "星空深底、细粉色圆环，唯一显著运动主角；少量主体让球、缺口、剩余层级比较容易区分。",
            "hypothesis": "单一主角降低追踪负担；缩圈标题与倒计时制造时间压力，缺口和环层级提供进展线索。未量化缩圈速度、缺口转速或留存。",
        },
        "frame_times_dom_before_capture": [23.008, 19.848496],
    },
    {
        "id": "7547536054669299004",
        "title": "游戏化视力训练",
        "uploader": "探索宇宙",
        "published_at": "2025-09-08T10:14:00+08:00",
        "duration_seconds": 62.159818,
        "duration_source": "video DOM duration",
        "metrics_display": {"likes": "47.0万", "comments": "4471", "favorites": "12.9万", "shares": "6.8万"},
        "observation": {
            "mechanism": "标题为作者的‘游戏化视力训练’说法；两张较晚截图中有青色球，另一张还能看到细圆轨迹和空心小圈。",
            "visible_design": "星空深底、青色球、顶部少量黄白文字；画内标有120 FPS，但未从媒体文件核实真实编码帧率和平台播放帧率。",
            "hypothesis": "将观看包装成追踪任务可能提供参与理由。不能据此宣称改善视力，也不能归因于120FPS。",
        },
        "frame_times_dom_before_capture": [50.199, 43.756421],
    },
    {
        "id": "7684444900621264485",
        "title": "它们谁能获得胜利？（第558集）",
        "uploader": "探索宇宙",
        "published_at": "2026-09-12T08:50:00+08:00",
        "duration_seconds": 67,
        "duration_source": "网页播放器显示约01:07，非精确媒体探测",
        "metrics_display": {"likes": "2.8万", "comments": "281", "favorites": "1539", "shares": "5728"},
        "observation": {
            "mechanism": "标题提出胜负问题；约30秒截图中圆环内两种颜色的球带有PS与Xbox标识，且有不同颜色连线。未核实完整资源变化规则或结局。",
            "visible_design": "深底白圆环，蓝绿主体标识、同色线条；可见弹幕‘蓝色加油’，属于观众反应而非作品字幕。",
            "hypothesis": "可辨阵营为选边与讨论提供对象；品牌标识只是案例事实，自制版本可用原创颜色或符号表达阵营。",
        },
        "frame_times_dom_before_capture": [],
    },
    {
        "id": "7705831565992955145",
        "title": "Blender | 这个动画太有创意还解压！",
        "uploader": "AOV视觉科学",
        "published_at": "2026-11-09T00:02:00+08:00",
        "duration_seconds": 48.966667,
        "duration_source": "前轮已下载原文件媒体探测",
        "metrics_display": {"likes": "2.5万", "comments": "506", "favorites": "1161", "shares": "1.6万"},
        "observation": {
            "mechanism": "用户原始参考；圆形容器、扇叶形挡板与小球，画内可见Will it overflow问题。当前约45秒截图不能代表完整过程。",
            "visible_design": "竖屏居中容器、扇叶形挡板、球体和顶部问题；页面上大量白字属于平台弹幕。",
            "hypothesis": "装填、遮挡和潜在溢出让运动具有等待对象；本轮不另行假定原片结尾如何兑现。",
        },
        "frame_times_dom_before_capture": [],
    },
]


def parse_display(value: str) -> int:
    """换算显示数量；是否为近似值在独立标记中保存。"""
    return round(float(value[:-1]) * 10000) if value.endswith("万") else int(value)


def build() -> None:
    """保存平台明细、合并目录和适于 Excel 打开的 CSV。"""
    douyin = []
    for row in DOUYIN_ROWS:
        item = {**row, "platform": "Douyin", "url": f"https://www.douyin.com/video/{row['id']}",
                "views": None, "views_status": "公开页面未展示，未推算",
                "metric_snapshot_date": "2026-11-11", "metric_source": "公开作品详情页可见指标",
                "watch_scope": "抽看公开网页中晚段并留截图；DOM时间在截图前读取，和截图UI时刻存在短暂偏差。未完整逐帧看验结尾。",
                "audio_scope": "未实际听验，不对具体配乐和音效作事实判断。",
                "metrics_approximate": {k: v.endswith("万") for k, v in row["metrics_display"].items()},
                "page_evidence_file": f"{row['id']}_snapshot.txt", "screenshot_file": f"{row['id']}.png"}
        item.update({k: parse_display(v) for k, v in row["metrics_display"].items()})
        additional = ROOT / "douyin" / f"{row['id']}_additional.png"
        if additional.exists():
            item["additional_screenshot_file"] = additional.name
        douyin.append(item)
    (ROOT / "douyin" / "cases.json").write_text(json.dumps(douyin, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    catalog = []
    for item in json.loads((ROOT / "bilibili" / "cases.json").read_text(encoding="utf-8")):
        copy = {**item, "id": item["bvid"], "duration_seconds": item["duration_seconds_api"],
                "metrics_approximate": {k: False for k in ["likes", "comments", "favorites", "shares"]},
                "evidence_directory": "bilibili"}
        catalog.append(copy)
    catalog.extend({**item, "evidence_directory": "douyin"} for item in douyin)
    (ROOT / "cases.json").write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    columns = ["platform", "id", "title", "uploader", "url", "published_at", "duration_seconds", "views",
               "likes_display", "likes", "likes_approximate", "comments_display", "favorites_display", "shares_display",
               "like_view_ratio_percent", "metric_snapshot_date", "metric_source", "evidence_directory", "page_evidence_file", "screenshot_file"]
    with (ROOT / "cases.csv").open("w", encoding="utf-8-sig", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=columns)
        writer.writeheader()
        for item in catalog:
            row = {k: item.get(k, "") for k in columns}
            for metric in ["likes", "comments", "favorites", "shares"]:
                row[f"{metric}_display"] = item.get("metrics_display", {}).get(metric, str(item[metric]))
            row["likes_approximate"] = item["metrics_approximate"]["likes"]
            row["metric_snapshot_date"] = item.get("metric_snapshot_date", item.get("fetched_at", "")[:10])
            writer.writerow(row)
    print(f"已生成 {len(catalog)} 条记录：B站 {len(catalog) - len(douyin)}、抖音 {len(douyin)}。抖音播放为空，万级数均标记约数。")


if __name__ == "__main__":
    build()
