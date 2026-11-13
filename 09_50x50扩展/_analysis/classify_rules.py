# -*- coding: utf-8 -*-
"""
classify_rules.py —— 从 107 条标题里抽取「机制原型」，统计规则空间分布

分类是启发式的（关键词 + 优先级），目的是看这批样本覆盖了哪些玩法，
而不是给每条视频下一个不可辩驳的结论。优先级高的先匹配，避免一条命中多类。
"""
import json
import os
import re
import sys
from collections import Counter, defaultdict

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\original_videos"
OUT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\_analysis\rule_space.json"

# (类别, 关键词列表) —— 顺序即优先级：越靠前的越"机制特异"
RULES = [
    ("吞噬-无底洞", ["吞噬", "无底洞", "吃完", "吃掉"]),
    ("边界变形", ["边界", "变换图形", "多一条边", "边数", "几边形", "五角大楼"]),
    ("合并进化", ["堆积", "进化", "合成", "三消"]),
    ("幂运算变大", ["幂运算", "变得更大", "变大", "变大。"]),
    ("碰撞翻倍", ["翻倍", "爆发", "增加1个", "增加2个", "分裂", "增加数量", "翻2倍", "翻3倍", "翻4倍", "翻30倍", "翻倍数"]),
    ("逃出穿环", ["逃出", "逃离", "逃出去", "逃脱", "逃生", "脱离"]),
    ("数量对抗", ["VS", "vs", "对战"]),
    ("颜色对抗", ["获胜", "胜利", "谁能赢", "存活", "淘汰", "留到最后", "坚持到最后", "谁能获得", "摧毁", "消灭"]),
    ("时间限制", ["秒内", "秒，", "有4秒", "活动2秒", "5秒", "倒计时", "30秒", "80秒"]),
    ("连锁反应", ["多米诺", "骨牌", "连锁"]),
    ("目标命中", ["中心", "砖块", "砸到", "击中", "到达", "打进"]),
    ("门与出口", ["门", "出口"]),
    ("速度竞赛", ["先到达", "多快", "速度"]),
    ("外部注入", ["掉落", "活塞", "注入", "投放"]),
    ("身份/拟人", ["百家姓", "姓氏", "动物", "喵", "表情包", "皮卡", "蛋糕", "乐器", "品牌", "史莱克"]),
    ("非球类异类", ["石头剪刀布", "弹幕", "小羊"]),
]


def classify(title):
    for name, kws in RULES:
        if any(k in title for k in kws):
            return name
    return "未归类"


def load():
    rows = []
    # 抖音 50 条的标题以主清单为准（含上一轮已下载的 13 条，那张 CSV 只覆盖后补的 37 条）
    mp = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\download_manifest.json"
    seen = set()
    if os.path.exists(mp):
        m = json.load(open(mp, encoding="utf-8"))
        for it in m["items"]:
            if it.get("platform") == "Douyin":
                rows.append({"source": "douyin", "vid": it["id"],
                             "title": str(it.get("title", ""))})
                seen.add(it["id"])
    for d in sorted(os.listdir(os.path.join(ROOT, "bilibili"))):
        p = os.path.join(ROOT, "bilibili", d, "manifest.json")
        if os.path.exists(p):
            m = json.load(open(p, encoding="utf-8"))
            rows.append({"source": "bilibili", "vid": d, "title": str(m.get("title", ""))})
    return rows


def main():
    rows = load()
    for r in rows:
        r["rule"] = classify(r["title"])

    c = Counter(r["rule"] for r in rows)
    print(f"[total] {len(rows)} 条\n")
    print(f"{'机制原型':<12}{'条数':>4}   {'抖音':>4} {'B站':>4}")
    for name, n in c.most_common():
        a = sum(1 for r in rows if r["rule"] == name and r["source"] == "douyin")
        b = sum(1 for r in rows if r["rule"] == name and r["source"] == "bilibili")
        print(f"{name:<12}{n:>4}   {a:>4} {b:>4}")

    unc = [r for r in rows if r["rule"] == "未归类"]
    if unc:
        print(f"\n未归类 {len(unc)} 条：")
        for r in unc:
            print("  ", r["vid"], "|", r["title"][:50])

    by = defaultdict(list)
    for r in rows:
        by[r["rule"]].append(r["title"])
    json.dump({"total": len(rows), "counts": dict(c),
               "examples": {k: v[:6] for k, v in by.items()},
               "items": rows},
              open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"\n-> {OUT}")


if __name__ == "__main__":
    main()
