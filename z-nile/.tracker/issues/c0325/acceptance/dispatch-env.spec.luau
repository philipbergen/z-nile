--!strict
-- c0325 AC6: the dispatcher sets ZN_MODEL, in the env of each attempt's process, to that attempt's own model: a
-- fallback attempt after a failed one sets its own, and a review started from an author's step (whose env holds the
-- author's ZN_MODEL) sets the reviewer's. The real dispatcher runs against fake CLIs (@tests/lib/fakecli) in a fixture
-- under .cache/c0325-dispatch-env, from a worktree of it (a review runs in its author's worktree).
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

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = ["grok"]
]]

local h: fakecli.Harness
local wt = ""

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
		CLAUDECODE = "",
		AI_AGENT = "",
		CLAUDE_EFFORT = "",
		ZN_DISPATCH = "",
		ZN_HEADLESS = "",
		ZN_MODEL = "",
		CLAUDE_CODE_SESSION_ID = "",
		KIMI_SESSION_ID = "",
		KIMI_CODE_SESSION_ID = "",
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return fixture.exec(wt, "bash", argv, { env = env })
end

-- every reviewer attempt appends the ZN_MODEL it was started with, then files its review
local function reviewer()
	fs.writeFile(
		`{h.fakes}/script.sh`,
		'echo "ZN_MODEL=$ZN_MODEL" >> "$FAKE_DIR/models.log"\nprintf "# Review\\n\\nVerdict: approve\\n" > "$ZN_DISPATCH_DIR/review.md"\n'
	)
end

local function models(): { string }
	local out = {}
	if fs.isFile(`{h.fakes}/models.log`) then
		for line in string.gmatch(fs.readFile(`{h.fakes}/models.log`), "[^\n]+") do
			table.insert(out, line)
		end
	end
	return out
end

local function reset()
	if fs.isFile(`{h.fakes}/models.log`) then
		fs.removeFile(`{h.fakes}/models.log`)
	end
	local review = `{wt}/pickman/.tracker/issues/c0010/design-review-001.md`
	if fs.isFile(review) then
		fs.removeFile(review)
	end
end

return t.spec("c0325 the dispatcher sets ZN_MODEL for each attempt", function(it)
	it("sets up a tracker with .models.toml, an issue in a worktree and the fake CLIs", function()
		h = fakecli.new("c0325-dispatch-env", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
		})
		wt = fixture.physical(`{h.f.base}/wt-env`) or `{h.f.base}/wt-env`
		fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "prep-env", wt, "origin/main" })
		wt = fixture.physical(wt) :: string
		fakecli.mode(h, "claude.zz-review", "script")
	end)

	it(
		"AC6: each attempt's env carries `ZN_MODEL` = that attempt's model (a fallback's own); a nested review sets its own",
		function()
			reviewer()
			-- the primary attempt
			local r = znIn({ "dispatch", "zz-review", "c0010", "--mode", "design" })
			if not r.ok then
				error(`dispatch failed: {r.stdout}{r.stderr}`)
			end
			t.expect(models()).toEqual({ "ZN_MODEL=claude-opus-5-5" })
			reset()
			-- the primary writes and hits its quota; the fallback attempt carries its own model, not the primary's
			fakecli.mode(h, "claude.zz-review", "scriptquota")
			fakecli.mode(h, "grok.zz-review", "script")
			local fb = znIn({ "dispatch", "zz-review", "c0010", "--mode", "design" })
			if not fb.ok then
				error(`dispatch with a fallback failed: {fb.stdout}{fb.stderr}`)
			end
			t.expect(models()).toEqual({ "ZN_MODEL=claude-opus-5-5", "ZN_MODEL=grok-4.7" })
			reset()
			fakecli.mode(h, "claude.zz-review", "script")
			fakecli.mode(h, "grok.zz-review", nil)
			-- a review started from an author's step: the author's env holds its own model, the review's child its own
			local nested = znIn(
				{ "dispatch", "zz-review", "c0010", "--mode", "design" },
				{ ZN_MODEL = "claude-sonnet-5-5" }
			)
			if not nested.ok then
				error(`nested dispatch failed: {nested.stdout}{nested.stderr}`)
			end
			t.expect(models()).toEqual({ "ZN_MODEL=claude-opus-5-5" })
			reset()
		end
	)
end)
