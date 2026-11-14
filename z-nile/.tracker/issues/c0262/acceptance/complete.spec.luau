--!strict
-- c0262: a layer is complete only when its ticket's final review is on course. c0248 (prepared, in the same raft
-- family, a dependency) writes the pure rule `completion.layer`; this ticket extends it with one optional input,
-- `final` (finalview.state's word). RED UNTIL c0248 IS DONE: z-nile/engine/completion.luau is c0248's module, and this
-- ticket depends on it. The input names below are the ones c0248's Public surface states (finishSha, patchId, review,
-- refute, doc); only `final` is this ticket's.
local completion = require("@znile/engine/completion")
local t = require("@tests/lib/t")

local FINISH = "a2f3c1d"
local PATCH = "7e02b9c"

local function input(final: string?): completion.LayerInput
	return {
		finishSha = FINISH,
		patchId = PATCH,
		review = `Commit: {FINISH}\nPatch: {PATCH}\n\n# Review 001\n\nVerdict: approve\n`,
		refute = nil,
		doc = "",
		final = final,
	}
end

return t.spec("c0262 a layer is complete after its final review", function(it)
	it(
		"AC13: a reviewed layer with no final input is as complete as c0248 says (an unmarked raft is not held)",
		function()
			t.expect(completion.layer(input(nil))).toBe(nil)
		end
	)

	it("AC13: with the final input, only an on-course ticket is complete", function()
		t.expect(completion.layer(input("on-course"))).toBe(nil)
	end)

	it("AC13: every other state is not complete, and the reason names the state", function()
		for _, state in { "none", "review-again", "redo-design", "redo-layer", "blocked", "invalid" } do
			local why = completion.layer(input(state))
			t.expect(why ~= nil).toBe(true)
			t.expect(string.find(why :: string, state, 1, true) ~= nil).toBe(true)
		end
	end)

	it("AC13: the final input never completes a layer c0248 calls incomplete", function()
		local stale = input("on-course")
		stale.patchId = "other"
		stale.review = `Commit: 1111111\nPatch: 2222222\n\nVerdict: approve\n`
		t.expect(completion.layer(stale) ~= nil).toBe(true)
	end)
end)
