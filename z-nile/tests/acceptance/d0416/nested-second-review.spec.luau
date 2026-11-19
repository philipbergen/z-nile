--!strict
-- d0416: a regression pin for what d0415 left untested. A second design review is refused before any reviewer starts,
-- whether dispatched directly or by an author's step (a real `./zn dispatch z-design`, whose fake CLI starts the review
-- as a headless author does); a first nested review starts its reviewer, so the refusal is about the second round, not
-- about nesting. The expected refusal is built by dispatch.filing, its one writer. Fake CLIs (@tests/lib/fakecli),
-- fixture under .cache/d0416-nested, about 15 s. It describes main as it is: it passes there.
local dispatch = require("@znile/engine/dispatch")
local dispatcher = require("@znile/engine/dispatcher")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
stall_seconds = 60
tool_seconds = 120

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []
]]

local ISSUES = "pickman/.tracker/issues"
local h: fakecli.Harness
local wt: string

-- what dispatch.filing says about an item whose folder holds design-review-001.md: the one writer of the refusal
local function refusalFor(id: string): string
	local f = dispatch.filing({
		mode = "design",
		dir = `{ISSUES}/{id}`,
		prefix = "design-review-",
		raftId = id,
		reviews = { ["design-review-001.md"] = "# Review\n" },
		grouped = nil,
	})
	return f.refusal or error("dispatch.filing no longer refuses a second review")
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
-- `./zn <args>` in the test worktree (a direct dispatch), with the fakes first on PATH
local function znIn(args: { string }, extra: { [string]: string }?): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		GH_TOKEN = "the-users-token",
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return fixture.exec(wt, "bash", argv, { env = env })
end
-- an author's step (the fake claude starts its review through the dispatcher, as the headless rule says), and a
-- reviewer that writes its review
local function authorAndReviewer()
	fakecli.clear(h)
	fakecli.mode(h, "claude.z-design", "waitreview")
	fakecli.mode(h, "claude.zz-review", "reviewer")
end
-- the nested run folders of an author's state folder, by number
local function nestedOf(id: string): { [number]: string }
	local out: { [number]: string } = {}
	local dir = `{dispatcher.homeAt(h.f.main)}/{id}`
	for _, name in fs.readDir(dir) do
		local k = tonumber(string.match(name, `^zz%-review%-design%-{id}%-(%d+)$`) or "")
		if k then
			out[k] = name
		end
	end
	return out
end

return t.spec("d0416 a second design review is refused before any reviewer, nested or not", function(it)
	it("sets up c0010, which holds design-review-001.md, and c0020, which holds no review", function()
		h = fakecli.new("d0416-nested", {
			[".models.toml"] = MODELS,
			[`{ISSUES}/c0010/c0010.md`] = trackerfix.stub("c0010", "one", "new-quiet-copper-falcon"),
			[`{ISSUES}/c0020/c0020.md`] = trackerfix.stub("c0020", "two", "new-quiet-copper-falcon"),
		})
		fakecli.advanceMain(h, {
			[`{ISSUES}/c0010/design-review-001.md`] = "# Review\n\nVerdict: approve\n",
		})
		fixture.git(h.f.main, { "fetch", "-q", "origin", "main" })
		wt = `{h.f.main}/.worktree/author`
		fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "author", wt, "origin/main" })
		wt = fixture.physical(wt) :: string
	end)

	it("(i) a direct second design review is refused before any CLI starts", function()
		authorAndReviewer()
		local r = znIn({ "dispatch", "zz-review", "c0010", "--mode", "design" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, refusalFor("c0010"))).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"(ii) the review an author's step starts, twice on one item, is refused each time at zero tokens",
		function()
			authorAndReviewer()
			for run = 1, 2 do
				local r = fakecli.zn(h, { "dispatch", "z-design", "c0010" })
				t.expect(fakecli.state(h, "c0010").outcome).toBe("ok") -- the author itself is fine
				t.expect(r.code).toBe(0)
				-- the nested run took a folder of its own each time: -1, then -2
				local nested = nestedOf("c0010")
				t.expect(nested[run] ~= nil).toBe(true)
				local s = fakecli.state(h, "c0010", nested[run])
				t.expect(s.outcome).toBe("failed")
				t.expect(s.tokens).toBe(0)
				t.expect(s.detail ~= nil and has(s.detail, refusalFor("c0010"))).toBe(true)
			end
			local nested = nestedOf("c0010")
			t.expect(nested[1]).toBe("zz-review-design-c0010-1")
			t.expect(nested[2]).toBe("zz-review-design-c0010-2")
			local log = fakecli.log(h)
			t.expect(count(log, "claude step=z-design")).toBe(2) -- both authors ran
			t.expect(has(log, "claude step=zz-review")).toBe(false) -- no reviewer ever started
			t.expect(has(log, "review=0")).toBe(false) -- each author's review command was refused
			t.expect(count(log, "review=")).toBe(2)
			t.expect(has(log, refusalFor("c0010"))).toBe(true) -- the author saw the refusal on its stderr
		end
	)

	it("(iii) a nested first design review on an item with no review starts its reviewer", function()
		authorAndReviewer()
		-- ZN_DISPATCH_DIR set, as an author's step sets it for a review it starts
		local parent = `{h.f.main}/.cache/dispatch/author-run`
		fs.writeDir(parent)
		local r = znIn({ "dispatch", "zz-review", "c0020", "--mode", "design" }, { ZN_DISPATCH_DIR = parent })
		t.expect(has(fakecli.log(h), "claude step=zz-review")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "there is no second round")).toBe(false)
		t.expect(fakecli.state(h, "author-run", "zz-review-design-c0020-1").outcome).toBe("ok")
	end)

	it("(iv) the same through a real author step: its nested review starts and ends ok", function()
		authorAndReviewer()
		local r = fakecli.zn(h, { "dispatch", "z-design", "c0020" })
		t.expect(r.code).toBe(0)
		local log = fakecli.log(h)
		t.expect(has(log, "claude step=zz-review")).toBe(true)
		t.expect(has(log, "review=0")).toBe(true)
		t.expect(has(log, "there is no second round")).toBe(false)
		local nested = nestedOf("c0020")
		t.expect(nested[1]).toBe("zz-review-design-c0020-1")
		t.expect(fakecli.state(h, "c0020", nested[1]).outcome).toBe("ok")
	end)
end)
