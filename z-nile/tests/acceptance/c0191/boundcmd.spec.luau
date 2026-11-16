--!strict
-- c0191 AC2: the PreToolUse hook on Bash refuses a command that starts an interpreter with no time limit and
-- names the wrapper, lets the gate's own commands and the wrapper through, and never blocks work on its own failure.
local boundcmd = require("@znile/engine/boundcmd")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local sh = require("@znile/lib/sh")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local REFUSED: { { command: string, rule: string, ctx: boundcmd.Context? } } = {
	-- the incident: a probe from a scratch folder
	{ command = "cd /tmp/x/cr4 && lune run p2.luau check 'a b'", rule = "unbounded" },
	{ command = "lune run p2.luau", rule = "unbounded" },
	{ command = "lune p2.luau", rule = "unbounded" },
	{ command = "lune run ./scripts/probe", rule = "unbounded" },
	{ command = "lune run tests/other", rule = "unbounded" },
	-- every way of reaching the program
	{ command = "env FOO=1 lune run x.luau", rule = "unbounded" },
	{ command = "FOO=1 lune run x.luau", rule = "unbounded" },
	{ command = "timeout 30 lune run x.luau", rule = "unbounded" },
	{ command = "time lune run x.luau", rule = "unbounded" },
	{ command = "ls | xargs -n1 lune run", rule = "unbounded" },
	{ command = "bash -c 'lune run x.luau'", rule = "unbounded" },
	{ command = 'sh -lc "cd d; lune run x.luau"', rule = "unbounded" },
	{ command = "eval 'lune run x.luau'", rule = "unbounded" },
	{ command = "echo $(lune run x.luau)", rule = "unbounded" },
	{ command = "echo `lune run x.luau`", rule = "unbounded" },
	{ command = "true && { lune run x.luau; }", rule = "unbounded" },
	{ command = "for f in a b; do lune run $f.luau; done", rule = "unbounded" },
	{ command = "false || lune run x.luau &", rule = "unbounded" },
	{ command = "lune repl", rule = "interactive" },
	-- other interpreters, and the things that leave a process nobody owns
	{ command = "python3 probe.py", rule = "unbounded" },
	-- inline Python is read like `perl -e`: refused only when it loops or starts a process with no timeout
	{ command = "python3 -c 'while True: pass'", rule = "unbounded" },
	{ command = "python3 -I -c 'import itertools; [x for x in itertools.count()]'", rule = "unbounded" },
	{ command = "python3 - <<'EOF'\nimport time\nwhile 1:\n    time.sleep(1)\nEOF", rule = "unbounded" },
	{ command = "cd d && python3 - <<'EOF'\nimport os\nos.system('sleep 999')\nEOF", rule = "unbounded" },
	{ command = "python3 -c 'import subprocess; subprocess.run([\"make\"])'", rule = "unbounded" },
	{ command = "python3 -m http.server", rule = "unbounded" },
	-- the other spellings of the same scripts: a prefix, a body piped in, a file fed on stdin, a script that cannot be read
	{ command = "FOO=1 python3 - <<'E'\nwhile True: pass\nE", rule = "unbounded" },
	{ command = "env X=1 python3 -I - <<'E'\nimport os\nos.system('x')\nE", rule = "unbounded" },
	{ command = "cat <<'E' | python3 -\nwhile True: pass\nE", rule = "unbounded" },
	{ command = "python3 - < probe.py", rule = "unbounded" },
	{ command = "cat probe.py | python3 -", rule = "unbounded" },
	-- more jobs started with & (a group, a brace group), in any kind of call
	{ command = "(sleep 1)&", rule = "background" },
	{ command = "{ sleep 1; }&", rule = "background" },
	{ command = "./zn land 2>&1 &", rule = "background", ctx = { background = true } },
	{ command = "sleep 600 &", rule = "background", ctx = { monitor = true } },
	-- a filter with nothing to read reads the tool shell's stdin, which never closes
	{ command = "grep -c x", rule = "background", ctx = { background = true } },
	{ command = "cat", rule = "background", ctx = { background = true } },
	{ command = "cat > out", rule = "background", ctx = { background = true } },
	{ command = "head -n 5", rule = "background", ctx = { background = true } },
	-- a clean inline script in a background call is refused like any interpreter there
	{ command = "python3 - <<'E'\nprint(1)\nE", rule = "background", ctx = { background = true } },
	-- a here-document whose owner has a redirection before it is still read
	{ command = "bash 2>&1 <<E\nlune run x.luau\nE", rule = "unbounded" },
	{ command = "python3", rule = "unbounded" },
	{ command = "node probe.js", rule = "unbounded" },
	{ command = "rojo serve", rule = "unbounded" },
	{ command = "rojo build --watch", rule = "unbounded" },
	{ command = "nohup lune run tests/run &", rule = "detach" },
	{ command = "setsid sleep 100", rule = "detach" },
	-- loops and follows that never end, which a foreground call turns into background ones when it times out
	{ command = "until s=$(gh pr view 138 --json state); do sleep 30; done", rule = "loop" },
	{ command = "cd x && while true; do date; sleep 1; done", rule = "loop" },
	{ command = "bash -c 'until grep -q DONE full.log; do sleep 20; done'", rule = "loop" },
	{ command = "tail -f full.log", rule = "follow" },
	{ command = "tail -n 20 -F full.log", rule = "follow" },
	{ command = "watch -n 5 ls", rule = "follow" },
	{ command = "gh run watch 123", rule = "follow" },
	{ command = "gh pr checks 138 --watch", rule = "follow" },
	{ command = "if x; then until true; do sleep 1; done; fi", rule = "loop" },
	{ command = "time while true; do :; done", rule = "loop" },
	{ command = "! until false; do :; done", rule = "loop" },
	{ command = "for ((;;)); do :; done", rule = "loop" },
	{ command = "for ((i=0;;i++)); do :; done", rule = "loop" },
	{ command = "bash <<EOF\nuntil false; do :; done\nEOF", rule = "loop" },
	{ command = "echo a <<< 'x'\nlune run y.luau", rule = "unbounded" },
	{ command = "echo $((1<<2))\nlune run y.luau", rule = "unbounded" },
	{ command = "echo 'x <<X'\nlune run y.luau", rule = "unbounded" },
	{ command = "caffeinate -t 5 lune run p.luau", rule = "unbounded" },
	{ command = "perl -e '1 while 1'", rule = "unbounded" },
	{ command = "perl -e 'for(;;){}'", rule = "unbounded" },
	{ command = "bash -c -- 'lune run x.luau'", rule = "unbounded" },
	{ command = "./zn list; perl -e 'print 1'", rule = "background", ctx = { background = true } },
	{ command = "caffeinate -i", rule = "unbounded" },
	-- the tooling that is not short or not limited: only `tests/run` is the runner's, the rest of it is wrapped
	{ command = "lune run z-nile/engine/main -- list", rule = "unbounded" },
	{ command = "lune run scripts/cicd", rule = "unbounded" },
	-- redirections are words: a probe with its output captured is still a probe
	{ command = "lune run p.luau 2>&1", rule = "unbounded" },
	{ command = "lune run p.luau &> out.log", rule = "unbounded" },
	-- more spellings of the program
	{ command = "timeout -s KILL 30 lune run x.luau", rule = "unbounded" },
	{ command = "sudo -u me lune run x.luau", rule = "unbounded" },
	{ command = "env -S 'lune run x.luau'", rule = "unbounded" },
	{ command = "cat <<EOF | bash\nlune run x.luau\nEOF", rule = "unbounded" },
	{ command = "perl -E 'sleep 5 while 1'", rule = "unbounded" },
	-- a job started with & in a foreground call, with nothing waiting for it
	{ command = "./zn run --time 600 -- z-nile/check.sh --full > log 2>&1 &", rule = "background" },
	{ command = "(sleep 1 &)", rule = "background" },
	{ command = "sleep 100 &", rule = "background" },
	-- background calls: later pipeline stages and redirections do not hide an unbounded command or a follow
	{ command = "./zn list 2>&1 | perl -e '1 while 1'", rule = "unbounded", ctx = { background = true } },
	{ command = "make build &> log", rule = "background", ctx = { background = true } },
	{ command = "tail -f log 2>&1", rule = "follow", ctx = { background = true } },
	-- a background call nothing bounds
	{ command = "make build", rule = "background", ctx = { background = true } },
	{ command = "cd d && ./build-everything.sh", rule = "background", ctx = { background = true } },
	-- a Monitor command is bounded by its timeout, but not its interpreters or detachers
	{ command = "lune run probe.luau", rule = "unbounded", ctx = { monitor = true } },
	{ command = "nohup sleep 9 &", rule = "detach", ctx = { monitor = true } },
	-- the recipe that looked safe: alarm stops the shim, and its tool child runs on, orphaned
	{ command = "perl -e 'alarm shift; exec @ARGV' 60 lune run p2.luau", rule = "alarm" },
}

