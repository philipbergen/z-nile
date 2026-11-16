# Mutation check for c0177. Usage: python3 -I mutants.py <clone> [ids...]
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
SPEC = ".tracker/issues/c0177/acceptance/narrowed.spec.luau"
S = os.path.join(home, "tests/acceptance/f0125/speeds.spec.luau")
M = {
 "N1": (S, "edge(Session.GAME_CONFIG, level) / edge(untunedOf(Session.GAME_CONFIG), level)\n\t\t\t\tt.expect",
        "edge(Session.GAME_CONFIG, level) / edge(Session.DEFAULT_CONFIG, level)\n\t\t\t\tt.expect"),
 "N2": (S, "\t\t\tfast.ramp = nil -- c0177: the bound on the classic tables\n", ""),
 "N3": (S, "t.expect(math.abs(sum / #list - want) < 0.1).toBe(true)", "t.expect(math.abs(sum / #list - want) < 10).toBe(true)"),
 "N4": (S, "\t\t\t\t.toBe(2 * Session.GAME_CONFIG.movement.speed)\n", "\t\t\t\t.toBe(Session.speeds(classicOf(Session.GAME_CONFIG), level).eyes)\n"),
 "N5": (S, 't.expect(levels.ghostSpeed(base, level, "normal", set.tuning, ramp)).toBe(sp.ghost)', 't.expect(levels.ghostSpeed(base, level, "normal", set.tuning)).toBe(sp.ghost)'),
 "N6": (S, "\t-- tenth of a unit on average\n\tlocal function allEqual", "\t-- tenth of a unit on average local function allEqual"),
 "N7": (os.path.join(home, ".tracker/issues/done/f0125/check.sh"), 'check "AC4:', '# check "AC4:'),
 "N8": (S, "\t\tt.expect(ramp).toBe((Session.GAME_CONFIG :: any).ramp)\n", ""),
 "N10": (S, "\t\t\t\tt.expect((pcall(Session.new, classic, 1, high))).toBe(false)\n", ""),
 "N11": (S, "if (Session.GAME_CONFIG :: any).ramp then", "if false then"),
 "N9": (S, "\t\tt.expect(mean >= 1.09 and mean <= 1.13).toBe(true)\n", ""),
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
