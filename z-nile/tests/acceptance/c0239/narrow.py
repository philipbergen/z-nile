# c0239 AC8: every Override changes only its named strings. For each of the six promoted specs, the file at the merge
# merge base (git merge-base origin/main HEAD), with the Override's substitutions applied, must equal the file on HEAD byte for byte; so deleting
# an assertion, adding one, or editing a comment is red. c0172's narrowed.spec changes by exactly one digest, the one of
# c0120/docs.spec.luau as it is on HEAD (the algorithm is rehash.py's). Usage: python3 narrow.py <checkout>.
import hashlib, pathlib, re, subprocess, sys
R = pathlib.Path(sys.argv[1])
A = "z-nile/tests/acceptance/"
MB = subprocess.run(["git", "-C", str(R), "merge-base", "origin/main", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()
def base(rel):
    return subprocess.run(["git", "-C", str(R), "show", f"{MB}:{rel}"], capture_output=True, text=True, check=True).stdout
def head(rel):
    return (R / rel).read_text()
RC0 = lambda tail: ("""'check "RC0: project gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --project %s --full'""" % tail,
                    """'check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project %s --affected'""" % tail)
SUBS = {
    "c0114/docs.spec.luau": [RC0("{{PROJECT}}")],
    "c0120/docs.spec.luau": [RC0("{{PROJECT}}")],
    "c0120/promote-home.spec.luau": [RC0("pickman")],
    # the rendered form of the template's RC0 line (design review 004 F1)
    "c0120/homes.spec.luau": [("""'"$ZN_ROOT/z-nile/check.sh" --project z-nile --full'""", """'"$ZN_ROOT/z-nile/check.sh" --project z-nile --affected'""")],
    "c0074/done-gate.spec.luau": [
        ("args: --full", "args: --affected"),
        ("full gate fails", "affected gate fails"),
        ("full gate is skipped", "gate is skipped"),
        (')).toBe("full")', ')).toBe("affected")'),  # all four doneGate lines (design review 003 F1)
    ],
}
def digest(rel):
    t = head(rel).replace("\r\n", "\n")
    t = re.sub(r"(?<![A-Za-z0-9_])[fdcR]\d+(?![A-Za-z0-9_])", "ID", t)
    return hashlib.sha256(t.encode()).hexdigest()
bad = []
COUNT = {
    ("c0074/done-gate.spec.luau", ')).toBe("full")'): 4,
    ("c0120/homes.spec.luau", """'"$ZN_ROOT/z-nile/check.sh" --project z-nile --full'"""): 1,
}
for f, subs in SUBS.items():
    want = base(A + f)
    for old, _ in subs:
        n = COUNT.get((f, old))
        if n is not None and want.count(old) != n:
            bad.append(f"{f}: expected {n} of {old!r}, found {want.count(old)}")
    for old, new in subs:
        if old not in want:
            bad.append(f"{f}: base has no {old!r}")
        want = want.replace(old, new)
    if head(A + f) != want:
        bad.append(f"{f}: differs from the base with its named substitutions applied")
n = base(A + "c0172/narrowed.spec.luau")
m = re.search(r'"z-nile",\s*"c0120",\s*"docs.spec.luau",\s*"([0-9a-f]{64})"', n)
if not m:
    bad.append("c0172/narrowed.spec.luau: no c0120 docs.spec digest row")
else:
    want = n[:m.start(1)] + digest(A + "c0120/docs.spec.luau") + n[m.end(1):]
    if head(A + "c0172/narrowed.spec.luau") != want:
        bad.append("c0172/narrowed.spec.luau: not the base with exactly the c0120 docs digest recomputed")
if bad:
    print("\n".join(bad)); sys.exit(1)
