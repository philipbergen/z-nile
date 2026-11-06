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
