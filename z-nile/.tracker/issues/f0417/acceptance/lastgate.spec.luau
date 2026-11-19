--!strict
-- f0417 AC8, AC9, AC10: what a marked member needs to land (z-nile/engine/lastgate.luau), and where a refusal sends
-- the work: the person's ./zn refuse, the last review's off-course verdicts, and the reason a loop blocks with. Pure.
local lastgate = require("@znile/engine/lastgate")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

-- `over` sets fields; `clear` names fields to leave nil (a table constructor cannot hold a nil value)
local function member(over: { [string]: any }?, clear: { string }?): lastgate.Member
	local m: lastgate.Member = {
		id = "c0010",
		marked = true,
		state = "on-course",
		judged = "aaa111",
		current = "aaa111",
		approved = "aaa111",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(m :: any)[k] = v
	end
	for _, k in (clear or {}) :: { string } do
		(m :: any)[k] = nil
	end
	return m
end

-- the refusal alone (problem also returns its kind)
local function prob(m: lastgate.Member): string?
	local why = lastgate.problem(m)
	return why
end

return t.spec("f0417: the last gate and the routes back", function(it)
	it("a marked member passes only on-course, judged and approved on one contract", function()
		t.expect(prob(member())).toBe(nil)
		for _, state in { "none", "review-again", "redo-design", "redo-layer", "blocked", "invalid" } do
			t.expect(prob(member({ state = state })) ~= nil).toBe(true)
		end
		t.expect(prob(member({ judged = "bbb222" })) ~= nil).toBe(true)
		t.expect(prob(member({ approved = "bbb222" })) ~= nil).toBe(true)
		t.expect(prob(member(nil, { "approved" })) ~= nil).toBe(true)
		-- approved and judged agree with each other but not with the contract now: both are stale
		t.expect(prob(member({ judged = "bbb222", approved = "bbb222" })) ~= nil).toBe(true)
	end)

	it("each missing piece is named, with its kind", function()
		t.expect(select(2, lastgate.problem(member({ state = "none" })))).toBe("review")
		t.expect(select(2, lastgate.problem(member({ judged = "bbb222" })))).toBe("review")
		t.expect(select(2, lastgate.problem(member(nil, { "approved" })))).toBe("approval")
		t.expect(select(2, lastgate.problem(member({ approved = "ccc333" })))).toBe("approval")
		t.expect(has(prob(member({ state = "none" })), "no on-course last review")).toBe(true)
		local stale = prob(member({ judged = "bbb222" }))
		t.expect(has(stale, "the last review judged contract bbb222")).toBe(true)
		t.expect(has(stale, "aaa111")).toBe(true)
		local unapproved = prob(member(nil, { "approved" }))
		t.expect(has(unapproved, "not approved: ./zn approve c0010")).toBe(true)
		local other = prob(member({ approved = "ccc333" }))
		t.expect(has(other, "approved ccc333")).toBe(true)
		t.expect(has(other, "not the contract the last review judged")).toBe(true)
	end)

	it("an unmarked member is not judged here", function()
		t.expect(prob(member({ marked = false, state = "none" }, { "approved", "judged" }))).toBe(nil)
	end)

	it("a refusal's route: idea and design amend the design, build retries, each with its new-loop line", function()
		local i = lastgate.route("idea", "idea-review-003", "2026-11-20", "Ada") :: lastgate.Route
		t.expect(i.decision).toBe("amend-design")
		t.expect(i.idea).toBe(true)
		t.expect(i.line).toBe("- Loop (Ada, 2026-11-20): a new idea loop from idea-review-003")
		local d = lastgate.route("design", "design-review-010", "2026-11-20", "Ada") :: lastgate.Route
		t.expect(d.decision).toBe("amend-design")
		t.expect(d.idea).toBe(false)
		t.expect(d.line).toBe("- Loop (Ada, 2026-11-20): a new design loop from design-review-010")
		local b = lastgate.route("build", "review-004", "2026-11-20", "Ada") :: lastgate.Route
		t.expect(b.decision).toBe("retry")
		t.expect(b.line).toBe("- Loop (Ada, 2026-11-20): a new code loop from review-004")
		local none, why = lastgate.route("deploy", "x-001", "2026-11-20", "Ada")
		t.expect(none).toBe(nil)
		t.expect(has(why, "idea|design|build")).toBe(true)
		-- the last review's off-course verdicts all go through the blocked state: a design gap blocks design-gap,
		-- an implementation gap needs-decision recommending retry, a second verdict needs-decision
		local dg = lastgate.offCourse("redo-design", { "design" }) :: lastgate.Block
		t.expect(dg.reason).toBe("design-gap")
		t.expect(dg.recommend).toBe("amend-design")
		local impl = lastgate.offCourse("redo-layer", { "implementation" }) :: lastgate.Block
		t.expect(impl.reason).toBe("needs-decision")
		t.expect(impl.recommend).toBe("retry")
		local twiceImpl = lastgate.offCourse("blocked", { "implementation" }) :: lastgate.Block
		t.expect(twiceImpl.reason).toBe("needs-decision")
		t.expect(twiceImpl.recommend).toBe("retry")
		local twiceDesign = lastgate.offCourse("blocked", { "implementation", "design" }) :: lastgate.Block
		t.expect(twiceDesign.recommend).toBe("amend-design")
		t.expect(lastgate.offCourse("on-course", {})).toBe(nil)
	end)

	it("refuse plans by the issue's state: a block and its resolve, or a refusal naming the way", function()
		local function plan(over: { [string]: any }): (any, string?)
			local p: any = {
				id = "c0010",
				where = "active",
				status = "active",
				raft = "R0010",
				to = "design",
				why = "Not what I asked.",
				today = "2026-11-20",
				who = "Ada",
				next = { idea = "idea-review-003", design = "design-review-005", code = "review-002" },
			}
			for k, v in over do
				p[k] = v
			end
			return lastgate.refusePlan(p)
		end
		local active = plan({}) :: any
		t.expect(active.block.reason).toBe("needs-decision")
		t.expect(active.resolve.decision).toBe("amend-design")
		t.expect(active.resolve.line).toBe("- Loop (Ada, 2026-11-20): a new design loop from design-review-005")
		t.expect(has(active.question, "Not what I asked.")).toBe(true)
		local build = plan({ to = "build" }) :: any
		t.expect(build.resolve.decision).toBe("retry")
		t.expect(build.resolve.line).toBe("- Loop (Ada, 2026-11-20): a new code loop from review-002")
		local ideaPlan = plan({ to = "idea" }) :: any
		t.expect(ideaPlan.resolve.idea).toBe(true)
		t.expect(has(ideaPlan.ask, "Not what I asked.")).toBe(true)
		local preparing = plan({ where = "backlog", status = "preparing", raft = "" }) :: any
		t.expect(preparing.block.reason).toBe("needs-decision")
		local noBuild, whyBuild = plan({ where = "backlog", status = "preparing", raft = "", to = "build" })
		t.expect(noBuild).toBe(nil)
		t.expect(has(whyBuild, "nothing is built")).toBe(true)
		local prep, whyPrep = plan({ where = "backlog", status = "prepared", raft = "R0020" })
		t.expect(prep).toBe(nil)
		t.expect(has(whyPrep, "./zn unfold R0020 c0010")).toBe(true)
		t.expect(has(whyPrep, "./zn status c0010 preparing")).toBe(true)
		local new, whyNew = plan({ where = "backlog", status = "new", raft = "", to = "idea" })
		t.expect(new).toBe(nil)
		t.expect(has(whyNew, "./zn idea c0010 --record")).toBe(true)
		for _, st in { "done", "closed", "blocked" } do
			local none, why = plan({ where = if st == "done" then "done" else "backlog", status = st })
			t.expect(none).toBe(nil)
			t.expect(why ~= nil).toBe(true)
		end
		local _, whyBlocked = plan({ where = "backlog", status = "blocked" })
		t.expect(has(whyBlocked, "./zn resolve c0010")).toBe(true)
	end)

	it("review-exhausted is the cap's reason, needs-decision a dispute's", function()
		t.expect(lastgate.reason("cap", true)).toBe("review-exhausted")
		t.expect(lastgate.reason("dispute", true)).toBe("needs-decision")
		-- an unmarked item keeps c0250's rule: an unruled open list is review-exhausted
		t.expect(lastgate.reason("dispute", false)).toBe("review-exhausted")
		t.expect(lastgate.reason("cap", false)).toBe("review-exhausted")
	end)
end)
