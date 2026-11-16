# c0153 prep: the mutation check. It never touches the tree it is run from: it clones this repository into a fresh
# folder under $TMPDIR, copies this item's folder in, applies c0153.patch there (the helper and the five narrowed
# specs), runs the intended state, then applies each mutant to that clone, runs the row's spec files from the
# clone's pickman/, restores the file, and deletes the clone at the end.
# Usage, from anywhere: python3 -I <this file> [mutant id prefixes...]
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
TMP = os.path.realpath(tempfile.mkdtemp(prefix="c0153-mutants-"))
CLONE = os.path.join(TMP, "repo")
HOME = os.path.join(CLONE, "pickman")
A = ".tracker/issues/c0153/acceptance/"
GOLDEN = [A + "golden.spec.luau"]
PLAIN = [A + "plain.spec.luau"]
H = "tests/lib/plain.luau"
F13 = "tests/acceptance/f0013/snapshot.spec.luau"
F18 = "tests/acceptance/f0018/frame.spec.luau"
F30 = "tests/acceptance/f0030/frame.spec.luau"
F32 = "tests/acceptance/f0032/frame.spec.luau"
F100 = "tests/acceptance/f0100/drops.spec.luau"
RT = "t.expect({ plain.roundTrip(frame, 1e-9) }).toEqual({ true })"
M = [
    # the narrowed files, pinned whole (review 001 F1: M1-M5 and the comment join)
    ("G1 f0032 ghosts assertion deleted", F32, "\t\tt.expect(frame.ghosts).toEqual(snap.ghosts)\n", "", GOLDEN),
    ("G2 f0032 tolerance widened", F32, "plain.roundTrip(frame, 1e-9)", "plain.roundTrip(frame, 1e9)", GOLDEN),
    ("G3 f0032 result never asserted", F32, RT, "plain.roundTrip(frame, 1e-9)", GOLDEN),
    ("G4 f0032 jumpTick assertion deleted", F32, "\t\t\tt.expect(g.jumpTick > resetTick).toBe(true)\n", "", GOLDEN),
    ("G5 f0032 size bound widened", F32, "< 700).toBe(true)", "< 70000).toBe(true)", GOLDEN),
    ("G6 f0013 check joined onto its comment", F13, "one ulp off)\n\t\tt.expect({ plain.roundTrip(snap", "one ulp off) t.expect({ plain.roundTrip(snap", GOLDEN),
    ("G7 f0018 tolerance widened", F18, "plain.roundTrip(frame, 1e-9)", "plain.roundTrip(frame, 1)", GOLDEN),
    ("G8 f0030 pellets assertion deleted", F30, '\t\tt.expect((Session.snapshot(s, "p") :: any).pellets).toBe(nil)\n', "", GOLDEN),
    ("G9 f0100 round trip deleted", F100, "\t\t" + RT + "\n", "", GOLDEN),
    ("G10 spaces inside a string", F32, '"the frame carries the same ghosts', '"the frame carries  the same ghosts', GOLDEN),
    # the helper (review 001 F3-F5, and the first round's P1-P7)
    ("P1 exact compare", H, "if not (math.abs(a - b) <= eps) then", "if a ~= b then", PLAIN),
    ("P2 cycles accepted", H, "\t\tif seen[v] then\n\t\t\treturn false, `{path}: a cycle`", "\t\tif seen[v] then\n\t\t\treturn true, nil", PLAIN),
    ("P3 metatables accepted", H, "if getmetatable(v) ~= nil then", "if false then", PLAIN),
    ("P4 extra keys ignored", H, "\t\tfor k in b do\n", "\t\tfor k in {} do\n", PLAIN),
    ("P5 roundTrip skips the check", H, "\tlocal ok, why = plain.check(v)\n\tif not ok then\n\t\treturn false, why\n\tend\n", "", PLAIN),
    ("P6 NaN and infinity accepted", H, "if v ~= v or v == math.huge or v == -math.huge then", "if false then", PLAIN),
    ("P7 NaN within eps (> eps)", H, "if not (math.abs(a - b) <= eps) then", "if math.abs(a - b) > eps then", PLAIN),
    ("P8 holes accepted", H, "if v[i] == nil then", "if false then", PLAIN),
    ("P9 mixed tables accepted", H, "if strings > 0 and numbers > 0 then", "if false then", PLAIN),
    ("P10 the encoder's refusal raises", H, "\tlocal done, back = pcall(function()\n\t\treturn serde.decode(\"json\", serde.encode(\"json\", v))\n\tend)\n", "\tlocal done, back = true, serde.decode(\"json\", serde.encode(\"json\", v))\n", PLAIN),
    ("P11 a refusal says nowhere", H, "return false, `{path}: a cycle`", 'return false, ""', PLAIN),
    # review 002 F1, F2: the round trip compares what came back; a table reached twice is not a cycle
    ("Q1 compares v with itself", H, "return plain.equalWithin(back, v, eps)", "return plain.equalWithin(v, v, eps)", PLAIN),
    ("Q2 never compares", H, "return plain.equalWithin(back, v, eps)", "return true, nil", PLAIN),
    ("Q3 seen never cleared", H, "\t\tseen[v] = nil\n", "", PLAIN),
]

def run(specs):
    out = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=600).stdout
    return out

def main():
    subprocess.run(["git", "clone", "--quiet", "--no-hardlinks", REPO, CLONE], check=True)
    item = os.path.join(HOME, ".tracker", "issues", "c0153")
    shutil.rmtree(item, ignore_errors=True)
    shutil.copytree(os.path.dirname(HERE), item)
    subprocess.run(["git", "-C", CLONE, "apply", os.path.join(HERE, "c0153.patch")], check=True)
    only = sys.argv[1:]
    out = run(GOLDEN + PLAIN + [F13, F18, F30, F32, F100])
    print("intended".ljust(40), out.strip().splitlines()[-1] if out.strip() else "NO OUTPUT", flush=True)
    for mid, rel, old, new, specs in M:
        if only and not any(mid.startswith(o) for o in only):
            continue
        f = os.path.realpath(os.path.join(HOME, rel))
        if not f.startswith(TMP + os.sep):
            sys.exit(f"refusing to write outside the clone: {f}")
        src = open(f).read()
        if src.count(old) != 1:
            print(mid.ljust(40), "ANCHOR", src.count(old))
            continue
        open(f, "w").write(src.replace(old, new))
        try:
            out = run(specs)
        finally:
            open(f, "w").write(src)
        verdict = "LOAD ERROR" if "could not load" in out else ("SURVIVED" if " 0 failed" in out else "killed")
        print(mid.ljust(40), verdict, flush=True)

try:
    main()
finally:
    shutil.rmtree(TMP, ignore_errors=True)
