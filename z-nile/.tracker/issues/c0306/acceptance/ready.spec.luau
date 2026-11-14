--!strict
-- c0306 AC5 and AC6 (the pure halves): readycheck.reason judges the coherence reviews of a marked raft and the design
-- reviews of each marked member (what ./zn ready and ./zn work next share), and work.decide prints `done`'s refusal for a
-- raft `done` would refuse. The commands themselves are commands.spec's.
local contract = require("@znile/engine/contract")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local DOC = table.concat({
	"---",
	"id: c0001",
	"design: ready",
	"---",
	"",
	"# c0001",
	"",
	"## Problem",
	"P",
	"",
	"## Solution",
	"S",
	"",
	"## Design",
	"D",
	"",
	"## Acceptance criteria",
	"A",
	"",
	"## Test plan",
	"T",
	"",
}, "\n")
local CHECK = 'check "AC1: holds" true\n'
local OPUS = "Model: claude-opus-5-5\nEffort: high\n# Review 001\n\nVerdict: approve\n"
local SONNET = "Model: claude-sonnet-5-5\nEffort: high\n# Review 001\n\nVerdict: approve\n"
local BARE = "# Review 001\n\nVerdict: approve\n"

local function has(s: string?, part: string): boolean
	return s ~= nil and string.find(s, part, 1, true) ~= nil
end

local function approval(): string
	local built = contract.build(DOC, CHECK, {}) :: contract.Parts
	return contract.render({
		{
			when = "2026-11-13T00:00:00Z",
			who = "Ada",
			hash = contract.hash(built),
			parts = contract.partHashes(built),
		},
	})
end

local function member(judged: boolean?, reviews: { [string]: string }?): any
	local a = approval()
	local files: { [string]: string } = { ["c0001.md"] = DOC, ["check.sh"] = CHECK, ["approval.md"] = a }
	local given: { [string]: string } = reviews or {}
	for name, text in given do
		files[name] = text
	end
	return {
		id = "c0001",
		design = "ready",
		doc = DOC,
		deps = {},
		files = files,
		specs = {},
		approval = a,
		approvalFile = "z-nile/.tracker/issues/c0001/approval.md",
		judged = judged,
	}
end

local function raft(judged: boolean?, reviews: { [string]: string }?, members: { any }?): any
	local files: { [string]: string } = { ["check.sh"] = CHECK }
	local given: { [string]: string } = reviews or {}
	for name, text in given do
		files[name] = text
	end
	return {
		id = "R0001",
		where = "backlog",
		status = "prepared",
		dir = "z-nile/.tracker/rafts/R0001",
		design = "ready",
		doc = "---\ndesign: ready\n---\n",
		grouped = nil,
		questions = false,
		listed = { "c0001" },
		members = members or { member(nil) },
		files = files,
		loaded = true,
		judged = judged,
	}
end

