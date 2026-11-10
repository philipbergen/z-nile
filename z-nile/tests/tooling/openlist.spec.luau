--!strict
-- One review round. A refuted finding, a high that was not fixed, and a failed Judged criterion
-- need a ruling under `## Open to the human`. A ruling is `Ruled (user, YYYY-MM-DD):`.
local openlist = require("@znile/engine/openlist")
local t = require("@tests/lib/t")

local REVIEW = "# Review 001\n\n"
	.. "### F1 [high] a high finding\nEvidence: x\n\n"
	.. "### F2 [medium] a medium finding\nEvidence: y\n\n"
	.. "### F3 [low] a low finding\nEvidence: z\n\n"
	.. "Judged\n- JC1: fail\n- JC2: pass\n\n"
	.. "Verdict: changes\n"

local function ruled(id: string): string
	return `## Open to the human\n- {id}: the finding. Answer: answered. Decision: accept.\n  Ruled (user, 2026-11-10): accepted.\n`
end

return t.spec("one review round leaves the open list for the human", function(it)
	it("a refutation, an unfixed high and a failed Judged criterion need a ruling", function()
		local refute = "- F1: refuted: the spec says so\n- F2: deferred c0020: later\n- F3: fixed abc: ok\n"
		t.expect(openlist.needsHuman(REVIEW, refute)).toEqual({ "F1", "JC1" })
		t.expect(openlist.problem(REVIEW, refute, "# raft\n"))
			.toBe(
				"open to the human (F1, JC1): record each under ## Open to the human with Ruled (user, YYYY-MM-DD):"
			)
	end)

	it("a high that is fixed, and a medium that is deferred, do not", function()
		local refute =
			"- F1: fixed abc: closed; consequences: none\n- F2: deferred c0020: later\n- F3: fixed abc: ok\n"
		local review =
			"# Review\n\n### F1 [high] h\n\n### F2 [medium] m\n\n### F3 [low] l\n\nVerdict: changes\n"
		t.expect(openlist.needsHuman(review, refute)).toEqual({})
		t.expect(openlist.problem(review, refute, "# raft\n") == nil).toBe(true)
	end)

	it("a ruling on the bullet or the next line closes that id", function()
		local refute = "- F1: refuted: shown\n- F2: fixed abc: ok\n- F3: fixed abc: ok\n"
		local review = "# Review\n\n### F1 [low] a\n\n### F2 [medium] b\n\n### F3 [high] c\n"
		local same = "- F1: a. Answer: shown. Decision: accept. Ruled (user, 2026-11-10): yes.\n"
		t.expect(openlist.pending("## Open to the human\n" .. same)).toEqual({})
		t.expect(openlist.problem(review, refute, ruled("F1")) == nil).toBe(true)
		local open = "## Open to the human\n- F1: a. Answer: shown. Decision: accept.\n"
		t.expect(openlist.pending(open)).toEqual({ "F1" })
		t.expect(openlist.problem(review, refute, open) ~= nil).toBe(true)
	end)

	it("an older review file is not read: only the text it is given", function()
		local one = "# Review 001\n\n### F1 [high] old\n\nVerdict: changes\n"
		t.expect(#openlist.findings(one .. "\n" .. REVIEW) >= 4).toBe(true)
		t.expect(openlist.findings("# Review 002\n\nVerdict: approve\n")).toEqual({})
	end)
end)
