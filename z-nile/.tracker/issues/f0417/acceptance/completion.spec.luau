--!strict
-- f0417 AC12: c0248's layer completion (z-nile/engine/completion.luau, as c0248 designs it) enforces the code loop for a
-- raft readied with `Rounds: on`: given the layer's rounds, a loop that has not ended is the layer's refusal, before
-- c0248's own checks. Pure. (c0248 lands the module; f0417 adds the `rounds` input.)
local completion = require("@znile/engine/completion")
local rounds = require("@znile/engine/rounds")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local REVIEW =
	"# Review 001: c0010 (code mode)\nInputs: x\n\n### F1 [medium] a claim\nWhere: x\nErred: zz-execute\nUpstream: none\n\nVerdict: changes\n"
local REFUTE = "# Refute 001\n\n- F1: fixed abc1234: done; consequences: none\n"
local HIGH = (string.gsub(REVIEW, "%[medium%]", "[high]"))

return t.spec("f0417: a layer's code loop is enforced where c0248 enforces a layer", function(it)
	it("a marked layer whose round 1 is answered by an edit is not complete: round 2 is owed", function()
		local list = { rounds.read("code", 1, REVIEW, REFUTE) }
		local problem = completion.layer({
			finishSha = "f1",
			patchId = "p1",
			review = REVIEW,
			refute = REFUTE,
			doc = "## Open to the human\nnone\n",
			reviewName = "review-001.md",
			refuteName = "refute-001.md",
			rounds = { list = list, window = { from = 1, extra = 0 }, doc = "## Open to the human\nnone\n" },
		} :: any)
		t.expect(has(problem, "the code loop has not ended")).toBe(true)
		t.expect(has(problem, "review-002")).toBe(true)
	end)

	it("a marked layer at the cap with an unruled leftover is not complete", function()
		local list: { rounds.Round } = {}
		for i = 1, 9 do
			table.insert(list, rounds.read("code", i, HIGH, REFUTE))
		end
		local problem = completion.layer({
			finishSha = "f1",
			patchId = "p1",
			review = REVIEW,
			refute = REFUTE,
			doc = "## Open to the human\nnone\n",
			reviewName = "review-009.md",
			refuteName = "refute-009.md",
			rounds = { list = list, window = { from = 1, extra = 0 }, doc = "## Open to the human\nnone\n" },
		} :: any)
		t.expect(has(problem, "the code loop has not ended")).toBe(true)
		t.expect(has(problem, "review-009 F1")).toBe(true)
	end)

	it("an ended loop adds nothing: the layer gets c0248's own answer", function()
		local approve = "# Review 002: c0010 (code mode)\nInputs: x\n\nVerdict: approve\n"
		local list = { rounds.read("code", 1, REVIEW, REFUTE), rounds.read("code", 2, approve, nil) }
		local input: any = {
			finishSha = "f1",
			patchId = "p1",
			review = approve,
			refute = nil,
			doc = "## Open to the human\nnone\n",
			reviewName = "review-002.md",
			refuteName = "refute-002.md",
		}
		local plain = completion.layer(input)
		input.rounds = { list = list, window = { from = 1, extra = 0 }, doc = "## Open to the human\nnone\n" }
		t.expect(completion.layer(input)).toBe(plain)
	end)
end)
