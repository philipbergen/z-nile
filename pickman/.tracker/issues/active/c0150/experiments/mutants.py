# c0150 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, copies this item's acceptance folder in, applies narrowing.patch there, applies each mutant to
# that clone and runs the row's spec files from the clone's pickman/, then deletes the clone.
# Usage, from anywhere: python3 <this file> [mutant id prefixes...]
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="c0150-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "pickman")
K = "tests/acceptance/f0104/keys.spec.luau"
P = "tests/acceptance/f0101/place.spec.luau"
V = "src/shared/Logic/View/init.luau"
CAM = "src/client/Camera.luau"
DIGEST = [".tracker/issues/c0150/acceptance/narrowed.spec.luau"]
PINS = [K, P]
M = [
    ("N1 count weakened", K, "t.expect(n >= 10).toBe(true)", "t.expect(n >= 4).toBe(true)", DIGEST),
    ("N2 a binding dropped", K, '\t\t\tE = "Fire",\n', "", DIGEST),
    ("N3 F pinned again", K, '{ "Q", "e",', '{ "Q", "F", "e",', DIGEST),
    ("N4 a case emptied", K, "\t\t\tt.expect(View.action(key)).toBe(nil)\n", "", DIGEST),
    ("N5 the frozen case defanged", K, '(View.KEYS :: any).Q = "Fire"', "local _ = 1", DIGEST),
    ("N6 camera pattern widened", P, '%s*([%w_]+)%s*[,%)]")', '.-([%w_]+)")', DIGEST),
    ("N7 one CFrame weakened", P, "t.expect(frames).toBe(1)", "t.expect(frames >= 1).toBe(true)", DIGEST),
    ("N8 code hidden in a comment", K, '\tit("the map is frozen", function()', '\t--[[ x ]] it("the map is frozen", function()', DIGEST),
    ("N9 a check joined into a comment", P, "\t\t\t-- that tick is View.shownTick", "\t\t\t-- that tick is View.shownTick --", DIGEST),
    ("N10 spaces in a string", P, "Vector3.new(6, 7, 6)", "Vector3.new(6,  7, 6)", DIGEST),
    ("N11 the View.KEYS check dropped", K, "\t\t\tt.expect(View.KEYS[key]).toBe(action)\n", "", DIGEST),
    ("K1 View.KEYS another table", V, "View.KEYS = table.freeze(KEYS)", 'View.KEYS = table.freeze({ F1 = "Fire", F2 = "Fire", F3 = "Fire", F4 = "Fire", F5 = "Fire", F6 = "Fire", F7 = "Fire", F8 = "Fire", F9 = "Fire", F10 = "Fire" })', PINS),
    ("K2 an extra key moves", V, '\tE = "Fire",\n', '\tE = "Fire",\n\tZ = "Forward",\n', PINS),
    ("K3 an extra key jumps", V, '\tE = "Fire",\n', '\tE = "Fire",\n\tG = "Jump",\n', PINS),
    ("K4 the eye at the snapshot's tick", CAM, "Hop.rise(hopped, shown)", "Hop.rise(hopped, snap.tick)", PINS),
]

def main():
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    item = os.path.join(HOME, ".tracker", "issues", "c0150")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "narrowing.patch")], check=True)
    only = sys.argv[1:]
    for mid, rel, old, new, specs in M:
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        if src.count(old) != 1:
            print(mid.ljust(36), "ANCHOR", src.count(old))
            continue
        open(f, "w").write(src.replace(old, new))
        try:
            out = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=600).stdout
        finally:
            open(f, "w").write(src)
        verdict = "LOAD ERROR" if "could not load" in out else ("SURVIVED" if " 0 failed" in out else "killed")
        print(mid.ljust(36), verdict, flush=True)

try:
    main()
finally:
    shutil.rmtree(TMP, ignore_errors=True)