local function fact(over: { [string]: any }): any
	local r: any = {
		id = "R0010",
		title = "t",
		where = "active",
		status = "active",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010" },
		layers = {
			{
				position = 1,
				issue = "c0010",
				name = "R0010/1/c0010",
				commits = 3,
				onlyStart = false,
				finished = true,
			},
		},
		holder = "Ada <ada@example>",
		since = "2026-11-12T00:00:00-08:00",
		stacked = true,
		codeReview = "resolved",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		root = "",
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

return t.spec("c0306 ready and work next judge the reviews", function(it)
	it(
		"AC5: a marked raft whose coherence review is off the review models is refused, naming the file and the model",
		function()
			local why = readycheck.reason(raft(true, { ["design-review-001.md"] = SONNET }))
			t.expect(has(why, "design-review-001.md")).toBe(true)
			t.expect(has(why, "claude-sonnet-5-5")).toBe(true)
			t.expect(has(why, "claude-opus-")).toBe(true)
			t.expect(has(why, "R0001")).toBe(true)
			t.expect(has(why, "./zn dispatch zz-review R0001 --mode raft")).toBe(true)
			t.expect(has(why, "./zn spend")).toBe(false) -- an off-model record is recorded once: only a new round
		end
	)

	it(
		"AC5: a marked raft whose coherence review records no model is refused (omission never passes)",
		function()
			local why = readycheck.reason(raft(true, { ["design-review-001.md"] = BARE }))
			t.expect(has(why, "design-review-001.md")).toBe(true)
			t.expect(has(why, "no `Model:` line")).toBe(true)
		end
	)

	it(
		"AC5: a coherence review's refusal says its way out is made in a worktree and lands by pull request",
		function()
			local none = readycheck.reason(raft(true, { ["design-review-001.md"] = BARE }))
			t.expect(has(none, "worktree")).toBe(true)
			t.expect(has(none, "pull request")).toBe(true)
			t.expect(has(none, "./zn spend R0001 --phase design-review --note design-review-001 --model"))
				.toBe(true)
			local member =
				readycheck.reason(raft(nil, nil, { member(true, { ["design-review-001.md"] = BARE }) }))
			t.expect(has(member, "worktree")).toBe(true)
			t.expect(has(member, "pull request")).toBe(true)
			t.expect(has(member, "--mode design")).toBe(true)
			local off = readycheck.reason(raft(true, { ["design-review-001.md"] = SONNET }))
			t.expect(has(off, "worktree")).toBe(true)
			t.expect(has(off, "pull request")).toBe(true)
			t.expect(has(off, "./zn spend")).toBe(false)
		end
	)

	it("AC5: every round of the coherence review is judged, not only the last", function()
		local why = readycheck.reason(
			raft(true, { ["design-review-001.md"] = SONNET, ["design-review-002.md"] = OPUS })
		)
		t.expect(has(why, "design-review-001.md")).toBe(true)
		-- the first failing file by number is the one named
		-- a later round off the review models is refused when the first is fine
		local later = readycheck.reason(
			raft(true, { ["design-review-001.md"] = OPUS, ["design-review-002.md"] = SONNET })
		)
		t.expect(has(later, "design-review-002.md")).toBe(true)
		local both = readycheck.reason(
			raft(true, { ["design-review-002.md"] = SONNET, ["design-review-001.md"] = BARE })
		)
		t.expect(has(both, "design-review-001.md")).toBe(true)
	end)

	it("AC5: a marked member's design review off the review models is refused, naming the member", function()
		local m = member(true, { ["design-review-001.md"] = SONNET })
		local why = readycheck.reason(raft(nil, nil, { m }))
		t.expect(has(why, "c0001")).toBe(true)
		t.expect(has(why, "design-review-001.md")).toBe(true)
		t.expect(has(why, "claude-sonnet-5-5")).toBe(true)
		local bare = readycheck.reason(raft(nil, nil, { member(true, { ["design-review-002.md"] = BARE }) }))
		t.expect(has(bare, "no `Model:` line")).toBe(true)
	end)

	it("AC5: a marked raft and member on a review model pass, at every kind", function()
		t.expect(
			(
				readycheck.reason(
					raft(
						true,
						{ ["design-review-001.md"] = OPUS },
						{ member(true, { ["design-review-001.md"] = OPUS }) }
					)
				)
			)
		).toBe(nil)
		for _, model in { "claude-fable-5-2", "kimi-code-k3.2" } do
			local text = `Model: {model}\n# Review\nVerdict: approve\n`
			t.expect((readycheck.reason(raft(true, { ["design-review-001.md"] = text })))).toBe(nil)
		end
		local grok = "Model: grok-4.7\nEffort: xhigh\n# Review\nVerdict: approve\n"
		t.expect((readycheck.reason(raft(true, { ["design-review-001.md"] = grok })))).toBe(nil)
		local lowGrok = "Model: grok-4.7\nEffort: high\n# Review\nVerdict: approve\n"
		t.expect(has(readycheck.reason(raft(true, { ["design-review-001.md"] = lowGrok })), "grok-4.7"))
			.toBe(true)
	end)

	it(
		"AC5: an unmarked raft and member pass any review, and a marked raft with no review is not refused",
		function()
			t.expect(
				(
					readycheck.reason(
						raft(
							nil,
							{ ["design-review-001.md"] = SONNET },
							{ member(nil, { ["design-review-001.md"] = SONNET }) }
						)
					)
				)
			).toBe(nil)
			t.expect((readycheck.reason(raft(false, { ["design-review-001.md"] = BARE })))).toBe(nil)
			t.expect((readycheck.reason(raft(true, nil, { member(true, nil) })))).toBe(nil)
			-- a refute and a harvest are never judged
			t.expect(
				(readycheck.reason(raft(true, { ["design-refute-001.md"] = BARE, ["harvest.md"] = BARE })))
			)
				.toBe(nil)
		end
	)

	it(
		"AC6: work.decide prints the codeModel refusal where it would say to run ./zn done, and only there",
		function()
			local refusal =
				"R0010: final-review-001.md records claude-sonnet-5-5 at effort high, which is not a review model"
			local d = work.decide({ asked = "R0010", held = nil, rafts = { fact({ codeModel = refusal }) } })
			t.expect(d.action ~= "done").toBe(true)
			t.expect(has(d.why, refusal)).toBe(true)
			t.expect(has(d.why, "Run ./zn done")).toBe(false)
			local fine = work.decide({ asked = "R0010", held = nil, rafts = { fact({}) } })
			t.expect(fine.action).toBe("done")
			t.expect(has(fine.why, "Run ./zn done R0010")).toBe(true)
			-- an earlier step still comes first
			local early = work.decide({
				asked = "R0010",
				held = nil,
				rafts = { fact({ codeModel = refusal, finalReview = "none" }) },
			})
			t.expect(early.action).toBe("final-review")
		end
	)
end)
