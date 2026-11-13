"""Fixed-step Pymunk simulation for the two-lane exponential race.

Both lanes share identical geometry, ball radius, gravity and collision rules.
The only asymmetry is the starting population and the burst size: lane A starts
with a single ball that splits into several children on every eligible contact,
lane B starts with a crowd that divides into two children per contact. Nothing is
pre-scripted: the verdict is the difference between two recorded times, so the
reported margin is whatever the physics actually produced.

Newborns share a short protection period instead of a random long cooldown.
An ongoing contact is checked again when that protection expires; a ball that
has already separated is never split by a delayed contact timer.
"""

from __future__ import annotations

import math
import random
from typing import Any, Callable, Mapping

import numpy as np
import pymunk

from src.data.scene import SceneData

BALL_TYPE = 1
LANE_TYPE = 3
LEFT = "left"
RIGHT = "right"
LANE_BOXES: dict[str, tuple[float, float]] = {"left": (44.0, 340.0), "right": (380.0, 676.0)}
LANE_TOP = 232.0
LANE_BOTTOM = 1158.0
SOUND_INTERVAL = 0.045


def _get(value: Any, key: str, default: Any) -> Any:
    """Read a key from either a mapping or a lightweight config object."""
    if isinstance(value, Mapping):
        return value.get(key, default)
    return getattr(value, key, default)


def _section(config: Any, name: str) -> Any:
    """Read a nested configuration section without importing config validation."""
    return _get(config, name, {})


