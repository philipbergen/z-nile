# c0304 AC2: `z-nile/tests/acceptance/c0045/workstreams.spec.luau` equals its merge base (git merge-base HEAD
# <origin's main, read with git ls-remote>) with exactly the three reviewed c0304 hunks applied, byte for byte (read as
# bytes), so a deleted or added line anywhere (a `--[[`, a `do return end`, a rebinding, a reworded comment, a push
# through raw process.exec) is red (design review 001 F1; lesson zz-test/narrowing-pins-the-whole-file). The hunks are
# applied by anchored substitution, each anchor's count asserted in the base first, so the pin does not depend on line
# numbers or on any other case's text (c0178 edits the first case's clone setup, which no anchor touches):
#   (a) after the one `t.expect(tip ~= git(main, { "rev-parse", "origin/main" })).toBe(true)` line, the two
#       `-- c0304 override:` comment lines and `git(wt1, { "branch", "raft-tip", tip })`;
#   (b) both `{ "worktree", "ws-f0010", "--from", "R0010-demo" }` (exactly two) name `raft-tip` instead;
#   (c) after the one `git(wt1, { "commit", "-qm", "stream review files" })` line, the two `-- c0304 override:`
#       comment lines and `git(wt1, { "push", "-q", "origin", "HEAD" })`.
# It runs at `./zn finish` and `./zn done`, before the change lands: a base where an anchor's count differs, or that
# already names `raft-tip` or `"push"`, is not the stale form this was reviewed against, and is red: stop for a re-prep
# (the base is origin's published main read with git ls-remote, so a moved local ref cannot turn the check green;
# zz-review/sequestration-reference-not-a-ref). It checks this file only; that no other file changes is the code
# review's (c0304 Non-goals).
# Usage: python3 narrow.py <checkout> [<file to judge instead of the checkout's>]
# (the second argument is for prep's mutation check only: check.sh never passes it).
import pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
F = "z-nile/tests/acceptance/c0045/workstreams.spec.luau"


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

A_AT = b'\t\tt.expect(tip ~= git(main, { "rev-parse", "origin/main" })).toBe(true)\n'
A_ADD = (
    b"\t\t-- c0304 override: since #296 a raft worktree is detached until start opens a layer, so the ref is a\n"
    b"\t\t-- branch the case makes at the raft work's tip (worktrees share refs); wt1 itself stays detached\n"
    b'\t\tgit(wt1, { "branch", "raft-tip", tip })\n'
)
B_OLD = b'{ "worktree", "ws-f0010", "--from", "R0010-demo" }'
B_NEW = b'{ "worktree", "ws-f0010", "--from", "raft-tip" }'
C_AT = b'\t\tgit(wt1, { "commit", "-qm", "stream review files" })\n'
C_ADD = (
    b"\t\t-- c0304 override: since #296 done first refuses a tree that is not the published top layer, so the\n"
    b"\t\t-- layer is pushed to the fixture's origin and done reaches the review check\n"
    b'\t\tgit(wt1, { "push", "-q", "origin", "HEAD" })\n'
)

stale = []
for what, needle, want in ((("(a) anchor", A_AT, 1)), ("(b) --from R0010-demo", B_OLD, 2), ("(c) anchor", C_AT, 1)):
    if base.count(needle) != want:
        stale.append(f"{what} occurs {base.count(needle)} times, expected {want}")
for word in (b"raft-tip", b'"push"'):
    if word in base:
        stale.append(f"the base already names {word.decode()}")
if stale:
    fail(f"{F}: the base {MB[:8]} is not the stale form c0304 was reviewed against ({'; '.join(stale)}): this check"
         " runs at finish, before the change lands; stop for a re-prep")

expected = base.replace(A_AT, A_AT + A_ADD).replace(B_OLD, B_NEW).replace(C_AT, C_AT + C_ADD)
if now != expected:
    a, b = expected.split(b"\n"), now.split(b"\n")
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    want = a[i].decode(errors="replace") if i < len(a) else "<end of file>"
    got = b[i].decode(errors="replace") if i < len(b) else "<end of file>"
    fail(f"{F}: differs from its merge base {MB[:8]} with exactly the three c0304 hunks, first at line {i + 1}:\n"
         f"  expected: {want}\n  found:    {got}\n(apply experiments/prototype.patch exactly; if the base moved, stop for a re-prep)")
print(f"{F}: the base {MB[:8]} with exactly the three c0304 hunks")
