#!/usr/bin/env python3
# c0286 prep's mutation check. Run it from a prototype worktree's z-nile home (proto-c0286): for each row it applies one
# mutant to the prototype's engine file, runs the row's spec, and requires the named case to FAIL on an assertion
# ("expected"), then restores the file. A row's anchor may be a list of (old, new) pairs, applied together.
# Usage (review 001 F6: bounded, and in the environment check.sh's `undispatched` gives a spec):
#   ./zn run --time 1800 -- python3 -I mutants.py <proto z-nile home>
import os, subprocess, sys

HOME = sys.argv[1]
A = ".tracker/issues/c0286/acceptance"
RP = "engine/raftplan.luau"
MAIN = "engine/main.luau"
ENV = {k: v for k, v in os.environ.items() if k not in (
    "ZN_DISPATCH", "ZN_DISPATCH_DIR", "ZN_PUBLISH_BROKER", "ZN_PUBLISH_TOKEN", "ZN_HEADLESS", "ZN_REAL_GIT",
    "ZN_REAL_GH")}
ENV["PATH"] = ":".join(d for d in ENV.get("PATH", "").split(":") if not d.endswith("/z-nile/bin"))

M = [
 ("M1", RP, '''	local inner = string.match(value, "^%[(.*)%]$")
	if not inner then
		return {}, `tied: is not''', '''	local inner = string.match(value, "^%[?(.-)%]?$")
	if not inner then
		return {}, `tied: is not''', "ties", "reads tied: as a list"),
 ("M2", RP, 'string.match(e, "^[fdc]%d%d%d%d$")', 'string.match(e, "^[fdcR]%d+$")', "ties", "reads tied: as a list"),
 ("M3", RP, 'if seen[e] then', 'if false then', "ties", "reads tied: as a list"),
 ("M4", RP, 'local list = if tparent[id] then tieMembers[tfind(id)] else nil', 'local own = raftplan.parseTied(issueOf[id] and issueOf[id].tied) local list = if #own > 0 then (function() local l = table.clone(own) table.insert(l, id) table.sort(l) return l end)() else nil', "ties", "reads the ties both ways"),
 ("M5", RP, '''			else
				table.insert(waiting, `{id} ({m.status}, design {m.design or "draft"})`)''', '''			else
				-- mutant: a member not prepared is ignored''', "ties", "rafts none of a tie while"),
 ("M6", RP, '''		v.op = if into''', '''		local total = 0
		for _, id in candidates do
			total += issueOf[id].size :: number
		end
		if total > limit then
			v.cause = "over the cap"
			return v
		end
		v.op = if into''', "ties", "makes a tie one raft once every member"),
 ("M7", RP, "issues = candidates,\n\t\t\t\tsingle = false,\n\t\t\t}\n\t\treturn v", "issues = candidates,\n\t\t\t\tsingle = true,\n\t\t\t}\n\t\treturn v", "ties", "makes a tie one raft once every member"),
 ("M8", RP, '''		local tie = tieOf(i.id)
		if tie then''', '''		if (i.size :: number) > limit then
			table.insert(ops, { kind = "new", raft = nil, type = i.type, root = i.root, issues = { i.id }, single = true })
			continue
		end
		local tie = tieOf(i.id)
		if tie then''', "ties", "makes a tie one raft once every member"),
 ("M9", RP, '''		local tie = tieOf(i.id)
		if tie then''', '''		local tie = tieOf(i.id)
		if tie and i.type ~= "feature" then''', "ties", "groups tied features whatever their surface"),
 ("M10", RP, 'if r.state ~= "backlog" or r.status ~= "prepared" or r.single then', 'if r.single then', "ties", "never rafts a tie apart"),
 ("M11", RP, '''		if #waiting > 0 then''', '''		if #waiting > 0 and not into then''', "ties", "waits for every member before folding"),
 ("M12", RP, 'and not r.single and not holdsTie then', 'and not r.single then', "ties", "folds no untied issue into a raft"),
 ("M13", RP, 'if m.type ~= first.type or m.root ~= first.root then', 'if m.type ~= first.type then', "ties", "skips a tie one raft can't hold"),
 ("M14", RP, 'if issueOf[id].solo then', 'if false then', "ties", "skips a tie one raft can't hold"),
 ("M15", RP, '''			if j ~= i.id then
				local a, b = tfind(i.id), tfind(j)''', '''			if j ~= i.id and issueOf[j] then
				local a, b = tfind(i.id), tfind(j)''', "ties", "skips a tie one raft can't hold"),
 ("M16", RP, '''		if problem then
			tiedProblem[i.id] = problem
		end''', '', "ties", "skips an issue whose tied: it can't read"),
 ("M17", RP, 'local _, note = unplannable(m)', 'local _, note = unplannable(m)\n\t\t\tif note == "no size:" then\n\t\t\t\tnote = nil\n\t\t\tend', "ties", "skips a tied issue with no size"),
 ("M18", RP, '''	for _, list in tieMembers do
		table.sort(list)
	end''', '', "ties", "gives the same plan and skips"),
 ("M19", MAIN, '			tied = front.tied,\n', '', "plan-cli", "prints the tie as one raft"),
 ("M20", RP, '''		if #inRafts > 1 then''', '''		if #inRafts > 99 then''', "ties", "never rafts a tie apart"),
 ("M21", RP, '''			elseif m.state ~= "backlog" then''', '''			elseif m.state ~= "backlog" and false then''', "ties", "never rafts a tie apart"),
 # review 001 F5: the order of the causes
 ("M22", RP, '''		local into = inRafts[1]
''', '''		if #waiting > 0 then
			v.cause =
				`{table.concat(waiting, ", ")} not prepared yet: raft-plan rafts them together when every one is (retry a dispatched member once that rafting has merged)`
			return v
		end
		local into = inRafts[1]
''', "ties", "names the first cause in the stated order"),
 ("M23", RP, '''		local first = ref :: Issue
''', '''		local first = ref :: Issue
		for _, id in list do
			if issueOf[id].solo then
				v.cause = `{id} is solo: true, a raft by itself: z-raft with arguments decides`
				return v
			end
		end
''', "ties", "names the first cause in the stated order"),
 ("M26", RP, [
	('''		local candidates: { string } = {}
''', '''		local gone: string? = nil
		local candidates: { string } = {}
'''),
	('''				v.cause = `{id} is {m.state} with no raft: z-raft with arguments decides`
				return v''', '''				gone = gone or `{id} is {m.state} with no raft: z-raft with arguments decides`'''),
	('''		local into = inRafts[1]
''', '''		if gone then
			v.cause = gone
			return v
		end
		local into = inRafts[1]
'''),
 ], None, "ties", "names the first cause in the stated order"),
 # review 001 F2: an unreadable line on a backlog issue that is not prepared is named
 ("M24", RP, 'if i.state == "backlog" and not isCandidate(i) and tiedProblem[i.id] then', 'if i.state == "backlog" and not isCandidate(i) and tiedProblem[i.id] and false then', "ties", "names an unreadable tied: on a backlog issue that is not prepared"),
 # review 001 F4: a raft being rafted is waited for
 ("M25", RP, 'if r.state == "backlog" and r.status == "preparing" and not r.single then', 'if false then', "ties", "never rafts a tie apart"),
 # review 001 F1: the open raft holding some of a tie beside untied members
 ("M27", RP, 'and not r.single and not holdsTie then', 'and not r.single then', "ties", "folds a tie into the open raft that holds some of it beside untied members"),
]

