"""Build a relocatable research/workbench handoff without live state or machine caches."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from datetime import datetime, timezone
import zipfile

LAB = Path("06_本地部署/godot-video-lab")
LEGACY = Path("06_本地部署/relaxing-physics")
SKIP_DIRS = {".git", ".godot", ".venv", "node_modules", "__pycache__", ".cache", ".ruff_cache", "scratch", "_dl_tmp"}
JOBS = {"workbench_2d_1794560945", "workbench_3d_vulkan_final"}
TAKES = {"workbench_2d.json", "workbench_3d.json", "workbench_2d.json.report.json", "workbench_3d.json.report.json"}
STORED = {".mp4", ".webm", ".mkv", ".jpg", ".png", ".webp", ".zip", ".whl", ".docx", ".xlsx"}


def digest(path: Path) -> str:
    """Hash streams rather than loading large reference videos in memory."""
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def wanted(relative: Path) -> bool:
    """Select portable tools, evidence and sources; keep mutable queues out of the copy."""
    parts = relative.parts
    if relative == Path("MANIFEST.json"):
        return False
    if any(part in SKIP_DIRS for part in parts) or relative.name == ".env":
        return False
    if relative.name.endswith((".tmp", ".pyc")):
        return False
    if ".runtime" in parts:
        if not relative.is_relative_to(LAB / ".runtime"):
            return False
        runtime = relative.relative_to(LAB / ".runtime").parts
        if runtime[0] == "godot":
            return len(runtime) == 2 and (relative.suffix == ".exe" or relative.name == "_sc_")
        return runtime[0] in {"python", "git", "downloads", "licenses", "ffmpeg.exe", "installed.json", "ffmpeg-version.log"}
    if relative.is_relative_to(LAB / "outputs"):
        output = relative.relative_to(LAB / "outputs").parts
        if output[0] == "jobs":
            return len(output) == 3 and output[1] in JOBS and relative.name != "video_only.mp4"
        if output[0] == "takes":
            return len(output) == 2 and output[1] in TAKES
        return output[0] in {"samples", "references", "relocation"} or (len(output) == 1 and relative.suffix in {".json", ".log"} and not (relative.suffix == ".log" and relative.name.startswith("handoff_")))
    if relative.is_relative_to(LEGACY / "outputs"):
        return relative.name in {"final.mp4", "poster.png", "contact_sheet.jpg", "config.json", "run_report.json", "export_report.json", "verification_report.json"} or len(relative.relative_to(LEGACY / "outputs").parts) == 1
    if relative.is_relative_to(LEGACY / "logs"):
        return False
    if parts[0].startswith("09_") and len(parts) == 2 and relative.name.startswith("_"):
        return False
    return True


def files_to_copy(source: Path):
    """Prune heavy caches before walking while retaining the workbench's portable runtime."""
    for directory, directories, names in os.walk(source):
        current = Path(directory)
        relative = current.relative_to(source)
        directories[:] = sorted(name for name in directories if name not in SKIP_DIRS and not (name == ".runtime" and relative != LAB))
        if relative == LAB / ".runtime":
            directories[:] = [name for name in directories if name in {"python", "git", "downloads", "licenses", "godot"}]
        if relative == LAB / ".runtime/godot":
            directories.clear()
        if relative == LAB / "outputs":
            directories[:] = [name for name in directories if name in {"samples", "references", "takes", "jobs", "relocation"}]
        if relative == LAB / "outputs/jobs":
            directories[:] = [name for name in directories if name in JOBS]
        if relative.parent == LAB / "outputs/jobs":
            directories.clear()
        for name in sorted(names):
            candidate = current / name
            if wanted(candidate.relative_to(source)):
                yield candidate


def preserve_history(source: Path, destination: Path) -> list[dict]:
    """Include repository history and any uncommitted patch without changing source staging."""
    git = source / LAB / ".runtime/git/cmd/git.exe"
    histories = []
    for relative in [Path("."), LAB, LEGACY]:
        repo = source / relative
        if not (repo / ".git").is_dir():
            continue
        label = "research" if relative == Path(".") else relative.name
        folder = destination / "version_history"
        folder.mkdir(exist_ok=True)
        command = [str(git), "-C", str(repo)]
        subprocess.run(command + ["bundle", "create", str(folder / (label + ".bundle")), "--all"], check=True, capture_output=True)
        head = subprocess.check_output(command + ["rev-parse", "HEAD"], text=True, stderr=subprocess.PIPE).strip()
        patch = subprocess.check_output(command + ["diff", "HEAD", "--binary"], stderr=subprocess.PIPE)
        untracked = subprocess.check_output(command + ["ls-files", "--others", "--exclude-standard", "-z"], stderr=subprocess.PIPE).decode("utf-8").strip("\0").split("\0")
        if patch:
            (folder / (label + "-working.patch")).write_bytes(patch)
        histories.append({"repository": relative.as_posix(), "head": head, "bundle": "version_history/" + label + ".bundle", "has_uncommitted_patch": bool(patch), "untracked_files_in_working_copy": [name for name in untracked if name]})
    return histories


