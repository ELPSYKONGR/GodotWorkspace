"""Validate packaging with small fixtures; actual tools and GPU migration are tested separately."""
from __future__ import annotations

import contextlib
import hashlib
import json
from pathlib import Path
import traceback
import uuid
import zipfile

import build_handoff as packaging


LAB_ROOT = Path(__file__).resolve().parents[1]


def write(path: Path, content: str) -> None:
    """Create a fixture file without touching existing projects or clearing directories."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def run() -> dict:
    """Exercise rebuilding, integrity, exclusions and extraction in a new retained folder."""
    folder = LAB_ROOT / "scratch" / ("handoff_validation_" + uuid.uuid4().hex[:12])
    folder.mkdir(parents=True)
    source, first, second = (folder / name for name in ("source", "first-package", "second-package"))
    archive = folder / "handoff.zip"
    checks = []

    def check(name: str, action) -> None:
        """Keep failures visible while allowing independent checks to report their outcome."""
        try:
            evidence = action()
            checks.append({"name": name, "passed": True, "evidence": evidence})
            print("PASS " + name)
        except Exception as error:
            checks.append({"name": name, "passed": False, "error": str(error)})
            traceback.print_exc()

    with (folder / "validation.log").open("w", encoding="utf-8") as log:
        with contextlib.redirect_stdout(log), contextlib.redirect_stderr(log):
            included = {
                Path("README.md"): "handoff fixture documentation\n",
                packaging.LAB / "config" / "example.json": '{"fixture":true}',
                packaging.LAB / ".runtime/python/python.exe": "fixture executable, not a Python runtime",
                packaging.LAB / ".runtime/python/Lib/site-packages/fixture.py": "fixture = True\n",
                packaging.LAB / ".runtime/godot/Godot_fixture.exe": "fixture, not an engine",
                packaging.LAB / ".runtime/godot/_sc_": "",
                packaging.LAB / ".runtime/ffmpeg.exe": "fixture, not an encoder",
                Path("09_references/original_videos/douyin/fixture.mp4"): "fixture media, not playable video",
            }
            excluded = [
                Path(".env"), packaging.LAB / ".env",
                packaging.LAB / "outputs/control/inbox/pending.json",
                packaging.LAB / "outputs/control/results/old.json",
                packaging.LAB / ".godot/editor/cache.bin",
                packaging.LAB / ".runtime/appdata/local/cache.bin",
                packaging.LEGACY / ".venv/pyvenv.cfg",
                packaging.LEGACY / "node_modules/fixture/package.json",
            ]
            for relative, content in included.items():
                write(source / relative, content)
            for relative in excluded:
                write(source / relative, "machine state must not travel")
            write(source / "MANIFEST.json", '{"old_manifest":true}')

            def rebuild():
                """A package containing its old manifest must be usable as the next source."""
                packaging.build(source, first, None, None)
                packaging.build(first, second, archive, None)
                manifest = json.loads((second / "MANIFEST.json").read_text(encoding="utf-8"))
                assert all(entry["path"] != "MANIFEST.json" for entry in manifest["files"])
                report = packaging.verify(second)
                assert report["passed"]
                return {"checked_files": report["checked_files"], "builds": 2}

            check("rebuild_excludes_old_manifest_and_verifies", rebuild)

            def exclusions():
                """Observe actual copied output rather than merely testing the selector."""
                leaked = [path.as_posix() for path in excluded if (first / path).exists()]
                assert not leaked, leaked
                return {"excluded_fixture_files": len(excluded)}

            check("machine_env_live_queues_and_caches_excluded", exclusions)

            def preservation():
                """Portable tool paths and original-media bytes must survive both copies."""
                for relative in included:
                    assert (second / relative).read_bytes() == (source / relative).read_bytes(), relative
                return {"preserved_fixture_files": len(included), "real_tools_verified": False}

            check("runtime_and_original_media_preserved", preservation)

            def reject_escape(absolute: bool):
                """Reject outside paths before attempting to hash the external sentinel."""
                target = folder / ("absolute-attack" if absolute else "parent-attack")
                outside = folder / "outside.txt"
                write(outside, "external sentinel")
                entry = str(outside) if absolute else "../outside.txt"
                write(target / "MANIFEST.json", json.dumps({"files": [{"path": entry,
                    "bytes": outside.stat().st_size, "sha256": hashlib.sha256(outside.read_bytes()).hexdigest()}]}))
                original_digest = packaging.digest
                attempts = []

                def guarded_digest(path):
                    if not path.resolve().is_relative_to(target.resolve()):
                        attempts.append(str(path))
                        raise AssertionError("attempted outside-file read")
                    return original_digest(path)

                packaging.digest = guarded_digest
                rejected = False
                try:
                    try:
                        packaging.verify(target)
                    except ValueError:
                        rejected = True
                finally:
                    packaging.digest = original_digest
                assert rejected and not attempts
                return {"rejected": True, "outside_hash_attempts": len(attempts)}

            check("absolute_manifest_path_rejected_before_read", lambda: reject_escape(True))
            check("parent_manifest_path_rejected_before_read", lambda: reject_escape(False))

            def extraction():
                """Check ZIP CRC, relative entries, extraction, file hashes and checksum sidecar."""
                with zipfile.ZipFile(archive) as bundle:
                    assert bundle.testzip() is None
                    names = bundle.namelist()
                    assert names and all(name.startswith(second.name + "/") and ".." not in Path(name).parts for name in names)
                    assert second.name + "/MANIFEST.json" in names
                    bundle.extractall(folder / "extracted")
                report = packaging.verify(folder / "extracted" / second.name)
                checksum, filename = archive.with_suffix(".zip.sha256").read_text(encoding="utf-8").strip().split("  ", 1)
                assert checksum == packaging.digest(archive) and filename == archive.name
                return {"zip_entries": len(names), "extracted_files": report["checked_files"], "sidecar_matches": True}

            check("zip_crc_extraction_and_sidecar", extraction)

            def tampering():
                """Change bytes without changing length so the content hash must detect damage."""
                extracted = folder / "extracted" / second.name
                changed = extracted / "README.md"
                original = changed.read_bytes()
                changed.write_bytes(bytes([original[0] ^ 1]) + original[1:])
                try:
                    packaging.verify(extracted)
                except RuntimeError as error:
                    failure = json.loads(str(error))
                    assert "README.md" in failure["failures"] and not failure["passed"]
                    return {"same_length_corruption_detected": True, "failures": failure["failures"]}
                raise AssertionError("changed bytes were accepted")

            check("changed_content_explicitly_fails_verify", tampering)

    return {"passed": bool(checks) and all(item["passed"] for item in checks), "checks": checks,
        "fixture_directory": folder.relative_to(LAB_ROOT).as_posix(),
        "scope": "Small text fixtures at exe/mp4 paths; no real tool, Git-history or GPU migration claims."}


if __name__ == "__main__":
    result = run()
    output = LAB_ROOT / "outputs/handoff_validation.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=True))
    raise SystemExit(0 if result["passed"] else 1)
