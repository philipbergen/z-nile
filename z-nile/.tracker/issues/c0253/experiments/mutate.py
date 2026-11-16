"""c0253 mutation check (round 2, the supervisor over the dispatcher). Usage (from the repository root, never the real checkout):
    ./zn run --time 3500 -- python3 -I z-nile/.tracker/issues/c0253/experiments/mutate.py <worktree> <ids|all>
For each mutant: apply one text replacement to one file of <worktree> (a scratch worktree of proto-c0253), run the row's spec
under `./zn run --time 290 -- lune run tests/run -- <spec>` from <worktree>/z-nile, restore the file, and print
`id hash outcome spec :: case | message`. The mutant must fail on an ASSERTION: a case that fails with an error (a syntax,
require or index error) is outcome `error`, not `killed`. Nothing here touches any other checkout."""
import hashlib, subprocess, sys, re, os

ACC = ".tracker/issues/c0253/acceptance/"
M = {}
def m(i, f, old, new, spec):
    M[i] = (f, old, new, spec)

S = "engine/supervise.luau"
m("S01", S, "if not table.find(supervise.KINDS, kind) then", "if false then", "pure")
m("S02", S, 'if code == 1 and string.sub(trim(stderr), 1, #"next: nothing to take") == "next: nothing to take" then', "if code == 1 then", "pure")
m("S04", S, '	table.insert(args, "--worker")\n', "", "pure")
m("S05", S, "	if o.noRun then", "	if false then", "pure")
m("S06", S, '		if kind == "draft" then\n			return { kind = "park"', '		if false then\n			return { kind = "park"', "pure")
m("S07", S, "if tries < 1 then", "if tries < 2 then", "pure")
m("S08", S, "elseif code == supervise.EXIT.user then", "elseif false then", "pure")
m("S09", S, '	"CLAUDE_CODE_SESSION_ID",\n', "", "pure")
m("S10", S, '	"ZN_DISPATCH_DIR",\n', "", "pure")
m("S11", S, '	if env.CLAUDECODE == "1" or (env.CLAUDE_CODE_SESSION_ID or "") ~= "" then', "	if false then", "pure")
m("S12", S, "if not table.find(roles[role], cli) then", "if false then", "pure")
m("S13", S, 'if (s.headless or "") ~= "" or (s.dispatch or "") ~= "" then', "if false then", "pure")
m("S14", S, "elseif s.detach and s.checking then", "elseif false then", "pure")
m("S15", S, "elseif s.here ~= s.main then", "elseif false then", "pure")
m("S16", S, 'return value ~= "false" and (value == "true" or value == nil)', 'return value ~= "false"', "pure")
m("S17", S, 'if not (noRun and gate == "run") then', "if true then", "pure")
m("S18", S, 'if preferred ~= nil and preferred ~= "" and cliOf(spec) == preferred then', "if false then", "pure")
m("S19", S, "if i == 1 and (waits[cliOf(spec)] or 0) > 0 then", "if false then", "pure")
m("S20", S, "if capSeconds ~= nil and now - began >= capSeconds then", "if false then", "pure")
m("S21", S, "local began = since or now", "local began = now", "pure")
m("S22", S, "elseif record.cli == cli then", "elseif false then", "pure")
m("S23", S, "read it now", "skip it", "pure")
m("S24", S, "you have read", "you may skip", "pure")
m("S25", S, "if at and out[at + 1] ~= nil then", "if false then", "pure")
m("S26", S, '	opencode = { new = "", resume = "-s" },\n', "", "pure")
m("S27", S, "	elseif ended then", "	elseif true then", "pure")
m("S28", S, '	if s.state == "stopped" then\n		live = "stopped"', '	if false then\n		live = "stopped"', "pure")
m("S29", S, "if not pid or not moved or not blocked or not state then", "if false then", "pure")
m("S30", S, 'if a ~= "--detach" and a ~= "work" and a ~= "run" then', 'if a ~= "work" and a ~= "run" then', "pure")
m("S31", S, "for _, a in supervise.cleanArgv(base, zn, forwarded) do", "for _, a in forwarded do", "pure")
m("S32", S, 'local forwarded: { string } = { "work", "run" }', 'local forwarded: { string } = { "work" }', "pure")
m("S33", S, '"- retry: run the worker again when a CLI has quota (recommended)"', '"- retry: run the worker again when a CLI has quota"', "pure")
m("S34", S, "return `{raftFolder}/notes.md`", "return `{raftFolder}/NOTES`", "pure")
m("S35", S, '`blocked: {if #s.blocked == 0 then "nothing" else table.concat(s.blocked, ", ")}`,', '`blocked: nothing`,', "pure")
m("S36", S, 'if o.cli and o.cli ~= "" then', "if false then", "pure")
m("S37", S, "	if o.retry then", "	if false then", "pure")

