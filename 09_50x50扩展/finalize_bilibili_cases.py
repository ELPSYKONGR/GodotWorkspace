"""Save evidence and analysis fields for the newly downloaded Bilibili works."""
from __future__ import annotations

import json
import shutil
import urllib.parse
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parent
UA = "Mozilla/5.0"


def get_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://www.bilibili.com/"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def classify(title: str, description: str) -> str:
    text = title + " " + description
    if any(word in text for word in ("胜利", "哪队", "颜色", "谁能留", "存活")):
        return "阵营竞争"
    if any(word in text for word in ("逃", "圆圈", "圆环", "到达", "中心", "包围")):
        return "逃逸/到达"
    if any(word in text for word in ("翻倍", "增加", "爆发", "粒子", "数量", "分裂")):
        return "数量增长"
    if any(word in text for word in ("冻结", "回溯", "时间", "秒")):
        return "时间规则"
    if any(word in text for word in ("边界", "多边形", "边数", "形状")):
        return "阶段变形"
    if "线" in text:
        return "线条/资源"
    return "几何碰撞"


def analysis(category: str, title: str) -> dict:
    visual = {
        "阵营竞争": "颜色、标识或分区承担阵营身份；画面应保持对象数量可读，避免同色叠在一起。",
        "逃逸/到达": "中心边界和出口构成明确构图；主角球、障碍层数和出口应有视觉优先级。",
        "数量增长": "稀疏到密集的数量变化是主视觉；计数与球群不能遮住触发点和目标。",
        "时间规则": "时间窗口、冻结或回溯状态需要稳定位置的计时提示；变化前后画面要留出辨识时间。",
        "阶段变形": "多边形边数或边界变化形成阶段层级；几何线条要规整，变化后保留足够观察时间。",
        "线条/资源": "线条同时是装饰和状态资源；线条颜色、归属与剩余量必须能够快速区分。",
        "几何碰撞": "边界、球和障碍物保持中心对齐；减少无关装饰，突出碰撞的因果关系。",
    }[category]
    motion = {
        "阵营竞争": "用连续碰撞和淘汰推动胜负；避免连续很长时间只反弹而没有阵营状态变化。",
        "逃逸/到达": "用主角接近出口、错过缺口、突破下一层形成节奏；每层应有可见进度。",
        "数量增长": "让触发事件先示范，再进入加速增长；增长过快时保留阶段计数或密度刻度。",
        "时间规则": "事件前给短暂预告，事件后留出反馈帧；冻结、回溯不能只表现为球突然停住。",
        "阶段变形": "固定碰撞规则，按次数或条件切换边界；阶段切换应是瞬时可见但运动连续。",
        "线条/资源": "碰线、抢线、失线都应有短暂高亮；资源转移后继续保持球的运动连续。",
        "几何碰撞": "保持恒定或可解释的速度、反弹和障碍变化；避免通过结尾硬改规则制造结果。",
    }[category]
    mechanism = {
        "阵营竞争": "颜色阵营 + 生存/胜负条件 + 可逆或可观察的淘汰过程。",
        "逃逸/到达": "出口/目标 + 障碍层数或收缩压力 + 通过数量/到达状态。",
        "数量增长": "碰撞触发增殖、翻倍或爆发 + 数量上限/清空条件。",
        "时间规则": "冻结、回溯、倒计时或窗口改变下一步概率。",
        "阶段变形": "碰撞计数或条件触发边界、边数、形状变化。",
        "线条/资源": "线条归属、抢夺和资源归零淘汰。",
        "几何碰撞": "球与边界/砖块/门发生可解释接触并改变状态。",
    }[category]
    return {
        "core_design": f"标题‘{title}’把一个运动规则包装成可验证问题；核心不是装饰数量，而是{mechanism}",
        "visual_order": visual,
        "motion_fluidity": motion,
        "sound_coordination": "本轮未逐条试听原声，不能断言原片声音效果；实现时应给碰撞、突破、淘汰、释放分别配短音，并让音频事件来自数据层而非按帧猜测。",
        "effective_mechanism": mechanism,
        "implementation_process": "数据层先生成固定随机种子、球ID、碰撞/状态事件和完成原因；渲染层再读取轨迹绘制球、边界、文字、拖尾与事件音。批量生成先按目标是否兑现、最长无进展间隔和结尾是否有球筛选，再渲染可发布版本。",
        "attention_hook": "首屏用一个具体问题、少量主角和一次早期事件建立期待；避免开头只展示静止装饰。",
        "retention_design": "每隔一段时间给出可见进展、受阻或新阶段；中段不能长时间没有目标变化；结尾必须回答标题问题并保留观察结果的时间。",
        "audience_expectation": "观众应能预测下一步可能发生什么，却不能提前知道最终数量、赢家或是否成功；标题承诺必须由真实状态兑现。",
        "evidence_limit": "本条为公开详情API、标题/简介和保存抽帧基础上的设计分析；未逐帧完整观看，未试听音轨，不将推断写成完播或流量因果。",
    }


