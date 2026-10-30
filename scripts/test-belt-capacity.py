#!/usr/bin/env python3
"""Run capacity integration tests in Factorio using an isolated copy of a save."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--factorio", type=Path, required=True)
parser.add_argument("--save", type=Path, required=True)
parser.add_argument("--data", type=Path, required=True)
parser.add_argument("--package", type=Path, help="Use a saved package as a timing baseline")
parser.add_argument("--cases", type=int, help="Run the first N geometry cases")
parser.add_argument("--fresh-grid", action="store_true", help="Verify against rebuilding ore grids on every pass")
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
root = Path(tempfile.mkdtemp(prefix="outpost-capacity-test-"))
(root / "mods").mkdir()
(root / "data").mkdir()
save = root / "input-save.zip"
shutil.copyfile(args.save, save)
digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert digest(save) == digest(args.save)
if args.package:
    package = args.package
else:
    subprocess.run(["python3", str(repo / "scripts/package-mod.py"), "--output", str(root / "package")], check=True)
    package = next((root / "package").glob("*.zip"))
with zipfile.ZipFile(package) as archive:
    archive.extractall(root / "mods")
mod = next(p for p in (root / "mods").iterdir() if p.is_dir())
control = mod / "control.lua"
flags = f"\nlocal cap_case_limit={args.cases or 'nil'};local cap_fresh_grid={str(args.fresh_grid).lower()}\n"
control.write_text(control.read_text() + flags + (repo / "tests/native/belt-capacity.lua").read_text())
names = ["base", "elevated-rails", "quality", "recycler", "space-age", "resource-outpost-planner"]
(root / "mods/mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in names]}))
(root / "config.ini").write_text(f"[path]\nread-data={args.data}\nwrite-data={root / 'data'}\n[other]\ncheck-updates=false\n")
print(root, flush=True)
with (root / "benchmark.log").open("w") as output:
    result = subprocess.run([str(args.factorio), "--config", str(root / "config.ini"), "--mod-directory",
                             str(root / "mods"), "--benchmark", str(save), "--benchmark-ticks", "10000",
                             "--benchmark-runs", "1"], stdout=output, stderr=subprocess.STDOUT,
                            env=dict(os.environ, SteamAppId="427520"))
log = (root / "benchmark.log").read_text()
print("\n".join(line for line in log.splitlines() if any(tag in line for tag in ("CAPACITY COMPLETE", "CAPACITY REGRESSIONS", "CAPACITY WORKFLOW", "Error"))))
if result.returncode or "CAPACITY COMPLETE" not in log:
    print("\n".join(log.splitlines()[-30:]))
    raise SystemExit(f"Native capacity test failed; see {root / 'benchmark.log'}")
