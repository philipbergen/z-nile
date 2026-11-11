--!strict
-- c0117 AC6: `./zn dispatch` runs one model step for real, with fake CLIs (@tests/lib/fakecli). It runs in its worktree
-- with the wrapper first on PATH, the agent's own token (never the user's) and a prompt that names its skill; it moves
-- down the CLI order only on a structured quota signal, kills the step's process group at the cap and on a stall
-- (a CLI's own wait message is quota; the model's words never are; a running tool call gets the tool limit), records
-- the step's tokens and model, and inside a check starts no CLI outside .cache. A dry run starts and writes nothing.
-- Fixture under .cache/c0117-dispatch.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude", "grok", "agent"]

[dispatch]
stall_seconds = 120
tool_seconds = 240

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
max_calls = 30
max_minutes = 60

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000

[zz-review.grok]
model = "grok-4.7"
effort = "xhigh"
rank = 4
runtime = "grok-cli"
max_tokens = 5000

[z-ready.claude]
model = "nobody"
rank = 1
runtime = "claude-cli"
max_tokens = 1
]]

local h: fakecli.Harness
local function issue(id: string, slug: string): string
	return trackerfix.stub(id, slug, "new-quiet-copper-falcon")
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
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
-- `./zn` from a worktree of the fixture (a review runs in its author's worktree, never the main checkout)
local function znIn(dir: string, args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
			GH_TOKEN = "the-users-token",
		},
	})
