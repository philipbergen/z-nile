#!/usr/bin/env python3
"""c0388 mutation check. Run from z-nile/ with the prototype applied (tests/acceptance/c0042/ondisk.luau and the
edited cli.spec.luau): `../zn run --time 300 -- python3 .tracker/issues/<state>/c0388/experiments/mutants.py <acceptance dir>`.
Each mutant is one text edit of the module or of c0042's spec, applied in place, the acceptance spec run once, and the
file put back. A mutant is killed when the spec fails on an assertion (a FAIL line with `expected`), not on a load error."""
import subprocess, sys

MOD = "tests/acceptance/c0042/ondisk.luau"
CLI = "tests/acceptance/c0042/cli.spec.luau"
SPEC = sys.argv[1].rstrip("/") + "/roots.spec.luau"
MUTANTS = [
    ("M1 a hand list of two roots", MOD, "for _, root in projects.roots(reg) do", 'for _, root in { "pickman/.tracker", "z-nile/.tracker" } do'),
    ("M2 active/ not read", MOD, '{ "", "/active", "/done" }', '{ "", "/done" }'),
    ("M3 done/ not read", MOD, '{ "", "/active", "/done" }', '{ "", "/active" }'),
    ("M4 no guard on a missing rafts folder", MOD, "if fs.isDir(rafts) then", "if true then"),
    ("M5 no guard on a missing issues folder", MOD, "if fs.isDir(issues) then", "if true then"),
    ("M6 retired roots read too", MOD, "projects.roots(reg)", "projects.allRoots(reg)"),
    ("M7 rafts/retired read too", MOD, '{ "", "/active", "/done" }', '{ "", "/active", "/done", "/retired" }'),
    ("M8 any R-number is a raft", MOD, '"^R%d%d%d%d$"', '"^R%d+$"'),
    ("M9 any letter is an issue", MOD, '"^[fdc]%d%d%d%d$"', '"^%a%d%d%d%d$"'),
    ("M10 an issue id of any length", MOD, '"^[fdc]%d%d%d%d$"', '"^[fdc]%d%d%d%d"'),
    ("M11 a missing registry falls back to an empty one", MOD, "local reg = projects.load(top, true)", 'local okReg, loaded = pcall(projects.load, top, true)\n\tlocal reg: projects.Registry = if okReg then loaded else { projects = {}, retired = {} }'),
    ("M15 a closed issue is listed", MOD, "and shown(issues, name)", ""),
    ("M16 an issue with no document is dropped", MOD, "return not (fs.isFile(doc) and closing.isClosed(store.readFront(doc)))", "return fs.isFile(doc) and not closing.isClosed(store.readFront(doc))"),
    ("M12 the spec keeps a hand list beside the module", CLI, "local found = ondisk.items(TOP)", 'local found = ondisk.items(TOP)\n\t\tlocal _hand = { "pickman/.tracker/rafts" }'),
    ("M13 the spec counts without the module", CLI, "t.expect(rafts).toBe(#found.rafts)", "t.expect(rafts).toBe(rafts)"),
    ("M14 every folder under a root's parent is a root", MOD, "for _, root in projects.roots(reg) do", 'for _, root in { "pickman/.tracker", "z-nile/.tracker", "arcade/.tracker", "snake/.tracker", "unregistered/.tracker" } do'),
]
survived = 0
for name, path, old, new in MUTANTS:
    text = open(path).read()
    assert text.count(old) >= 1, (name, "anchor missing")
    open(path, "w").write(text.replace(old, new, 1))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", SPEC], capture_output=True, text=True, timeout=120)
    finally:
        open(path, "w").write(text)
    out = r.stdout + r.stderr
    asserted = "expected" in out and "FAIL" in out
    print(f"{'killed  ' if asserted else 'SURVIVED' if r.returncode == 0 else 'ERROR   '} {name}")
    if not asserted:
        survived += 1
        print("   " + "\n   ".join(l for l in out.splitlines() if "FAIL" in l or "error" in l.lower())[:600])
print(f"{len(MUTANTS) - survived}/{len(MUTANTS)} killed on an assertion")
sys.exit(1 if survived else 0)
