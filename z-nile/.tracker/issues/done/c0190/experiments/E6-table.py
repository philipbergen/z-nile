# c0190: check that the Design's ownership table (c0190.md) and capture.py's per-file records agree: every owner a row
# names owns parts of that row's design file, and every issue has a row for each file it owns parts of (design review
# 004 F3). Run from the repository's top: python3 -I <this file>
import pathlib, re
here = pathlib.Path(__file__).resolve().parent
src = (here / "capture.py").read_text()
ns = {}
exec(compile(src.split("if __name__")[0], "capture.py", "exec"), ns)
I = {e["key"]: e for e in ns["I"]}
F = {"Snake": "snake", "Invaders": "invaders", "Asteroids": "asteroids", "Portal": "portal", "Arcade": ns["ARCH"]}
t = (here.parent / "c0190.md").read_text()
seg = t[t.index("| design | part | owner |"):]
seg = seg[:seg.index("\n\n")]
bad, seen = [], {}
for line in seg.split("\n")[2:]:
    c = [x.strip() for x in line.strip("|").split("|")]
    d = F[c[0]]
    for k in re.findall(r"\b([AKPZSIT][1-5])\b", c[2]):
        if k in I:
            if d not in [I[k]["file"]] + I[k].get("also", []):
                bad.append(f"{c[0]} row '{c[1]}' names {k}, which owns nothing in {d}")
            seen.setdefault(k, set()).add(d)
for k, e in I.items():
    for f in [e["file"]] + e.get("also", []):
        if f not in seen.get(k, set()):
            bad.append(f"{k} owns parts of {f} but has no row for it")
print("\n".join(bad) if bad else "ok: the table agrees with capture.py")
raise SystemExit(1 if bad else 0)
