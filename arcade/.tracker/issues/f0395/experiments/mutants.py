#!/usr/bin/env python3
# f0395's mutation check (prep only). It clones the prototype (a .worktree/proto-* checkout holding f0201's prototype
# base, f0201's specs as promoted, the f0395 change and c0397's narrowing of f0201's three cases) into a fresh
# mktemp -d, copies this issue's acceptance specs into the clone's tests/acceptance/f0395, and there:
#   1. controls: the unmutated clone passes f0395's specs and all six of f0201's (as c0397 narrows them);
#   2. base: with the three library files back at f0201's prototype, f0395's specs fail on assertions and f0201's
#      narrowed specs still pass (the narrowing holds on both sides of f0395);
#   3. mutants: each applied alone must fail its row's case on an assertion (killed), not pass (SURVIVED) or fail to
#      load (NO RUN);
#   4. correct variants: each applied alone must keep f0395's specs and every f0201 spec green (lesson
#      z-design/mutation-runner-runs-correct-variants).
# It never writes the tree it is given, refuses a root that is not a .worktree/proto-* checkout, and refuses when
# f0201's prototype patch or sequestered specs have moved (lesson z-design/in-flight-bases-pin-their-source).
# Run from the repository root: ./zn run --time 1800 -- python3 -I <this file> <prototype root> [ids...]
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.realpath(__file__))
SPECS = os.path.join(os.path.dirname(HERE), "acceptance")
PROTO = os.path.realpath(sys.argv[1])
if "/.worktree/proto-" not in PROTO + "/":
    sys.exit(f"refused: {PROTO} is not a .worktree/proto-* checkout")

F0201 = "arcade/.tracker/issues/f0201/"
BASES = {
    F0201 + "experiments/prototype.patch": "f99bd914ff800cfc3403ab4000109951694ebebaa2b6d8381d7b8879d6afce7b",
    F0201 + "acceptance/client.spec.luau": "2857017d50846309af69865bccc41373b22345be8c79480a57828e43e67d93fb",
    F0201 + "acceptance/config.spec.luau": "7e56aa626a1ea77f22db189421e5a27db27f9c0957592662b9c3e0fdfa93d9cf",
    F0201 + "acceptance/paidplay.spec.luau": "aae86ec29db24ac1b0adb7ff4d08d176e6e6d305529cba97df7fc7400d6585e8",
    F0201 + "acceptance/place.spec.luau": "951e7168f9b7e434976f8263aad8fea1898393685456a70128fcb1b9d259e8ab",
    F0201 + "acceptance/receipts.spec.luau": "e531907a48ddb0ee9f87417a9a28bab9f80bfac0209626bf0bd4eb8dfc732e7c",
    F0201 + "acceptance/wallet.spec.luau": "eb9d28573e239789e79365ed8d3687b1e5df01ed1711aa2dcf30b75a6f67e443",
}
for rel, want in BASES.items():
    got = hashlib.sha256(open(os.path.join(PROTO, rel), "rb").read()).hexdigest()
    if got != want:
        sys.exit(f"refused: {rel} moved ({got}); rebuild the prototype and rerun")

TMP = tempfile.mkdtemp(prefix="f0395-mut-")
ROOT = os.path.join(TMP, "repo")
subprocess.run(["git", "clone", "-q", "--no-hardlinks", PROTO, ROOT], check=True)
HOME = os.path.join(ROOT, "arcade")
OWN = os.path.join(HOME, "tests/acceptance/f0395")
os.makedirs(OWN, exist_ok=True)
for name in sorted(os.listdir(SPECS)):
    if name.endswith(".spec.luau"):
        shutil.copyfile(os.path.join(SPECS, name), os.path.join(OWN, name))

PP = "arcade/src/shared/Logic/PaidPlay/init.luau"
PR = "arcade/src/shared/Prices.luau"
TP = "arcade/src/shared/TestPurchase.luau"
LINES = "tests/acceptance/f0395/lines.spec.luau"
CLIENT = "tests/acceptance/f0395/client.spec.luau"
DOCS = "tests/acceptance/f0395/docs.spec.luau"
AR = "arcade/.tracker/architecture.md"
OWN_SPECS = [LINES, CLIENT, DOCS]
F0201_SPECS = [f"tests/acceptance/f0201/{n}.spec.luau" for n in ("paidplay", "config", "wallet", "receipts", "client", "place")]

