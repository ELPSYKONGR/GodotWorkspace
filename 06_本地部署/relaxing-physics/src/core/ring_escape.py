"""Fixed-step Pymunk simulation for the nested rotating-ring escape scheme.

Each ring is a kinematic body made of real segment shapes with a rotating gap.
Balls are dynamic circles. A ring-pass event is recorded only after a ball's
measured distance crosses that ring, and escape/fail events remove the body
from the space. The module returns renderer-neutral :class:`SceneData`.
"""

from __future__ import annotations

import math
import random
from typing import Any, Callable, Mapping

import numpy as np
import pymunk

from src.data.scene import SceneData

BALL_TYPE = 1
RING_TYPE = 2
RING_SEGMENTS = 96
PALETTE_SIZE = 6


def _get(value: Any, key: str, default: Any) -> Any:
    """Read a key from either a mapping or a lightweight config object."""
    if isinstance(value, Mapping):
        return value.get(key, default)
    return getattr(value, key, default)


def _section(config: Any, name: str) -> Any:
    """Read a nested configuration section without importing config validation."""
    return _get(config, name, {})


def _wrap(value: float) -> float:
    """Normalize an angle to the signed half-turn interval."""
    return math.atan2(math.sin(value), math.cos(value))


class _RingWorld:
    """A deterministic Pymunk world containing rotating rings and balls."""

    def __init__(self, config: Any) -> None:
        self.sim = _section(config, "simulation")
        self.rng = random.Random(int(_get(self.sim, "seed", 24017)))
        self.fixed_dt = 1.0 / 120.0
        self.sample_rate = int(_get(self.sim, "sample_rate", 120))
        self.max_balls = int(_get(self.sim, "max_balls", 32))
        self.ball_radius = float(_get(self.sim, "ball_radius", 12.0))
        self.outer_radius = float(_get(self.sim, "outer_radius", 263.0))
        self.ring_count = int(_get(self.sim, "ring_count", 12))
        self.ring_spacing = float(_get(self.sim, "ring_spacing", 18.0))
        self.gap_width = float(_get(self.sim, "gap_width", 0.56))
        self.gap_speed = float(_get(self.sim, "gap_speed", 0.65))
        self.escape_speed = float(_get(self.sim, "escape_speed", 220.0))
        self.max_speed = float(_get(self.sim, "max_speed", 360.0))
        self.gravity = float(_get(self.sim, "gravity", 0.0))
        self.energy_max = float(_get(self.sim, "energy", 180.0))
        self.collision_energy_loss = float(_get(self.sim, "collision_energy_loss", 8.0))
        self.center = pymunk.Vec2d(
            float(_get(self.sim, "center_x", 360.0)),
            float(_get(self.sim, "center_y", 664.0)),
        )
        self.time = 0.0
        self.space = pymunk.Space()
        self.space.gravity = (0.0, self.gravity)
        self.space.damping = 0.999
        self.space.iterations = 20
        self.events: list[tuple[float, float, float]] = []
        self.event_log: list[dict[str, Any]] = []
        self.balls: list[dict[str, Any]] = []
        self.by_shape: dict[pymunk.Shape, dict[str, Any]] = {}
        self.ring_bodies: list[pymunk.Body] = []
        self.ring_radii = [self.outer_radius - index * self.ring_spacing for index in range(self.ring_count)]
        self.terminal_count = 0
        self.failed_count = 0
        self.result_started = False

        if self.ring_radii[-1] <= self.ball_radius * 2:
            raise ValueError("ring_spacing/ring_count leave no room for the innermost ring")
        if self.max_balls < 1:
            raise ValueError("max_balls must be positive")
        self._build_rings()
        self.space.on_collision(BALL_TYPE, RING_TYPE, post_solve=self._on_impact)
        self.space.on_collision(BALL_TYPE, BALL_TYPE, post_solve=self._on_impact)
        self._seed_balls()

    def _build_rings(self) -> None:
        """Create kinematic segmented rings whose gaps rotate with the body."""
        half_gap = self.gap_width * 0.5
        for ring_index, radius in enumerate(self.ring_radii):
            body = pymunk.Body(body_type=pymunk.Body.KINEMATIC)
            body.position = self.center
            body.angular_velocity = self.gap_speed * (1.0 + ring_index * 0.02)
            shapes: list[pymunk.Segment] = []
            for segment_index in range(RING_SEGMENTS):
                midpoint = (segment_index + 0.5) * math.tau / RING_SEGMENTS
                if abs(_wrap(midpoint)) <= half_gap:
                    continue
                a0 = segment_index * math.tau / RING_SEGMENTS
                a1 = (segment_index + 1) * math.tau / RING_SEGMENTS
                shape = pymunk.Segment(
                    body,
                    (math.cos(a0) * radius, math.sin(a0) * radius),
                    (math.cos(a1) * radius, math.sin(a1) * radius),
                    2.5,
                )
                shape.elasticity = 0.88
                shape.friction = 0.15
                shape.collision_type = RING_TYPE
                shapes.append(shape)
            self.space.add(body, *shapes)
            self.ring_bodies.append(body)

    def _seed_balls(self) -> None:
        """Place non-overlapping balls near the center with outward velocity."""
        initial = int(_get(self.sim, "initial_balls", 12))
        if initial > self.max_balls:
            raise ValueError("initial_balls cannot exceed max_balls")
        target_radius = initial * self.ball_radius / math.pi * 1.12
        start_radius = min(self.ring_radii[-1] - self.ball_radius * 1.15, max(self.ball_radius * 2.5, target_radius))
        if start_radius <= self.ball_radius * 2.0:
            raise ValueError("initial_balls do not fit inside the innermost ring without overlap")
        for slot in range(initial):
            angle = math.tau * slot / max(1, initial)
            position = self.center + pymunk.Vec2d(math.cos(angle), math.sin(angle)) * start_radius
            radial = pymunk.Vec2d(math.cos(angle), math.sin(angle))
            tangent = pymunk.Vec2d(-radial.y, radial.x)
            velocity = radial * self.escape_speed + tangent * self.rng.uniform(-38.0, 38.0)
            body = pymunk.Body(1.0, pymunk.moment_for_circle(1.0, 0.0, self.ball_radius))
            body.position = position
            body.velocity = velocity
            shape = pymunk.Circle(body, self.ball_radius)
            shape.elasticity = 0.82
            shape.friction = 0.12
            shape.collision_type = BALL_TYPE
            self.space.add(body, shape)
            record = {
                "slot": slot,
                "body": body,
                "shape": shape,
                "active": True,
                "next_ring": 0,
                "previous_distance": float((position - self.center).length),
                "energy": self.energy_max,
                "color": slot % PALETTE_SIZE,
                "status": "running",
            }
            self.balls.append(record)
            self.by_shape[shape] = record

    def _emit(self, kind: str, ball: dict[str, Any] | None, strength: float) -> None:
        """Append typed metadata and compact audio data for one physical event."""
        position = self.center
        if ball is not None and ball["active"]:
            position = ball["body"].position
        pan = max(-1.0, min(1.0, (float(position.x) - self.center.x) / max(1.0, self.outer_radius)))
        self.events.append((self.time, max(0.0, min(1.0, strength)), pan))
        entry: dict[str, Any] = {"time_s": round(self.time, 6), "type": kind, "pan": round(pan, 4)}
        if ball is not None:
            entry.update({"ball_id": int(ball["slot"]), "ring_index": int(ball["next_ring"])})
        self.event_log.append(entry)

    def _on_impact(self, arbiter: Any, _space: Any, _data: Any) -> None:
        """Consume collision impulse as energy and record an audio event."""
        impulse = float(arbiter.total_impulse.length)
        if impulse < 2.0:
            return
        ball = next((self.by_shape.get(shape) for shape in arbiter.shapes if shape in self.by_shape), None)
        if ball is None or not ball["active"]:
            return
        loss = min(self.collision_energy_loss * 4.0, impulse * 0.012)
        ball["energy"] -= loss
        self._emit("collision", ball, min(1.0, impulse / 220.0))

    def _finish(self, ball: dict[str, Any], status: str, reason: str) -> None:
        """Remove one ball from the space and record its terminal state."""
        if not ball["active"]:
            return
        ball["active"] = False
        ball["status"] = status
        self.space.remove(ball["shape"], ball["body"])
        self.terminal_count += 1
        if status == "fail":
            self.failed_count += 1
        self._emit(status, ball, 0.92 if status == "escape" else 0.65)
        self.event_log[-1]["reason"] = reason

    def _check_progress(self, ball: dict[str, Any]) -> None:
        """Detect actual radial crossings and terminal out-of-bounds states."""
        position = ball["body"].position
        distance = float((position - self.center).length)
        previous = float(ball["previous_distance"])
        while ball["next_ring"] < self.ring_count:
            threshold = self.ring_radii[ball["next_ring"]] + self.ball_radius
            if not (previous < threshold <= distance):
                break
            self._emit("ring_pass", ball, 0.8)
            ball["next_ring"] += 1
        if distance > self.outer_radius + self.ball_radius * 2.0:
            self._finish(ball, "escape", "outside_outer_ring")
        elif ball["energy"] <= 0.0:
            self._finish(ball, "fail", "collision_energy_depleted")
        elif ball["energy"] <= self.energy_max * 0.25 and ball["status"] == "running":
            ball["status"] = "energy_low"
            self._emit("energy_low", ball, 0.55)
        ball["previous_distance"] = distance

    def advance(self) -> None:
        """Advance the physical world by one fixed 120 Hz step."""
        self.time += self.fixed_dt
        self.space.step(self.fixed_dt)
        for ball in self.balls:
            if ball["active"]:
                speed = float(ball["body"].velocity.length)
                if speed > self.max_speed:
                    ball["body"].velocity *= self.max_speed / speed
                self._check_progress(ball)
        if self.terminal_count >= len(self.balls) and not self.result_started:
            self.result_started = True
            self._emit("result", None, 1.0)

    def snapshot(self) -> tuple[np.ndarray, int, int, int, float, float, bool]:
        """Return the current drawable state using the shared SceneData contract."""
        positions = np.full((self.max_balls, 2), np.nan, dtype=np.float32)
        for ball in self.balls:
            if ball["active"]:
                positions[ball["slot"]] = ball["body"].position.x, ball["body"].position.y
        remaining = sum(bool(ball["active"]) for ball in self.balls)
        angle = self.ring_bodies[0].angle if self.ring_bodies else 0.0
        return positions, len(self.balls), remaining, self.terminal_count, 0.0, angle, self.result_started


