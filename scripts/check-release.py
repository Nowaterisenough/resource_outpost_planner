"""Run offline release regressions; native Factorio tests remain separate."""

import os
from pathlib import Path
import subprocess
import sys

from lupa.lua52 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def main():
    os.chdir(ROOT)
    # Use tracked files plus source trees so local dist/ fixtures never enter syntax checks.
    lua_files = sorted({*ROOT.glob("*.lua"), *ROOT.joinpath("tests").rglob("*.lua"),
                        *(p for directory in ("gui", "layouts", "mpp", "oil", "prototypes")
                          for p in (ROOT / directory).rglob("*.lua"))})
    parse = LuaRuntime().eval("function(text, name) local f,e=load(text,name); return f~=nil,e end")
    for path in lua_files:
        ok, error = parse(path.read_text(encoding="utf-8-sig"), str(path.relative_to(ROOT)))
        if not ok:
            raise SystemExit(error)
    print(f"Lua 5.2 syntax OK: {len(lua_files)} files", flush=True)
    for path in sorted((ROOT / "tests").glob("*.lua")):
        print(f"RUN {path.relative_to(ROOT)}", flush=True)
        LuaRuntime().execute(path.read_text(encoding="utf-8-sig"))
    for path in ("scripts/check-locales.py", "tests/balancer-import.py", "tests/release.py"):
        subprocess.run([sys.executable, path], check=True)
    for path in (ROOT / "scripts").glob("*.py"):
        compile(path.read_text(), str(path), "exec")
    print("Offline release checks passed; native Factorio scenarios were not run.")


if __name__ == "__main__":
    main()