def freeze_scene(source: Path, destination: Path, snapshot: Path | None) -> dict:
    """Save the latest initial layout; never replay copied command inboxes on another PC."""
    scene_path = snapshot if snapshot else source / LAB / "outputs/control/scene.current.json"
    if not scene_path.is_file():
        return {}
    for attempt in range(5):
        try:
            scene = json.loads(scene_path.read_text(encoding="utf-8-sig"))
            break
        except (OSError, json.JSONDecodeError):
            if attempt == 4:
                raise
            time.sleep(0.05)
    wav = scene.get("presentation", {}).get("audio", {}).get("wav_path", "")
    if wav:
        asset = source / LAB / wav.removeprefix("res://") if wav.startswith("res://") else Path(wav)
        if not asset.is_absolute():
            asset = source / LAB / asset
        target = destination / LAB / "assets/handoff/collision.wav"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(asset, target)
        scene["presentation"]["audio"]["wav_path"] = "res://assets/handoff/collision.wav"
    target = destination / LAB / "config/handoff_current_scene.json"
    target.write_text(json.dumps(scene, ensure_ascii=False, indent=2), encoding="utf-8")
    return {"source": scene_path.relative_to(source).as_posix(), "revision": scene.get("revision"), "scene_id": scene.get("scene_id"), "kind": "initial_layout_not_solver_state"}


def verify(destination: Path) -> dict:
    """Check every listed file's size and hash after copying or extracting."""
    manifest = json.loads((destination / "MANIFEST.json").read_text(encoding="utf-8"))
    failures = []
    root = destination.resolve()
    for entry in manifest["files"]:
        path = destination / entry["path"]
        if Path(entry["path"]).is_absolute() or not path.resolve().is_relative_to(root):
            raise ValueError("Manifest path leaves the package: " + entry["path"])
        if not path.is_file() or path.stat().st_size != entry["bytes"] or digest(path) != entry["sha256"]:
            failures.append(entry["path"])
    report = {"passed": not failures, "checked_files": len(manifest["files"]), "bytes": sum(item["bytes"] for item in manifest["files"]), "failures": failures}
    if failures:
        raise RuntimeError(json.dumps(report, ensure_ascii=False))
    return report


def build(source: Path, destination: Path, archive: Path | None, snapshot: Path | None) -> dict:
    """Create a new reviewable directory, record content hashes, then optionally zip it."""
    if destination == source or destination.is_relative_to(source) or destination.exists():
        raise ValueError("Destination must be a new directory outside the source project")
    destination.mkdir(parents=True)
    count = 0
    for path in files_to_copy(source):
        target = destination / path.relative_to(source)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
        count += 1
        if count % 250 == 0:
            print(json.dumps({"phase": "copy", "files": count}), flush=True)
    history = preserve_history(source, destination)
    scene_saved = freeze_scene(source, destination, snapshot)
    content = [{"path": path.relative_to(destination).as_posix(), "bytes": path.stat().st_size, "sha256": digest(path)} for path in sorted(destination.rglob("*")) if path.is_file()]
    manifest = {"format_version": 1, "created_utc": datetime.now(timezone.utc).isoformat(), "platform": "Windows x64", "repositories": history, "initial_scene_snapshot": scene_saved, "excluded": ["live command queues", "machine .env", "editor/browser caches", "old virtual environments", "PNG render intermediates", "legacy temporary scripts"], "self_hash_note": "MANIFEST.json is not included in its own file hash list", "files": content}
    (destination / "MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    report = verify(destination)
    if archive:
        if archive.exists() or archive.is_relative_to(source) or archive.is_relative_to(destination):
            raise ValueError("Archive must be new and outside source/destination")
        print(json.dumps({"phase": "archive", "files": len(content) + 1}), flush=True)
        with zipfile.ZipFile(archive, "w", allowZip64=True) as bundle:
            for path in sorted(destination.rglob("*")):
                if path.is_file():
                    mode = zipfile.ZIP_STORED if path.suffix.lower() in STORED else zipfile.ZIP_DEFLATED
                    bundle.write(path, Path(destination.name) / path.relative_to(destination), compress_type=mode, compresslevel=6)
        checksum = digest(archive)
        archive.with_suffix(archive.suffix + ".sha256").write_text(checksum + "  " + archive.name + "\n", encoding="utf-8")
        report.update({"archive": str(archive), "archive_bytes": archive.stat().st_size, "archive_sha256": checksum})
    return report


def main() -> None:
    """Allow the receiving AI to rebuild or verify without installing Python packages."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--destination", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--scene-snapshot", type=Path)
    parser.add_argument("--verify", type=Path)
    args = parser.parse_args()
    if args.verify:
        report = verify(args.verify.resolve())
    elif args.destination:
        report = build(args.source.resolve(), args.destination.resolve(), args.archive.resolve() if args.archive else None, args.scene_snapshot.resolve() if args.scene_snapshot else None)
    else:
        parser.error("Use --destination or --verify")
    print(json.dumps(report, ensure_ascii=True), flush=True)


if __name__ == "__main__":
    main()
