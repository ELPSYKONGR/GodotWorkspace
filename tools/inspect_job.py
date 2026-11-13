"""Independently decode a completed production job and validate geometry, timing and audio."""

from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import wave


def run_decode(command: list[str]) -> subprocess.CompletedProcess:
    """Require successful full decoding, without trusting the encoder's exit alone."""
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace')[-3000:])
    return result


def audio_stats(samples: array) -> dict:
    """Measure actual sample content rather than only checking that a track exists."""
    peak = max((abs(value) for value in samples), default=0.0)
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) if samples else 0.0
    threshold = max(1e-5, peak * 0.02)
    onset = next((index // 2 / 48000 for index, value in enumerate(samples) if abs(value) > threshold), None)
    return {"peak": peak, "rms": rms, "non_silent": peak > 1e-5, "sample_count": len(samples), 'first_audible_time': onset}


def inspect(job_dir: Path) -> dict:
    """Read frozen inputs and verify both video and audio against their actual decoded data."""
    root = Path(__file__).resolve().parent.parent
    ffmpeg = root / '.runtime/ffmpeg.exe'
    job = json.loads((job_dir / 'job.json').read_text(encoding='utf-8-sig'))
    scene = json.loads((job_dir / 'scene.snapshot.json').read_text(encoding='utf-8-sig'))
    mix = json.loads((job_dir / 'mix_report.json').read_text(encoding='utf-8-sig'))
    video = job_dir / 'final.mp4'
    result = run_decode([str(ffmpeg), '-hide_banner', '-nostdin', '-i', str(video), '-map', '0:v:0', '-an', '-fps_mode', 'passthrough', '-f', 'null', '-', '-progress', 'pipe:1', '-nostats'])
    stderr = result.stderr.decode('utf-8', errors='replace')
    stream = next((line for line in stderr.splitlines() if 'Stream #' in line and 'Video:' in line), '')
    audio_stream = next((line for line in stderr.splitlines() if 'Stream #' in line and 'Audio:' in line), '')
    geometry = re.search(r',\s*(\d+)x(\d+)(?:\s|,)', stream)
    fps = re.search(r'([\d.]+)\s+fps', stream)
    if not geometry or not fps:
        raise ValueError(f'Cannot read actual stream geometry/FPS: {stream}')
    progress = dict(line.split('=', 1) for line in result.stdout.decode().splitlines() if '=' in line)
    decoded_frames = int(progress.get('frame', 0))
    decoded_duration = int(progress.get('out_time_us', 0)) / 1_000_000
    expected_duration = int(job['frames']) / float(job['fps'])
    decoded_rgb = run_decode([str(ffmpeg), '-v', 'error', '-nostdin', '-i', str(video), '-map', '0:v:0', '-an', '-vf', 'scale=90:160', '-pix_fmt', 'rgb24', '-fps_mode', 'passthrough', '-f', 'rawvideo', 'pipe:1']).stdout
    stride = 90 * 160 * 3
    rgb_frames = len(decoded_rgb) // stride
    black_frames = [index for index in range(rgb_frames) if max(decoded_rgb[index * stride:(index + 1) * stride], default=0) < 8]
    video_hashes = {hashlib.sha256(decoded_rgb[i * stride:(i + 1) * stride]).hexdigest() for i in range(rgb_frames)}
    audio_result = run_decode([str(ffmpeg), '-v', 'error', '-nostdin', '-i', str(video), '-map', '0:a:0', '-vn', '-ac', '2', '-ar', '48000', '-f', 'f32le', 'pipe:1'])
    audio = array('f')
    audio.frombytes(audio_result.stdout)
    if sys.byteorder != 'little': audio.byteswap()
    decoded_audio = audio_stats(audio)
    with wave.open(str(job_dir / 'mix.wav'), 'rb') as wav:
        wav_frames, wav_rate, wav_channels, wav_width = wav.getnframes(), wav.getframerate(), wav.getnchannels(), wav.getsampwidth()
        raw = array('h', wav.readframes(wav_frames))
    if sys.byteorder != 'little': raw.byteswap()
    wav_stats = audio_stats(array('f', (value / 32768 for value in raw)))
    requires_sound = bool(scene.get('presentation', {}).get('audio', {}).get('enabled', True)) and int(mix.get('accepted_events', 0)) > 0
    wav_path = str(scene.get('presentation', {}).get('audio', {}).get('wav_path', '')).strip()
    frozen_asset = None
    if wav_path:
        frozen_asset = Path(wav_path).resolve()
    placement_error = max((abs(float(event['sample_time']) - float(event['event_time'])) for event in mix.get('events', [])), default=0.0)
    onset_error = abs(decoded_audio['first_audible_time'] - wav_stats['first_audible_time']) if decoded_audio['first_audible_time'] is not None and wav_stats['first_audible_time'] is not None else None
    checks = {
        'dimensions': (int(geometry[1]), int(geometry[2])) == (int(job['width']), int(job['height'])),
        'fps': abs(float(fps[1]) - float(job['fps'])) < 0.001,
        'frame_count': decoded_frames == int(job['frames']) == rgb_frames,
        'duration': abs(decoded_duration - expected_duration) <= 1 / float(job['fps']) + 0.000001,
        'full_video_decode': progress.get('progress') == 'end' and len(decoded_rgb) % stride == 0,
        'no_black_frames': not black_frames,
        'audio_present_and_decodable': len(audio) > 0,
        'h264_aac_codecs': 'Video: h264' in stream and 'Audio: aac' in audio_stream,
        'audio_stream_48khz': bool(re.search(r'48000\s+Hz', audio_stream)),
        'wav_format': wav_channels == 2 and wav_width == 2 and wav_rate == 48000,
        'wav_duration': abs(wav_frames / wav_rate - expected_duration) <= 1 / wav_rate,
        'audio_non_silent_when_expected': not requires_sound or (decoded_audio['non_silent'] and wav_stats['non_silent']),
        'event_sample_alignment': placement_error <= 1 / 48000,
        'encoded_audio_onset_alignment': not requires_sound or (onset_error is not None and onset_error <= 1 / float(job['fps'])),
        'wav_asset_frozen': frozen_asset is None or (frozen_asset.is_file() and frozen_asset.is_relative_to(job_dir.resolve())),
    }
    inputs = {name: hashlib.sha256((job_dir / name).read_bytes()).hexdigest() for name in ['take.json', 'scene.snapshot.json', 'job.json']}
    if frozen_asset is not None and frozen_asset.is_file():
        inputs['wav_asset'] = hashlib.sha256(frozen_asset.read_bytes()).hexdigest()
    return {'passed': all(checks.values()), 'checks': checks, 'video': {'width': int(geometry[1]), 'height': int(geometry[2]), 'fps': float(fps[1]), 'frames': decoded_frames, 'duration': decoded_duration, 'unique_frame_hashes': len(video_hashes), 'black_frames': black_frames},
            'audio': {'expected': requires_sound, 'decoded': decoded_audio, 'wav': wav_stats, 'accepted_events': mix.get('accepted_events', 0), 'max_event_sample_error_seconds': placement_error, 'encoded_onset_error_seconds': onset_error},
            'inputs': inputs}


def main() -> None:
    """Always write a diagnostic report, including when validation cannot decode an artifact."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--job', required=True, type=Path)
    args = parser.parse_args()
    try:
        report = inspect(args.job)
    except (OSError, ValueError, RuntimeError, KeyError, wave.Error) as error:
        report = {'passed': False, 'error': str(error)}
    (args.job / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    if not report['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
