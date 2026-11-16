#!/usr/bin/env bash
# Prints the znile board model as JSON on stdout, for the znile.board plugin.
# Usage: fetch.sh <repo>
#
# Reads only through ./zn (the engine's own model). It uses `./zn board --json`
# once znile has it; until then it renders the board page into ~/.cache and
# lifts the JSON the page embeds. It adds `projects` (id -> project, from which
# tracker root holds the item's folder), `projectOrder`, `repo` and `fetchedAt`.
set -euo pipefail

repo=${1:?usage: fetch.sh <repo>}
cache=${XDG_CACHE_HOME:-$HOME/.cache}/znile-board
export PATH="$HOME/.rokit/bin:$PATH"

cd "$repo"
[[ -x ./zn ]] || { echo "fetch.sh: no ./zn in $repo" >&2; exit 2; }
command -v lune >/dev/null || { echo "fetch.sh: lune not found (run z-nile/setup.sh --tools)" >&2; exit 3; }
mkdir -p "$cache"

if grep -q 'board .*--json' z-nile/engine/main.luau 2>/dev/null; then
  ./zn board --json >"$cache/board.json"
  source=json
else
  ./zn board -O --out "$cache/board.html" >/dev/null
  source=html
fi
lune run z-nile/roots -- --projects >"$cache/projects.tsv"
export ZNILE_REMOTE=$(git remote get-url origin 2>/dev/null || true)

exec python3 -I - "$source" "$cache" "$repo" <<'PY'
import json, os, re, sys, datetime

source, cache, repo = sys.argv[1], sys.argv[2], sys.argv[3]
if source == "json":
    with open(os.path.join(cache, "board.json"), encoding="utf-8") as f:
        model = json.load(f)
else:
    with open(os.path.join(cache, "board.html"), encoding="utf-8") as f:
        page = f.read()
    m = re.search(r'<script type="application/json" id="board-data">(.*?)</script>', page, re.S)
    if not m:
        sys.exit("fetch.sh: board page has no board-data block")
    model = json.loads(m.group(1))

ID = re.compile(r"^[fdcR][0-9]{4}$")
projects, paths, order = {}, {}, []
with open(os.path.join(cache, "projects.tsv"), encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 3:
            continue
        name, _home, root = parts
        order.append(name)
        for kind in ("issues", "rafts"):
            base = os.path.join(repo, root, kind)
            for sub in ("", "active", "done"):
                d = os.path.join(base, sub)
                if not os.path.isdir(d):
                    continue
                for entry in os.listdir(d):
                    if ID.match(entry) and entry not in projects:
                        projects[entry] = name
                        doc = os.path.join(root, kind, sub, entry, entry + ".md")
                        paths[entry] = os.path.normpath(doc)

# Spend per item, from the spend.md beside each document: the totals line
# `./zn` writes for machines, and the rows' phase column for a breakdown.
TOTALS = re.compile(r"<!-- totals: (.*?) -->")
def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0
spend = {}
for entry, doc in paths.items():
    f = os.path.join(repo, os.path.dirname(doc), "spend.md")
    if not os.path.isfile(f):
        continue
    with open(f, encoding="utf-8") as fh:
        text = fh.read()
    m = TOTALS.search(text)
    if not m:
        continue
    kv = dict(p.split("=", 1) for p in m.group(1).split() if "=" in p)
    phases = {}
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        # issue rows: # | when | commit | +lines | -lines | minutes | attribution | phase | tokens
        if len(cells) == 9 and cells[0].isdigit():
            ph = phases.setdefault(cells[7] or "other", {"minutes": 0.0, "tokens": 0.0})
            ph["minutes"] += num(cells[5])
            ph["tokens"] += num(cells[8])
        # a raft's phase table: phase | +lines | -lines | minutes | tokens
        elif len(cells) == 5 and re.match(r"^[a-z][a-z-]*$", cells[0]) and cells[0] != "phase":
            ph = phases.setdefault(cells[0], {"minutes": 0.0, "tokens": 0.0})
            ph["minutes"] += num(cells[3])
            ph["tokens"] += num(cells[4])
    spend[entry] = {
        "minutes": num(kv.get("minutes")), "tokens": num(kv.get("tokens")),
        "added": num(kv.get("added")), "removed": num(kv.get("removed")),
        "phases": phases,
    }
model["spend"] = spend

model.pop("home", None)
model["projects"] = projects
model["projectOrder"] = order
model["paths"] = paths
# https://github.com/<owner>/<repo>/blob/main/ for the files' web pages
remote = os.environ.get("ZNILE_REMOTE", "")
m = re.match(r"^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([\w.-]+/[\w.-]+?)(?:\.git)?/?$", remote)
model["webBase"] = "https://github.com/" + m.group(1) + "/blob/main/" if m else ""
model["repo"] = repo
model["fetchedAt"] = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
json.dump(model, sys.stdout, separators=(",", ":"))
PY
