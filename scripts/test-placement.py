"""Verify adaptive beacons and native forced placement in an isolated server."""

import argparse
import hashlib
import json
import os
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
parser.add_argument("--visual", action="store_true", help="Render native underground belts beside preview artwork in an isolated game")
parser.add_argument("--scene", choices=["shoreline", "gui"], help="Capture the large irregular lava-shore scenario")
parser.add_argument("--locale", choices=["en", "zh-CN"], default="zh-CN")
parser.add_argument("--ui-scale", type=float, default=1)
parser.add_argument("--window-size", default="1600x1000")
parser.add_argument("--suite", choices=["placement", "ore-filter"], default="placement", help="Headless native checks")
args = parser.parse_args()
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
    fixture = ("gui.lua" if args.scene == "gui" else "shoreline-artwork.lua") if args.scene else "underground-artwork.lua" if args.visual else args.suite + ".lua"
    control.write_text(control.read_text() + "\n" + (repo / "tests/native" / fixture).read_text())
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
        startup = ["--load-game", str(saved), "--window-size", args.window_size] if visual else ["--start-server", str(saved),
                   "--server-settings", str(root / "server.json"), "--bind", "127.0.0.1", "--port", str(port)]
        process = subprocess.Popen([str(args.factorio.resolve()), "--config", str(root / "config.ini"),
                                    "--mod-directory", str(root / "mods"), *startup],
                                   stdout=output, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   env=dict(os.environ, SteamAppId="427520"))
        print(f"{phase}: {root} (test process {process.pid}, localhost port {port})", flush=True)
        success = False
        try:
            for _ in range(480):
                time.sleep(0.25)
                log = log_path.read_text()
                screenshot = root / "data/script-output/underground-artwork.png"
                if args.scene == "shoreline":
                    screenshot = root / "data/script-output/shoreline-applied.png"
                if args.scene == "gui":
                    screenshot = root / "data/script-output/gui-oil.png"
                if (args.scene == "gui" and screenshot.exists() and "GUI SCENE COMPLETE" in log
                        or args.scene == "shoreline" and screenshot.exists() and "PLACEMENT SCENE COMPLETE" in log
                        or args.visual and not args.scene and screenshot.exists() and screenshot.stat().st_size > 0
                        or not visual and "PLACEMENT COMPLETE" in log):
                    success = True
                    break
                if process.poll() is not None:
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
        print("\n".join(line for line in log_path.read_text().splitlines() if "PLACEMENT" in line or "GUI " in line), flush=True)
        (root / "manifest.json").write_text(json.dumps({"source": str(source), "source_sha256": original,
                                                        "archive_sha256": digest(next((root / "package").glob("*.zip"))),
                                                        "passed": True}, indent=2) + "\n")

result = {"artwork_screenshot": str(screenshot)} if visual else {"native_placement": True}
(results / "result.json").write_text(json.dumps(result, indent=2) + "\n")
print(f"{'Native artwork rendered' if visual else 'Native placement checks passed'}: {results}")
