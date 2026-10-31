"""Verify adaptive beacons and native forced placement in an isolated server."""

import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--factorio", type=Path, required=True)
parser.add_argument("--data", type=Path, required=True)
parser.add_argument("--save", type=Path, required=True)
parser.add_argument("--output", type=Path)
parser.add_argument("--suite", choices=["placement", "ore-filter", "dual-belts", "scenario-matrix", "terrain-warnings", "consecutive-placement", "lava-routes", "lava-mine", "lava-terrain"], default="placement", help="Headless native checks")
parser.add_argument("--visual", action="store_true", help="Render native underground belts beside preview artwork in an isolated game")
parser.add_argument("--scene", choices=["shoreline", "gui", "capacity", "large-mine", "dual-belts", "lava-routes", "lava-mine", "lava-terrain"], help="Capture a native placement or configuration GUI scenario")
parser.add_argument("--capacity-matrix", action="store_true", help="Audit dense beacon and fluid capacity layouts in all four rotations")
parser.add_argument("--no-auto-belts", action="store_true", help="Test large-mine layouts with automatic belt merging/splitting disabled")
parser.add_argument("--dense-matrix", action="store_true", help="Audit both dense layouts in all four rotations")
parser.add_argument("--headless-scene", action="store_true", help="Run scene audits without screenshots")
parser.add_argument("--case", type=int, help="Run one large-mine or lava-routing scenario (1-based)")
parser.add_argument("--from-case", type=int, help="Resume the headless lava matrix from this 1-based case")
parser.add_argument("--through-case", type=int, help="Stop the headless lava matrix after this 1-based case")
parser.add_argument("--large-cases", type=Path, help="JSON array of large-mine settings for repeatable visual coverage")
parser.add_argument("--timeout", type=float, default=120, help="Maximum scene runtime in seconds")
parser.add_argument("--power-coverage", action="store_true", help="Overlay native pole supply areas in the capacity scene")
parser.add_argument("--locale", choices=["en", "zh-CN"], default="zh-CN", help="Language for visual checks")
parser.add_argument("--ui-scale", type=float, default=1, help="UI scale for visual checks")
parser.add_argument("--window-size", default="1600x1000", help="Window resolution for visual checks")
args = parser.parse_args()
if (args.large_cases or args.headless_scene or args.dense_matrix or args.capacity_matrix or args.no_auto_belts) and args.scene != "large-mine":
    parser.error("--case, --headless-scene and --dense-matrix require --scene large-mine")
if (args.dense_matrix or args.capacity_matrix) and not args.headless_scene:
    parser.error("--dense-matrix requires --headless-scene")
large_cases = None
large_case_names = ["01-compact-iron", "02-staggered-copper", "03-beacon-tungsten", "04-piped-uranium"]
if args.large_cases:
    if args.dense_matrix or args.capacity_matrix:
        parser.error("--large-cases cannot be combined with a built-in matrix")
    large_cases = json.loads(args.large_cases.read_text())
    if not isinstance(large_cases, list) or not large_cases:
        parser.error("--large-cases must contain a non-empty JSON array")
    large_case_names = [case["id"] for case in large_cases]
    if len(set(large_case_names)) != len(large_case_names) or any(not re.fullmatch(r"[a-zA-Z0-9_-]+", name) for name in large_case_names):
        parser.error("large-mine ids must be unique safe filenames")
if args.from_case is not None or args.through_case is not None:
    if args.scene or args.visual or args.suite not in ("lava-routes", "lava-mine", "lava-terrain") or args.case:
        parser.error("--from-case/--through-case require a headless lava suite and cannot be combined with --case")
    count = 36 if args.suite == "lava-terrain" else 50 if args.suite == "lava-mine" else 34
    if not 1 <= (args.from_case if args.from_case is not None else 1) <= (args.through_case if args.through_case is not None else count) <= count:
        parser.error("invalid lava case range")
if args.case is not None and args.case < 1:
    parser.error("--case must be positive")
if args.case and args.scene not in ("large-mine", "lava-routes", "lava-mine", "lava-terrain") and args.suite not in ("lava-routes", "lava-mine", "lava-terrain"):
    parser.error("--case requires large-mine or lava-routes")
