"""Physics regression checks for the two-lane exponential race."""

from __future__ import annotations

import colorsys
from pathlib import Path
import unittest
from unittest.mock import patch

import numpy as np
from PIL import ImageDraw

from src.core.versus import LANE_BOXES, generate_versus_scene
from src.data.config import load_json
from src.rendering.renderer import FrameRenderer, _generation_color, _verdict_headline


ROOT = Path(__file__).resolve().parents[1]


def build(duration: float = 8.0, **overrides) -> dict:
    """Load the preset and shrink it so the race resolves inside a short clip."""
    config = load_json(ROOT / "config/presets/versus.json")
    config["output"]["duration"] = duration
    config["simulation"]["release_at"] = duration - 1.0
    config["versus"].update(
        {"lane_capacity": 90, "seed_balls": 12, "first_split_at": 0.6, "hold_after_decide": 1.0}
    )
    config["versus"].update(overrides)
    return config


class VersusSchemeTests(unittest.TestCase):
    """Keep the verdict tied to recorded physics instead of a timeline script."""

    def test_verdict_matches_recorded_fill_times(self) -> None:
        """The winner is whichever lane actually recorded the earlier full time."""
        scene = generate_versus_scene(build(left_burst=4, left_cooldown=1.2, right_cooldown=1.0))
        spec = scene.metadata["versus"]
        result = spec["result"]
        self.assertTrue(spec["physical_model"].startswith("pymunk_"))
        self.assertIsNotNone(spec["decided_at"])
        filled = {side: result[f"{side}_full_at"] for side in ("left", "right") if result[f"{side}_full_at"] is not None}
        self.assertTrue(filled)
        self.assertEqual(spec["decided_at"], min(filled.values()))
        if result["winner"] == "draw":
            self.assertEqual(len(filled), 2)
            self.assertAlmostEqual(filled["left"], filled["right"], places=6)
        else:
            self.assertIn(result["winner"], filled)
            self.assertEqual(filled[result["winner"]], min(filled.values()))
        if len(filled) == 2:
            self.assertIsNotNone(result["margin"])
            self.assertAlmostEqual(
                result["margin"],
                abs(result["left_full_at"] - result["right_full_at"]),
                places=4,
            )
        else:
            self.assertIsNone(result["margin"])

    def test_lane_counters_respect_capacity_and_accounting(self) -> None:
        """Neither lane may exceed its capacity and every ball stays accounted for."""
        config = build()
        scene = generate_versus_scene(config)
        spec = scene.metadata["versus"]
        capacity = spec["capacity"]
        left = np.asarray(spec["count_left"])
        right = np.asarray(spec["count_right"])
        self.assertLessEqual(int(left.max()), capacity)
        self.assertLessEqual(int(right.max()), capacity)
        self.assertTrue(np.all(np.diff(left) >= 0))
        self.assertTrue(np.all(np.diff(right) >= 0))
        self.assertTrue(np.array_equal(scene.counts - scene.retired, left + right))
        self.assertTrue(np.all(scene.remaining + scene.escaped + scene.retired == scene.counts))
        self.assertEqual(scene.colors[0], 0)
        self.assertEqual(scene.colors[spec["lane_slots"]], 1)

    def test_balls_stay_inside_their_lane_before_release(self) -> None:
        """Contacts are the only driver, so no ball may drift across the divider early."""
        config = build()
        scene = generate_versus_scene(config)
        released = np.asarray(scene.released)
        positions = scene.positions
        for index in np.flatnonzero(~released):
            frame = positions[index]
            for slot, point in enumerate(frame):
                if not np.isfinite(point).all():
                    continue
                x0, x1 = LANE_BOXES["left" if scene.colors[slot] == 0 else "right"]
                self.assertGreater(point[0], x0 - 14.0)
                self.assertLess(point[0], x1 + 14.0)

    def test_run_is_deterministic(self) -> None:
        """The same seed must reproduce the same verdict for a re-render."""
        config = build()
        first = generate_versus_scene(config).metadata["versus"]
        second = generate_versus_scene(config).metadata["versus"]
        self.assertEqual(first["decided_at"], second["decided_at"])
        self.assertEqual(first["result"], second["result"])

    def test_newborn_stays_next_to_the_split_origin(self) -> None:
        """Children originate beside the removed parent instead of teleporting elsewhere."""
        scene = generate_versus_scene(build(duration=6.0, lane_capacity=60, left_cooldown=0.8, right_cooldown=0.6))
        births = scene.birth_times
        self.assertIsNotNone(births)
        sample_rate = float(scene.metadata["sample_rate"])
        checked = 0
        for event in scene.metadata["versus"]["event_log"]:
            if event["type"] != "split":
                continue
            index = int(np.ceil((event["time"] - 1e-5) * sample_rate))
            origin = np.asarray(event["position"])
            for slot in event["children"]:
                point = scene.positions[index, slot]
                if not np.isfinite(point).all():
                    continue
                self.assertLess(float(np.linalg.norm(point - origin)), 70.0, f"slot {slot} was born far from its origin")
                checked += 1
        self.assertGreater(checked, 10, "the short clip should contain several births")
        self.assertLessEqual(float(np.nanmax(births)), scene.sample_count / sample_rate + 1e-3)

    def test_split_replaces_parent_with_total_children(self) -> None:
        """A 1→N split retires the old ID permanently and gains exactly N−1 balls."""
        scene = generate_versus_scene(build(duration=6.0, lane_capacity=60, left_cooldown=0.8, right_cooldown=0.6))
        spec = scene.metadata["versus"]
        populations = {"left": 1, "right": spec["seed_balls"]}
        all_children = set()
        events = [event for event in spec["event_log"] if event["type"] == "split"]
        self.assertGreater(len(events), 10)
        for event in events:
            parent = event["parent"]
            children = event["children"]
            side = event["side"]
            expected = min(event["requested_children"], spec["capacity"] - populations[side] + 1)
            self.assertEqual(len(children), expected)
            self.assertNotIn(parent, children)
            self.assertFalse(all_children.intersection(children), "historical ball IDs cannot be reused")
            all_children.update(children)
            self.assertTrue(np.all(scene.generations[children] == scene.generations[parent] + 1))
            self.assertTrue(np.allclose(scene.birth_times[children], event["time"], atol=1e-5, rtol=0))
            index = int(np.ceil((event["time"] + 1e-5) * scene.metadata["sample_rate"]))
            self.assertFalse(np.isfinite(scene.positions[index:, parent]).any(), "a retired parent must never reappear")
            populations[side] += len(children) - 1
        self.assertEqual(populations["left"], spec["result"]["left_final"])
        self.assertEqual(populations["right"], spec["result"]["right_final"])
        self.assertEqual(int(scene.retired[-1]), len(events))
        self.assertEqual(int(scene.counts[-1]), 1 + spec["seed_balls"] + len(all_children))

    def test_hitstop_freezes_positions_and_spawn_animation(self) -> None:
        """A visible hold freezes both physics and the children's growth/glow age."""
        config = build(duration=4.0, left_cooldown=0.8, right_cooldown=0.6, split_hitstop=0.12)
        config["output"].update(width=180, height=320)
        scene = generate_versus_scene(config)
        spec = scene.metadata["versus"]
        times = np.arange(scene.sample_count) / scene.metadata["sample_rate"]
        windows = spec["hitstop_windows"]
        self.assertGreater(len(windows), 0)
        renderer = FrameRenderer(config)
        rendered = False
        for window in windows:
            indices = np.flatnonzero((times > window["start"] + 1e-5) & (times < window["end"] - 1e-5))
            if len(indices) < 2:
                continue
            first, last = int(indices[0]), int(indices[-1])
            self.assertTrue(np.array_equal(scene.positions[first], scene.positions[last], equal_nan=True))
            self.assertEqual(scene.motion_times[first], scene.motion_times[last])
            before = scene.frame_at(float(times[first]) + 1e-6)
            after = scene.frame_at(float(times[last]) + 1e-6)
            self.assertTrue(np.array_equal(before.ages, after.ages))
            if not rendered and (spec["decided_at"] is None or times[last] < spec["decided_at"]):
                self.assertEqual(renderer.render(before, scene.metadata).tobytes(), renderer.render(after, scene.metadata).tobytes())
                rendered = True
        self.assertTrue(rendered, "the clip should include a held visual frame before the verdict")

    def test_zero_hitstop_keeps_the_motion_clock_running(self) -> None:
        """The adjustable hold can be disabled without changing split semantics."""
        scene = generate_versus_scene(build(duration=4.0, left_cooldown=0.8, right_cooldown=0.6, split_hitstop=0.0))
        self.assertEqual(scene.metadata["versus"]["hitstop_windows"], [])
        self.assertGreater(int(scene.retired[-1]), 0)
        self.assertTrue(np.allclose(scene.motion_times, np.arange(scene.sample_count) / scene.metadata["sample_rate"]))

    def test_verdict_card_renders_current_score_without_future_counts(self) -> None:
        """The actual result card must agree with the lane counters on that frame."""
        config = build(duration=4.0, lane_capacity=60, left_cooldown=0.05, right_cooldown=0.05, first_split_at=0.0, hold_after_decide=3.0)
        config["output"].update(width=180, height=320)
        scene = generate_versus_scene(config)
        spec = scene.metadata["versus"]
        self.assertIsNotNone(spec["decided_at"])
        frame = scene.frame_at(spec["decided_at"] + 0.1)
        index = round(frame.time * scene.metadata["sample_rate"])
        current = tuple(spec[f"count_{side}"][index] for side in ("left", "right"))
        final = tuple(spec["result"][f"{side}_final"] for side in ("left", "right"))
        self.assertNotEqual(current, final, "the fixture needs real score growth after the displayed verdict")
        drawn_text = []
        original_text = ImageDraw.ImageDraw.text

        def record_text(draw, xy, text, *args, **kwargs):
            drawn_text.append(str(text))
            return original_text(draw, xy, text, *args, **kwargs)

        with patch.object(ImageDraw.ImageDraw, "text", new=record_text):
            image = FrameRenderer(config).render(frame, scene.metadata)
        self.assertEqual(image.size, (180, 320))
        self.assertEqual([text for text in drawn_text if "   VS   " in text], [f"{current[0]:,} 颗   VS   {current[1]:,} 颗"])
        self.assertNotIn(f"{final[0]:,} 颗   VS   {final[1]:,} 颗", drawn_text)
        self.assertIn(_verdict_headline(spec["result"]), drawn_text)

    def test_generation_colors_lighten_without_changing_hue(self) -> None:
        """Every generation grows lighter in the original color family, with adjustable fade."""
        for base in ((34, 197, 94), (255, 122, 51)):
            original_hue = colorsys.rgb_to_hls(*(value / 255 for value in base))[0]
            colors = [_generation_color(base, generation, 0.2) for generation in range(8)]
            self.assertEqual(colors[0], base)
            previous_lightness = -1.0
            for color in colors:
                hue, lightness, _saturation = colorsys.rgb_to_hls(*(value / 255 for value in color))
                self.assertAlmostEqual(hue, original_hue, delta=0.003)
                self.assertGreater(lightness, previous_lightness)
                self.assertGreater(max(color) - min(color), 0, "the deepest generation should still retain its hue")
                previous_lightness = lightness
            self.assertEqual(_generation_color(base, 5, 0.0), base)
            self.assertGreater(sum(_generation_color(base, 2, 0.4)), sum(_generation_color(base, 2, 0.1)))


class VersusVerdictTextTests(unittest.TestCase):
    """回归：结论卡只能复述记录到的判定，不能把「对手没到线」说成「双方都没到」。"""

    def test_one_sided_race_reports_the_side_that_filled(self) -> None:
        """只有一方填满时 margin 为空，文案仍必须承认胜方已经到线。"""
        headline = _verdict_headline(
            {"winner": "left", "margin": None, "left_full_at": 9.5, "right_full_at": None}
        )
        self.assertIn("9.50", headline)
        self.assertNotIn("未能", headline)
        self.assertNotIn("没有", headline)

    def test_close_finish_and_clear_lead(self) -> None:
        """同时到线与拉开差距各有对应说法。"""
        self.assertEqual(_verdict_headline({"winner": "left", "margin": 0.0}), "两侧几乎同时填满")
        self.assertEqual(_verdict_headline({"winner": "right", "margin": 1.234}), "右侧 领先 1.23 秒")


if __name__ == "__main__":
    unittest.main()
