"""Coordinate cached motion data and presentation-only rendering operations."""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import shutil
import threading
import uuid
from datetime import datetime, timedelta, timezone

from src.core.simulation import generate_scene
from src.data.config import ROOT, simulation_key, validate_config
from src.data.scene import SceneData
from src.rendering.exporter import export_scene
from src.rendering.renderer import render_frame

OUTPUTS = ROOT / "outputs"
SCENE_CACHE = ROOT / ".cache/scenes"
SCENE_LOCK = threading.RLock()


def _notify(callback, value: float, message: str) -> None:
    """Adapt the shared progress callback without coupling lower-level modules."""
    if callback is not None:
        callback(value, message)


def get_scene(config: dict, progress=None) -> tuple[SceneData, str, bool]:
    """Load or compute a fixed-rate trajectory independently of rendering edits."""
    checked = validate_config(config)
    key = simulation_key(checked)
    path = SCENE_CACHE / f"{key}.npz"
    with SCENE_LOCK:
        if path.is_file():
            _notify(progress, 0.24, "复用已有运动数据")
            return SceneData.load(path), key, True
        _notify(progress, 0.01, "生成运动数据")
        scene = generate_scene(checked, lambda value: _notify(progress, 0.02 + value * 0.22, "生成运动数据"))
        SCENE_CACHE.mkdir(parents=True, exist_ok=True)
        scene.save(path)
        return scene, key, False


def output_url(path: Path) -> str:
    """Produce a local HTTP URL only for files under the output directory."""
    relative = path.resolve().relative_to(OUTPUTS.resolve())
    return "/outputs/" + relative.as_posix()


def race_verdict(scene: SceneData, config: dict) -> dict | None:
    """Summarize a versus race so the editor can flag a verdict cut off by the duration."""
    spec = (scene.metadata or {}).get("versus")
    if not spec:
        return None
    result = spec.get("result", {})
    decided = spec.get("decided_at")
    hold = float(config.get("versus", {}).get("hold_after_decide", 0))
    labels = {"left": "左侧", "right": "右侧", "draw": "两侧同时"}
    return {
        "decided_at": decided,
        "winner": labels.get(str(result.get("winner")), ""),
        "margin": result.get("margin"),
        "left_final": result.get("left_final"),
        "right_final": result.get("right_final"),
        "fits": decided is None or float(decided) + hold <= float(config["output"]["duration"]),
    }


def preview(config: dict, time: float = 8) -> dict:
    """Render a single frame using the exact same visual layer as video export."""
    checked = validate_config(config)
    if isinstance(time, bool) or not isinstance(time, (int, float)) or not math.isfinite(time):
        raise ValueError("预览时间必须是有限数字")
    if not 0 <= time <= checked["output"]["duration"]:
        raise ValueError("预览时间必须位于视频时长以内")
    scene, key, is_cache_hit = get_scene(checked)
    encoded = json.dumps({"config": checked, "time": time}, ensure_ascii=False, sort_keys=True).encode()
    suffix = hashlib.sha256(encoded).hexdigest()[:14]
    folder = OUTPUTS / "previews" / key
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{suffix}.png"
    image = render_frame(scene, checked, time)
    image.save(path)
    return {
        "url": output_url(path),
        "data_key": key,
        "is_cache_hit": is_cache_hit,
        "actual_time": scene.frame_at(time).time,
        "verdict": race_verdict(scene, checked),
    }


def render(config: dict, output_dir: str | Path | None = None, progress=None) -> dict:
    """Export a full video and retain its motion/configuration for re-rendering."""
    checked = validate_config(config)
    stamp = datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d_%H%M%S")
    folder = Path(output_dir) if output_dir else OUTPUTS / "studio" / f"{stamp}_{uuid.uuid4().hex[:6]}"
    if not folder.is_absolute():
        folder = ROOT / folder
    folder = folder.resolve()
    folder.relative_to(OUTPUTS.resolve())
    scene, key, is_cache_hit = get_scene(checked, progress)
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SCENE_CACHE / f"{key}.npz", folder / "scene.npz")
    (folder / "config.json").write_text(json.dumps(checked, ensure_ascii=False, indent=2), encoding="utf-8")
    _notify(progress, 0.25, "绘制并编码视频")
    report = export_scene(
        scene, checked, folder, lambda value: _notify(progress, 0.25 + value * 0.70, "绘制并编码视频")
    )
    report.update(
        {
            "data_key": key,
            "is_cache_hit": is_cache_hit,
            "video_url": output_url(folder / "final.mp4"),
            "poster_url": output_url(folder / "poster.png"),
            "scene_url": output_url(folder / "scene.npz"),
            "config_url": output_url(folder / "config.json"),
        }
    )
    (folder / "run_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    _notify(progress, 1, "导出完成")
    return report