failed = 0
for mid, path, old, new, spec, case in M:
    if spec is None:
        continue
    p = os.path.join(HOME, path)
    src = open(p).read()
    pairs = old if isinstance(old, list) else [(old, new)]
    mutated, missing = src, None
    for a, b in pairs:
        if mutated.count(a) != 1:
            missing = a
            break
        mutated = mutated.replace(a, b)
    if missing is not None:
        print(f"{mid}: anchor not found once in {path}"); failed += 1; continue
    open(p, "w").write(mutated)
    try:
        r = subprocess.run(["lune", "run", "tests/run", "--", f"{A}/{spec}.spec.luau"], cwd=HOME, env=ENV,
                           capture_output=True, text=True, timeout=600)
        out = r.stdout + r.stderr
        lines = out.splitlines()
        hit = [i for i, l in enumerate(lines) if l.startswith("FAIL") and case in l and "::" in l]
        ok = bool(hit) and any("expected" in lines[i + 1] for i in hit if i + 1 < len(lines))
        print(f"{mid}: {'killed (assertion)' if ok else 'SURVIVED or not an assertion'} :: {case}")
        if not ok:
            failed += 1
            print("\n".join(l for l in lines if l.startswith("FAIL") or "spec:" in l)[:1500])
    finally:
        open(p, "w").write(src)
sys.exit(1 if failed else 0)
