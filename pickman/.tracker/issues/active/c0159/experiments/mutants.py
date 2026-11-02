# Mutation check for c0159. Usage: python3 -I mutants.py <clone> [ids...]
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
SPEC = ".tracker/issues/c0159/acceptance/narrowed.spec.luau"
D = os.path.join(home, "tests/acceptance/d0105/adapter.spec.luau")
F = os.path.join(home, "tests/acceptance/f0033/adapters.spec.luau")
P = os.path.join(home, "tests/acceptance/f0102/place.spec.luau")
M = {
 "N1": (P, '\t\tt.expect(has(src, ".Rotation")).toBe(false)\n', ""),
 "N2": (D, "\t\t\t-- as a prefix; the Position line must follow it directly\n\t\t\tlocal head",
        "\t\t\t-- as a prefix; the Position line must follow it directly\tlocal head"),
 "N3": (P, "\t\t\tt.expect(#orders).toBe(1) -- the glows' screen sets one; the radar's (Danger) keeps the default, 0\n", ""),
 "N4": (P, '\t\tt.expect(has(src, "Awareness.glows(") or has(src, "Awareness.ring(")).toBe(true)\n',
        '\t\tt.expect(has(src, "Awareness.indicators(")).toBe(true)\n'),
 "N5": (P, '\t\tt.expect(string.find(src, "snap%.ghosts%[") == nil).toBe(true)\n', ""),
 "N6": (D, '\t\tt.expect(string.find(src, "Awareness.radar(", 1, true) ~= nil).toBe(true)\n', ""),
 "N7": (F, '{ "Awareness.radar(", "Awareness.indicators(" }', '{ "Awareness.indicators(" }'),
 "N9": (os.path.join(home, "tests/acceptance/c0106/narrow-adapter.spec.luau"), '\t\tt.expect(sum .. ":" .. len).toBe("1671723699:2275")\n\tend)\n\n\tit("the adapter fingerprint', '\t\tt.expect(sum > 0).toBe(true)\n\tend)\n\n\tit("the adapter fingerprint'),
 "N8": (os.path.join(home, ".tracker/issues/done/f0102/check.sh"), 'check "AC5:', '# check "AC5:'),
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
    fails = [l.split(":: ")[-1].strip() for l in out.splitlines() if l.startswith("FAIL")]
    bad = "not an assertion failure" in out
    print(mid, "ERROR" if bad else ("killed" if code != 0 else "SURVIVED"), "|", "; ".join(fails))
