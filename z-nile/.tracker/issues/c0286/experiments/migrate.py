#!/usr/bin/env python3
# c0286 Implementation step 5, the migration (Behaviour 6). Usage, from the repository top of the tree to migrate:
#   ./zn run --time 60 -- python3 -I <this file> [--dry-run]
# For each family below: every member in the backlog with an empty `raft:` and a design that is not `ready` gets
# `tied: [<the family's other members, sorted, ", ">]` as the line after `id:`; if the family has no such member but
# some member is in the backlog with an empty `raft:`, the lowest such id gets it (one line connects the family: the
# ties are undirected). A member in a raft, active or done, or one that already carries the right line, is left alone.
# Nothing else in any document changes. Prints one line per document it writes (or would write).
import os, re, sys

FAMILIES = [
    ["c0247", "c0248", "c0250", "c0256", "c0260", "c0262"],
    ["c0249", "c0251", "c0252", "c0253", "c0254"],
]
DRY = "--dry-run" in sys.argv


def find(id_):
    for top in sorted(os.listdir(".")):
        base = os.path.join(top, ".tracker", "issues")
        for sub, state in (("", "backlog"), ("active", "active"), ("done", "done")):
            p = os.path.join(base, sub, id_, id_ + ".md")
            if os.path.isfile(p):
                return p, state
    sys.exit(f"{id_} is not in the tree")


def front(text):
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    out = {}
    for line in (m.group(1).split("\n") if m else []):
        k = re.match(r"^([\w]+):\s*(.*?)\s*$", line)
        if k:
            out[k.group(1)] = k.group(2)
    return out


for fam in FAMILIES:
    info = {}
    for id_ in fam:
        p, state = find(id_)
        text = open(p).read()
        f = front(text)
        info[id_] = (p, text, state == "backlog" and f.get("raft", "") == "", f.get("design", ""), f.get("tied"))
    writers = [i for i in sorted(fam) if info[i][2] and info[i][3] != "ready"]
    if not writers:
        raftless = [i for i in sorted(fam) if info[i][2]]
        writers = raftless[:1]
    for id_ in writers:
        p, text, _, _, tied = info[id_]
        want = "[" + ", ".join(sorted(x for x in fam if x != id_)) + "]"
        if tied == want:
            continue
        if tied is not None:
            sys.exit(f"{id_} already has tied: {tied}: fix it by hand")
        new, n = re.subn(rf"^(---\nid: {id_}\n)", rf"\1tied: {want}\n", text, count=1)
        if n != 1:
            sys.exit(f"{id_}: its front matter does not start with id: {id_}")
        print(f"{'would write' if DRY else 'wrote'} {p}: tied: {want}")
        if not DRY:
            open(p, "w").write(new)