L = "engine/workloop.luau"
m("L01", L, 'if resumeFirst ~= "" then', "if false then", "loop")
m("L02", L, '	if result ~= "stopped" and result ~= "stop" then\n		publish(world, "working", "", "", tally)', '	if false then\n		publish(world, "working", "", "", tally)', "loop")
m("L03", L, "if not world.lock(pick.id) then", "if false then", "loop")
m("L04", L, '		if world.stopped() then\n			result, why = "stopped"', '		if false then\n			result, why = "stopped"', "loop")
m("L05", L, "			tries += 1\n", "			tries += 0\n", "loop")
m("L06", L, "if world.now() - from >= supervise.GATE_WAIT_SECONDS then", "if false then", "loop")
m("L08", L, 'elseif move.kind == "park" then', "elseif false then", "loop")
m("L09", L, "if blockedInARow >= work.BLOCKED_IN_A_ROW then", "if false then", "loop")
m("L10", L, "if failedReads >= supervise.READ_RETRIES then", "if false then", "loop")
m("L11", L, "			failedReads = 0\n", "", "loop")
m("L12", L, 'if opts.once then\n					stopped = "nothing claimable (--once)"', 'if false then\n					stopped = "nothing claimable (--once)"', "loop")
m("L13", L, "if opts.maxItems and taken >= opts.maxItems then", "if false then", "loop")
m("L14", L, "world.sleep(world.idleSeconds or supervise.IDLE_SECONDS)\n				continue", "continue", "loop")
m("L15", L, '				publish(world, "waiting", "", "", tally)\n				world.sleep(supervise.IDLE_SECONDS)', '				publish(world, "waiting", "", "", tally)', "loop")
m("L17", L, "			heldAtEnd = p.id\n			world.say(why)", "			world.say(why)", "loop")
m("L20", L, "			retrying = true\n", "			retrying = false\n", "loop")
m("L21", L, "cli = world.cli, noRun", "cli = nil, noRun", "loop")
m("L22", L, "noRun = world.noRun, retry", "noRun = false, retry", "loop")

E = "engine/workedge.luau"
m("E01", E, "	if refused then\n		return nil, refused", "	if false then\n		return nil, refused", "command")
m("E02", E, "local problem = supervise.cliProblem(cli, rolesTries(top))", "local problem = nil", "command")
m("E04", E, "pcall(fs.removeFile, `{dir(top)}/stop`)", 'pcall(print, "x")', "command")
m("E05", E, "	if not lock then", "	if false then", "command")
m("E06", E, 'if not s or s.state == "stopped" or not alive(s.pid) then', "if false then", "command")
m("E07", E, "local argv = supervise.cleanArgv(process.env :: { [string]: string? }, `{top}/zn`, args)", "local argv = supervise.cleanArgv({}, `{top}/zn`, args)", "session")
m("E08", E, 'process.exec("git", { "show", "origin/main:.models.toml" }, { cwd = top })', 'process.exec("cat", { ".models.toml" }, { cwd = top })', "command")
m("E10", E, 'local held = if before then before.held else ""', 'local held = ""', "command")

Mn = "engine/main.luau"
m("N01", Mn, '			or a == "--once"\n', "", "command")
m("N02", Mn, '			or a == "--detach"\n', "", "command")
m("N03", Mn, '			or a == "--worker"\n', "", "command")
m("N04", Mn, '			or a == "--no-run"\n', "", "command")
m("N05", Mn, '	local path = "z-nile/skills/z-work/SKILL.md"', '	fail("bare work refused")\n	local path = "z-nile/skills/z-work/SKILL.md"', "command")
m("N06", Mn, 'elseif k ~= "--released" then\n			fail(', 'elseif false then\n			fail(', "command")
m("N07", Mn, "if not n or n < 1 or n ~= math.floor(n) then\n				fail(\"usage: --max-items", "if not n then\n				fail(\"usage: --max-items", "command")
m("N08", Mn, 'if (#pos > 1) or (#pos == 1 and sub ~= "run") or opts["--released"] then\n			fail("usage: ./zn work run', 'if false then\n			fail("usage: ./zn work run', "command")

