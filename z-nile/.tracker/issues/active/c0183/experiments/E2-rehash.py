# c0183 prototype step 2 (after stylua): c0172's narrowed.spec digests for the four overridden specs
import hashlib, pathlib, re, sys
R = pathlib.Path(sys.argv[1])
N = R / "z-nile/tests/acceptance/c0172/narrowed.spec.luau"; n = N.read_text()
def digest(rel):
    t = (R / rel).read_text().replace("\r\n", "\n")
    t = re.sub(r"(?<![A-Za-z0-9_])[fdcR]\d+(?![A-Za-z0-9_])", "ID", t)
    return hashlib.sha256(t.encode()).hexdigest()
rows = [("z-nile", "c0114", "gate-cover.spec.luau"), ("z-nile", "c0120", "ci.spec.luau"),
        ("z-nile", "c0120", "docs.spec.luau"), ("pickman", "c0015", "workflow.spec.luau")]
for proj, item, f in rows:
    m = re.search(r'"%s",\s*"%s",\s*"%s",\s*"([0-9a-f]{64})"' % (proj, item, re.escape(f)), n)
    assert m, (proj, item, f)
    new = digest(f"{proj}/tests/acceptance/{item}/{f}")
    n = n[:m.start(1)] + new + n[m.end(1):]
    print(item, f, m.group(1)[:8], "->", new[:8])
N.write_text(n)
