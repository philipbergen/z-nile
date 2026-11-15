#!/usr/bin/env python3
# c0267 prep's mutation check: applies each mutant alone to a copy of the prototype (argv[1], a scratch worktree),
# runs the row's spec outside a dispatched step's variables (nostep.sh), and records whether it failed on an assertion. Restores the file after each mutant.
import subprocess, sys, pathlib
root = pathlib.Path(sys.argv[1])
NOSTEP = pathlib.Path(__file__).resolve().parent / "nostep.sh"
A = ".tracker/issues/c0267/acceptance/"
MUTANTS = [
  ("M1 no approval stop", "z-nile/engine/dispatch.luau", "if f.unapproved and #f.unapproved > 0 then", "if false then", "chain"),
  ("M2 a failure, not a wait", "z-nile/engine/dispatch.luau", "return stop(dispatch.EXIT.user, dispatch.waitingWhy(f.id, f.unapproved))", "return stop(dispatch.EXIT.failure, dispatch.waitingWhy(f.id, f.unapproved))", "chain"),
  ("M3 names only the first issue", "z-nile/engine/dispatch.luau", "for _, u in unapproved do\n\t\tlocal what", "for _, u in { unapproved[1] } do\n\t\tlocal what", "chain"),
  ("M4 nil list stops", "z-nile/engine/dispatch.luau", "if f.unapproved and #f.unapproved > 0 then", "if not f.unapproved then\n\t\t\t\treturn stop(dispatch.EXIT.user, \"waiting for the person\")\n\t\t\tend\n\t\t\tif f.unapproved and #f.unapproved > 0 then", "chain"),
  ("M5 unreadable ignored", "z-nile/engine/dispatch.luau", "if f.unreadable then", "if false then", "chain"),
  ("M6 waits before rafting", "z-nile/engine/dispatch.luau", "\tif f.kind == \"issue\" then\n\t\tif f.where == \"done\" then", "\tif f.kind == \"issue\" and f.unapproved and #f.unapproved > 0 then\n\t\treturn stop(dispatch.EXIT.user, \"waiting\")\n\tend\n\tif f.kind == \"issue\" then\n\t\tif f.where == \"done\" then", "chain"),
  ("M7 an active raft waits too", "z-nile/engine/dispatch.luau", "\t-- a raft\n\tif f.where == \"done\" then", "\t-- a raft\n\tif f.unapproved and #f.unapproved > 0 and f.where == \"active\" then\n\t\treturn stop(dispatch.EXIT.user, dispatch.waitingWhy(f.id, f.unapproved))\n\tend\n\tif f.where == \"done\" then", "chain"),
  ("M8 the wait before questions", "z-nile/engine/dispatch.luau", "function dispatch.next(f: Facts): Action\n", "function dispatch.next(f: Facts): Action\n\tif f.unapproved and #f.unapproved > 0 then\n\t\treturn stop(3, dispatch.waitingWhy(f.id, f.unapproved))\n\tend\n", "chain"),
  ("M9 an unreadable approval holds", "z-nile/engine/readycheck.luau", "if state ~= \"holds\" then", "if state ~= \"holds\" and state ~= \"bad\" then", "waiting"),
  ("M10 no layer order", "z-nile/engine/readycheck.luau", "local ra, rb = rank[a.id] or math.huge, rank[b.id] or math.huge", "local ra, rb = 0, 0", "waiting"),
  ("M11 other refusals ignored", "z-nile/engine/readycheck.luau", "if other or not complete then\n\t\treturn nil\n\tend", "if not complete then\n\t\treturn nil\n\tend", "waiting"),
  ("M12 the record ignored", "z-nile/engine/readycheck.luau", "if readycheck.record(r.id, r.grouped, r.members, r.files) then\n\t\treturn nil\n\tend", "", "waiting"),
  ("M13 the one-time step stays", "z-nile/engine/approval.luau", "in a terminal of your own, in a worktree on origin/main (not the main checkout).`", "from the worktree that holds the design. This is a one-time step for an item prepared before approval.`", "waiting"),
  ("M14 facts never read approvals", "z-nile/engine/dispatcher.luau", "local ok, list, why = pcall(ctx.approvals, id)", "local ok, list, why = true, {}, nil", "wiring"),
  ("M15 other refusals ignored, end to end", "z-nile/engine/readycheck.luau", "if other or not complete then\n\t\treturn nil\n\tend", "if not complete then\n\t\treturn nil\n\tend", "wiring"),
  ("M16 an unreadable approval's line keeps the file", "z-nile/engine/dispatch.luau", "local drop = if u.state == \"bad\"", "local drop = if false", "chain"),
  ("M16w an unreadable approval's line keeps the file, end to end", "z-nile/engine/dispatch.luau", "local drop = if u.state == \"bad\"", "local drop = if false", "wiring"),
  ("M17 all commands on one line", "z-nile/engine/dispatch.luau", "\tfor _, u in unapproved do\n\t\ttable.insert(lines, dispatch.approveLine(u))\n\tend", "\tlocal all: { string } = {}\n\tfor _, u in unapproved do\n\t\ttable.insert(all, dispatch.approveLine(u))\n\tend\n\ttable.insert(lines, table.concat(all, \"; \") .. \".\")", "chain"),
  ("M18 no cleanup", "z-nile/engine/dispatch.luau", " && git worktree remove \"$w\" && git branch -D \"$\\{w##*/}\"`", "`", "wiring"),
  ("M19 a reader error is an empty list", "z-nile/engine/dispatcher.luau", "\tif not ok then\n\t\treturn nil, tostring(list)\n\tend\n\tif not list and not why then", "\tif not ok then\n\t\treturn {}, nil\n\tend\n\tif not list and not why then", "actsite"),
  ("M20 no answer is an empty list", "z-nile/engine/dispatcher.luau", "\tif not list and not why then\n\t\treturn nil, \"no answer\"\n\tend", "\tif not list and not why then\n\t\treturn {}, nil\n\tend", "actsite"),
  ("M21 read for every item", "z-nile/engine/dispatcher.luau", "if not (kind == \"raft\" and where == \"backlog\" and status == \"prepared\") then", "if false then", "actsite"),
  ("M22 a failed collect is an empty list", "z-nile/engine/workread.luau", "\tif not ok then\n\t\treturn nil, tostring(input)\n\tend", "\tif not ok then\n\t\treturn {}, nil\n\tend", "actsite"),
  ("M23 a missing raft is an empty list", "z-nile/engine/workread.luau", "return nil, `{id} is not a raft on origin/main`", "return {}, nil", "actsite"),
  ("M24 the reader passes no layer order", "z-nile/engine/workread.luau", "blockFor(id, at, text, byId, docs, under, promoted, fact.issues)", "blockFor(id, at, text, byId, docs, under, promoted, {})", "wiring"),
]
only = sys.argv[2:] 
for name, path, old, new, spec in MUTANTS:
    if only and name.split()[0] not in only:
        continue
    f = root / path
    text = f.read_text()
    if old not in text:
        print(f"{name}: NOT APPLIED (pattern missing)"); continue
    f.write_text(text.replace(old, new, 1))
    try:
        cmd = ["bash", "-c", f"cd z-nile && bash {NOSTEP} lune run tests/run -- {A}{spec}.spec.luau"]
        r = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=900)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if l.startswith("FAIL ") and "::" in l]
        asserted = "expected" in out or "does not say" in out
        print(f"{name}: {'killed' if fails else 'SURVIVED'} ({len(fails)} failing cases{', assertion' if asserted else ''})")
        for l in fails[:3]:
            print("   ", l)
    finally:
        f.write_text(text)
