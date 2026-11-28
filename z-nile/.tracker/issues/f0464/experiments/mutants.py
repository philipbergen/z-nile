#!/usr/bin/env python3
# f0464 prep mutation check (E6). Prep's, not the executor's. Run it only on a scratch worktree built from c0458's
# experiments/prototype.patch and this folder's prototype.patch (E6 says how), never on a raft worktree or a tree that
# will be committed: python3 mutants.py <scratch worktree> [M<n> ...], under ./zn run --time <s>.
# Each mutant replaces one text in one file, runs the row's acceptance spec from the issue's folder (backlog or
# active), prints KILLED (a case failed on it), SURVIVED, NOT APPLIED (the text is not in the file) or ERROR (the
# spec did not load, or the runner ended without its summary line), and restores the file, also on TERM and INT. It refuses to start when a file it mutates is
# not clean in git, checks they are clean again at the end, and exits 1 unless every chosen mutant was KILLED.
import os, re, signal, subprocess, sys

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
    ("M28", "a raise's freed members left in other words (z-raft groups them again)", "z-nile/skills/zz-review/SKILL.md",
     "its other members are readied again, each alone (`./zn ready <id>`)", "its other members go back to z-raft, which groups them again", "docs"),
    ("M29", "AGENTS.md keeps designs and rafts", "AGENTS.md", "the worker also designs and readies", "the worker also designs and rafts", "docs"),
    ("M30", "the walk's release words left as c0458 wrote them", W, "are readied again, each alone (./zn ready <id>).",
     "are rafted again (z-raft).", "docs"),
    ("M31", "zz-rules' raise route left as z-raft, ready", "z-nile/skills/zz-rules/SKILL.md",
     "z-design in full, then `./zn ready <id>`)", "z-design in full, z-raft, ready)", "docs"),
]
chosen = [m for m in MUTANTS if not ONLY or m[0] in ONLY]
files = sorted({m[2] for m in chosen})


def dirty():
    r = subprocess.run(["git", "-C", P, "status", "--porcelain", "--"] + files, capture_output=True, text=True)
    return r.stdout.strip()


if dirty():
    print("refused: these files are not clean in git, so a mutant could not be told from a change:\n" + dirty())
    sys.exit(2)
acc = next((f"{P}/z-nile/.tracker/issues/{d}f0464/acceptance" for d in ("", "active/")
            if os.path.isdir(f"{P}/z-nile/.tracker/issues/{d}f0464/acceptance")), None)
if acc is None:
    print("refused: no z-nile/.tracker/issues/[active/]f0464/acceptance in " + P)
    sys.exit(2)
current = {}


def restore(*_):
    for path, text in list(current.items()):
        open(path, "w").write(text)
    current.clear()
    if _:
        sys.exit(3)


signal.signal(signal.SIGTERM, restore)
signal.signal(signal.SIGINT, restore)
killed = 0
for mid, name, f, old, new, spec in chosen:
    path = f"{P}/{f}"
    text = open(path).read()
    if old not in text:
        print(mid, name, "NOT APPLIED", flush=True)
        continue
    current[path] = text
    open(path, "w").write(text.replace(old, new, 1))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", f"{acc}/{spec}.spec.luau"], cwd=f"{P}/z-nile",
                           capture_output=True, text=True)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if "FAIL" in l and "::" in l]
        # a run that ended without the runner's summary (`<n> passed, <m> failed, 1 spec files`) never ran the spec:
        # a refused start (a fence or identity check) or a load error is an ERROR, never a survivor
        loaded = "could not load spec" not in out and re.search(r"\d+ passed, \d+ failed, 1 spec files", out) is not None
        why = [l.strip() for l in out.splitlines() if "expected" in l or "rror" in l][:1]
        verdict = "KILLED" if fails and loaded else ("ERROR" if not loaded else "SURVIVED")
        killed += 1 if verdict == "KILLED" else 0
        print(mid, name, verdict, fails[:1], why, flush=True)
    finally:
        restore()
if dirty():
    print("not clean after the run:\n" + dirty())
    sys.exit(2)
print(f"{killed} of {len(chosen)} killed")
sys.exit(0 if killed == len(chosen) else 1)
