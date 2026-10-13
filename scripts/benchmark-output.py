"""Profile output previews in an isolated Factorio benchmark process."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
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
    baseline = parser.add_mutually_exclusive_group()
    baseline.add_argument("--ref", help="Git revision to compare with the working tree")
    baseline.add_argument("--package", type=Path, help="Previously packaged runtime to compare with the working tree")
    parser.add_argument("--scenario", choices=("outputs", "large", "move", "apply", "irregular", "contour", "load", "load-repeat"), default="outputs",
                        help="Output previews, large/irregular mines, beacon contours, station moves, or application")
    parser.add_argument("--timing-only", action="store_true",
                        help="Skip correctness snapshots and their allocations between measured requests")
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
    isolated_save = root / "input-save.zip"
    shutil.copyfile(saved, isolated_save)
    save_digest = hashlib.sha256(isolated_save.read_bytes()).hexdigest()
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
    if args.package:
        archive = args.package.resolve()
    else:
        subprocess.run([sys.executable, str(source / "scripts/package-mod.py"), "--output", str(package_dir)],
                       check=True, stdout=subprocess.DEVNULL)
        archive = next(package_dir.glob("*.zip"))
    digest = hashlib.sha256()
    with zipfile.ZipFile(archive) as bundle:
        info_files = [name for name in bundle.namelist() if len(Path(name).parts) == 2 and name.endswith("/info.json")]
        if len(info_files) != 1:
            parser.error("The runtime archive must contain one top-level mod folder")
        info = json.loads(bundle.read(info_files[0]))
        prefix = f"{info['name']}_{info['version']}/"
        if info_files[0] != prefix + "info.json":
            parser.error("Runtime folder does not match its mod name and version")
        for name in sorted(bundle.namelist()):
            if not name.startswith(prefix) or Path(name).is_absolute() or ".." in Path(name).parts:
                parser.error("Unsafe runtime archive path")
            digest.update(name.encode()); digest.update(bundle.read(name))
        bundle.extractall(mods)
    mod = mods / f"{info['name']}_{info['version']}"
    control = mod / "control.lua"
    harness = f'local output_performance_scenario = "{args.scenario}"\n'
    harness += f'local output_performance_capture = {str(not args.timing_only).lower()}\n'
    harness += (REPO / "tests/integration/output-performance.lua").read_text()
    control.write_text(control.read_text() + "\n" + harness)
    enabled = [name for name in ("base", "elevated-rails", "quality", "recycler", "space-age")
               if (data / name / "info.json").is_file()] + [info["name"]]
    (mods / "mod-list.json").write_text(json.dumps({"mods": [{"name": n, "enabled": True} for n in enabled]}))
    config = root / "config.ini"
    config.write_text(f"[path]\nread-data={data}\nwrite-data={root / 'data'}\n[other]\ncheck-updates=false\n")
    log_path = root / "benchmark.log"
    with log_path.open("w") as output:
        result = subprocess.run([str(binary), "--config", str(config), "--mod-directory", str(mods),
                                 "--benchmark", str(isolated_save), "--benchmark-ticks", "2200", "--benchmark-runs", "1"],
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
    for name, part, count, ms in re.findall(r"OUTPUT PERF DETAIL ([\w-]+) ([\w_]+) count=(\d+) .*?([\d.]+)ms", log):
        cases.setdefault(name, {}).setdefault("details", {})[part] = {"count": int(count), "ms": float(ms)}
    for name, case in cases.items():
        for suffix, field in (("", "geometry_sha256"), ("-sprites", "sprites_sha256")):
            snapshot = root / "data/script-output/output-performance" / f"{name}{suffix}.json"
            if snapshot.is_file():
                rows = [json.dumps(row, sort_keys=True) for row in json.loads(snapshot.read_text())]
                case[field] = hashlib.sha256("\n".join(sorted(rows)).encode()).hexdigest()
                if suffix:
                    case["sprite_order_sha256"] = hashlib.sha256("\n".join(rows).encode()).hexdigest()
    report = {"source": args.ref or (str(args.package) if args.package else "working-tree"), "scenario": args.scenario,
              "capture_snapshots": not args.timing_only,
              "runtime_sha256": digest.hexdigest(), "save_sha256": save_digest, "cases": cases}
    (root / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(root)
    if result.returncode or "OUTPUT PERF COMPLETE" not in log:
        print("\n".join(log.splitlines()[-35:]))
        raise SystemExit(result.returncode or 1)
    for name, case in cases.items():
        print(f"{name}: total={case['total_ms']:.2f} ms, max tick={case['max_tick_ms']:.2f} ms, ready={case['ready']}")


if __name__ == "__main__":
    main()
