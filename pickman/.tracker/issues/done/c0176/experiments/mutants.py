# Mutation check for c0176. Usage: python3 -I mutants.py <clone> [ids...]
# <clone> is a separate clone under the temp folder with experiments/narrow.patch applied and this issue's
# acceptance/ copied in. Each mutant weakens a narrowed promoted spec (or a check.sh); narrowed.spec must fail on
# an assertion. Prints which of narrowed.spec's cases failed for each.
import os, subprocess, sys, tempfile
clone = os.path.realpath(sys.argv[1])
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here, there = common(os.path.dirname(os.path.abspath(__file__))), common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
home = os.path.join(clone, "pickman")
SPEC = ".tracker/issues/c0176/acceptance/narrowed.spec.luau"
A = lambda p: os.path.join(home, "tests/acceptance", p)
M = {
 "N1": (A("f0101/airborne.spec.luau"), "\tlocal s = Session.new(classic, 1, CLASSIC_GAME)\n\tSession.join(s, \"p\")\n\treturn s\n",
        "\tlocal s = Session.new(classic, 1, Session.GAME_CONFIG)\n\tSession.join(s, \"p\")\n\treturn s\n"),
 "N2": (A("f0100/shots.spec.luau"), "the last pellet's clear\nlocal CLASSIC_GAME", "the last pellet's clear local CLASSIC_GAME"),
 "N3": (A("f0100/drops.spec.luau"), "table.clone(Session.GAME_CONFIG) :: any", "table.clone(Session.DEFAULT_CONFIG) :: any"),
 "N4": (A("f0023/session-ghosts.spec.luau"), "CLASSIC_GAME.ramp = nil\n", ""),
 "N5": (A("f0023/session-ghosts.spec.luau"), "\t\t\tt.expect(Session.GAME_CONFIG.ghosts).toBe(true)\n", ""),
 "N6": (A("c0153/golden.spec.luau"), '\t\tsha = "611b2ed37535ad74fb53fc216693f6e13708e18bb9b106e2079ebbca0a89feb7",\n',
        '\t\tsha = "bd7fe073fa4193702568cf6e415b925b6e5d305fa2608d98b880af2bab1bc249",\n'),
 "N7": (os.path.join(home, ".tracker/issues/done/f0100/check.sh"), 'check "AC3:', '# check "AC3:'),
 "N8": (A("f0100/shots.spec.luau"), "local s = Session.new(CORRIDOR, 1, CLASSIC_GAME)", "local s = Session.new(CORRIDOR, 1, table.clone(CLASSIC_GAME))"),
}
def run():
    r = subprocess.run(["lune", "run", "tests/run", "--", SPEC], cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
code, out = run()
print("BASE", "pass" if code == 0 else "FAIL", out.strip().splitlines()[-1])
for mid in (sys.argv[2:] or list(M)):
    path, old, new = M[mid]
    text = open(path).read()
    assert text.count(old) == 1, (mid, "anchor not found once")
    open(path, "w").write(text.replace(old, new))
    try:
        code, out = run()
    finally:
        open(path, "w").write(text)
    fails = [l.split(":: ")[-1].strip() for l in out.splitlines() if l.startswith("FAIL") and "::" in l]
    bad = "not an assertion failure" in out
    print(mid, "ERROR" if bad else ("killed" if code != 0 else "SURVIVED"), "|", "; ".join(fails))
