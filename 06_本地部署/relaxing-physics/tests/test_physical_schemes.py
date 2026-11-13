"""Physics-specific regression checks for the two redesigned mechanisms."""

from __future__ import annotations

from pathlib import Path
import unittest

import numpy as np

from src.core.ring_escape import generate_ring_escape_scene
from src.core.stack_domino import generate_stack_domino_scene
from src.data.config import load_json


ROOT = Path(__file__).resolve().parents[1]


class PhysicalSchemeTests(unittest.TestCase):
    """Reject the old timeline-only behavior and impossible state transitions."""

    def test_ring_events_and_motion_are_physics_driven(self) -> None:
        """Ring events use the Pymunk model and positions do not teleport."""
        config = load_json(ROOT / "config/presets/ring_escape.json")
        config["output"]["duration"] = 3.0
        scene = generate_ring_escape_scene(config)
        spec = scene.metadata["ring_escape"]
        self.assertTrue(spec["physical_model"].startswith("pymunk_"))
        self.assertNotIn("ring_shrink", {event["type"] for event in spec["event_log"]})
        self.assertTrue(any(event["type"] == "collision" for event in spec["event_log"]))
        self.assertTrue(np.all(scene.remaining + scene.escaped == scene.counts))
        max_step = float(np.nanmax(np.linalg.norm(np.diff(scene.positions, axis=0), axis=2)))
        self.assertLess(max_step, 30.0)

    def test_stack_events_follow_contact_causality(self) -> None:
        """Gates, dominoes and glass can only change through recorded contacts."""
        config = load_json(ROOT / "config/presets/stack_domino.json")
        config["output"]["duration"] = 8.0
        scene = generate_stack_domino_scene(config)
        spec = scene.metadata["stack_domino"]
        events = spec["event_log"]
        types = [event["type"] for event in events]
        self.assertTrue(spec["physical_model"].startswith("pymunk_"))
        self.assertLessEqual(types.count("gate_open"), len(config["stack_domino"]["multiplier_values"]))
        domino_ids = [event["object_id"] for event in events if event["type"] == "domino_hit"]
        self.assertEqual(len(domino_ids), len(set(domino_ids)))
        hits = {event["object_id"] for event in events if event["type"] == "glass_hit"}
        breaks = {event["object_id"] for event in events if event["type"] == "glass_break"}
        self.assertTrue(breaks.issubset(hits))
        self.assertTrue(np.all(scene.remaining + scene.escaped == scene.counts))


if __name__ == "__main__":
    unittest.main()
