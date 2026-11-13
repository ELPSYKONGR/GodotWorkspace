"""Find new public Bilibili geometry/physics animation candidates."""
from __future__ import annotations

import json
import re
import time
from collections import OrderedDict
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent
HEADERS = {
    # Bilibili's search endpoint intermittently returns an anti-bot HTML page
    # for browser-like headers. A plain public HTTP client is sufficient and
    # avoids pretending to be a logged-in browser.
    "User-Agent": "curl/8.0",
}
KEYWORDS = [
    "\u5c0f\u7403 \u89e3\u538b \u51e0\u4f55",
    "\u5c0f\u7403 \u9003\u51fa \u5706\u73af",
    "\u5c0f\u7403 \u53cd\u5f39 \u52a8\u753b",
    "\u5c0f\u7403 \u78b0\u649e \u589e\u6b96",
    "\u5c0f\u7403 \u591a\u8fb9\u5f62 \u89e3\u538b",
    "\u5f39\u73e0 \u89e3\u538b \u52a8\u753b",
    "\u51e0\u4f55\u56fe\u5f62 \u5c0f\u7403",
    "\u5706\u73af \u5c0f\u7403 \u9003\u79bb",
    "\u7c92\u5b50 \u52a8\u753b \u89e3\u538b",
]


def api_get(keyword: str, page: int) -> dict:
    url = "https://api.bilibili.com/x/web-interface/search/type"
    params = {"search_type": "video", "keyword": keyword, "order": "click", "page": page, "page_size": 20}
    for retry in range(3):
        response = requests.get(url, params=params, headers=HEADERS, timeout=30)
        try:
            data = response.json()
        except Exception:
            if retry == 2:
                raise RuntimeError(f"search returned non-JSON: status={response.status_code} url={response.url}")
            time.sleep(0.8)
            continue
        if data.get("code") == 0:
            return data
        time.sleep(0.8)
    raise RuntimeError(f"search failed: {keyword!r} page={page}")


def main() -> None:
    existing = set()
    for path in [
        Path("D:/codex/AGI/AI视频三项目评估_20261111/07_同类视频调研_20261111/bilibili/cases.json"),
        Path("D:/codex/AGI/AI视频三项目评估_20261111/08_同类作品扩展_20261111/bilibili/cases_additional.json"),
    ]:
        if path.exists():
            data = json.loads(path.read_text(encoding="utf-8"))
            existing.update(item.get("bvid") for item in data if item.get("bvid"))
    rows = OrderedDict()
    search_evidence = []
    good_terms = re.compile("[\u5c0f\u7403\u5f39\u73e0\u5706\u73af\u51e0\u4f55\u7c92\u5b50\u8fb9\u754c]")
    mechanism_terms = re.compile("[\u89e3\u538b\u78b0\u649e\u53cd\u5f39\u9003\u541e\u589e\u6b96\u7e41\u6b96\u5206\u88c2\u5706\u73af\u5f39\u73e0\u95e8\u7ebf\u6761]")
    for keyword in KEYWORDS:
        # Search page 2+ is often challenged with HTTP 412; several page-1
        # keyword queries give enough public candidates without bypassing it.
        for page in range(1, 2):
            try:
                data = api_get(keyword, page)
            except RuntimeError as error:
                print(f"skip keyword={keyword!r}: {error}")
                continue
            search_evidence.append({"keyword": keyword, "page": page, "data": data})
            for item in data.get("data", {}).get("result", []) or []:
                bvid = item.get("bvid")
                title = re.sub(r"<[^>]+>", "", item.get("title", ""))
                description = item.get("description", "") or ""
                text = title + " " + description
                if not bvid or bvid in existing or bvid in rows:
                    continue
                if not good_terms.search(text) or not mechanism_terms.search(text):
                    continue
                duration = item.get("duration", "")
                match = re.fullmatch(r"(?:(\d+):)?(\d+)", duration)
                seconds = (int(match.group(1) or 0) * 60 + int(match.group(2))) if match else 0
                if not 10 <= seconds <= 180:
                    continue
                rows[bvid] = {**item, "title_clean": title, "search_keyword": keyword, "duration_seconds": seconds}
            time.sleep(0.12)
    selected = sorted(rows.values(), key=lambda item: int(str(item.get("play", 0)).replace(",", "") or 0), reverse=True)
    (ROOT / "bilibili_search_evidence.json").write_text(json.dumps(search_evidence, ensure_ascii=False), encoding="utf-8")
    (ROOT / "bilibili_candidates.json").write_text(json.dumps(selected, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"candidates={len(selected)}; existing={len(existing)}")
    for item in selected[:60]:
        print(item["bvid"], item.get("play"), item.get("like"), item.get("title_clean"))


if __name__ == "__main__":
    main()
