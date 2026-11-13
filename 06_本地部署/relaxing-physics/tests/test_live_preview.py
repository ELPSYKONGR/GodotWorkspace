"""Validate exact preview images, trajectory reuse, bounded sessions and HTTP errors."""

from __future__ import annotations

import copy
from io import BytesIO
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from unittest.mock import patch

import numpy as np
from PIL import Image

from src import pipeline
from src.data.config import ROOT, default_config
from src.live_preview import PreviewStore
from src.rendering.renderer import render_frame
from src.server import StudioHandler, ThreadingHTTPServer


class LivePreviewTests(unittest.TestCase):
    """Use real short simulations with a project-local temporary cache."""

    def setUp(self):
        """Isolate caches while retaining the production simulator and renderer."""
        folder = ROOT / "scratch"
        folder.mkdir(exist_ok=True)
        temporary = tempfile.TemporaryDirectory(dir=folder)
        self.addCleanup(temporary.cleanup)
        cache = patch.object(pipeline, "SCENE_CACHE", Path(temporary.name))
        cache.start()
        self.addCleanup(cache.stop)
        self.store = PreviewStore()
        self.config = self.config_for("multiply")

    def config_for(self, mode):
        """Keep the physical parameters but shorten each fixture to two seconds."""
        config = default_config(mode)
        config["output"].update(width=720, height=1280, fps=60, duration=2)
        config["simulation"]["release_at"] = 1.5
        return config

    def test_six_modes_match_export_renderer_pixels(self):
        """Lossless preview must match the export renderer at the same size and time."""
        for mode in ("multiply", "escape", "rain", "ring_escape", "stack_domino", "versus"):
            with self.subTest(mode=mode):
                config = self.config_for(mode)
                result = self.store.prepare(config)
                scene, _, _ = pipeline.get_scene(config)
                reduced = copy.deepcopy(config)
                reduced["output"].update(width=360, height=640)
                for stamp in (0, 1.75, 2):
                    actual = Image.open(BytesIO(self.store.frame(result["session_id"], stamp)))
                    expected = render_frame(scene, reduced, stamp)
                    np.testing.assert_array_equal(np.asarray(actual), np.asarray(expected))
                self.assertEqual(config["output"]["width"], 720)
                self.assertEqual(result["fps"], 30)

    def test_text_changes_reuse_memory_and_leave_previous_session_unchanged(self):
        """Presentation edits neither simulate again nor change a frame already in flight."""
        before = self.store.prepare(self.config)
        original = self.store.frame(before["session_id"], 0.5)
        changed = copy.deepcopy(self.config)
        changed["texts"][0].update(text="即时预览", size=30, color="#ffffff")
        changed["output"].update(width=1080, height=1920, fps=24)
        with patch("src.live_preview.get_scene", side_effect=AssertionError("不能重新读取轨迹")):
            after = self.store.prepare(changed, before["session_id"])
            self.assertNotEqual(original, self.store.frame(after["session_id"], 0.5))
        self.assertEqual(before["data_key"], after["data_key"])
        self.assertTrue(after["is_cache_hit"])
        self.assertEqual(after["fps"], 24)
        self.assertEqual(original, self.store.frame(before["session_id"], 0.5))

    def test_seed_change_generates_new_motion(self):
        """A physical edit invalidates the memory and disk trajectory keys."""
        before = self.store.prepare(self.config)
        self.config["simulation"]["seed"] += 1
        with patch.object(pipeline, "generate_scene", wraps=pipeline.generate_scene) as simulate:
            after = self.store.prepare(self.config, before["session_id"])
        self.assertEqual(simulate.call_count, 1)
        self.assertNotEqual(before["data_key"], after["data_key"])

    def test_bad_times_and_evicted_sessions_fail(self):
        """Do not silently clamp invalid API times or retain unlimited sessions."""
        store = PreviewStore(max_sessions=2)
        first = store.prepare(self.config)
        for stamp in (True, -1, 2.001, float("nan"), float("inf")):
            with self.subTest(time=stamp), self.assertRaises(ValueError):
                store.frame(first["session_id"], stamp)
        second = store.prepare(self.config, first["session_id"])
        store.prepare(self.config, second["session_id"])
        with self.assertRaises(KeyError):
            store.frame(first["session_id"], 0)
        self.assertEqual(len(store.sessions), 2)

    def test_http_prepare_frame_validation_and_origin(self):
        """Exercise the actual HTTP routes and preserve localhost origin restrictions."""
        with patch("src.server.LIVE_PREVIEWS", self.store):
            server = ThreadingHTTPServer(("127.0.0.1", 0), StudioHandler)
            worker = threading.Thread(target=server.serve_forever, daemon=True)
            worker.start()
            base = f"http://127.0.0.1:{server.server_port}"
            try:
                payload = json.dumps({"config": self.config}).encode()
                request = Request(base + "/api/live-preview", payload, {"Content-Type": "application/json"})
                with urlopen(request, timeout=10) as response:
                    session_id = json.load(response)["session_id"]
                with urlopen(base + f"/api/live-preview/{session_id}?time=0.5", timeout=10) as response:
                    self.assertEqual(response.headers["Content-Type"], "image/png")
                    self.assertEqual(Image.open(BytesIO(response.read())).size, (360, 640))
                for suffix, code in ((session_id + "?time=nan", 400), ("unknown?time=0", 404)):
                    with self.assertRaises(HTTPError) as error:
                        urlopen(base + "/api/live-preview/" + suffix, timeout=10)
                    self.assertEqual(error.exception.code, code)
                request = Request(base + f"/api/live-preview/{session_id}", headers={"Origin": "https://example.com"})
                with self.assertRaises(HTTPError) as error:
                    urlopen(request, timeout=10)
                self.assertEqual(error.exception.code, 403)
                with urlopen(base + "/live-preview.js", timeout=10) as response:
                    self.assertIn("export function createLivePreview", response.read().decode())
            finally:
                server.shutdown()
                server.server_close()
                worker.join(timeout=2)
