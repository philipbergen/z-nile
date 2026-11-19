--!strict
-- f0417 AC2: where the dispatcher files a review. A marked item's design or code review is the next round of its loop
-- (rounds.filing); an unmarked folder keeps d0415's one-round refusal word for word. And the prompt of a marked
-- round says which round it is and which earlier rounds to read. Pure.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function design(verdict: string, severity: string?): string
	local f = if severity
		then `### F1 [{severity}] a claim\nWhere: x\nErred: z-design\nUpstream: none\n\n`
		else ""
	return `# Review NNN: c0001 (design mode)\nInputs: x\n\n{f}Verdict: {verdict}\n`
end

local FIXED = "- F1: fixed: done; consequences: none\n"

-- n answered `changes` rounds, as the folder holds them
local function folder(
	prefix: string,
	refPrefix: string,
	n: number
): ({ [string]: string }, { [string]: string })
	local reviews, refutes = {}, {}
	for i = 1, n do
		local num = string.format("%03d", i)
		reviews[`{prefix}{num}.md`] = design("changes", "medium")
		refutes[`{refPrefix}{num}.md`] = FIXED
	end
	return reviews, refutes
end

return t.spec("f0417: the dispatcher files rounds", function(it)
	it("a marked design folder files round 2 and round 9, and refuses round 10", function()
		local reviews, refutes = folder("design-review-", "design-refute-", 1)
		local two = dispatch.filing({
			mode = "design",
			dir = "d",
			prefix = "design-review-",
			raftId = "c0001",
			reviews = reviews,
			stage = "design",
			refutes = refutes,
			window = { from = 1, extra = 0 },
		})
		t.expect(two.number).toBe(2)
		t.expect(two.refusal).toBe(nil)
		local r8, f8 = folder("design-review-", "design-refute-", 8)
		local nine = dispatch.filing({
			mode = "design",
			dir = "d",
			prefix = "design-review-",
			raftId = "c0001",
			reviews = r8,
			stage = "design",
			refutes = f8,
			window = { from = 1, extra = 0 },
		})
		t.expect(nine.number).toBe(9)
		local r9, f9 = folder("design-review-", "design-refute-", 9)
		local ten = dispatch.filing({
			mode = "design",
			dir = "d",
			prefix = "design-review-",
			raftId = "c0001",
			reviews = r9,
			stage = "design",
			refutes = f9,
			window = { from = 1, extra = 0 },
		})
		t.expect(ten.number).toBe(nil)
		t.expect(has(ten.refusal, "cap of 9 rounds")).toBe(true)
		-- an unanswered round is answered before the next is filed
		local open = { ["design-review-001.md"] = design("changes", "high") }
		local wait = dispatch.filing({
			mode = "design",
			dir = "d",
			prefix = "design-review-",
			raftId = "c0001",
			reviews = open,
			stage = "design",
			refutes = {},
			window = { from = 1, extra = 0 },
		})
		t.expect(wait.number).toBe(nil)
		t.expect(has(wait.refusal, "answer design-review-001 first")).toBe(true)
	end)

	it("an unmarked folder keeps the one-round refusal, word for word", function()
		local reviews, _ = folder("design-review-", "design-refute-", 1)
		local f = dispatch.filing({
			mode = "design",
			dir = "d",
			prefix = "design-review-",
			raftId = "c0001",
			reviews = reviews,
		})
		t.expect(f.number).toBe(nil)
		t.expect(f.refusal).toBe(
			"d already has design-review-001.md: one round, then the author answers it; there is no second round"
		)
		local empty = dispatch.filing({
			mode = "design",
			dir = "d",
			prefix = "design-review-",
			raftId = "c0001",
			reviews = {},
		})
		t.expect(empty.number).toBe(1)
	end)

	it("a marked code folder files the layer's next review", function()
		local reviews, refutes = folder("review-", "refute-", 3)
		local f = dispatch.filing({
			mode = "code",
			dir = "i",
			prefix = "review-",
			raftId = "c0010",
			reviews = reviews,
			stage = "code",
			refutes = refutes,
			window = { from = 1, extra = 0 },
		})
		t.expect(f.number).toBe(4)
		-- the approving round ends it
		reviews["review-004.md"] = design("approve")
		local ended = dispatch.filing({
			mode = "code",
			dir = "i",
			prefix = "review-",
			raftId = "c0010",
			reviews = reviews,
			stage = "code",
			refutes = refutes,
			window = { from = 1, extra = 0 },
		})
		t.expect(ended.number).toBe(nil)
		t.expect(has(ended.refusal, "the loop ended")).toBe(true)
	end)

	it("the dispatcher's input: the stage for a marked design item or a Rounds raft's code review, else none", function()
		local reviews, refutes = folder("design-review-", "design-refute-", 1)
		local marked = "---\nid: c0001\nrounds: on\n---\n\n# c0001\n\n## Loops\n- Loop (tool, 2026-11-20): a new design loop from design-review-001\n"
		local unmarked = "---\nid: c0001\n---\n\n# c0001\n"
		local base = { mode = "design", dir = "d", prefix = "design-review-", raftId = "c0001", reviews = reviews, refutes = refutes }
		local function with(over: { [string]: any }): any
			local p = table.clone(base) :: any
			for k, v in over do
				p[k] = v
			end
			return p
		end
		local m = dispatch.filingFor(with({ doc = marked }))
		t.expect(m.stage).toBe("design")
		t.expect((m.window :: any).from).toBe(1)
		t.expect(dispatch.filing(m).number).toBe(2)
		local u = dispatch.filingFor(with({ doc = unmarked }))
		t.expect(u.stage).toBe(nil)
		t.expect(has(dispatch.filing(u).refusal, "there is no second round")).toBe(true)
		local code = dispatch.filingFor(with({ mode = "code", prefix = "review-", doc = unmarked, readyRounds = true }))
		t.expect(code.stage).toBe("code")
		local codeOld = dispatch.filingFor(with({ mode = "code", prefix = "review-", doc = marked, readyRounds = false }))
		t.expect(codeOld.stage).toBe(nil) -- a raft readied without the trailer keeps one review
		local raft = dispatch.filingFor(with({ mode = "raft", doc = marked }))
		t.expect(raft.stage).toBe(nil)
		-- a rebuilt layer: its approving round reviewed an older patch, so the next round is filed, not refused
		local codeReviews = { ["review-001.md"] = design("approve") }
		local stale = dispatch.filingFor(with({
			mode = "code",
			prefix = "review-",
			reviews = codeReviews,
			refutes = {},
			doc = unmarked,
			readyRounds = true,
			stale = { ["review-001.md"] = true },
		}))
		t.expect(dispatch.filing(stale).number).toBe(2)
		local fresh = dispatch.filingFor(with({
			mode = "code",
			prefix = "review-",
			reviews = codeReviews,
			refutes = {},
			doc = unmarked,
			readyRounds = true,
		}))
		t.expect(has(dispatch.filing(fresh).refusal, "the loop ended")).toBe(true)
		-- the person's extra round, written by resolve retry in the layer's issue document, reaches the dispatcher
		local r9, f9 = folder("review-", "refute-", 9)
		local granted = "---\nid: c0010\n---\n\n# c0010\n\n## Loops\n- Loop (Ada, 2026-11-20): one more code round past review-009\n"
		local capped = dispatch.filingFor(with({ mode = "code", prefix = "review-", reviews = r9, refutes = f9, doc = unmarked, readyRounds = true }))
		t.expect(dispatch.filing(capped).number).toBe(nil)
		local more = dispatch.filingFor(with({ mode = "code", prefix = "review-", reviews = r9, refutes = f9, doc = granted, readyRounds = true }))
		t.expect(dispatch.filing(more).number).toBe(10)
	end)

	it("the prompt of a marked round names its number, the cap and the earlier rounds", function()
		local p = dispatch.prompt({
			step = "zz-review",
			id = "c0001",
			mode = "design",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = ".worktree/prep-x",
			stateDir = ".cache/dispatch/c0001/s",
			round = 3,
			cap = 9,
			priors = {
				"design-review-001.md",
				"design-refute-001.md",
				"design-review-002.md",
				"design-refute-002.md",
			},
		})
		t.expect(has(p, "This is round 3 of at most 9.")).toBe(true)
		t.expect(has(p, "design-refute-002.md")).toBe(true)
		t.expect(has(p, "Dropped from")).toBe(true)
		t.expect(has(p, "(repeat of")).toBe(true)
		-- an unmarked review's prompt says nothing of rounds, and the stream prompt keeps its one round
		local plain = dispatch.prompt({
			step = "zz-review",
			id = "c0001",
			mode = "design",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = ".worktree/prep-x",
			stateDir = ".cache/dispatch/c0001/s",
		})
		t.expect(has(plain, "of at most")).toBe(false)
		local stream = dispatch.prompt({
			step = "zz-review",
			id = "c0010",
			mode = "stream",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = ".worktree/R0010",
			stateDir = ".cache/dispatch/c0010/s",
		})
		t.expect(has(stream, "This is the one round")).toBe(true)
	end)
end)
