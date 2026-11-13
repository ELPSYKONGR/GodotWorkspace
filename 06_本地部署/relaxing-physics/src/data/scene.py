"""Serializable motion data shared by simulation, rendering, and audio layers."""

from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
from typing import Any

import numpy as np


@dataclass(frozen=True)
class SceneFrame:
    """One sampled scene state ready for a renderer."""

    time: float
    positions: np.ndarray
    colors: np.ndarray
    count: int
    remaining: int
    escaped: int
    rotor_angle: float
    ring_angle: float
    is_released: bool
    ages: np.ndarray = field(default_factory=lambda: np.empty(0, dtype=np.float32))
    generations: np.ndarray = field(default_factory=lambda: np.empty(0, dtype=np.uint16))
    retired: int = 0


@dataclass
class SceneData:
    """Complete deterministic scene trajectory with no renderer dependencies."""

    metadata: dict[str, Any]
    positions: np.ndarray
    counts: np.ndarray
    remaining: np.ndarray
    escaped: np.ndarray
    rotor_angles: np.ndarray
    ring_angles: np.ndarray
    released: np.ndarray
    colors: np.ndarray
    events: np.ndarray
    birth_times: np.ndarray | None = None
    retired: np.ndarray | None = None
    generations: np.ndarray | None = None
    motion_times: np.ndarray | None = None
    birth_motion_times: np.ndarray | None = None

    def __post_init__(self) -> None:
        """Validate and normalize arrays at the data-layer boundary."""
        self.positions = np.asarray(self.positions, dtype=np.float32)
        self.counts = np.asarray(self.counts, dtype=np.int32)
        self.remaining = np.asarray(self.remaining, dtype=np.int32)
        self.escaped = np.asarray(self.escaped, dtype=np.int32)
        self.rotor_angles = np.asarray(self.rotor_angles, dtype=np.float32)
        self.ring_angles = np.asarray(self.ring_angles, dtype=np.float32)
        self.released = np.asarray(self.released, dtype=np.bool_)
        self.colors = np.asarray(self.colors, dtype=np.uint8)
        self.events = np.asarray(self.events, dtype=np.float32)
        if self.events.ndim != 2 or self.events.shape[1] != 3:
            raise ValueError("events must have shape [event_count, 3]")
        if self.positions.ndim != 3 or self.positions.shape[-1] != 2:
            raise ValueError("positions must have shape [samples, slots, 2]")
        sample_count, slot_count = self.positions.shape[:2]
        if not sample_count or not slot_count:
            raise ValueError("positions must contain samples and ball slots")
        if self.retired is None:
            self.retired = np.zeros(sample_count, dtype=np.int32)
        else:
            raw_retired = np.asarray(self.retired)
            if (
                raw_retired.dtype.kind not in "iuf"
                or not np.isfinite(raw_retired).all()
                or np.any(raw_retired < 0)
                or np.any(raw_retired > np.iinfo(np.int32).max)
                or np.any(raw_retired != np.floor(raw_retired))
            ):
                raise ValueError("retired must contain nonnegative integers")
            self.retired = raw_retired.astype(np.int32)
        for name in ("counts", "remaining", "escaped", "retired", "rotor_angles", "ring_angles", "released"):
            if getattr(self, name).shape != (sample_count,):
                raise ValueError(f"{name} must have one value per position sample")
        if self.colors.shape != (slot_count,):
            raise ValueError("colors must have one value per position slot")
        if self.birth_times is not None:
            self.birth_times = np.asarray(self.birth_times, dtype=np.float32)
            if self.birth_times.shape != (slot_count,):
                raise ValueError("birth_times must have one value per position slot")
            if np.isinf(self.birth_times).any():
                raise ValueError("birth_times must be a finite time or NaN for unused slots")
        if self.generations is not None:
            generations = np.asarray(self.generations)
            if generations.shape != (slot_count,):
                raise ValueError("generations must have one value per position slot")
            if (
                generations.dtype.kind not in "iuf"
                or not np.isfinite(generations).all()
                or np.any(generations < 0)
                or np.any(generations > np.iinfo(np.uint16).max)
                or np.any(generations != np.floor(generations))
            ):
                raise ValueError("generations must contain nonnegative uint16 integers")
            self.generations = generations.astype(np.uint16)
        sample_rate = float(self.metadata.get("sample_rate", 0))
        duration = float(self.metadata.get("duration", 0))
        if not np.isfinite(sample_rate) or not 1 <= sample_rate <= 240:
            raise ValueError("metadata.sample_rate must be between 1 and 240")
        if not np.isfinite(duration) or not 0 < duration <= 120:
            raise ValueError("metadata.duration must be between 0 and 120 seconds")
        if sample_count != round(duration * sample_rate) + 1:
            raise ValueError("sample count does not match metadata duration/sample_rate")
        if self.motion_times is not None:
            self.motion_times = np.asarray(self.motion_times, dtype=np.float32)
            if self.motion_times.shape != (sample_count,):
                raise ValueError("motion_times must have one value per position sample")
            if (
                not np.isfinite(self.motion_times).all()
                or np.any(self.motion_times < 0)
                or np.any(np.diff(self.motion_times) < 0)
                or np.any(self.motion_times > np.arange(sample_count) / sample_rate + 1e-5)
            ):
                raise ValueError("motion_times must be finite, monotonic, and no later than display time")
        if self.birth_motion_times is not None:
            self.birth_motion_times = np.asarray(self.birth_motion_times, dtype=np.float32)
            if self.birth_motion_times.shape != (slot_count,):
                raise ValueError("birth_motion_times must have one value per position slot")
            if np.isinf(self.birth_motion_times).any():
                raise ValueError("birth_motion_times must be finite or NaN for unused slots")
            if self.motion_times is None or self.birth_times is None:
                raise ValueError("birth_motion_times requires motion_times and birth_times")
        if np.any((self.counts < 0) | (self.counts > slot_count)) or np.any(np.diff(self.counts) < 0):
            raise ValueError("counts must increase monotonically within available slots")
        if np.any((self.remaining < 0) | (self.escaped < 0)) or np.any(
            self.remaining + self.escaped + self.retired != self.counts
        ):
            raise ValueError("remaining + escaped + retired must equal counts")
        if np.any(np.diff(self.escaped) < 0):
            raise ValueError("escaped must increase monotonically")
        if np.any(np.diff(self.retired) < 0):
            raise ValueError("retired must increase monotonically")
        if not np.isfinite(self.rotor_angles).all() or not np.isfinite(self.ring_angles).all():
            raise ValueError("scene angles must be finite")
        if np.isinf(self.positions).any() or np.any(
            np.isnan(self.positions[..., 0]) != np.isnan(self.positions[..., 1])
        ):
            raise ValueError("positions must be finite coordinates or paired empty NaN slots")
        if np.any(np.isfinite(self.positions).all(axis=2).sum(axis=1) != self.remaining):
            raise ValueError("drawable position counts must match remaining")
        if not np.isfinite(self.events).all():
            raise ValueError("events must contain finite numbers")
        if len(self.events) and (
            np.any(self.events[:, 0] < 0)
            or np.any(self.events[:, 0] > duration + 1e-5)
            or np.any((self.events[:, 1] < 0) | (self.events[:, 1] > 1))
            or np.any(np.abs(self.events[:, 2]) > 1)
        ):
            raise ValueError("event time, strength, or pan is outside its valid range")
        self.metadata = json.loads(json.dumps(self.metadata, ensure_ascii=False))

    @property
    def sample_count(self) -> int:
        """Return the number of fixed-rate trajectory samples."""
        return int(self.positions.shape[0])

    @property
    def slot_count(self) -> int:
        """Return the maximum number of drawable ball slots."""
        return int(self.positions.shape[1])

    def frame_at(self, time: float) -> SceneFrame:
        """Return the data frame at or immediately before a requested time."""
        if not np.isfinite(time):
            raise ValueError("time must be finite")
        sample_rate = float(self.metadata["sample_rate"])
        index = int(np.floor(max(0.0, time) * sample_rate + 1e-7))
        index = min(index, self.sample_count - 1)
        raw_positions = self.positions[index]
        valid = np.isfinite(raw_positions).all(axis=1)
        ages = np.empty(0, dtype=np.float32)
        if self.birth_motion_times is not None:
            ages = np.ascontiguousarray(self.motion_times[index] - self.birth_motion_times[valid], dtype=np.float32)
        elif self.birth_times is not None:
            ages = np.ascontiguousarray(index / sample_rate - self.birth_times[valid], dtype=np.float32)
        generations = np.empty(0, dtype=np.uint16)
        if self.generations is not None:
            generations = np.ascontiguousarray(self.generations[valid])
        return SceneFrame(
            time=index / sample_rate,
            positions=np.ascontiguousarray(raw_positions[valid]),
            colors=np.ascontiguousarray(self.colors[valid]),
            count=int(self.counts[index]),
            remaining=int(self.remaining[index]),
            escaped=int(self.escaped[index]),
            rotor_angle=float(self.rotor_angles[index]),
            ring_angle=float(self.ring_angles[index]),
            is_released=bool(self.released[index]),
            ages=ages,
            generations=generations,
            retired=int(self.retired[index]),
        )

    def save(self, path: str | Path) -> Path:
        """Write a compressed NPZ without object arrays or pickle loading."""
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        metadata_json = json.dumps(self.metadata, ensure_ascii=False, separators=(",", ":"))
        births = self.birth_times if self.birth_times is not None else np.empty(0, dtype=np.float32)
        with target.open("wb") as output:
            np.savez_compressed(
                output,
                metadata_json=np.array(metadata_json),
                positions=self.positions,
                counts=self.counts,
                remaining=self.remaining,
                escaped=self.escaped,
                rotor_angles=self.rotor_angles,
                ring_angles=self.ring_angles,
                released=self.released,
                colors=self.colors,
                events=self.events,
                birth_times=births,
                retired=self.retired,
                generations=self.generations if self.generations is not None else np.empty(0, dtype=np.uint16),
                motion_times=self.motion_times if self.motion_times is not None else np.empty(0, dtype=np.float32),
                birth_motion_times=(
                    self.birth_motion_times if self.birth_motion_times is not None else np.empty(0, dtype=np.float32)
                ),
            )
        return target

    @classmethod
    def load(cls, path: str | Path) -> "SceneData":
        """Load a scene using NumPy's safe, non-pickle path."""
        with np.load(Path(path), allow_pickle=False) as archive:
            metadata = json.loads(str(archive["metadata_json"].item()))
            optional = {}
            for name in ("birth_times", "retired", "generations", "motion_times", "birth_motion_times"):
                value = archive[name] if name in archive.files else None
                optional[name] = value if value is not None and value.size else None
            return cls(
                metadata=metadata,
                positions=archive["positions"],
                counts=archive["counts"],
                remaining=archive["remaining"],
                escaped=archive["escaped"],
                rotor_angles=archive["rotor_angles"],
                ring_angles=archive["ring_angles"],
                released=archive["released"],
                colors=archive["colors"],
                events=archive["events"],
                **optional,
            )
