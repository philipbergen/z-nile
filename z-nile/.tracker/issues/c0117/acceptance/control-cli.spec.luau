--!strict
-- c0117 AC10: the dispatcher's control of a run, for real with fake CLIs (@tests/lib/fakecli): the chain stops at
-- questions.md and retry keeps the answers; `dispatch new` captures and chains; a review the author starts through the
-- dispatcher runs on its own CLI with the real git and its own state; the tracker's claims from inside a step reach
-- main through the publish broker; a push past the wrapper trips the wire; a step dies with its dispatcher, a dead
-- run is lost (never resumed or signalled), a live run is never dispatched twice, and `stop` signals only a group that
-- is still the run's; the merge gates come from the item's own walk. Fixture under .cache/c0117-control.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude", "grok", "agent"]

[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[z-ticket.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000

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
max_calls = 2

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000
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
local function mode(name: string, value: string?)
	fakecli.mode(h, name, value)
end
local function dirOf(id: string): string
	return `{h.f.main}/.cache/dispatch/{id}`
end
local function onOrigin(path: string): string
	return fixture.git(h.f.origin, { "show", `main:{path}` })
end
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

return t.spec("c0117 the dispatcher's control of a run", function(it)
	it("sets up a tracker with .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("c0117-control", {
			[".models.toml"] = MODELS,
			["tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
			["tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			["tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
			["tracker/issues/c0070/c0070.md"] = issue("c0070", "seventh-thing"),
			["tracker/issues/c0080/c0080.md"] = issue("c0080", "eighth-thing"),
			["tracker/issues/c0080/.models.toml"] = "[dispatch]\nauto_merge = []\n",
			["tracker/issues/c0090/c0090.md"] = issue("c0090", "ninth-thing"),
			["tracker/issues/c0090/.models.toml"] = 'order = ["agent"]\n',
		})
	end)

	it(
		"stops the chain at questions.md, starts nothing more, and retry keeps the answers and reruns",
		function()
			fakecli.clear(h)
			mode("claude", "questions")
			local r = zn({ "dispatch", "c0010" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "needs the user")).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			t.expect(zn({ "dispatch", "c0010" }).code).toBe(3)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			mode("claude", "ok")
			local retry = zn({ "dispatch", "retry", "c0010" })
			t.expect(fs.isFile(`{dirOf("c0010")}/answered-1.md`)).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(2)
			-- the fake claimed nothing: the chain stops instead of designing again
			t.expect(retry.code).toBe(1)
			t.expect(has(retry.stdout, "still new on origin/main")).toBe(true)
		end
	)

	it("captures a new issue (z-ticket), records its capture row, and chains into its design", function()
		fakecli.clear(h)
		mode("claude.z-ticket", "ticket")
		mode("claude.z-design", "questions")
		local r = zn({ "dispatch", "new", "a dispatched thing" })
		t.expect(r.code).toBe(3)
		local id = string.match(fakecli.log(h), "issues/(c%d%d%d%d)/") :: string
		t.expect(id ~= nil).toBe(true)
		t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1)
		t.expect(count(fakecli.log(h), "claude step=z-design mode=questions")).toBe(1)
		local rows = fakecli.rows(h, id) :: { any }
		t.expect(rows[1].phase).toBe("capture")
		t.expect(rows[1].model).toBe("claude-sonnet-5")
		t.expect(fs.isFile(`{dirOf(id)}/questions.md`)).toBe(true)
	end)

	it(
		"a review the author starts through the dispatcher runs on its own CLI, with the real git and its own state",
		function()
			fakecli.clear(h)
			-- the author ends up on grok (claude is out of quota for it); the review's own walk puts it on claude
			mode("claude.z-design", "quota")
			mode("grok.z-design", "author")
			mode("claude.zz-review", "reviewer")
			local r = zn({ "dispatch", "z-design", "c0020" })
			if not r.ok then
				error(r.stdout .. r.stderr .. fakecli.log(h))
			end
			local l = fakecli.log(h)
			t.expect(has(l, "gitstatus=0")).toBe(true)
			t.expect(has(l, "review=0")).toBe(true)
			local wt = `{h.f.main}/.worktree/prep-second-thing`
			t.expect(fs.isFile(`{wt}/tracker/issues/c0020/design-review-001.md`)).toBe(true)
			local rows = fakecli.rows(h, "c0020") :: { any }
			local review: any = nil
			for _, row in rows do
				if row.subject == "design-review-001" then
					review = row
				end
			end
			t.expect(review ~= nil).toBe(true)
			t.expect(review.model).toBe("claude-opus-5-5")
			t.expect(review.phase).toBe("design-review")
			-- the author's state is its own, and the review's sits beside it
			local author = fakecli.state(h, "c0020")
			t.expect(author.outcome).toBe("ok")
			t.expect(author.cli).toBe("grok")
			local nestedState = fakecli.state(h, "c0020", "zz-review-design-1")
			t.expect(nestedState.cli).toBe("claude")
			t.expect(nestedState.outcome).toBe("ok")
		end
	)

	it(
		"a claim from inside a step reaches main through the publish broker, and the tripwire stays quiet",
		function()
			fakecli.clear(h)
			mode("claude", "claim")
			local r = zn({ "dispatch", "z-design", "c0030" })
			if not r.ok then
				error(r.stdout .. r.stderr .. fakecli.log(h))
			end
			t.expect(has(fakecli.log(h), "claim=0")).toBe(true)
			t.expect(string.match(onOrigin("tracker/issues/c0030/c0030.md"), "\nstatus: preparing%-") ~= nil)
				.toBe(true)
			t.expect(#fakecli.state(h, "c0030").pushed).toBe(1)
		end
	)

	it(
		"a code push past the wrapper (the real git) trips the wire: exit 5, and the step's spend is kept",
		function()
			fakecli.clear(h)
			mode("claude", "tripwire")
			local r = zn({ "dispatch", "z-design", "c0040" })
			t.expect(r.code).toBe(5)
			t.expect(has(fakecli.log(h), "realpush=0")).toBe(true)
			local s = fakecli.state(h, "c0040")
			t.expect(s.outcome).toBe("tripwire")
			t.expect(has(s.detail, "code.lua")).toBe(true)
			t.expect((fakecli.rows(h, "c0040") :: { any })[1].tokens).toBe(123)
			-- the chain does not go on after it
			t.expect(zn({ "dispatch", "c0040" }).code).toBe(5)
		end
	)

	it(
		"a step dies with its dispatcher; the dead run is lost, never resumed, and retry takes it over",
		function()
			fakecli.clear(h)
			mode("claude", "orphan")
			local r = zn({ "dispatch", "z-design", "c0050" })
			t.expect(r.ok).toBe(false)
			t.expect(absentAfter(`{h.fakes}/grandchild-orphan`, 5)).toBe(true)
			local again = zn({ "dispatch", "z-design", "c0050" })
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stdout, "lost")).toBe(true)
			t.expect(fakecli.state(h, "c0050").outcome).toBe("lost")
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			mode("claude", "ok")
			t.expect(zn({ "dispatch", "retry", "c0050" }).ok).toBe(true)
			t.expect(fakecli.state(h, "c0050").outcome).toBe("ok")
		end
	)

	it("a live run is never dispatched twice", function()
		fakecli.clear(h)
		local dir = dirOf("c0060")
		fs.writeDir(dir)
		local holder = runner.holdLock(`{dir}/lock`)
		t.expect(holder ~= nil).toBe(true)
		local r = zn({ "dispatch", "z-design", "c0060" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "is being dispatched")).toBe(true)
		t.expect(fakecli.log(h)).toBe("");
		(holder :: any).stdin:close()
	end)

	it("stop signals only a group that is still the run's, and never a group id of 1", function()
		local dir = dirOf("c0060")
		local me =
			tonumber((string.gsub(process.exec("sh", { "-c", "echo $PPID" }).stdout, "%s+", ""))) :: number
		-- a group id that names a live process (this spec's own) whose run lock nobody holds: a stale state
		-- a group id of 1 with a held lock: never signalled (`kill -- -1` would signal every process of the user)
		local held = runner.holdLock(`{dir}/held.lock`)
		for _, run in
			{ { pgid = me, lockFile = `{dir}/nobody.lock` }, { pgid = 1, lockFile = `{dir}/held.lock` } }
		do
			fs.writeFile(
				`{dir}/state.json`,
				serde.encode("json", {
					id = "c0060",
					mode = "step",
					outcome = "running",
					run = run,
					history = {},
					pending = {},
				})
			)
			local r = zn({ "dispatch", "stop", "c0060" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "lost")).toBe(true)
			t.expect(fakecli.state(h, "c0060").outcome).toBe("lost")
		end
		(held :: any).stdin:close()
		-- this spec's own process (the stale group id above) is alive
		t.expect(process.exec("kill", { "-0", tostring(me) }).ok).toBe(true)
	end)

	it(
		"a cursor step stops after max_calls model calls, and a finished one records the real total",
		function()
			fakecli.clear(h)
			mode("agent", "calls")
			local r = zn({ "dispatch", "z-design", "c0090" })
			t.expect(r.ok).toBe(false)
			local s = fakecli.state(h, "c0090")
			t.expect(s.outcome).toBe("cap")
			t.expect(string.find(s.detail, "passed max_calls 2 at call 3", 1, true) ~= nil).toBe(true)
			fakecli.clear(h)
			local ok = zn({ "dispatch", "z-design", "c0090" })
			t.expect(ok.ok).toBe(true)
			local rows = fakecli.rows(h, "c0090")
			t.expect(rows ~= nil).toBe(true)
			local list = rows :: { any }
			t.expect(list[#list].tokens).toBe(300 + 9)
			t.expect(list[#list].model).toBe("claude-opus-5-5-high")
		end
	)

	it(
		"passes the prep gate only when the item's own walk allows it, and merges with the real gh itself",
		function()
			fakecli.clear(h)
			-- a GitHub-looking origin, rewritten to the fixture's own (the chain asks the fake gh about PRs)
			local url = "https://github.com/zn-fixture/c0117.git"
			fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			for _, slug in { "seventh-thing", "eighth-thing" } do
				fs.writeFile(
					`{h.fakes}/pr-prep-{slug}.json`,
					'{"number":7,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS"}]}'
				)
			end
			mode("claude", "claim")
			-- auto_merge = ["prep"] at the root: the dispatcher merges, then sees origin unchanged and stops
			local merged = zn({ "dispatch", "c0070" })
			t.expect(has(fakecli.log(h), "realgh pr merge 7 --squash")).toBe(true)
			t.expect(merged.code).toBe(1)
			t.expect(has(merged.stdout, "merged but origin/main does not show it")).toBe(true)
			-- an item-level auto_merge = [] wins: the chain waits at the gate, and nothing is merged
			fs.writeFile(
				`{h.fakes}/pr-prep-eighth-thing.json`,
				'{"number":8,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{"conclusion":"SUCCESS"}]}'
			)
			local waiting = zn({ "dispatch", "c0080" })
			t.expect(waiting.code).toBe(4)
			t.expect(has(waiting.stdout, "#8 waits for a merge")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge 8")).toBe(false)
		end
	)
end)
