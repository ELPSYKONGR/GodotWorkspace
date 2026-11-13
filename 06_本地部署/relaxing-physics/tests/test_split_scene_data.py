"""Check retired parents, stable lineage and paused animation clocks in saved scene data."""

from __future__ import annotations

import copy
from pathlib import Path
import tempfile
import unittest

import numpy as np

from src.data.config import ROOT
from src.data.scene import SceneData


def fixture(split: bool = True) -> dict:
    """Build a tiny timeline with one parent replaced by two children and a held frame."""
    positions = np.full((5, 4, 2), np.nan, dtype=np.float32)
    positions[:, 0] = (10, 10)
    payload = {
        "metadata": {"duration": 1.0, "sample_rate": 4},
        "positions": positions,
        "counts": np.ones(5, dtype=np.int32),
        "remaining": np.ones(5, dtype=np.int32),
        "escaped": np.zeros(5, dtype=np.int32),
        "rotor_angles": np.zeros(5),
        "ring_angles": np.zeros(5),
        "released": np.zeros(5, dtype=np.bool_),
        "colors": np.zeros(4, dtype=np.uint8),
        "events": np.empty((0, 3)),
    }
    if split:
        positions[1:, 0] = np.nan
        positions[1:, 1] = (9, 10)
        positions[1:4, 2] = (11, 10)
        payload.update(
            counts=np.array([1, 3, 3, 3, 3]),
            remaining=np.array([1, 2, 2, 2, 1]),
            escaped=np.array([0, 0, 0, 0, 1]),
            retired=np.array([0, 1, 1, 1, 1]),
            generations=np.array([0, 1, 1, 0]),
            birth_times=np.array([-1, 0.25, 0.25, np.nan]),
            motion_times=np.array([0, 0.25, 0.25, 0.5, 0.75]),
            birth_motion_times=np.array([-1, 0.25, 0.25, np.nan]),
        )
    return payload


class SplitSceneDataTests(unittest.TestCase):
    """Validate the data contract without depending on the evolving physical generator."""

    def test_retired_parent_is_accounted_and_generations_follow_visible_slots(self):
        """Retirement is separate from escape; lineage follows stable slots after filtering."""
        scene = SceneData(**fixture())
        np.testing.assert_array_equal(scene.remaining + scene.escaped + scene.retired, scene.counts)
        parent, children, last = scene.frame_at(0), scene.frame_at(0.25), scene.frame_at(1)
        self.assertEqual((parent.count, parent.remaining, parent.retired), (1, 1, 0))
        self.assertEqual((children.count, children.remaining, children.retired, children.escaped), (3, 2, 1, 0))
        np.testing.assert_array_equal(children.generations, [1, 1])
        np.testing.assert_array_equal(last.generations, [1])
        self.assertEqual(scene.generations.dtype, np.uint16)

    def test_ages_pause_with_motion_clock_and_fall_back_for_older_scenes(self):
        """Repeated positions during a hitstop must also freeze newborn growth and glow."""
        scene = SceneData(**fixture())
        np.testing.assert_array_equal(scene.frame_at(0.25).ages, scene.frame_at(0.5).ages)
        np.testing.assert_array_equal(scene.frame_at(0.75).ages, [0.25, 0.25])
        legacy = fixture(split=False)
        legacy["birth_times"] = np.array([-1, np.nan, np.nan, np.nan])
        frame = SceneData(**legacy).frame_at(0.5)
        np.testing.assert_array_equal(frame.ages, [1.5])
        np.testing.assert_array_equal(frame.generations, [])
        self.assertEqual(frame.retired, 0)

    def test_invalid_retirement_lineage_and_clocks_are_rejected(self):
        """Reject fractional lineage, inconsistent ledgers and clocks outside display time."""
        cases = (
            {"retired": [0, 0, 1, 1, 1]},
            {"retired": [0, 1, -1, 1, 1]},
            {"retired": [0, 1, 0.5, 1, 1]},
            {"generations": [0, 1.2, 1, 0]},
            {"generations": [0, -1, 1, 0]},
            {"generations": [0, 65536, 1, 0]},
            {"motion_times": [0, 0.25, 0.2, 0.5, 0.75]},
            {"motion_times": [0, 0.5, 0.5, 0.5, 0.75]},
            {"motion_times": [0, 0.25, np.inf, 0.5, 0.75]},
            {"motion_times": None},
            {"birth_times": None},
            {"birth_motion_times": [-1, 0.25, np.inf, np.nan]},
        )
        for overrides in cases:
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                payload = fixture()
                payload.update(overrides)
                SceneData(**payload)
        payload = fixture()
        payload.update(counts=[2, 3, 3, 3, 3], retired=[1, 1, 0, 1, 1], remaining=[1, 2, 3, 2, 1])
        payload["positions"][2, 3] = (12, 10)
        with self.assertRaisesRegex(ValueError, "retired must increase"):
            SceneData(**payload)

    def test_new_arrays_roundtrip_and_legacy_files_need_no_migration(self):
        """Both new NPZ fields and older archives without them use the non-pickle loader."""
        scratch = ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            scene = SceneData(**fixture())
            loaded = SceneData.load(scene.save(Path(folder) / "lineage.npz"))
            for name in ("retired", "generations", "motion_times", "birth_motion_times", "birth_times"):
                np.testing.assert_array_equal(getattr(scene, name), getattr(loaded, name))
            legacy_path = SceneData(**fixture(split=False)).save(Path(folder) / "legacy.npz")
            with np.load(legacy_path, allow_pickle=False) as archive:
                old = {name: copy.copy(archive[name]) for name in archive.files if name not in {
                    "retired", "generations", "motion_times", "birth_motion_times", "birth_times"
                }}
            np.savez_compressed(legacy_path, **old)
            legacy = SceneData.load(legacy_path)
            np.testing.assert_array_equal(legacy.retired, np.zeros(5, dtype=np.int32))
            self.assertIsNone(legacy.generations)
            self.assertIsNone(legacy.motion_times)
            self.assertIsNone(legacy.birth_motion_times)


if __name__ == "__main__":
    unittest.main()
