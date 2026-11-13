"""Exercise saved motion contracts and actual physics independently of video export."""

from __future__ import annotations

import copy
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np

from src.core.simulation import generate_scene
from src.data.config import default_config, simulation_key
from src.data.scene import SceneData

ROOT = Path(__file__).resolve().parents[1]
ARRAY_FIELDS = (
    "positions",
    "counts",
    "remaining",
    "escaped",
    "rotor_angles",
    "ring_angles",
    "released",
    "colors",
    "events",
)


class SceneDataTests(unittest.TestCase):
    """Reuse each complete production preset once across invariant checks."""

    @classmethod
    def setUpClass(cls) -> None:
        """Build all real presets, keeping test temporary files on the project disk."""
        cls.configs = {mode: default_config(mode) for mode in ("multiply", "escape", "rain")}
        cls.scenes = {mode: generate_scene(config) for mode, config in cls.configs.items()}
        scratch = ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="scene-tests-", dir=scratch)
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)

    def test_three_modes_have_distinct_mechanisms(self) -> None:
        """Multiplication creates children, escape removes balls, rain injects balls."""
        multiply, escape, rain = (self.scenes[name] for name in ("multiply", "escape", "rain"))
        for mode, scene in self.scenes.items():
            with self.subTest(mode=mode):
                self.assertEqual(scene.counts[0], self.configs[mode]["simulation"]["initial_balls"])
                self.assertLessEqual(int(scene.counts.max()), self.configs[mode]["simulation"]["max_balls"])
                np.testing.assert_array_equal(scene.remaining + scene.escaped, scene.counts)
        self.assertGreater(multiply.metadata["summary"]["births"], 0)
        self.assertGreater(multiply.counts[-1], multiply.counts[0])
        self.assertTrue(np.all(escape.counts == escape.counts[0]))
        self.assertGreater(int(escape.escaped[-1]), 0)
        self.assertLess(escape.remaining[-1], escape.remaining[0])
        self.assertGreater(rain.counts[-1], rain.counts[0])
        self.assertEqual(rain.metadata["summary"]["births"], 0)

    def test_release_is_exact_and_stops_new_balls(self) -> None:
        """The configured release sample opens the scene without a one-frame delay."""
        for mode, scene in self.scenes.items():
            with self.subTest(mode=mode):
                rate = scene.metadata["sample_rate"]
                release_at = self.configs[mode]["simulation"]["release_at"]
                release_index = round(release_at * rate)
                self.assertFalse(scene.frame_at(release_at - 1 / rate).is_released)
                self.assertTrue(scene.frame_at(release_at).is_released)
                self.assertTrue(np.all(scene.released[release_index:]))
                self.assertTrue(np.all(scene.counts[release_index:] == scene.counts[release_index]))

    def test_closed_modes_keep_balls_inside_until_release(self) -> None:
        """Long runs cannot leak balls through the complete circular boundary."""
        for mode in ("multiply", "rain"):
            scene = self.scenes[mode]
            positions = scene.positions[~scene.released]
            center = np.asarray(scene.metadata["center"])
            distance = np.linalg.norm(positions - center, axis=2)
            with self.subTest(mode=mode):
                self.assertLess(float(np.nanmax(distance)), scene.metadata["radius"] + 12)
                self.assertTrue(np.all(scene.escaped[~scene.released] == 0))

    def test_frame_sampling_has_both_endpoints_and_clamps(self) -> None:
        """Display sampling is defined for off-grid and outside-range timestamps."""
        scene = self.scenes["multiply"]
        self.assertEqual(scene.frame_at(-1).time, 0)
        self.assertEqual(scene.frame_at(0).time, 0)
        self.assertAlmostEqual(scene.frame_at(0.021).time, 1 / 60)
        self.assertEqual(scene.frame_at(24).time, 24)
        self.assertEqual(scene.frame_at(100).time, 24)
        self.assertEqual(scene.sample_count, 24 * 60 + 1)
        for value in (float("nan"), float("inf")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                scene.frame_at(value)

    def test_npz_roundtrip_preserves_data_without_pickle(self) -> None:
        """Saved motion can be reopened exactly with object loading disabled."""
        source = self.scenes["escape"]
        path = source.save(self.directory / "roundtrip.npz")
        loaded = SceneData.load(path)
        self.assertEqual(source.metadata, loaded.metadata)
        for field in ARRAY_FIELDS:
            with self.subTest(field=field):
                np.testing.assert_array_equal(getattr(source, field), getattr(loaded, field))
        with np.load(path, allow_pickle=False) as archive:
            self.assertTrue(all(archive[key].dtype.kind != "O" for key in archive.files))

    def test_corrupted_npz_is_rejected(self) -> None:
        """Inconsistent counters, coordinates, events, and object payloads fail closed."""
        clean_path = self.scenes["multiply"].save(self.directory / "clean.npz")
        with np.load(clean_path, allow_pickle=False) as archive:
            original = {key: archive[key].copy() for key in archive.files}
        mutations = {
            "negative_count": lambda data: data["counts"].__setitem__(0, -1),
            "wrong_shape": lambda data: data.__setitem__("counts", data["counts"][:-1]),
            "counter_mismatch": lambda data: data["remaining"].__setitem__(0, 0),
            "partial_nan": lambda data: data["positions"].__setitem__((0, 0, 0), np.nan),
            "invalid_pan": lambda data: data.__setitem__("events", np.array([[0, 0.5, 2]])),
            "object_payload": lambda data: data.__setitem__("positions", np.array([{}], dtype=object)),
        }
        for label, mutate in mutations.items():
            with self.subTest(corruption=label):
                payload = {key: value.copy() for key, value in original.items()}
                mutate(payload)
                path = self.directory / f"{label}.npz"
                np.savez_compressed(path, **payload)
                with self.assertRaises(ValueError):
                    SceneData.load(path)

    def test_rendering_changes_reuse_identical_motion(self) -> None:
        """FPS, resolution, colors, and text edits leave trajectories and keys unchanged."""
        config = copy.deepcopy(self.configs["multiply"])
        config["output"]["duration"] = 4
        config["simulation"].update(release_at=3, max_balls=80)
        variant = copy.deepcopy(config)
        variant["output"].update(fps=60, width=1080, height=1920)
        variant["texts"][0].update(text="A different title", size=36)
        variant["appearance"]["ring_color"] = "#FFFFFF"
        self.assertEqual(simulation_key(config), simulation_key(variant))
        first, second = generate_scene(config), generate_scene(variant)
        for field in ARRAY_FIELDS:
            with self.subTest(field=field):
                np.testing.assert_array_equal(getattr(first, field), getattr(second, field))

    def test_renderer_import_does_not_load_physics_engine(self) -> None:
        """A clean renderer process stays independent from the Pymunk runtime."""
        process = subprocess.run(
            [
                sys.executable,
                "-B",
                "-c",
                "import sys; import src.rendering.renderer; assert 'pymunk' not in sys.modules",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(process.returncode, 0, process.stdout + process.stderr)


if __name__ == "__main__":
    unittest.main()
