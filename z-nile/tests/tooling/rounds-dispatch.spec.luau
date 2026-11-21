--!strict
-- f0421 AC10: for a normal issue, `./zn dispatch zz-review <id> --mode design` files design-review-002.md after an
-- answered design-review-001.md whose verdict is changes, and refuses with zero tokens and no CLI started while that
-- review is unanswered. Fake CLIs (@tests/lib/fakecli) in a fixture under .cache, from a worktree of it.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240

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

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []
]]

local DIR = "pickman/.tracker/issues/c0010"
local h: fakecli.Harness
local wt: string

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function dispatchDesign(): fixture.Result
	return fixture.exec(
		wt,
		"bash",
		{ "scripts/tracker.sh", "dispatch", "zz-review", "c0010", "--mode", "design" },
		{
			env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_AGENT_TOKEN_FILE = h.token,
				GH_TOKEN = "the-users-token",
			},
		}
	)
end

local function reviewer()
	fakecli.clear(h)
	fakecli.mode(h, "claude.zz-review", "script")
	fs.writeFile(
		`{h.fakes}/script.sh`,
		"sleep 1; printf '# Review\\n\\nVerdict: approve\\n' > \"$ZN_DISPATCH_DIR/review.md\"\n"
	)
end

return t.spec("f0421: a dispatched design review files the next round once the last is answered", function(it)
	it("sets up an issue c0010 on origin and an author's worktree with an unanswered round 1", function()
		h = fakecli.new("f0421-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"one",
				"preparing-quiet-copper-falcon"
			),
		})
		fixture.git(h.f.main, { "fetch", "-q", "origin", "main" })
		wt = `{h.f.main}/.worktree/author`
		fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "author", wt, "origin/main" })
		wt = fixture.physical(wt) :: string
		fs.writeFile(
			`{wt}/{DIR}/design-review-001.md`,
			"# Review\n\n### F1 [medium] a finding\nEvidence: x\n\nVerdict: changes\n"
		)
	end)

	it("refuses with zero tokens and no CLI while round 1 is unanswered", function()
		reviewer()
		local r = dispatchDesign()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, `{DIR}/design-review-001.md is not answered`)).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
		t.expect(fakecli.state(h, "c0010").tokens).toBe(0)
		t.expect(fs.isFile(`{wt}/{DIR}/design-review-002.md`)).toBe(false)
	end)

	it("files design-review-002.md once round 1 is answered", function()
		reviewer()
		fs.writeFile(`{wt}/{DIR}/design-refute-001.md`, "- F1: fixed abc; consequences: none\n")
		local r = dispatchDesign()
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(fs.isFile(`{wt}/{DIR}/design-review-002.md`)).toBe(true)
		t.expect(fs.isFile(`{wt}/{DIR}/design-review-003.md`)).toBe(false)
	end)

	it("refuses again, naming the settled review, once the latest round approves", function()
		reviewer()
		local r = dispatchDesign()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "design-review-002.md settled the review")).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "there is no further round")).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
	end)
end)
