"""Save public GitHub evidence for the engine selection report; no dependencies."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
DEST = ROOT / "sources"
HEADERS = {"User-Agent": "RelaxingPhysics-Engine-Research", "Accept": "application/vnd.github+json"}
REPOS = [
    "4ian/GDevelop", "phaserjs/phaser", "liabru/matter-tools", "pmndrs/react-three-rapier",
    "JustLachin/ring-escape", "bikramadhikari001/engaging-animations",
    "QuantumZain/chaotic-system", "Sarish002/BallSimulation",
]


def fetch(url):
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=30) as response:
            return {"url": url, "status": response.status, "body": response.read().decode("utf-8", "replace")}
    except (urllib.error.URLError, TimeoutError) as error:
        return {"url": url, "error": str(error)}


def research(repo):
    response = fetch("https://api.github.com/repos/" + repo)
    if "body" not in response:
        return {"repo": repo, "error": response}
    data = json.loads(response["body"])
    result = {key: data.get(key) for key in ["full_name", "html_url", "description", "license", "stargazers_count", "pushed_at", "updated_at", "archived", "default_branch", "homepage"]}
    result["source"] = response["url"]
    branch = result["default_branch"]
    for name in ["README.md", "LICENSE"]:
        raw = fetch(f"https://raw.githubusercontent.com/{repo}/{branch}/{name}")
        target = DEST / (repo.replace("/", "__") + "__" + name)
        if "body" in raw:
            target.write_text(raw.pop("body"), encoding="utf-8")
            raw["local_file"] = str(target.relative_to(ROOT))
        result[name] = raw
    return result


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(research, REPOS))
    report = {"retrieved_at_utc": datetime.now(timezone.utc).isoformat(), "repositories": results}
    (DEST / "additional_repositories.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    for result in results:
        print(json.dumps({key: result.get(key) for key in ["full_name", "license", "pushed_at", "archived", "error"]}, ensure_ascii=False))
