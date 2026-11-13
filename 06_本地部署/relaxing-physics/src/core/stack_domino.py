"""Fixed-step Pymunk simulation for the mechanical multiplier chain.

The multiplier is represented by gates that release preloaded balls after a
trigger ball enters a sensor. This preserves the intended visual multiplication
while avoiding impossible spontaneous creation of matter. Dominoes and glass
panels are dynamic bodies; their events come from collision impulses, and the
collector removes balls only after sensor contact.
"""

from __future__ import annotations

import math
import random
from typing import Any, Callable, Mapping

import numpy as np
import pymunk

from src.data.scene import SceneData

BALL_TYPE = 1
DOMINO_TYPE = 3
GLASS_TYPE = 4
SENSOR_TYPE = 5
PALETTE_SIZE = 6


def _get(value: Any, key: str, default: Any) -> Any:
    """Read a key from either a mapping or a lightweight config object."""
    if isinstance(value, Mapping):
        return value.get(key, default)
    return getattr(value, key, default)


def _section(config: Any, name: str) -> Any:
    """Read a nested configuration section without importing config validation."""
    return _get(config, name, {})


class _StackWorld:
    """Physical world for gates, balls, dominoes, glass and collection."""

    def __init__(self, config: Any) -> None:
        self.sim = _section(config, "simulation")
        self.custom = _section(config, "stack_domino")
        self.rng = random.Random(int(_get(self.sim, "seed", 260811)))
        self.fixed_dt = 1.0 / 120.0
        self.sample_rate = int(_get(self.sim, "sample_rate", 60))
        self.max_balls = int(_get(self.custom, "max_live_balls", _get(self.sim, "max_balls", 48)))
        self.ball_radius = float(_get(self.sim, "ball_radius", 10.0))
        self.gravity = float(_get(self.sim, "gravity", 920.0))
        self.max_speed = float(_get(self.sim, "max_speed", 1200.0))
        self.domino_count = int(_get(self.custom, "domino_count", 24))
        self.glass_count = int(_get(self.custom, "glass_count", 24))
        values = list(_get(self.custom, "multiplier_values", [4, 4]))
        self.wave_counts = [max(0, int(value)) for value in values]
        self.center = pymunk.Vec2d(360.0, 664.0)
        self.time = 0.0
        self.space = pymunk.Space()
        self.space.gravity = (0.0, self.gravity)
        self.space.damping = 0.998
        self.space.iterations = 30
        self.events: list[tuple[float, float, float]] = []
        self.event_log: list[dict[str, Any]] = []
        self.balls: list[dict[str, Any]] = []
        self.dominoes: list[dict[str, Any]] = []
        self.glass: list[dict[str, Any]] = []
        self.by_shape: dict[pymunk.Shape, dict[str, Any]] = {}
        self.sensor_by_shape: dict[pymunk.Shape, tuple[str, int | None]] = {}
        self.gates: list[dict[str, Any]] = []
        self.pending_gate: int | None = None
        self.pending_collect: set[int] = set()
        self.pending_glass: set[int] = set()
        self.break_due: dict[int, float] = {}
        self.opened_gates: set[int] = set()
        self.escaped_count = 0
        self.broken_count = 0
        self.result_started = False
        self._build_boundaries()
        self._build_gates()
        self._build_dominoes()
        self._build_glass()
        self._build_collector()
        self.space.on_collision(BALL_TYPE, SENSOR_TYPE, begin=self._on_sensor)
        self.space.on_collision(BALL_TYPE, DOMINO_TYPE, post_solve=self._on_impact)
        self.space.on_collision(DOMINO_TYPE, DOMINO_TYPE, post_solve=self._on_impact)
        self.space.on_collision(BALL_TYPE, GLASS_TYPE, post_solve=self._on_impact)
        self.space.on_collision(DOMINO_TYPE, GLASS_TYPE, post_solve=self._on_impact)
        self.space.on_collision(GLASS_TYPE, GLASS_TYPE, post_solve=self._on_impact)
        self._add_ball((80.0, 180.0), (300.0, 0.0), color=0)

    def _build_boundaries(self) -> None:
        """Build the static floor and side walls that constrain the stage."""
        body = self.space.static_body
        boundaries = [
            pymunk.Segment(body, (40.0, 920.0), (680.0, 920.0), 5.0),
            pymunk.Segment(body, (40.0, 160.0), (40.0, 920.0), 5.0),
            pymunk.Segment(body, (700.0, 160.0), (700.0, 920.0), 5.0),
        ]
        for shape in boundaries:
            shape.elasticity = 0.25
            shape.friction = 0.75
        self.space.add(*boundaries)

    def _build_gates(self) -> None:
        """Create physical bars and contact sensors for each preloaded wave."""
        definitions = [
            ((200.0, 240.0), (220.0, 230.0), (170.0, 270.0, 270.0, 270.0)),
            ((420.0, 860.0), (430.0, 360.0), (380.0, 400.0, 480.0, 400.0)),
        ]
        for index, (sensor_position, spawn_position, bar_coords) in enumerate(definitions[: len(self.wave_counts)]):
            sensor = pymunk.Circle(self.space.static_body, 30.0, sensor_position)
            sensor.sensor = True
            sensor.collision_type = SENSOR_TYPE
            self.space.add(sensor)
            self.sensor_by_shape[sensor] = ("gate", index)
            x0, y0, x1, y1 = bar_coords
            bar = pymunk.Segment(self.space.static_body, (x0, y0), (x1, y1), 5.0)
            bar.elasticity = 0.15
            bar.friction = 0.7
            self.space.add(bar)
            self.gates.append({"index": index, "sensor": sensor, "bar": bar, "spawn": spawn_position, "opened": False})

    def _build_dominoes(self) -> None:
        """Create dynamic domino bodies standing on the floor."""
        start_x = 270.0
        spacing = 10.0
        for index in range(self.domino_count):
            width, height = 8.0, 58.0
            body = pymunk.Body(0.35, pymunk.moment_for_box(0.35, (width, height)))
            body.position = (start_x + index * spacing, 890.0)
            shape = pymunk.Poly.create_box(body, (width, height))
            shape.elasticity = 0.1
            shape.friction = 0.65
            shape.collision_type = DOMINO_TYPE
            self.space.add(body, shape)
            record = {"id": index, "body": body, "shape": shape, "hit": False}
            self.dominoes.append(record)
            self.by_shape[shape] = record

    def _build_glass(self) -> None:
        """Create breakable dynamic glass panels after the domino line."""
        start_x = 525.0
        spacing = 7.2
        for index in range(self.glass_count):
            width, height = 5.0, 58.0
            body = pymunk.Body(0.12, pymunk.moment_for_box(0.12, (width, height)))
            body.position = (start_x + index * spacing, 890.0)
            shape = pymunk.Poly.create_box(body, (width, height))
            shape.elasticity = 0.05
            shape.friction = 0.45
            shape.collision_type = GLASS_TYPE
            self.space.add(body, shape)
            record = {"id": index, "body": body, "shape": shape, "active": True, "hit": False}
            self.glass.append(record)
            self.by_shape[shape] = record

    def _build_collector(self) -> None:
        """Create a sensor that collects balls after they pass the chain."""
        sensor = pymunk.Circle(self.space.static_body, 38.0, (660.0, 880.0))
        sensor.sensor = True
        sensor.collision_type = SENSOR_TYPE
        self.space.add(sensor)
        self.sensor_by_shape[sensor] = ("collector", None)

    def _add_ball(self, position: tuple[float, float], velocity: tuple[float, float], color: int) -> None:
        """Add one dynamic ball, representing a preloaded or trigger ball."""
        if len(self.balls) >= self.max_balls:
            return
        body = pymunk.Body(1.0, pymunk.moment_for_circle(1.0, 0.0, self.ball_radius))
        body.position = position
        body.velocity = velocity
        shape = pymunk.Circle(body, self.ball_radius)
        shape.elasticity = 0.55
        shape.friction = 0.45
        shape.collision_type = BALL_TYPE
        self.space.add(body, shape)
        record = {"slot": len(self.balls), "body": body, "shape": shape, "active": True, "color": color % PALETTE_SIZE}
        self.balls.append(record)
        self.by_shape[shape] = record

    def _emit(self, kind: str, object_id: str, value: float, position: pymunk.Vec2d) -> None:
        """Store a typed physical event and its compact audio representation."""
        pan = max(-1.0, min(1.0, (float(position.x) - 360.0) / 320.0))
        self.events.append((self.time, max(0.0, min(1.0, value)), pan))
        self.event_log.append({"time": round(self.time, 6), "type": kind, "object_id": object_id, "value": round(value, 4)})

    def _on_sensor(self, arbiter: Any, _space: Any, _data: Any) -> bool:
        """Defer gate opening or collection until after the physics step."""
        sensor_shape = next((shape for shape in arbiter.shapes if shape in self.sensor_by_shape), None)
        ball_shape = next((shape for shape in arbiter.shapes if shape in self.by_shape), None)
        if sensor_shape is None or ball_shape is None:
            return True
        kind, index = self.sensor_by_shape[sensor_shape]
        ball = self.by_shape[ball_shape]
        if kind == "gate" and index is not None and index not in self.opened_gates and index == len(self.opened_gates):
            self.pending_gate = index
        elif kind == "collector":
            self.pending_collect.add(int(ball["slot"]))
        return True

    def _on_impact(self, arbiter: Any, _space: Any, _data: Any) -> None:
        """Turn actual collision impulses into domino and glass state changes."""
        impulse = float(arbiter.total_impulse.length)
        if impulse < 8.0:
            return
        for shape in arbiter.shapes:
            record = self.by_shape.get(shape)
            if record is None:
                continue
            if record in self.dominoes and not record["hit"]:
                record["hit"] = True
                self._emit("domino_hit", f"domino_{record['id']:02d}", min(1.0, impulse / 100.0), record["body"].position)
            if record in self.glass and record["active"] and not record["hit"]:
                record["hit"] = True
                self.pending_glass.add(int(record["id"]))
                self._emit("glass_hit", f"glass_{record['id']:02d}", min(1.0, impulse / 120.0), record["body"].position)

    def _open_gate(self, index: int) -> None:
        """Open a gate after its sensor has been physically contacted."""
        if index in self.opened_gates or index >= len(self.gates):
            return
        gate = self.gates[index]
        gate["opened"] = True
        self.opened_gates.add(index)
        self.space.remove(gate["bar"])
        x, y = gate["spawn"]
        amount = self.wave_counts[index]
        for local_index in range(amount):
            if len(self.balls) >= self.max_balls:
                break
            offset = (local_index - (amount - 1) / 2.0) * self.ball_radius * 2.2
            self._add_ball((x + offset, y), (170.0 + self.rng.uniform(-25.0, 25.0), 0.0), (index + local_index + 1))
        self._emit("gate_open", f"gate_{index}", min(1.0, amount / 8.0), pymunk.Vec2d(x, y))

    def _process_pending(self) -> None:
        """Apply deferred contact consequences outside Pymunk callbacks."""
        if self.pending_gate is not None:
            gate = self.pending_gate
            self.pending_gate = None
            self._open_gate(gate)
        for slot in sorted(self.pending_collect):
            if slot >= len(self.balls):
                continue
            ball = self.balls[slot]
            if not ball["active"]:
                continue
            position = ball["body"].position
            self.space.remove(ball["shape"], ball["body"])
            ball["active"] = False
            self.escaped_count += 1
            self._emit("collector_update", "collector", 0.7, position)
        self.pending_collect.clear()
        for glass_id in sorted(self.pending_glass):
            if glass_id >= len(self.glass):
                continue
            panel = self.glass[glass_id]
            if not panel["active"]:
                continue
            self.break_due[glass_id] = self.time + 0.10
        self.pending_glass.clear()
        for glass_id in sorted(self.break_due):
            if self.break_due[glass_id] > self.time:
                continue
            if glass_id >= len(self.glass):
                continue
            panel = self.glass[glass_id]
            if not panel["active"]:
                self.break_due.pop(glass_id, None)
                continue
            position = panel["body"].position
            self.space.remove(panel["shape"], panel["body"])
            panel["active"] = False
            self.broken_count += 1
            self._emit("glass_break", f"glass_{glass_id:02d}", 0.82, position)
            self.break_due.pop(glass_id, None)

    def _remove_out_of_bounds(self) -> None:
        """Collect balls that leave the bounded stage instead of hiding them."""
        for ball in self.balls:
            if not ball["active"]:
                continue
            position = ball["body"].position
            if position.y > 1060.0 or position.x < 0.0 or position.x > 740.0:
                self.space.remove(ball["shape"], ball["body"])
                ball["active"] = False
                self.escaped_count += 1
                self._emit("collector_update", "boundary", 0.35, position)

    def advance(self) -> None:
        """Advance one fixed 120 Hz step and apply collision consequences."""
        self.time += self.fixed_dt
        self.space.step(self.fixed_dt)
        self._process_pending()
        self._remove_out_of_bounds()
        for ball in self.balls:
            if ball["active"]:
                speed = float(ball["body"].velocity.length)
                if speed > self.max_speed:
                    ball["body"].velocity *= self.max_speed / speed
        if self.broken_count >= self.glass_count and not self.result_started:
            self.result_started = True
            self._emit("result", "result", 1.0, pymunk.Vec2d(600.0, 800.0))

    def snapshot(self) -> tuple[np.ndarray, int, int, int, list[float], bool]:
        """Return ball positions, counters and domino angles for one sample."""
        positions = np.full((self.max_balls, 2), np.nan, dtype=np.float32)
        colors = []
        for ball in self.balls:
            colors.append(ball["color"])
            if ball["active"]:
                positions[ball["slot"]] = ball["body"].position.x, ball["body"].position.y
        angles = [math.degrees(float(item["body"].angle)) for item in self.dominoes]
        remaining = sum(bool(ball["active"]) for ball in self.balls)
        return positions, len(self.balls), remaining, self.escaped_count, angles, self.result_started


