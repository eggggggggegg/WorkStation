#!/usr/bin/env python3
"""Persist large workspace files as GitHub-safe chunks and reconstruct them on load."""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import sys
from pathlib import Path

CHUNK_SIZE = 45 * 1024 * 1024
MANIFEST_NAME = "manifest.json"
PART_SIZE = 8 * 1024 * 1024

# These are runtime/cache/toolchain directories rather than user-authored workspace data.
EXCLUDED_PREFIXES = {
    ".cache",
    ".local/share/Trash",
    ".config/Code/Cache",
    ".config/Code/CachedData",
    ".config/Code/logs",
    ".npm",
    ".cargo/registry",
    ".cargo/git",
    ".rustup",
    ".config/workstation/runtime",
    ".workstation-chunks",
}

# Never copy common credential stores into a Git repository.
EXCLUDED_SECRET_PREFIXES = {
    ".ssh",
    ".gnupg",
    ".aws",
    ".azure",
    ".config/gh",
    ".config/gcloud",
    ".kube",
}
EXCLUDED_SECRET_NAMES = {
    ".env",
    ".env.local",
    ".env.production",
    "credentials.json",
    "token.json",
    "cookies.sqlite",
    "key4.db",
    "logins.json",
    "Login Data",
    "Cookies",
}


def norm_rel(path: Path) -> str:
    return path.as_posix().lstrip("./")


def excluded(rel: str) -> bool:
    rel = rel.rstrip("/")
    parts = rel.split("/")
    if not rel:
        return False
    if parts[0] in EXCLUDED_SECRET_PREFIXES:
        return True
    if any(part in EXCLUDED_SECRET_NAMES for part in parts):
        return True
    for prefix in EXCLUDED_PREFIXES:
        if rel == prefix or rel.startswith(prefix + "/"):
            return True
    return False


def safe_join(root: Path, rel: str) -> Path:
    root = root.resolve()
    out = (root / rel).resolve()
    if os.path.commonpath((str(root), str(out))) != str(root):
        raise RuntimeError(f"manifest path escapes workspace: {rel}")
    return out


def sha256_file(path: Path) -> tuple[str, int]:
    h = hashlib.sha256()
    size = 0
    with path.open("rb") as f:
        while True:
            block = f.read(PART_SIZE)
            if not block:
                break
            size += len(block)
            h.update(block)
    return h.hexdigest(), size


def chunk_file(path: Path, chunk_dir: Path) -> list[str]:
    tmp = chunk_dir.with_name(chunk_dir.name + ".tmp")
    if tmp.exists():
        shutil.rmtree(tmp)
    tmp.mkdir(parents=True)

    names: list[str] = []
    index = 1
    with path.open("rb") as src:
        while True:
            data = src.read(CHUNK_SIZE)
            if not data:
                break
            name = f"part-{index:06d}"
            (tmp / name).write_bytes(data)
            names.append(name)
            index += 1

    if chunk_dir.exists():
        shutil.rmtree(chunk_dir)
    tmp.rename(chunk_dir)
    return names


def save(source: Path, store: Path) -> None:
    store.mkdir(parents=True, exist_ok=True)
    manifest_path = store / MANIFEST_NAME
    old: dict = {}
    if manifest_path.exists():
        try:
            old = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception:
            old = {}

    old_files = old.get("files", {})
    files: dict[str, dict] = {}

    for base, dirs, names in os.walk(source, topdown=True, followlinks=False):
        base_path = Path(base)
        rel_base = norm_rel(base_path.relative_to(source))
        if rel_base == ".":
            rel_base = ""

        dirs[:] = [
            d for d in dirs
            if not excluded(norm_rel(Path(rel_base) / d))
        ]

        for name in names:
            path = base_path / name
            rel = norm_rel(path.relative_to(source))
            if excluded(rel):
                continue

            try:
                st = path.stat()
            except FileNotFoundError:
                continue
            if not stat.S_ISREG(st.st_mode) or st.st_size <= CHUNK_SIZE:
                continue

            digest, size = sha256_file(path)
            key = hashlib.sha256(rel.encode("utf-8")).hexdigest()[:32]
            chunk_dir = store / key
            # A previous version of persistence may have copied this large
            # file directly. Remove that oversized destination before Git
            # staging; the chunk store becomes the canonical representation.
            destination_file = store.parent / rel
            if destination_file.is_file() or destination_file.is_symlink():
                destination_file.unlink()
            elif destination_file.exists():
                shutil.rmtree(destination_file)
            previous = old_files.get(rel)
            chunks = previous.get("chunks", []) if isinstance(previous, dict) else []

            valid = (
                isinstance(previous, dict)
                and previous.get("sha256") == digest
                and previous.get("size") == size
                and chunks
                and all((chunk_dir / part).is_file() for part in chunks)
            )
            if not valid:
                chunks = chunk_file(path, chunk_dir)

            files[rel] = {
                "sha256": digest,
                "size": size,
                "mode": stat.S_IMODE(st.st_mode),
                "chunks": chunks,
            }

    # Remove chunk directories belonging to files that no longer exist.
    live_keys = {
        hashlib.sha256(rel.encode("utf-8")).hexdigest()[:32]
        for rel in files
    }
    for child in store.iterdir():
        if child.name in {MANIFEST_NAME, "manifest.json.tmp"}:
            continue
        if child.is_dir() and child.name not in live_keys:
            shutil.rmtree(child)

    manifest = {
        "format": 1,
        "chunk_size": CHUNK_SIZE,
        "files": files,
    }
    tmp_manifest = store / "manifest.json.tmp"
    tmp_manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    tmp_manifest.replace(manifest_path)


def load(source: Path, target: Path) -> None:
    manifest_path = source / MANIFEST_NAME
    if not manifest_path.exists():
        return

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    for rel, meta in manifest.get("files", {}).items():
        if excluded(rel):
            continue
        if not isinstance(meta, dict):
            continue
        chunks = meta.get("chunks")
        if not chunks:
            continue

        output = safe_join(target, rel)
        output.parent.mkdir(parents=True, exist_ok=True)
        tmp = output.with_name(output.name + ".workstation-rebuild")

        with tmp.open("wb") as dst:
            for part in chunks:
                part_path = source / hashlib.sha256(rel.encode("utf-8")).hexdigest()[:32] / part
                if not part_path.is_file():
                    raise RuntimeError(f"missing chunk for {rel}: {part}")
                with part_path.open("rb") as src:
                    shutil.copyfileobj(src, dst, length=PART_SIZE)

        digest, size = sha256_file(tmp)
        if digest != meta.get("sha256") or size != meta.get("size"):
            tmp.unlink(missing_ok=True)
            raise RuntimeError(f"checksum mismatch while rebuilding {rel}")

        os.chmod(tmp, int(meta.get("mode", 0o644)))
        tmp.replace(output)


def main() -> int:
    if len(sys.argv) != 4 or sys.argv[1] not in {"save", "load"}:
        print(f"usage: {Path(sys.argv[0]).name} {{save|load}} <source> <store>", file=sys.stderr)
        return 2

    action = sys.argv[1]
    source = Path(sys.argv[2]).resolve()
    store = Path(sys.argv[3]).resolve()

    if action == "save":
        save(source, store)
    else:
        load(store, source)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
