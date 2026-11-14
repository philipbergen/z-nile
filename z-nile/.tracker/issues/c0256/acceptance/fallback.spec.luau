--!strict
-- c0256 AC13 (found by design review 007, F3), for real with fake CLIs (@tests/lib/fakecli): a role's fallback CLI
-- (#299: the next CLI also takes over a plain failure) never re-runs a z-ticket that already acted. An attempt that
-- pushed its issue, or left a questions.md, ends the step's tries: the capture is not made twice and the question is
-- the exchange's, asked by z-ticket. Fixture under .cache/c0256-fallback, whose idea role has a grok fallback.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.idea]
model = "claude-sonnet-5"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 5000
fallbacks = ["grok"]

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
fallbacks = []

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
fallbacks = []

[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
fallbacks = []

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []

[roles.final-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []
]]

local h: fakecli.Harness
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
local function zn(args: { string }): fixture.Result
	return fakecli.zn(h, args)
end
local function mode(name: string, value: string?)
	fakecli.mode(h, name, value)
end
local function dirOf(id: string): string
	return `{h.f.main}/.cache/dispatch/{id}`
end
local function exchangeOf(id: string): string
	local dir = `{dirOf(id)}/exchange`
	if not fs.isDir(dir) then
		return ""
	end
	local names = fs.readDir(dir)
	table.sort(names)
	return table.concat(names, ",")
end
-- how many issues origin's main holds
local function originIssues(): number
	local r = process.exec("git", { `--git-dir={h.f.origin}`, "ls-tree", "-r", "--name-only", "main" })
	local n = 0
	for _, path in string.split(r.stdout, "\n") do
		if string.match(path, "/issues/c%d+/c%d+%.md$") then
			n += 1
		end
	end
	return n
end

return t.spec("c0256 AC13: a role's fallback CLI does not re-run a z-ticket that already acted", function(it)
	it("sets up a tracker with .models.toml (idea falls back to grok) and the fake CLIs", function()
		h = fakecli.new("c0256-fallback", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
		})
		t.expect(fs.isDir(h.f.main)).toBe(true)
	end)

	it(
		"AC13: a z-ticket that made its issue and then failed is not re-run by the fallback; retry new adopts it",
		function()
			local before = originIssues()
			fakecli.clear(h)
			mode("claude.z-ticket", "script")
			mode("grok.z-ticket", "ticket") -- would make a second issue if it ever started
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[./zn new issue c first-try --project pickman --desc x; kill -9 "$PPID"]]
			)
			local r = zn({ "dispatch", "new", "make one thing" })
			t.expect(r.ok).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(1)
			t.expect(count(fakecli.log(h), "grok step=z-ticket")).toBe(0) -- the fallback never started
			t.expect(originIssues()).toBe(before + 1)
			t.expect(has(r.stdout .. r.stderr, "z-ticket made 2 issues")).toBe(false)
			-- the retry adopts the one issue and starts nothing
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local again = zn({ "dispatch", "retry", "new" })
			local out = again.stdout .. again.stderr
			t.expect(again.ok).toBe(true)
			local id = string.match(out, "(c%d%d%d%d) was made by this capture")
			t.expect(id ~= nil).toBe(true)
			t.expect(count(fakecli.log(h), "step=z-ticket")).toBe(0)
			t.expect(originIssues()).toBe(before + 1)
			t.expect(exchangeOf(id :: string)).toBe("001-ask.md")
		end
	)

	it(
		"AC13: a z-ticket that left questions.md and failed is not re-run by the fallback; the question is the exchange's",
		function()
			local before = originIssues()
			fakecli.clear(h)
			zn({ "dispatch", "retry", "new", "--forget-exchange" })
			fakecli.clear(h)
			mode("claude.z-ticket", "script")
			mode("grok.z-ticket", "ticket")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[printf '## Q1\nWhich project is this for?\n' > "$ZN_DISPATCH_DIR/questions.md"; kill -9 "$PPID"]]
			)
			local r = zn({ "dispatch", "new", "a thing that needs a question" })
			t.expect(r.ok).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(1)
			t.expect(count(fakecli.log(h), "grok step=z-ticket")).toBe(0)
			t.expect(originIssues()).toBe(before) -- it made nothing
			t.expect(exchangeOf("new")).toBe("001-ask.md,002-question.md")
			local question = fs.readFile(`{dirOf("new")}/exchange/002-question.md`)
			t.expect(has(question, "step: z-ticket")).toBe(true)
			t.expect(has(question, "Which project is this for?")).toBe(true)
		end
	)
end)
