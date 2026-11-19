# d0416 AC1: `z-nile/tests/acceptance/c0117/control-cli.spec.luau` equals its merge base (git merge-base HEAD <origin's
# main, read with git ls-remote>) with exactly the three reviewed d0416 hunks applied, byte for byte (read as bytes), so
# a deleted or added line anywhere (an assertion dropped from any case, the quiet half deleted, wrapped in `--[[ ]]`,
# short-circuited by `do return end`, or its expectation changed to "failed") is red (lesson
# zz-test/narrowing-pins-the-whole-file). The hunks are applied by anchored substitution, each anchor's count asserted
# in the base first, so the pin depends on no line number and on no other case's text:
#   (a) the one line giving c0095 its `.models.toml` is followed by c0098's two setup lines (issue and `.models.toml`);
#   (b) the one comment line "a nested reviewer that goes quiet: ..." becomes the three-line comment saying why the
#       quiet half reviews another issue;
#   (c) the quiet half (from the bare `zn({ "dispatch", "z-design", "c0095" })` to its `"stalled"` assertion) becomes
#       the same code on c0098, with `t.expect(n).toBe(1)` before the state is read (so a missing nested folder cannot
#       read the author's own state); its expectation stays "stalled".
# Three windows (lesson z-design/exact-checks-compare-against-the-merge-base): before the change lands, the base is the
# stale form and the file must be the base plus the hunks; once the change is on origin's main (this branch landed, or
# main moved on), the base already holds all three new forms and none of the old, and the file must equal that base
# (nothing weakened since), which is not vacuous: the new forms must be there. A base holding some hunks only, or an
# anchor whose count is wrong, is not the form this was reviewed against: red, stop for a re-prep. The base is
# origin's published main read with git ls-remote (a moved local ref cannot turn the check green; zz-review/
# sequestration-reference-not-a-ref); the check trusts this machine's git and the origin it resolves (check.sh prints
# the URL). It checks this file only; that no engine file changes is AC4's.
# Usage: python3 narrow.py <checkout> [<file to judge instead of the checkout's>]
# (the second argument is for prep's mutation check only: check.sh never passes it).
import pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
F = "z-nile/tests/acceptance/c0117/control-cli.spec.luau"


def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout


def fail(msg):
    print(msg)
    sys.exit(1)


try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()
try:
    base = git("show", f"{MB}:{F}")
except subprocess.CalledProcessError:
    fail(f"{F} is not in the merge base {MB[:8]}")
try:
    now = (pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else R / F).read_bytes()
except OSError:
    fail(f"{F} is missing from the checkout")

T = b"\t"
A_OLD = (
    T * 3 + b'["pickman/.tracker/issues/c0095/.models.toml"] = "[dispatch]\\ntool_seconds = 8\\nstall_seconds = 8\\n",\n'
)
A_NEW = (
    A_OLD
    + T * 3 + b'["pickman/.tracker/issues/c0098/c0098.md"] = issue("c0098", "quiet-review"),\n'
    + T * 3 + b'["pickman/.tracker/issues/c0098/.models.toml"] = "[dispatch]\\ntool_seconds = 8\\nstall_seconds = 8\\n",\n'
)
B_OLD = (
    T * 3 + b"-- a nested reviewer that goes quiet: it stalls at its own limits and its beats stop, so nothing hangs\n"
)
B_NEW = (
    T * 3 + b"-- a nested reviewer that goes quiet: it stalls at its own limits and its beats stop, so nothing hangs. It reviews\n"
    + T * 3 + b"-- another issue: c0095 holds design-review-001.md now, and a second design review is refused before any reviewer\n"
    + T * 3 + b"-- starts (d0415, d0416)\n"
)


def quiet(item, extra):
    return (
        T * 3 + b'zn({ "dispatch", "z-design", "' + item + b'" })\n'
        + T * 3 + b'local newest, n = "", 0\n'
        + T * 3 + b'for _, name in fs.readDir(dirOf("' + item + b'")) do\n'
        + T * 4 + b'local k = tonumber(string.match(name, "^zz%-review%-design%-' + item + b'%-(%d+)$") or "")\n'
        + T * 4 + b"if k and k > n then\n"
        + T * 5 + b"newest, n = name, k\n"
        + T * 4 + b"end\n"
        + T * 3 + b"end\n"
        + extra
        + T * 3 + b't.expect(fakecli.state(h, "' + item + b'", newest).outcome).toBe("stalled")\n'
    )


C_OLD = quiet(b"c0095", b"")
C_NEW = quiet(
    b"c0098", T * 3 + b"t.expect(n).toBe(1) -- c0098 is fresh: exactly one nested run, never the author's own state\n"
)
HUNKS = (("(a) c0098's two setup lines", A_OLD, A_NEW), ("(b) the quiet half's comment", B_OLD, B_NEW),
         ("(c) the quiet half", C_OLD, C_NEW))

old_counts = [base.count(o) for _, o, _ in HUNKS]
landed = [base.count(n) for _, _, n in HUNKS]
if old_counts == [1, 1, 1] and b"c0098" not in base:
    expected, window = base, "stale base"
    for _, o, n in HUNKS:
        expected = expected.replace(o, n)
elif landed == [1, 1, 1] and old_counts[1:] == [0, 0]:
    # the change is on main: (a)'s old line stays inside its new text, so only (b) and (c) must be gone
    expected, window = base, "landed base"
else:
    detail = "; ".join(f"{w}: {o} old and {n} new occurrences" for (w, _, _), o, n in zip(HUNKS, old_counts, landed))
    fail(f"{F}: the base {MB[:8]} is neither the stale form d0416 was reviewed against nor the landed form ({detail}): "
         "stop for a re-prep")

if now != expected:
    a, b = expected.split(b"\n"), now.split(b"\n")
    i = next((k for k in range(min(len(a), len(b))) if a[k] != b[k]), min(len(a), len(b)))
    want = a[i].decode(errors="replace") if i < len(a) else "<end of file>"
    got = b[i].decode(errors="replace") if i < len(b) else "<end of file>"
    fail(f"{F}: differs from its merge base {MB[:8]} with exactly the three d0416 hunks, first at line {i + 1}:\n"
         f"  expected: {want}\n  found:    {got}\n(apply experiments/prototype.patch exactly; if the base moved, stop for a re-prep)")
print(f"{F}: the {window} {MB[:8]}" + (" with exactly the three d0416 hunks" if window == "stale base" else " unchanged"))