class _VersusWorld:
    """Two sealed lanes of bouncing balls that multiply on contact."""

    def __init__(self, config: Any) -> None:
        self.sim = _section(config, "simulation")
        self.custom = _section(config, "versus")
        self.rng = random.Random(int(_get(self.sim, "seed", 42)))
        self.fixed_dt = 1.0 / 120.0
        self.sample_rate = int(_get(self.sim, "sample_rate", 60))
        self.capacity = int(_get(self.custom, "lane_capacity", 640))
        self.seed_right = int(_get(self.custom, "seed_balls", 70))
        self.burst = {
            LEFT: int(_get(self.custom, "left_burst", 4)),
            RIGHT: int(_get(self.custom, "right_burst", 2)),
        }
        if min(self.burst.values()) < 2:
            raise ValueError("每次分裂的子球总数至少为2，原球会被移除")
        self.cooldown = {
            LEFT: float(_get(self.custom, "left_cooldown", 0.05)),
            RIGHT: float(_get(self.custom, "right_cooldown", 0.05)),
        }
        self.hold_after_decide = float(_get(self.custom, "hold_after_decide", 2.2))
        self.first_split_at = float(_get(self.custom, "first_split_at", 0.0))
        self.radius = float(_get(self.sim, "ball_radius", 5.5))
        self.gravity = float(_get(self.sim, "gravity", 260.0))
        self.max_speed = float(_get(self.sim, "max_speed", 900.0))
        # Bound travel per solve to one radius so fast small balls do not jump
        # past each other between the outer 120 Hz sampling steps.
        self.physics_substeps = max(1, math.ceil(self.max_speed * self.fixed_dt / self.radius))
        self.substep_dt = self.fixed_dt / self.physics_substeps
        self.release_at = float(_get(self.sim, "release_at", 17.6))
        # Each retired parent is replaced by at least two children. Lifetime births
        # per side therefore stay below twice capacity; never reuse a historical ID.
        self.lane_slots = self.capacity * 2
        self.slots = self.lane_slots * 2
        self.time = 0.0
        self.motion_time = 0.0
        self.hitstop = float(_get(self.custom, "split_hitstop", 0.06))
        self.hitstop_interval = float(_get(self.custom, "split_hitstop_interval", 0.25))
        self.hitstop_until = 0.0
        self.last_hitstop = -math.inf
        self.hitstop_windows: list[dict[str, float]] = []
        self.released = False
        self.count = {LEFT: 0, RIGHT: 0}
        self.created = {LEFT: 0, RIGHT: 0}
        self.retired_count = 0
        self.full_at: dict[str, float | None] = {LEFT: None, RIGHT: None}
        self.decided_at: float | None = None
        self.escaped_count = 0
        self.rejected = 0
        self.balls: list[dict[str, Any]] = []
        self.by_shape: dict[pymunk.Shape, dict[str, Any]] = {}
        self.by_slot: dict[int, dict[str, Any]] = {}
        self.birth = np.full(self.slots, np.nan, dtype=np.float32)
        self.birth_motion = np.full(self.slots, np.nan, dtype=np.float32)
        self.generations = np.zeros(self.slots, dtype=np.uint16)
        self.pending: set[int] = set()
        self.events: list[tuple[float, float, float]] = []
        self.event_log: list[dict[str, Any]] = []
        self.sound_gate = -1.0
        self.walls: list[pymunk.Segment] = []
        self.space = pymunk.Space()
        self.space.gravity = (0.0, self.gravity)
        self.space.damping = 1.0
        self.space.iterations = 18
        self._build_lanes()
        self.space.on_collision(BALL_TYPE, LANE_TYPE, pre_solve=self._on_contact)
        self.space.on_collision(BALL_TYPE, BALL_TYPE, pre_solve=self._on_contact)
        self._seed()

    # ---------------------------------------------------------------- geometry

    def _build_lanes(self) -> None:
        """Create four static walls per lane; every wall becomes a sensor on release."""
        body = self.space.static_body
        for x0, x1 in LANE_BOXES.values():
            for start, end in (
                ((x0, LANE_BOTTOM), (x1, LANE_BOTTOM)),
                ((x0, LANE_TOP), (x1, LANE_TOP)),
                ((x0, LANE_TOP), (x0, LANE_BOTTOM)),
                ((x1, LANE_TOP), (x1, LANE_BOTTOM)),
            ):
                shape = pymunk.Segment(body, start, end, 3.0)
                shape.elasticity, shape.friction, shape.collision_type = 0.99, 0.02, LANE_TYPE
                self.space.add(shape)
                self.walls.append(shape)

    # ------------------------------------------------------------------ bodies

    def _make_ball(
        self,
        side: str,
        position: tuple[float, float],
        velocity: tuple[float, float],
        birth: float | None = None,
        generation: int = 0,
    ) -> dict[str, Any] | None:
        """Attach one dynamic ball to its side slot, respecting the lane capacity."""
        if self.count[side] >= self.capacity:
            return None
        offset = 0 if side == LEFT else self.lane_slots
        slot = offset + self.created[side]
        body = pymunk.Body(1.0, pymunk.moment_for_circle(1.0, 0.0, self.radius))
        body.position = position
        body.velocity = velocity
        shape = pymunk.Circle(body, self.radius)
        shape.elasticity, shape.friction, shape.collision_type = 0.98, 0.03, BALL_TYPE
        self.space.add(body, shape)
        record = {
            "slot": slot,
            "side": side,
            "body": body,
            "shape": shape,
            "active": True,
            "generation": generation,
            "last_birth": self.motion_time if birth is None else self.motion_time - self.cooldown[side],
        }
        self.balls.append(record)
        self.by_shape[shape] = record
        self.by_slot[slot] = record
        self.birth[slot] = self.time if birth is None else birth
        self.birth_motion[slot] = self.motion_time if birth is None else birth
        self.generations[slot] = generation
        self.created[side] += 1
        self.count[side] += 1
        if self.count[side] >= self.capacity and self.full_at[side] is None:
            self.full_at[side] = self.time
        return record

    def _free_point(self, side: str, origin: pymunk.Vec2d | None = None) -> tuple[float, float] | None:
        """Find the roomiest spot on a ring hugging the parent.

        Newborns are always placed next to their parent so a split reads as a
        burst. When every ring position is occupied the roomiest one is used and
        the solver pushes the pair apart; teleporting to a distant free spot
        would look like a random spawn instead of a division.
        """
        x0, x1 = LANE_BOXES[side]
        margin = self.radius * 1.1
        if origin is None:
            for _ in range(24):
                point = (
                    self.rng.uniform(x0 + margin, x1 - margin),
                    self.rng.uniform(LANE_TOP + margin, LANE_BOTTOM - margin),
                )
                if self.space.point_query_nearest(point, self.radius * 1.2, pymunk.ShapeFilter()) is None:
                    return point
            return None
        probe = self.radius * 3.0
        start = self.rng.uniform(0.0, math.tau)
        best_point, best_gap = None, -math.inf
        for ring in (1.95, 2.5, 3.2, 4.0):
            for step in range(12):
                angle = start + step * math.tau / 12
                point = (
                    min(x1 - margin, max(x0 + margin, float(origin.x) + math.cos(angle) * self.radius * ring)),
                    min(LANE_BOTTOM - margin, max(LANE_TOP + margin, float(origin.y) + math.sin(angle) * self.radius * ring)),
                )
                hit = self.space.point_query_nearest(point, probe, pymunk.ShapeFilter())
                gap = probe if hit is None else hit.distance
                if gap >= self.radius * 0.9:
                    return point
                if gap > best_gap:
                    best_gap, best_point = gap, point
        return best_point

    def _seed(self) -> None:
        """Place the single ball on the left and the starting crowd on the right."""
        x0, x1 = LANE_BOXES[LEFT]
        seed = self._make_ball(
            LEFT,
            ((x0 + x1) / 2, LANE_TOP + 150.0),
            (self.rng.uniform(-130, 130), self.rng.uniform(120, 220)),
            birth=-1.0,
        )
        if seed is not None:
            seed["last_birth"] = self.motion_time - self.cooldown[LEFT] + self.first_split_at
        columns = max(1, int(math.sqrt(self.seed_right)))
        x0r, x1r = LANE_BOXES[RIGHT]
        spacing = (x1r - x0r - 46.0) / max(1, columns - 1) if columns > 1 else 0.0
        for index in range(self.seed_right):
            row, column = divmod(index, columns)
            position = (
                x0r + 23.0 + column * spacing + self.rng.uniform(-3.0, 3.0),
                LANE_TOP + 40.0 + row * self.radius * 3.1 + self.rng.uniform(-2.5, 2.5),
            )
            self._make_ball(RIGHT, position, (self.rng.uniform(-130, 130), self.rng.uniform(30, 170)), birth=-1.0)

    # ------------------------------------------------------------------ events

    def _emit(self, kind: str, value: float, position: pymunk.Vec2d | tuple[float, float]) -> None:
        """Record one typed event for the audio layer and the renderer timeline."""
        x = float(position[0])
        pan = max(-1.0, min(1.0, (x - 360.0) / 320.0))
        strength = max(0.0, min(1.0, value))
        self.events.append((self.time, strength, pan))
        self.event_log.append({"time": round(self.time, 6), "type": kind, "value": round(strength, 4)})

    def _tick(self, kind: str, value: float, position: pymunk.Vec2d | tuple[float, float]) -> None:
        """Emit a rate-limited sound so a dense crowd cannot flood the audio buffer."""
        if self.time - self.sound_gate < SOUND_INTERVAL:
            return
        self.sound_gate = self.time
        self._emit(kind, value, position)

    def _on_contact(self, arbiter: Any, _space: Any, _data: Any) -> bool:
        """Split a ready parent on live contact, including one begun during protection.

        A successful split retires the parent, so persistent contact cannot
        split that same ID again. The pending set merges simultaneous contacts.
        """
        if self.released:
            return True
        for shape in arbiter.shapes:
            record = self.by_shape.get(shape)
            if record is None or not record["active"]:
                continue
            if self.motion_time - record["last_birth"] + 1e-9 >= self.cooldown[record["side"]]:
                self.pending.add(int(record["slot"]))
        return True

    def _split(self, record: dict[str, Any]) -> bool:
        """Retire the parent and create new child IDs; the burst is the total child count."""
        side = record["side"]
        if self.count[side] >= self.capacity:
            return False
        origin, velocity = record["body"].position, record["body"].velocity
        self.space.remove(record["shape"], record["body"])
        record["active"] = False
        self.by_shape.pop(record["shape"], None)
        self.count[side] -= 1
        self.retired_count += 1
        made = 0
        children = []
        for _ in range(self.burst[side]):
            if self.count[side] >= self.capacity:
                break
            point = self._free_point(side, origin)
            if point is None:
                self.rejected += 1
                continue
            direction = self.rng.uniform(0, math.tau)
            speed = self.rng.uniform(80.0, 170.0)
            child_velocity = (
                velocity.x * 0.30 + math.cos(direction) * speed,
                velocity.y * 0.30 + math.sin(direction) * speed,
            )
            child = self._make_ball(side, point, child_velocity, generation=record["generation"] + 1)
            if child is not None:
                made += 1
                children.append(child["slot"])
        if made:
            self.event_log.append({
                "time": round(self.time, 6), "type": "split", "side": side,
                "parent": record["slot"], "children": children, "generation": record["generation"] + 1,
                "position": [float(origin.x), float(origin.y)], "requested_children": self.burst[side],
                "value": 0.0,
            })
            self._tick("birth", min(1.0, 0.35 + made * 0.12), origin)
        return bool(made)

    # ------------------------------------------------------------------ phases

    def _release(self) -> None:
        """Drop the lane floors so both chambers empty out of the frame."""
        self.released = True
        for shape in self.walls:
            shape.sensor = True
        for record in self.balls:
            if record["active"]:
                record["body"].velocity += (self.rng.uniform(-70.0, 70.0), 380.0)
        self._emit("release", 1.0, (360.0, LANE_BOTTOM))

    def _collect_escaped(self) -> None:
        """Remove balls that have left their lane after the release."""
        if not self.released:
            return
        for record in self.balls:
            if not record["active"]:
                continue
            position = record["body"].position
            if position.y > 1420.0 or position.x < -90.0 or position.x > 810.0:
                self.space.remove(record["shape"], record["body"])
                record["active"] = False
                self.escaped_count += 1

    def _decide(self) -> None:
        """Freeze the verdict from the first lane that actually filled up."""
        if self.decided_at is not None:
            return
        done = {side: at for side, at in self.full_at.items() if at is not None}
        if not done:
            return
        self.decided_at = min(done.values())
        self._emit("decide", 1.0, (360.0, 700.0))

    def advance(self) -> None:
        """Advance one 120 Hz sampling step with bounded-distance physics substeps."""
        for _ in range(self.physics_substeps):
            self._advance_substep()

    def _advance_substep(self) -> None:
        """Resolve contacts and retire parents before the next physics solve."""
        self.time += self.substep_dt
        if self.time <= self.hitstop_until + 1e-9:
            return
        if not self.released:
            deadline = self.release_at
            if self.decided_at is not None:
                deadline = min(deadline, self.decided_at + self.hold_after_decide)
            if self.time >= deadline:
                self._release()
        self.motion_time += self.substep_dt
        self.space.step(self.substep_dt)
        did_split = False
        for slot in sorted(self.pending):
            record = self.by_slot.get(slot)
            if record is not None and record["active"]:
                did_split = self._split(record) or did_split
        self.pending.clear()
        # Merge a whole solver batch into one short hold; dense splits cannot
        # repeatedly extend it because another hold needs fresh moving time.
        if did_split and self.hitstop > 0 and self.motion_time - self.last_hitstop >= self.hitstop_interval:
            self.hitstop_until = self.time + self.hitstop
            self.last_hitstop = self.motion_time
            self.hitstop_windows.append({"start": self.time, "end": self.hitstop_until})
        self._decide()
        self._collect_escaped()
        for record in self.balls:
            if not record["active"]:
                continue
            speed = float(record["body"].velocity.length)
            if speed > self.max_speed:
                record["body"].velocity *= self.max_speed / speed

    # ---------------------------------------------------------------- sampling

    def snapshot(self) -> tuple[np.ndarray, int, int, int, int]:
        """Return drawable positions plus per-lane and aggregate counters."""
        positions = np.full((self.slots, 2), np.nan, dtype=np.float32)
        for record in self.balls:
            if record["active"]:
                positions[record["slot"]] = record["body"].position.x, record["body"].position.y
        remaining = sum(1 for record in self.balls if record["active"])
        return positions, self.count[LEFT], self.count[RIGHT], remaining, self.escaped_count


