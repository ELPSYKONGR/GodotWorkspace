"""Load, validate and normalize editable scene configuration.

The renderer and simulator receive plain dictionaries from this module.  This
keeps the data contract serializable for the local editor and prevents UI
concerns from leaking into physics code.
"""

from __future__ import annotations

import copy
import json
import os
import math
import hashlib
from string import Formatter
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / "config"
PRESET_DIR = CONFIG_DIR / "presets"
CURRENT_CONFIG = CONFIG_DIR / "current.json"
HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
ALLOWED_MODES = {"multiply", "escape", "rain", "ring_escape", "stack_domino", "versus"}
ALLOWED_FPS = {24, 25, 30, 50, 60}
ALLOWED_SIZES = {(360, 640), (540, 960), (720, 1280), (1080, 1920)}
TEXT_FIELDS = {
    "count",
    "remaining",
    "escaped",
    "time",
    "phase",
    "left",
    "right",
    "margin",
    "winner",
    "capacity",
    "seed_balls",
    "left_burst",
    "right_burst",
}
TEXT_FIELD_SPECS = {"time": {".0f", ".1f", ".2f"}, "margin": {".1f", ".2f", ".3f"}}


def default_config(mode: str = "multiply") -> dict[str, Any]:
    """Read a fresh starter preset from its editable JSON file."""
    if mode not in ALLOWED_MODES:
        raise ValueError(f"Unknown mode: {mode}")
    return load_json(PRESET_DIR / f"{mode}.json")


def _require(condition: bool, message: str) -> None:
    """Raise a useful validation error instead of allowing bad data downstream."""
    if not condition:
        raise ValueError(message)


def _number(value: Any, low: float, high: float, *, is_integer: bool = False) -> bool:
    """Check finite numeric values while rejecting JSON booleans and NaN."""
    expected = int if is_integer else (int, float)
    return not isinstance(value, bool) and isinstance(value, expected) and math.isfinite(value) and low <= value <= high


