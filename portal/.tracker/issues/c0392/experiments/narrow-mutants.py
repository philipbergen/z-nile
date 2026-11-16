#!/usr/bin/env python3
# c0392 prep's mutation check of acceptance/narrow.py (AC1). Run from the top of a prototype checkout with c0392's
# change in place (c0210 done, the pre-ready tracker PR applied, lobby-start.spec removed, c0392's folder present),
# with nothing uncommitted:
#   ./zn run --time 300 -- python3 -I -u <this file>
# Each mutant changes the checkout's files, runs narrow.py, and is killed only when narrow.py exits 1 printing the
# expected words; the checkout is restored after each (git checkout of the tracked files it touched, removal of the
# files it added). Unmutated, narrow.py must pass first.
import os, pathlib, shutil, subprocess, sys

R = pathlib.Path.cwd()
C = R / "portal/tests/acceptance/c0210"
CHECK = R / "portal/.tracker/issues/done/c0210/check.sh"
NARROW = R / "portal/.tracker/issues/c0392/acceptance/narrow.py"


def edit(path, old, new):
    def f():
        t = path.read_bytes()
        assert t.count(old) == 1, f"{path}: {t.count(old)} matches"
        path.write_bytes(t.replace(old, new))
    return f


def add(path, data):
    def f():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    return f


GONE_TEXT = subprocess.run(["git", "cat-file", "blob", "2efc8d8afa61f427c920228ca04969d5c38cb2b2"], capture_output=True).stdout
BASE_CHECK = subprocess.run(["git", "cat-file", "blob", "0fefecb37d9ffda96cfeb198037807c438e6c8be"], capture_output=True).stdout

def crlf():
    p = C / "override-01.txt"
    t = p.read_bytes()
    p.write_bytes(t.replace(b"\n", b"\r\n", 1))


MUTANTS = [
    ("N1", "an assertion deleted from pickman.spec", edit(C / "pickman.spec.luau", b'\t\t\tt.expect(game:GetAttribute("GamePlaceId")).toBe(nil)\n', b""), "pickman.spec.luau is blob"),
    ("N2", "a line joined onto the comment above it in way-back.spec", edit(C / "way-back.spec.luau", b"\n\tfor _, var in", b" for _, var in"), "way-back.spec.luau is blob"),
    ("N3", "`do return end` added to an overrides.spec case", edit(C / "overrides.spec.luau", b'is exactly its reviewed golden", function()\n', b'is exactly its reviewed golden", function()\n\t\tdo return end\n'), "overrides.spec.luau is blob"),
    ("N4", "one line ending of a golden made CRLF", crlf, "override-01.txt is blob"),
    ("N5", "c0210's check.sh still runs AC11 (the pre-ready PR missing)", lambda: CHECK.write_bytes(BASE_CHECK), "pre-ready tracker PR is missing"),
    ("N6", "AC10 dropped from c0210's check.sh too", edit(CHECK, b'check "AC10: ', b'# check "AC10: '), "not 259b5159"),
    ("N7", "lobby-start.spec left in the promoted folder", add(C / "lobby-start.spec.luau", GONE_TEXT), "is still there"),
    ("N8", "lobby-start.spec kept under another name", add(C / "lobby.spec.luau", GONE_TEXT), "not one of c0210's reviewed files"),
    ("N9", "a kept spec removed", lambda: (C / "build.spec.luau").unlink(), "build.spec.luau is missing"),
    ("N10", "another tests/ file names it", add(R / "portal/tests/unit/Nothing/nothing.luau", b"-- runs lobby-start.spec\n"), "names lobby-start"),
    ("N11", "a check.sh under a tracker runs it", edit(R / "portal/.tracker/issues/f0209/check.sh", b"\nfinish\n", b'\ncheck "X" lune run tests/run -- tests/acceptance/c0210/lobby-start.spec.luau\nfinish\n'), "names lobby-start.spec.luau"),
    ("N12", "c0210's sequestered acceptance folder left in done/", add(R / "portal/.tracker/issues/done/c0210/acceptance/build.spec.luau", b"x"), "acceptance exists"),
]


def narrow():
    r = subprocess.run([sys.executable, "-I", str(NARROW), str(R)], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def restore():
    subprocess.run(["git", "checkout", "--", "portal"], check=True)
    for extra in [C / "lobby-start.spec.luau", C / "lobby.spec.luau", R / "portal/tests/unit/Nothing", R / "portal/.tracker/issues/done/c0210/acceptance"]:
        if extra.is_dir():
            shutil.rmtree(extra)
        elif extra.exists():
            extra.unlink()


if subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip():
    sys.exit("the tree has uncommitted or untracked changes")
code, out = narrow()
print(f"unmutated: exit {code} {out.strip()}")
if code != 0:
    sys.exit("narrow.py must pass unmutated")
for name, what, apply, words in MUTANTS:
    try:
        apply()
        code, out = narrow()
    finally:
        restore()
    verdict = "killed" if code == 1 and words in out else "SURVIVED"
    print(f"{name} ({what}): {verdict}: {out.strip().splitlines()[0] if out.strip() else '(no output)'}")
if subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True).stdout.strip():
    sys.exit("the tree was left changed")