end
-- a fake reviewer: three seconds of work (so its wall minutes are over 0), then the review file
-- a fake reviewer under the dispatcher: three seconds of work (so its wall minutes are over 0), then its review in
-- its own state folder, which the dispatcher numbers into place (design review 009 F1: one landing for every mode)
local function reviewer()
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`sleep 3; printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
end
local function reviewNames(dir: string, prefix: string): { string }
	local out = {}
	for _, name in fs.readDir(dir) do
		if string.sub(name, 1, #prefix) == prefix then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end
local function recordLines(out: string): { string }
	local lines = {}
	for line in string.gmatch(out, "[^\n]+") do
		if string.sub(line, 1, 8) == "record: " then
			table.insert(lines, line)
		end
	end
	return lines
end
local function log(): string
	return fakecli.log(h)
end
local function mode(name: string, value: string?)
	fakecli.mode(h, name, value)
end
local function state(id: string): any
	return fakecli.state(h, id)
end
local function lastRow(id: string): any
	local rows = fakecli.rows(h, id)
	return rows and rows[#rows]
end
-- a bounded wait for a process to be gone: it ends the moment the process is, and runs long only when it never dies.
-- Gone means `kill -0` says "No such process": any other failure (a permission, a missing kill) is not a death. The
-- bound is wall-clock (os.time), so the polling commands' own cost under load is inside it, and the grandchild's
-- sleep (an hour) is far past any bound.
local function deadWithin(pid: string, seconds: number): boolean
	local started = os.time()
	while true do
		local r = process.exec("kill", { "-0", pid })
		if not r.ok and string.find(r.stderr, "No such process", 1, true) then
			return true
		end
		if os.time() - started >= seconds then
			return false
		end
		task.wait(0.1)
	end
end
-- the pid a fake's grandchild wrote before the step was killed
local function grandchildPid(name: string): string
	return (string.gsub(fs.readFile(`{h.fakes}/{name}.pid`), "%s+", ""))
end

return t.spec("c0117 ./zn dispatch runs one step with fake CLIs", function(it)
	it("sets up a tracker with .models.toml, issues, a closer .models.toml and the fake CLIs", function()
		h = fakecli.new("c0117-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
			["pickman/.tracker/issues/c0020/.models.toml"] = "[z-design.claude]\nmax_tokens = 1000\n",
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			-- the one issue whose cases test a stall keeps short limits (10 s, which a starved machine does not reach, against the fakes' 12 s quiet tool call and 20 s silences); every other case stalls only if it really does
			["pickman/.tracker/issues/c0040/.models.toml"] = "[dispatch]\nstall_seconds = 10\ntool_seconds = 30\n",
			["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["pickman/.tracker/issues/c0050/.models.toml"] = 'order = ["agent"]\n',
			["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
		})
		-- agent resolves outside .cache (a link to /bin/echo): the dispatcher must refuse to start it
		fs.removeFile(`{h.bin}/agent`)
		process.exec("ln", { "-s", "/bin/echo", `{h.bin}/agent` })
	end)

	it(
		"--dry-run prints each CLI it would try, in order, from the stacked files, and starts and writes nothing",
		function()
			local r = zn({ "dispatch", "z-design", "c0010", "--dry-run" })
			t.expect(r.ok).toBe(true)
			t.expect(string.split(string.gsub(r.stdout, "%s+$", ""), "\n")).toEqual({
				"step=z-design id=c0010 kind=model",
				"try=1 cli=claude runtime=claude-cli model=claude-opus-5-5 rank=3 max_tokens=5000",
				"try=2 cli=grok runtime=grok-cli model=grok-4.7-high rank=3 max_tokens=5000",
				"try=3 cli=agent runtime=cursor-cli model=claude-opus-5-5-high rank=3 max_tokens=5000 max_calls=30 max_minutes=60",
			})
			local closer = zn({ "dispatch", "z-design", "c0020", "--dry-run" })
			t.expect(
				has(
					closer.stdout,
					"try=1 cli=claude runtime=claude-cli model=claude-opus-5-5 rank=3 max_tokens=1000"
				)
			).toBe(true)
			local chain = zn({ "dispatch", "c0010", "--dry-run" })
			t.expect(has(chain.stdout, "next: z-design c0010")).toBe(true)
			t.expect(log()).toBe("")
			t.expect(fs.isDir(`{h.f.main}/.worktree/prep-first-thing`)).toBe(false)
			t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/c0010/state.json`)).toBe(false)
			t.expect(runner.held(`{h.f.main}/.cache/dispatch/c0010/lock`)).toBe(false)
		end
	)

	it("model files come from main, never the working tree: an uncommitted one is refused", function()
		fakecli.clear(h)
		local stray = `{h.f.main}/pickman/.tracker/issues/c0010/.models.toml`
		fs.writeFile(stray, "[z-design.claude]\nmax_tokens = 99999999\n")
		local r = zn({ "dispatch", "z-design", "c0010", "--dry-run" })
		fs.removeFile(stray)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "pickman/.tracker/issues/c0010/.models.toml is not committed")).toBe(true)
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
		"a model step runs in its worktree with the wrapper first and the agent's own token, and records its spend",
		function()
			fakecli.clear(h)
			local r = zn({ "dispatch", "z-design", "c0010" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			local l = log()
			t.expect(count(l, "claude step=z-design mode=ok")).toBe(1)
			t.expect(has(l, "grok step=")).toBe(false)
			local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
			t.expect(has(l, `cwd={wt}\n`)).toBe(true)
			t.expect(has(l, "--output-format stream-json --verbose --model claude-opus-5-5")).toBe(true)
			t.expect(has(l, "--permission-mode bypassPermissions --permission-prompts none")).toBe(true)
			t.expect(has(l, "`z-nile/skills/z-design/SKILL.md`")).toBe(true)
			t.expect(has(l, "Search with `./zn lessons <terms>`")).toBe(true)
			t.expect(has(l, "lessons --when design --full")).toBe(false)
			local main = fixture.physical(h.f.main) :: string
			t.expect(has(l, `dir={main}/.cache/dispatch/c0010\n`)).toBe(true)
			t.expect(has(l, `path0={main}/z-nile/bin\n`)).toBe(true)
			-- the agent's token, never the user's, and an empty gh configuration of the step's own
			t.expect(has(l, "token=fake-agent-token fake-agent-token\n")).toBe(true)
			t.expect(has(l, "the-users-token")).toBe(false)
			t.expect(has(l, `ghdir={main}/.cache/dispatch/c0010/gh\n`)).toBe(true)
			-- a broker folder of this run's own (review 002 F7)
			t.expect(has(l, `broker={main}/.cache/dispatch/c0010/broker\n`)).toBe(true)
			local row = lastRow("c0010")
			t.expect(row.tokens).toBe(100 + 20 + 3)
			t.expect(row.model).toBe("claude-opus-5-5")
			t.expect(row.phase).toBe("prep")
			t.expect(row.subject).toBe("dispatch z-design")
			-- the user's G13, 2026-10-25: "Dispatcher row 0 min": the step's own skill records its minutes
			t.expect(row.minutes).toBe(0)
			local s = state("c0010")
			t.expect(s.outcome).toBe("ok")
			t.expect(s.history[#s.history].tokens).toBe(123)
			-- the run lock is released at the end
			t.expect(runner.held(`{h.f.main}/.cache/dispatch/c0010/lock`)).toBe(false)
		end
	)

	-- the user's G13 reading, 2026-10-25: "Yes, reviewers keep minutes": no skill records a reviewer's minutes, so a
	-- review's rows carry its wall minutes (an author's rows record 0)
	it(
		"a code review prints one record: line for its author's commit, with the review's wall minutes, tokens and model, and writes no row",
		function()
			fakecli.clear(h)
			mode("claude.zz-review", "script")
			reviewer()
			local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
			local before = #(fakecli.rows(h, "c0010") or {})
			local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			local lines = recordLines(r.stdout)
			t.expect(#lines).toBe(1)
			t.expect(lines[1])
				.toBe('record: ./zn commit -m "c0010: review-001" --phase code-review --model claude-opus-5-5')
			t.expect(#(fakecli.rows(h, "c0010") or {})).toBe(before) -- the row is in the author's tree, not the dispatch branch
			t.expect(fs.isDir(`{wt}/pickman/.tracker/issues/c0010/spend.d`)).toBe(true)
			fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/review-001.md`)
			-- quota on claude, the review on grok: still one line, the model that wrote the review
			fakecli.clear(h)
			-- claude writes a review, spends 42 tokens, then reports quota (design review 007 F3, 009 F1): the line sums
			-- both attempts, and one review lands, numbered once
			mode("claude.zz-review", "scriptquota")
			mode("grok.zz-review", "script")
			reviewer()
			local q = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
			if not q.ok then
				error(q.stdout .. q.stderr)
			end
			local two = recordLines(q.stdout)
			t.expect(#two).toBe(1)
			t.expect(has(two[1], "--model grok-4.7-xhigh")).toBe(true) -- the reviewing model
			t.expect(has(two[1], "--tokens")).toBe(false)
			local hist = state("c0010").history
			t.expect(hist[#hist - 1].tokens).toBe(42)
			t.expect(hist[#hist - 1].tokens + hist[#hist].tokens).toBe(249)
			t.expect(has(two[1], '-m "c0010: review-001"')).toBe(true)
			t.expect(reviewNames(`{wt}/pickman/.tracker/issues/c0010`, "review-"))
				.toEqual({ "review-001.md" })
			fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/review-001.md`)
		end
	)

	it("a design review writes its own row with its wall minutes, and prints no record: line", function()
		fakecli.clear(h)
		mode("claude.zz-review", "script")
		reviewer()
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(#recordLines(r.stdout)).toBe(0)
		local row = lastRow("c0010")
		t.expect(row.subject).toBe("design-review-001")
		t.expect(row.phase).toBe("design-review")
		t.expect(row.model).toBe("claude-opus-5-5")
		t.expect(row.minutes).toBe(0)
		t.expect((row.wall or 0) > 0).toBe(true)
		t.expect(row.tokens).toBe(123)
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/design-review-001.md`)
		-- a fallthrough whose first attempt wrote a review: one file, numbered once, from the reviewing model
		fakecli.clear(h)
		mode("claude.zz-review", "scriptquota")
		mode("grok.zz-review", "script")
		reviewer()
		local q = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design" })
		local names = reviewNames(`{wt}/pickman/.tracker/issues/c0010`, "design-review-")
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/design-review-001.md`)
		if not q.ok then
			error(q.stdout .. q.stderr)
		end
		t.expect(names).toEqual({ "design-review-001.md" })
		local last = lastRow("c0010")
		t.expect(last.subject).toBe("design-review-001")
		t.expect(last.model).toBe("grok-4.7-xhigh")
	end)

	it(
		"a design or code reviewer that writes nothing fails the step; the row is written, or the line printed",
		function()
			local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
			local dir = `{wt}/pickman/.tracker/issues/c0010`
			fakecli.clear(h)
			mode("claude.zz-review", "script")
			fs.writeFile(`{h.fakes}/script.sh`, "sleep 3\n")
			local d = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design" })
			t.expect(d.ok).toBe(false)
			t.expect(state("c0010").outcome).toBe("failed")
			t.expect(has(state("c0010").detail, "the reviewer wrote no review")).toBe(true)
			t.expect(reviewNames(dir, "design-review-")).toEqual({})
			t.expect(lastRow("c0010").subject).toBe("dispatch zz-review")
			local c = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
			t.expect(c.ok).toBe(false)
			t.expect(reviewNames(dir, "review-")).toEqual({})
			local lines = recordLines(c.stdout)
			t.expect(#lines).toBe(1)
			t.expect(has(lines[1], '-m "c0010: dispatch zz-review"')).toBe(true)
		end
	)

	-- design review 008 F1: under the dispatcher a stream reviewer writes `$ZN_DISPATCH_DIR/review.md`, its own state
	-- folder; the dispatcher numbers it (the next free NNN of that issue in the raft's folder) and moves it into place
	local function inRaft(): (string, string, () -> ())
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		-- c0010 in raft R0090 (as in a raft worktree), uncommitted in this worktree only
		local raftDir = `{wt}/pickman/.tracker/rafts/R0090`
		fs.writeDir(raftDir)
		fs.writeFile(
			`{raftDir}/R0090.md`,
			"---\nid: R0090\ntype: chore\ntitle: demo\nslug: demo\nissues: [c0010, c0011]\ncreated: 2026-01-01\nstatus: active-a-b-c\n---\n\n# R0090\n"
		)
		local doc = `{wt}/pickman/.tracker/issues/c0010/c0010.md`
		local was = fs.readFile(doc)
		fs.writeFile(doc, (string.gsub(was, "\nraft:[^\n]*", "\nraft: R0090", 1)))
		return wt, raftDir, function()
			fs.writeFile(doc, was)
			fs.removeDir(raftDir)
		end
	end
	local function writesReview(extra: string?)
		fs.writeFile(
			`{h.fakes}/script.sh`,
			`sleep 3; printf '# Stream review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"; {extra or ""}\n`
		)
	end
	local function streamFiles(dir: string): { string }
		local out = {}
		for _, name in fs.readDir(dir) do
			if string.match(name, "^stream%-review") then
				table.insert(out, name)
			end
		end
		table.sort(out)
		return out
	end

	it(
		"a stream review: the dispatcher numbers its review.md into the raft's folder, and a second one is refused",
		function()
			fakecli.clear(h)
			mode("claude.zz-review", "script")
			writesReview()
			local wt, raftDir, restore = inRaft()
			local before = #(fakecli.rows(h, "c0010") or {})
			local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream" })
			local one = streamFiles(raftDir)
			local l1 = log()
			-- round 2: the lead committed round 1's review and its refute
			fs.writeFile(`{raftDir}/stream-refute-c0010-001.md`, "- F1: fixed\n")
			fakecli.clear(h) -- clears the modes and the script too
			mode("claude.zz-review", "script")
			writesReview()
			local r2 = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream" })
			local two = streamFiles(raftDir)
			local l2 = log()
			restore()
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(one).toEqual({ "stream-review-c0010-001.md" })
			local lines = recordLines(r.stdout)
			t.expect(#lines).toBe(1)
			t.expect(lines[1]).toBe(
				'record: ./zn commit -m "c0010: stream-review-001" --phase code-review --model claude-opus-5-5 --issue c0010'
			)
			t.expect(#(fakecli.rows(h, "c0010") or {})).toBe(before)
			-- the prompt names the stream's own worktree (the call site's argument, design review 008 F3)
			local main = fixture.physical(h.f.main) :: string
			t.expect(has(l1, `{main}/.worktree/ws-c0010`)).toBe(true)
			t.expect(has(l1, "previous round")).toBe(false)
			t.expect(r2.ok).toBe(false)
			t.expect(has(r2.stdout .. r2.stderr, "there is no second round")).toBe(true)
			t.expect(two).toEqual({ "stream-review-c0010-001.md" })
			t.expect(has(l2, "previous round")).toBe(false)
		end
	)

	it(
		"a stream reviewer that writes no review fails the step, and its spend line is still printed",
		function()
			fakecli.clear(h)
			mode("claude.zz-review", "script")
			fs.writeFile(`{h.fakes}/script.sh`, "sleep 3\n")
			local wt, raftDir, restore = inRaft()
			local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream" })
			local files = streamFiles(raftDir)
			restore()
			t.expect(r.ok).toBe(false)
			t.expect(files).toEqual({})
			local s = state("c0010")
			t.expect(s.outcome).toBe("failed")
			t.expect(has(s.detail, "the reviewer wrote no review")).toBe(true)
			local lines = recordLines(r.stdout)
			t.expect(#lines).toBe(1)
			t.expect(has(lines[1], '-m "c0010: dispatch zz-review"')).toBe(true)
			t.expect(has(lines[1], "--model")).toBe(true)
			t.expect(has(lines[1], "--tokens")).toBe(false)
			local hist = state("c0010").history
			t.expect(hist[#hist].tokens).toBe(0)
			t.expect(hist[#hist - 1].tokens).toBe(123)
		end
	)

	it(
		"a quota fallthrough lands one review, numbered once; the failed attempt's file is moved aside; another issue's file is never this one's",
		function()
			fakecli.clear(h)
			-- claude writes a review, spends 42 tokens, then reports quota; grok writes the review that counts, and
			-- also a stray file of another issue in the raft's folder
			mode("claude.zz-review", "scriptquota")
			mode("grok.zz-review", "script")
			writesReview('d=$(./zn find R0090); echo x > "$d/stream-review-c0011-001.md"')
			local wt, raftDir, restore = inRaft()
			local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream" })
			local files = streamFiles(raftDir)
			restore()
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(files).toEqual({ "stream-review-c0010-001.md", "stream-review-c0011-001.md" })
			local lines = recordLines(r.stdout)
			t.expect(#lines).toBe(1)
			t.expect(has(lines[1], '-m "c0010: stream-review-001"')).toBe(true)
			t.expect(has(lines[1], "--model grok-4.7-xhigh")).toBe(true)
			t.expect(has(lines[1], "--tokens")).toBe(false)
			t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/c0010/review-attempt-1.md`)).toBe(true)
		end
	)

	it("a raft review lands as design-review-NNN.md in the raft's own folder", function()
		fakecli.clear(h)
		mode("claude.zz-review", "script")
		reviewer()
		local wt, raftDir, restore = inRaft()
		local r = znIn(wt, { "dispatch", "zz-review", "R0090", "--mode", "raft" })
		local names = reviewNames(raftDir, "design-review-")
		restore()
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(names).toEqual({ "design-review-001.md" })
	end)

	-- design review 009 F3: the cleanup rules, each with a next writer that writes nothing
	it("a stale review.md from an earlier run never lands: a reviewer that writes nothing fails", function()
		fakecli.clear(h)
		mode("claude.zz-review", "script")
		fs.writeFile(`{h.fakes}/script.sh`, "sleep 3\n")
		local wt, raftDir, restore = inRaft()
		fs.writeDir(`{h.f.main}/.cache/dispatch/c0010`)
		fs.writeFile(`{h.f.main}/.cache/dispatch/c0010/review.md`, "# stale\n")
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream" })
		local files = streamFiles(raftDir)
		restore()
		t.expect(r.ok).toBe(false)
		t.expect(state("c0010").outcome).toBe("failed")
		t.expect(files).toEqual({})
	end)

	it("a failed attempt's review never lands: the next CLI writes nothing, and the step fails", function()
		fakecli.clear(h)
		mode("claude.zz-review", "scriptquota")
		-- grok in its default mode: it spends tokens and writes no review
		writesReview()
		local wt, raftDir, restore = inRaft()
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream" })
		local files = streamFiles(raftDir)
		restore()
		t.expect(r.ok).toBe(false)
		t.expect(state("c0010").outcome).toBe("failed")
		t.expect(files).toEqual({})
		t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/c0010/review-attempt-1.md`)).toBe(true)
		t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/c0010/review.md`)).toBe(false)
	end)

	it("with no agent credential, no CLI starts", function()
		fakecli.clear(h)
		local r = zn({ "dispatch", "z-design", "c0010" }, { ZN_AGENT_TOKEN_FILE = `{h.f.base}/none` })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "no agent credential")).toBe(true)
		t.expect(log()).toBe("")
	end)

	-- the user's G11, 2026-10-25: "Skip missing CLIs": a CLI that is not installed is skipped like quota, named on stderr
	it(
		"a CLI that is not installed is skipped, named on stderr, and the next one runs; none installed fails",
		function()
			fakecli.clear(h)
			fs.move(`{h.bin}/claude`, `{h.bin}/claude.off`)
			-- only the fakes and the system's tools on PATH: no real CLI of this machine stands in for the missing one
			local r = zn({ "dispatch", "z-design", "c0030" }, { PATH = `{h.bin}:/usr/bin:/bin` })
			fs.move(`{h.bin}/claude.off`, `{h.bin}/claude`)
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(has(r.stderr, "claude is not installed")).toBe(true)
			t.expect(has(r.stderr, "no CLI in the order")).toBe(false)
			t.expect(count(log(), "grok step=z-design mode=ok")).toBe(1)
			local s = state("c0030")
			t.expect(s.outcome).toBe("ok")
			t.expect(s.history[#s.history - 1].outcome).toBe("missing")
			t.expect(s.history[#s.history].outcome).toBe("ok")
			fakecli.clear(h)
			local none = zn({ "dispatch", "z-design", "c0030" }, { PATH = "/usr/bin:/bin" })
			t.expect(none.ok).toBe(false)
			t.expect(has(none.stderr, "claude is not installed")).toBe(true)
			t.expect(has(none.stderr, "grok is not installed")).toBe(true)
			t.expect(has(none.stderr, "no CLI in the order is installed")).toBe(true)
			t.expect(log()).toBe("")
			t.expect(state("c0030").outcome).toBe("failed")
		end
	)

	it(
		"a CLI on quota and the rest not installed: the outcome is quota and the message names both",
		function()
			fakecli.clear(h)
			mode("claude", "quota")
			fs.move(`{h.bin}/grok`, `{h.bin}/grok.off`)
			fs.move(`{h.bin}/agent`, `{h.bin}/agent.off`)
			local r = zn({ "dispatch", "z-design", "c0030" }, { PATH = `{h.bin}:/usr/bin:/bin` })
			fs.move(`{h.bin}/grok.off`, `{h.bin}/grok`)
			fs.move(`{h.bin}/agent.off`, `{h.bin}/agent`)
			t.expect(r.ok).toBe(false)
			t.expect(state("c0030").outcome).toBe("quota")
			t.expect(
				has(r.stderr, "no CLI in the order could run: claude on quota; grok, agent not installed")
			)
				.toBe(true)
			t.expect(has(r.stderr, "every CLI in the order failed on quota")).toBe(false)
			t.expect(has(r.stderr, "no CLI in the order is installed")).toBe(false)
		end
	)

	it("moves down the order when a CLI reports quota, and records the CLI that did the work", function()
		fakecli.clear(h)
		mode("claude", "quota")
		local r = zn({ "dispatch", "z-design", "c0020" })
		t.expect(r.ok).toBe(true)
		local l = log()
		t.expect(count(l, "claude step=z-design mode=quota")).toBe(1)
		t.expect(count(l, "grok step=z-design mode=ok")).toBe(1)
		t.expect(has(l, "-m grok-4.7")).toBe(true)
		t.expect(has(l, "--reasoning-effort high")).toBe(true)
		local s = state("c0020")
		t.expect(s.history[#s.history - 1].outcome).toBe("quota")
		t.expect(s.history[#s.history].outcome).toBe("ok")
		local row = lastRow("c0020")
		t.expect(row.model).toBe("grok-4.7-high")
		t.expect(row.tokens).toBe(207)
	end)

	it(
		"a failure that is not quota stops: the next CLI never starts; an exit 0 with no count fails",
		function()
			fakecli.clear(h)
			mode("claude", "fail")
			local r = zn({ "dispatch", "z-design", "c0030" })
			t.expect(r.code).toBe(1)
			t.expect(has(log(), "grok step=")).toBe(false)
			t.expect(state("c0030").outcome).toBe("failed")
			fakecli.clear(h)
			mode("claude", "nocount")
			local n = zn({ "dispatch", "z-design", "c0030" })
			t.expect(n.ok).toBe(false)
			t.expect(has(state("c0030").detail, "without a token count")).toBe(true)
			t.expect(has(log(), "grok step=")).toBe(false)
		end
	)

	it("kills the step's whole process group past max_tokens, and records what it spent", function()
		fakecli.clear(h)
		mode("claude", "cap")
		local r = zn({ "dispatch", "z-design", "c0030" })
		t.expect(r.ok).toBe(false)
		local s = state("c0030")
		t.expect(s.outcome).toBe("cap")
		t.expect(s.history[#s.history].tokens > 5000).toBe(true)
		t.expect(has(log(), "grok step=")).toBe(false)
		t.expect(deadWithin(grandchildPid("grandchild-cap"), 60)).toBe(true)
		t.expect(lastRow("c0030").tokens > 5000).toBe(true)
	end)

	it(
		"a stall after the CLI's own wait message is quota; after the model's words, or none, it is a stall",
		function()
			fakecli.clear(h)
			mode("claude", "wait")
			t.expect(zn({ "dispatch", "z-design", "c0040" }).ok).toBe(true)
			t.expect(count(log(), "grok step=z-design mode=ok")).toBe(1)
			local s = state("c0040")
			t.expect(s.history[#s.history - 1].outcome).toBe("quota")
			for _, m in { "prose", "stall" } do
				fakecli.clear(h)
				mode("claude", m)
				local st = zn({ "dispatch", "z-design", "c0040" })
				t.expect(st.ok).toBe(false)
				t.expect(state("c0040").outcome).toBe("stalled")
				t.expect(has(log(), "grok step=")).toBe(false)
			end
		end
	)

	it("a tool call quiet past the stall limit is not killed before the tool limit", function()
		fakecli.clear(h)
		mode("claude", "tool")
		local r = zn({ "dispatch", "z-design", "c0040" })
		t.expect(r.ok).toBe(true)
		local s = state("c0040")
		t.expect(s.outcome).toBe("ok")
		-- the step took over twelve seconds of wall time, yet the dispatcher's row records 0 minutes (the user's G13)
		t.expect(s.history[#s.history].minutes > 0).toBe(true)
		t.expect(lastRow("c0040").minutes).toBe(0)
	end)

	it("dispatch stop kills the running step's group, and retry reruns the same step", function()
		fakecli.clear(h)
		mode("claude", "stop")
		local r = zn({ "dispatch", "z-design", "c0060" }, { FAKE_STOP = "c0060" })
		t.expect(r.ok).toBe(false)
		t.expect(state("c0060").outcome).toBe("stopped")
		t.expect(deadWithin(grandchildPid("grandchild-stop"), 60)).toBe(true)
		mode("claude", "ok")
		local retry = zn({ "dispatch", "retry", "c0060" })
		t.expect(retry.ok).toBe(true)
		t.expect(state("c0060").outcome).toBe("ok")
		t.expect(count(log(), "claude step=z-design")).toBe(2)
	end)

	it("an agent's git and gh refuse a code push to main and a merge, before the real gh runs", function()
		fakecli.clear(h)
		mode("claude", "push")
		local before = fixture.git(h.f.origin, { "rev-parse", "main" })
		local r = zn({ "dispatch", "z-design", "c0060" })
		t.expect(r.ok).toBe(true)
		local l = log()
		t.expect(has(l, "push=1")).toBe(true)
		t.expect(has(l, "notes.txt is not tracker state")).toBe(true)
		t.expect(has(l, "merge=1")).toBe(true)
		t.expect(has(l, "realgh pr merge")).toBe(false)
		t.expect(fixture.exec(h.f.origin, "git", { "cat-file", "-e", "main:notes.txt" }).ok).toBe(false)
		-- the agent's push was refused, and spend commits on the dispatcher's branch without pushing
		t.expect(fixture.git(h.f.origin, { "rev-list", "--count", `{before}..main` })).toBe("0")
	end)

	it("inside a check, refuses a CLI whose real path is not under .cache, before it starts", function()
		fakecli.clear(h)
		local r = zn({ "dispatch", "z-design", "c0050" }, { PICKMAN_FENCE_SPECS = "1" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "refusing to start agent")).toBe(true)
		local s = state("c0050")
		t.expect(has(s.history[#s.history].detail, "only a CLI under this checkout's .cache")).toBe(true)
		t.expect(s.history[#s.history].tokens).toBe(0)
		t.expect(has(r.stdout, "on agent")).toBe(false)
		t.expect(lastRow("c0050")).toBe(nil)
	end)
end)
