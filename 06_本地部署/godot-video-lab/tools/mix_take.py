"""Mix recorded collision sounds to sample-aligned 48 kHz stereo PCM using only stdlib."""

from __future__ import annotations

import argparse
from array import array
import json
import math
from pathlib import Path
import struct
import sys
import wave

SAMPLE_RATE = 48_000


def wav_clip(path: str, pitch: float, duration: float) -> tuple[array, dict]:
    """Load integer PCM and linearly sample the same asset at 48 kHz with pitch applied."""
    source_path = Path(path)
    root = Path(__file__).resolve().parent.parent
    if path.startswith('res://'):
        source_path = root / path[6:]
    elif path.startswith('user://'):
        raise ValueError('WAV user:// path must be frozen to an absolute asset path before production')
    elif not source_path.is_absolute():
        source_path = root / source_path
    with source_path.open('rb') as stream:
        header = stream.read(12)
        if len(header) != 12 or header[:4] != b'RIFF' or header[8:] != b'WAVE':
            raise ValueError(f'Not a RIFF/WAVE asset: {source_path}')
        encoding = None
        while chunk := stream.read(8):
            if len(chunk) != 8:
                raise ValueError('Truncated WAV chunk header')
            kind, size = struct.unpack('<4sI', chunk)
            if kind == b'fmt ':
                content = stream.read(min(size, 16))
                if size < 16 or len(content) < 16:
                    raise ValueError('Truncated WAV format chunk')
                encoding = struct.unpack_from('<H', content)[0]
                break
            stream.seek(size + size % 2, 1)
    if encoding != 1:
        raise ValueError('Only integer PCM WAV is supported; compressed/float/extensible formats are rejected')
    with wave.open(str(source_path), 'rb') as source:
        rate, channels, width, source_frames = source.getframerate(), source.getnchannels(), source.getsampwidth(), source.getnframes()
        if channels not in (1, 2) or width not in (1, 2, 3, 4) or not 8000 <= rate <= 192000 or source_frames <= 0 or source.getcomptype() != 'NONE':
            raise ValueError('WAV requires 8–192 kHz, mono/stereo, 8/16/24/32-bit integer PCM')
        output_frames = min(round(duration * SAMPLE_RATE), max(1, round(source_frames * SAMPLE_RATE / (rate * pitch))))
        required_frames = min(source_frames, math.ceil((output_frames - 1) * rate * pitch / SAMPLE_RATE) + 2)
        raw = source.readframes(required_frames)
    if len(raw) != required_frames * width * channels:
        raise ValueError('Truncated WAV sample data')

    def read_sample(frame: int, channel: int) -> float:
        offset = (min(frame, required_frames - 1) * channels + min(channel, channels - 1)) * width
        if width == 1:
            return (raw[offset] - 128) / 128
        return int.from_bytes(raw[offset:offset + width], 'little', signed=True) / (1 << (width * 8 - 1))

    clip = array('f')
    for index in range(output_frames):
        position = index * rate * pitch / SAMPLE_RATE
        lower = int(position)
        fraction = position - lower
        for channel in range(2):
            start = read_sample(lower, channel)
            clip.append(start + (read_sample(lower + 1, channel) - start) * fraction)
    return clip, {'path': str(source_path), 'sample_rate': rate, 'channels': channels, 'bits': width * 8,
                  'source_duration': source_frames / rate, 'pitched_duration': source_frames / rate / pitch}


def waveform(time: float, preset: str, pitch: float) -> float:
    """Match src/presentation/audio.gd exactly before voice gain and master limiting."""
    frequency = {"bell": 1046.5, "click": 1400.0}.get(preset, 650.0) * pitch
    decay = {"bell": 18.0, "click": 180.0}.get(preset, 55.0)
    carrier = math.sin(math.tau * frequency * time)
    if preset == "wood":
        carrier = (carrier + 0.32 * math.sin(math.tau * frequency * 2.73 * time)) / 1.32
    elif preset == "bell":
        carrier = (carrier + 0.35 * math.sin(math.tau * frequency * 2.01 * time)) / 1.35
    return 0.72 * carrier * math.exp(-time * decay) * (1 - math.exp(-time * 1000))


def event_key(event: dict) -> str:
    """Collapse two body notifications from one contact, but retain later impacts."""
    if "contact_episode_id" in event:
        return str(event["contact_episode_id"])
    if event.get("type") == "contact":
        pair = sorted([str(event.get("id", event.get("body_id", ""))), str(event.get("other_id", ""))])
        return f"{pair[0]}:{pair[1]}:{int(float(event.get('time', 0)) * 1_000_000)}"
    return str(event.get("event_id", "split:" + str(event.get("parent", ""))))


