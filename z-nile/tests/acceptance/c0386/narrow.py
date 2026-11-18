# c0386 AC2: c0371's promoted check-paths-homes spec equals its merge base (git merge-base HEAD <origin's main, read
# with git ls-remote>) with only the one fixture entry of its grep case respelled in two literals, byte for byte (read
# as bytes): a deleted assertion, a commented or moved entry, an added `do return end`, an entry joined onto the comment
# above it or a changed line ending is red. It runs at `./zn finish`, before the change lands: a base that already holds
# the new lines is red (the base is origin's published main read with git ls-remote, so a moved local ref cannot turn
# the check green). Another item in the same raft that changes the file turns it red with a message saying so. c0302's
# narrow.py is the model. The banned option is built from parts, so this file names none of it (the fence scan reads no
# .py today; the parts keep it safe if it ever does). The path is spelled whole, so a compaction rewrites it.
# Usage: python3 narrow.py <checkout>.
import pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])


def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout


def fail(msg):
    print(msg)
    sys.exit(1)


# the base is the published main, read from the remote (git ls-remote writes no ref), never the local origin/main ref:
# the branch's author can write that ref (zz-review/sequestration-reference-not-a-ref)
try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network at finish)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
F = "z-nile/tests/acceptance/c0371/check-paths-homes.spec.luau"
OPT = b"env" + b" -i"
ANCHOR = b"\t\t\t\t\t'" + OPT + b' grep -qF "src/nothing" "$F"\',\n'
NEW = (
    b"\t\t\t\t\t-- in two parts: the repository fence scan bans the literal in a file that runs as a check (c0386)\n"
    + b'\t\t\t\t\t"env " .. \'-i grep -qF "src/nothing" "$F"\',\n'
)
base = git("show", f"{MB}:{F}")
if base.count(ANCHOR) != 1 or base.count(NEW) != 0:
    fail(
        f"{F}: expected one literal fixture entry and no respelled one at the base, found {base.count(ANCHOR)} and "
        f"{base.count(NEW)} (this check runs at finish, before the change lands; a base that already holds it is not "
        "trusted)"
    )
if (R / F).read_bytes() != base.replace(ANCHOR, NEW):
    fail(
        f"{F}: differs from the base with only the fixture entry respelled (if another item in this raft changes this "
        "file, c0386 must not share its raft: split the raft)"
    )
