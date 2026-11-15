# c0302 AC1: each of the seven promoted specs equals its merge base (git merge-base HEAD <origin's main, read with
# git ls-remote>) with only the two c0302 lines inserted after its one `git({ "remote", "remove", "origin" })` line,
# byte for byte (read as bytes), so a deleted assertion, an added case, an edited comment or a changed line ending is
# red. It runs at `./zn finish`, before the change lands: a base that already holds the inserted lines is red (the base
# is origin's published main read with git ls-remote, so a moved local ref cannot turn the check green). It checks
# these files only: another item in the same raft that changes one turns it red with a message saying so (c0269's
# narrow.py is the model). Each path is spelled whole, so a compaction rewrites it with the folder it names.
# Usage: python3 narrow.py <checkout>.
import pathlib, subprocess, sys
R = pathlib.Path(sys.argv[1])
def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout
def fail(msg):
    print(msg); sys.exit(1)
# the base is the published main, read from the remote (git ls-remote writes no ref), never the local origin/main ref:
# the branch's author can write that ref (zz-review/sequestration-reference-not-a-ref). The remote itself, a swapped
# `origin`, is review's to catch; check.sh prints the URL it resolves.
try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network at finish)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
FILES = [
    "z-nile/tests/acceptance/c0001/tracker-lifecycle.spec.luau",
    "z-nile/tests/acceptance/c0008/done-order.spec.luau",
    "z-nile/tests/acceptance/c0038/deferred.spec.luau",
    "z-nile/tests/acceptance/c0050/start-depends.spec.luau",
    "z-nile/tests/acceptance/c0074/done-gate.spec.luau",
    "z-nile/tests/acceptance/c0080/consequences.spec.luau",
    "z-nile/tests/acceptance/c0120/promote-home.spec.luau",
]
ANCHOR = b'\t\tgit({ "remote", "remove", "origin" })\n'
NAMED = b'\t\tgit({ "checkout", "-q", "-B", "main" })\n'
ADD = (b"\t\t-- c0302: the clone has no origin, so its branch is its main: on a stack layer branch `./zn start` finds no other\n"
       + NAMED)
SPLIT = " (if another item in this raft changes this file, c0302 must not share its raft: split the raft)"
bad = []
for f in FILES:
    base = git("show", f"{MB}:{f}")
    if base.count(ANCHOR) != 1 or base.count(NAMED) != 0:
        bad.append(f"{f}: expected one origin removal and no `checkout -B main` at the base, found {base.count(ANCHOR)} and {base.count(NAMED)} (this check runs at finish, before the change lands; a base that already holds it is not trusted)")
        continue
    if (R / f).read_bytes() != base.replace(ANCHOR, ANCHOR + ADD):
        bad.append(f"{f}: differs from the base with the two c0302 lines inserted after the origin removal" + SPLIT)
if bad:
    print("\n".join(bad)); sys.exit(1)
