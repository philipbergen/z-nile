--!strict
-- c0260: `./zn dispatch zz-review <id> --mode idea` runs the idea review of z-ticket's capture: a clean reviewer on the
-- review model of the CLI, whose review the dispatcher numbers into the issue's capture/ folder as idea-review-NNN.md,
-- with its spend under the capture phase. Fake CLIs (@tests/lib/fakecli); fixture under .cache/c0260-dispatch.
local dispatch = require("@znile/engine/dispatch")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude", "grok", "agent"]

[dispatch]
stall_seconds = 5
tool_seconds = 8

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000

[z-ticket-review.claude]
model = "claude-opus-fake-ticket"
rank = 4
runtime = "claude-cli"
max_tokens = 5000

[z-ticket-review.grok]
model = "grok-fake-ticket"
effort = "xhigh"
rank = 4
runtime = "grok-cli"
max_tokens = 5000

[zz-review.grok]
model = "grok-4.7"
effort = "xhigh"
rank = 4
runtime = "grok-cli"
max_tokens = 5000
]]

local h: fakecli.Harness
local ISSUE = "pickman/.tracker/issues/c0010"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
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
local function reviewer()
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`printf '# Review\\n\\n### F1 [low] a claim\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
end
local function names(dir: string, prefix: string): { string }
	local out = {}
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if string.sub(name, 1, #prefix) == prefix then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

return t.spec("c0260 the idea review is a dispatched review mode", function(it)
	it(
		"AC5: idea is a review mode of the capture phase that reads the design lessons, and its prompt names its file",
		function()
			local m = dispatch.REVIEW_MODES.idea
			t.expect(m ~= nil and m.phase or "").toBe("capture")
			t.expect(m ~= nil and m.lessons or "").toBe("design")
			t.expect(m ~= nil and m.activity or "").toBe("z-ticket-review") -- the model comes from the activity's table
			t.expect(dispatch.phaseOf("zz-review", "idea")).toBe("capture")
			t.expect(dispatch.phaseOf("zz-review", "design")).toBe("design-review") -- the other modes keep their phase
			local prompt = dispatch.prompt({
				step = "zz-review",
				id = "c0010",
				mode = "idea",
				skillPath = "z-nile/skills/zz-review/SKILL.md",
				worktree = "/w",
				stateDir = "/s",
			})
			t.expect(has(prompt, "in idea mode")).toBe(true)
			t.expect(has(prompt, "`capture/idea-review-NNN.md`")).toBe(true)
			t.expect(has(prompt, "design-review-NNN")).toBe(false)
			t.expect(has(prompt, "--when design")).toBe(false) -- the design lessons are about designs, not ideas
			t.expect(has(prompt, "--skill z-ticket")).toBe(true)
			t.expect(has(prompt, "`## Ask (verbatim)`, `## Interview` and `## Idea`")).toBe(true) -- the reviewer sees the three sections
			t.expect(has(prompt, "do not read its Problem")).toBe(true)
			t.expect(has(prompt, "`/s/review.md`")).toBe(true)
		end
	)

	it("sets up a tracker with .models.toml, an issue and the fake CLIs, and a capture worktree", function()
		h = fakecli.new("c0260-dispatch", {
			[".models.toml"] = MODELS,
			[`{ISSUE}/c0010.md`] = trackerfix.stub("c0010", "first-thing", "new-quiet-copper-falcon"),
		})
		local made = fakecli.zn(h, { "worktree", "capture-first-thing" })
		t.expect(made.ok).toBe(true)
	end)

	it(
		"AC5: the review lands as capture/idea-review-001.md, then 002, with a capture row and never as a design review",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude.zz-review", "script")
			reviewer()
			local wt = fixture.physical(`{h.f.main}/.worktree/capture-first-thing`) :: string
			t.expect(fs.isDir(`{wt}/{ISSUE}/capture`)).toBe(false) -- the first review makes the folder
			local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "idea" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(names(`{wt}/{ISSUE}/capture`, "")).toEqual({ "idea-review-001.md" })
			local row = fakecli.rows(h, "c0010") :: any
			row = row[#row]
			t.expect(row.subject).toBe("idea-review-001")
			t.expect(row.phase).toBe("capture")
			-- the model is the one .models.toml names for the activity z-ticket-review, not zz-review's (no tier asserted)
			t.expect(row.model).toBe("claude-opus-fake-ticket")
			local again = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "idea" })
			if not again.ok then
				error(again.stdout .. again.stderr)
			end
			t.expect(names(`{wt}/{ISSUE}/capture`, "")).toEqual({ "idea-review-001.md", "idea-review-002.md" })
			t.expect(names(`{wt}/{ISSUE}`, "design-review-")).toEqual({})
			t.expect(names(`{wt}/{ISSUE}`, "idea-")).toEqual({})
			-- a design review in the same worktree still lands beside the document, numbered on its own
			local design = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design" })
			if not design.ok then
				error(design.stdout .. design.stderr)
			end
			t.expect(names(`{wt}/{ISSUE}`, "design-review-")).toEqual({ "design-review-001.md" })
			local drow = fakecli.rows(h, "c0010") :: any
			t.expect(drow[#drow].model).toBe("claude-opus-5-5") -- a design review still resolves zz-review's table
			t.expect(names(`{wt}/{ISSUE}/capture`, "")).toEqual({ "idea-review-001.md", "idea-review-002.md" })
		end
	)

	it("an unknown review mode is refused and starts no CLI", function()
		fakecli.clear(h)
		local wt = fixture.physical(`{h.f.main}/.worktree/capture-first-thing`) :: string
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "ideas" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr .. r.stdout, "idea")).toBe(true) -- the message lists the modes, idea among them
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"AC5: the idea review's activity table is under the review-model rule: Opus through claude, a grok model at xhigh",
		function()
			local function spec(cli: string, model: string, effort: string?): models.Spec
				return {
					cli = cli,
					model = model,
					effort = effort,
					rank = 4,
					runtime = "x",
					maxTokens = 1,
				} :: any
			end
			t.expect(models.reviewRule("z-ticket-review", spec("claude", "claude-opus-fake-ticket", nil))).toBe(nil)
			t.expect(models.reviewRule("z-ticket-review", spec("grok", "grok-fake-ticket", "xhigh"))).toBe(nil)
			t.expect(models.reviewRule("z-ticket-review", spec("claude", "claude-sonnet-fake", nil)) ~= nil).toBe(true)
			t.expect(models.reviewRule("z-ticket-review", spec("grok", "grok-fake-ticket", "high")) ~= nil).toBe(true)
			t.expect(models.reviewRule("z-ticket", spec("claude", "claude-sonnet-fake", nil))).toBe(nil) -- other activities are not reviews
		end
	)
end)