def validate_config(raw: Any) -> dict[str, Any]:
    """Validate and deep-copy an editor payload, returning normalized data."""
    _require(isinstance(raw, dict), "配置必须是 JSON 对象")
    config = copy.deepcopy(raw)
    _require(isinstance(config.get("name"), str) and 1 <= len(config["name"]) <= 100, "方案名称必须为 1 到 100 个字符")
    output = config.get("output")
    simulation = config.get("simulation")
    appearance = config.get("appearance")
    texts = config.get("texts")
    _require(isinstance(output, dict), "output 必须是对象")
    _require(isinstance(simulation, dict), "simulation 必须是对象")
    _require(isinstance(appearance, dict), "appearance 必须是对象")
    _require(isinstance(texts, list), "texts 必须是数组")
    width, height = output.get("width"), output.get("height")
    _require(
        _number(width, 1, 1080, is_integer=True) and _number(height, 1, 1920, is_integer=True), "画布尺寸必须是整数"
    )
    _require((width, height) in ALLOWED_SIZES, "画布必须是受支持的 9:16 尺寸")
    fps, duration = output.get("fps"), output.get("duration")
    _require(_number(fps, 1, 60, is_integer=True) and fps in ALLOWED_FPS, "fps 只能是 24、25、30、50 或 60")
    _require(_number(duration, 1, 60), "duration 必须在 1 到 60 秒")
    mode = simulation.get("mode")
    _require(isinstance(mode, str) and mode in ALLOWED_MODES, "simulation.mode 不受支持")
    sample_rate = simulation.get("sample_rate")
    _require(
        _number(sample_rate, 30, 120, is_integer=True) and sample_rate in {30, 60, 120},
        "sample_rate 只能是 30、60 或 120",
    )
    _require(_number(simulation.get("seed"), 0, 2**31 - 1, is_integer=True), "seed 无效")
    _require(
        _number(simulation.get("initial_balls"), 1, 1500, is_integer=True)
        and _number(simulation.get("max_balls"), 1, 1500, is_integer=True),
        "球数必须为 1 到 1500 的整数",
    )
    _require(simulation["initial_balls"] <= simulation["max_balls"], "初始球数不能超过上限")
    _require(
        _number(simulation.get("release_at"), 0.1, duration) and simulation["release_at"] < duration,
        "release_at 必须小于 duration",
    )
    for name, low, high in (
        ("ball_radius", 3, 25),
        ("rotation_speed", 0, 3),
        ("birth_cooldown", 0.1, 5),
        ("gravity", 0, 1500),
    ):
        _require(_number(simulation.get(name), low, high), f"{name} 必须在 {low} 到 {high}")
    if mode == "ring_escape":
        ring = config.get("ring_escape", {})
        _require(isinstance(ring, dict), "ring_escape 必须是对象")
        _require(_number(simulation.get("outer_radius"), 200, 900), "outer_radius 无效")
        _require(_number(simulation.get("ring_count"), 1, 64, is_integer=True), "ring_count 无效")
        _require(_number(simulation.get("ring_spacing"), 5, 200), "ring_spacing 无效")
        _require(_number(simulation.get("gap_width"), 0.05, math.tau), "gap_width 无效")
        _require(_number(simulation.get("escape_speed"), 1, 2000), "escape_speed 无效")
        _require(_number(simulation.get("max_speed"), 1, 3000), "max_speed 无效")
    if mode == "stack_domino":
        stack = config.get("stack_domino", {})
        _require(isinstance(stack, dict), "stack_domino 必须是对象")
        for name, low, high in (("domino_count", 1, 200), ("glass_count", 1, 300), ("max_live_balls", 1, 1500)):
            _require(_number(stack.get(name), low, high, is_integer=True), f"{name} 无效")
        values = stack.get("multiplier_values")
        _require(
            isinstance(values, list)
            and 1 <= len(values) <= 8
            and all(_number(value, 1, 32, is_integer=True) for value in values),
            "multiplier_values 无效",
        )
    if mode == "versus":
        versus = config.get("versus", {})
        _require(isinstance(versus, dict), "versus 必须是对象")
        for name, low, high in (
            ("lane_capacity", 60, 700),
            ("seed_balls", 1, 700),
            ("left_burst", 2, 12),
            ("right_burst", 2, 6),
        ):
            _require(_number(versus.get(name), low, high, is_integer=True), f"{name} 无效")
        for name in ("left_cooldown", "right_cooldown"):
            _require(_number(versus.get(name), 0.05, 20.0), f"{name} 必须是 0.05 到 20 秒")
        _require(_number(versus.get("hold_after_decide", 2.2), 0.5, 8.0), "hold_after_decide 必须是 0.5 到 8 秒")
        _require(_number(versus.get("first_split_at", 0), 0, 12.0), "first_split_at 必须是 0 到 12 秒")
        versus.setdefault("split_hitstop", 0.06)
        versus.setdefault("split_hitstop_interval", 0.25)
        _require(_number(versus["split_hitstop"], 0, 0.2), "分裂顿帧时长必须是0到0.2秒，0为关闭")
        _require(_number(versus["split_hitstop_interval"], 0.1, 2), "顿帧间隔必须是0.1到2秒")
        appearance.setdefault("generation_fade", 0.2)
        _require(_number(appearance["generation_fade"], 0, 0.6), "代际变浅强度必须是0到0.6")
        _require(versus["seed_balls"] < versus["lane_capacity"], "seed_balls 必须小于 lane_capacity")
        _require(2 * versus["lane_capacity"] <= 1500, "双通道总容量不能超过 1500 个球槽")
    for key in ("background_top", "background_bottom", "ring_color", "rotor_color"):
        _require(
            isinstance(appearance.get(key), str) and HEX_RE.match(appearance[key]) is not None, f"{key} 必须是 #RRGGBB"
        )
    palette = appearance.get("palette")
    _require(
        isinstance(palette, list)
        and 1 <= len(palette) <= 16
        and all(isinstance(x, str) and HEX_RE.match(x) for x in palette),
        "palette 无效",
    )
    _require(len(texts) <= 32, "文字层最多 32 个")
    for item in texts:
        _require(isinstance(item, dict), "文字层必须是对象")
        _require(isinstance(item.get("id"), str) and re.match(r"^[A-Za-z0-9_-]{1,40}$", item["id"]), "文字层 id 无效")
        _require(isinstance(item.get("text"), str) and len(item["text"]) <= 500, "文字内容无效")
        try:
            for _, field, spec, conversion in Formatter().parse(item["text"]):
                if field is not None:
                    _require(
                        field in TEXT_FIELDS,
                        "文字占位符仅支持 count、remaining、escaped、time、phase、left、right、margin、winner、"
                        "capacity、seed_balls、left_burst、right_burst",
                    )
                    _require(
                        not conversion and (not spec or spec in TEXT_FIELD_SPECS.get(field, set())),
                        "文字格式不受支持",
                    )
        except ValueError as exc:
            raise ValueError(f"文字模板无效: {exc}") from exc
        _require(_number(item.get("x"), 0, 720), "文字 x 越界")
        _require(_number(item.get("y"), 0, 1280), "文字 y 越界")
        _require(_number(item.get("size"), 8, 180), "字体大小必须在 8 到 180")
        _require(isinstance(item.get("color"), str) and HEX_RE.match(item["color"]) is not None, "文字颜色无效")
        _require(
            item.get("font", "auto") == "auto" or re.match(r"^[A-Za-z0-9_.-]{1,100}$", str(item["font"])),
            "font 只能使用字体 ID",
        )
        _require(isinstance(item.get("is_visible", True), bool), "文字显隐必须为布尔值")
        _require(item.get("anchor", "mm") in {"mm", "lm", "rm"}, "文字对齐方式无效")
        resolve_font(item.get("font", "auto"))
    _require(len({item["id"] for item in texts}) == len(texts), "文字层 id 不能重复")
    audio = config.get("audio", {})
    _require(isinstance(audio, dict) and isinstance(audio.get("is_enabled", True), bool), "audio 无效")
    _require(_number(audio.get("volume", 1.0), 0, 2), "音量必须在 0 到 2")
    _require(audio.get("sample_rate", 44100) in (44100, 48000), "音频采样率只能是 44100 或 48000")
    _require(isinstance(audio.get("bgm", False), bool), "bgm 必须为布尔值")
    _require(_number(audio.get("bgm_level", 0.5), 0, 1), "bgm_level 必须在 0 到 1")
    _require(_number(audio.get("gain", 1.0), 0.2, 4.0), "gain 必须在 0.2 到 4")
    config["schema_version"] = 1
    return config