-- Background calls that are the gate and its friends, with the redirections and pipes agents really write
local BACKGROUND_OK: { string } = {
	"z-nile/check.sh --full > .cache/full.log 2>&1",
	"cd /x/wt && z-nile/check.sh --affected 2>&1 | tail -20",
	"./zn check c0191 2>&1 | tail -5",
	"./zn land 2>&1",
	"./zn land 2>&1 | tail -4",
	"mkdir -p .cache && z-nile/check.sh --full > .cache/full.log 2>&1",
	"rm -f x; [[ -f y ]] && ./zn land 2>&1",
	"tail -3 land.log",
	"grep -q DONE full.log",
	"tr a b < f",
	'./zn land > land.log 2>&1; echo "exit=$?"; tail -3 land.log',
	"lune run tests/run -- tests/x 2>&1 | tee .cache/log",
	"./zn run --time 1200 -- sh -c 'until grep -q DONE full.log; do sleep 20; done'",
	-- a counted poll of gh with its jq, no command of the repository's own in it
	'H=$(git rev-parse HEAD); for i in $(seq 1 180); do s=$(gh pr view 166 --json headRefOid 2>/dev/null); sleep 30; done; echo "timeout $s"',
	"sleep 600 &> log",
	"cd d && echo started",
}

-- What a hook that knows its checkout and the call's folder says about the gate's tooling
local CHECKOUT = "/Users/me/code/pickman"
local TOOLING_CASES: { { command: string, cwd: string, ok: boolean } } = {
	{ command = "lune run tests/run -- a", cwd = CHECKOUT .. "/z-nile", ok = true },
	{ command = "lune run tests/run -- a", cwd = CHECKOUT .. "/.worktree/R1/pickman", ok = true },
	{ command = `lune run {CHECKOUT}/z-nile/tests/run -- a`, cwd = "/tmp", ok = true },
	{ command = `lune run {CHECKOUT}/.worktree/R1/z-nile/affected -- x`, cwd = "/tmp", ok = true },
	{ command = "lune run /tmp/x/z-nile/tests/run -- a", cwd = CHECKOUT, ok = false },
	{ command = "lune run tests/run -- a", cwd = "/tmp/scratch/cr4", ok = false },
	{ command = "lune run /tmp/scratch/cr4/z-nile/affected", cwd = CHECKOUT, ok = false },
	{ command = "cd /scratch && lune run tests/run", cwd = CHECKOUT .. "/z-nile", ok = false },
	{ command = "cd .. && lune run tests/run", cwd = CHECKOUT .. "/z-nile", ok = true },
	{ command = "cd ../.. && lune run tests/run", cwd = CHECKOUT .. "/z-nile", ok = false },
	{ command = "cd ~ && lune run tests/run", cwd = CHECKOUT .. "/z-nile", ok = false },
	{ command = 'cd "$X" && lune run tests/run', cwd = CHECKOUT .. "/z-nile", ok = false },
	{ command = "cd '/tmp/x' && lune run tests/run", cwd = CHECKOUT .. "/z-nile", ok = false },
	{ command = "lune run tests/run -- a; cd /tmp", cwd = CHECKOUT .. "/z-nile", ok = true },
	{ command = 'echo "cd /tmp" && lune run tests/run', cwd = CHECKOUT .. "/z-nile", ok = true },
}

