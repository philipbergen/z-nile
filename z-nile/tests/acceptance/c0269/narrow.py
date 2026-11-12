# c0269 AC4: each of the two promoted specs equals its merge base (git merge-base HEAD <origin's main, from git ls-remote>) with only its named
# substitutions applied, byte for byte (read as bytes), so a deleted assertion, an added case, an edited comment or a
# changed line ending is red; and z-nile/tests/inputs.tsv keeps every row it had at the merge base and gains the one row
# this issue declares. It runs at `./zn done`, before the change lands: a base that already holds a `new` text is red
# (the base is origin's published main read with git ls-remote, so a moved local ref cannot turn the check green). It checks these files only: another item in the same raft that changes them turns it red
# with a message saying so. Usage: python3 narrow.py <checkout>.
import pathlib, subprocess, sys
R = pathlib.Path(sys.argv[1])
A = "z-nile/tests/acceptance/"
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
    fail("cannot read origin's main with git ls-remote (this check needs the network at done)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
SUBS = {
    "c0074/done-gate.spec.luau": [
        ("`tracker.sh done` runs the full gate on the final tree", "`tracker.sh done` runs the affected gate on the final tree"),
        ('t.spec("c0800 done runs the full gate after promotion"', 't.spec("c0800 done runs the affected gate after promotion"'),
        ('it("done runs the full gate on the promoted, moved tree, then commits"', 'it("done runs the affected gate on the promoted, moved tree, then commits"'),
        ('it("the gate decision: full, unless inside a spec run without the switch"', 'it("the gate decision: affected, unless inside a spec run without the switch"'),
    ],
    "c0080/consequences.spec.luau": [
        ("(so done skips the full gate, c0800)", "(so done skips the gate, c0800)"),
    ],
}
ROW = b"tests/acceptance/c0269/titles.spec.luau\tz-nile/tests/\n"
SPLIT = " (if another item in this raft changes this file, c0269 must not share its raft: split the raft)"
bad = []
for f, subs in SUBS.items():
    want = git("show", f"{MB}:{A}{f}")
    for old, new in subs:
        old, new = old.encode(), new.encode()
        if want.count(old) == 1 and want.count(new) == 0:
            want = want.replace(old, new)
        else:
            bad.append(f"{f}: expected one {old!r} and no {new!r} at the base, found {want.count(old)} and {want.count(new)} (this check runs at done, before the change lands; a base that already holds it is not trusted)")
    if (R / (A + f)).read_bytes() != want:
        bad.append(f"{f}: differs from the base with its named substitutions applied" + SPLIT)
base_rows = git("show", f"{MB}:z-nile/tests/inputs.tsv").splitlines(keepends=True)
head_rows = (R / "z-nile/tests/inputs.tsv").read_bytes().splitlines(keepends=True)
pool = list(head_rows)
for r in base_rows:
    if r in pool:
        pool.remove(r)
    else:
        bad.append(f"z-nile/tests/inputs.tsv lost or changed a row: {r!r}")
if ROW not in head_rows and ROW not in base_rows:
    bad.append("z-nile/tests/inputs.tsv does not declare the titles.spec row")
if bad:
    print("\n".join(bad)); sys.exit(1)
