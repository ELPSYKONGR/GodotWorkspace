"""Pure visual renderer for SceneData; this module never imports the physics engine."""

from __future__ import annotations

import math
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from src.data.config import resolve_font

LOGICAL_SIZE = (720, 1280)


def _hex(value: str, fallback: tuple[int, int, int]) -> tuple[int, int, int]:
    """Parse a #RRGGBB value, returning fallback for malformed input."""
    try:
        value = str(value).lstrip("#")
        if len(value) != 6:
            raise ValueError
        return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))
    except (TypeError, ValueError):
        return fallback


def _mix(base: tuple[int, int, int], accent: tuple[int, int, int], ratio: float) -> tuple[int, int, int]:
    """Blend two colors; used to fake glow and fade without an alpha channel."""
    ratio = max(0.0, min(1.0, ratio))
    return tuple(round(base[i] + (accent[i] - base[i]) * ratio) for i in range(3))


def _spawn_growth(progress: float) -> float:
    """Ease-out-back growth so a newborn ball pops out instead of blinking into place."""
    progress = max(0.0, min(1.0, progress))
    shifted = progress - 1.0
    return 1.0 + 3.4 * shifted**3 + 2.4 * shifted**2


_GLOW_CACHE: dict[tuple[int, int, int], Image.Image] = {}


def _glow_sprite(color: tuple[int, int, int]) -> Image.Image:
    """Build (and cache) one radial falloff sprite so a newborn reads as a light burst."""
    sprite = _GLOW_CACHE.get(color)
    if sprite is None:
        size = 96
        axis = (np.arange(size) - (size - 1) / 2.0) / (size / 2.0)
        radius = np.hypot(axis[None, :], axis[:, None])
        rgba = np.zeros((size, size, 4), dtype=np.uint8)
        rgba[..., 0], rgba[..., 1], rgba[..., 2] = color
        rgba[..., 3] = (np.clip(1.0 - radius, 0.0, 1.0) ** 2 * 255).astype(np.uint8)
        sprite = Image.fromarray(rgba, "RGBA")
        _GLOW_CACHE[color] = sprite
    return sprite


def _text_value(template: str, frame: Any, extra: dict[str, Any] | None = None) -> str:
    """Expand safe display placeholders from a SceneFrame."""
    values: dict[str, Any] = {
        "count": getattr(frame, "count", 0),
        "remaining": getattr(frame, "remaining", 0),
        "escaped": getattr(frame, "escaped", 0),
        "time": float(getattr(frame, "time", 0)),
        "phase": "释放" if getattr(frame, "is_released", False) else "累积",
        "left": 0,
        "right": 0,
        "margin": 0.0,
        "winner": "",
    }
    if extra:
        values.update(extra)
    return str(template).format_map(values)


def _generation_color(base: tuple[int, int, int], generation: int, fade: float) -> tuple[int, int, int]:
    """Lighten toward white by generation while preserving the lane's base hue."""
    tint = 0.85 * (1.0 - (1.0 - fade) ** max(0, generation))
    return _mix(base, (255, 255, 255), tint)


def _verdict_headline(result: dict[str, Any]) -> str:
    """Describe a finished race; a missing margin means the rival never reached the line."""
    winner = str(result.get("winner", "undecided"))
    margin = result.get("margin")
    side = "左侧" if winner == "left" else "右侧"
    if margin is None:
        reached = result.get("left_full_at") if winner == "left" else result.get("right_full_at")
        return f"{side} {float(reached):.2f} 秒填满" if reached is not None else f"{side} 先填满"
    if float(margin) < 0.01:
        return "两侧几乎同时填满"
    return f"{side} 领先 {float(margin):.2f} 秒"


