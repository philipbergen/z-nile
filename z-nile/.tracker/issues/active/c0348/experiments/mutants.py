#!/usr/bin/env python3
"""c0348 mutation check. Run from the top of a throwaway clone under $TMPDIR that holds the prototype
(experiments/prototype.patch and overrides.patch applied), through `./zn run --time 1200 -- python3 <this file>`: for each mutant, edit the engine, run the named spec, expect a failed
assertion in the named case, and put the engine back. Prints one line per mutant. Not run by any check."""
import os, subprocess, sys

# It rewrites engine files in place, so it runs only in a throwaway clone: the repository must lie under $TMPDIR.
_top = os.path.realpath(subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True).stdout.strip())
_tmp = os.path.realpath(os.environ.get("TMPDIR") or "/tmp")
if not _top.startswith(_tmp.rstrip("/") + "/") or os.path.realpath(os.getcwd()) != _top:
    sys.exit(f"mutants.py: run it from the top of a throwaway clone under $TMPDIR ({_tmp}), not {_top}")

MAIN = "z-nile/engine/main.luau"
PUB = "z-nile/engine/publish.luau"
NEW = ".tracker/issues/c0348/acceptance/deliver-publish.spec.luau"
if not os.path.isfile("z-nile/" + NEW):
    NEW = "tests/acceptance/c0348/deliver-publish.spec.luau"  # after ./zn done promoted it
GUARD = "tests/acceptance/c0081/publish-guard.spec.luau"
LAND = "tests/acceptance/d0333/commit-land.spec.luau"

MUTANTS = [
    ("M1 spend never publishes", MAIN, '\tif landed then\n\t\t-- published before the local commit', '\tif false then\n\t\t-- published before the local commit', LAND,
     "after done, ./zn spend --phase deliver puts its row on origin/main"),
    ("M1b spend never publishes", MAIN, '\tif landed then\n\t\t-- published before the local commit', '\tif false then\n\t\t-- published before the local commit', NEW,
     "a deliver row for a done issue is published as one commit"),
    ("M2 a deliver row publishes whatever the item's state", MAIN,
     '\t\t\tlanded = landed and stateOfPath(doc :: string) == "done"\n', '', NEW,
     "a deliver row for an item that is not done stays on the branch"),
    ("M3 every phase publishes for a done item", MAIN, 'local landed = phase == "deliver"', 'local landed = true', NEW,
     "the other phases never publish"),
    ("M4 a failed publish keeps the written files", MAIN,
     '\t\t\tcostrow.restore(planned)\n\t\t\tfail(\n\t\t\t\t`spend: could not publish',
     '\t\t\tfail(\n\t\t\t\t`spend: could not publish', NEW,
     "a deliver publish that fails records nothing"),
    ("M5 the publisher takes any content", PUB,
     '\tlocal had = existing or ""\n', '\tlocal had = existing or ""\n\tif true then\n\t\treturn nil\n\tend\n', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M6 no prefix rule", PUB, 'if string.sub(content, 1, #had) ~= had then', 'if false then', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M7 text that does not parse counts as no rows", PUB, '\tif not rows then\n\t\treturn `does not parse', '\tif not rows then\n\t\trows = {}\n\tend\n\tif false then\n\t\treturn `does not parse', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M8 no newline rule", PUB, 'if string.sub(content, -1) ~= "\\n" then', 'if false then', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M9 spend.d allowed in any state folder", PUB, '\t\t\tand path == `{root}/issues/done/{id}/{rel}`\n', '', NEW,
     "the publisher's path rule takes a spend.d file only for a done issue"),
    ("M10 no document beside the rows", PUB, '\t\t\t\tif not onOrigin[doc] then\n\t\t\t\t\treturn fail(`{c.path}: no {id}.md beside it in done/',
     '\t\t\t\tif false then\n\t\t\t\t\treturn fail(`{c.path}: no {id}.md beside it in done/', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M11 an unchanged file publishes", PUB, 'if #content == #had then', 'if false then', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M13 rows the branch has not landed are published with the deliver row", MAIN,
     '\t\t\t\tlanded = false\n\t\t\t\tunlanded = true\n', '', NEW,
     "rows this branch has not landed keep the deliver row on the branch too"),
    ("M14 a checkout behind origin records anyway", MAIN, 'if relation == "behind" then', 'if false then', NEW,
     "a checkout that lacks rows origin holds records nothing"),
    ("M15 an append with no deliver row publishes", PUB, '\treturn "no deliver row among the new rows"\n', '\treturn nil\n', NEW,
     "the publisher takes a done issue's spend.d file only as an append"),
    ("M16 a failed local commit leaves the index staged", MAIN, '\t\tlocal unstaged = sh.run("git", resetArgs)\n',
     '\t\tlocal unstaged = { ok = true }\n', NEW, "a local commit that fails after the publish warns"),
    ("M17 a failed local commit after the publish fails the command", MAIN, '\t\tif not publishedSha then\n\t\t\tfail(\n\t\t\t\t(\n\t\t\t\t\tif added.ok',
     '\t\tif true then\n\t\t\tfail(\n\t\t\t\t(\n\t\t\t\t\tif added.ok', NEW, "a local commit that fails after the publish warns"),
    ("M18 a failed publish rewrites the measure buffer", MAIN,
     '\t\t\tcostrow.restore(planned)\n\t\t\tfail(\n\t\t\t\t`spend: could not publish',
     '\t\t\tcostrow.writeBuffer(top, planned)\n\t\t\tcostrow.restore(planned)\n\t\t\tfail(\n\t\t\t\t`spend: could not publish', NEW,
     "a deliver publish that fails records nothing"),
    ("M12 no stale-tree check before the publish", MAIN,
     '\t\trefuseStale()\n\t\tlocal r = published(publish.commit(".", function(_paths, _read, _roots, _counter)\n\t\t\tlocal changes',
     '\t\tlocal r = published(publish.commit(".", function(_paths, _read, _roots, _counter)\n\t\t\tlocal changes', GUARD,
     "refuses a stale tree right before every publish.commit"),
]

only = sys.argv[1:]
bad = 0
for name, path, old, new, spec, case in MUTANTS:
    if only and name.split()[0] not in only:
        continue
    text = open(path).read()
    if text.count(old) != 1:
        print(f"{name}: CANNOT APPLY ({text.count(old)} matches)")
        bad += 1
        continue
    open(path, "w").write(text.replace(old, new, 1))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", spec], cwd="z-nile", capture_output=True, text=True)
    finally:
        open(path, "w").write(text)
    out = r.stdout + r.stderr
    failed = [l for l in out.splitlines() if l.startswith("FAIL ") and " :: " in l]
    hit = any(case in l for l in failed)
    wrong = "attempt to" in out or "syntax" in out.lower() or "Type" in out and "error" in out and not failed
    verdict = "killed" if (r.returncode != 0 and hit and not wrong) else "SURVIVED"
    if verdict != "killed":
        bad += 1
    print(f"{name}: {verdict} ({len(failed)} failed case(s): {'; '.join(l.split(' :: ', 1)[1][:70] for l in failed)})")
sys.exit(1 if bad else 0)