PLAY = "`<s>{plain(prices.struck)}</s> {plain(prices.price)} {plain(prices.sale)}`"
ESC = 'return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))'
TITLE = "plain(`{title}: {PaidPlay.KIND_TEXT[kind]}`),"

# id, file, old text, new text, spec, a substring of the case that must fail (D3 moves the sentence out of its bullet)
M = [
    ("Y1", PP, PLAY, "`{plain(prices.struck)} {plain(prices.price)} {plain(prices.sale)}`", LINES, "a play's price line strikes"),
    ("Y2", PP, PLAY, "`<s>{plain(prices.struck)} {plain(prices.price)} {plain(prices.sale)}</s>`", LINES, "a play's price line strikes"),
    ("Y3", PP, PLAY, '"<s>5 R$</s> 1 R$ SALE"', LINES, "built from the prices it is given"),
    ("Y4", PP, 'local price = if kind == "play"', "local price = if true", LINES, "a revive's price line is the revive's own"),
    ("Y5", PP, "else plain(prices.revive)", "else plain(prices.price)", LINES, "a revive's price line is the revive's own"),
    ("Y6", PP, "else plain(prices.revive)", "else `<s>{plain(prices.revive)}</s>`", LINES, "a revive's price line is the revive's own"),
    ("Y7", PP, ESC, "return text", LINES, "every text in a line shows as it is"),
    ("Y8", PP, ESC, 'return (string.gsub(string.gsub(string.gsub(text, "<", "&lt;"), ">", "&gt;"), "&", "&amp;"))', LINES, "every text in a line shows as it is"),
    ("Y9", PP, TITLE, "`{title}: {PaidPlay.KIND_TEXT[kind]}`,", LINES, "every text in a line shows as it is"),
    ("Y10", PP, PLAY, "`<s>{prices.struck}</s> {prices.price} {prices.sale}`", LINES, "every text in a line shows as it is"),
    ("Y11", PP, "else plain(prices.revive)", "else prices.revive", LINES, "every text in a line shows as it is"),
    ("Y12", PP, ESC, 'return (string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"))', LINES, "every text in a line shows as it is"),
    ("P1", PR, '\trevive = "1 R$", -- a revive\'s price (f0395): its own, nothing struck\n', "", LINES, "Prices is one frozen table"),
    ("P2", PR, 'revive = "1 R$",', 'revive = "1 R$ SALE",', LINES, "Prices is one frozen table"),
    ("P3", PR, "return table.freeze({", "return ({", LINES, "Prices is one frozen table"),
    ("C1", TP, "\t\t\tlabel.RichText = true -- the lines are rich text: a play's struck price (f0395)\n", "", CLIENT, "a play's lines"),
    ("C2", TP, "label.RichText = true", "label.RichText = i == 2", CLIENT, "a play's lines"),
    ("C3", TP, "label.Text = line", 'label.Text = (string.gsub(line, "<[^>]*>", ""))', CLIENT, "a play's lines"),
    ("C4", TP, "label.Text = line", 'label.Text = (string.gsub(line, "&", "&amp;"))', CLIENT, "a revive's lines and escaped text"),
    ("D1", AR, ' and a revive\'s price ("1 R$", nothing struck; f0395)', "", DOCS, "the Prices bullet names"),
    ("D2", AR, " Its lines are rich text: a play's price line strikes the badge's struck price (f0395).", "", DOCS, "the TestPurchase bullet says"),
    ("D3", AR, " Its lines are rich text: a play's price line strikes the badge's struck price (f0395).", "\n- Its lines are rich text: a play's price line strikes the badge's struck price (f0395).", DOCS, "the TestPurchase bullet says"),
]

