#!/usr/bin/env python3
# c0392 prep's window sweep: for each mutant mutants.py leaves alive in c0210's other specs (L1 to L5), does any other
# spec of the repository that reads the deploy wiring kill it? Run from the top of the prototype checkout at its
# "c0392 removed" commit (lobby-start.spec gone), with nothing uncommitted:
#   ./zn run --time 3000 -- python3 -I -u <this file> [pickman z-nile portal]   (no names: every home)
# The specs: every spec under pickman/tests, z-nile/tests and portal/tests whose text names experience.json,
# GamePlaceId, lobby.project, runtime/lobby, deploy-beta or runtime-test (git grep, below), plus every spec under
# portal/tests (git ls-files). Each home's list runs in one runner call from its home, unmutated first, then once per mutant.
import os, re, subprocess, sys

ONLY = set(sys.argv[1:])  # home names to run (default: all)

HERE = os.path.dirname(os.path.abspath(__file__))
PAT = r"experience\.json|GamePlaceId|lobby\.project|runtime/lobby|deploy-beta|runtime-test"


def grep(home):
    r = subprocess.run(["git", "grep", "-lE", PAT, "--", f"{home}/tests/**.spec.luau"], capture_output=True, text=True)
    return sorted(p[len(home) + 1:] for p in r.stdout.split())


def run(home, specs):
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=home, capture_output=True, text=True, timeout=1500)
    out = r.stdout + r.stderr
    m = re.search(r"(\d+) passed, (\d+) failed, (\d+) spec files?", out)
    fails = sorted({l.split(" :: ", 1)[0][5:].strip() + " :: " + l.split(" :: ", 1)[1].strip() for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l})
    return (m.group(0) if m else "no result line"), fails


if subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], capture_output=True, text=True).stdout:
    sys.exit("the tree has uncommitted changes")
if os.path.exists("portal/tests/acceptance/c0210/lobby-start.spec.luau"):
    sys.exit("run this on the commit with lobby-start.spec removed")
def every(home):
    r = subprocess.run(["git", "ls-files", "--", f"{home}/tests/**.spec.luau"], capture_output=True, text=True)
    return sorted(p[len(home) + 1:] for p in r.stdout.split())


sets = {"pickman": grep("pickman"), "z-nile": grep("z-nile"), "portal": every("portal")}
sets = {h: v for h, v in sets.items() if not ONLY or h in ONLY}
for home, specs in sets.items():
    print(f"{home}: {len(specs)} specs")
base = {home: run(home, specs) for home, specs in sets.items()}
for home, (line, fails) in base.items():
    print(f"unmutated {home}: {line}")
    for f in fails:
        print(f"    FAIL {f}")
# the mutant table, read from mutants.py's source without running it
src = open(os.path.join(HERE, "mutants.py")).read()
ns = {}
exec(src.split("\nMUTANTS = ")[0].split("import glob, re, subprocess, sys\n", 1)[1], ns)
exec("MUTANTS = " + src.split("\nMUTANTS = ")[1].split("\n]\n", 1)[0] + "\n]\n", ns)
for name, path, old, new, what in ns["MUTANTS"]:
    if name not in ("L1", "L2", "L3", "L4", "L5"):
        continue
    text = open(path).read()
    if text.count(old) != 1:
        print(f"{name}: NOT APPLIED")
        continue
    open(path, "w").write(text.replace(old, new))
    try:
        res = {home: run(home, specs) for home, specs in sets.items()}
    finally:
        open(path, "w").write(text)
    for home, (line, fails) in res.items():
        new_fails = [f for f in fails if f not in base[home][1]]
        print(f"{name} ({what}) {home}: {line}; new failures: {len(new_fails)}")
        for f in new_fails[:6]:
            print(f"    FAIL {f}")
if subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], capture_output=True, text=True).stdout:
    sys.exit("the tree was left changed")
