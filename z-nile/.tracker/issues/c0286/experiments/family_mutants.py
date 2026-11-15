#!/usr/bin/env python3
# c0286 prep's mutation check of AC4 (family.spec). Run it from the repository top of a scratch tree on which
# migrate.py has run and the prototype patch is applied (never the real checkout): for each mutant it changes one
# document, runs family.spec, requires a failure, then restores the document. Usage:
#   ./zn run --time 600 -- env -u ZN_REAL_GIT ... PATH=<no z-nile/bin> python3 -I family_mutants.py
import os, re, subprocess, sys

SPEC = ".tracker/issues/c0286/acceptance/family.spec.luau"
D = "z-nile/.tracker/issues"


def doc(i):
    for sub in ("", "active/", "done/"):
        p = f"{D}/{sub}{i}/{i}.md"
        if os.path.isfile(p):
            return p
    sys.exit(f"{i} not found")


def sub(i, pat, rep):
    def f(t):
        new, n = re.subn(pat, rep, t, count=1, flags=re.M)
        if n != 1:
            raise SystemExit(f"{i}: pattern {pat!r} not found")
        return new
    return (i, f)


M = [
    ("A1 a raftless draft member lost its line", sub("c0249", r"^tied: .*\n", "")),
    ("A2 a line without brackets", sub("c0251", r"^tied: \[(.*)\]$", r"tied: \1")),
    ("A3 a line naming an id outside its family", sub("c0252", r"^tied: \[(.*)\]$", r"tied: [\1, c0263]")),
    ("A4 a line missing a member", sub("c0253", r"^tied: \[c0249, ", "tied: [")),
    ("A5 a line after title: instead of id:", sub("c0254", r"^(tied: .*\n)(type: .*\n)(title: .*\n)", r"\2\3\1")),
    ("A6 two tied: lines", sub("c0249", r"^(tied: .*\n)", r"\1\1")),
    ("A7 the one carrier of a ready family lost its line", sub("c0248", r"^tied: .*\n", "")),
    ("A8 an issue outside the families names a member", sub("c0286", r"^(id: c0286\n)", r"\1tied: [c0249]\n")),
    ("A9 an id twice", sub("c0249", r"^tied: \[(.*)\]$", r"tied: [\1, c0251]")),
]

bad = 0
for name, (i, f) in M:
    p = doc(i)
    before = open(p).read()
    open(p, "w").write(f(before))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", SPEC], cwd="z-nile", capture_output=True, text=True,
                           timeout=300)
        out = r.stdout + r.stderr
        killed = r.returncode != 0 and re.search(r"[1-9]\d* failed", out) is not None
        print(f"{name}: {'killed' if killed else 'SURVIVED'}")
        bad += 0 if killed else 1
    finally:
        open(p, "w").write(before)
sys.exit(1 if bad else 0)
