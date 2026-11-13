from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json, re, requests, sys, base64
SESSION = requests.Session()
SESSION.trust_env = False
sys.stdout.reconfigure(encoding="utf-8")
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "05_证据与来源"
OUT.mkdir(exist_ok=True)
REPOS = ["Comfy-Org/ComfyUI", "Wan-Video/Wan2.2", "QwenLM/Qwen-Image",
         "SYSTRAN/faster-whisper", "FunAudioLLM/CosyVoice", "hexgrad/kokoro",
         "FFmpeg/FFmpeg", "blender/blender", "PrefectHQ/prefect", "harry0703/MoneyPrinterTurbo"]
PAGES = {
    "runway_pricing": "https://docs.dev.runwayml.com/guides/pricing/",
    "youtube_monetization": "https://support.google.com/youtube/answer/1311392?hl=en",
    "youtube_ai_disclosure": "https://support.google.com/youtube/answer/14328491?hl=en",
    "youtube_ypp": "https://support.google.com/youtube/answer/72851?hl=en",
    "blender_license": "https://www.blender.org/about/license/",
    "blender_cli": "https://docs.blender.org/manual/en/latest/advanced/command_line/render.html",
    "youtube_upload": "https://developers.google.com/youtube/v3/docs/videos/insert",
    "douyin_open": "https://developer.open-douyin.com/",
}


def repo(name):
    data = {"repo": name, "url": "https://github.com/" + name}
    try:
        r = SESSION.get("https://api.github.com/repos/"+name, timeout=12)
        r.raise_for_status()
        j = r.json()
        data.update(default_branch=j["default_branch"], license=j.get("license"), archived=j["archived"], pushed_at=j["pushed_at"], description=j["description"])
        readme = SESSION.get(f"https://api.github.com/repos/{name}/readme", timeout=12)
        data["readme_status"] = readme.status_code
        readme.raise_for_status()
        content=base64.b64decode(readme.json()['content']).decode('utf-8')
        (OUT/(name.replace('/', '__')+".md")).write_text(content, encoding="utf-8")
    except Exception as e:
        data["error"] = str(e)
    return data


def page(item):
    key,url = item
    data = {"key":key, "url":url}
    try:
        r=SESSION.get(url,timeout=15)
        data.update(status=r.status_code,final_url=r.url)
        (OUT/(key+".html")).write_text(r.text,encoding="utf-8")
        text=re.sub(r"<(script|style)\b[^>]*>.*?</\1>","",r.text,flags=re.S|re.I)
        text=re.sub(r"<[^>]+>","\n",text)
        text=re.sub(r"\n\s*\n+","\n",text)
        (OUT/(key+".txt")).write_text(text,encoding="utf-8")
    except Exception as e:
        data["error"]=str(e)
    return data


if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=8) as pool:
        repos=list(pool.map(repo,REPOS))
        pages=list(pool.map(page,PAGES.items()))
    data={"checked_date_Asia_Shanghai":"2026-11-11", "repos":repos, "pages":pages}
    (OUT/"sources.json").write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(data,ensure_ascii=False,indent=2))
