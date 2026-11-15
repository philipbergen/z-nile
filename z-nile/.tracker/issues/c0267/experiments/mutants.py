#!/usr/bin/env python3
# c0267 prep's mutation check: applies each mutant alone to a copy of the prototype (argv[1], a scratch worktree),
# runs the row's spec outside a dispatched step's variables (nostep.sh), and records whether it failed on an assertion. Restores the file after each mutant.
import subprocess, sys, pathlib
root = pathlib.Path(sys.argv[1])
NOSTEP = pathlib.Path(__file__).resolve().parent / "nostep.sh"
A = ".tracker/issues/c0267/acceptance/"
MUTANTS = [
  ("M1 no approval stop", "z-nile/engine/dispatch.luau", "if f.unapproved and #f.unapproved > 0 then", "if false then", "chain"),
  ("M2 a failure, not a wait", "z-nile/engine/dispatch.luau", "code = dispatch.EXIT.user,\n\t\t\t\t\twhy = dispatch.waitingWhy", "code = dispatch.EXIT.failure,\n\t\t\t\t\twhy = dispatch.waitingWhy", "chain"),
  ("M3 names only the first issue", "z-nile/engine/dispatch.luau", "for _, u in unapproved do\n\t\tlocal what", "for _, u in { unapproved[1] } do\n\t\tlocal what", "chain"),
  ("M4 nil list stops", "z-nile/engine/dispatch.luau", "if f.unapproved and #f.unapproved > 0 then", "if not f.unapproved then\n\t\t\t\treturn stop(dispatch.EXIT.user, \"waiting for the person\")\n\t\t\tend\n\t\t\tif f.unapproved and #f.unapproved > 0 then", "chain"),
  ("M5 unreadable ignored", "z-nile/engine/dispatch.luau", "if f.unreadable then", "if false then", "chain"),
  ("M6 waits before rafting", "z-nile/engine/dispatch.luau", "\tif f.kind == \"issue\" then\n\t\tif f.where == \"done\" then", "\tif f.kind == \"issue\" and f.unapproved and #f.unapproved > 0 then\n\t\treturn stop(dispatch.EXIT.user, \"waiting\")\n\tend\n\tif f.kind == \"issue\" then\n\t\tif f.where == \"done\" then", "chain"),
  ("M7 an active raft waits too", "z-nile/engine/dispatch.luau", "\t-- a raft\n\tif f.where == \"done\" then", "\t-- a raft\n\tif f.unapproved and #f.unapproved > 0 and f.where == \"active\" then\n\t\treturn stop(dispatch.EXIT.user, dispatch.waitingWhy(f.id, f.unapproved))\n\tend\n\tif f.where == \"done\" then", "chain"),
  ("M8 the wait before questions", "z-nile/engine/dispatch.luau", "function dispatch.next(f: Facts): Action\n", "function dispatch.next(f: Facts): Action\n\tif f.unapproved and #f.unapproved > 0 then\n\t\treturn { kind = \"stop\", code = 3, why = dispatch.waitingWhy(f.id, f.unapproved), waiting = \"approval\" }\n\tend\n", "chain"),
  ("M9 an unreadable approval holds", "z-nile/engine/readycheck.luau", "if state ~= \"holds\" then", "if state ~= \"holds\" and state ~= \"bad\" then", "waiting"),
  ("M10 no layer order", "z-nile/engine/readycheck.luau", "local ra, rb = rank[a.id] or math.huge, rank[b.id] or math.huge", "local ra, rb = 0, 0", "waiting"),
  ("M11 other refusals ignored", "z-nile/engine/readycheck.luau", "if other or not complete then\n\t\treturn nil\n\tend", "if not complete then\n\t\treturn nil\n\tend", "waiting"),
  ("M12 the record ignored", "z-nile/engine/readycheck.luau", "if readycheck.record(r.id, r.grouped, r.members, r.files) then\n\t\treturn nil\n\tend", "", "waiting"),
  ("M13 reasonOf's words drift", "z-nile/engine/approval.luau", "This is a one-time step for an item prepared before approval.", "This is a step.", "waiting"),
  ("M14 facts never read approvals", "z-nile/engine/dispatcher.luau", "unapproved, unreadable = ctx.approvals(id)\n\t\tif not unapproved and not unreadable then\n\t\t\tunreadable = \"no answer\"\n\t\tend", "unapproved = {}", "wiring"),
  ("M15 other refusals ignored, end to end", "z-nile/engine/readycheck.luau", "if other or not complete then\n\t\treturn nil\n\tend", "if not complete then\n\t\treturn nil\n\tend", "wiring"),
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
