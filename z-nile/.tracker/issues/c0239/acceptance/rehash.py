# c0239: c0172's narrowed.spec pins c0120's docs.spec by SHA-256 (the text with item ids masked, CRLF made LF); the RC0
# Override changes that file, so the pinned digest is recomputed after stylua, as the last step (c0165's rehash.py is the
# model). Usage: python3 rehash.py <checkout>. It changes only that one digest.
import hashlib, pathlib, re, sys
R = pathlib.Path(sys.argv[1])
N = R / "z-nile/tests/acceptance/c0172/narrowed.spec.luau"; n = N.read_text()
def digest(rel):
    t = (R / rel).read_text().replace("\r\n", "\n")
    t = re.sub(r"(?<![A-Za-z0-9_])[fdcR]\d+(?![A-Za-z0-9_])", "ID", t)
    return hashlib.sha256(t.encode()).hexdigest()
for proj, item, f in [("z-nile", "c0120", "docs.spec.luau")]:
    m = re.search(r'"%s",\s*"%s",\s*"%s",\s*"([0-9a-f]{64})"' % (proj, item, re.escape(f)), n)
    assert m, (proj, item, f)
    new = digest(f"{proj}/tests/acceptance/{item}/{f}")
    n = n[:m.start(1)] + new + n[m.end(1):]
    print(item, f, m.group(1)[:8], "->", new[:8])
N.write_text(n)