def generate_stack_domino_scene(config: Any, progress: Callable[[float], None] | None = None) -> SceneData:
    """Generate a mechanically triggered, collision-driven chain trajectory."""
    output = _section(config, "output")
    simulation = _section(config, "simulation")
    duration = float(_get(output, "duration", 18.0))
    sample_rate = int(_get(simulation, "sample_rate", 60))
    if duration <= 0 or duration > 120 or sample_rate not in {30, 60, 120}:
        raise ValueError("duration must be between 0 and 120 seconds; sample_rate must be 30, 60, or 120")
    world = _StackWorld(config)
    sample_count = round(duration * sample_rate) + 1
    positions = np.full((sample_count, world.max_balls, 2), np.nan, dtype=np.float32)
    counts = np.zeros(sample_count, dtype=np.int32)
    remaining = np.zeros(sample_count, dtype=np.int32)
    escaped = np.zeros(sample_count, dtype=np.int32)
    rotor_angles = np.zeros(sample_count, dtype=np.float32)
    ring_angles = np.zeros(sample_count, dtype=np.float32)
    released = np.zeros(sample_count, dtype=np.bool_)
    domino_angles: list[list[float]] = []
    colors = np.zeros(world.max_balls, dtype=np.uint8)
    for index, ball in enumerate(world.balls):
        colors[index] = ball["color"]
    steps_per_sample = 120 // sample_rate
    for index in range(sample_count):
        state = world.snapshot()
        positions[index], counts[index], remaining[index], escaped[index], angles, released[index] = state
        domino_angles.append(angles)
        for ball in world.balls:
            colors[ball["slot"]] = ball["color"]
        if progress:
            progress(index / max(1, sample_count - 1))
        if index < sample_count - 1:
            for _ in range(steps_per_sample):
                world.advance()
    if not world.result_started:
        world.time = duration
        world._emit("result", "result", 0.8, pymunk.Vec2d(600.0, 800.0))
    domino_layout = [
        {"id": f"domino_{index:02d}", "x": 270.0 + index * 10.0, "y": 890.0, "width": 8.0, "height": 58.0, "angle_deg": 0.0}
        for index in range(world.domino_count)
    ]
    glass_layout = [
        {"id": f"glass_{index:02d}", "x": 525.0 + index * 7.2, "y": 890.0, "width": 5.0, "height": 58.0, "hp": 1}
        for index in range(world.glass_count)
    ]
    metadata = {
        "duration": duration,
        "sample_rate": sample_rate,
        "simulation": dict(simulation) if isinstance(simulation, Mapping) else {"mode": "stack_domino"},
        "center": [360.0, 664.0],
        "radius": 263.0,
        "custom_renderer": "stack_domino",
        "stack_domino": {
            "domino_layout": domino_layout,
            "domino_angles": domino_angles,
            "glass_layout": glass_layout,
            "gates": [
                {
                    "id": f"gate_{gate['index']}",
                    "x": gate["spawn"][0],
                    "y": gate["spawn"][1],
                    "bar_y": 270.0 if gate["index"] == 0 else 400.0,
                    "opened": gate["opened"],
                }
                for gate in world.gates
            ],
            "collector": {"x": 660.0, "y": 880.0, "radius": 38.0},
            "event_log": world.event_log,
            "result": {
                "status": "success" if world.broken_count >= world.glass_count else "partial",
                "broken_count": world.broken_count,
                "target_count": world.glass_count,
                "reason": "all_glass_broken" if world.broken_count >= world.glass_count else "duration_ended",
            },
            "physical_model": "pymunk_dynamic_balls_dominoes_and_breakable_glass",
        },
        "summary": {
            "mode": "stack_domino",
            "births": len(world.balls),
            "escaped": world.escaped_count,
            "broken_glass": world.broken_count,
            "target_glass": world.glass_count,
        },
    }
    event_array = np.asarray(world.events, dtype=np.float32).reshape((-1, 3))
    return SceneData(metadata, positions, counts, remaining, escaped, rotor_angles, ring_angles, released, colors, event_array)
