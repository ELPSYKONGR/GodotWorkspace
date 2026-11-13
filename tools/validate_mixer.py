"""Verify sample placement, paired collision dedup, pitch formulas and a real WAV."""

from __future__ import annotations

from array import array
import json
import math
from pathlib import Path
import wave

from mix_take import SAMPLE_RATE, mix, waveform, wav_clip


def main() -> None:
    """Exercise the production mixer with a small, known collision event timeline."""
    root = Path(__file__).resolve().parent.parent
    fixture = json.loads((root / "outputs/media_test.take.json").read_text(encoding="utf-8"))
    contacts = [
        {"type": "contact", "event_id": "zero", "time": 0.0, "id": "a", "other_id": "b"},
        {"type": "contact", "event_id": "duplicate", "time": 0.0, "id": "b", "other_id": "a"},
        {"type": "contact", "event_id": "later", "time": 0.101, "id": "a", "other_id": "b"},
    ]
    fixture["events"] = contacts
    report = mix(fixture, fixture["scene"], root / "outputs/media_mixer_test.wav", 0.3)
    checks = {
        "zero_event_included": report["first_sound_time"] == 0.0,
        "paired_contact_deduplicated": report["accepted_events"] == 2 and report["skipped_audio_events"] == 1,
        "sample_placement": report["events"][1]["sample_index"] == round(0.101 * SAMPLE_RATE),
        "non_silent": report["non_silent"],
        "no_clipping": report["peak"] <= 0.980001,
    }
    reference = json.loads((root / "outputs/media_components_validation.json").read_text(encoding="utf-8"))["wave_reference"]
    indexes = [0, 1, 48, 200, 1000]
    checks["godot_python_wave_parity"] = all(
        math.isclose(waveform(index / SAMPLE_RATE, preset, 1.0), value, abs_tol=1e-12)
        for preset, values in reference.items() for index, value in zip(indexes, values)
    )
    with wave.open(str(root / "outputs/media_mixer_test.wav"), "rb") as wav:
        checks["wav_format_and_duration"] = wav.getnchannels() == 2 and wav.getsampwidth() == 2 and wav.getframerate() == SAMPLE_RATE and wav.getnframes() == 14400
        pcm = array("h", wav.readframes(wav.getnframes()))
        checks["pcm_nonzero"] = max(abs(value) for value in pcm) > 100
    imported_scene = json.loads(json.dumps(fixture["scene"]))
    imported_scene["presentation"]["audio"].update({"wav_path": str(root / "outputs/media_import_source.wav"), "pitch": 2.0})
    fixture["events"] = [{"type": "contact", "event_id": "imported_asset", "time": 0.02, "id": "a", "other_id": "b"}]
    imported_report = mix(fixture, imported_scene, root / "outputs/media_import_mixed.wav", 0.3)
    checks["wav_import_resample"] = imported_report["source"] == "wav" and imported_report["wav_asset"]["sample_rate"] == 22050 and imported_report["sample_rate"] == 48000
    checks["wav_import_pitch_duration"] = math.isclose(imported_report["wav_asset"]["pitched_duration"], 0.06) and imported_report["events"][0]["sample_index"] == 960
    with wave.open(str(root / "outputs/media_import_mixed.wav"), "rb") as wav:
        imported_pcm = array("h", wav.readframes(wav.getnframes()))
        active = [index // 2 for index, value in enumerate(imported_pcm) if abs(value) > 100]
        checks["wav_import_stereo_actual_samples"] = wav.getnchannels() == 2 and wav.getframerate() == 48000 and active and min(active) >= 960 and max(active) <= 960 + 2880 and imported_pcm[::2] == imported_pcm[1::2]
    imported_scene["presentation"]["audio"]["wav_path"] = str(root / "outputs/media_unsupported_float.wav")
    try:
        mix(fixture, imported_scene, root / "outputs/should_not_mix.wav", 0.3)
    except ValueError:
        checks["unsupported_wav_rejected"] = True
    else:
        checks["unsupported_wav_rejected"] = False
    all_formats = True
    for bits in (8, 16, 24, 32):
        for channels in (1, 2):
            clip, info = wav_clip(str(root / f"outputs/media_pcm_{bits}_{channels}.wav"), 1.0, 0.3)
            all_formats = all_formats and len(clip) == 5760 * 2 and info['bits'] == bits and info['channels'] == channels and max(abs(value) for value in clip) > 0.38
            all_formats = all_formats and ((clip[::2] == clip[1::2]) == (channels == 1))
    checks["all_pcm_widths_and_channels_resampled"] = all_formats
    result = {"passed": all(checks.values()), "checks": checks}
    (root / "outputs/mixer_validation.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result))
    if not result["passed"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
