"""Independently inspect rendered PNGs and decode the delivered videos.

Run with the sibling relaxing-physics/.venv Python, which already includes Pillow.
All inputs and outputs resolve from --root (the project directory by default).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageStat


SCENES = ("demo_2d", "demo_3d", "demo_perspective", "demo_custom_60fps")
PHYSICS_BOX = (44, 246, 676, 1136)


def inspect_video(ffmpeg: Path, video: Path) -> dict:
    """Decode every encoded frame and measure actual stream geometry and motion."""
    decoded = subprocess.run(
        [str(ffmpeg), "-hide_banner", "-nostdin", "-i", str(video), "-map", "0:v:0",
         "-an", "-fps_mode", "passthrough", "-f", "null", os.devnull,
         "-progress", "pipe:1", "-nostats"],
        capture_output=True, text=True, encoding="utf-8", errors="replace", check=False,
    )
    if decoded.returncode:
        raise RuntimeError(f"Video decode failed for {video.name}: {decoded.stderr[-2000:]}")
    stream = next((line for line in decoded.stderr.splitlines() if "Stream #" in line and "Video:" in line), "")
    geometry = re.search(r",\s*(\d+)x(\d+)(?:\s|,)", stream)
    fps = re.search(r"([\d.]+)\s+fps", stream)
    if not geometry or not fps:
        raise RuntimeError(f"Cannot read actual video geometry/FPS: {stream}")
    progress = dict(line.split("=", 1) for line in decoded.stdout.splitlines() if "=" in line)
    frame_count = int(progress.get("frame", 0))
    duration = int(progress.get("out_time_us", 0)) / 1_000_000
    pixels = subprocess.run(
        [str(ffmpeg), "-v", "error", "-nostdin", "-i", str(video), "-map", "0:v:0", "-an",
         "-vf", "scale=90:160", "-pix_fmt", "rgb24", "-fps_mode", "passthrough", "-f", "rawvideo", "pipe:1"],
        capture_output=True, check=False,
    )
    if pixels.returncode:
        raise RuntimeError(f"Pixel decode failed: {pixels.stderr.decode('utf-8', errors='replace')[-2000:]}")
    stride = 90 * 160 * 3
    if len(pixels.stdout) % stride:
        raise RuntimeError("Decoded RGB stream contains an incomplete frame")
    means, differences, hashes, black_frames = [], [], set(), []
    previous = None
    for index in range(len(pixels.stdout) // stride):
        raw = pixels.stdout[index * stride:(index + 1) * stride]
        frame = Image.frombytes("RGB", (90, 160), raw)
        means.append(sum(ImageStat.Stat(frame).mean) / 3)
        if max(high for _, high in frame.getextrema()) < 32:
            black_frames.append(index)
        if previous is not None:
            differences.append(sum(ImageStat.Stat(ImageChops.difference(frame, previous)).mean) / 3)
        hashes.add(hashlib.sha256(raw).hexdigest())
        previous = frame
    return {
        "width": int(geometry[1]), "height": int(geometry[2]), "fps": float(fps[1]),
        "decoded_frames": frame_count, "pixel_decoded_frames": len(means), "duration_seconds": duration,
        "progress_end": progress.get("progress") == "end", "decode_ok": True,
        "black_frame_indices": black_frames, "unique_decoded_frame_hashes": len(hashes),
        "mean_brightness_range": [min(means), max(means)] if means else [],
        "max_adjacent_pixel_difference": max(differences, default=0),
        "dynamic": max(differences, default=0) > 0.05,
    }


def inspect_pngs(paths: list[Path], fps: float, is_2d: bool) -> dict:
    """Check all PNG sizes; compare only the physical arena when proving hitstop."""
    dimensions, hashes, entity_peaks = set(), [], []
    black_frames = []
    for index, path in enumerate(paths):
        with Image.open(path) as source:
            frame = source.convert("RGB")
        dimensions.add(frame.size)
        if max(high for _, high in frame.getextrema()) < 32:
            black_frames.append(index)
        if is_2d:
            sx, sy = frame.width / 720, frame.height / 1280
            box = tuple(round(value * (sx if n % 2 == 0 else sy)) for n, value in enumerate(PHYSICS_BOX))
            arena = frame.crop(box)
            hashes.append(hashlib.sha256(arena.tobytes()).hexdigest())
            entity_peaks.append(max(high for _, high in arena.getextrema()))
    holds = []
    start = 0
    while start < len(hashes):
        end = start + 1
        while end < len(hashes) and hashes[end] == hashes[start]:
            end += 1
        # Require visible objects and motion on both sides; startup or final stills do not prove hitstop.
        if end - start >= 2 and start >= 2 and end < len(hashes) and entity_peaks[start] >= 160:
            holds.append({
                "first_frame": start, "last_frame": end - 1, "identical_frames": end - start,
                "start_seconds": start / fps, "frozen_intervals_seconds": (end - start - 1) / fps,
                "motion_before_and_after": hashes[start - 1] != hashes[start] != hashes[end],
            })
        start = end
    return {
        "count": len(paths), "dimensions": [list(size) for size in sorted(dimensions)],
        "black_frame_indices": black_frames,
        "physics_crop_at_720x1280": list(PHYSICS_BOX) if is_2d else None,
        "physics_identical_runs": holds, "hitstop_proven_from_physical_pixels": bool(holds) if is_2d else None,
        "unique_physics_crop_hashes": len(set(hashes)) if is_2d else None,
    }


def main() -> int:
    """Validate four delivered samples and build a three-column evidence sheet."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.root.resolve()
    ffmpeg = root / ".runtime" / "ffmpeg.exe"
    if not ffmpeg.is_file():
        raise FileNotFoundError(ffmpeg)
    results = []
    cell_w, cell_h, label_h = 240, 427, 30
    sheet = Image.new("RGB", (cell_w * 3, (cell_h + label_h) * len(SCENES)), "#162130")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=15)
    for row, name in enumerate(SCENES):
        folder = root / "outputs" / name
        export = json.loads((folder / "export.json").read_text(encoding="utf-8-sig"))
        report = json.loads((folder / "report.json").read_text(encoding="utf-8-sig"))
        frames = sorted((folder / "frames").glob("*.png"))
        encoded_paths = frames[:int(export["encoded_frames"])]
        video = inspect_video(ffmpeg, folder / "final.mp4")
        is_2d = report.get("mode", report.get("config", {}).get("mode")) == "2d"
        pngs = inspect_pngs(encoded_paths, video["fps"], is_2d)
        expected_frames = int(export["requested_frames"])
        expected_fps = float(export["fps"])
        expected_size = [720, 1280]
        checks = {
            "geometry_matches_pngs": pngs["dimensions"] == [[video["width"], video["height"]]],
            "geometry_is_720x1280": [video["width"], video["height"]] == expected_size,
            "fps_matches_request": abs(video["fps"] - expected_fps) < 0.001,
            "frame_count_matches_request": video["decoded_frames"] == video["pixel_decoded_frames"] == expected_frames,
            "duration_matches_request": abs(video["duration_seconds"] - expected_frames / expected_fps) <= 1 / expected_fps,
            "no_black_png_frames": not pngs["black_frame_indices"],
            "no_black_video_frames": not video["black_frame_indices"],
            "video_contains_motion": video["dynamic"],
            "decode_reached_end": video["progress_end"],
        }
        if is_2d:
            checks["physical_hitstop_visible"] = pngs["hitstop_proven_from_physical_pixels"]
            checks["host_recorded_hold"] = int(report.get("hold_frames", 0)) > 0
        representatives = []
        for column, fraction in enumerate((0.12, 0.45, 0.8)):
            index = min(len(encoded_paths) - 1, max(2, round((len(encoded_paths) - 1) * fraction)))
            with Image.open(encoded_paths[index]) as source:
                frame = source.convert("RGB")
            frame.thumbnail((cell_w, cell_h), Image.Resampling.LANCZOS)
            x, y = column * cell_w, row * (cell_h + label_h)
            draw.text((x + 5, y + 7), f"{name} | {index / expected_fps:.2f}s", font=font, fill="#eef7ff")
            sheet.paste(frame, (x + (cell_w - frame.width) // 2, y + label_h))
            representatives.append({"frame": index, "seconds": index / expected_fps,
                                    "png": encoded_paths[index].relative_to(root).as_posix()})
        result = {"scene": name, "passed": all(checks.values()), "checks": checks, "video": video,
                  "pngs": pngs, "raw_written_pngs": len(frames), "host_hold_frames": report.get("hold_frames", 0),
                  "representative_frames": representatives}
        results.append(result)
        print(f"{name}: {'PASS' if result['passed'] else 'FAIL'}; {video['width']}x{video['height']} "
              f"{video['fps']:g}fps, {video['decoded_frames']} frames, {video['duration_seconds']:.3f}s")
    destination = root / "outputs"
    sheet.save(destination / "contact_sheet.jpg", quality=92)
    summary = {
        "passed": all(result["passed"] for result in results), "samples": results,
        "method": "Full FFmpeg decode with -i and -progress; separate RGB decode; original PNG arena crop hashes for 2D hitstop.",
        "hitstop_limit": "Identical physical pixels prove visible pauses; this check does not establish cross-machine deterministic physics.",
        "contact_sheet": "outputs/contact_sheet.jpg",
    }
    (destination / "media_validation.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