def mix(take: dict, scene: dict, destination: Path, duration: float) -> dict:
    """Place each accepted voice at round(film_time*rate), and fit the exact video duration."""
    if not math.isfinite(duration) or not 0 < duration <= 60:
        raise ValueError("Duration must be between 0 and 60 seconds")
    settings = scene.get("presentation", {}).get("audio", {})
    preset = str(settings.get("preset", "wood"))
    wav_path = str(settings.get('wav_path', '')).strip()
    if not wav_path and preset not in ("wood", "bell", "click"):
        raise ValueError(f"Unknown audio preset: {preset}")
    pitch = max(0.25, min(4.0, float(settings.get("pitch", 1))))
    gain = 10 ** (max(-60.0, min(0.0, float(settings.get("volume_db", -12)))) / 20)
    interval = max(0.0, float(settings.get("min_interval", 0.035)))
    max_voices = max(1, min(32, int(settings.get("max_voices", 16))))
    asset: dict = {}
    if wav_path:
        note, asset = wav_clip(wav_path, pitch, duration)
    else:
        note = array('f')
        note_duration = {"bell": 0.24, "click": 0.035}.get(preset, 0.09)
        for index in range(round(note_duration * SAMPLE_RATE)):
            value = waveform(index / SAMPLE_RATE, preset, pitch) * 0.70710678
            note.extend([value, value])
    note_frames = len(note) // 2
    note_duration = note_frames / SAMPLE_RATE
    length = round(duration * SAMPLE_RATE)
    samples = array("f", [0]) * (length * 2)
    seen: set[str] = set()
    voice_ends: list[float] = []
    last_time = -1000.0
    accepted: list[dict] = []
    skipped = 0
    raw_events = take.get("events", [])
    if not isinstance(raw_events, list):
        raise ValueError("Take events must be an array")
    events = sorted(enumerate(raw_events), key=lambda entry: (float(entry[1].get("time", 0)), entry[0]))
    for _, event in events:
        if not settings.get("enabled", True) or event.get("type") not in ("contact", "split"):
            continue
        if event.get("type") == "contact" and event.get("phase", "enter") != "enter":
            continue
        time = float(event.get("time", 0))
        if not math.isfinite(time) or time < 0:
            raise ValueError("Event time must be finite and nonnegative")
        if time >= duration:
            continue
        key = event_key(event)
        voice_ends = [end for end in voice_ends if end > time]
        if key in seen or time - last_time + 0.000001 < interval or len(voice_ends) >= max_voices:
            skipped += 1
            continue
        seen.add(key)
        last_time = time
        voice_ends.append(time + note_duration)
        strength = max(0.25, min(1.4, float(event.get("strength", 1))))
        start = round(time * SAMPLE_RATE)
        for offset in range(min(note_frames, max(0, length - start))):
            target = (start + offset) * 2
            samples[target] += note[offset * 2] * gain * strength
            samples[target + 1] += note[offset * 2 + 1] * gain * strength
        accepted.append({"event_id": event.get("event_id", ""), "event_time": time,
                         "sample_index": start, "sample_time": start / SAMPLE_RATE})
    peak_before = max((abs(value) for value in samples), default=0.0)
    limiter_gain = min(1.0, 0.98 / peak_before) if peak_before else 1.0
    pcm = array("h")
    for sample in samples:
        value = round(max(-1.0, min(1.0, sample * limiter_gain)) * 32767)
        pcm.append(value)
    if sys.byteorder != "little":
        pcm.byteswap()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())
    report = {"sample_rate": SAMPLE_RATE, "channels": 2, "samples_per_channel": length,
              "duration_seconds": length / SAMPLE_RATE, "preset": preset, "accepted_events": len(accepted),
              "skipped_audio_events": skipped, "raw_events": len(raw_events), "non_silent": peak_before > 1e-5,
              "peak_before_limiter": peak_before, "peak": peak_before * limiter_gain,
              "limiter_gain": limiter_gain, "first_sound_time": accepted[0]["event_time"] if accepted else None,
              "events": accepted, "output": str(destination), 'source': 'wav' if wav_path else 'procedural', 'wav_asset': asset}
    destination.with_name("mix_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report


def main() -> None:
    """Load the frozen take and optional style snapshot used by a production job."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--take", required=True, type=Path)
    parser.add_argument("--scene", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--duration", type=float)
    args = parser.parse_args()
    take = json.loads(args.take.read_text(encoding="utf-8-sig"))
    scene = json.loads(args.scene.read_text(encoding="utf-8-sig")) if args.scene else take["scene"]
    report = mix(take, scene, args.output, args.duration if args.duration is not None else float(take["duration"]))
    print(json.dumps({key: value for key, value in report.items() if key != "events"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
