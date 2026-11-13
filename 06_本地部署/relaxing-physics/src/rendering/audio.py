"""Deterministic procedural audio generated from SceneData collision events."""

from __future__ import annotations

import math
import wave
from pathlib import Path
from typing import Any

import numpy as np


def _bgm(duration: float, rate: int, level: float) -> np.ndarray:
    """Build a minimal low-frequency bed: a 100 BPM kick plus a quiet drone.

    The reference samples measured roughly three times the loudness of the
    event-only tracks and a much higher low-frequency share, so this adds a
    steady floor instead of extra melody. It stays optional and off by default.
    """
    samples = np.zeros((round(duration * rate), 2), dtype=np.float32)
    if level <= 0:
        return samples
    beat = 0.6
    for index in range(int(duration / beat) + 1):
        start = round(index * beat * rate)
        count = min(round(0.32 * rate), len(samples) - start)
        if count <= 0:
            continue
        x = np.arange(count) / rate
        kick = np.sin(math.tau * (55.0 - 16.0 * x) * x) * np.exp(-x * 11.0)
        samples[start : start + count] += (kick * 0.22 * level)[:, None]
    x = np.arange(len(samples)) / rate
    drone = np.sin(math.tau * 55.0 * x) + 0.5 * np.sin(math.tau * 82.5 * x)
    samples += (drone * 0.05 * level)[:, None]
    return samples


def synthesize_audio(scene: Any, config: dict[str, Any], output_path: Path) -> dict[str, Any]:
    """Write collision and release sounds to WAV without reading a rendered video."""
    audio_config = config.get("audio", {})
    duration = float(config.get("output", config).get("duration", scene.metadata.get("duration", 1)))
    rate = int(audio_config.get("sample_rate", 44100))
    volume = max(0.0, min(2.0, float(audio_config.get("volume", 1.0))))
    if not audio_config.get("is_enabled", True):
        volume = 0.0
    samples = np.zeros((round(duration * rate), 2), dtype=np.float32)
    events = np.asarray(getattr(scene, "events", np.empty((0, 3))), dtype=np.float32)
    bins: dict[int, tuple[float, float, float, str]] = {}
    custom_log = []
    for section in scene.metadata.values():
        if isinstance(section, dict) and isinstance(section.get("event_log"), list):
            custom_log.extend(section["event_log"])
    if custom_log:
        for event in custom_log:
            kind = str(event.get("type", "event"))
            if kind == "split":
                continue  # Detailed lineage is silent; the paired rate-limited birth event carries the sound.
            t = float(event.get("time_s", event.get("time", 0.0)))
            strength = float(event.get("value", 0.6))
            pan = float(event.get("pan", 0.0))
            key = int(t / 0.024)
            if key not in bins or strength > bins[key][1]:
                bins[key] = (t, strength, pan, kind)
    else:
        for event in events:
            if len(event) < 3:
                continue
            t, strength, pan = map(float, event[:3])
            key = int(t / 0.024)
            if key not in bins or strength > bins[key][1]:
                bins[key] = (t, strength, pan, "collision")
    frequencies = {"ring_pass": 760, "ring_shrink": 180, "escape": 980, "fail": 150, "spawn": 520,
                   "domino_hit": 430, "glass_hit": 680, "glass_break": 1100, "collector_update": 620,
                   "result": 840, "collision": 470, "birth": 560, "decide": 880, "release": 210}
    for t, strength, pan, kind in bins.values():
        start = round(t * rate)
        count = min(round((0.12 if kind in {"ring_pass", "glass_break", "result"} else 0.065) * rate), len(samples) - start)
        if count <= 0:
            continue
        x = np.arange(count) / rate
        tone = np.sin(math.tau * (frequencies.get(kind, 470) + (int(t * 13) % 7) * 28) * x) * np.exp(-x * (35 if kind == "glass_break" else 65))
        tone *= (0.035 + min(1.0, strength) * 0.13) * volume
        pan = max(-0.8, min(0.8, pan))
        samples[start : start + count, 0] += tone * math.sqrt((1 - pan) / 2)
        samples[start : start + count, 1] += tone * math.sqrt((1 + pan) / 2)
    simulation = {**config.get("simulation", {}), **scene.metadata.get("simulation", {})}
    release_at = float(simulation.get("release_at", duration * 0.8))
    start = round(release_at * rate)
    count = min(round(0.65 * rate), len(samples) - start)
    if count > 0 and audio_config.get("is_enabled", True):
        x = np.arange(count) / rate
        seed = int(scene.metadata.get("simulation", {}).get("seed", 0))
        release = np.random.default_rng(seed).normal(0, 0.07, count)
        release += np.sin(math.tau * (105 * x - 45 * x * x)) * 0.19
        samples[start : start + count] += release[:, None] * volume * np.exp(-x * 7)[:, None]
    bgm_level = float(audio_config.get("bgm_level", 0.5)) if audio_config.get("bgm", False) else 0.0
    if bgm_level > 0:
        samples += _bgm(duration, rate, bgm_level * volume)
    gain = max(0.2, min(4.0, float(audio_config.get("gain", 1.0))))
    samples = np.tanh(samples * gain)
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak > 0.89:
        samples *= 0.89 / peak
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(output_path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes((samples * 32767).astype("<i2").tobytes())
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    return {
        "collision_events": int(len(events)),
        "mixed_hits": len(bins),
        "peak": peak,
        "sample_rate": rate,
        "bgm_level": bgm_level,
        "gain": gain,
        "source": "procedural",
    }