# correct variants: right changes of the kind a later issue (or the executor) may make; all must stay green
V = [
    ("V1", PP, ESC, 'return (string.gsub(text, "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" }))'),
    ("V2", PP, "local price = if kind == \"play\"\n\t\tthen " + PLAY + "\n\t\telse plain(prices.revive)",
     "local price = if kind == \"revive\"\n\t\tthen plain(prices.revive)\n\t\telse " + PLAY),
    ("V3", TP, "\t\t\tlabel.RichText = true -- the lines are rich text: a play's struck price (f0395)\n\t\t\tlabel.Text = line\n",
     "\t\t\tlabel.Text = line\n\t\t\tlabel.RichText = true\n"),
    ("V4", PP, ESC, 'return (string.gsub(string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), \'"\', "&quot;"))'),
]

SUMMARY = re.compile(r"^(\d+) passed, (\d+) failed, (\d+) spec files?$")


def run(specs):
    p = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=900)
    out = p.stdout + p.stderr
    summary = None
    for line in out.splitlines():
        m = SUMMARY.match(line.strip())
        if m:
            summary = (int(m.group(1)), int(m.group(2)), int(m.group(3)))
    return out, summary


def green(specs):
    out, s = run(specs)
    return s is not None and s[1] == 0 and s[2] == len(specs) and "could not load" not in out, s


def apply(rel, old, new):
    path = os.path.join(ROOT, rel)
    text = open(path).read()
    if text.count(old) != 1:
        return None, text.count(old)
    open(path, "w").write(text.replace(old, new))
    return text, 1


only = set(sys.argv[2:])
try:
    if not only:
        ok, s = green(OWN_SPECS + F0201_SPECS)
        print(f"CONTROL f0395 and f0201 (narrowed) specs on the prototype: {'green' if ok else 'RED'} {s}", flush=True)
        # base: the three library files as f0201's prototype left them
        base = subprocess.run(["git", "-C", ROOT, "log", "--format=%H", "--grep", "^proto: f0395 change$"],
                              capture_output=True, text=True, check=True).stdout.split()
        assert len(base) == 1, base
        saved = {}
        for rel in (PP, PR, TP, AR):
            saved[rel] = open(os.path.join(ROOT, rel)).read()
            text = subprocess.run(["git", "-C", ROOT, "show", f"{base[0]}~1:{rel}"], capture_output=True, text=True,
                                  check=True).stdout
            open(os.path.join(ROOT, rel), "w").write(text)
        out, s = run(OWN_SPECS)
        fails = [l for l in out.splitlines() if l.startswith("FAIL ") and "::" in l]
        print(f"BASE f0395's specs on f0201 alone: {s}; failing cases: {len(fails)}; load errors: {'could not load' in out}", flush=True)
        for l in fails:
            print(f"  {l}", flush=True)
        ok, s = green(F0201_SPECS)
        print(f"BASE f0201's narrowed specs on f0201 alone: {'green' if ok else 'RED'} {s}", flush=True)
        for rel, text in saved.items():
            open(os.path.join(ROOT, rel), "w").write(text)
    for mid, rel, old, new, spec, case in M:
        if only and mid not in only:
            continue
        text, n = apply(rel, old, new)
        if text is None:
            print(f"{mid} NOT APPLIED: {n} matches in {rel}", flush=True)
            continue
        try:
            out, s = run([spec])
        finally:
            open(os.path.join(ROOT, rel), "w").write(text)
        lines = out.splitlines()
        verdict = "SURVIVED"
        if "could not load" in out:
            verdict = "NO RUN (load error)"
        else:
            for i, l in enumerate(lines):
                if l.startswith("FAIL ") and "::" in l and case in l:
                    nxt = lines[i + 1] if i + 1 < len(lines) else ""
                    verdict = "killed (assertion)" if "expected" in nxt else f"killed by an ERROR: {nxt.strip()}"
                    break
        print(f"{mid} {os.path.basename(spec)} :: {case}: {verdict}", flush=True)
    for vid, rel, old, new in V:
        if only and vid not in only:
            continue
        text, n = apply(rel, old, new)
        if text is None:
            print(f"{vid} NOT APPLIED: {n} matches in {rel}", flush=True)
            continue
        try:
            ok, s = green(OWN_SPECS + F0201_SPECS)
        finally:
            open(os.path.join(ROOT, rel), "w").write(text)
        print(f"{vid} correct variant: {'green' if ok else 'RED'} {s}", flush=True)
finally:
    shutil.rmtree(TMP)
