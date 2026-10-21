--!strict
-- c0117 AC9 to AC13: `./zn dispatch` for real, with fake CLIs. A model step runs in its worktree with the wrapper
-- first on PATH and a prompt that names its skill; the dispatcher moves down the CLI order only on quota, kills the
-- step's process group at the cap, on a stall and on `dispatch stop`, records the step's tokens and model, stops the
-- chain at questions.md, and starts no CLI outside .cache inside a check. Fixture under .cache/c0117-dispatch; the
-- fakes (shell scripts in its bin/) print the stream lines each CLI prints and act as the mode file
-- `<fakes>/<cli>.<step>` (or `<fakes>/<cli>`) says. No real CLI and no network: every CLI name resolves to a fake
-- under .cache, and a CLI that resolves anywhere else is refused (the last cases pin that).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude", "grok", "agent"]

[dispatch]
stall_seconds = 2

[z-design.claude]
model = "claude-opus-5-5"
rank = 3
runtime = "claude-cli"
max_tokens = 5000

[z-design.grok]
model = "grok-4.7"
effort = "high"
rank = 3
runtime = "grok-cli"
max_tokens = 5000

[z-design.agent]
model = "claude-opus-5-5-high"
rank = 3
runtime = "cursor-cli"
max_tokens = 5000

[z-ticket.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000

[z-ready.claude]
model = "nobody"
rank = 1
runtime = "claude-cli"
max_tokens = 1
]]

-- One fake CLI: logs how it was started, then prints what the mode asks for in its own stream format.
local function fake(cli: string): string
	local ok = ({
		claude = [[echo '{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":5000,"output_tokens":3},"content":[{"type":"text","text":"ok"}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"modelUsage":{"m":{"inputTokens":100,"cacheCreationInputTokens":20,"cacheReadInputTokens":5000,"outputTokens":3}}}']],
		grok = [[echo '{"type":"usage","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":900,"output_tokens":7}}'
echo '{"type":"end","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":900,"output_tokens":7}}']],
		agent = [[echo '{"type":"result","subtype":"success","is_error":false,"usage":{"inputTokens":300,"outputTokens":9,"cacheReadTokens":0,"cacheWriteTokens":0}}']],
	})[cli]
	local quota = if cli == "claude"
		then [[echo '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","rateLimitType":"five_hour","resetsAt":1}}'; sleep 20]]
		else [[echo "Error: rate limit exceeded (too many requests)" >&2; exit 1]]
	local heavy = if cli == "claude"
		then [[echo "{\"type\":\"assistant\",\"message\":{\"id\":\"m$i\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":1}}}"]]
		else [[echo "{\"type\":\"usage\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":1}}"]]
	return table.concat({
		"#!/bin/sh",
		'step=$(printf "%s" "$*" | sed -n "s/.*z-nile step \\([a-z-]*\\).*/\\1/p" | head -n 1)',
		'mode=ok; [ -f "$FAKE_DIR/' .. cli .. '" ] && mode=$(cat "$FAKE_DIR/' .. cli .. '")',
		'[ -f "$FAKE_DIR/' .. cli .. '.$step" ] && mode=$(cat "$FAKE_DIR/' .. cli .. '.$step")',
		'{ echo "'
			.. cli
			.. ' step=$step mode=$mode cwd=$(pwd -P)"; echo "args=$*"; echo "dir=$ZN_DISPATCH_DIR"; echo "path0=${PATH%%:*}"; } >> "$FAKE_DIR/log"',
		'case "$mode" in',
		"ok) " .. ok .. " ;;",
		"quota) " .. quota .. " ;;",
		'fail) echo "boom" >&2; exit 1 ;;',
		"nocount) echo 'not json'; exit 0 ;;",
		'questions) printf "## Q1\\nWhich scope?\\n" > "$ZN_DISPATCH_DIR/questions.md"; ' .. ok .. " ;;",
		'cap) i=0; ( sleep 2; touch "$FAKE_DIR/grandchild-cap" ) & while [ $i -lt 20 ]; do '
			.. heavy
			.. "; i=$((i+1)); done; sleep 20 ;;",
		"wait) echo 'Usage limit reached, retrying in 60s'; sleep 20 ;;",
		"stall) echo 'thinking'; sleep 20 ;;",
		'stop) ( sleep 2; touch "$FAKE_DIR/grandchild-stop" ) & echo \'{"type":"system"}\'; sleep 0.5; ./zn dispatch stop "$FAKE_STOP" >> "$FAKE_DIR/log" 2>&1; sleep 20 ;;',
		'ticket) ( while :; do echo \'{"type":"system"}\'; sleep 0.5; done ) & hb=$!; ./zn new issue c dispatched-thing --desc \'from the fake\' >> "$FAKE_DIR/log" 2>&1; kill $hb; '
			.. ok
			.. " ;;",
		"push) echo note > notes.txt; git add notes.txt; git -c user.name=c0117-dispatch -c user.email=c0117-dispatch@example.invalid commit -q -m note; "
			.. 'git push -q origin HEAD:main 2>> "$FAKE_DIR/log"; echo "push=$?" >> "$FAKE_DIR/log"; gh pr merge 7 --squash 2>> "$FAKE_DIR/log"; echo "merge=$?" >> "$FAKE_DIR/log"; '
			.. ok
			.. " ;;",
		"esac",
		"",
	}, "\n")
