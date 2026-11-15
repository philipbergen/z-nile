# c0359 AC6: the promoted c0172 deploy spec equals its merge base (git merge-base HEAD <origin's main, read with
# git ls-remote>) with only c0359's override, byte for byte (read as bytes): its one "the only workflow file is
# deploy.yml" case renamed, preceded by one comment line, and its expected list widened to deploy.yml and static.yml.
# So a deleted assertion, an added line (a `do return end`, a `--[[`), a joined line, an edited comment or a changed line
# ending anywhere in the file is red. A base that already holds the override, or lacks either anchor, is red: the check
# runs at `./zn finish`, before the change lands (c0302's narrow.py is the model). Usage: python3 narrow.py <checkout>.
import pathlib, subprocess, sys
R = pathlib.Path(sys.argv[1])
def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout
def fail(msg):
    print(msg); sys.exit(1)
# the base is the published main, read from the remote (git ls-remote writes no ref), never the local origin/main ref:
# the branch's author can write that ref (zz-review/sequestration-reference-not-a-ref). A swapped `origin` is review's
# to catch; check.sh prints the URL it resolves.
try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network at finish)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
F = "z-nile/tests/acceptance/c0172/deploy.spec.luau"
TITLE = b'\tit("the only workflow file is deploy.yml", function()\n'
LIST = b'\t\tt.expect(names).toEqual({ "deploy.yml" })\n'
NEW_TITLE = (b"\t-- c0359 override: the static check is the one other workflow (c0359's workflow spec pins what it runs)\n"
             b'\tit("the only workflow files are deploy.yml and static.yml", function()\n')
NEW_LIST = b'\t\tt.expect(names).toEqual({ "deploy.yml", "static.yml" })\n'
base = git("show", f"{MB}:{F}")
if base.count(TITLE) != 1 or base.count(LIST) != 1 or base.count(b"static.yml") != 0:
    fail(f"{F}: expected one deploy.yml-only case and no static.yml at the base {MB[:8]}, found {base.count(TITLE)}, "
         f"{base.count(LIST)} and {base.count(b'static.yml')} (this check runs at finish, before the change lands; a "
         "base that already holds it, or one that moved, is not trusted: stop and re-prep)")
want = base.replace(TITLE, NEW_TITLE).replace(LIST, NEW_LIST)
if (R / F).read_bytes() != want:
    fail(f"{F}: differs from its base {MB[:8]} with only c0359's override (the renamed case, its comment line and the "
         "widened list); if another item in this raft changes this file, c0359 must not share its raft")
print(f"{F}: its base {MB[:8]} plus c0359's override, byte for byte")