m("P01", "engine/reap.luau", "		if exempt[at.pid] then\n			return true", "		if reap.isSupervisor(at) then\n			return true", "reap")
m("P02", "engine/reap.luau", "if at == nil or not reap.isSupervisor(at) then", "if at == nil then", "reap")
m("P03", "engine/reap.luau", '		and string.find(p.command, "engine/main -- work run", 1, true) ~= nil\n', "", "reap")
m("P04", "engine/reap.luau", "			at = byPid[at.ppid]\n", "			at = nil\n", "reap")
m("P05", "engine/reap.luau", "			and not underExempt(p, exempt, byPid)\n", "", "reap")
m("B01", "engine/board.luau", '			and process.exec("kill", { "-0", tostring(s.pid) }).ok\n', "", "board")
m("B02", "engine/board.luau", '			and s.state ~= "stopped"\n', "", "board")
m("B03", "engine/board.luau", "facts.dispatch[s.item] = facts.dispatch[s.item]\n				or {", "facts.dispatch[s.item] = {", "board")
m("K01", "engine/models.luau", "out[cli] = minutes * 60", "out[cli] = minutes", "models")
m("K02", "engine/models.luau", 'if type(name) ~= "string" or not isCli(name) or type(fields) ~= "table" then', 'if type(name) ~= "string" or type(fields) ~= "table" then', "models")
m("K03", "engine/models.luau", 'if field ~= "quota_wait_minutes" then', "if false then", "models")

D = "engine/dispatcher.luau"
m("D01", D, "sessionMode = supervise.sessionMode(st.session, spec.cli)", 'sessionMode = "new"', "dispatch")
m("D02", D, "st.session = { cli = spec.cli, id = result.session or sessionId }", "st.session = st.session", "dispatch")
m("D03", D, "if worker.on and step ~= \"zz-review\" then worker.cli else nil,", "nil,", "dispatch")
m("D04", D, "dispatcher.workerWait(ctx, id, cwd, stateDir, quotaWaits[spec.cli] or 0)", "local _ = 0", "dispatch")
m("D05", D, 'if worker.on and step ~= "zz-review" then quotaWaits else {}', "models.quotaWaits(walk(store.get(id).dir))", "dispatch")
m("D07", D, '				if worker.on and step == "z-run" then\n					for _ = 1, 1000000 do', '				if false then\n					for _ = 1, 1000000 do', "dispatch")
m("D08", D, "			if outcomeNow == \"ok\" then\n				st.quotaSince = nil", "			if false then\n				st.quotaSince = nil", "dispatch")
m("D10", D, "started = heartbeat.stampIn(store.readFront(store.get(id).doc).status)", "started = nil", "dispatch")
m("D11", D, "if verdict.kind == \"block\" then\n							local wt", "if false then\n							local wt", "dispatch")
m("D12", D, 'supervise.notesPath(store.get(id).dir)', '"notes"', "dispatch")

SPEC = {k: ACC + k + ".spec.luau" for k in ["pure", "loop", "session", "command", "reap", "board", "models", "docs", "dispatch"]}

def run(wt, ids):
    z = os.path.join(wt, "z-nile")
    for i in ids:
        f, old, new, spec = M[i]
        path = os.path.join(z, f)
        text = open(path).read()
        n = text.count(old)
        if n != 1:
            print(i, "-", "not-applied", f"old text occurs {n} times in {f}", flush=True)
            continue
        h = hashlib.sha1((f + "\0" + old + "\0" + new).encode()).hexdigest()[:8]
        open(path, "w").write(text.replace(old, new, 1))
        try:
            # the output goes to a file, not a pipe: a mutant that makes a dispatch loop never end leaves a child holding a pipe
            # open, and the run would wait for it; the leak is stopped by name after the run (these are this script's own)
            log = os.path.join(z, ".cache", "mutant.out")
            os.makedirs(os.path.dirname(log), exist_ok=True)
            with open(log, "w") as fh:
                subprocess.run(["../zn", "run", "--time", "290", "--", "lune", "run", "tests/run", "--", SPEC[spec]],
                               cwd=z, stdout=fh, stderr=subprocess.STDOUT, timeout=420)
            out = open(log).read()
        except subprocess.TimeoutExpired:
            out = "TIMEOUT"
        finally:
            open(path, "w").write(text)
            if spec in ("dispatch", "session"):
                subprocess.run(["pkill", "-f", "engine/main -- dispatch R0010"], capture_output=True)
        fails = re.findall(r"^FAIL [^\n]*? :: ([^\n]*)\n\s*[^\n]*?: ([^\n]*)", out, re.M)
        bad = ("attempt to", "syntax", "Unable to", "cannot", "Parse", "unexpected", "Requires", "TIMEOUT", "error:", "Expected identifier")
        if not fails:
            print(i, h, "SURVIVED", spec, flush=True)
        elif any(any(b in msg for b in bad) for _, msg in fails) and not any("expected" in msg for _, msg in fails):
            print(i, h, "error", fails[0][0][:90], "|", fails[0][1][:120], flush=True)
        else:
            c, msg = fails[0]
            print(i, h, "killed", spec, "::", c[:90], "|", msg[-70:], flush=True)

if __name__ == "__main__":
    wt = sys.argv[1]
    ids = list(M) if sys.argv[2] == "all" else sys.argv[2].split(",")
    run(wt, ids)