class FrameRenderer:
    """Render a cached SceneFrame to a portrait Pillow image."""

    def __init__(self, config: dict[str, Any]):
        self.config = config
        output = config.get("output", config)
        self.width = int(output.get("width", 720))
        self.height = int(output.get("height", round(self.width * 16 / 9)))
        self.scale = self.width / LOGICAL_SIZE[0]
        self.appearance = config.get("appearance", {})
        sim = config.get("simulation", {})
        self.simulation = dict(sim)
        self.center = tuple(sim.get("center", [360, 664]))
        self.radius = float(sim.get("radius", 263))
        self.texts = config.get("texts", [])
        palette = self.appearance.get("palette", ["#74eabf", "#ffb46f", "#f5809f", "#80baff", "#cca5ff", "#f8e188"])
        self.palette = [_hex(color, (120, 200, 220)) for color in palette]
        self.font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}
        self.background = self._background()

    def _font(self, spec: dict[str, Any]) -> ImageFont.FreeTypeFont:
        """Load and cache a configured font without accepting arbitrary paths."""
        size = max(1, round(float(spec.get("size", 24)) * self.scale))
        key = (str(spec.get("font", "auto")), size)
        if key not in self.font_cache:
            self.font_cache[key] = ImageFont.truetype(str(resolve_font(key[0])), size)
        return self.font_cache[key]

    def _background(self) -> Image.Image:
        """Create a configurable vertical gradient background."""
        top = np.array(_hex(self.appearance.get("background_top", "#0c1322"), (12, 19, 34)), dtype=np.float32)
        bottom = np.array(_hex(self.appearance.get("background_bottom", "#182338"), (24, 35, 56)), dtype=np.float32)
        ramp = np.linspace(0, 1, self.height)[:, None, None]
        return Image.fromarray(np.repeat(((1 - ramp) * top + ramp * bottom).astype(np.uint8), self.width, axis=1))

    def _draw_texts(self, image: Image.Image, frame: Any, extra: dict[str, Any] | None = None) -> None:
        """Draw configured text boxes and keep every string in the data layer."""
        draw = ImageDraw.Draw(image)
        for spec in self.texts:
            if not spec.get("is_visible", True):
                continue
            text = _text_value(spec.get("text", ""), frame, extra)
            xy = (round(float(spec.get("x", 360)) * self.scale), round(float(spec.get("y", 160)) * self.scale))
            font = self._font(spec)
            anchor = spec.get("anchor", "mm")
            align = {"mm": "center", "lm": "left", "rm": "right"}[anchor]
            bounds = draw.multiline_textbbox(xy, text, font=font, anchor=anchor, align=align)
            if bounds[0] < 0 or bounds[1] < 0 or bounds[2] > self.width or bounds[3] > self.height:
                raise ValueError(f"文字 {spec.get('id', '')!r} 超出画布；请调整内容、字号或位置")
            draw.multiline_text(
                xy,
                text,
                font=font,
                fill=_hex(spec.get("color", "#ebf0f8"), (235, 240, 248)),
                anchor=anchor,
                align=align,
            )

    def _draw_ring(self, draw: ImageDraw.ImageDraw, frame: Any) -> None:
        """Draw the intact, rotating, or released ring according to the frame flags."""
        cx, cy = self.center
        box = tuple(
            round(v * self.scale) for v in (cx - self.radius, cy - self.radius, cx + self.radius, cy + self.radius)
        )
        ring = _hex(self.appearance.get("ring_color", "#849dbc"), (132, 157, 188))
        rotor = _hex(self.appearance.get("rotor_color", "#7890b2"), (120, 144, 178))
        if not getattr(frame, "is_released", False):
            draw.ellipse(box, fill=_hex(self.appearance.get("inner_color", "#121d2f"), (18, 29, 47)))
            if self.simulation.get("mode") == "escape":
                angle = math.degrees(float(getattr(frame, "ring_angle", 0)))
                draw.arc(box, 110 + angle, 430 + angle, fill=ring, width=max(2, round(4 * self.scale)))
            else:
                draw.ellipse(box, outline=ring, width=max(2, round(4 * self.scale)))
            angle = float(getattr(frame, "rotor_angle", 0.0))
            endpoints = [
                (cx + math.cos(angle) * 215, cy + math.sin(angle) * 215),
                (cx - math.cos(angle) * 215, cy - math.sin(angle) * 215),
            ]
            draw.line(
                [tuple(round(v * self.scale) for v in p) for p in endpoints],
                fill=rotor,
                width=max(3, round(15 * self.scale)),
            )
        else:
            elapsed = float(getattr(frame, "time", 0)) - float(self.simulation.get("release_at", 0))
            if elapsed < 0.65:
                for index in range(12):
                    start = index * 30
                    dx = math.cos(math.radians(start + 12)) * elapsed * 210
                    dy = math.sin(math.radians(start + 12)) * elapsed * 210
                    moved = tuple(
                        round(value * self.scale)
                        for value in (
                            cx - self.radius + dx,
                            cy - self.radius + dy,
                            cx + self.radius + dx,
                            cy + self.radius + dy,
                        )
                    )
                    draw.arc(moved, start, start + 22, fill=ring, width=max(2, round(4 * self.scale)))

    def _draw_ring_escape(self, draw: ImageDraw.ImageDraw, frame: Any, metadata: dict[str, Any]) -> None:
        """Draw the redesigned multi-ring gap scene from typed metadata."""
        spec = metadata.get("ring_escape", {})
        coordinate_scale = self.width / 1080.0
        center = tuple(metadata.get("center", [540.0, 960.0]))
        cx, cy = center[0] * coordinate_scale, center[1] * coordinate_scale
        outer = float(metadata.get("radius", 610.0)) * coordinate_scale
        spacing = float(spec.get("ring_spacing", 42.0)) * coordinate_scale
        ring_count = int(spec.get("ring_count", 12))
        gap_width = float(spec.get("gap_width", 0.34))
        rotation = float(getattr(frame, "ring_angle", 0.0))
        event_log = spec.get("event_log", [])
        passed = sum(1 for event in event_log if event.get("type") == "ring_pass" and event.get("time_s", 0) <= frame.time)
        ring_color = _hex(self.appearance.get("ring_color", "#b9c9e6"), (185, 201, 230))
        for index in range(ring_count):
            radius_values = spec.get("ring_radii", [])
            radius = float(radius_values[index]) * coordinate_scale if index < len(radius_values) else outer - index * spacing
            box = (round(cx - radius), round(cy - radius), round(cx + radius), round(cy + radius))
            gap_center = math.degrees(rotation * (1.0 + index * 0.02))
            gap_degrees = math.degrees(gap_width)
            start = gap_center + gap_degrees / 2
            end = gap_center + 360 - gap_degrees / 2
            color = (255, 255, 255) if index == min(ring_count - 1, passed) else ring_color
            draw.arc(box, start, end, fill=color, width=max(2, round(8 * coordinate_scale)))
        self._draw_custom_positions(draw, frame, coordinate_scale, float(self.simulation.get("ball_radius", 25)))

    def _draw_custom_positions(self, draw: ImageDraw.ImageDraw, frame: Any, coordinate_scale: float, radius: float) -> None:
        """Draw moving balls with a coordinate scale matching the simulation contract."""
        positions = np.asarray(getattr(frame, "positions", np.empty((0, 2))), dtype=np.float32)
        colors = np.asarray(getattr(frame, "colors", np.zeros(len(positions), dtype=np.uint8)))
        ball_radius = max(2, round(radius * coordinate_scale))
        for position, color_index in zip(positions, colors):
            if not np.isfinite(position).all():
                continue
            x, y = round(float(position[0]) * coordinate_scale), round(float(position[1]) * coordinate_scale)
            color = self.palette[int(color_index) % len(self.palette)]
            draw.ellipse((x - ball_radius, y - ball_radius, x + ball_radius, y + ball_radius), fill=color)
            highlight = max(1, ball_radius // 3)
            draw.ellipse((x - highlight, y - highlight, x + highlight, y + highlight), fill=tuple(min(255, c + 45) for c in color))

    def _draw_stack_domino(self, draw: ImageDraw.ImageDraw, frame: Any, metadata: dict[str, Any]) -> None:
        """Draw gates, dominoes, glass damage and moving balls for scheme B."""
        spec = metadata.get("stack_domino", {})
        event_log = spec.get("event_log", [])
        now = float(frame.time)
        events = [event for event in event_log if event.get("time", 0) <= now]
        domino_hits = {event.get("object_id") for event in events if event.get("type") == "domino_hit"}
        glass_hits = {event.get("object_id") for event in events if event.get("type") == "glass_hit"}
        glass_breaks = {event.get("object_id") for event in events if event.get("type") == "glass_break"}
        opened = {event.get("object_id") for event in events if event.get("type") == "gate_open"}
        gates = spec.get("gates", [])
        if gates:
            for gate in gates:
                if gate.get("id") in opened:
                    continue
                gx = float(gate.get("x", 220)) * self.scale
                gy = float(gate.get("bar_y", gate.get("y", 300))) * self.scale
                draw.line((round(gx - 45 * self.scale), round(gy), round(gx + 45 * self.scale), round(gy)), fill=(251, 146, 60), width=max(2, round(5 * self.scale)))
        else:
            gate = spec.get("gate", {})
            gx, gy = float(gate.get("x", 220)) * self.scale, float(gate.get("y", 740)) * self.scale
            gw, gh = float(gate.get("width", 54)) * self.scale, float(gate.get("height", 120)) * self.scale
            draw.rectangle((round(gx - gw / 2), round(gy - gh / 2), round(gx + gw / 2), round(gy + gh / 2)), outline=(251, 146, 60), width=max(2, round(4 * self.scale)))
        angle_samples = spec.get("domino_angles", [])
        sample_rate = float(metadata.get("sample_rate", 60.0))
        angle_index = min(len(angle_samples) - 1, max(0, round(now * sample_rate))) if angle_samples else -1
        current_angles = angle_samples[angle_index] if angle_index >= 0 else []
        for item in spec.get("domino_layout", []):
            x, y = float(item["x"]) * self.scale, float(item["y"]) * self.scale
            width, height = float(item["width"]) * self.scale, float(item["height"]) * self.scale
            domino_index = int(str(item.get("id", "domino_0")).split("_")[-1])
            hit = item.get("id") in domino_hits
            color = (251, 146, 60) if hit else (148, 163, 184)
            angle = math.radians(float(current_angles[domino_index])) if domino_index < len(current_angles) else math.radians(float(item.get("angle_deg", 0.0)))
            corners = []
            for local_x, local_y in ((-width / 2, -height / 2), (width / 2, -height / 2), (width / 2, height / 2), (-width / 2, height / 2)):
                corners.append((round(x + local_x * math.cos(angle) - local_y * math.sin(angle)), round(y + local_x * math.sin(angle) + local_y * math.cos(angle))))
            draw.polygon(corners, fill=color)
        for item in spec.get("glass_layout", []):
            if item.get("id") in glass_breaks:
                continue
            x, y = float(item["x"]) * self.scale, float(item["y"]) * self.scale
            width, height = float(item["width"]) * self.scale, float(item["height"]) * self.scale
            hit = item.get("id") in glass_hits
            color = (248, 250, 252) if not hit else (125, 211, 252)
            draw.rectangle((round(x - width / 2), round(y - height / 2), round(x + width / 2), round(y + height / 2)), fill=color, outline=(147, 197, 253), width=max(1, round(2 * self.scale)))
            if hit:
                draw.line((round(x - width / 2), round(y - height / 2), round(x + width / 2), round(y + height / 2)), fill=(30, 64, 175), width=max(1, round(self.scale)))
                draw.line((round(x + width / 2), round(y - height / 2), round(x - width / 2), round(y + height / 2)), fill=(30, 64, 175), width=max(1, round(self.scale)))
        collector = spec.get("collector", {})
        x, y, radius = float(collector.get("x", 675)) * self.scale, float(collector.get("y", 860)) * self.scale, float(collector.get("radius", 42)) * self.scale
        draw.ellipse((round(x - radius), round(y - radius), round(x + radius), round(y + radius)), outline=(34, 211, 238), width=max(2, round(5 * self.scale)))
        self._draw_custom_positions(draw, frame, self.scale, float(self.simulation.get("ball_radius", 10)))

    def _versus_counts(self, frame: Any, metadata: dict[str, Any]) -> dict[str, int]:
        """Look up both lane counters at the frame's sample index."""
        spec = metadata.get("versus", {})
        sample_rate = float(metadata.get("sample_rate", 60.0))
        index = round(float(getattr(frame, "time", 0)) * sample_rate)
        counts = {}
        for side in ("left", "right"):
            values = spec.get(f"count_{side}", [])
            counts[side] = int(values[min(len(values) - 1, max(0, index))]) if values else 0
        return counts

    def _versus_values(self, frame: Any, metadata: dict[str, Any]) -> dict[str, Any]:
        """Expose lane counters and the race rules to the editable text layer."""
        spec = metadata.get("versus", {})
        counts = self._versus_counts(frame, metadata)
        result = spec.get("result", {})
        labels = {"left": "左侧", "right": "右侧", "draw": "两侧", "undecided": ""}
        margin = result.get("margin")
        rules = self.config.get("versus", {})
        return {
            "left": counts["left"],
            "right": counts["right"],
            "winner": labels.get(str(result.get("winner")), ""),
            "margin": float(margin) if isinstance(margin, (int, float)) else 0.0,
            "capacity": max(2, int(spec.get("capacity", 560))),
            "seed_balls": int(rules.get("seed_balls", 70)),
            "left_burst": int(rules.get("left_burst", 4)),
            "right_burst": int(rules.get("right_burst", 2)),
        }

    def _draw_versus(
        self,
        draw: ImageDraw.ImageDraw,
        frame: Any,
        metadata: dict[str, Any],
        glow: Image.Image | None = None,
    ) -> None:
        """Draw two sealed race lanes, their log-scale ladder, live counters and verdict."""
        spec = metadata.get("versus", {})
        scale = self.width / LOGICAL_SIZE[0]
        capacity = max(2, int(spec.get("capacity", 560)))
        counts = self._versus_counts(frame, metadata)
        background = _hex(self.appearance.get("background_top", "#05070c"), (5, 7, 12))
        radius = max(2, round(float(self.simulation.get("ball_radius", 5.5)) * scale))
        geometry: dict[str, tuple[float, float, float, float, tuple[int, int, int]]] = {}
        for side in ("left", "right"):
            lane = spec.get("lanes", {}).get(side, {})
            x0 = float(lane.get("x0", 44.0)) * scale
            x1 = float(lane.get("x1", 340.0)) * scale
            y0 = float(lane.get("y0", 232.0)) * scale
            y1 = float(lane.get("y1", 1158.0)) * scale
            color = self.palette[int(lane.get("color", 0)) % len(self.palette)]
            geometry[side] = (x0, x1, y0, y1, color)
            draw.rectangle((x0, y0, x1, y1), fill=_mix(background, color, 0.05))
            for step in range(1, 8):
                y = y1 - (y1 - y0) * step / 8
                draw.line((x0 + 5 * scale, y, x1 - 5 * scale, y), fill=_mix(background, color, 0.055), width=1)
        positions = np.asarray(getattr(frame, "positions", np.empty((0, 2))), dtype=np.float32)
        indices = np.asarray(getattr(frame, "colors", np.zeros(len(positions), dtype=np.uint8)))
        ages = np.asarray(getattr(frame, "ages", np.empty(0, dtype=np.float32)), dtype=np.float32)
        has_ages = ages.shape == (len(positions),)
        generations = np.asarray(getattr(frame, "generations", np.empty(0, dtype=np.uint16)))
        has_generations = generations.shape == (len(positions),)
        generation_fade = float(self.appearance.get("generation_fade", 0.2))
        spawn_seconds = 0.24
        for order, (position, color_index) in enumerate(zip(positions, indices)):
            if not np.isfinite(position).all():
                continue
            x, y = float(position[0]) * scale, float(position[1]) * scale
            color = self.palette[int(color_index) % len(self.palette)]
            if has_generations:
                color = _generation_color(color, int(generations[order]), generation_fade)
            age = float(ages[order]) if has_ages else spawn_seconds
            ball_radius = max(1.0, radius * _spawn_growth(age / spawn_seconds)) if age < spawn_seconds else radius
            if age < spawn_seconds and glow is not None:
                # A real radial falloff: a flat disc would look like brown fog on a packed lane.
                progress = age / spawn_seconds
                strength = (1.0 - progress) ** 1.5
                diameter = max(4, round(radius * 2.0 * (1.7 + 2.2 * progress)))
                if strength > 0.02:
                    sprite = _glow_sprite(color).resize((diameter, diameter), Image.BILINEAR)
                    sprite.putalpha(sprite.getchannel("A").point(lambda value: int(value * strength)))
                    glow.alpha_composite(sprite, (round(x - diameter / 2), round(y - diameter / 2)))
            draw.ellipse((x - ball_radius, y - ball_radius, x + ball_radius, y + ball_radius), fill=color)
            if age < 0.09:
                spark_phase = age / 0.09
                spark = radius * (1.5 - 0.6 * spark_phase)
                draw.ellipse(
                    (x - spark, y - spark, x + spark, y + spark),
                    fill=_mix(color, (255, 255, 255), 0.85 * (1.0 - spark_phase)),
                )
            elif radius >= 4:
                core = max(1, radius // 3)
                draw.ellipse(
                    (x - core, y - core, x + core, y + core), fill=_mix(color, (255, 255, 255), 0.22)
                )
        for x0, x1, y0, y1, color in geometry.values():
            draw.rectangle(
                (x0 - 4 * scale, y0 - 4 * scale, x1 + 4 * scale, y1 + 4 * scale),
                outline=_mix(background, color, 0.16),
                width=max(2, round(4 * scale)),
            )
            draw.rectangle((x0, y0, x1, y1), outline=color, width=max(1, round(2.4 * scale)))
        for side, (x0, x1, y0, _y1, color) in geometry.items():
            rail_y = y0 + 5 * scale
            rail_h = max(2, round(4 * scale))
            draw.rectangle((x0 + 5 * scale, rail_y, x1 - 5 * scale, rail_y + rail_h), fill=_mix(background, color, 0.16))
            filled = x0 + 5 * scale + (x1 - x0 - 10 * scale) * min(1.0, counts[side] / capacity)
            draw.rectangle((x0 + 5 * scale, rail_y, filled, rail_y + rail_h), fill=color)
            draw.text(
                ((x0 + x1) / 2, y0 - 34 * scale),
                f"{counts[side]:,}",
                font=self._font({"font": "auto", "size": 34}),
                fill=color,
                anchor="mm",
            )
        decided_at = spec.get("decided_at")
        now = float(getattr(frame, "time", 0))
        if decided_at is None or now < float(decided_at):
            return
        result = spec.get("result", {})
        winner = str(result.get("winner", "undecided"))
        accent = geometry["right"][4] if winner == "right" else geometry["left"][4]
        ramp = min(1.0, (now - float(decided_at)) / 0.35)
        plate = (56 * scale, 640 * scale, 664 * scale, 900 * scale)
        draw.rectangle(plate, fill=_mix(background, _mix((8, 12, 18), accent, 0.10), ramp))
        draw.rectangle(plate, outline=_mix(background, accent, 0.75 * ramp), width=max(1, round(1.6 * scale)))
        headline = _verdict_headline(result)
        draw.text(
            (360 * scale, 700 * scale),
            headline,
            font=self._font({"font": "auto", "size": 38}),
            fill=_mix(background, (242, 246, 255), ramp),
            anchor="mm",
        )
        draw.text(
            (360 * scale, 782 * scale),
            "HOW?!",
            font=self._font({"font": "auto", "size": 54}),
            fill=_mix(background, accent, ramp),
            anchor="mm",
        )
        draw.text(
            (360 * scale, 858 * scale),
            f"{counts['left']:,} 颗   VS   {counts['right']:,} 颗",
            font=self._font({"font": "auto", "size": 21}),
            fill=_mix(background, (150, 166, 186), ramp),
            anchor="mm",
        )

    def render(self, frame: Any, scene_metadata: dict[str, Any] | None = None) -> Image.Image:
        """Render one SceneFrame; this is the only public image operation."""
        if scene_metadata:
            self.simulation = {**self.config.get("simulation", {}), **scene_metadata.get("simulation", {})}
            self.center = tuple(scene_metadata.get("center", self.center))
            self.radius = float(scene_metadata.get("radius", self.radius))
        image = self.background.copy()
        draw = ImageDraw.Draw(image)
        custom_renderer = (scene_metadata or {}).get("custom_renderer")
        extra = None
        if custom_renderer == "versus":
            glow = Image.new("RGBA", image.size, (0, 0, 0, 0))
            self._draw_versus(draw, frame, scene_metadata or {}, glow)
            image.paste(glow, (0, 0), glow)
            extra = self._versus_values(frame, scene_metadata or {})
        elif custom_renderer == "stack_domino":
            self._draw_stack_domino(draw, frame, scene_metadata or {})
        elif self.simulation.get("mode") == "ring_escape":
            self._draw_ring_escape(draw, frame, scene_metadata or {})
        else:
            self._draw_ring(draw, frame)
            self._draw_custom_positions(draw, frame, self.scale, float(self.simulation.get("ball_radius", 9.4)))
        self._draw_texts(image, frame, extra)
        return image


def render_frame(scene: Any, config: dict[str, Any], time_seconds: float) -> Image.Image:
    """Convenience helper used by preview endpoints."""
    return FrameRenderer(config).render(scene.frame_at(float(time_seconds)), scene.metadata)