if args.case is not None and args.scene == "large-mine" and not 1 <= args.case <= len(large_case_names):
    parser.error("--case is outside the scenario list")
large_override = "\nlocal large_case_overrides=helpers.json_to_table(" + json.dumps(json.dumps(large_cases)) + ")\n" if large_cases else ""
visual = args.visual or args.scene is not None
repo = Path(__file__).resolve().parents[1]
source = args.save.resolve()
if args.output:
    args.output.mkdir(parents=True, exist_ok=True)
results = Path(tempfile.mkdtemp(prefix="placement-", dir=args.output)).resolve()
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

for phase in ("placement",):
    root = results / phase
    (root / "mods").mkdir(parents=True)
    (root / "data/saves").mkdir(parents=True)
    original = digest(source)
    saved = root / "input-save.zip"
    shutil.copyfile(source, saved)
    assert digest(saved) == original
    subprocess.run([sys.executable, str(repo / "scripts/package-mod.py"), "--output", str(root / "package")], check=True)
    with zipfile.ZipFile(next((root / "package").glob("*.zip"))) as archive:
        archive.extractall(root / "mods")
    mod = next(p for p in (root / "mods").iterdir() if p.is_dir())
    control = mod / "control.lua"
    fixture = {"shoreline": "shoreline-artwork.lua", "gui": "gui.lua", "capacity": "belt-capacity.lua", "large-mine": "large-mine-artwork.lua", "dual-belts": "dual-belts.lua", "lava-routes": "lava-routes.lua", "lava-mine": "lava-routes.lua", "lava-terrain": "lava-routes.lua"}[args.scene] if args.scene else "underground-artwork.lua" if args.visual else "lava-routes.lua" if args.suite in ("lava-mine", "lava-terrain") else args.suite + ".lua"
    control.write_text(control.read_text() + large_override + (f"\nlocal large_case_filter={args.case or 'nil'};local large_headless={str(args.headless_scene).lower()};local large_dense_matrix={str(args.dense_matrix).lower()};local large_capacity_matrix={str(args.capacity_matrix).lower()};local large_auto_belts={str(not args.no_auto_belts).lower()}\n" if args.scene == "large-mine" else "") + (f"\nlocal cap_visual=true;local cap_power_visual={str(args.power_coverage).lower()}\n" if args.scene == "capacity" else "\n") + ("\nlocal dual_visual=true\n" if args.scene == "dual-belts" else "") + (f"\nlocal lava_case_filter={args.case or 'nil'};local lava_case_start={args.from_case or 'nil'};local lava_case_end={args.through_case or 'nil'};local lava_visual={str(args.scene in ('lava-routes', 'lava-mine', 'lava-terrain')).lower()};local lava_internal={str(args.scene in ('lava-mine', 'lava-terrain') or args.suite in ('lava-mine', 'lava-terrain')).lower()};local lava_diverse={str(args.scene == 'lava-terrain' or args.suite == 'lava-terrain').lower()}\n" if fixture == "lava-routes.lua" else "") + (repo / "tests/native" / fixture).read_text())
    names = ["base", "quality", "elevated-rails", "recycler", "space-age", "resource-outpost-planner"]
    (root / "mods/mod-list.json").write_text(json.dumps({"mods": [{"name": name, "enabled": True} for name in names]}))
    (root / "config.ini").write_text(f"[path]\nread-data={args.data.resolve()}\nwrite-data={root / 'data'}\n[other]\ncheck-updates=false\n[general]\nlocale={args.locale}\n[graphics]\nfull-screen=false\n[interface]\nui-scale-mode=manual-pixels\ncustom-ui-scale={args.ui_scale}\n")
    settings = json.loads((args.data / "server-settings.example.json").read_text())
    settings.update(name="Isolated placement verification", visibility={"public": False, "lan": False},
                    auto_pause=False, require_user_verification=False, autosave_interval=0)
    (root / "server.json").write_text(json.dumps(settings))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    log_path = root / "server.log"
    with log_path.open("w") as output:
        startup = ["--load-game", str(saved), "--window-size", args.window_size] if visual and not args.headless_scene else ["--start-server", str(saved),
                   "--server-settings", str(root / "server.json"), "--bind", "127.0.0.1", "--port", str(port)]
        process = subprocess.Popen([str(args.factorio.resolve()), "--config", str(root / "config.ini"),
                                    "--mod-directory", str(root / "mods"), *startup],
                                   stdout=output, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   env=dict(os.environ, SteamAppId="427520"))
        print(f"{phase}: {root} (test process {process.pid}, localhost port {port})", flush=True)
        success = False
        try:
            for _ in range(int(args.timeout * 4)):
                time.sleep(0.25)
                log = log_path.read_text()
                screenshot = root / "data/script-output/underground-artwork.png"
                if args.scene in ("lava-routes", "lava-mine", "lava-terrain"):
                    screenshot = root / "data/script-output/lava-routing-complete.png"
                if args.scene == "shoreline":
                    screenshot = root / "data/script-output/shoreline-applied.png"
                if args.scene == "gui":
                    screenshot = root / "data/script-output/gui-oil.png"
                if args.scene == "dual-belts":
                    screenshot = root / "data/script-output/dual-belts-2.png"
                if args.scene == "capacity":
                    screenshot = root / "data/script-output/capacity-layout.png"
                if args.scene == "large-mine":
                    screenshot = root / "data/script-output" / (large_case_names[(args.case or len(large_case_names))-1] + "-detail.png")
                if (args.scene == "large-mine" and (args.headless_scene or screenshot.exists()) and "LARGE MINE SCENE COMPLETE" in log
                        or args.scene in ("lava-routes", "lava-mine", "lava-terrain") and screenshot.exists() and "PLACEMENT COMPLETE" in log
                        or args.scene == "dual-belts" and screenshot.exists() and "PLACEMENT COMPLETE: dual belt native throughput" in log
                        or args.scene == "capacity" and screenshot.exists() and "CAPACITY SCENE COMPLETE" in log
                        or args.scene == "gui" and screenshot.exists() and "GUI SCENE COMPLETE" in log
                        or args.scene == "shoreline" and screenshot.exists() and "PLACEMENT SCENE COMPLETE" in log
                        or args.visual and not args.scene and screenshot.exists() and screenshot.stat().st_size > 0
                        or not visual and "PLACEMENT COMPLETE" in log):
                    success = True
                    break
                if "LARGE MINE FAILED" in log or "Error while running event" in log or process.poll() is not None:
                    break
        finally:
            # Only stop the child created by this invocation, never another game.
            if process.poll() is None:
                process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.terminate()
                    process.wait(timeout=15)
        assert digest(source) == original, "Source save changed"
        if not success:
            print("\n".join(log_path.read_text().splitlines()[-35:]))
            raise SystemExit(f"Native placement verification failed; see {log_path}")
        print("\n".join(line for line in log_path.read_text().splitlines() if "PLACEMENT" in line or "GUI " in line or "LARGE MINE" in line), flush=True)
        (root / "manifest.json").write_text(json.dumps({"source": str(source), "source_sha256": original,
                                                        "archive_sha256": digest(next((root / "package").glob("*.zip"))),
                                                        "completed": True, "passed": None if args.suite == "lava-terrain" or args.scene == "lava-terrain" else True}, indent=2) + "\n")

if args.scene == "large-mine":
    report_path = root / "data/script-output/large-mine-result.json"
    reports = json.loads(report_path.read_text())
    timings = {(case, phase): float(ms) for case, phase, ms in re.findall(
        r"LARGE MINE TIMING (\S+) (mine|output) .*?([0-9.]+)ms", log_path.read_text())}
    for report in reports:
        for phase in ("mine", "output"):
            report.pop(phase + "_time", None)
            report[phase + "_task_ms"] = timings.get((report["case"]["id"], phase))
    report_path.write_text(json.dumps(reports, ensure_ascii=False, indent=2) + "\n")
result = ({"native_scene_audit": args.scene} if args.headless_scene
          else {"artwork_screenshot": str(screenshot)} if visual else {"terrain_survey_completed": True} if args.suite == "lava-terrain" else {"native_placement": True})
(results / "result.json").write_text(json.dumps(result, indent=2) + "\n")
print(f"{'Native scene audits passed' if args.headless_scene else 'Native artwork rendered' if visual else 'Native terrain survey completed (inspect scenario results)' if args.suite == 'lava-terrain' else 'Native placement checks passed'}: {results}")
