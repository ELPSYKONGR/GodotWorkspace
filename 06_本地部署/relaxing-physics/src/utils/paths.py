"""Project-relative paths; no path is taken from an HTTP request."""

from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = PROJECT_ROOT / "config"
PRESET_DIR = CONFIG_DIR / "presets"
OUTPUT_DIR = PROJECT_ROOT / "outputs"
LOG_DIR = PROJECT_ROOT / "logs"
UI_DIR = PROJECT_ROOT / "src" / "ui"


def ensure_directories() -> None:
    """Create writable directories required by the studio."""
    for directory in (CONFIG_DIR, PRESET_DIR, OUTPUT_DIR, LOG_DIR):
        directory.mkdir(parents=True, exist_ok=True)


def output_path(relative_path: str) -> Path:
    """Resolve a relative output path and reject traversal outside outputs."""
    candidate = (OUTPUT_DIR / relative_path).resolve()
    output_root = OUTPUT_DIR.resolve()
    if candidate != output_root and output_root not in candidate.parents:
        raise ValueError("产物路径必须位于 outputs 目录内")
    return candidate