local ALLOWED: { string } = {
	"python3 - 2>&1 <<E\nprint(1)\nE",
	"python3 - <<\\E\nprint(1)\nE",
	'echo "cd /tmp" && lune run tests/run',
	"lune run tests/run -- a; cd /tmp",
	"python3 - <<'E'\nprint('while True: pass')\nx = \"subprocess.run\"\nE",
	"python3 - <<'E'\ns = '''\nwhile True:\n'''\nprint(1)\nE",
	"python3 -c 'print(\"os.system\")'",
	"cat <<'E' | python3 -\nprint(1)\nE",
	"sleep 1 & wait",
	"(sleep 1 &) ; wait",
	"python3 - <<'EOF'\np='a.md'\ns=open(p).read()\nopen(p,'w').write(s.replace('a','b'))\nEOF",
	"cd pickman && python3 -I - <<'PY'\nprint(1)\nPY",
	"python3 -I -c 'import json;print(json.load(open(\"x\")))'",
	"python3 -c 'import subprocess; subprocess.run([\"x\"], timeout=5)'",
	"lune run --help",
	'echo "for ((;;))" > note',
	"./zn run --time 5 -- sh -c 'sleep 1 & sleep 2; wait'",
	"sleep 1 & sleep 2 & wait",
	"git log | while read l; do echo $l; done",
	"while IFS= read -r l; do echo $l; done < f",
	"for ((i=0;i<3;i++)); do echo $i; done",
	"lune run /Users/me/code/pickman/z-nile/tests/run -- a.spec.luau",
	"caffeinate -t 5 ls",
	"perl -ne 'print while <>' f",
	"yes | head -3",
	"caffeinate -i -t 300",
	"tail -n 5 full.log",
	"gh pr view 138 --json state",
	"for f in a b c; do echo $f; done",
	"",
	"ls -la",
	"./zn status c0191",
	"./zn run --time 60 -- lune run p2.luau",
	"/Users/x/pickman/zn run -- lune run p2.luau",
	"perl z-nile/lib/bounded.pl --time 5 -- lune run p2.luau",
	"cd pickman && lune run tests/run -- tests/unit/Maze",
	"lune run tests/run",
	"lune run ../z-nile/tests/run -- a.spec.luau",
	"lune run z-nile/affected -- z-nile/engine/main.luau",
	"lune run z-nile/roots -- --projects",
	"bash z-nile/check.sh --full",
	"z-nile/check.sh --affected",
	"bash .worktree/R0010/z-nile/.tracker/issues/c0191/check.sh",
	"lune --version",
	"lune setup",
	"python3 --version",
	"rojo build -o x.rbxl",
	"perl -e 'print 1'",
	"perl z-nile/lib/replace-file.pl dest",
	-- mentions, not commands
	"echo 'lune run p2.luau' > note.txt",
	'grep -rn "lune run" z-nile/skills',
	"git commit -m 'document lune run'",
	"cat <<EOF\nlune run p2.luau\nEOF",
	"# lune run p2.luau",
	-- unreadable text passes: the reaper is the backstop
	"echo 'unbalanced lune run",
	"echo ${",
}

