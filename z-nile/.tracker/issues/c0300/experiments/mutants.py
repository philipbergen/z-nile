#!/usr/bin/env python3
# c0300 mutation check: applies each mutant to the prototype worktree (argv[1]), runs the named cases, restores.
# Run from the prep worktree's z-nile/ through ./zn run, with experiments/plainenv.sh as argv[2] (no dispatcher wrapper on PATH).
import subprocess, sys, pathlib
proto = pathlib.Path(sys.argv[1]); plain = sys.argv[2]
A = ".tracker/issues/c0300/acceptance/"
L = "z-nile/engine/layercommits.luau"; MN = "z-nile/engine/main.luau"
M = [
 ("M1 upstream from the last <issue>: commit (the tip shortcut)", "z-nile/engine/stack.luau",
  "	for _, row in rows do\n		if string.sub(row.subject, 1, #finishPrefix) == finishPrefix then\n			return row.parent",
  "	for i = #rows, 1, -1 do\n		local row = rows[i]\n		if string.sub(row.subject, 1, #finishPrefix) == finishPrefix then\n			return row.parent", "restack-keeps"),
 ("M2 no keepsCommits verification", MN,
  "local lost = layercommits.keepsCommits(held, commitsOf(`{onto}..{rebuilt}`))",
  "local lost = nil and layercommits.keepsCommits(held, commitsOf(`{onto}..{rebuilt}`))", "restack-keeps"),
 ("M3 origin's copy always wins", L, "	if c.remoteSha == nil or c.remoteInLocal then", "	if c.remoteSha == nil then", "restack-keeps"),
 ("M4 diverged copies: local wins", L,
  '	return nil, "the local branch and its origin copy have diverged"', "	return c.localSha, nil", "restack-keeps"),
 ("M5 push before the check", MN,
  "		local issue = store.find(layer.issue)\n		if not issue or not runCheck(issue) then",
  "		sh.git({ \"push\", \"--quiet\", \"--force\", \"origin\", layer.name })\n		local issue = store.find(layer.issue)\n		if not issue or not runCheck(issue) then", "restack-keeps"),
 ("M6 rebase on the branch, a refusal leaves it moved", MN,
  '		sh.git({ "switch", "--quiet", "--detach", tip })\n		local rebasing',
  '		layergit.checkoutLayer(layer)\n		sh.git({ "reset", "--hard", tip })\n		local rebasing', "restack-keeps"),
 ("M7 hunk headers kept", L, '				table.insert(into, "@@")', "				table.insert(into, line)", "layercommits"),
 ("M8 spend.md not left out", L, "			current = if string.sub(line, -#spend) == spend then nil else {}", "			current = {}", "layercommits"),
 ("M9 index lines kept", L,
  '				or not (startsWith(line, "index ") or startsWith(line, "--- ") or startsWith(line, "+++ "))',
  '				or not (startsWith(line, "--- ") or startsWith(line, "+++ "))', "layercommits"),
 ("M10 extra commits accepted", L, "	if #after > #before then", "	if false then", "layercommits"),
 ("M11 subjects not compared", L, "		if now.subject ~= was.subject then", "		if false then", "layercommits"),
 ("M12 skip never cleared after a spend.md section", L,
  "			current = if string.sub(line, -#spend) == spend then nil else {}",
  "			skipAll = skipAll or string.sub(line, -#spend) == spend\n			current = if skipAll then nil else {}", "layercommits"),
 ("M13 only added lines in the key", L,
  "			then\n				table.insert(into, line)\n			end",
  "			then\n				if startsWith(line, \"+\") then\n					table.insert(into, line)\n				end\n			end", "layercommits"),
 ("M14 a stale local copy wins over origin", L, "	if c.localInRemote then\n		return c.remoteSha, nil", "	if c.localInRemote then\n		return c.localSha, nil", "layercommits"),
 ("M15 no reset on a red check", MN, '			sh.git({ "reset", "--hard", was })\n', "", "restack-keeps"),
 ("M16 a conflict is not aborted", MN, '			sh.run("git", { "rebase", "--abort" })\n', "", "restack-keeps"),
 ("M17 same-commit copies refused as diverged", L, "	if c.sameCommits then", "	if false then", "layercommits"),
 ("M17b same-commit copies refused as diverged (restack)", L, "	if c.sameCommits then", "	if false then", "restack-keeps"),
 ("M18 an already stacked copy origin lacks is never pushed", MN,
  "			if hasOrigin() and remoteSha and tip ~= remoteSha then", "			if false then", "restack-keeps"),
 ("M19 neither ancestor: copies taken as the same without comparing", MN,
  "			same = layercommits.keepsCommits(theirs, mine) == nil", "			same = true", "restack-keeps"),
 ("M20 path lines kept in the key", L,
  '				or not (startsWith(line, "index ") or startsWith(line, "--- ") or startsWith(line, "+++ "))',
  '				or not startsWith(line, "index ")', "layercommits"),
 ("M20b path lines kept in the key (restack, a rename on main)", L,
  '				or not (startsWith(line, "index ") or startsWith(line, "--- ") or startsWith(line, "+++ "))',
  '				or not startsWith(line, "index ")', "restack-keeps"),
 ("M21 --- and +++ dropped outside the header too", L, "				not inHeader\n				or not (", "				not (", "layercommits"),
 ("M22 sections not sorted", L, "	table.sort(sections)\n", "", "layercommits"),
]
for name, path, old, new, spec in M:
    p = proto / path; s = p.read_text()
    assert s.count(old) == 1, f"{name}: anchor not found once"
    p.write_text(s.replace(old, new))
    try:
        r = subprocess.run([plain, "lune", "run", "tests/run", "--", A + spec + ".spec.luau"], cwd=proto / "z-nile",
                           capture_output=True, text=True)
        out = r.stdout + r.stderr
        fails = [l for l in out.splitlines() if l.startswith("FAIL ") and "::" in l]
        kind = "assertion" if any("expected" in l for l in out.splitlines()) else "OTHER"
        print(f"{name}: {'KILLED' if fails else 'SURVIVED'} ({kind}); {len(fails)} case(s) red")
        for l in fails: print("   ", l.split("::", 1)[1].strip()[:110])
    finally:
        p.write_text(s)
