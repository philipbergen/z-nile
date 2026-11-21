#!/usr/bin/env python3
"""c0248 r2 and r3 mutation check. Usage: mutate.py <worktree> <names...>. Each mutant is one exact text replacement in one
engine file; its spec runs from z-nile/ with `lune run tests/run`; the mutant is killed when the spec fails on an
assertion (an `expected` line or a spec's own error naming the case), never on a syntax or require error. The file is
restored with `git checkout` after each run."""
import subprocess, sys

ROOT = sys.argv[1]
A = ".tracker/issues/c0248/acceptance"
M = {
    "work-reviewReason": ("z-nile/engine/work.luau", 'if layer.reviewReason ~= nil and layer.reviewReason ~= "" then', "if false then", f"{A}/work.spec.luau"),
    "work-landed": ("z-nile/engine/work.luau", "if layer and layer.landed then", "if false then", f"{A}/work.spec.luau"),
    "work-marked": ("z-nile/engine/work.luau", 'if not r.marked and r.codeReview == "none" then', 'if r.codeReview == "none" then', f"{A}/work.spec.luau"),
    "work-traceName": ("z-nile/engine/work.luau", 'commit that skeleton as {r.traceName or "trace.md"} in', "commit that skeleton as trace.md in", f"{A}/work.spec.luau"),
    "work-all-marked": ("z-nile/engine/work.luau", 'if not r.marked and r.codeReview == "none" then', "if false then", f"{A}/work.spec.luau"),
    "current-true": ("z-nile/engine/completion.luau", "function completion.current(review: string, refute: string?, finishSha: string, patchId: string): boolean\n", "function completion.current(review: string, refute: string?, finishSha: string, patchId: string): boolean\n\tdo return true end\n", f"{A}/completion.spec.luau"),
    "filing-onMain": ("z-nile/engine/dispatch.luau", "\tif p.onMain then\n", "\tif false then\n", f"{A}/dispatch-review.spec.luau"),
    # r3: aboveLandingBase (the layer above a landing) and layerOneBase in baseOf (layer 1)
    "fork-mainTip": ("z-nile/engine/layergit.luau", "\tlocal base = (layergit.layerOneBase(raftId, tip))\n\tlocal main = layergit.mainTip()\n", "\tdo\n\t\treturn layergit.mainTip()\n\tend\n\tlocal base = (layergit.layerOneBase(raftId, tip))\n\tlocal main = layergit.mainTip()\n", f"{A}/layers-land.spec.luau"),
    "baseof-layer1-mainfork": ("z-nile/engine/layergit.luau", "\tif position == 1 then\n\t\treturn (layergit.layerOneBase(raftId, tip))\n", "\tif position == 1 then\n\t\tlocal bt, bp = layergit.raftBase(raftId)\n\t\tif bp ~= \"main\" then\n\t\t\treturn bt\n\t\tend\n\t\treturn layergit.mainFork(tip)\n", "tests/acceptance/d0331/on-landed.spec.luau"),
    "above-landing-fork-only": ("z-nile/engine/layergit.luau", "\tif upstream and not sh.run(\"git\", { \"merge-base\", \"--is-ancestor\", upstream, main }).ok then\n", "\tif false then\n", f"{A}/layers-land.spec.luau"),
    "above-landing-needs-landed-tip": ("z-nile/engine/layergit.luau", "\tif upstream and not sh.run(\"git\", { \"merge-base\", \"--is-ancestor\", upstream, main }).ok then\n", "\tlocal binds = sh.run(\"git\", { \"log\", \"-1\", \"--first-parent\", \"--format=%P\", \"--fixed-strings\", `--grep={raftId}: bind `, main })\n\tlocal landedTip = string.match(sh.trim(binds.stdout), \"^%S+%s+(%S+)\")\n\tif not landedTip or not sh.run(\"git\", { \"merge-base\", \"--is-ancestor\", landedTip, tip }).ok then\n", f"{A}/layers-land.spec.luau"),
    "above-landing-finished-only": ("z-nile/engine/layergit.luau", "\tlocal upstream = stack.rebaseUpstream(issueId, raftId, \"\", \"\", true, rows)\n", "\tlocal last = rows[#rows]\n\tlocal upstream = if last and string.sub(last.subject, 1, #issueId + 2) == `{issueId}: ` then last.parent else nil\n", f"{A}/layers-land.spec.luau"),
    "ready-on-partly-landed": ("z-nile/engine/main.luau", "\tif #landedIds > 0 then\n", "\tif false then\n", f"{A}/layers-land.spec.luau"),
    "done-no-spend": ("z-nile/engine/main.luau", "if not merged.ok and not H.takeDerivedSpend() then", "if not merged.ok then", f"{A}/layers-land.spec.luau"),
    "restack-no-spend": ("z-nile/engine/main.luau", "while not rebasing.ok and H.takeDerivedSpend() do", "while false do", f"{A}/layers-land.spec.luau"),
    "ready-lists-landed": ("z-nile/engine/readyfacts.luau", "listed = unlanded(store.idList(front.issues)),", "listed = store.idList(front.issues),", f"{A}/layers-land.spec.luau"),
    "approvals-all": ("z-nile/engine/main.luau", "local gap = if bindSet[m.id] then f0399.approvalGap(m) else nil", "local gap = f0399.approvalGap(m)", f"{A}/layers-land.spec.luau"),
    "landed-local": ("z-nile/engine/layergit.luau", "\tlocal here = store.find(issueId)\n\tif not here then\n\t\treturn false\n\tend\n", "\tlocal here = store.find(issueId)\n\tif here and here.state == \"done\" then\n\t\treturn true\n\tend\n\tif not here then\n\t\treturn false\n\tend\n", f"{A}/layers-land.spec.luau"),
    "inputs-ignored": ("z-nile/engine/layergit.luau", "\t\tif string.match(p.name, \"^review%-\") then\n", "\t\tif false then\n", f"{A}/layers-land.spec.luau"),
    "filing-ignores-current": ("z-nile/engine/dispatch.luau", "\tif last >= 1 and p.current == false then\n", "\tif false then\n", f"{A}/dispatch-review.spec.luau"),
    "filing-always-next": ("z-nile/engine/dispatch.luau", "\tif last >= 1 and p.current == false then\n", "\tif last >= 1 and p.current ~= nil then\n", f"{A}/dispatch-review.spec.luau"),
    "inputs-no-patch": ("z-nile/engine/layergit.luau", "named = full ~= nil and layergit.patchId(full :: string) == patch", "named = false", f"{A}/layers-land.spec.luau"),
    "filing-ignores-unanswered": ("z-nile/engine/dispatch.luau", "\tif last >= 1 and p.current == false and p.unanswered then\n", "\tif false then\n", f"{A}/dispatch-review.spec.luau"),
    "handstamp-kept": ("z-nile/engine/layergit.luau", "\t\t\t(c ~= nil or pid ~= nil)\n", "\t\t\tfalse\n", f"{A}/layers-land.spec.luau"),
    "own-stamp-refused": ("z-nile/engine/layergit.luau", "\t\t\tand (c ~= string.lower(sha :: string) or pid ~= string.lower(patch :: string))\n", "\t\t\tand true\n", f"{A}/layers-land.spec.luau"),
    "committed-stamp-changed": ("z-nile/engine/layergit.luau", "if c0 ~= c1 or p0 ~= p1 then", "if false then", f"{A}/layers-land.spec.luau"),
    "dispatcher-no-backlog": ("z-nile/engine/dispatcher.luau", "return item ~= nil and item.kind == \"issue\" and item.state == \"backlog\"", "return false", f"{A}/dispatch-review.spec.luau"),
    "dispatcher-no-unanswered": ("z-nile/engine/dispatcher.luau", "unanswered = unanswered,", "unanswered = nil,", f"{A}/dispatch-review.spec.luau"),
    "round-deleted": ("z-nile/engine/layergit.luau", "if not fs.isFile(path) then", "if false then", f"{A}/layers-land.spec.luau"),
    "own-stamp-needs-inputs": ("z-nile/engine/layergit.luau", "and not ownStamp then", "then", f"{A}/dispatch-review.spec.luau"),
    "untrue-stamp-kept": ("z-nile/engine/layergit.luau", "if not full or not pid or layergit.patchId(full :: string) ~= pid then", "if false then", f"{A}/layers-land.spec.luau"),
    "restore-refused": ("z-nile/engine/layergit.luau", "if removed.ok and removed.stdout == text then", "if false then", f"{A}/layers-land.spec.luau"),
    "fresh-readd-accepted": ("z-nile/engine/layergit.luau", "if not before.ok and deletedBy ~= \"\" then", "if false then", f"{A}/layers-land.spec.luau"),
    "stale-stamp-refused": ("z-nile/engine/layergit.luau", "if not full or not pid or layergit.patchId(full :: string) ~= pid then", "if not full or not pid or layergit.patchId(full :: string) ~= pid or pid ~= patch then", f"{A}/dispatch-review.spec.luau"),
    "rename-old-path-dropped": ("z-nile/engine/layergit.luau", "\t\t\ttable.insert(paths, from)\n", "", f"{A}/layers-land.spec.luau"),
}
for name in sys.argv[2:]:
    path, old, new, spec = M[name]
    p = f"{ROOT}/{path}"
    s = open(p).read()
    assert s.count(old) == 1, (name, s.count(old))
    open(p, "w").write(s.replace(old, new))
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", spec], cwd=f"{ROOT}/z-nile", capture_output=True, text=True)
    finally:
        # a stopped run must not leave its mutant in the prototype (it did once: a later `git add -A` committed it)
        open(p, "w").write(s)
    out = r.stdout + r.stderr
    fails = [l.strip() for l in out.splitlines() if l.strip().startswith("FAIL ") and "::" in l]
    details = [l.strip() for l in out.splitlines() if ".spec:" in l]
    print(f"== {name}: exit {r.returncode}, {'KILLED' if r.returncode != 0 and fails else 'SURVIVED'}")
    for f in fails[:4]:
        print("   ", f[:220])
    for d in details[:4]:
        print("     ", d[-220:])
    sys.stdout.flush()
