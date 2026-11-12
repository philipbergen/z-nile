#!/usr/bin/env python3
# c0280 mutation check: python3 mutants.py [name ...]  (run through ./zn run --time N -- python3 ... from z-nile's home)
# Each mutant replaces one or more texts in the prototype, runs the specs from z-nile's home, and restores the files.
import subprocess, sys, os

HOME = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CASES = "tests/acceptance/c0280/provenance-cases.spec.luau"
WHO = "tests/acceptance/c0280/who.spec.luau"
PRO = "engine/provenance.luau"
TRAIL = "engine/trail.luau"
WHOM = "engine/who.luau"
MAIN = "engine/main.luau"
RULES = "skills/zz-rules/SKILL.md"

M = []  # (name, file, old, new, specs)


def m(name, f, old, new, specs):
    M.append((name, f, old, new, specs))


KEY = '"^[Cc][Oo]%-[Aa][Uu][Tt][Hh][Oo][Rr][Ee][Dd]%-[Bb][Yy]:(.*)$"'
m("fromTrailer key case-sensitive", PRO, KEY, '"^Co%-Authored%-By:(.*)$"', [CASES])
m("fromTrailer any trailer", PRO, KEY, '"^[%w%-]+:(.*)$"', [CASES])
m("fromTrailer model unnormalised", PRO, 'return `{provenance.agent(name, nil)} (from git)`', 'return `agent:{name} effort unknown (from git)`', [CASES])
m("fromTrailer ignores people", PRO, 'if people ~= nil and email ~= nil and people[email] then', 'if false then', [CASES])
m("fromTrailer emailless is a person", PRO, 'if people ~= nil and email ~= nil and people[email] then', 'if people ~= nil and (email == nil or people[email]) then', [CASES])
m("person email not lower-cased", PRO, 'string.lower(email) else nil', 'email else nil', [WHO])
m("agentOf first agent wins", PRO, 'agent = provenance.fromTrailer(`Co-Authored-By: {value}`, people) or agent', 'agent = agent or provenance.fromTrailer(`Co-Authored-By: {value}`, people)', [CASES])
m("idea reads the trailer", PRO, '`{provenance.human(capture.author)} ({how})`, mark.note)', 'actorOf(capture, people), mark.note)', [WHO])
m("idea first add unmarked", PRO, 'local how = if isCapture then "from git" else "from git, first add"', 'local how = "from git"', [CASES])
m("cut life idea not its start", PRO, 'if mark.cut and steps[1] then', 'if false and steps[1] then', [CASES, WHO])
m("idea mark dropped", PRO, '`{provenance.human(capture.author)} ({how})`, mark.note)', '`{provenance.human(capture.author)} ({how})`, "")', [CASES, WHO])
m("restamp is a status change", PRO, 'elseif word ~= nil and prevWord ~= nil and word ~= prevWord then', 'elseif word ~= nil and prevWord ~= nil then', [CASES])
m("first word is a status change", PRO, 'elseif word ~= nil and prevWord ~= nil and word ~= prevWord then', 'elseif word ~= nil and word ~= prevWord then', [CASES])
m("release give-back is an unblock", PRO, 'if word == "new" and string.match(step.c.subject, "^tracker: [fdcR]%d%d%d%d new$") then', 'if word == "new" then', [CASES])
m("unblock only by the item id", PRO, '"^tracker: [fdcR]%d%d%d%d new$"', '"^tracker: c0010 new$"', [CASES])
m("no unblocked", PRO, 'if word == "new" and string.match(step.c.subject, "^tracker: [fdcR]%d%d%d%d new$") then', 'if false then', [CASES])
m("unblocked covered ignored", PRO, 'if not records[step.c.sha] then', 'if true then', [CASES])
m("unblocked covered by any record", PRO, 'if not records[step.c.sha] then', 'if next(records) == nil then', [CASES, WHO])
m("rafted first rafting kept", PRO, '				else\n					start = nil\n				end\n			end\n		end\n		-- a run', '				end\n			end\n		end\n		-- a run', [CASES])
m("rafted newest commit", PRO, 'start = start or step', 'start = step', [CASES])
m("cut run attributed to the cut", PRO, 'if mark.cut and start == steps[1] then', 'if false then', [CASES])
m("delivery without a previous area", PRO, '			and prevArea ~= nil\n', '', [CASES, WHO])
m("a second arrival replaces the delivery", PRO, '			and out.delivered == nil\n', '', [CASES])
m("a root move is a delivery", PRO, '			and prevArea ~= "done"\n', '', [CASES, WHO])
m("a delete row read as the step", PRO, 'if c.doc and not isRecordPath(c.path) and c.status ~= "D" and not seen[c.sha] then', 'if c.doc and not isRecordPath(c.path) and not seen[c.sha] then', [CASES])
m("merged names the author", PRO, 'provenance.agentOf(allTrailers(step.c), people) or "unknown"', 'actorOf(step.c, people)', [CASES, WHO])
m("second parent trailers ignored", PRO, 'for _, v in side do', 'for _, v in {} :: { string } do', [CASES])
m("merge newest first", PRO, 'return a.when < b.when', 'return a.when > b.when', [CASES])
m("merge stored first on a tie", PRO, 'return a.source == "git"', 'return a.source == "record"', [CASES])
m("merge derived by kind within a minute", PRO, 'if a.at ~= b.at and a.at ~= nil and b.at ~= nil then', 'if false then', [CASES])
m("merge stored of any raft wins", PRO, '(want == "" or raftPart(r.detail) == want)', 'true', [CASES])
m("merge derived always kept", PRO, 'if derived.rafted and not stored(rows, "rafted", derived.rafted) then', 'if derived.rafted then', [CASES, WHO])
m("merge worker dropped", PRO, 'e.detail = withWorker(e.detail, worker)', 'e.detail = e.detail', [CASES])
m("merge worker on every entry", PRO, 'if e.event == "delivered" then\n			e.detail', 'if true then\n			e.detail', [CASES, WHO])
m("workerRow build first", PRO, 'for _, phase in { "deliver", "build" } do', 'for _, phase in { "build", "deliver" } do', [CASES])
m("workerRow oldest row", PRO, 'for i = #rows, 1, -1 do\n			local r = rows[i]', 'for i = 1, #rows do\n			local r = rows[i]', [CASES])
m("workerOf model only", PRO, 'for _, part in { row.host, row.cli, row.model } do', 'for _, part in { row.model } do', [CASES])
m("line prints an empty detail", PRO, 'if e.detail ~= "" then\n		table.insert(parts, e.detail)', 'if true then\n		table.insert(parts, e.detail)', [WHO])
m("trail: every trailer key", TRAIL, 'trailers:key=Co-Authored-By,valueonly', 'trailers:valueonly', [WHO])
m("trail: author not read", TRAIL, 'author = string.sub(line, 3)', 'author = nil', [CASES, WHO])
m("trail: unit separator lost", TRAIL, 'string.gmatch(string.sub(line, 3), "[^\\31]+")', 'string.gmatch(string.sub(line, 3), "[^\\n]+")', [CASES])
m("trail: email not read", TRAIL, 'email = string.sub(line, 3)', 'email = nil', [CASES])
m("trail: parents not read", TRAIL, 'parents = list', 'parents = nil', [CASES, WHO])
m("trail: lifeOf leaves the id unset", TRAIL, '		copy.id = id\n', '', [WHO])
m("trail: mainline not first-parent", TRAIL, 'changes({ "log", head }, trail.dirs(kind, id, within :: { string }), keep, id, firstParent == true)', 'changes({ "log", head }, trail.dirs(kind, id, within :: { string }), keep, id, false)', [WHO])
m("cut ignores compaction cuts", TRAIL, 'return c.doc and cuts[c.sha] ~= nil', 'return false', [CASES, WHO])
m("cut note dropped", TRAIL, 'table.insert(notes, { sha = string.sub(start.sha, 1, 7), file = cuts[start.sha] })', 'table.insert(notes, { sha = "", file = "" })', [CASES])
m("people not lower-cased", WHOM, 'out[string.lower(email)] = true', 'out[email] = true', [WHO])
m("people ignored", MAIN, 'whoLib.people(head)', '{}', [WHO])
m("people from the newest commit only", WHOM, 'git({ "log", "--format=%ae", head })', 'git({ "log", "-1", "--format=%ae", head })', [WHO])
m("fronts ignored", MAIN, 'whoLib.fronts(commits)', '{}', [WHO])
m("record not wanted", WHOM, 'return trail.isDoc(name) or name == "provenance.md"', 'return trail.isDoc(name)', [WHO])
m("head is this checkout", WHOM, '		then "origin/main"\n', '		then "HEAD"\n', [WHO])
m("no history is accepted", WHOM, 'if commits == nil or not hasDoc then', 'if commits == nil then', [WHO])
m("side trailers not read", WHOM, '	if #want == 0 then\n		return\n	end', '	if true then\n		return\n	end', [WHO])
m("who: mark dropped", MAIN, 'whoLib.fronts(commits), mark)', 'whoLib.fronts(commits), { note = "", cut = false })', [WHO])
m("who: rows ignored", MAIN, '		rows = parsed :: { provenance.Row }\n	end', '		rows = {}\n	end', [WHO])
m("who: bad record skipped", MAIN, 'fail(`who: {recordPath}: {err}`)', 'rows = {}', [WHO])
m("who: spend ignored", MAIN, 'for _, r in (parsed :: ledger.Ledger).rows do\n			table.insert(spendRows', 'for _, r in {} :: { ledger.Row } do\n			table.insert(spendRows', [WHO])
m("who: bad spend skipped", MAIN, 'fail(`who: {spendPath} does not parse ({err})`)', 'stdio.ewrite("")', [WHO])
m("who: a raft's roll-up read as a ledger", MAIN, 'if found.kind == "issue" and fs.isFile(spendPath) then', 'if fs.isFile(spendPath) then', [WHO])
m("who: raft kind fixed to issues", WHOM, 'local kind = if string.sub(id, 1, 1) == "R" then "rafts" else "issues"', 'local kind = "issues"', [WHO])
m("docs: who row dropped from zz-rules", RULES, "| who | `./zn who <id>` |", "| whom | `./zn whom <id>` |", [CASES])
m("docs: usage line dropped", MAIN, "  who <id>   ", "  whom <id>  ", [CASES])
m("docs: merged named the author", RULES, "(that commit's agent trailer, or its second", "(that commit's author, or its second", [CASES])


def run(specs):
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=900)
    return r.returncode, r.stdout + r.stderr


def main():
    want = sys.argv[1:]
    for name, f, old, new, specs in M:
        if want and name not in want:
            continue
        path = os.path.join(HOME, f)
        src = open(path).read()
        if src.count(old) != 1:
            print(f"ERROR   {name}: old text occurs {src.count(old)} times", flush=True)
            continue
        open(path, "w").write(src.replace(old, new, 1))
        try:
            verdict, detail = "SURVIVED", ""
            for spec in specs:
                code, out = run([spec])
                if code != 0:
                    fails = [l for l in out.splitlines() if "FAIL" in l or "expected" in l]
                    detail = " | ".join(x.strip()[-150:] for x in fails[:2])
                    verdict = "KILLED" if ("expected" in out or "toBe" in out or "FAIL" in out) else "ERRORED"
                    break
            print(f"{verdict:8}{name}: {detail}", flush=True)
        finally:
            open(path, "w").write(src)


main()
