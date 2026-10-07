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
    info = json.loads((ROOT / "info.json").read_text(encoding="utf-8-sig"))
    name = f"{info['name']}_{info['version']}"
    args.output.mkdir(parents=True, exist_ok=True)
    archive = args.output / f"{name}.zip"
    files = []
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        parts = path.relative_to(ROOT).parts
        if any(part.startswith(".") or part == "__pycache__" for part in parts):
            continue
        if len(parts) == 1 and (path.name in ROOT_FILES or path.suffix == ".lua"):
            files.append(path)
        elif parts[0] in DIRECTORIES:
            files.append(path)
    with zipfile.ZipFile(archive, "x", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in sorted(files):
            bundle.write(path, f"{name}/{path.relative_to(ROOT).as_posix()}")
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise SystemExit("Archive verification failed")
    print(f"{archive}: {len(files)} files, {archive.stat().st_size} bytes")


if __name__ == "__main__":
    main()