end

local f: trackerfix.Fixture
local fakes, bin = "", ""
local function issue(id: string, slug: string): string
	return trackerfix.stub(id, slug, "new-quiet-copper-falcon")
end
local function mode(name: string, value: string?)
	local p = `{fakes}/{name}`
	if value then
		fs.writeFile(p, value)
	elseif fs.isFile(p) then
		fs.removeFile(p)
	end
end
local function clearModes()
	for _, name in fs.readDir(fakes) do
		if name ~= "log" then
			fs.removeFile(`{fakes}/{name}`)
		end
	end
	if fs.isFile(`{fakes}/log`) then
		fs.removeFile(`{fakes}/log`)
	end
end
local function env(extra: { [string]: string }?): { [string]: string }
	local e: { [string]: string } = { FAKE_DIR = fakes, PATH = `{bin}:{process.env.PATH}` }
	local more_extra: { [string]: any } = extra or {}
	for k, v in more_extra do
		e[k] = v
	end
	return e
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(f.main, "bash", argv, { env = env(extra) })
end
local function log(): string
	return if fs.isFile(`{fakes}/log`) then fs.readFile(`{fakes}/log`) else ""
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(text, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local function state(id: string): any
	return serde.decode("json", fs.readFile(`{f.main}/.cache/dispatch/{id}/state.json`))
end
local function lastRow(id: string): ledger.Row?
	local r = fixture.exec(f.origin, "git", { "show", `main:tracker/issues/{id}/spend.md` })
	if not r.ok then
		return nil
	end
	local l = ledger.parse(r.stdout .. "\n") :: ledger.Ledger
	return l.rows[#l.rows]
end
-- a bounded wait for a file a fake's grandchild would write, so its absence means it was killed
local function absentAfter(path: string, seconds: number): boolean
	local waited = 0
	while waited < seconds do
		if fs.isFile(path) then
			return false
		end
		waited += task.wait(0.1)
	end
	return not fs.isFile(path)
end

return t.spec("c0117 ./zn dispatch with fake CLIs", function(it)
	it("sets up a tracker with .models.toml, issues, a closer .models.toml and the fake CLIs", function()
		f = trackerfix.new("c0117-dispatch", {
			[".models.toml"] = MODELS,
			["tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
			["tracker/issues/c0020/.models.toml"] = "[z-design.claude]\nmax_tokens = 1000\n",
			["tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			["tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["tracker/issues/c0050/.models.toml"] = 'order = ["agent"]\n',
			["tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
		})
		bin = `{f.base}/bin`
		fakes = `{f.base}/fakes`
		fs.writeDir(bin)
		fs.writeDir(fakes)
		for _, cli in { "claude", "grok" } do
			fs.writeFile(`{bin}/{cli}`, fake(cli))
			process.exec("chmod", { "+x", `{bin}/{cli}` })
		end
		-- agent resolves outside .cache (a link to /bin/echo): the dispatcher must refuse to start it
		process.exec("ln", { "-s", "/bin/echo", `{bin}/agent` })
		fs.writeFile(`{bin}/gh`, '#!/bin/sh\necho "real gh $*" >> "$FAKE_DIR/log"\n')
		process.exec("chmod", { "+x", `{bin}/gh` })
	end)

	it("--dry-run prints each CLI it would try, in order, from the stacked files, and starts nothing", function()
		local r = zn({ "dispatch", "z-design", "c0010", "--dry-run" })
		t.expect(r.ok).toBe(true)
		t.expect(string.split(string.gsub(r.stdout, "%s+$", ""), "\n")).toEqual({
			"step=z-design id=c0010 kind=model",
			"try=1 cli=claude runtime=claude-cli model=claude-opus-5-5 rank=3 max_tokens=5000",
			"try=2 cli=grok runtime=grok-cli model=grok-4.7-high rank=3 max_tokens=5000",
			"try=3 cli=agent runtime=cursor-cli model=claude-opus-5-5-high rank=3 max_tokens=5000",
		})
		local closer = zn({ "dispatch", "z-design", "c0020", "--dry-run" })
		t.expect(has(closer.stdout, "try=1 cli=claude runtime=claude-cli model=claude-opus-5-5 rank=3 max_tokens=1000"))
			.toBe(true)
		t.expect(has(closer.stdout, "cli=grok runtime=grok-cli model=grok-4.7-high rank=3 max_tokens=5000")).toBe(true)
		local chain = zn({ "dispatch", "c0010", "--dry-run" })
		t.expect(has(chain.stdout, "next: z-design c0010")).toBe(true)
		t.expect(log()).toBe("")
	end)

	it("a script step runs ./zn itself and never takes a model, whatever .models.toml says", function()
		local r = zn({ "dispatch", "z-ready", "R0090", "--dry-run" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "kind=script")).toBe(true)
		t.expect(has(r.stdout, "run=./zn ready R0090")).toBe(true)
		t.expect(has(r.stdout, "model=")).toBe(false)
		local bad = zn({ "dispatch", "zz-rules", "c0010" })
		t.expect(bad.ok).toBe(false)
		t.expect(has(bad.stderr, "not a step")).toBe(true)
	end)

	it(
		"a model step runs in its prep worktree with the wrapper first, names its skill, records tokens and model",
		function()
			clearModes()
			local r = zn({ "dispatch", "z-design", "c0010" })
			t.expect(r.ok).toBe(true)
			local l = log()
			t.expect(count(l, "claude step=z-design mode=ok")).toBe(1)
			t.expect(has(l, "grok step=")).toBe(false)
			local wt = fixture.physical(`{f.main}/.worktree/prep-first-thing`) :: string
			t.expect(has(l, `cwd={wt}\n`)).toBe(true)
			t.expect(has(l, "--output-format stream-json --verbose --model claude-opus-5-5")).toBe(true)
			t.expect(has(l, "--permission-mode bypassPermissions --permission-prompts none")).toBe(true)
			t.expect(has(l, "`z-nile/skills/z-design/SKILL.md`")).toBe(true)
			t.expect(has(l, "`./zn lessons --when design --full`")).toBe(true)
			t.expect(has(l, `dir={fixture.physical(f.main)}/.cache/dispatch/c0010\n`)).toBe(true)
			t.expect(has(l, `path0={fixture.physical(f.main)}/z-nile/bin\n`)).toBe(true)
			local row = lastRow("c0010") :: ledger.Row
			t.expect(row.tokens).toBe(100 + 20 + 3)
			t.expect(row.model).toBe("claude-opus-5-5")
			t.expect(row.phase).toBe("prep")
			t.expect(row.subject).toBe("dispatch z-design")
			local s = state("c0010")
			t.expect(s.outcome).toBe("ok")
			t.expect(s.cli).toBe("claude")
			t.expect(s.history[#s.history].tokens).toBe(123)
		end
	)

	it("moves down the order when a CLI fails on quota, and records the CLI that did the work", function()
		clearModes()
		mode("claude", "quota")
		local r = zn({ "dispatch", "z-design", "c0020" })
		t.expect(r.ok).toBe(true)
		local l = log()
		t.expect(count(l, "claude step=z-design mode=quota")).toBe(1)
		t.expect(count(l, "grok step=z-design mode=ok")).toBe(1)
		t.expect(has(l, "--cwd ")).toBe(true)
		t.expect(has(l, "-m grok-4.7")).toBe(true)
		t.expect(has(l, "--reasoning-effort high")).toBe(true)
		local s = state("c0020")
		t.expect(s.history[#s.history - 1].outcome).toBe("quota")
		t.expect(s.history[#s.history].outcome).toBe("ok")
		local row = lastRow("c0020") :: ledger.Row
		t.expect(row.model).toBe("grok-4.7-high")
		t.expect(row.tokens).toBe(207)
	end)

	it("a failure that is not quota stops: the next CLI never starts", function()
		clearModes()
		mode("claude", "fail")
		local r = zn({ "dispatch", "z-design", "c0030" })
		t.expect(r.ok).toBe(false)
		t.expect(r.code).toBe(1)
		t.expect(has(log(), "grok step=")).toBe(false)
		t.expect(state("c0030").outcome).toBe("failed")
		-- an exit 0 with no token count is a failure too
		clearModes()
		mode("claude", "nocount")
		local n = zn({ "dispatch", "z-design", "c0030" })
		t.expect(n.ok).toBe(false)
		t.expect(has(state("c0030").detail, "without a token count")).toBe(true)
		t.expect(has(log(), "grok step=")).toBe(false)
	end)

	it("kills the step's whole process group past max_tokens, and records what it spent", function()
		clearModes()
		mode("claude", "cap")
		local r = zn({ "dispatch", "z-design", "c0030" })
		t.expect(r.ok).toBe(false)
		local s = state("c0030")
		t.expect(s.outcome).toBe("cap")
		t.expect(s.history[#s.history].tokens > 5000).toBe(true)
		t.expect(has(log(), "grok step=")).toBe(false)
		t.expect(absentAfter(`{fakes}/grandchild-cap`, 3)).toBe(true)
		t.expect((lastRow("c0030") :: ledger.Row).tokens > 5000).toBe(true)
	end)

	it("a CLI never waits for quota: a stall after a wait message is quota, any other stall is a failure", function()
		clearModes()
		mode("claude", "wait")
		local r = zn({ "dispatch", "z-design", "c0040" })
		t.expect(r.ok).toBe(true)
		t.expect(count(log(), "grok step=z-design mode=ok")).toBe(1)
		local s = state("c0040")
		t.expect(s.history[#s.history - 1].outcome).toBe("quota")
		clearModes()
		mode("claude", "stall")
		local st = zn({ "dispatch", "z-design", "c0040" })
		t.expect(st.ok).toBe(false)
		t.expect(state("c0040").outcome).toBe("stalled")
		t.expect(has(log(), "grok step=")).toBe(false)
	end)

	it("stops the chain at questions.md, starts nothing more, and retry keeps the answers and reruns", function()
		clearModes()
		mode("claude", "questions")
		local r = zn({ "dispatch", "c0010" })
		t.expect(r.code).toBe(3)
		t.expect(has(r.stdout, "needs the user")).toBe(true)
		t.expect(fs.isFile(`{f.main}/.cache/dispatch/c0010/questions.md`)).toBe(true)
		t.expect(count(log(), "claude step=z-design")).toBe(1)
		local again = zn({ "dispatch", "c0010" })
		t.expect(again.code).toBe(3)
		t.expect(count(log(), "claude step=z-design")).toBe(1)
		mode("claude", "ok")
		local retry = zn({ "dispatch", "retry", "c0010" })
		t.expect(fs.isFile(`{f.main}/.cache/dispatch/c0010/answered-1.md`)).toBe(true)
		t.expect(fs.isFile(`{f.main}/.cache/dispatch/c0010/questions.md`)).toBe(false)
		t.expect(count(log(), "claude step=z-design")).toBe(2)
		-- the fake claimed nothing: the chain stops instead of designing again
		t.expect(retry.code).toBe(1)
		t.expect(has(retry.stdout, "still new on origin/main")).toBe(true)
	end)

	it("captures a new issue (z-ticket), records its capture row, and chains into its design", function()
		clearModes()
		mode("claude.z-ticket", "ticket")
		mode("claude.z-design", "questions")
		local r = zn({ "dispatch", "new", "a dispatched thing" })
		t.expect(r.code).toBe(3)
		local id = string.match(log(), "issues/(c%d%d%d%d)/") :: string
		t.expect(id ~= nil).toBe(true)
		t.expect(count(log(), "claude step=z-ticket mode=ticket")).toBe(1)
		t.expect(count(log(), "claude step=z-design mode=questions")).toBe(1)
		local text = fixture.git(f.origin, { "show", `main:tracker/issues/{id}/spend.md` }) .. "\n"
		local rows = (ledger.parse(text) :: ledger.Ledger).rows
		t.expect(rows[1].phase).toBe("capture")
		t.expect(rows[1].model).toBe("claude-sonnet-5")
		t.expect(rows[#rows].phase).toBe("prep")
		t.expect(fs.isFile(`{f.main}/.cache/dispatch/{id}/questions.md`)).toBe(true)
	end)

	it("dispatch stop kills the running step's group, and retry reruns the same step", function()
		clearModes()
		mode("claude", "stop")
		local r = zn({ "dispatch", "z-design", "c0060" }, { FAKE_STOP = "c0060" })
		t.expect(r.ok).toBe(false)
		t.expect(state("c0060").outcome).toBe("stopped")
		t.expect(absentAfter(`{fakes}/grandchild-stop`, 3)).toBe(true)
		mode("claude", "ok")
		local retry = zn({ "dispatch", "retry", "c0060" })
		t.expect(retry.ok).toBe(true)
		t.expect(state("c0060").outcome).toBe("ok")
		t.expect(count(log(), "claude step=z-design")).toBe(2)
	end)

	it("an agent's git and gh refuse a code push to main and an unauthorised merge", function()
		clearModes()
		mode("claude", "push")
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local r = zn({ "dispatch", "z-design", "c0060" })
		t.expect(r.ok).toBe(true)
		local l = log()
		t.expect(has(l, "push=1")).toBe(true)
		t.expect(has(l, "notes.txt is not tracker state")).toBe(true)
		t.expect(has(l, "merge=1")).toBe(true)
		t.expect(has(l, "real gh pr merge")).toBe(false)
		t.expect(fixture.exec(f.origin, "git", { "cat-file", "-e", "main:notes.txt" }).ok).toBe(false)
		-- only the dispatcher's own spend row reached main
		t.expect(fixture.git(f.origin, { "rev-list", "--count", `{before}..main` })).toBe("1")
	end)

	it("inside a check, refuses a CLI whose real path is not under .cache, before it starts", function()
		clearModes()
		local r = zn({ "dispatch", "z-design", "c0050" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "refusing to start agent")).toBe(true)
		local s = state("c0050")
		t.expect(has(s.history[#s.history].detail, "only a CLI under this checkout's .cache")).toBe(true)
		t.expect(s.history[#s.history].tokens).toBe(0)
		t.expect(has(r.stdout, "on agent")).toBe(false)
		t.expect(lastRow("c0050")).toBe(nil)
	end)
end)
