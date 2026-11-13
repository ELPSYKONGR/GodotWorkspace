"""Inventory research copies by work ID; keep historical claims separate from disk facts."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

WORK_ID = re.compile(r"BV[A-Za-z0-9]{10}|(?<!\d)\d{19}(?!\d)")
VIDEO_SUFFIXES = {".mp4", ".webm", ".mkv", ".flv"}
REVIEWED_SHEETS = {"7704067395716158693", "7706016277194605307", "7705589456817358330"}
METRICS = ("views", "likes", "comments", "favorites", "shares")


def read_json(path: Path):
    """Fail visibly on broken metadata rather than silently dropping a source."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


def work_id(value) -> str:
    """Recover IDs from paths and old download records without needing old drive names."""
    match = WORK_ID.search(str(value))
    return match.group(0) if match else ""


def entries(data):
    """Accept the list and items-list manifest formats used by this research project."""
    if isinstance(data, list):
        return [item for item in data if isinstance(item, dict)]
    if isinstance(data, dict) and isinstance(data.get("items"), list):
        return entries(data["items"])
    return [data] if isinstance(data, dict) else []


def sha256(path: Path) -> str:
    """Stream hashes so the index can also verify copies after transport."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_inventory(root: Path) -> dict:
    """Join current media files to the recorded sources, without claiming a new viewing."""
    expansion = next(root.glob("09_*"))
    sources = [expansion / "cases_50x50.json", expansion / "cases_bilibili_56.json",
               expansion / "douyin/cases_douyin_partial.json", expansion / "download_manifest.json"]
    sources.extend(sorted((expansion / "original_videos").rglob("*manifest*.json")))
    sources.extend(sorted(root.glob("08_*20261111/cases_*.json")))
    sources.extend(sorted(root.glob("01_*/*/metadata.json")))
    by_id = defaultdict(list)
    for source in sources:
        for item in entries(read_json(source)):
            ident = work_id(item.get("id", item.get("bvid", item.get("file", ""))))
            if not ident:
                ident = work_id(source.as_posix())
            if ident:
                by_id[ident].append((source.relative_to(root).as_posix(), item))

    files = defaultdict(list)
    evidence_names = defaultdict(list)
    skipped = []
    for directory in sorted(root.iterdir()):
        if not directory.is_dir() or not directory.name.startswith(("01_", "07_", "08_", "09_")):
            continue
        for path in sorted(directory.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(root).as_posix()
            evidence_names[path.name].append(relative)
            is_story = directory.name.startswith("01_") and path.name == "reference.webp"
            if path.suffix.lower() not in VIDEO_SUFFIXES and not is_story:
                continue
            ident = work_id(relative)
            if not ident:
                skipped.append(relative)
                continue
            files[ident].append({"path": relative, "bytes": path.stat().st_size,
                                "sha256": sha256(path), "kind": "story_image" if is_story else "video"})

    selected = {(str(item.get("platform", "")).lower(), str(item.get("id", "")))
                for item in read_json(expansion / "cases_50x50.json")}
    records = []
    for ident in sorted(set(by_id) | set(files)):
        platform = "Bilibili" if ident.startswith("BV") else "Douyin"
        copies = files.get(ident, [])
        observations, evidence, metric_records, declarations = [], set(), [], []
        title, uploader, category, scope = "", "", "", ""
        for source_path, item in by_id.get(ident, []):
            title = title or str(item.get("title", "") or "")
            uploader = uploader or str(item.get("uploader", "") or "")
            category = category or str(item.get("mechanism_category", "") or "")
            scope = scope or str(item.get("evidence_scope", "") or "")
            observations.append(source_path)
            metrics = {key: item[key] for key in METRICS if item.get(key) is not None}
            if isinstance(item.get("metrics_display"), dict):
                metrics["page_display"] = item["metrics_display"]
            if metrics:
                metric_records.append({"source": source_path, "recorded_at": item.get("checked_at"),
                                       "metrics": metrics})
            if item.get("download_status", item.get("status")):
                declared = {"source": source_path, "status": item.get("download_status", item.get("status"))}
                if isinstance(item.get("bytes"), int):
                    declared["declared_bytes"] = item["bytes"]
                    declared["size_matches_a_copy"] = any(copy["bytes"] == item["bytes"] for copy in copies)
                declarations.append(declared)
            for key in ("page_evidence_file", "screenshot_file", "evidence_file", "frame_file"):
                name = str(item.get(key, "") or "").replace("\\", "/").split("/")[-1]
                evidence.update(evidence_names.get(name, []))
        records.append({
            "platform": platform, "id": ident, "title": title, "uploader": uploader,
            "url": f"https://www.bilibili.com/video/{ident}/" if platform == "Bilibili" else f"https://www.douyin.com/video/{ident}",
            "selected_in_50x50_report": (platform.lower(), ident) in selected,
            "mechanism_category_historical": category, "historical_evidence_scope": scope,
            "current_status": "present_nonempty" if copies and all(copy["bytes"] > 0 for copy in copies) else "missing_or_empty",
            "copies": copies, "metadata_sources": sorted(set(observations)), "page_evidence": sorted(evidence),
            "metric_records": metric_records, "historical_download_claims": declarations,
            "review_scope": "five_timepoint_sheet_review_no_complete_audio_review" if ident in REVIEWED_SHEETS else "inventory_only_see_historical_evidence_scope",
        })

    platform_summary = {}
    for platform in ("Bilibili", "Douyin"):
        present = [record for record in records if record["platform"] == platform and record["copies"]]
        copies = [copy for record in present for copy in record["copies"]]
        canonical = [copy for copy in copies if copy["path"].startswith(expansion.name + "/original_videos/")]
        selected_records = [record for record in records if record["platform"] == platform and record["selected_in_50x50_report"]]
        platform_summary[platform] = {
            "unique_present_work_ids": len(present), "all_copy_files": len(copies),
            "all_copy_bytes": sum(copy["bytes"] for copy in copies),
            "canonical_09_files": len(canonical), "canonical_09_bytes": sum(copy["bytes"] for copy in canonical),
            "selected_report_records": len(selected_records),
            "selected_report_present": sum(bool(record["copies"]) for record in selected_records),
        }
    return {"schema_version": 1, "generated_utc": datetime.now(timezone.utc).isoformat(),
            "path_base": "research_project_root", "validation_scope": "file_presence_size_sha256_only_not_new_decode_or_full_content_review",
            "summary": platform_summary, "unidentified_media_paths": skipped, "records": records}


def main() -> None:
    """Write stable relative paths into the handoff documents beside this tool's project."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-root", type=Path, help="Research root containing 01_* and 09_*; inferred from this tool by default.")
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "docs")
    args = parser.parse_args()
    root = (args.project_root or Path(__file__).resolve().parents[3]).resolve()
    report = build_inventory(root)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "reference_media_inventory.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    columns = ("platform", "id", "title", "uploader", "url", "selected_in_50x50_report", "current_status",
               "mechanism_category_historical", "review_scope", "copies", "page_evidence", "metadata_sources", "metric_records")
    with (args.output_dir / "reference_media_index.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        for record in report["records"]:
            writer.writerow({key: json.dumps(record[key], ensure_ascii=False) if isinstance(record[key], list) else record[key] for key in columns})
    print(json.dumps({"summary": report["summary"], "unidentified_media": report["unidentified_media_paths"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