def load_json(path: Path) -> dict[str, Any]:
    """Read and validate a JSON configuration from an allowed project path."""
    if not path.is_file() or path.suffix.lower() != ".json":
        raise FileNotFoundError(f"配置文件不存在: {path}")
    return validate_config(json.loads(path.read_text(encoding="utf-8")))


def save_json(config: dict[str, Any], path: Path = CURRENT_CONFIG) -> dict[str, Any]:
    """Validate and atomically save configuration inside the project."""
    checked = validate_config(config)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(checked, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)
    return checked


def load_current() -> dict[str, Any]:
    """Load current.json or create it from the multiply preset."""
    if CURRENT_CONFIG.is_file():
        return load_json(CURRENT_CONFIG)
    return save_json(default_config())


def preset_configs() -> list[dict[str, Any]]:
    """Return the built-in configurations without reading unsafe paths."""
    return [
        default_config(mode)
        for mode in ("multiply", "escape", "rain", "ring_escape", "stack_domino", "versus")
    ]


def _font_files() -> dict[str, Path]:
    """Discover installed fonts and optional project fonts without user paths."""
    roots = [ROOT / "assets/fonts"]
    windir = os.environ.get("WINDIR") or os.environ.get("SystemRoot")
    if windir:
        roots.append(Path(windir) / "Fonts")
    else:
        roots.extend(
            Path(part) / "fonts"
            for part in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(os.pathsep)
        )
        roots.append(Path.home() / ".local/share/fonts")
    fonts = {}
    for root in roots:
        if root.is_dir():
            for path in sorted(root.rglob("*")):
                if (
                    path.suffix.lower() in {".ttf", ".ttc", ".otf"}
                    and path.is_file()
                    and re.fullmatch(r"[A-Za-z0-9_.-]+", path.name)
                ):
                    fonts.setdefault(path.name.lower(), path)
    return fonts


def font_options() -> list[dict[str, str]]:
    """Expose safe font IDs for the editor instead of filesystem paths."""
    names = {
        "msyh.ttc": "微软雅黑",
        "msyhbd.ttc": "微软雅黑 粗体",
        "msyhl.ttc": "微软雅黑 细体",
        "simhei.ttf": "黑体",
        "simsun.ttc": "宋体",
        "simkai.ttf": "楷体",
    }
    fonts = _font_files()
    preferred = [name for name in names if name in fonts]
    others = sorted(set(fonts) - set(preferred))
    return [{"id": "auto", "name": "自动选择中文字体"}] + [
        {"id": name, "name": names.get(name, fonts[name].stem)} for name in preferred + others
    ]


def resolve_font(font_id: str = "auto") -> Path:
    """Resolve an allowlisted font ID, with a Chinese-first automatic choice."""
    fonts = _font_files()
    if font_id == "auto":
        for name in ("msyh.ttc", "simhei.ttf", "notosanscjk-regular.ttc", "dejavusans.ttf"):
            if name in fonts:
                return fonts[name]
        if fonts:
            return next(iter(fonts.values()))
        raise ValueError("未找到可用字体，请把 .ttf/.ttc 字体放入 assets/fonts")
    if not isinstance(font_id, str) or font_id not in fonts:
        raise ValueError("所选字体不可用，请从字体列表重新选择")
    return fonts[font_id]


def simulation_key(config: dict[str, Any]) -> str:
    """Key only motion inputs; all rendering edits intentionally reuse data."""
    data = {
        "schema": 1,
        "physics_revision": 7 if config["simulation"]["mode"] == "versus" else 4,
        "duration": config["output"]["duration"],
        "simulation": config["simulation"],
        "custom": {name: config.get(name) for name in ("ring_escape", "stack_domino", "versus")},
    }
    encoded = json.dumps(data, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return hashlib.sha256(encoded).hexdigest()[:24]
