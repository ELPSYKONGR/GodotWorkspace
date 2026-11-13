"""Deterministic Pymunk scene generation kept independent from rendering."""

from __future__ import annotations

import math
import random
from typing import Any, Callable, Mapping

import numpy as np
import pymunk

from src.data.scene import SceneData

Vec = tuple[float, float]
CENTER: Vec = (360.0, 664.0)
RADIUS = 263.0
RING_SEGMENTS = 96
PALETTE_SIZE = 6


def _get(value: Any, key: str, default: Any) -> Any:
    """Read a key from either a mapping or a lightweight config object."""
    if isinstance(value, Mapping):
        return value.get(key, default)
    return getattr(value, key, default)


def _section(config: Any, name: str) -> Any:
    """Read a nested configuration section without importing the config layer."""
    return _get(config, name, {})


class _World:
    """Private fixed-rate Pymunk world used to fill a SceneData trajectory."""

    def __init__(self, config: Any) -> None:
        self.config = config
        self.sim = _section(config, "simulation")
        self.mode = str(_get(self.sim, "mode", "multiply"))
        if self.mode not in {"multiply", "escape", "rain"}:
            raise ValueError("simulation.mode must be multiply, escape, or rain")
        self.rng = random.Random(int(_get(self.sim, "seed", 42)))
        self.sample_rate = int(_get(self.sim, "sample_rate", 60))
        self.release_at = float(_get(self.sim, "release_at", 20.0))
        self.max_balls = int(_get(self.sim, "max_balls", 460))
        self.radius = float(_get(self.sim, "ball_radius", 9.4))
        self.cooldown = float(_get(self.sim, "birth_cooldown", 1.1))
        self.gravity = float(_get(self.sim, "gravity", 570.0))
        self.rotation_speed = float(_get(self.sim, "rotation_speed", 0.95))
        self.substeps = max(1, int(_get(self.sim, "substeps", 4)))
        self.space = pymunk.Space()
        self.space.gravity = (0.0, self.gravity)
        self.space.damping = 0.997
        self.space.iterations = 20
        self.time = 0.0
        self.released = False
        self.ring_angle = 0.0
        self.balls: list[dict[str, Any]] = []
        self.by_shape: dict[pymunk.Shape, dict[str, Any]] = {}
        self.pending: set[int] = set()
        self.events: list[tuple[float, float, float]] = []
        self.births = 0
        self.rejected_births = 0
        self.escaped_count = 0
        self.ring: list[pymunk.Segment] = []
        self._build_ring()
        self._build_rotor()
        self.space.on_collision(1, 2, begin=self._on_contact, post_solve=self._on_impact)
        self.space.on_collision(1, 1, begin=self._on_contact, post_solve=self._on_impact)
        initial = int(_get(self.sim, "initial_balls", 6))
        spacing = self.radius * 2.4
        offsets = np.arange(-RADIUS + spacing, RADIUS - spacing, spacing)
        candidates = [
            (CENTER[0] + x, CENTER[1] + y)
            for y in offsets
            for x in offsets
            if math.hypot(x, y) < RADIUS - self.radius - 12 and abs(y) > 25
        ]
        if initial > len(candidates):
            raise ValueError("Initial balls cannot fit without overlap at the configured radius")
        for position in candidates[:initial]:
            self._add_ball(position, (self.rng.uniform(-90, 90), self.rng.uniform(-70, 50)))

    def _build_ring(self) -> None:
        """Create a segmented circular boundary; escape mode toggles sensors for its gap."""
        static = self.space.static_body
        for index in range(RING_SEGMENTS):
            a0 = index * math.tau / RING_SEGMENTS
            a1 = (index + 1) * math.tau / RING_SEGMENTS
            shape = pymunk.Segment(
                static,
                (CENTER[0] + math.cos(a0) * RADIUS, CENTER[1] + math.sin(a0) * RADIUS),
                (CENTER[0] + math.cos(a1) * RADIUS, CENTER[1] + math.sin(a1) * RADIUS),
                4,
            )
            shape.elasticity, shape.friction, shape.collision_type = 0.84, 0.18, 2
            self.space.add(shape)
            self.ring.append(shape)
        self._update_gap()

    def _build_rotor(self) -> None:
        """Create the single rotating internal bar shared by all mechanisms."""
        self.rotor = pymunk.Body(body_type=pymunk.Body.KINEMATIC)
        self.rotor.position = CENTER
        self.rotor.angular_velocity = self.rotation_speed
        self.blade = pymunk.Segment(self.rotor, (-215, 0), (215, 0), 8)
        self.blade.elasticity, self.blade.friction, self.blade.collision_type = 0.9, 0.3, 2
        self.space.add(self.rotor, self.blade)

    def _update_gap(self) -> None:
        """Rotate the 40-degree escape gap around the ring without rebuilding geometry."""
        if self.mode != "escape":
            for shape in self.ring:
                shape.sensor = self.released
            return
        gap_center = math.pi / 2 + self.ring_angle
        half_gap = math.radians(20)
        for index, shape in enumerate(self.ring):
            midpoint = (index + 0.5) * math.tau / RING_SEGMENTS
            delta = math.atan2(math.sin(midpoint - gap_center), math.cos(midpoint - gap_center))
            shape.sensor = self.released or abs(delta) <= half_gap

    def _add_ball(self, position: Vec, velocity: Vec, color: int | None = None) -> None:
        """Add one bounded dynamic ball and register it for collision callbacks."""
        if len(self.balls) >= self.max_balls:
            return
        body = pymunk.Body(1.0, pymunk.moment_for_circle(1.0, 0, self.radius))
        body.position, body.velocity = position, velocity
        shape = pymunk.Circle(body, self.radius)
        shape.elasticity, shape.friction, shape.collision_type = 0.83, 0.16, 1
        self.space.add(body, shape)
        slot = len(self.balls)
        record = {
            "body": body,
            "shape": shape,
            "slot": slot,
            "color": slot % PALETTE_SIZE,
            "last_birth": self.time,
            "active": True,
        }
        if color is not None:
            record["color"] = int(color) % PALETTE_SIZE
        self.balls.append(record)
        self.by_shape[shape] = record

    def _on_contact(self, arbiter: Any, _space: Any, _data: Any) -> None:
        """Schedule one eligible ball for multiplication after a new contact."""
        if self.released or self.mode != "multiply":
            return
        for shape in arbiter.shapes:
            record = self.by_shape.get(shape)
            if record and record["active"] and self.time - record["last_birth"] >= self.cooldown:
                self.pending.add(int(record["slot"]))

    def _on_impact(self, arbiter: Any, _space: Any, _data: Any) -> None:
        """Store compact collision events for the audio layer."""
        impulse = float(arbiter.total_impulse.length)
        if impulse < 35:
            return
        shape = arbiter.shapes[0]
        x = float(shape.body.position.x) if shape.body.body_type != pymunk.Body.STATIC else CENTER[0]
        pan = max(-1.0, min(1.0, (x - CENTER[0]) / RADIUS))
        self.events.append((self.time, min(impulse / 800.0, 1.0), pan))

    def _spawn_child(self, parent: dict[str, Any]) -> None:
        """Create a non-overlapping child near a collision parent when space allows."""
        for _ in range(24):
            angle = self.rng.random() * math.tau
            direction = pymunk.Vec2d(math.cos(angle), math.sin(angle))
            pos = parent["body"].position + direction * self.radius * 2.18
            if (pos - pymunk.Vec2d(*CENTER)).length > RADIUS - self.radius - 7:
                continue
            if self.space.point_query_nearest(pos, self.radius + 0.5, pymunk.ShapeFilter()) is not None:
                continue
            self._add_ball(tuple(pos), tuple(parent["body"].velocity * 0.6 + direction * 105))
            self.births += 1
            return
        self.rejected_births += 1

    def _spawn_rain(self) -> None:
        """Inject rain-mode balls just inside the upper boundary at fixed intervals."""
        interval = float(_get(self.sim, "rain_interval", 0.10))
        while self.time + 1e-8 >= getattr(self, "next_rain", 0.0) and len(self.balls) < self.max_balls:
            position = (CENTER[0] + self.rng.uniform(-45, 45), CENTER[1] - RADIUS + self.radius * 2.5)
            if self.space.point_query_nearest(position, self.radius + 0.5, pymunk.ShapeFilter()) is None:
                self._add_ball(position, (self.rng.uniform(-35, 35), self.rng.uniform(20, 65)))
            self.next_rain = getattr(self, "next_rain", 0.0) + interval

    def _release(self) -> None:
        """Open all boundaries and impart a visible outward release impulse."""
        self.released = True
        self._update_gap()
        self.space.remove(self.blade, self.rotor)
        for record in self.balls:
            direction = record["body"].position - pymunk.Vec2d(*CENTER)
            if direction.length > 1:
                record["body"].velocity += direction.normalized() * 160 + (0, -165)

    def _remove_escaped(self) -> None:
        """Remove balls that passed through the rotating escape gap."""
        if self.mode != "escape" or self.released:
            return
        center = pymunk.Vec2d(*CENTER)
        for record in self.balls:
            if not record["active"]:
                continue
            delta = record["body"].position - center
            if delta.length <= RADIUS + self.radius * 1.5:
                continue
            self.space.remove(record["shape"], record["body"])
            record["active"] = False
            self.escaped_count += 1

    def advance(self, dt: float) -> None:
        """Advance the physical world using fixed substeps independent of output FPS."""
        step = dt / self.substeps
        for _ in range(self.substeps):
            if not self.released and self.time + step >= self.release_at - 1e-8:
                self._release()
            self.ring_angle += self.rotation_speed * 0.23 * step
            self._update_gap()
            if self.mode == "rain" and not self.released:
                self._spawn_rain()
            self.time += step
            self.space.step(step)
            for slot in sorted(self.pending):
                if slot < len(self.balls) and len(self.balls) < self.max_balls:
                    parent = self.balls[slot]
                    if parent["active"]:
                        parent["last_birth"] = self.time
                        self._spawn_child(parent)
            self.pending.clear()
            self._remove_escaped()
            for record in self.balls:
                if not record["active"]:
                    continue
                speed = record["body"].velocity.length
                if speed > 1050:
                    record["body"].velocity *= 1050 / speed

    def snapshot(self) -> tuple[np.ndarray, int, int, int, float, float, bool]:
        """Return drawable positions and scalar counters for the current time."""
        positions = np.full((self.max_balls, 2), np.nan, dtype=np.float32)
        for record in self.balls:
            slot = record["slot"]
            if record["active"]:
                positions[slot] = record["body"].position.x, record["body"].position.y
        active_count = sum(record["active"] for record in self.balls)
        return (
            positions,
            len(self.balls),
            active_count,
            self.escaped_count,
            self.rotor.angle,
            self.ring_angle,
            self.released,
        )


