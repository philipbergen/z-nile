# Mutation check for c0343. Usage, from the worktree: ./zn run --time 1200 -- python3 -I mutants.py <clone> [ids...]
# <clone> is a separate clone under the temp folder with experiments/prototype.patch applied and this issue's
# acceptance/ copied in. Each mutant is a plausible wrong implementation of the prototype; it prints whether
# postfinish.spec (AC2, fast) and, for the ids in LAND, commit-land.spec (AC1, 30 s) turned red, and on which cases.
import os, subprocess, sys, tempfile
clone = os.path.realpath(sys.argv[1])
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here, there = common(os.path.dirname(os.path.abspath(__file__))), common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
home = os.path.join(clone, "z-nile")
ACC = ".tracker/issues/c0343/acceptance"
LG, TR = os.path.join(home, "engine/layergit.luau"), os.path.join(home, "engine/trace.luau")
ADD = '\t\t\tor name == "spend.md" -- c0343: `./zn commit` rewrites the raft\'s ledger in every commit\n'
AFTER = '\t\t\tor name == "spend.md" -- c0343: the commit that carries the final review rewrites the ledger too\n'
M = {
 "M1": (LG, ADD, ""),                                   # the worker's rule not changed
 "M2": (TR, ADD, ""),                                   # the table's rule not changed (after the finish)
 "M3": (TR, AFTER, ""),                                 # the table's rule not changed (after the table)
 "M4": (TR, ADD, '\t\t\tor string.find(name, "spend.md", 1, true) ~= nil\n'),   # any name holding spend.md, a sub-folder's too
 "M5": (LG, ADD, '\t\t\tor string.find(name, "spend.md", 1, true) ~= nil\n'),
 "M6": (TR, ADD, ADD + '\t\t\tor name == "harvest.md"\n'),   # the harvest joins the set
 "M7": (LG, "\tlocal raftDirPattern = ", '\tif string.match(path, "/spend%.md$") ~= nil then\n\t\treturn true\n\tend\n\tlocal raftDirPattern = '),  # any raft's or ticket's ledger
 "M8": (TR, AFTER, AFTER + '\t\t\tor name == "harvest.md"\n'),
 "M9": (TR, ADD, '\t\t\tor string.match(path, "/spend%.md$") ~= nil\n'),  # any ledger anywhere, the table's rule
}
LAND = {"M1", "M2", "M3"}
def run(spec):
    r = subprocess.run(["lune", "run", "tests/run", "--", f"{ACC}/{spec}"], cwd=home, capture_output=True, text=True)
    out = r.stdout + r.stderr
    if "not an assertion failure" in out:
        return "ERROR"
    fails = [l.split(":: ")[-1].strip()[:60] for l in out.splitlines() if l.startswith("FAIL") and "::" in l]
    lines = [l.strip().split(": ", 1)[0].rsplit(":", 1)[-1] for l in out.splitlines() if "commit-land.spec:" in l]
    return ("red", fails, lines) if r.returncode != 0 else "green"
print("BASE", run("postfinish.spec.luau"), run("commit-land.spec.luau"))
for mid in (sys.argv[2:] or list(M)):
    path, old, new = M[mid]
    text = open(path).read()
    assert text.count(old) == 1, (mid, "anchor not found once")
    open(path, "w").write(text.replace(old, new))
    try:
        print(mid, "AC2", run("postfinish.spec.luau"), "| AC1", run("commit-land.spec.luau") if mid in LAND else "-")
    finally:
        open(path, "w").write(text)
