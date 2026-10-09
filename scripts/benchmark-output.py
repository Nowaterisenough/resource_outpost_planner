"""Profile output previews in an isolated Factorio benchmark process."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import zipfile

REPO = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--factorio", type=Path, required=True)
    parser.add_argument("--save", type=Path, required=True, help="Existing save with player 1; read only")
    parser.add_argument("--data", type=Path, help="Factorio data directory; inferred when omitted")
    parser.add_argument("--ref", help="Git revision to compare with the working tree")
    parser.add_argument("--output", type=Path, help="Parent directory for the isolated run")
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
    root = Path(tempfile.mkdtemp(prefix="output-performance-", dir=args.output)).resolve()
    source = REPO
    if args.ref:
        source = root / "source"
        source.mkdir()
        archive = root / "source.tar"
        subprocess.run(["git", "archive", "-o", str(archive), args.ref], cwd=REPO, check=True)
        with tarfile.open(archive) as bundle:
            bundle.extractall(source, filter="data")
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
    control.write_text(control.read_text() + "\n" + (REPO / "tests/integration/output-performance.lua").read_text())
    enabled = [name for name in ("base", "elevated-rails", "quality", "recycler", "space-age")
               if (data / name / "info.json").is_file()] + [info["name"]]
    (mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in enabled]}))
    config = root / "config.ini"
    config.write_text(f"[path]\nread-data={data}\nwrite-data={root / 'data'}\n[other]\ncheck-updates=false\n")
    log_path = root / "benchmark.log"
    with log_path.open("w") as output:
        result = subprocess.run([str(binary), "--config", str(config), "--mod-directory", str(mods),
                                 "--benchmark", str(saved), "--benchmark-ticks", "2200", "--benchmark-runs", "1"],
                                stdout=output, stderr=subprocess.STDOUT, env=dict(os.environ, SteamAppId="427520"))
    log = log_path.read_text()
    cases = {}
    for name, ms in re.findall(r"OUTPUT PERF TICK ([\w-]+) .*?([\d.]+)ms", log):
        case = cases.setdefault(name, {"max_tick_ms": 0})
        case["max_tick_ms"] = max(case["max_tick_ms"], float(ms))
    pattern = r"OUTPUT PERF ([\w-]+) total=.*?([\d.]+)ms ticks=(\d+) ready=(true|false) entities=(\d+) calls=(\{.*\})"
    for name, ms, ticks, ready, entities, calls in re.findall(pattern, log):
        cases.setdefault(name, {}).update(total_ms=float(ms), ticks=int(ticks), ready=ready == "true",
                                          entities=int(entities), calls=json.loads(calls))
    report = {"source": args.ref or "working-tree", "runtime_sha256": digest.hexdigest(), "cases": cases}
    (root / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(root)
    if result.returncode or "OUTPUT PERF COMPLETE" not in log:
        print("\n".join(log.splitlines()[-35:]))
        raise SystemExit(result.returncode or 1)
    for name, case in cases.items():
        print(f"{name}: total={case['total_ms']:.2f} ms, max tick={case['max_tick_ms']:.2f} ms, ready={case['ready']}")


if __name__ == "__main__":
    main()
