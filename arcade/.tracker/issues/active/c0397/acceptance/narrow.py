# c0397 AC1: f0201's two promoted specs that f0395 (Test purchase screen strikes the price) turns red are narrowed in
# their three cases, and nothing else of f0201's changes. Read as bytes and compared byte for byte, so a deleted
# assertion, a line joined onto the comment above it, an added `do return end` or a changed line ending is red:
# - the base is the merge base of HEAD and origin's published main (read with git ls-remote, which writes no ref, so a
#   moved local ref cannot turn the check green), and f0201 is done there: its folder in done/ and its six specs
#   promoted to arcade/tests/acceptance/f0201;
# - config.spec and receipts.spec at the base are f0201's prepared blobs (the files c0397 was cut and proven on, before
#   and after f0395's change), each anchor occurs there once and none of the new text does (a base that already holds
#   the narrowing is not trusted: this check runs before the change lands, at finish and at done);
# - each file in the working tree is its base with exactly the anchored substitutions, which is the reviewed blob;
# - every other file of arcade/tests/acceptance/f0201 (watch files aside, which `./zn finish` may write) and f0201's
#   finished check.sh are byte for byte as at the base, and the folder gains and loses no file.
# Trust boundary: it trusts this machine's git and the origin URL it resolves (check.sh prints that URL); the pull
# request's diff and the code review are the backstop. It is no spec: only c0397's check.sh runs it, so it charges no
# later editor of these files. The paths are spelled whole, so a compaction rewrites them.
# Usage: python3 -I narrow.py <checkout>.
import hashlib, os, pathlib, subprocess, sys

R = pathlib.Path(sys.argv[1])
F = "arcade/tests/acceptance/f0201/"
CONFIG = F + "config.spec.luau"
RECEIPTS = F + "receipts.spec.luau"
CHECK = "arcade/.tracker/issues/done/f0201/check.sh"

# path: (f0201's prepared blob, the reviewed narrowed blob, [(anchor, replacement)])
NARROW = {
    CONFIG: (
        "f09b9d38e17cae490d4b95f94cc60609d5275837",
        "4d20b2130d0f37673038638868adafe9c78af067",
        [
            (
                b'\t\t\tt.expect(Prices).toEqual({ struck = "5 R$", price = "1 R$", sale = "SALE" })\n',
                b"\t\t\t-- field by field (c0397): the table may hold more than the badge's three words (f0395 adds a"
                b" revive's price)\n"
                b'\t\t\tt.expect(Prices.struck).toBe("5 R$")\n'
                b'\t\t\tt.expect(Prices.price).toBe("1 R$")\n'
                b'\t\t\tt.expect(Prices.sale).toBe("SALE")\n',
            ),
            (
                b'\t\tt.expect(PaidPlay.testLines("SNAKE", "play", Prices)).toEqual({\n'
                b'\t\t\t"SNAKE: 1 GAME",\n'
                b'\t\t\t"5 R$ 1 R$ SALE",\n'
                b'\t\t\t"TEST PURCHASE: NOTHING IS CHARGED",\n'
                b"\t\t})\n"
                b'\t\tt.expect(PaidPlay.testLines("PICKMAN", "revive", Prices)[1]).toBe("PICKMAN: REVIVE: 3 NEW LIVES")\n',
                b"\t\t-- the price line, the second, is not pinned here (c0397): f0395 strikes it and its own specs pin it\n"
                b'\t\tlocal lines = PaidPlay.testLines("SNAKE", "play", Prices)\n'
                b"\t\tt.expect(#lines).toBe(3)\n"
                b'\t\tt.expect(lines[1]).toBe("SNAKE: 1 GAME")\n'
                b'\t\tt.expect(lines[3]).toBe("TEST PURCHASE: NOTHING IS CHARGED")\n'
                b'\t\tt.expect(PaidPlay.testLines("PICKMAN", "revive", Prices)[1]).toBe("PICKMAN: REVIVE: 3 NEW LIVES")\n'
                b"\t\t-- a revive's screen has the same three lines, the note last (receipts.spec compares Receipts'"
                b" through testLines)\n"
                b'\t\tlocal revive = PaidPlay.testLines("PICKMAN", "revive", Prices)\n'
                b"\t\tt.expect(#revive).toBe(3)\n"
                b'\t\tt.expect(revive[3]).toBe("TEST PURCHASE: NOTHING IS CHARGED")\n',
            ),
        ],
    ),
    RECEIPTS: (
        "d298dee9fb2268447976155b68c39cea26cf0233",
        "3e9e500785d27df479e87b06ac59c208ba5bfb5f",
        [
            (
                b"\t\tlocal expected: { any } = {\n"
                b'\t\t\t"open",\n'
                b'\t\t\t{ "INVADERS: REVIVE: 3 NEW LIVES", "5 R$ 1 R$ SALE", "TEST PURCHASE: NOTHING IS CHARGED" },\n'
                b"\t\t}\n",
                b"\t\t-- the lines are the library's for the title and kind (c0397): config.spec pins them, f0395 changes"
                b" the price line\n"
                b'\t\tlocal expected: { any } = { "open", PaidPlay.testLines("INVADERS", "revive", Prices) }\n',
            ),
        ],
    ),
}


