#!/usr/bin/env python3
# c0397's prep experiment (E1 to E4): builds both bases from committed files, proves the narrowing on each, and runs
# the mutants. It takes no directory: it clones this checkout's HEAD into a fresh mktemp -d (outside every
# repository), with a bare origin of its own there, and removes both when it ends.
#   base a  = HEAD + f0201's prototype.patch + f0201's six specs promoted + f0201's architecture section (as f0395's
#             prototype emulated it, experiments/f0201-architecture.patch) + f0201's folder in done/ without
#             acceptance/ + the watch files `./zn finish` writes: f0201 done, as `./zn done` leaves it;
#   base b  = base a + f0395's experiments/prototype.patch as prepared on main;
#   a-n/b-n = each base + this folder's experiments/prototype.patch (c0397's narrowing).
# Controls (E1/E2): f0201's six specs on a, a-n, b, b-n (b: exactly the three cases red), f0395's three on b-n,
# f0201's check.sh on a-n, and acceptance/narrow.py on a (red), a-n and b-n (green).
# C rows: code mutants on a-n and b-n; the row's narrowed case must fail on an assertion (killed), not pass
# (SURVIVED) or fail to load (NO RUN). W rows: the window's gaps (expected to survive f0201's specs).
# N rows: narrowed-file mutants on a-n; acceptance/narrow.py must be red (N13: c0397's check.sh, its digest pin of
# narrow.py). V rows: changes it must stay green for. Last, c0397's whole check.sh on a-n (2/2).
# It refuses when f0201's or f0395's patch or specs moved (f0395's: c0397 design review 001 F2; lesson
# z-design/in-flight-bases-pin-their-source).
# Run from the repository root: ./zn run --time 1800 -- python3 -I <this file>
import hashlib, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
ISSUE = os.path.dirname(HERE)
SRC = subprocess.run(["git", "-C", HERE, "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                     check=True).stdout.strip()
HEAD = subprocess.run(["git", "-C", SRC, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()

F0201 = "arcade/.tracker/issues/f0201/"
F0395 = "arcade/.tracker/issues/f0395/"
PINS = {
    F0201 + "experiments/prototype.patch": "f99bd914ff800cfc3403ab4000109951694ebebaa2b6d8381d7b8879d6afce7b",
    F0201 + "acceptance/client.spec.luau": "2857017d50846309af69865bccc41373b22345be8c79480a57828e43e67d93fb",
    F0201 + "acceptance/config.spec.luau": "7e56aa626a1ea77f22db189421e5a27db27f9c0957592662b9c3e0fdfa93d9cf",
    F0201 + "acceptance/paidplay.spec.luau": "aae86ec29db24ac1b0adb7ff4d08d176e6e6d305529cba97df7fc7400d6585e8",
    F0201 + "acceptance/place.spec.luau": "951e7168f9b7e434976f8263aad8fea1898393685456a70128fcb1b9d259e8ab",
    F0201 + "acceptance/receipts.spec.luau": "e531907a48ddb0ee9f87417a9a28bab9f80bfac0209626bf0bd4eb8dfc732e7c",
    F0201 + "acceptance/wallet.spec.luau": "eb9d28573e239789e79365ed8d3687b1e5df01ed1711aa2dcf30b75a6f67e443",
    F0395 + "experiments/prototype.patch": "f2a54c44b12b484e4e163c1c5f942ad75d8fec272229ecc3e7047476bf143deb",
    F0395 + "acceptance/client.spec.luau": "12d389f9c3e7004cfcca0083c839cfa7864f14263ec37a0318993c2fcc388711",
    F0395 + "acceptance/docs.spec.luau": "ede223595cfe20e2daaae7f47057e1048c3dfd18800cf77d763ecb2a6204d955",
    F0395 + "acceptance/lines.spec.luau": "33a3be705de3f3f5b99ae05eba3a432bb7336a6627a7fac7004dc10ac12ae464",
}
for rel, want in PINS.items():
    got = hashlib.sha256(open(os.path.join(SRC, rel), "rb").read()).hexdigest()
    if got != want:
        sys.exit(f"refused: {rel} moved ({got[:8]}); re-cut c0397's prototype and rerun")

WATCH = {
    "arcade/tests/acceptance/f0201/watch.txt": "arcade/src/server/Catalog.luau\narcade/src/server/Receipts.luau\n"
    "arcade/src/server/Wallet.luau\narcade/src/shared/Logic/PaidPlay/init.luau\narcade/src/shared/Prices.luau\n"
    "arcade/src/shared/TestPurchase.luau\n",
    "arcade/tests/unit/PaidPlay/paidplay.watch.txt": "arcade/src/shared/Logic/PaidPlay/init.luau\n",
}

TMP = tempfile.mkdtemp(prefix="c0397-mut-")
if os.path.realpath(TMP).startswith(os.path.realpath(SRC) + os.sep):
    sys.exit(f"refused: {TMP} is inside the checkout")
ROOT = os.path.join(TMP, "repo")
ORIGIN = os.path.join(TMP, "origin.git")
HOME = os.path.join(ROOT, "arcade")
ENV = dict(os.environ, GIT_AUTHOR_NAME="c0397-proto", GIT_AUTHOR_EMAIL="c0397-proto@localhost",
           GIT_COMMITTER_NAME="c0397-proto", GIT_COMMITTER_EMAIL="c0397-proto@localhost")


def git(*a, cwd=None):
    return subprocess.run(["git", *a], cwd=cwd or ROOT, capture_output=True, text=True, check=True, env=ENV).stdout


def commit(msg):
    git("add", "-A")
    git("-c", "commit.gpgsign=false", "commit", "-qm", msg)
    return git("rev-parse", "HEAD").strip()


def publish(ref):  # origin's main, as narrow.py reads it with ls-remote
    git("push", "-q", "-f", ORIGIN, f"{ref}:refs/heads/main")
    git("fetch", "-q", "origin")


SUMMARY = re.compile(r"^(\d+) passed, (\d+) failed, (\d+) spec files?$")


def run(specs):
    p = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True,
                       timeout=900)
    out = p.stdout + p.stderr
    s = None
    for line in out.splitlines():
        m = SUMMARY.match(line.strip())
        if m:
            s = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    fails = sorted({l.split(" :: ", 1)[1].strip() for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l})
    return s, fails, "could not load" in out


def narrow():
    p = subprocess.run(["python3", "-I", os.path.join(ISSUE, "acceptance", "narrow.py"), ROOT], capture_output=True,
                       text=True, timeout=120)
    return p.returncode, (p.stdout + p.stderr).strip().replace("\n", " | ")


F = ["tests/acceptance/f0201/" + n + ".spec.luau" for n in ("paidplay", "config", "wallet", "receipts", "client", "place")]
CONFIG, RECEIPTS = F[1], F[3]
OWN395 = [".tracker/issues/f0395/acceptance/" + n + ".spec.luau" for n in ("lines", "client", "docs")]
PRICES_CASE = "the badge text is one config table: 5 R$ struck through, on sale for 1 R$, which is the charge"
LINES_CASE = "the test screen's lines: the title and product, the badge, and that nothing is charged"
ASK_CASE = "ask in test mode opens the test screen with its lines and never prompts Roblox"
THREE = sorted([PRICES_CASE, LINES_CASE, ASK_CASE])


def show(label, s, fails, bad):
    print(f"{label}: {s}; failing cases: {fails}; load errors: {bad}", flush=True)


try:
    git("clone", "-q", "--no-hardlinks", "--no-checkout", SRC, ROOT, cwd=TMP)
    git("checkout", "-q", "--detach", HEAD)
    git("init", "-q", "--bare", ORIGIN, cwd=TMP)
    git("remote", "set-url", "origin", ORIGIN)
    git("config", "user.email", "c0397-proto@localhost")
    git("config", "user.name", "c0397-proto")
    publish("HEAD")
    # base a: f0201 done
    git("apply", F0201 + "experiments/prototype.patch")
    git("apply", os.path.join(HERE, "f0201-architecture.patch"))
    os.makedirs(os.path.join(ROOT, "arcade/tests/acceptance/f0201"), exist_ok=True)
    for n in ("client", "config", "paidplay", "place", "receipts", "wallet"):
        shutil.copyfile(os.path.join(ROOT, F0201, "acceptance", n + ".spec.luau"),
                        os.path.join(ROOT, "arcade/tests/acceptance/f0201", n + ".spec.luau"))
    for rel, text in WATCH.items():
        open(os.path.join(ROOT, rel), "w").write(text)
    os.makedirs(os.path.join(ROOT, "arcade/.tracker/issues/done"), exist_ok=True)
    git("mv", F0201.rstrip("/"), "arcade/.tracker/issues/done/f0201")
    shutil.rmtree(os.path.join(ROOT, "arcade/.tracker/issues/done/f0201/acceptance"))
    A = commit("base a: f0201 done")
    git("apply", F0395 + "experiments/prototype.patch")
    B = commit("base b: f0395's change")
    git("checkout", "-q", "--detach", A)
    git("apply", os.path.join(HERE, "prototype.patch"))
    AN = commit("a-n: c0397's narrowing")
    git("checkout", "-q", "--detach", B)
    git("apply", os.path.join(HERE, "prototype.patch"))
    BN = commit("b-n: c0397's narrowing")
    print(f"bases: a {A[:9]}, b {B[:9]}, a-n {AN[:9]}, b-n {BN[:9]} (from {HEAD[:9]})", flush=True)

    # controls
    publish(A)
    git("checkout", "-q", "--detach", A)
    show("CONTROL a: f0201's six specs", *run(F))
    print(f"CONTROL a: narrow.py {narrow()}", flush=True)
    git("checkout", "-q", "--detach", B)
    s, fails, bad = run(F)
    show("CONTROL b: f0201's six specs, un-narrowed, with f0395", s, fails, bad)
    print(f"CONTROL b: exactly the three cases red: {fails == THREE}", flush=True)
    git("checkout", "-q", "--detach", AN)
    show("CONTROL a-n: f0201's six specs", *run(F))
    print(f"CONTROL a-n: narrow.py {narrow()}", flush=True)
    p = subprocess.run(["bash", os.path.join(ROOT, "arcade/.tracker/issues/done/f0201/check.sh")], cwd=ROOT,
                       capture_output=True, text=True, timeout=900)
    print(f"CONTROL a-n: f0201's check.sh exit {p.returncode}: {[l for l in p.stdout.splitlines() if l.startswith('----')]}",
          flush=True)
    git("checkout", "-q", "--detach", BN)
    show("CONTROL b-n: f0201's six specs and f0395's three", *run(F + OWN395))
    publish(B)
    print(f"CONTROL b-n (origin main = b): narrow.py {narrow()}", flush=True)
    publish(A)

    PP = "arcade/src/shared/Logic/PaidPlay/init.luau"
    PR = "arcade/src/shared/Prices.luau"
    RC = "arcade/src/server/Receipts.luau"
    NOTE_A, NOTE_B = "\t\tPaidPlay.TEST_NOTE,\n", "\t\tplain(PaidPlay.TEST_NOTE),\n"
    # id, file, {base: (old, new)}, spec, case, what it is
    C = [
        ("C1", PR, ('struck = "5 R$",', 'struck = "5R$",'), None, CONFIG, PRICES_CASE, "the struck words wrong"),
        ("C2", PR, ('price = "1 R$",', 'price = "2 R$",'), None, CONFIG, PRICES_CASE, "the price words wrong"),
        ("C3", PR, ('sale = "SALE",', 'sale = "ON SALE",'), None, CONFIG, PRICES_CASE, "the sale word wrong"),
        ("C4", PR, ("return table.freeze({", "return ({"), None, CONFIG, PRICES_CASE, "Prices not frozen"),
        ("C5", PP, ("PaidPlay.PRICE = 1 ", "PaidPlay.PRICE = 2 "), None, CONFIG, PRICES_CASE, "the charge is not the price"),
        ("C6", PP, (NOTE_A, NOTE_A + '\t\t"",\n'), (NOTE_B, NOTE_B + '\t\t"",\n'), CONFIG, LINES_CASE, "a fourth line"),
        ("C7", PP, ('play = "1 GAME"', 'play = "1 GAMES"'), None, CONFIG, LINES_CASE, "the play's title line wrong"),
        ("C8", PP, ('PaidPlay.TEST_NOTE = "TEST PURCHASE: NOTHING IS CHARGED"', 'PaidPlay.TEST_NOTE = "TEST PURCHASE"'),
         None, CONFIG, LINES_CASE, "the note wrong"),
        ("C9", PP, (NOTE_A, '\t\tif kind == "play" then PaidPlay.TEST_NOTE else nil,\n'),
         (NOTE_B, '\t\tif kind == "play" then plain(PaidPlay.TEST_NOTE) else nil,\n'), CONFIG, LINES_CASE,
         "a revive's screen drops the note"),
        ("C10", PP, (NOTE_A, '\t\tif kind == "play" then PaidPlay.TEST_NOTE else "TEST PURCHASE",\n'),
         (NOTE_B, '\t\tif kind == "play" then plain(PaidPlay.TEST_NOTE) else "TEST PURCHASE",\n'), CONFIG, LINES_CASE,
         "a revive's last line is not the note"),
        ("C11", PP, ('revive = "REVIVE: 3 NEW LIVES"', 'revive = "REVIVE: 3 LIVES"'), None, CONFIG, LINES_CASE,
         "the revive's title line wrong"),
        ("C12", PP, ("\t\t`{prices.struck} {prices.price} {prices.sale}`,\n" + NOTE_A,
                     NOTE_A + "\t\t`{prices.struck} {prices.price} {prices.sale}`,\n"),
         ("\t\tprice,\n" + NOTE_B, NOTE_B + "\t\tprice,\n"), CONFIG, LINES_CASE, "the note before the price"),
        ("C13", RC, ("PaidPlay.testLines(t.entry.title, kind, Prices)", 'PaidPlay.testLines(t.entry.title, "play", Prices)'),
         None, RECEIPTS, ASK_CASE, "Receipts sends a play's lines for a revive"),
        ("C14", RC, ("PaidPlay.testLines(t.entry.title, kind, Prices)", "PaidPlay.testLines(name, kind, Prices)"), None,
         RECEIPTS, ASK_CASE, "Receipts sends the catalog name, not the title"),
        ("C15", RC, ('"open", PaidPlay.testLines', '"show", PaidPlay.testLines'), None, RECEIPTS, ASK_CASE,
         "Receipts sends another message"),
        ("C16", RC, ("PaidPlay.testLines(t.entry.title, kind, Prices)",
                     '{ `{t.entry.title}: {PaidPlay.KIND_TEXT[kind]}`, "5 R$ 1 R$ SALE", PaidPlay.TEST_NOTE }'), None,
         RECEIPTS, ASK_CASE, "Receipts sends a hard-coded copy of f0201's lines"),
        ("W1", PP, ("`{prices.struck} {prices.price} {prices.sale}`", "`{prices.struck} {prices.price}`"),
         ("`<s>{plain(prices.struck)}</s> {plain(prices.price)} {plain(prices.sale)}`",
          "`<s>{plain(prices.struck)}</s> {plain(prices.price)}`"), None, None, "a play's price line drops SALE"),
        ("W2", PR, ('sale = "SALE",', 'sale = "SALE",\n\tjunk = "x",'), None, None, None, "Prices gains a stray field"),
    ]

    def mutate(rel, old, new):
        path = os.path.join(ROOT, rel)
        text = open(path).read()
        if text.count(old) != 1:
            return None
        open(path, "w").write(text.replace(old, new, 1))
        return text

    only = set(sys.argv[1:])
    for base_name, ref in (("a-n", AN), ("b-n", BN)):
        git("checkout", "-q", "--detach", ref)
        for mid, rel, pa, pb, spec, case, what in C:
            if only and mid not in only:
                continue
            old, new = pa if base_name == "a-n" or pb is None else pb
            saved = mutate(rel, old, new)
            if saved is None:
                print(f"{mid} on {base_name}: NOT APPLIED (anchor not found once) - {what}", flush=True)
                continue
            try:
                if spec is None:  # a gap: does any of f0201's specs (and f0395's on b-n) catch it?
                    s, fails, bad = run(F + (OWN395 if base_name == "b-n" else []))
                    print(f"{mid} on {base_name}: {'caught' if s and s[1] else 'survives'} f0201's specs"
                          f"{' and f0395s' if base_name == 'b-n' else ''} {s} {fails} - {what}", flush=True)
                else:
                    s, fails, bad = run([spec])
                    verdict = "NO RUN" if bad or s is None else ("killed" if case in fails else "SURVIVED")
                    print(f"{mid} on {base_name}: {verdict} ({spec} {s}; {case in fails}) - {what}", flush=True)
            finally:
                open(os.path.join(ROOT, rel), "w").write(saved)
        if git("status", "--porcelain").strip():
            sys.exit("a mutant was not restored")

    # N rows: narrowed-file mutants on a-n (origin main = a); narrow.py must be red. V rows must stay green.
    git("checkout", "-q", "--detach", AN)
    CF = "arcade/" + CONFIG
    RF = "arcade/" + RECEIPTS
    CL = "arcade/tests/acceptance/f0201/client.spec.luau"
    CK = "arcade/.tracker/issues/done/f0201/check.sh"
    N = [
        ("N1", CF, '\t\t\tt.expect(PaidPlay.mode("live", {})).toBe("closed")\n', "", "an untouched case's assertion deleted"),
        ("N2", CF, "revive's price)\n\t\t\tt.expect(Prices.struck)", "revive's price) t.expect(Prices.struck)",
         "a narrowed assertion joined onto the comment above it"),
        ("N3", CF, '\t\tlocal lines = PaidPlay.testLines("SNAKE", "play", Prices)\n',
         '\t\tdo return end\n\t\tlocal lines = PaidPlay.testLines("SNAKE", "play", Prices)\n', "a do return end added"),
        ("N4", CF, "\t\tt.expect(#lines).toBe(3)\n", "", "the play's line count dropped"),
        ("N5", CF, "\t\tt.expect(#revive).toBe(3)\n", "", "the revive's line count dropped"),
        ("N6", RF, "\n", "\r\n", "receipts.spec with CRLF line endings"),
        ("N7", CL, "t.expect(", "-- t.expect(", "client.spec's first assertion commented out"),
        ("N8", CK, 'check "AC4: ', '# check "AC4: ', "f0201's check.sh no longer runs receipts.spec"),
        ("N9", RF, 'PaidPlay.testLines("INVADERS", "revive", Prices) }', 'PaidPlay.testLines("INVADERS", "play", Prices) }',
         "the receipts comparison changed"),
    ]
    for nid, rel, old, new, what in N:
        if only and nid not in only:
            continue
        path = os.path.join(ROOT, rel)
        data = open(path, "rb").read()
        o, n = old.encode(), new.encode()
        if nid != "N6" and nid != "N7" and nid != "N8" and data.count(o) != 1:
            print(f"{nid}: NOT APPLIED - {what}", flush=True)
            continue
        open(path, "wb").write(data.replace(o, n) if nid == "N6" else data.replace(o, n, 1))
        try:
            code, msg = narrow()
            s, fails, bad = run([CONFIG, RECEIPTS, "tests/acceptance/f0201/client.spec.luau"])
            print(f"{nid}: narrow.py {'red' if code else 'GREEN'} ({msg[:160]}); specs {s} - {what}", flush=True)
        finally:
            open(path, "wb").write(data)
    extra = os.path.join(HOME, "tests/acceptance/f0201/extra.spec.luau")
    open(extra, "w").write("return nil\n")
    print(f"N10: narrow.py {'red' if narrow()[0] else 'GREEN'} - a file added to f0201's folder", flush=True)
    os.remove(extra)
    publish(HEAD)
    print(f"N11: narrow.py {'red' if narrow()[0] else 'GREEN'} ({narrow()[1][:120]}) - f0201 not done at the base", flush=True)
    publish(AN)
    print(f"N12: narrow.py {'red' if narrow()[0] else 'GREEN'} ({narrow()[1][:120]}) - the base already holds the narrowing",
          flush=True)
    publish(A)
    w = os.path.join(HOME, "tests/acceptance/f0201/watch.txt")
    keep = open(w).read()
    open(w, "w").write(keep + "arcade/src/shared/TestPurchase.luau\n")
    print(f"V1: narrow.py {'green' if narrow()[0] == 0 else 'RED'} - f0201's watch.txt rewritten", flush=True)
    open(w, "w").write(keep)
    git("checkout", "-q", "--detach", BN)
    print(f"V2: narrow.py {'green' if narrow()[0] == 0 else 'RED'} - f0395's change in the tree (origin main = a)", flush=True)
    # c0397's own check.sh in the clone, as `./zn check c0397` runs it on the raft's branch (a-n, origin main = a)
    git("checkout", "-q", "--detach", AN)
    mine = os.path.join(ROOT, "arcade/.tracker/issues/c0397")
    shutil.copyfile(os.path.join(ISSUE, "check.sh"), os.path.join(mine, "check.sh"))
    shutil.copytree(os.path.join(ISSUE, "acceptance"), os.path.join(mine, "acceptance"), dirs_exist_ok=True)

    def check():
        p = subprocess.run(["bash", os.path.join(mine, "check.sh")], cwd=ROOT, capture_output=True, text=True, timeout=900)
        return [l[:60] for l in p.stdout.splitlines() if l.startswith(("PASS", "FAIL", "----"))]

    print(f"CONTROL a-n: c0397's check.sh {check()}", flush=True)
    stub = os.path.join(mine, "acceptance/narrow.py")
    keep = open(stub, "rb").read()
    open(stub, "w").write("import sys\nsys.exit(0)\n")
    print(f"N13: c0397's check.sh with narrow.py a stub that exits 0: {check()}", flush=True)
    open(stub, "wb").write(keep)
finally:
    shutil.rmtree(TMP, ignore_errors=True)