local function hook(payload: string): sh.Result
	return sh.run("lune", { "run", "guard-bash" }, payload)
end

local function toolCall(command: string): string
	return serde.encode("json", { tool_name = "Bash", tool_input = { command = command } })
end

return t.spec("the hook that refuses unbounded commands", function(it)
	it("AC2: every command that starts an unbounded interpreter is refused, by the rule that fits", function()
		for _, c in REFUSED do
			local v = boundcmd.check(c.command, c.ctx)
			if v.ok or v.rule ~= c.rule then
				error(
					`{c.command}: expected refusal by {c.rule}, got {if v.ok then "ok" else tostring(v.rule)}`,
					0
				)
			end
		end
	end)

	it("AC2: the gate's own commands, the wrapper, mentions and unreadable text pass", function()
		for _, command in ALLOWED do
			local v = boundcmd.check(command)
			if not v.ok then
				error(`{command}: expected ok, refused by {tostring(v.rule)}`, 0)
			end
		end
	end)

	it("AC2: a refusal names the wrapper and the command to run, and the rule", function()
		local v = boundcmd.check("cd x && lune run p2.luau check a")
		local say = boundcmd.explain(v)
		t.expect(string.find(say, "./zn run --time 60 -- lune run p2.luau check a", 1, true) ~= nil)
			.toBe(true)
		t.expect(string.find(say, "(unbounded)", 1, true) ~= nil).toBe(true)
		local alarm = boundcmd.explain(boundcmd.check("perl -e 'alarm shift; exec @ARGV' 5 lune run a.luau"))
		t.expect(string.find(alarm, "orphaned", 1, true) ~= nil).toBe(true)
		t.expect(string.find(alarm, "./zn run", 1, true) ~= nil).toBe(true)
	end)

	it(
		"AC2: the hook entry refuses with exit 2 and the reason on stderr, from the tool call's JSON",
		function()
			local r = hook(toolCall("lune run p2.luau check a"))
			t.expect(r.code).toBe(2)
			t.expect(string.find(r.stderr, "./zn run --time 60 -- lune run p2.luau check a", 1, true) ~= nil)
				.toBe(true)
			t.expect(r.stdout).toBe("")
		end
	)

	it("AC2: the hook entry lets an allowed command through silently", function()
		local r = hook(toolCall("./zn run --time 5 -- lune run p2.luau"))
		t.expect(r.code).toBe(0)
		t.expect(r.stdout .. r.stderr).toBe("")
	end)

	it("AC2: the hook fails open: unreadable input, a missing or non-string command all exit 0", function()
		for _, payload in
			{
				"",
				"garbage",
				"[1,2]",
				"{}",
				'{"tool_input":{}}',
				'{"tool_input":{"command":5}}',
				'{"tool_input":"x"}',
			}
		do
			local r = hook(payload)
			if r.code ~= 0 then
				error(`payload {payload}: expected exit 0, got {r.code}: {r.stderr}`, 0)
			end
		end
	end)

	it(
		"AC2: scripts/hooks/pre-bash.sh runs the entry from its own checkout, whatever the session's folder",
		function()
			local script = `{ROOT}/scripts/hooks/pre-bash.sh`
			t.expect(fs.isFile(script)).toBe(true)
			local r = process.exec(
				"bash",
				{ script },
				{ cwd = "/", stdio = { stdin = toolCall("lune run p2.luau") } }
			)
			t.expect(r.code).toBe(2)
			local ok = process.exec(
				"bash",
				{ script },
				{ cwd = "/", stdio = { stdin = toolCall("./zn status") } }
			)
			t.expect(ok.code).toBe(0)
		end
	)

	it(
		"AC2: a Monitor command may loop and follow (its timeout ends it); a background call may be the gate or the wrapper",
		function()
			local monitor: boundcmd.Context = { monitor = true }
			for _, command in
				{
					"until grep -q DONE full.log; do sleep 20; done",
					"tail -f full.log",
					"gh run watch 123",
					"watch ls",
				}
			do
				local v = boundcmd.check(command, monitor)
				if not v.ok then
					error(`Monitor {command}: expected ok, refused by {tostring(v.rule)}`, 0)
				end
			end
			local background: boundcmd.Context = { background = true }
			for _, command in
				{
					"./zn run --time 600 -- sh -c 'until grep -q DONE full.log; do sleep 20; done'",
					"cd pickman && ./zn status",
					"z-nile/check.sh --full",
					"bash .worktree/R0010/z-nile/.tracker/issues/c0191/check.sh",
					"lune run tests/run -- tests/unit",
				}
			do
				local v = boundcmd.check(command, background)
				if not v.ok then
					error(`background {command}: expected ok, refused by {tostring(v.rule)}`, 0)
				end
			end
		end
	)

	it(
		"AC2: background calls that are the gate and its friends pass, with their redirections and pipes",
		function()
			for _, command in BACKGROUND_OK do
				local v = boundcmd.check(command, { background = true })
				if not v.ok then
					error(`background {command}: expected ok, refused by {tostring(v.rule)}`, 0)
				end
			end
		end
	)

	it(
		"AC2: the gate's tooling passes only in this checkout, by relative path from inside it or by absolute path",
		function()
			for _, c in TOOLING_CASES do
				local v = boundcmd.check(c.command, { checkout = CHECKOUT, cwd = c.cwd })
				if v.ok ~= c.ok then
					error(
						`{c.command} (from {c.cwd}): expected {if c.ok then "ok" else "refused"}, got {tostring(
							v.rule
						)}`,
						0
					)
				end
			end
		end
	)

	it(
		"AC2: the entry reads run_in_background and the Monitor tool from the call, and names the checkout's own zn",
		function()
			local function call(tool: string, command: string, background: boolean?): sh.Result
				local payload = serde.encode(
					"json",
					{ tool_name = tool, tool_input = { command = command, run_in_background = background } }
				)
				return sh.run(
					"env",
					{ "ZN_CHECKOUT=/Users/me/code/pickman", "lune", "run", "guard-bash" },
					payload
				)
			end
			local bg = call("Bash", "make build", true)
			t.expect(bg.code).toBe(2)
			t.expect(string.find(bg.stderr, "(background)", 1, true) ~= nil).toBe(true)
			t.expect(string.find(bg.stderr, "/Users/me/code/pickman/zn run --time", 1, true) ~= nil)
				.toBe(true)
			t.expect(call("Bash", "make build", false).code).toBe(0)
			t.expect(call("Bash", "./zn run --time 5 -- sleep 600", true).code).toBe(0)
			t.expect(call("Monitor", "until grep -q DONE x.log; do sleep 5; done", nil).code).toBe(0)
			t.expect(call("Monitor", "lune run probe.luau", nil).code).toBe(2)
			t.expect(call("Bash", "until grep -q DONE x.log; do sleep 5; done", nil).code).toBe(2)
		end
	)

	it(
		"AC2: .claude/settings.json runs the hook on Bash and Monitor and the reaper at SessionEnd with room to finish",
		function()
			local settings = serde.decode("json", fs.readFile(`{ROOT}/.claude/settings.json`)) :: any
			local pre = settings.hooks.PreToolUse
			t.expect(type(pre)).toBe("table")
			local found = false
			for _, group in pre do
				if group.matcher == "Bash|Monitor" then
					for _, h in group.hooks do
						if string.find(h.command, "scripts/hooks/pre-bash.sh", 1, true) then
							found = true
							-- a hook that hangs must not hold every Bash call for the default minute
							t.expect(h.timeout ~= nil and h.timeout >= 1 and h.timeout <= 10).toBe(true)
						end
					end
				end
			end
			t.expect(found).toBe(true)
			local ends = settings.hooks.SessionEnd
			t.expect(type(ends)).toBe("table")
			local timeout = 0
			for _, group in ends do
				for _, h in group.hooks do
					if string.find(h.command, "scripts/hooks/session-end.sh", 1, true) then
						timeout = h.timeout or 0
					end
				end
			end
			-- Claude Code's SessionEnd budget is 1.5 s unless the hook asks for more
			t.expect(timeout >= 10).toBe(true)
			for _, name in { "pre-bash.sh", "session-end.sh" } do
				local mode = process.exec("test", { "-x", `{ROOT}/scripts/hooks/{name}` })
				t.expect(mode.ok).toBe(true)
			end
			local allow = table.concat(settings.permissions.allow, "\n")
			-- the user's decision (2026-11-01, "Allow ./zn run"): the wrapper's prefix is allowed, so any wrapped command runs
			-- without a permission prompt; the reaper, which stops real processes, stays prompted
			t.expect(string.find(allow, "Bash(./zn run:*)", 1, true) ~= nil).toBe(true)
			t.expect(string.find(allow, "Bash(./zn reap", 1, true) ~= nil).toBe(false)
		end
	)
end)
