"""Test exact balancer templates in an isolated Factorio benchmark process."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", type=Path, required=True)
    parser.add_argument("--save", type=Path, required=True, help="Existing save with player 1; read only")
    parser.add_argument("--data", type=Path, help="Factorio data directory; inferred when omitted")
    parser.add_argument("--output", type=Path, help="Parent directory for the isolated run")
    parser.add_argument("--placement-only", action="store_true", help="Check placement and filter round-trips without the flow phases")
    args = parser.parse_args()
    binary, saved = args.factorio.resolve(), args.save.resolve()
    if not binary.is_file() or not saved.is_file():
        parser.error("The Factorio executable and save must exist")
    data = args.data.resolve() if args.data else next(
        (parent / "data" for parent in binary.parents if (parent / "data/base/info.json").is_file()), None)
    if not data or not (data / "base/info.json").is_file():
        parser.error("Cannot locate Factorio data; pass --data")
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix="balancer-matrix-", dir=args.output)).resolve()
    source = REPO
    info = json.loads((source / "info.json").read_text())
    package_dir, mods = root / "package", root / "mods"
    mods.mkdir()
    subprocess.run([sys.executable, str(source / "scripts/package-mod.py"), "--output", str(package_dir)],
                   check=True, stdout=subprocess.DEVNULL)
    archive = next(package_dir.glob("*.zip"))
    digest = hashlib.sha256()
    with zipfile.ZipFile(archive) as bundle:
        for name in sorted(bundle.namelist()):
            digest.update(name.encode()); digest.update(bundle.read(name))
        bundle.extractall(mods)
    mod = mods / f"{info['name']}_{info['version']}"
    control = mod / "control.lua"
    control.write_text(control.read_text() + "\n" + (REPO / "tests/integration/balancer-matrix.lua").read_text())
    enabled = [name for name in ("base", "elevated-rails", "quality", "recycler", "space-age")
               if (data / name / "info.json").is_file()] + [info["name"]]
    (mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in enabled]}))
    config = root / "config.ini"
    config.write_text(f"[path]\nread-data={data}\nwrite-data={root / 'data'}\n[other]\ncheck-updates=false\n")
    log_path = root / "benchmark.log"
    with log_path.open("w") as output:
        result = subprocess.run([str(binary), "--config", str(config), "--mod-directory", str(mods),
                                 "--benchmark", str(saved), "--benchmark-ticks", "2" if args.placement_only else "69640", "--benchmark-runs", "1"],
                                stdout=output, stderr=subprocess.STDOUT, env=dict(os.environ, SteamAppId="427520"))
    log = log_path.read_text()
    print(root)
    lines = [line for line in log.splitlines() if "BALANCER MATRIX" in line]
    print("\n".join(lines))
    marker = "BALANCER MATRIX START" if args.placement_only else "BALANCER MATRIX COMPLETE"
    if result.returncode or marker not in log or "BALANCER MATRIX FILTERS PASSED" not in log:
        print("\n".join(log.splitlines()[-35:]))
        raise SystemExit(result.returncode or 1)
    (root / "results.json").write_text(json.dumps({"runtime_sha256": digest.hexdigest(), "checks": lines}, indent=2) + "\n")


if __name__ == "__main__":
    main()
