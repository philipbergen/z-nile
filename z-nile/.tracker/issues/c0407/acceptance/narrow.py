# c0407 AC2: `z-nile/tests/acceptance/c0084/commit-phase.spec.luau` equals its merge base (git merge-base HEAD
# <origin's main, read with git ls-remote>) with exactly the two reviewed c0407 hunks applied, byte for byte (read as
# bytes), so a deleted or added line anywhere (another case changed, a `--[[`, a `do return end`, the phase assertion
# dropped, a subject assertion loosened) is red (lesson zz-test/narrowing-pins-the-whole-file). The hunks are applied by
# anchored substitution, each anchor's count asserted in the base first, so the pin depends on no line number and on no
# other case's text:
#   (a) the one line `must(tr({ "done", raft }), "done")` becomes the two-line `-- c0407 override:` comment, the
#       binding of done's output, and the match of its `session: <note>` line;
#   (b) the one line `t.expect(ra[#ra].subject).toBe(`{raft}: bind {a}, {b}`)` becomes the expected subject (the plain
#       subject, plus one space and the printed note when done printed a non-empty one) and the assertion on it.
# It runs at `./zn finish` and `./zn done`, before the change lands: a base where an anchor's count differs, or that
# already holds `c0407 override`, is not the stale form this was reviewed against, and is red: stop for a re-prep (the
# base is origin's published main read with git ls-remote, so a moved local ref cannot turn the check green;
# zz-review/sequestration-reference-not-a-ref). It checks this file only; that no other file changes is the code
# review's (c0407 Non-goals).
# Usage: python3 narrow.py <checkout> [<file to judge instead of the checkout's>]
# (the second argument is for prep's mutation check only: check.sh never passes it).
import pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
F = "z-nile/tests/acceptance/c0084/commit-phase.spec.luau"


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

A_OLD = b'\t\tmust(tr({ "done", raft }), "done")\n'
A_NEW = (
    b"\t\t-- c0407 override: since #318 done puts the session reading's note, which it also prints as `session: <note>`,\n"
    b"\t\t-- after the first row's subject, so the subject is the plain subject plus that printed note\n"
    b'\t\tlocal doneOut = must(tr({ "done", raft }), "done")\n'
    b'\t\tlocal note = string.match(doneOut, "session: ([^\\n]*)")\n'
)
B_OLD = b"\t\tt.expect(ra[#ra].subject).toBe(`{raft}: bind {a}, {b}`)\n"
B_NEW = (
    b"\t\tlocal subject = `{raft}: bind {a}, {b}`\n"
    b'\t\tif note ~= nil and note ~= "" then\n'
    b'\t\t\tsubject ..= " " .. note\n'
    b"\t\tend\n"
    b"\t\tt.expect(ra[#ra].subject).toBe(subject)\n"
)

stale = []
for what, needle in (("(a) the done call", A_OLD), ("(b) the subject assertion", B_OLD)):
    if base.count(needle) != 1:
        stale.append(f"{what} occurs {base.count(needle)} times, expected 1")
if b"c0407 override" in base:
    stale.append("the base already holds c0407 override")
if stale:
    fail(f"{F}: the base {MB[:8]} is not the stale form c0407 was reviewed against ({'; '.join(stale)}): this check"
         " runs at finish, before the change lands; stop for a re-prep")

expected = base.replace(A_OLD, A_NEW).replace(B_OLD, B_NEW)
if now != expected:
    a, b = expected.split(b"\n"), now.split(b"\n")
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    want = a[i].decode(errors="replace") if i < len(a) else "<end of file>"
    got = b[i].decode(errors="replace") if i < len(b) else "<end of file>"
    fail(f"{F}: differs from its merge base {MB[:8]} with exactly the two c0407 hunks, first at line {i + 1}:\n"
         f"  expected: {want}\n  found:    {got}\n(apply experiments/prototype.patch exactly; if the base moved, stop for a re-prep)")
print(f"{F}: the base {MB[:8]} with exactly the two c0407 hunks")
