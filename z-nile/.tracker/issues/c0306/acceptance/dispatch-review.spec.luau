--!strict
-- c0306 AC7: the dispatcher records the model and effort of the attempt that wrote a review, as `Model:` and `Effort:` lines
-- at the top of the file it files, in every mode (design, raft, code, final, stream); the reviewer never writes them, and a
-- review that already opens with a record fails the step. The real dispatcher runs against fake CLIs (@tests/lib/fakecli) in
-- a fixture under .cache/c0306-dispatch-review, from a worktree of it (a review runs in its author's worktree).
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
fallbacks = []

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = ["grok"]

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "medium"
fallbacks = []

[roles.final-review]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []
]]

local RAFT_DOC =
	"---\nid: R0090\ntype: chore\ntitle: demo\nslug: demo\nissues: [c0010, c0011]\ncreated: 2026-01-01\nstatus: active-a-b-c\n---\n\n# R0090\n"

local h: fakecli.Harness
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function znIn(args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(wt, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			GH_TOKEN = "the-users-token",
			CLAUDECODE = "",
			AI_AGENT = "",
			CLAUDE_EFFORT = "",
			ZN_DISPATCH = "",
			ZN_HEADLESS = "",
			CLAUDE_CODE_SESSION_ID = "",
			KIMI_SESSION_ID = "",
			KIMI_CODE_SESSION_ID = "",
		},
	})
end

-- the reviewer writes this review (never a record) to its state folder; `head` lets a case make it write one
local function reviewer(head: string?)
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`printf '{head or ""}# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
end

local function dispatch(id: string, mode: string): fixture.Result
	local r = znIn({ "dispatch", "zz-review", id, "--mode", mode })
	if not r.ok then
		error(`dispatch zz-review {id} --mode {mode} failed: {r.stdout}{r.stderr}`, 2)
	end
	return r
end

local function filed(path: string): string
	return fs.readFile(`{wt}/{path}`)
end

local function clean(path: string)
	if fs.isFile(`{wt}/{path}`) then
		fs.removeFile(`{wt}/{path}`)
	end
end

local ISSUE = "pickman/.tracker/issues/c0010"
local RAFT = "pickman/.tracker/rafts/R0090"

return t.spec("c0306 the dispatcher stamps the reviews it files", function(it)
	it("sets up a tracker with .models.toml, an issue, a raft in a worktree and the fake CLIs", function()
		h = fakecli.new("c0306-dispatch-review", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0011/c0011.md"] = trackerfix.stub(
				"c0011",
				"second-thing",
				"new-quiet-copper-falcon"
			),
		})
		wt = fixture.physical(`{h.f.base}/wt-review`) or `{h.f.base}/wt-review`
		fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "prep-review", wt, "origin/main" })
		wt = fixture.physical(wt) :: string
		-- c0010 in raft R0090 (as in a raft worktree), uncommitted in this worktree only
		fs.writeDir(`{wt}/{RAFT}`)
		fs.writeFile(`{wt}/{RAFT}/R0090.md`, RAFT_DOC)
		local doc = `{wt}/{ISSUE}/c0010.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\nraft:[^\n]*", "\nraft: R0090", 1)))
		fakecli.mode(h, "claude.zz-review", "script")
	end)

	it("AC7: a design review is stamped with the design-challenge role's model and effort", function()
		reviewer()
		dispatch("c0010", "design")
		t.expect(filed(`{ISSUE}/design-review-001.md`))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
		clean(`{ISSUE}/design-review-001.md`)
	end)

	it("AC7: a raft review is stamped with the raft role's model and effort", function()
		reviewer()
		dispatch("R0090", "raft")
		t.expect(filed(`{RAFT}/design-review-001.md`))
			.toBe("Model: claude-opus-5-5\nEffort: medium\n# Review\n\nVerdict: approve\n")
		clean(`{RAFT}/design-review-001.md`)
	end)

	it("AC7: a code review is stamped with the code-review role's model and effort", function()
		reviewer()
		dispatch("c0010", "code")
		t.expect(filed(`{ISSUE}/review-001.md`))
			.toBe("Model: claude-opus-5-5\nEffort: high\n# Review\n\nVerdict: approve\n")
		clean(`{ISSUE}/review-001.md`)
	end)

	it(
		"AC7: a code review that a fallback wrote is stamped with the fallback's model, the one that wrote it",
		function()
			fakecli.mode(h, "claude.zz-review", "scriptquota")
			fakecli.mode(h, "grok.zz-review", "script")
			reviewer()
			dispatch("c0010", "code")
			t.expect(filed(`{ISSUE}/review-001.md`))
				.toBe("Model: grok-4.7\nEffort: high\n# Review\n\nVerdict: approve\n")
			clean(`{ISSUE}/review-001.md`)
			fakecli.mode(h, "claude.zz-review", "script")
			fakecli.mode(h, "grok.zz-review", nil)
		end
	)

	it(
		"AC7: a final review is stamped with the final-review role's model, and no Effort: line when the role names none",
		function()
			reviewer()
			dispatch("R0090", "final")
			t.expect(filed(`{RAFT}/final-review-001.md`))
				.toBe("Model: claude-fable-5-2\n# Review\n\nVerdict: approve\n")
			clean(`{RAFT}/final-review-001.md`)
		end
	)

	it("AC7: a stream review is stamped too", function()
		reviewer()
		dispatch("c0010", "stream")
		t.expect(filed(`{RAFT}/stream-review-c0010-001.md`))
			.toBe("Model: claude-opus-5-5\nEffort: high\n# Review\n\nVerdict: approve\n")
		clean(`{RAFT}/stream-review-c0010-001.md`)
	end)

	it("AC7: a reviewer that writes its own Model: line fails the step and files nothing", function()
		reviewer("Model: claude-opus-5-5\\n")
		local r = znIn({ "dispatch", "zz-review", "c0010", "--mode", "design" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "already records")).toBe(true)
		t.expect(fs.isFile(`{wt}/{ISSUE}/design-review-001.md`)).toBe(false)
	end)

	it("cleans up", function()
		fixture.git(h.f.main, { "worktree", "remove", "--force", wt })
		fs.removeDir(h.f.base)
	end)
end)
