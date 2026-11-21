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

[rounds]
design = { easy = 1 }

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

local function withRisk(doc: string, risk: string): string
	return (string.gsub(doc, "\ncreated:", `\nrisk: {risk}\ncreated:`, 1))
end

local function dispatchDesign(id: string?): fixture.Result
	return fixture.exec(
		wt,
		"bash",
		{ "scripts/tracker.sh", "dispatch", "zz-review", id or "c0010", "--mode", "design" },
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
			["pickman/.tracker/issues/c0020/c0020.md"] = withRisk(
				trackerfix.stub("c0020", "two", "preparing-quiet-copper-falcon"),
				"easy"
			),
			["pickman/.tracker/issues/c0030/c0030.md"] = trackerfix.stub(
				"c0030",
				"three",
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

	it(
		"the limits are main's [rounds] and the level is the issue's risk: an easy issue settles at round 1",
		function()
			reviewer()
			local dir = `{wt}/pickman/.tracker/issues/c0020`
			fs.writeFile(
				`{dir}/design-review-001.md`,
				"# Review\n\n### F1 [medium] a finding\nEvidence: x\n\nVerdict: changes\n"
			)
			fs.writeFile(`{dir}/design-refute-001.md`, "- F1: fixed abc; consequences: none\n")
			local r = dispatchDesign("c0020")
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stdout .. r.stderr,
					"design-review-001.md settled the review (approve, or answered at round 1 of 1)"
				)
			).toBe(true)
			t.expect(fakecli.log(h)).toBe("")
			t.expect(fs.isFile(`{dir}/design-review-002.md`)).toBe(false)
		end
	)

	it(
		"a ruling in the item's document settles a refuted low-only round; without it the rule is asked",
		function()
			reviewer()
			local dir = `{wt}/pickman/.tracker/issues/c0030`
			fs.writeFile(
				`{dir}/design-review-001.md`,
				"# Review\n\n### F1 [low] a finding\nEvidence: x\n\nVerdict: changes\n"
			)
			fs.writeFile(`{dir}/design-refute-001.md`, "- F1: refuted: shown\n")
			local asked = dispatchDesign("c0030")
			t.expect(asked.ok).toBe(false)
			t.expect(
				has(
					asked.stdout .. asked.stderr,
					"list what is refuted or still open under ## Open to the human"
				)
			).toBe(true)
			local doc = `{dir}/c0030.md`
			fs.writeFile(
				doc,
				fs.readFile(doc)
					.. "\n## Open to the human\n- F1: a finding. Answer: shown. Decision: accept. Ruled (user, 2026-11-20): ok.\n"
			)
			local settled = dispatchDesign("c0030")
			t.expect(settled.ok).toBe(false)
			t.expect(has(settled.stdout .. settled.stderr, "design-review-001.md settled the review"))
				.toBe(true)
			t.expect(fakecli.log(h)).toBe("")
		end
	)

	it("a review with no verdict and no findings is refused as malformed", function()
		reviewer()
		local dir = `{wt}/pickman/.tracker/issues/c0030`
		fs.writeFile(`{dir}/design-review-001.md`, "# Review\n\nnothing\n")
		fs.writeFile(
			`{dir}/c0030.md`,
			(string.gsub(fs.readFile(`{dir}/c0030.md`), "\n## Open to the human.*$", "\n"))
		)
		local r = dispatchDesign("c0030")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "design-review-001.md has no Verdict line and no findings"))
			.toBe(true)
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"./zn rounds prints where an item's reviews stand, from the same reader the dispatcher uses",
		function()
			local function rounds(id: string, kind: string?): fixture.Result
				local argv = { "scripts/tracker.sh", "rounds", id }
				if kind then
					table.insert(argv, "--kind")
					table.insert(argv, kind)
				end
				return fixture.exec(wt, "bash", argv, { env = { PATH = process.env.PATH } })
			end
			-- a working-tree .models.toml never counts: the dispatcher and work next read main's, and so does rounds (N4a)
			local toml = `{wt}/.models.toml`
			local original = fs.readFile(toml)
			fs.writeFile(toml, (string.gsub(original, "design = { easy = 1 }", "design = { easy = 5 }")))
			local easy = rounds("c0020")
			fs.writeFile(toml, original)
			t.expect(easy.ok).toBe(true)
			t.expect(
				has(
					easy.stdout,
					"c0020 design: design-review-001.md settled at the maximum (round 1 of 1) with 1 serious findings answered"
				)
			).toBe(true)
			local none = rounds("c0010", "code")
			t.expect(has(none.stdout, "c0010 code: no review yet; run code review round 1 of at most 5"))
				.toBe(true)
			t.expect(rounds("c0010", "nonsense").ok).toBe(false)
		end
	)
end)
