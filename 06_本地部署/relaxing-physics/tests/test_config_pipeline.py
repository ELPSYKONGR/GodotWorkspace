"""Verify editable presentation, invalid input, and actual trajectory cache reuse."""

from __future__ import annotations

import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from src import pipeline
from src.data.config import ROOT, default_config, validate_config
from src.rendering.renderer import render_frame


class ConfigPipelineTests(unittest.TestCase):
    """Exercise integration boundaries with short, real motion data."""

    def setUp(self):
        """Use a project-local temporary cache and a short validated scene."""
        scratch = ROOT / "scratch"
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.cache = patch.object(pipeline, "SCENE_CACHE", Path(self.temporary.name))
        self.cache.start()
        self.addCleanup(self.cache.stop)
        self.config = default_config()
        self.config["output"].update(width=360, height=640, duration=2)
        self.config["simulation"]["release_at"] = 1.5

    def test_invalid_values_fail_before_render(self):
        """Reject unsafe templates, arbitrary font paths, and invalid output values."""
        cases = (
            ("fps", lambda c: c["output"].update(fps=True)),
            ("nan", lambda c: c["simulation"].update(gravity=float("nan"))),
            ("release", lambda c: c["simulation"].update(release_at=2)),
            ("template", lambda c: c["texts"][0].update(text="{count.__class__}")),
            ("format", lambda c: c["texts"][0].update(text="{time:99999999f}")),
            ("font", lambda c: c["texts"][0].update(font="../../private.ttf")),
        )
        for label, mutate in cases:
            with self.subTest(label=label):
                config = copy.deepcopy(self.config)
                mutate(config)
                with self.assertRaises(ValueError):
                    validate_config(config)

    def test_presentation_changes_load_cached_data_without_simulating(self):
        """A real cache survives text, size, font, FPS, resolution, and palette edits."""
        scene, key, was_cached = pipeline.get_scene(self.config)
        self.assertFalse(was_cached)
        before = render_frame(scene, self.config, 0.5)
        variant = copy.deepcopy(self.config)
        variant["texts"][0].update(text="缓存测试", size=34, font="auto")
        variant["output"].update(fps=60, width=720, height=1280)
        variant["appearance"]["ring_color"] = "#FFFFFF"
        with patch.object(pipeline, "generate_scene", side_effect=AssertionError("必须复用缓存")):
            cached, new_key, is_cached = pipeline.get_scene(variant)
        self.assertTrue(is_cached)
        self.assertEqual(new_key, key)
        self.assertEqual(cached.metadata, scene.metadata)
        after = render_frame(cached, variant, 0.5)
        self.assertNotEqual(before.size, after.size)

    def test_physics_edit_gets_a_new_cache_entry(self):
        """Changing the seed must actually regenerate motion data."""
        _, key, _ = pipeline.get_scene(self.config)
        self.config["simulation"]["seed"] += 1
        _, changed_key, is_cached = pipeline.get_scene(self.config)
        self.assertNotEqual(key, changed_key)
        self.assertFalse(is_cached)

    def test_text_outside_canvas_is_reported(self):
        """Oversized text is rejected instead of silently cropping user content."""
        scene, _, _ = pipeline.get_scene(self.config)
        self.config["texts"][0].update(text="超长标题" * 15, size=100)
        with self.assertRaises(ValueError):
            render_frame(scene, validate_config(self.config), 0.5)