def git(*a):
    return subprocess.run(["git", "-C", str(R), *a], capture_output=True, check=True).stdout


def fail(msg):
    print(msg)
    sys.exit(1)


def blob(data):
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()


def watch(name):
    return name == "watch.txt" or name.endswith(".watch.txt")


try:
    tip = git("ls-remote", "origin", "refs/heads/main").decode().split()[0]
except (subprocess.CalledProcessError, IndexError):
    fail("cannot read origin's main with git ls-remote (this check needs the network)")
if subprocess.run(["git", "-C", str(R), "cat-file", "-e", tip + "^{commit}"], capture_output=True).returncode != 0:
    fail(f"origin's main {tip[:8]} is not fetched: fetch origin main first")
MB = git("merge-base", "HEAD", tip).decode().strip()


def at_base(path):
    r = subprocess.run(["git", "-C", str(R), "cat-file", "blob", f"{MB}:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


# f0201 is done at the base
if at_base(CHECK) is None or at_base(CONFIG) is None or at_base(RECEIPTS) is None:
    fail(f"f0201 is not done at the base {MB[:8]}: {CHECK} and its promoted specs under {F} must exist there")

problems = []

# the two narrowed files: the prepared base with exactly the anchored substitutions, byte for byte
for path, (base_id, want_id, subs) in NARROW.items():
    base = at_base(path)
    if blob(base) != base_id:
        fail(f"{path} at the base is blob {blob(base)[:8]}, not f0201's prepared {base_id[:8]} that c0397 was cut and "
             "proven on: stop and escalate for a re-prep of c0397")
    want = base
    for old, new in subs:
        if base.count(old) != 1 or base.count(new) != 0:
            fail(f"{path}: expected one anchor and no narrowed text at the base, found {base.count(old)} and "
                 f"{base.count(new)} (this check runs before the change lands; a base that already holds it is not "
                 "trusted)")
        want = want.replace(old, new)
    if blob(want) != want_id:
        fail(f"{path}: the base with the substitutions is blob {blob(want)[:8]}, not the reviewed {want_id[:8]}")
    p = R / path
    got = p.read_bytes() if p.is_file() else None
    if got == base:
        problems.append(f"{path} is not narrowed: it is still f0201's prepared file")
    elif got != want:
        problems.append(f"{path} is not exactly f0201's file with c0397's three narrowed cases (blob "
                        f"{blob(got)[:8] if got is not None else 'missing'}, want {want_id[:8]}); if another item in "
                        "this raft changes it, c0397 must not share its raft: split the raft")

# every other file of f0201's promoted folder, and its finished check.sh, as at the base; nothing added or removed
listed = git("ls-tree", "-r", "--name-only", MB, "--", F, CHECK).decode().splitlines()
here = [F + n for n in sorted(os.listdir(R / F))] if (R / F).is_dir() else []
for path in sorted(set(listed) | set(here)):
    if path in NARROW or watch(os.path.basename(path)):
        continue
    p = R / path
    if path not in listed:
        problems.append(f"{path} is added: c0397 changes no other file of f0201's")
    elif not p.is_file():
        problems.append(f"{path} is missing: c0397 changes no other file of f0201's")
    elif p.read_bytes() != at_base(path):
        problems.append(f"{path} differs from the base: c0397 changes no other file of f0201's")
if CHECK not in listed:
    problems.append(f"{CHECK} is not at the base")

for line in problems:
    print(line)
sys.exit(1 if problems else 0)
