# c0411 AC1: `z-nile/tests/acceptance/c0043/rounds.spec.luau` equals its merge base (git merge-base HEAD <origin's main,
# read with git ls-remote>) with exactly the two reviewed c0411 hunks applied, byte for byte (read as bytes), so a
# deleted or added line anywhere (a `--[[`, a `do return end`, a rebinding of `want`, a dropped assertion, a reworded
# comment, a folder left out of the four) is red (lesson zz-test/narrowing-pins-the-whole-file). The hunks are applied
# by anchored substitution, each anchor's count asserted in the base first, so the pin does not depend on line numbers:
#   (a) after the one `local process = require("@lune/process")` line, `local projects = require("@znile/engine/projects")`;
#   (b) the hand-written two-project folder list, from the `-- c0120 override: pickman's files live in pickman/ (its home)`
#       comment through the `do` that closes the `for` header, becomes the c0411 loop over `projects.roots(projects.load(TOP))`.
# It runs at `./zn finish` and `./zn done`, before the change lands: a base where an anchor's count differs, or that
# already names `projects.roots`, is not the stale form this was reviewed against, and is red: stop for a re-prep (the
# base is origin's published main read with git ls-remote, so a moved local ref cannot turn the check green;
# zz-review/sequestration-reference-not-a-ref). It checks this file only; that no other file changes is the code review's
# (c0411 Non-goals).
# Usage: python3 narrow.py <checkout> [<file to judge instead of the checkout's>]
# (the second argument is for prep's mutation check only: check.sh never passes it).
import pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
F = "z-nile/tests/acceptance/c0043/rounds.spec.luau"


def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout


def fail(msg):
    print(msg)
    sys.exit(1)


try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network at finish)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
base = git("show", f"{MB}:{F}")
now = (pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else R / F).read_bytes()

A_AT = b'local process = require("@lune/process")\n'
A_ADD = b'local projects = require("@znile/engine/projects")\n'
B_OLD = (
    b"\t\t-- c0120 override: pickman's files live in pickman/ (its home)\n"
    b"\t\t-- c0114 override: rafts live under every project root (c0120: pickman's root is pickman/.tracker)\n"
    b"\t\tfor _, base in\n"
    b"\t\t\t-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)\n"
    b"\t\t\t{\n"
    b'\t\t\t\t"pickman/.tracker/rafts",\n'
    b'\t\t\t\t"pickman/.tracker/rafts/active",\n'
    b'\t\t\t\t"pickman/.tracker/rafts/done",\n'
    b'\t\t\t\t"z-nile/.tracker/rafts",\n'
    b'\t\t\t\t"z-nile/.tracker/rafts/active",\n'
    b'\t\t\t\t"z-nile/.tracker/rafts/done",\n'
    b"\t\t\t\t-- c0116 override: a raft recombine retired keeps its folder, and its rounds, in rafts/retired/\n"
    b'\t\t\t\t"pickman/.tracker/rafts/retired",\n'
    b'\t\t\t\t"z-nile/.tracker/rafts/retired",\n'
    b"\t\t\t}\n"
    b"\t\tdo\n"
)
B_NEW = (
    b"\t\t-- c0411 override: rafts live under every registered project's root (z-nile/projects.toml), in the four folders\n"
    b"\t\t-- a raft can stand in, so a new project or raft needs no edit here\n"
    b"\t\tlocal bases: { string } = {}\n"
    b"\t\tfor _, root in projects.roots(projects.load(TOP)) do\n"
    b'\t\t\tfor _, folder in { "rafts", "rafts/active", "rafts/done", "rafts/retired" } do\n'
    b"\t\t\t\ttable.insert(bases, `{root}/{folder}`)\n"
    b"\t\t\tend\n"
    b"\t\tend\n"
    b"\t\tfor _, base in bases do\n"
)

stale = []
for what, needle in (("(a) anchor", A_AT), ("(b) the hand-written folder list", B_OLD)):
    if base.count(needle) != 1:
        stale.append(f"{what} occurs {base.count(needle)} times, expected 1")
for word in (b"projects.roots", b"@znile/engine/projects"):
    if word in base:
        stale.append(f"the base already names {word.decode()}")
if stale:
    fail(f"{F}: the base {MB[:8]} is not the stale form c0411 was reviewed against ({'; '.join(stale)}): this check"
         " runs at finish, before the change lands; stop for a re-prep")

expected = base.replace(A_AT, A_AT + A_ADD).replace(B_OLD, B_NEW)
if now != expected:
    a, b = expected.split(b"\n"), now.split(b"\n")
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    want = a[i].decode(errors="replace") if i < len(a) else "<end of file>"
    got = b[i].decode(errors="replace") if i < len(b) else "<end of file>"
    fail(f"{F}: differs from its merge base {MB[:8]} with exactly the two c0411 hunks, first at line {i + 1}:\n"
         f"  expected: {want}\n  found:    {got}\n(apply experiments/prototype.patch exactly; if the base moved, stop for a re-prep)")
print(f"{F}: the base {MB[:8]} with exactly the two c0411 hunks")
