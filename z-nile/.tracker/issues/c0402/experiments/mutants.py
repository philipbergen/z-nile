# c0402 E1: does each Rules row's mutant fail its case on an assertion? Applies the prototype (already in this worktree
# when run from a prep worktree with prototype.patch applied) then each mutant in turn, runs the row's spec from z-nile/,
# counts a mutant killed only on an "expected" assertion line, and restores the file.
# Usage, from the repository root of the prep worktree, after `git apply experiments/prototype.patch`:
#   ./zn run --time 600 -- python3 -I z-nile/.tracker/issues/c0402/experiments/mutants.py
import os, subprocess, sys

TOP = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip()
A = ".tracker/issues/c0402/acceptance/"
PLAN = "tests/acceptance/c0116/plan.spec.luau"
DOCS = "tests/acceptance/c0116/docs.spec.luau"
ENG = "engine/raftplan.luau"
RAFT = "skills/z-raft/SKILL.md"
DES = "skills/z-design/SKILL.md"
LES = "skills/z-design/lessons/size-is-re-estimated-when-scope-grows.md"
# (id, file, old, new, [spec files])  -- one per Rules row
E_ = A + "engine.spec.luau"
U_ = A + "untouched.spec.luau"
S_ = A + "skills.spec.luau"
P_ = A + "pins.spec.luau"
MUTANTS = [
    ("C1 the cap stays 1500", ENG, "raftplan.CAP = 3000", "raftplan.CAP = 1500", [E_]),
    ("C2 the cap is 3001", ENG, "raftplan.CAP = 3000", "raftplan.CAP = 3001", [E_]),
    ("C3 the cap is 2999", ENG, "raftplan.CAP = 3000", "raftplan.CAP = 2999", [E_]),
    ("C4 a sum at the cap does not fit", ENG, "if b.size + size <= cap then", "if b.size + size < cap then", [E_]),
    ("C5 an issue at the cap is single", ENG, "(i.size :: number) > limit", "(i.size :: number) >= limit", [E_]),
    ("C6 solo ignored", ENG, "if i.solo or (i.size :: number) > limit then", "if (i.size :: number) > limit then", [U_]),
    ("C7 an explicit cap ignored", ENG, "local limit = cap or raftplan.CAP", "local limit = raftplan.CAP", [U_]),
    ("D1 z-raft keeps 1,500", RAFT, "about 3,000 changed lines", "about 1,500 changed lines", [S_]),
    ("D2 z-design keeps 1,500", DES, "cap of about 3,000 lines", "cap of about 1,500 lines", [S_]),
    ("D3 the lesson keeps 1,500", LES, "its cap of about 3,000 lines", "its cap of about 1,500 lines", [S_]),
    ("D4 the lesson's check keeps 1,500", LES, "raft cap of about 3,000 changed lines", "raft cap of about 1,500 changed lines", [S_]),
    ("P1 plan.spec drops the CAP pin", PLAN, "t.expect(raftplan.CAP).toBe(3000)", "t.expect(raftplan.CAP > 0).toBe(true)", [P_]),
    ("P2 plan.spec header keeps 1,500", PLAN, "size cap of 3,000 changed lines", "size cap of 1,500 changed lines", [P_]),
    ("P3 docs.spec pins 1,500", DOCS, "a raft that would pass about 3,000 changed lines", "a raft that would pass about 1,500 changed lines", [P_]),
]
# correct variants: changes that must keep the specs green
VARIANTS = [
    ("V1 an extra blank line in raftplan", ENG, "raftplan.CAP = 3000\n", "raftplan.CAP = 3000\n\n", [E_, U_, PLAN]),
]


def run(specs):
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=os.path.join(TOP, "z-nile"), capture_output=True, text=True, timeout=300)
    return r.returncode, r.stdout + r.stderr


def apply(rel, old, new):
    p = os.path.join(TOP, "z-nile", rel)
    text = open(p).read()
    if text.count(old) != 1:
        raise SystemExit(f"{rel}: {old!r} found {text.count(old)} times")
    open(p, "w").write(text.replace(old, new))
    return p, text


bad = 0
rc, out = run([E_, U_, S_, P_, PLAN, DOCS])
print("base:", "green" if rc == 0 else "RED")
if rc != 0:
    print(out)
    raise SystemExit(1)
for name, rel, old, new, specs in MUTANTS:
    p, text = apply(rel, old, new)
    try:
        rc, out = run(specs)
    finally:
        open(p, "w").write(text)
    killed = rc != 0 and "expected" in out
    bad += 0 if killed else 1
    print(("killed  " if killed else "SURVIVED/NOT-AN-ASSERTION  ") + name)
for name, rel, old, new, specs in VARIANTS:
    p, text = apply(rel, old, new)
    try:
        rc, out = run(specs)
    finally:
        open(p, "w").write(text)
    bad += 0 if rc == 0 else 1
    print(("green   " if rc == 0 else "RED  ") + name)
print("mutants:", len(MUTANTS) - bad if bad == 0 else f"{bad} problems")
sys.exit(1 if bad else 0)
