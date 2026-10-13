"""Check output-cache persistence and invalidation using isolated local servers."""

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
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
source = args.save.resolve()
if args.output:
    args.output.mkdir(parents=True, exist_ok=True)
results = Path(tempfile.mkdtemp(prefix="preview-output-cache-", dir=args.output)).resolve()
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()

for phase in ("save", "reload"):
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
    control.write_text(control.read_text() + "\n" + (repo / "tests/native/preview-output-cache.lua").read_text())
    names = ["base", "quality", "elevated-rails", "recycler", "space-age", "resource-outpost-planner"]
    (root / "mods/mod-list.json").write_text(json.dumps({"mods": [{"name": name, "enabled": True} for name in names]}))
    (root / "config.ini").write_text(f"[path]\nread-data={args.data.resolve()}\nwrite-data={root / 'data'}\n[other]\ncheck-updates=false\n")
    settings = json.loads((args.data / "server-settings.example.json").read_text())
    settings.update(name="Isolated preview-cache verification", visibility={"public": False, "lan": False},
                    auto_pause=False, require_user_verification=False, autosave_interval=0)
    (root / "server.json").write_text(json.dumps(settings))
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    log_path = root / "server.log"
    with log_path.open("w") as output:
        process = subprocess.Popen([str(args.factorio.resolve()), "--config", str(root / "config.ini"),
                                    "--mod-directory", str(root / "mods"), "--start-server", str(saved),
                                    "--server-settings", str(root / "server.json"), "--bind", "127.0.0.1", "--port", str(port)],
                                   stdout=output, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                   env=dict(os.environ, SteamAppId="427520"))
        print(f"{phase}: {root} (test process {process.pid}, localhost port {port})", flush=True)
        success = False
        try:
            for _ in range(480):
                time.sleep(0.25)
                log = log_path.read_text()
                checkpoint = root / "data/saves/preview-output-cache-checkpoint.zip"
                if (phase == "save" and checkpoint.exists() and "Saving finished" in log
                        or phase == "reload" and "OUTPUT CACHE COMPLETE" in log):
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
            raise SystemExit(f"Native cache verification failed; see {log_path}")
        print("\n".join(line for line in log_path.read_text().splitlines() if "OUTPUT CACHE" in line), flush=True)
        (root / "manifest.json").write_text(json.dumps({"source": str(source), "source_sha256": original,
                                                        "archive_sha256": digest(next((root / "package").glob("*.zip"))),
                                                        "passed": True}, indent=2) + "\n")
        if phase == "save":
            source = checkpoint

(results / "result.json").write_text(json.dumps({"save_reload": True, "input_invalidation": True,
                                                 "preview_apply_parity": True, "undo_clean": True}, indent=2) + "\n")
print(f"Native output-cache checks passed: {results}")
