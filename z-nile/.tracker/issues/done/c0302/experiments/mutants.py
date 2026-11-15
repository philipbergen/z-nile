# Mutation check for c0302. Usage, from the worktree: ./zn run --time 900 -- python3 -I mutants.py <clone> [ids...]
# <clone> is a separate clone under the temp folder with experiments/narrow.patch applied and committed, and this
# issue's acceptance/ and check.sh copied in. Each mutant weakens one of the seven fixture specs (or plants a new
# one); it prints which of AC1 (narrow.py), AC3 (fixtures.spec), AC4 (maintip.spec) and, for the ids in LAYER, AC2 (layer.sh)
# turned red. C1 is a code mutant (the rejected design: mainTip falls back to HEAD on a lone layer branch).
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
ACC = ".tracker/issues/c0302/acceptance"
A = lambda p: os.path.join(home, "tests/acceptance", p)
NOTE = "\t\t-- c0302: the clone has no origin, so its branch is its main: on a stack layer branch `./zn start` finds no other\n"
NAME = '\t\tgit({ "checkout", "-q", "-B", "main" })\n'
START8 = '\t\tmust(tr({ "start", "R0010" }), "start")\n'
PLANT = ('local clone = require("@tests/lib/clone")\nlocal function f(root, dir, git, tr)\n\t\tclone.isolated(root, dir)\n'
         '\t\tgit({ "remote", "remove", "origin" })\n\t\ttr({ "start", "R0010" })\nend\nreturn f\n')
M = {
 "N1": (A("c0080/consequences.spec.luau"), NAME, ""),
 "N2": (A("c0074/done-gate.spec.luau"), NAME, "\t\t-- " + NAME.lstrip("\t")),
 "N3": (A("c0038/deferred.spec.luau"), NAME, NAME.replace('"-B", "main"', '"-b", "trunk"')),
 "N4": (A("c0001/tracker-lifecycle.spec.luau"), '\t\tt.expect(string.find(r.stderr, "cannot contain", 1, true) ~= nil).toBe(true)\n', ""),
 "N5": (A("c0050/start-depends.spec.luau"), None, None),  # a CRLF copy
 "N6": (A("c0008/done-order.spec.luau"), None, None),     # the naming moved after the first start
 "N7": (os.path.join(home, "tests/tooling/c0302-planted.spec.luau"), None, PLANT),  # a new unnamed fixture
 "N8": (A("c0120/promote-home.spec.luau"), "so its branch is its main", "so its branch is main"),
 "N9": (A("c0074/done-gate.spec.luau"), "finds no other\n" + NAME, "finds no other " + NAME.lstrip("\t")),
 "N10": (A("c0038/deferred.spec.luau"), NAME, NAME.replace('"-B"', '"-b"')),
 # design review 001 F4: fixtures the first scan passed
 "N11": (os.path.join(home, "tests/tooling/c0302-planted.spec.luau"), None, PLANT.replace("root", "TOP")),  # the checkout by another name
 "N12": (A("c0074/done-gate.spec.luau"), NAME, "\t\t--[[\n" + NAME + "\t\t]]\n"),  # the naming in a block comment
 "N13": (os.path.join(home, "tests/tooling/c0302-planted.spec.luau"), None, 'local function early(git)\n' + NAME + 'end\n' + PLANT),  # a naming in an earlier helper
 "N14": (A("c0080/consequences.spec.luau"), NAME, "\t\tfs.writeDir(base) -- " + NAME.lstrip("\t")),  # the naming in a trailing comment
 # design review 001 F5: the rejected design, mainTip falling back to HEAD on a lone layer branch
 "C1": (os.path.join(home, "engine/layergit.luau"), '\treturn fail("no main branch")\nend\n\nfunction layergit.layersOf', '\treturn layergit.shaOf("HEAD") or fail("no main branch")\nend\n\nfunction layergit.layersOf'),
}
LAYER = {"N1", "N3"}
def run(cmd):
    r = subprocess.run(cmd, cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
def acs(mid):
    out = {}
    out["AC1"] = run(["python3", "-I", f"{ACC}/narrow.py", clone])[0] != 0
    code, text = run(["lune", "run", "tests/run", "--", f"{ACC}/fixtures.spec.luau"])
    out["AC3"] = code != 0
    if "not an assertion failure" in text:
        out["AC3"] = "ERROR"
    code, text = run(["lune", "run", "tests/run", "--", f"{ACC}/maintip.spec.luau"])
    out["AC4"] = "ERROR" if "not an assertion failure" in text else code != 0
    if mid in LAYER or mid == "BASE":
        code, text = run(["bash", f"{ACC}/layer.sh"])
        out["AC2"] = (code != 0, text.count("no main branch"))
    return out
print("BASE", acs("BASE"))
for mid in (sys.argv[2:] or list(M)):
    path, old, new = M[mid]
    text = open(path, newline="").read() if os.path.exists(path) else None
    if mid == "N5":
        mutated = text.replace("\n", "\r\n")
    elif mid == "N6":
        assert text.count(NOTE + NAME) == 1 and text.count(START8) == 1
        mutated = text.replace(NOTE + NAME, "").replace(START8, START8 + NAME)
    elif mid in ("N7", "N11", "N13"):
        assert text is None
        mutated = new
    else:
        assert text.count(old) == 1, (mid, "anchor not found once")
        mutated = text.replace(old, new)
    open(path, "w", newline="").write(mutated)
    try:
        print(mid, acs(mid))
    finally:
        if text is None:
            os.remove(path)
        else:
            open(path, "w", newline="").write(text)
