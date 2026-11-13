"""Verify real media output and re-rendering without the simulation runtime."""

from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import wave

import imageio_ffmpeg
import numpy as np

from src.core.simulation import generate_scene
from src.data.config import ROOT, default_config
from src.rendering.exporter import export_scene
from src.rendering.renderer import render_frame


def decoded_frame_count(video: Path) -> int:
    """Decode every video frame and count FFmpeg's per-frame checksum records."""
    result = subprocess.run(
        [imageio_ffmpeg.get_ffmpeg_exe(), "-v", "error", "-i", str(video), "-map", "0:v:0", "-f", "framemd5", "-"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        check=True,
        timeout=30,
    )
    return sum(bool(line) and not line.startswith("#") for line in result.stdout.splitlines())


class ExportTests(unittest.TestCase):
    """Share two short real encodes across media and isolation assertions."""

    @classmethod
    def setUpClass(cls) -> None:
        """Generate two seconds of motion and keep all temporary media on the project disk."""
        output_root = ROOT / "outputs"
        output_root.mkdir(exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="export-tests-", dir=output_root)
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)
        cls.config = default_config("escape")
        cls.config["output"].update(width=360, height=640, duration=2)
        cls.config["simulation"]["release_at"] = 1.5
        cls.scene = generate_scene(cls.config)
        cls.scene_path = cls.scene.save(cls.directory / "scene.npz")
        cls.reports = {}
        for fps in (24, 60):
            config = copy.deepcopy(cls.config)
            config["output"]["fps"] = fps
            config["audio"]["is_enabled"] = fps != 24
            cls.reports[fps] = export_scene(cls.scene, config, cls.directory / str(fps))

    def test_full_decode_has_requested_frame_count(self) -> None:
        """Both FPS choices encode and completely decode to their expected frame counts."""
        for fps, expected in ((24, 48), (60, 120)):
            with self.subTest(fps=fps):
                report = self.reports[fps]
                self.assertEqual(report["frame_count"], expected)
                self.assertEqual(report["fps"], fps)
                self.assertEqual(report["decode_check"], "passed")
                self.assertEqual(decoded_frame_count(Path(report["video"])), expected)

    def test_scene_metadata_overrides_conflicting_physics_config(self) -> None:
        """A saved escape scene keeps its geometry and release timing with stale editor physics."""
        conflicting = copy.deepcopy(self.config)
        conflicting["simulation"].update(mode="multiply", ball_radius=24, release_at=0.2)
        for stamp in (0.4, 1.55, 1.95):
            with self.subTest(time=stamp):
                expected = render_frame(self.scene, self.config, stamp)
                actual = render_frame(self.scene, conflicting, stamp)
                np.testing.assert_array_equal(np.asarray(actual), np.asarray(expected))

    def test_mismatched_duration_is_rejected(self) -> None:
        """Reject both truncated and frozen-tail exports before creating media."""
        for duration in (1, 3):
            with self.subTest(duration=duration):
                config = copy.deepcopy(self.config)
                config["output"]["duration"] = duration
                with self.assertRaisesRegex(ValueError, "时长"):
                    export_scene(self.scene, config, self.directory / "invalid-duration")
        self.assertFalse((self.directory / "invalid-duration").exists())

    def test_disabled_audio_has_zero_wav_and_aac_samples(self) -> None:
        """The audio switch mutes both the source WAV and the final compressed movie."""
        report = self.reports[24]
        with wave.open(str(self.directory / "24/sound.wav"), "rb") as audio:
            samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2")
        self.assertGreater(samples.size, 0)
        self.assertFalse(samples.any())
        self.assertEqual(report["audio"]["peak"], 0)
        self.assertGreater(self.reports[60]["audio"]["peak"], 0)
        decoded = subprocess.run(
            [
                imageio_ffmpeg.get_ffmpeg_exe(),
                "-v",
                "error",
                "-i",
                report["video"],
                "-map",
                "0:a:0",
                "-f",
                "s16le",
                "-acodec",
                "pcm_s16le",
                "pipe:1",
            ],
            capture_output=True,
            check=True,
            timeout=30,
        )
        decoded_samples = np.frombuffer(decoded.stdout, dtype="<i2")
        self.assertGreater(decoded_samples.size, 0)
        self.assertFalse(decoded_samples.any())

    def test_cli_rerenders_saved_scene_without_pymunk(self) -> None:
        """An isolated CLI process re-renders NPZ data while Pymunk imports are forbidden."""
        stale_config = self.directory / "stale-config.json"
        stale_config.write_text(json.dumps(default_config("multiply"), ensure_ascii=False), encoding="utf-8")
        argv = [
            "render.py",
            "render",
            "--scene",
            str(self.scene_path),
            "--config",
            str(stale_config),
            "--fps",
            "24",
            "--width",
            "360",
            "--output",
            str(self.directory / "cli"),
        ]
        code = (
            "import sys; sys.modules['pymunk'] = None; "
            "from src.cli import main; "
            f"sys.argv = {argv!r}; "
            "status = main(); "
            "assert 'src.core.simulation' not in sys.modules; "
            "assert 'src.pipeline' not in sys.modules; "
            "raise SystemExit(status)"
        )
        process = subprocess.run(
            [sys.executable, "-B", "-c", code],
            cwd=ROOT,
            env={**os.environ, "PYTHONIOENCODING": "utf-8"},
            capture_output=True,
            text=True,
            encoding="utf-8",
            timeout=45,
        )
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)
        report = json.loads(process.stdout)
        self.assertEqual(report["duration"], 2)
        self.assertEqual(report["frame_count"], 48)
        self.assertEqual(decoded_frame_count(Path(report["video"])), 48)


if __name__ == "__main__":
    unittest.main()
