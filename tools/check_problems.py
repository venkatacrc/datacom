#!/usr/bin/env python3
"""Runs every problem's solution against its tests (and checks the starter doesn't already pass).

Uses the same harness as the apps: the code, then dc.run_tests(<tests>, globals()).
Problems that import numpy or pandas are skipped when this Python lacks them.

Usage: python3 tools/check_problems.py [--python python3] [--only substring]
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import build_library  # noqa: E402


def harness(code: str, tests: str) -> str:
    return f"{code.rstrip()}\n\n\nimport dc as _dc\n_dc.run_tests({json.dumps(tests)}, globals())\n"


def run(python: str, workdir: Path, source: str, timeout=120) -> tuple[int, int, str]:
    out = subprocess.run([python, "-u", "-c", source], cwd=workdir, capture_output=True, text=True, timeout=timeout,
                         env={"PYTHONPATH": str(workdir), "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"})
    m = re.search(r"__DC_RESULT__ (\{.*\})", out.stdout)
    if not m:
        return 0, -1, out.stdout + out.stderr
    r = json.loads(m.group(1))
    return r["passed"], r["total"], out.stdout + out.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    config = json.loads((ROOT / "sources.json").read_text())
    config["sources"] = [s for s in config["sources"] if s["type"] == "problems"]
    lib, _ = build_library.build(config, include_private=False)
    have = {m: bool(subprocess.run([args.python, "-c", f"import {m}"], capture_output=True).returncode == 0)
            for m in ("numpy", "pandas")}
    work = Path(tempfile.mkdtemp())
    shutil.copy(ROOT / "content" / "dc.py", work / "dc.py")
    problems = [p for p in lib["problems"] if args.only in p["id"]]

    def check(p):
        missing = [m for m in p["needs"] if m in have and not have[m]]
        if missing:
            return p, "skip", f"needs {', '.join(missing)}"
        ok, total, log = run(args.python, work, harness(p["solution"], p["tests"]))
        if total <= 0 or ok != total:
            return p, "FAIL", log
        s_ok, s_total, _ = run(args.python, work, harness(p["starter"], p["tests"]))
        if s_total > 0 and s_ok == s_total:
            return p, "FAIL", "the starter already passes every test"
        return p, "ok", f"{ok}/{total}"

    failures = skipped = 0
    with ThreadPoolExecutor(8) as pool:
        for p, status, info in pool.map(check, problems):
            if status == "FAIL":
                failures += 1
                print(f"FAIL {p['id']}  ({p['file']})\n{info}\n")
            elif status == "skip":
                skipped += 1
                print(f"skip {p['id']}: {info}")
    print(f"{len(problems) - failures - skipped} passed, {failures} failed, {skipped} skipped "
          f"of {len(problems)} problems ({args.python})")
    shutil.rmtree(work, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
