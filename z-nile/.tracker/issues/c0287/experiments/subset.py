#!/usr/bin/env python3
# c0287: write a reduced copy of a spec file holding its first case (the fixture's setup) and the cases whose title
# contains one of the given words, so a mutant runs only the cases its row names.
#   python3 -I subset.py <spec> <out> <title words>...
import re
import sys

src, out, words = sys.argv[1], sys.argv[2], sys.argv[3:]
lines = open(src).read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("return t.spec("))
head, body = lines[: start + 1], lines[start + 1 :]
# the closing `end)` of t.spec is the last non-empty line
last = max(i for i, l in enumerate(body) if l.strip())
tail, body = body[last:], body[:last]
blocks, cur = [], []
for l in body:
    if re.match(r"^\t(it\(|-- )", l) and cur and not all(re.match(r"^\t-- ", c) or not c.strip() for c in cur):
        blocks.append(cur)
        cur = []
    cur.append(l)
if cur:
    blocks.append(cur)
keep = [blocks[0]] + [b for b in blocks[1:] if any(w in "\n".join(b) for w in words)]
if len(keep) - 1 < len(words):
    sys.exit(f"subset.py: {len(keep) - 1} cases matched {len(words)} words")
open(out, "w").write("\n".join(head + [l for b in keep for l in b] + tail) + "\n")
print(f"{out}: {len(keep)} cases")
