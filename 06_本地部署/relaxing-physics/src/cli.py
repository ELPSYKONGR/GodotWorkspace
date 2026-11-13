"""Command-line entry points for the studio and independent data/render stages."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

from src.data.config import ALLOWED_MODES, ROOT, default_config, load_current, load_json, validate_config
from src.data.scene import SceneData


def arguments() -> argparse.Namespace:
    """Parse stable, minimal options for both new and legacy launch scripts."""
    parser = argparse.ArgumentParser(description="解压动画工作台：编辑、生成数据、渲染")
    parser.add_argument("command", choices=["studio", "simulate", "render"], nargs="?", default="render")
    parser.add_argument("--config", type=Path)
    parser.add_argument("--preset", choices=sorted(ALLOWED_MODES))
    parser.add_argument("--scene", type=Path, help="render only: re-render a saved scene.npz")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--width", type=int, choices=[360, 540, 720, 1080])
    parser.add_argument("--fps", type=int, choices=[24, 25, 30, 50, 60])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--simulate-only", action="store_true")
    parser.add_argument("--port", type=int, default=int(os.getenv("STUDIO_PORT", "8765")))
    parser.add_argument("--open", dest="should_open", action="store_true")
    return parser.parse_args()


def main() -> int:
    """Dispatch work while logging failures and returning a nonzero exit code."""
    from src.utils.logger import get_logger

    logger = get_logger("studio.cli")
    args = arguments()
    try:
        if args.command == "studio":
            from src.server import serve

            serve(port=args.port, should_open=args.should_open)
            return 0
        config = (
            load_json(args.config) if args.config else (default_config(args.preset) if args.preset else load_current())
        )
        if args.seed is not None:
            config["simulation"]["seed"] = args.seed
        if args.width:
            config["output"].update(width=args.width, height=args.width * 16 // 9)
        if args.fps:
            config["output"]["fps"] = args.fps
        if args.preview:
            config["output"].update(width=360, height=640, duration=12)
            config["simulation"]["release_at"] = 9
        scene = None
        if args.scene:
            scene = SceneData.load(args.scene)
            config["simulation"] = scene.metadata["simulation"]
            config["output"]["duration"] = scene.metadata["duration"]
        config = validate_config(config)
        if args.command == "simulate" or args.simulate_only:
            from src import pipeline

            scene, key, is_cache_hit = pipeline.get_scene(config)
            path = args.output or ROOT / "outputs/data" / f"{key}.npz"
            if not path.is_absolute():
                path = ROOT / path
            scene.save(path)
            result = {"scene": str(path), "data_key": key, "is_cache_hit": is_cache_hit}
        elif args.scene:
            from src.rendering.exporter import export_scene

            folder = args.output or ROOT / "outputs/rerender"
            if not folder.is_absolute():
                folder = ROOT / folder
            folder.resolve().relative_to((ROOT / "outputs").resolve())
            result = export_scene(scene, config, folder)
        else:
            from src import pipeline

            last_progress = -1

            def show_progress(value, message):
                """Log only meaningful progress changes instead of every frame."""
                nonlocal last_progress
                percent = int(value * 100) // 5 * 5
                if percent != last_progress:
                    logger.info("%d%% %s", percent, message)
                    last_progress = percent

            result = pipeline.render(config, args.output, show_progress)
        sys.stdout.write(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        return 0
    except KeyboardInterrupt:
        logger.info("用户停止程序")
        return 130
    except Exception:
        logger.exception("任务失败")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