def generate_versus_scene(config: Any, progress: Callable[[float], None] | None = None) -> SceneData:
    """Generate a deterministic two-lane race trajectory and its verdict."""
    output = _section(config, "output")
    simulation = _section(config, "simulation")
    duration = float(_get(output, "duration", 20.0))
    sample_rate = int(_get(simulation, "sample_rate", 60))
    if duration <= 0 or duration > 120:
        raise ValueError("duration must be between 0 and 120 seconds")
    if sample_rate not in {30, 60, 120}:
        raise ValueError("sample_rate must be 30, 60, or 120")
    world = _VersusWorld(config)
    sample_count = round(duration * sample_rate) + 1
    positions = np.full((sample_count, world.slots, 2), np.nan, dtype=np.float32)
    counts = np.zeros(sample_count, dtype=np.int32)
    retired = np.zeros(sample_count, dtype=np.int32)
    motion_times = np.zeros(sample_count, dtype=np.float32)
    remaining = np.zeros(sample_count, dtype=np.int32)
    escaped = np.zeros(sample_count, dtype=np.int32)
    rotor_angles = np.zeros(sample_count, dtype=np.float32)
    ring_angles = np.zeros(sample_count, dtype=np.float32)
    released = np.zeros(sample_count, dtype=np.bool_)
    count_left = np.zeros(sample_count, dtype=np.int32)
    count_right = np.zeros(sample_count, dtype=np.int32)
    colors = np.zeros(world.slots, dtype=np.uint8)
    colors[world.lane_slots :] = 1
    steps_per_sample = max(1, 120 // sample_rate)
    for index in range(sample_count):
        frame, left, right, alive, gone = world.snapshot()
        positions[index] = frame
        count_left[index], count_right[index] = left, right
        counts[index] = world.created[LEFT] + world.created[RIGHT]
        retired[index] = world.retired_count
        motion_times[index] = world.motion_time
        remaining[index], escaped[index] = alive, gone
        released[index] = world.released
        if progress:
            progress(index / max(1, sample_count - 1))
        if index < sample_count - 1:
            for _ in range(steps_per_sample):
                world.advance()
    world.time = duration
    world._decide()
    left_at, right_at = world.full_at[LEFT], world.full_at[RIGHT]
    if world.decided_at is None:
        winner, margin = "undecided", None
    elif left_at is not None and right_at is not None and abs(left_at - right_at) < 1e-6:
        winner, margin = "draw", 0.0
    else:
        winner = LEFT if (right_at is None or (left_at is not None and left_at < right_at)) else RIGHT
        margin = round(abs(left_at - right_at), 4) if left_at is not None and right_at is not None else None
    metadata = {
        "duration": duration,
        "sample_rate": sample_rate,
        "simulation": dict(simulation) if isinstance(simulation, Mapping) else {"mode": "versus"},
        "center": [360.0, 664.0],
        "radius": 263.0,
        "custom_renderer": "versus",
        "versus": {
            "lanes": {
                "left": {"x0": LANE_BOXES[LEFT][0], "x1": LANE_BOXES[LEFT][1], "y0": LANE_TOP, "y1": LANE_BOTTOM, "color": 0},
                "right": {"x0": LANE_BOXES[RIGHT][0], "x1": LANE_BOXES[RIGHT][1], "y0": LANE_TOP, "y1": LANE_BOTTOM, "color": 1},
            },
            "capacity": world.capacity,
            "seed_balls": world.seed_right,
            "lane_slots": world.lane_slots,
            "physics_substeps": world.physics_substeps,
            "solver_rate": 120 * world.physics_substeps,
            "burst": dict(world.burst),
            "split_semantics": "parent_replaced_by_total_children_capped_at_capacity",
            "hitstop_windows": world.hitstop_windows,
            "ladder": [10, 100, 500],
            "count_left": count_left.tolist(),
            "count_right": count_right.tolist(),
            "decided_at": world.decided_at,
            "release_at": world.release_at,
            "result": {
                "winner": winner,
                "margin": margin,
                "left_full_at": left_at,
                "right_full_at": right_at,
                "left_final": int(count_left[-1]),
                "right_final": int(count_right[-1]),
            },
            "event_log": world.event_log,
            "physical_model": "pymunk_contact_multiplication_two_identical_lanes",
        },
        "summary": {
            "mode": "versus",
            "births": int(counts[-1]),
            "retired": int(retired[-1]),
            "escaped": int(escaped[-1]),
            "rejected_births": world.rejected,
            "winner": winner,
            "margin": margin,
        },
    }
    event_array = np.asarray(world.events, dtype=np.float32).reshape((-1, 3))
    return SceneData(
        metadata,
        positions,
        counts,
        remaining,
        escaped,
        rotor_angles,
        ring_angles,
        released,
        colors,
        event_array,
        birth_times=world.birth.copy(),
        retired=retired,
        generations=world.generations.copy(),
        motion_times=motion_times,
        birth_motion_times=world.birth_motion.copy(),
    )