def generate_scene(config: Any, progress: Callable[[float], None] | None = None) -> SceneData:
    """Generate deterministic fixed-rate motion data for one configured mechanism."""
    output = _section(config, "output")
    simulation = _section(config, "simulation")
    mode = str(_get(simulation, "mode", "multiply"))
    if mode == "ring_escape":
        from src.core.ring_escape import generate_ring_escape_scene

        return generate_ring_escape_scene(config, progress)
    if mode == "stack_domino":
        from src.core.stack_domino import generate_stack_domino_scene

        return generate_stack_domino_scene(config, progress)
    if mode == "versus":
        from src.core.versus import generate_versus_scene

        return generate_versus_scene(config, progress)
    duration = float(_get(output, "duration", 24.0))
    sample_rate = int(_get(simulation, "sample_rate", 60))
    if duration <= 0 or duration > 120 or sample_rate < 1 or sample_rate > 240:
        raise ValueError("duration must be 0..120 and sample_rate must be 1..240")
    world = _World(config)
    world.sample_rate = sample_rate
    sample_count = round(duration * sample_rate) + 1
    positions = np.full((sample_count, world.max_balls, 2), np.nan, dtype=np.float32)
    counts = np.zeros(sample_count, dtype=np.int32)
    remaining = np.zeros(sample_count, dtype=np.int32)
    escaped = np.zeros(sample_count, dtype=np.int32)
    rotor_angles = np.zeros(sample_count, dtype=np.float32)
    ring_angles = np.zeros(sample_count, dtype=np.float32)
    released = np.zeros(sample_count, dtype=np.bool_)
    colors = np.zeros(world.max_balls, dtype=np.uint8)
    for index in range(sample_count):
        frame, count, capacity, gone, rotor, ring, is_released = world.snapshot()
        positions[index], counts[index], remaining[index], escaped[index] = frame, count, capacity, gone
        rotor_angles[index], ring_angles[index], released[index] = rotor, ring, is_released
        colors[: len(world.balls)] = [record["color"] for record in world.balls]
        if progress:
            progress(index / max(1, sample_count - 1))
        if index < sample_count - 1:
            world.advance(1.0 / sample_rate)
    metadata = {
        "duration": duration,
        "sample_rate": sample_rate,
        "simulation": dict(simulation) if isinstance(simulation, Mapping) else {"mode": world.mode},
        "center": list(CENTER),
        "radius": RADIUS,
        "summary": {
            "mode": world.mode,
            "births": world.births,
            "rejected_births": world.rejected_births,
            "escaped": world.escaped_count,
            "final_count": len(world.balls),
        },
    }
    events = np.asarray(world.events, dtype=np.float32).reshape((-1, 3))
    return SceneData(
        metadata, positions, counts, remaining, escaped, rotor_angles, ring_angles, released, colors, events
    )