def main() -> None:
    selected = json.loads((ROOT / "bilibili_new_selected.json").read_text(encoding="utf-8"))
    manifests = {item["bvid"]: item for item in json.loads((ROOT / "original_videos" / "bilibili" / "download_manifest.json").read_text(encoding="utf-8"))}
    evidence = ROOT / "bilibili"
    evidence.mkdir(exist_ok=True)
    cases = []
    for candidate in selected:
        bvid = candidate["bvid"]
        manifest = manifests[bvid]
        view_url = f"https://api.bilibili.com/x/web-interface/view?bvid={urllib.parse.quote(bvid)}"
        view = get_json(view_url)
        data = view["data"]
        page = (data.get("pages") or [{}])[0]
        cid = page.get("cid")
        play_url = "https://api.bilibili.com/x/player/playurl?" + urllib.parse.urlencode({"bvid": bvid, "cid": cid, "fnval": 16, "fnver": 0, "fourk": 1})
        play = get_json(play_url)
        (evidence / f"{bvid}_api.json").write_text(json.dumps({"url": view_url, "data": view}, ensure_ascii=False, indent=2), encoding="utf-8")
        (evidence / f"{bvid}_playurl.json").write_text(json.dumps({"url": play_url, "data": play}, ensure_ascii=False, indent=2), encoding="utf-8")
        title = data.get("title", "")
        description = data.get("desc", "") or ""
        category = classify(title, description)
        media = ROOT / "original_videos" / "bilibili" / bvid / f"{bvid}.mp4"
        frame = ROOT / "frames" / f"{bvid}.jpg"
        cases.append({
            "platform": "Bilibili", "bvid": bvid, "url": f"https://www.bilibili.com/video/{bvid}/",
            "title": title, "description": description, "uploader": data.get("owner", {}).get("name"),
            "published_at": data.get("pubdate"), "duration_seconds": data.get("duration"),
            "views": data.get("stat", {}).get("view"), "likes": data.get("stat", {}).get("like"),
            "comments": data.get("stat", {}).get("reply"), "favorites": data.get("stat", {}).get("favorite"),
            "shares": data.get("stat", {}).get("share"), "rights_download": data.get("rights", {}).get("download"),
            "mechanism_category": category, "download_status": manifest.get("status"),
            "download_file": str(media.relative_to(ROOT)), "frame_file": str(frame.relative_to(ROOT)),
            "page_evidence_files": [f"bilibili/{bvid}_api.json", f"bilibili/{bvid}_playurl.json"],
            "design_analysis": analysis(category, title),
            "public_stream_note": "公开DASH播放流，≤480p请求下实际流可能为852高；不是创作者母版，不代表再发布许可。",
        })
    (ROOT / "cases_bilibili_24_new.json").write_text(json.dumps(cases, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"new_cases={len(cases)}; downloaded={sum(item['download_status']=='downloaded' for item in cases)}")


if __name__ == "__main__":
    main()
