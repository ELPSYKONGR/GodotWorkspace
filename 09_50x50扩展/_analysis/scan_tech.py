# -*- coding: utf-8 -*-
"""
scan_tech.py —— 全量扫描 107 个 mp4 的技术规格与音轨特征（纯 PyAV + numpy，不依赖 ffprobe）

音频侧想要回答的问题：
  1) 有没有声音？        -> rms_mean / silent_ratio
  2) 是持续 BGM 还是离散音效？ -> rms_std（离散音效起伏大）、onset_rate（能量突增次数/秒）
  3) 低频是否被压满？    -> low_ratio（20-200Hz 能量占比，BGM 常见低频铺底）
  4) 是否有人声旁白？    -> 1k-3kHz 能量占比 + 段间稳定性（粗略代理指标，非语音识别）

输出：tech_scan.json
"""
import json
import os
import sys
import traceback

import av
import numpy as np

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\original_videos"
OUT = r"D:\codex\AGI\AI视频三项目评估_20261111\09_50x50扩展\_analysis\tech_scan.json"
SR = 8000            # 包络分析够用，且解码快
WIN = 400            # 50ms 窗


def find_videos():
    out = []
    for dirpath, _, files in os.walk(ROOT):
        for fn in files:
            if fn.lower().endswith(".mp4"):
                p = os.path.join(dirpath, fn)
                rel = os.path.relpath(p, ROOT).replace("\\", "/")
                src = "bilibili" if rel.startswith("bilibili/") else "douyin"
                out.append((rel, p, src, os.path.splitext(fn)[0]))
    return sorted(out)


def audio_stats(container):
    """解码整条音轨 -> RMS 序列与频段能量占比。无音轨返回 None。"""
    if not container.streams.audio:
        return None
    st = container.streams.audio[0]
    res = av.AudioResampler(format="flt", layout="mono", rate=SR)
    chunks = []
    for frame in container.decode(st):
        for f2 in res.resample(frame):
            chunks.append(f2.to_ndarray().reshape(-1))
    # 冲刷重采样器里残留的样本
    try:
        for f2 in res.resample(None):
            chunks.append(f2.to_ndarray().reshape(-1))
    except Exception:
        pass
    if not chunks:
        return None
    x = np.concatenate(chunks).astype(np.float32)
    if x.size < SR // 2:
        return None

    n = x.size // WIN
    if n < 2:
        return None
    env = np.sqrt(np.mean(x[: n * WIN].reshape(n, WIN) ** 2, axis=1) + 1e-12)

    # ---- 频段能量（整体 FFT，10 段平均，降低计算量）----
    seg = min(x.size, SR * 10)
    spec = np.abs(np.fft.rfft(x[:seg] * np.hanning(seg))) ** 2
    freqs = np.fft.rfftfreq(seg, 1 / SR)
    total = spec.sum() + 1e-12
    low = spec[(freqs >= 20) & (freqs < 200)].sum() / total
    mid = spec[(freqs >= 200) & (freqs < 1000)].sum() / total
    voice = spec[(freqs >= 1000) & (freqs < 3000)].sum() / total
    high = spec[(freqs >= 3000)].sum() / total

    # ---- 音效密度：包络相对自身基线的突增次数 ----
    base = np.median(env) + 1e-9
    thresh = base * 2.5
    above = env > thresh
    onsets = int(np.sum(above[1:] & ~above[:-1])) if above.size > 1 else 0
    dur_s = x.size / SR

    return {
        "audio_dur_s": round(dur_s, 1),
        "rms_mean": float(np.mean(env)),
        "rms_std": float(np.std(env)),
        "rms_p95": float(np.percentile(env, 95)),
        "rms_dynamic": float(np.percentile(env, 95) - np.percentile(env, 10)),
        "silent_ratio": float(np.mean(env < max(base * 0.15, 1e-4))),
        "onset_count": onsets,
        "onset_rate": round(onsets / dur_s, 2) if dur_s else 0,
        "low_ratio": float(low),
        "mid_ratio": float(mid),
        "voice_ratio": float(voice),
        "high_ratio": float(high),
        "env_profile": [round(float(v), 4) for v in env[:: max(1, n // 40)][:40]],
    }


def probe(path):
    container = av.open(path, metadata_errors="ignore")
    try:
        v = container.streams.video[0] if container.streams.video else None
        if v is None:
            return {"error": "无视频流"}
        dur = float(container.duration / av.time_base) if container.duration else 0.0
        if not dur and v.duration and v.time_base:
            dur = float(v.duration * v.time_base)
        fps = float(v.average_rate) if v.average_rate else 0.0
        rec = {
            "duration_s": round(dur, 2),
            "w": int(v.codec_context.width or 0),
            "h": int(v.codec_context.height or 0),
            "fps": round(fps, 1),
            "vcodec": v.codec_context.name,
            "vbitrate_kbps": round((v.bit_rate or 0) / 1000) if v.bit_rate else 0,
            "has_audio": bool(container.streams.audio),
            "acodec": container.streams.audio[0].codec_context.name if container.streams.audio else "",
        }
        rec["audio"] = audio_stats(container)
        return rec
    finally:
        container.close()


def main():
    vids = find_videos()
    print(f"[scan] {len(vids)} 个视频")
    out = []
    for i, (rel, p, src, vid) in enumerate(vids, 1):
        try:
            rec = probe(p)
        except Exception as e:
            rec = {"error": f"{type(e).__name__}: {e}"[:200]}
        rec.update({"path": rel, "source": src, "vid": vid,
                    "bytes": os.path.getsize(p)})
        out.append(rec)
        a = rec.get("audio") or {}
        print(f"[{i}/{len(vids)}] {vid[:14]:<14} {rec.get('duration_s','?'):>6}s "
              f"{rec.get('w')}x{rec.get('h')} rms={(a.get('rms_mean') or 0):.3f} "
              f"onset/s={(a.get('onset_rate') or 0):.2f}", flush=True)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    ok = sum(1 for r in out if "error" not in r)
    print(f"\n[done] 成功 {ok}/{len(out)} -> {OUT}")


if __name__ == "__main__":
    main()
