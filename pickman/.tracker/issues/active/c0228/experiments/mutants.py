# Mutation check for c0228. Usage: ./zn run --time 1800 -- python3 -I <this file> <clone> [ids...]
# <clone>: a separate clone with no remote under the temp folder, at the prototype's base with
# experiments/prototype.patch applied (zz-test's method; design review 001 F5):
#   D="$(mktemp -d)/repo"; git clone --no-hardlinks <repo> "$D" && git -C "$D" remote remove origin
#   git -C "$D" checkout <base> && git -C "$D" apply <this folder>/prototype.patch The script copies this issue's
# acceptance specs into the clone, then for each mutant edits the clone's source (each edit must match exactly once),
# runs the specs it names and restores the file. A mutant (M*) must turn its named case red on an assertion; a
# correct variant (C*) and the unmutated prototype (BASE) must leave every named spec green. It commits, resets and
# moves no ref; it edits only files of the clone it is given, which must be a separate clone under the temp folder.
import glob, os, re, shutil, subprocess, sys, tempfile
clone = os.path.realpath(sys.argv[1])
tmp = os.path.realpath(tempfile.gettempdir())
def common(cwd):
    r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], capture_output=True, text=True, cwd=cwd)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""
here = common(os.path.dirname(os.path.abspath(__file__)))
there = common(clone) if os.path.isdir(clone) else ""
if not clone.startswith(tmp + os.sep) or not there or there == here:
    sys.exit(f"refused: {clone} is not a separate clone under {tmp}")
remotes = subprocess.run(["git", "remote"], capture_output=True, text=True, cwd=clone)
if remotes.returncode != 0 or remotes.stdout.strip():
    sys.exit(f"refused: {clone} has a remote ({remotes.stdout.strip() or 'git remote failed'}): remove it first")
home = os.path.join(clone, "pickman")
ACC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../acceptance")
dest = os.path.join(home, ".tracker/issues/c0228/acceptance")
os.makedirs(dest, exist_ok=True)
for f in glob.glob(os.path.join(ACC, "*.spec.luau")):
    shutil.copy(f, dest)
