#!/usr/bin/env python3
# f0464 prep mutation check (E6). Run on a prototype worktree (c0458's prototype patch plus f0464's change), never on
# the real checkout: python3 mutants.py <prototype worktree> [M<n> ...]. Each mutant replaces one text in one file,
# runs the row's acceptance spec from the prototype's issue folder, prints KILLED (a case failed) or SURVIVED with
# the first failing case and assertion, and restores the file. Start it under ./zn run --time <s>.
import subprocess, sys

P = sys.argv[1]
ONLY = sys.argv[2:]
LR, W, D, M, PUB, RC, WR = ("z-nile/engine/lightready.luau", "z-nile/engine/work.luau", "z-nile/engine/dispatch.luau",
    "z-nile/engine/main.luau", "z-nile/engine/publish.luau", "z-nile/engine/readycheck.luau", "z-nile/engine/workread.luau")
MUTANTS = [
    ("M1", "ready refuses what is not light", LR, "\tlocal o: Opts = opts or {}\n",
     "\tlocal o: Opts = opts or {}\n\tif rule then\n\t\treturn { why = rule, light = false, lightWhy = rule, reviewed = reviewed }\n\tend\n", "single"),
    ("M2", "every single raft light", LR, "return { why = refused, light = rule == nil,", "return { why = refused, light = true,", "single"),
    ("M3", "approval never required", LR, "requireApproval = o.dispatched,", "requireApproval = false,", "single"),
    ("M4", "onMembers ignored", LR, "onMembers = o.onMembers,", "onMembers = nil,", "single"),
    ("M5", "light judged with --on members met", LR, "\t\tdepsMet = not unmet,",
     "\t\tdepsMet = not unmet or (opts ~= nil and opts.onMembers ~= nil),", "single"),
    ("M6", "Lands: approved always", LR, "\tif not how.dispatched then\n", "\tif true then\n", "single"),
    ("M7", "Light: true always", LR, "\tif how.light then\n", "\tif true then\n", "single"),
    ("M8", "On: dropped", LR, "\tif how.on then\n", "\tif false then\n", "single"),
    ("M9", "non-light raftless still rafting", W, "\t\tif i.readyWhy == nil then\n",
     "\t\tif i.readyWhy == nil and i.light ~= true and i.sized then\n\t\t\taction = \"rafting\"\n\t\telseif i.readyWhy == nil then\n", "walk"),
    ("M10", "unsized still fix", W, "\t\tif i.readyWhy == nil then\n",
     "\t\tif i.readyWhy == nil and not i.sized then\n\t\t\taction = \"fix\"\n\t\telseif i.readyWhy == nil then\n", "walk"),
    ("M11", "readyWhy ignored", W, "\t\tif i.readyWhy == nil then\n", "\t\tif true then\n", "walk"),
    ("M12", "changed approval offered as fix", W,
     "\t\telseif string.find(i.readyWhy :: string, \"changed since approval\", 1, true) ~= nil then\n\t\t\treturn nil, `ready refuses it: {i.readyWhy :: string}`\n", "", "walk"),
    ("M13", "tier 2 ready without a base", W, "\t\t\tif not base then\n\t\t\t\treturn nil, why\n\t\t\tend\n", "", "walk"),
    ("M14", "why names no --on", W, "\t\tlocal base = if #unmet > 0 then work.baseForDeps(i.deps, rafts or {}, issues) else nil\n",
     "\t\tlocal base = nil\n", "walk"),
    ("M15", "dispatch keeps raft-plan", D, "\t\t\t\treturn { kind = \"step\", step = \"z-ready\", target = f.id }\n\t\t\tend\n\t\t\tif not",
     "\t\t\t\treturn { kind = \"step\", step = \"raft-plan\", target = f.id }\n\t\t\tend\n\t\t\tif not", "dispatch"),
    ("M16", "no stop after an empty z-ready", D,
     "\telseif done == \"z-ready\" and f.kind == \"issue\" and f.raft == \"\" then\n\t\treturn stop(dispatch.EXIT.failure, `z-ready ended but {f.id} has no raft on origin/main`)\n", "", "dispatch"),
    ("M17", "in-flight rafting dropped", D, "\t\t\tif f.localRaft == \"\" then\n", "\t\t\tif true then\n", "dispatch"),
    ("M18", "coherence review not required", RC, "\tif #members > 1 and not raftplan.reviewCovers(reviewFiles, map) then",
     "\tif false and not raftplan.reviewCovers(reviewFiles, map) then", "plan"),
    ("M19", "raft doc always light", M, "\t\t\tif isLight then\n\t\t\t\trdoc = withFront(rdoc, \"light\", \"true\")",
     "\t\t\tif true then\n\t\t\t\trdoc = withFront(rdoc, \"light\", \"true\")", "ready"),
    ("M20", "dispatched issue refused", M, "\t\t\tlightId = target.id\n",
     "\t\t\tif dispatched then\n\t\t\t\tfail(\"the light path (ready <issue>) takes no --on and is not for ./zn dispatch\")\n\t\t\tend\n\t\t\tlightId = target.id\n", "ready"),
    ("M21", "readyWhy only for easy", WR, "if status == \"prepared\" and front.design == \"ready\" then",
     "if status == \"prepared\" and front.design == \"ready\" and front.risk == \"easy\" then", "ready"),
    ("M22", "raft-plan still prints a fold", M, "\t\t\ttable.insert(skips, {\n\t\t\t\tid = i.id,",
     "\t\t\tprint(`./zn fold R0030 {i.id}`)\n\t\t\ttable.insert(skips, {\n\t\t\t\tid = i.id,", "plan"),
    ("M23", "skill keeps the old Next step", "z-nile/skills/z-design/SKILL.md", "- **Next step**: `./zn ready <issue-id>` from the main checkout",
     "- **Next step**: `/z-raft` (it groups prepared issues), then `/z-ready <R-id>`. Old: `./zn ready <issue-id>` from the main checkout", "docs"),
    ("M24", "--on members from the raft's issues: list (no readyOnMembers)", M,
     "\t\t\tonMembersOf = f0399.readyOnMembers(issue, { issue }, onId)\n",
     "\t\t\tonMembersOf = store.idList(store.readFront(store.get(onId).doc).issues)\n", "ready"),
    ("M25", "no raft: line check", LR, "\tif not light.hasRaftLine(text) then\n", "\tif false then\n", "single"),
    ("M26", "the guard's light: test deleted", PUB, "\tif rf.light ~= nil and rf.light ~= \"true\" then\n", "\tif false then\n", "guard"),
    ("M27", "zz-rules keeps z-raft makes every raft", "z-nile/skills/zz-rules/SKILL.md",
     "z-design stops at a prepared issue with no raft, and", "z-design stops at a prepared issue with no raft (z-raft makes every raft), and", "docs"),
]
for mid, name, f, old, new, spec in MUTANTS:
    if ONLY and mid not in ONLY:
        continue
    path = f"{P}/{f}"
    text = open(path).read()
    if old not in text:
        print(mid, name, "NOT APPLIED", flush=True)
        continue
    open(path, "w").write(text.replace(old, new, 1))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", f"{P}/z-nile/.tracker/issues/f0464/acceptance/{spec}.spec.luau"],
                           cwd=f"{P}/z-nile", capture_output=True, text=True)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if "FAIL" in l and "::" in l]
        why = [l.strip() for l in out.splitlines() if "expected" in l or "rror" in l][:1]
        print(mid, name, "KILLED" if fails else "SURVIVED", fails[:1], why, flush=True)
    finally:
        open(path, "w").write(text)
