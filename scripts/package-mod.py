"""Create an installable Factorio archive without development files."""

import argparse
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = {"graphics", "gui", "layouts", "locale", "mpp", "oil", "prototypes"}
ROOT_FILES = {"info.json", "LICENSE", "changelog.txt", "thumbnail.png"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    archive = package(ROOT, args.output)
    print(f"{archive}: {archive.stat().st_size} bytes")


def source_files(root):
    """Only ship runtime assets, never development files or local credentials."""
    files = []
    candidates = list(root.iterdir())
    for directory in sorted(DIRECTORIES):
        candidates.extend((root / directory).rglob("*"))
    for path in candidates:
        if not path.is_file():
            continue
        parts = path.relative_to(root).parts
        if any(part.startswith(".") or part == "__pycache__" for part in parts):
            continue
        if len(parts) == 1 and (path.name in ROOT_FILES or path.suffix == ".lua"):
            files.append(path)
        elif parts[0] in DIRECTORIES:
            files.append(path)
    return sorted(files)


def package(root, output):
    """Build byte-identical archives regardless of checkout timestamps or permissions."""
    info = json.loads((root / "info.json").read_text(encoding="utf-8-sig"))
    name = f"{info['name']}_{info['version']}"
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"{name}.zip"
    with zipfile.ZipFile(archive, "x", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in source_files(root):
            entry = zipfile.ZipInfo(f"{name}/{path.relative_to(root).as_posix()}", (1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            bundle.writestr(entry, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise SystemExit("Archive verification failed")
    return archive


if __name__ == "__main__":
    main()