RUNS = ".tracker/issues/c0228/acceptance/runs.spec.luau"
WALLS = ".tracker/issues/c0228/acceptance/walls.spec.luau"
VIEWS = "tests/acceptance/f0126/views.spec.luau"
ADAPT = "tests/acceptance/f0126/adapters.spec.luau"
F0109 = "tests/acceptance/f0109/place.spec.luau"
MAIN, MV, VIEW = "src/client/Main.client.luau", "src/client/MazeView.luau", "src/shared/Logic/View/init.luau"
KEYLINE = "\t\ttable.insert(parts, `{r.x0},{r.y0},{r.x1},{r.y1},{if r.marked == true then 1 else 0}`)\n"
SKIP = "\tif drawn[model] == key then\n\t\treturn\n\tend\n\tdrawn[model] = key\n"
BUILD = "\t\tlocal walls = MazeView.build(View.frameMaze(frame), marked)\n"
# id: (file, [(old, new)], specs that must fail (mutant) or pass (correct), the case that must fail)
M = {
 "BASE": (MAIN, [], [RUNS, WALLS, VIEWS, ADAPT, F0109], None),
 # Main
 "M1": (MAIN, [(BUILD, "\t\tlocal walls = MazeView.build(m)\n")], [WALLS], "Main builds every wall once"),  # main as it was
 "M2": (MAIN, [(BUILD, "\t\tlocal walls = MazeView.build(m, marked)\n")], [WALLS], "Main builds every wall once"),  # the layout: holes shut
 "M3": (MAIN, [(BUILD, "\t\tlocal walls = MazeView.build(View.frameMaze(frame))\n")], [WALLS], "Main builds every wall once"),  # no marks
 "M14": (MAIN, [("\t\twallsKey = nil\n", "\t\twallsKey = View.wallsKey(frame)\n")], [VIEWS], "Main rebuilds the walls once per change"),  # skips the first rewall: f0126's count
 # MazeView
 "M4": (MV, [(SKIP, "")], [WALLS], "makes and destroys no part"),  # no skip: a rewall always redraws
 "M5": (MV, [(SKIP, "\tif drawn[model] then\n\t\treturn\n\tend\n\tdrawn[model] = key\n")], [WALLS], "a rewall to other walls draws them"),  # drawn once, never again
 "M6": (MV, [(SKIP, "\tif drawn[model] == key then\n\t\treturn\n\tend\n\tdrawn[model] = drawn[model] or key\n")], [WALLS], "makes and destroys no part"),  # remembers only the first draw
 "M7": (MV, [("\twalls(model, m, marked)\n\tfor _, d in", "\twalls(model, m)\n\tfor _, d in")], [WALLS], "MazeView.build draws the walls with the marks"),  # build drops the marks
 "M8": (MV, [(SKIP, "\tif drawn[model] == tostring(m) .. tostring(marked) then\n\t\treturn\n\tend\n\tdrawn[model] = tostring(m) .. tostring(marked)\n")], [WALLS], "however the maze and marks were made"),  # identity, not values
 "ML": (MV, [('part(model, "MarkedWall", wallColorOf(model, true), size, center)', 'part(model, "MarkedWall", rgb(View.wallColor(false, model:GetAttribute("Edible") == true, true)), size, center)')], [WALLS], "lit and edible colours, a new mark included"),  # review 001 F1: marked walls drawn under the flash stay gold
 "MG": (MV, [("local drawn: { [Model]: string } = setmetatable({}, { __mode = \"k\" }) :: any\n", "local drawnKey: string? = nil\n"), (SKIP, "\tif drawnKey == key then\n\t\treturn\n\tend\n\tdrawnKey = key\n")], [WALLS], "each maze model keeps its own drawn walls"),  # review 001 F2: one key for every model
 # View.runsKey
 "M9": (VIEW, [(KEYLINE, "\t\ttable.insert(parts, `{r.x0},{r.y0},{r.x1},{r.y1}`)\n")], [RUNS], "a one-tile run marked or not"),  # the mark left out
 "M9w": (VIEW, [(KEYLINE, "\t\ttable.insert(parts, `{r.x0},{r.y0},{r.x1},{r.y1}`)\n")], [WALLS], "a one-tile run marked or not"),  # the same, through MazeView
 "M10": (VIEW, [(KEYLINE, "\t\ttable.insert(parts, `{r.x0}{r.y0}{r.x1}{r.y1}{if r.marked == true then 1 else 0}`)\n")], [RUNS], "runs that differ in any bound"),  # bounds run together
 "M11": (VIEW, [(KEYLINE, "\t\ttable.insert(parts, `{r.x0},{r.x1},{r.y1},{if r.marked == true then 1 else 0}`)\n")], [RUNS], "runs that differ in any bound"),  # y0 left out
 "M12": (VIEW, [(KEYLINE, "\t\ttable.insert(parts, `{r.x0},{r.y0},{r.x1},{r.y1},{r.marked}`)\n")], [RUNS], "unmarked is unmarked either way"),  # false and nil apart
 "M13": (VIEW, [(KEYLINE, KEYLINE + "\t\tbreak\n")], [RUNS], "walls with a moved mark"),  # the first run only
 # correct variants
 "C3": (MAIN, [("\tCamera.hopTicks(frame.hopTicks)\n", "\tCamera.hopTicks(frame.hopTicks)\n\tCamera.ready(frame.play, frame.tick)\n")], [WALLS, VIEWS, ADAPT], None),  # f0234's Main line (review 001 F3)
 "C1": (MAIN, [(BUILD, "\t\tlocal walls = MazeView.build(View.frameMaze(frame), if frame.walls then frame.walls.marked else {})\n")], [WALLS, VIEWS, ADAPT], None),
 "C2": (VIEW, [(KEYLINE, "\t\ttable.insert(parts, string.format(\"%d:%d:%d:%d:%s\", r.x0, r.y0, r.x1, r.y1, if r.marked then \"m\" else \"-\"))\n")], [RUNS, WALLS], None),
}
def run(specs):
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=home, capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr
ids = sys.argv[2:] or list(M)
bad = 0
for i in ids:
    path, edits, specs, case = M[i]
    full = os.path.join(home, path)
    orig = open(full).read()
    s = orig
    try:
        for old, new in edits:
            n = s.count(old)
            if n != 1:
                raise SystemExit(f"{i}: edit matches {n} times in {path}: {old[:50]!r}")
            s = s.replace(old, new)
        if edits and s == orig:
            raise SystemExit(f"{i}: edit changed nothing")
        open(full, "w").write(s)
        code, out = run(specs)
    finally:
        open(full, "w").write(orig)
    if i == "BASE" or i.startswith("C"):
        ok = code == 0
        print(f"{i}: {'green' if ok else 'RED (wrong)'}")
    else:
        fails = [l for l in out.splitlines() if "FAIL" in l]
        hit = [l for l in fails if case in l]
        assertion = any(k in out for k in ("expected", "Expected", "toBe", "toEqual"))
        load = "could not load spec" in out or "syntax" in out.lower()
        ok = code != 0 and bool(hit) and assertion and not load
        print(f"{i}: {'killed' if ok else 'SURVIVED or wrong failure'}: {hit[0].strip()[:150] if hit else (fails[:1] or ['no FAIL'])[0][:150]}")
    bad += 0 if ok else 1
sys.exit(1 if bad else 0)
