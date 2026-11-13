"""Frame-rate independent video exporter for cached SceneData."""

from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path
from typing import Any

import imageio_ffmpeg
from PIL import Image, ImageDraw

from .audio import synthesize_audio
from .renderer import FrameRenderer


def _ffmpeg() -> str:
    """Return the bundled FFmpeg binary used by the project environment."""
    return imageio_ffmpeg.get_ffmpeg_exe()


def _run_ffmpeg(command: list[str]) -> None:
    """Run a final media operation with an actionable error message."""
    result = subprocess.run(command, capture_output=True)
    if result.returncode:
        message = result.stderr.decode("utf8", "replace")
        raise RuntimeError(f"FFmpeg failed ({result.returncode}): {message[-1500:]}")


def export_scene(scene: Any, config: dict[str, Any], output_dir: Path, progress=None) -> dict[str, Any]:
    """Render cached scene data at any requested FPS and validate the final container."""
    started = time.perf_counter()
    output = config.get("output", config)
    width, height = int(output.get("width", 720)), int(output.get("height", 1280))
    fps = int(output.get("fps", 30))
    duration = float(output.get("duration", scene.metadata.get("duration", 1)))
    if fps < 1 or fps > 120 or width % 2 or height % 2:
        raise ValueError("output width/height must be even and fps must be 1..120")
    if abs(duration - float(scene.metadata.get("duration", duration))) > 1e-6:
        raise ValueError("导出时长必须与运动数据时长一致；请修改导出时长或重新生成运动数据")
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    video_only = output_dir / "video_only.mp4"
    audio_path = output_dir / "sound.wav"
    final = output_dir / "final.mp4"
    renderer = FrameRenderer(config)
    simulation = {**config.get("simulation", {}), **scene.metadata.get("simulation", {})}
    poster_time = min(duration * 0.75, max(0, float(simulation.get("release_at", duration)) - 0.5))
    renderer.render(scene.frame_at(poster_time), scene.metadata).save(output_dir / "poster.png")
    command = [
        _ffmpeg(),
        "-y",
        "-v",
        "error",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "-s",
        f"{width}x{height}",
        "-r",
        str(fps),
        "-i",
        "pipe:0",
        "-an",
        "-c:v",
        "libx264",
        "-preset",
        "fast",
        "-crf",
        "19",
        "-pix_fmt",
        "yuv420p",
        "-movflags",
        "+faststart",
        str(video_only),
    ]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        total = max(1, round(duration * fps))
        for index in range(total):
            image = renderer.render(scene.frame_at(index / fps), scene.metadata)
            process.stdin.write(image.tobytes())
            if progress:
                progress((index + 1) / total)
    finally:
        process.stdin.close()
        stderr = process.stderr.read().decode("utf8", "replace")
        process.stderr.close()
        code = process.wait()
        (output_dir / "ffmpeg.log").write_text(stderr, encoding="utf8")
        if code:
            raise RuntimeError(f"FFmpeg video encode failed ({code}): {stderr[-1000:]}")
    audio_report = synthesize_audio(scene, config, audio_path)
    _run_ffmpeg(
        [
            _ffmpeg(),
            "-y",
            "-v",
            "error",
            "-i",
            str(video_only),
            "-i",
            str(audio_path),
            "-c:v",
            "copy",
            "-c:a",
            "aac",
            "-b:a",
            "192k",
            "-shortest",
            "-movflags",
            "+faststart",
            str(final),
        ]
    )
    _run_ffmpeg([_ffmpeg(), "-v", "error", "-i", str(final), "-f", "null", "-"])
    sheet = Image.new("RGB", (270 * 4, 512 * 2), (13, 21, 35))
    draw = ImageDraw.Draw(sheet)
    for index in range(8):
        stamp = index * duration / 8
        image = renderer.render(scene.frame_at(stamp), scene.metadata)
        image.thumbnail((270, 480))
        x, y = index % 4 * 270, index // 4 * 512
        sheet.paste(image, (x, y))
        draw.text((x + 12, y + 484), f"{stamp:.1f}s", fill=(225, 233, 244))
    sheet.save(output_dir / "contact_sheet.jpg", quality=92)
    report = {
        "output": str(final),
        "video": str(final),
        "poster": str(output_dir / "poster.png"),
        "width": width,
        "height": height,
        "fps": fps,
        "duration": duration,
        "frame_count": total,
        "audio": audio_report,
        "elapsed_seconds": round(time.perf_counter() - started, 3),
        "decode_check": "passed",
    }
    (output_dir / "export_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf8")
    return report
