#!/usr/bin/env python3
# c0280 mutation check: python3 mutants.py [name ...]  (run through ./zn run --time N -- python3 ...)
# Each mutant replaces one text in the prototype, runs the specs from z-nile's home, and restores the file.
import subprocess, sys, os

HOME = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CASES = "tests/acceptance/c0280/provenance-cases.spec.luau"
WHO = "tests/acceptance/c0280/who.spec.luau"
PRO = "engine/provenance.luau"
TRAIL = "engine/trail.luau"
WHOM = "engine/who.luau"
MAIN = "engine/main.luau"

M = []  # (name, file, old, new, specs)
def m(name, f, old, new, specs):
    M.append((name, f, old, new, specs))

m("fromTrailer key case-sensitive", PRO, '"^[Cc][Oo]%-[Aa][Uu][Tt][Hh][Oo][Rr][Ee][Dd]%-[Bb][Yy]:(.*)$"', '"^Co%-Authored%-By:(.*)$"', [CASES])
m("fromTrailer any trailer", PRO, '"^[Cc][Oo]%-[Aa][Uu][Tt][Hh][Oo][Rr][Ee][Dd]%-[Bb][Yy]:(.*)$"', '"^[%w%-]+:(.*)$"', [CASES])
m("fromTrailer model unnormalised", PRO, 'return `{provenance.agent(name, nil)} (from git)`', 'return `agent:{name} effort unknown (from git)`', [CASES])
m("fromCommit people ignored", PRO, 'not (email and people[email])', 'true', [CASES])
m("person email not lower-cased", PRO, 'string.lower(email) else nil', 'email else nil', [WHO])
m("fromCommit first agent wins", PRO, '			agent = `{provenance.agent(name, nil)} (from git)`\n', '			agent = agent or `{provenance.agent(name, nil)} (from git)`\n', [CASES])
m("idea reads the trailer", PRO, 'actor = `{provenance.human(capture.author)} ({how})`', 'actor = provenance.fromCommit(capture.author, capture.trailers or {}, people)', [CASES, WHO])
m("idea first add unmarked", PRO, 'local how = if isCapture then "from git" else "from git, first add"', 'local how = "from git"', [CASES])
m("new counted as a status", PRO, 'if word == "new" then', 'if false then', [CASES])
m("status of any subject", PRO, '`^tracker: {id} (%S+)$`', '"^tracker: %S+ (%S+)$"', [CASES])
m("unblocked covered ignored", PRO, 'if not records[c.sha] then', 'if true then', [CASES])
m("unblocked covered by any record", PRO, 'if not records[c.sha] then', 'if next(records) == nil then', [CASES, WHO])
m("rafted first rafting kept", PRO, '				else\n					start = nil\n', '				else\n', [CASES])
m("rafted newest commit", PRO, 'start = start or c\n', 'start = c\n', [CASES])
m("delivered newest done add", PRO, '		for _, c in docs do\n			local added: Commit? = nil', '		for k = #docs, 1, -1 do\n			local c = docs[k]\n			local added: Commit? = nil', [CASES])
m("delivered any change under done", PRO, 'r.status == "A" and string.find(r.path, marker, 1, true)', 'r.status ~= "D" and string.find(r.path, marker, 1, true)', [CASES])
m("merged reads the trailer", PRO, 'actor = `{provenance.human(c.author or "unknown")} (from git)`,\n					detail = "",\n					source = "git",\n				}\n				break', 'actor = actorOf(c, people),\n					detail = "",\n					source = "git",\n				}\n				break', [CASES, WHO])
m("merge newest first", PRO, 'return a.when < b.when', 'return a.when > b.when', [CASES])
m("merge stored first on a tie", PRO, 'return a.source == "git"', 'return a.source == "record"', [CASES])
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
m("people not lower-cased", WHOM, 'out[string.lower(email)] = true', 'out[email] = true', [WHO])
m("people ignored", MAIN, 'whoLib.people(head)', '{}', [WHO])
m("raft after each commit empty", WHOM, 'out[c.sha] = store.parseFront(text).raft or ""', 'out[c.sha] = ""', [WHO])
m("record not wanted", WHOM, 'return trail.isDoc(name) or name == "provenance.md"', 'return trail.isDoc(name)', [WHO])
m("who: rows ignored", MAIN, '		rows = parsed :: { provenance.Row }\n	end\n	local spendRows', '		rows = {}\n	end\n	local spendRows', [WHO])
m("who: bad record skipped", MAIN, 'fail(`who: {recordPath}: {err}`)', 'rows = {}', [WHO])
m("who: spend ignored", MAIN, 'for _, r in (parsed :: ledger.Ledger).rows do\n			table.insert(spendRows', 'for _, r in {} :: { ledger.Row } do\n			table.insert(spendRows', [WHO])
m("who: raft ignored", MAIN, 'local raft = store.readFront(found.doc).raft or ""', 'local raft = ""', [WHO])
m("who: state fixed", MAIN, '		found.state,\n		raft,', '		"backlog",\n		raft,', [WHO])
m("delivered last change under done", PRO, ['		for _, c in docs do\n			local added: Commit? = nil', 'r.status == "A" and string.find(r.path, marker, 1, true)'], ['		for k = #docs, 1, -1 do\n			local c = docs[k]\n			local added: Commit? = nil', 'r.status ~= "D" and string.find(r.path, marker, 1, true)'], [CASES])
m("cut ignores compaction cuts", TRAIL, 'return c.doc and cuts[c.sha] ~= nil', 'return false', [CASES])
m("cut note dropped", TRAIL, 'table.insert(notes, { sha = string.sub(start.sha, 1, 7), file = cuts[start.sha] })', 'table.insert(notes, { sha = "", file = "" })', [CASES])
m("docs: who row dropped from zz-rules", "skills/zz-rules/SKILL.md", "| who | `./zn who <id>` |", "| whom | `./zn whom <id>` |", [CASES])
m("docs: usage line dropped", MAIN, "  who <id>   ", "  whom <id>  ", [CASES])

def run(specs):
    r = subprocess.run(["lune", "run", "tests/run", "--"] + specs, cwd=HOME, capture_output=True, text=True, timeout=500)
    return r.returncode, r.stdout + r.stderr

def main():
    want = sys.argv[1:]
    for name, f, old, new, specs in M:
        if want and name not in want:
            continue
        path = os.path.join(HOME, f)
        src = open(path).read()
        pairs = list(zip(old, new)) if isinstance(old, list) else [(old, new)]
        bad = [o for o, _ in pairs if src.count(o) != 1]
        if bad:
            print(f"ERROR   {name}: old text occurs {src.count(bad[0])} times")
            continue
        mutated = src
        for o, n in pairs:
            mutated = mutated.replace(o, n, 1)
        open(path, "w").write(mutated)
        try:
            verdict, detail = "SURVIVED", ""
            for spec in specs:
                code, out = run([spec])
                if code != 0:
                    fails = [l for l in out.splitlines() if "FAIL" in l or "expected" in l or "error" in l.lower()]
                    detail = " | ".join(x.strip()[-160:] for x in fails[:3])
                    verdict = "KILLED" if ("expected" in out or "toBe" in out or "FAIL" in out) else "ERRORED"
                    break
            print(f"{verdict:8}{name}: {detail}", flush=True)
        finally:
            open(path, "w").write(src)

main()