def generate_ring_escape_scene(config: Any, progress: Callable[[float], None] | None = None) -> SceneData:
    """Generate a fixed-rate physically simulated ring-escape trajectory."""
    output = _section(config, "output")
    simulation = _section(config, "simulation")
    duration = float(_get(output, "duration", 19.6))
    sample_rate = int(_get(simulation, "sample_rate", 120))
    if duration <= 0 or duration > 120 or sample_rate not in {30, 60, 120}:
        raise ValueError("duration must be between 0 and 120 seconds; sample_rate must be 30, 60, or 120")
    world = _RingWorld(config)
    sample_count = round(duration * sample_rate) + 1
    positions = np.full((sample_count, world.max_balls, 2), np.nan, dtype=np.float32)
    counts = np.zeros(sample_count, dtype=np.int32)
    remaining = np.zeros(sample_count, dtype=np.int32)
    escaped = np.zeros(sample_count, dtype=np.int32)
    rotor_angles = np.zeros(sample_count, dtype=np.float32)
    ring_angles = np.zeros(sample_count, dtype=np.float32)
    released = np.zeros(sample_count, dtype=np.bool_)
    colors = np.zeros(world.max_balls, dtype=np.uint8)
    for ball in world.balls:
        colors[ball["slot"]] = ball["color"]
    steps_per_sample = 120 // sample_rate
    for index in range(sample_count):
        state = world.snapshot()
        positions[index], counts[index], remaining[index], escaped[index], rotor_angles[index], ring_angles[index], released[index] = state
        if progress:
            progress(index / max(1, sample_count - 1))
        if index < sample_count - 1:
            for _ in range(steps_per_sample):
                world.advance()
    if not world.result_started:
        world.time = duration
        world._emit("result", None, 0.8)
        world.event_log[-1]["reason"] = "duration_ended"
    metadata = {
        "duration": duration,
        "sample_rate": sample_rate,
        "simulation": dict(simulation) if isinstance(simulation, Mapping) else {"mode": "ring_escape"},
        "center": [float(world.center.x), float(world.center.y)],
        "radius": float(world.outer_radius),
        "custom_renderer": "ring_escape",
        "ring_escape": {
            "ring_count": world.ring_count,
            "ring_spacing": world.ring_spacing,
            "gap_width": world.gap_width,
            "gap_speed": world.gap_speed,
            "ring_radii": world.ring_radii,
            "event_log": world.event_log,
            "result": {
                "status": "finished" if world.result_started else "incomplete",
                "escaped": sum(ball["status"] == "escape" for ball in world.balls),
                "failed": world.failed_count,
                "reason": "all_balls_terminal" if world.result_started else "duration_ended",
            },
            "physical_model": "pymunk_dynamic_balls_and_kinematic_segment_rings",
        },
        "summary": {
            "mode": "ring_escape",
            "births": len(world.balls),
            "rejected_births": 0,
            "escaped": sum(ball["status"] == "escape" for ball in world.balls),
            "failed": world.failed_count,
            "final_count": len(world.balls),
        },
    }
    event_array = np.asarray(world.events, dtype=np.float32).reshape((-1, 3))
    return SceneData(metadata, positions, counts, remaining, escaped, rotor_angles, ring_angles, released, colors, event_array)
