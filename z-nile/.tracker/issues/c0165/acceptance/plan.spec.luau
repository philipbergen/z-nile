--!strict
-- c0165 AC3, AC8 (pure parts): what the orchestrator does with each spec given its db row (reuseplan.decide), and the
-- graph-miss plan (learn): which failures are misses, the trial sequence, and what the trial results teach.
local learn = require("@znile/lib/learn")
local reuseplan = require("@znile/lib/reuseplan")
local t = require("@tests/lib/t")

local function row(state: string, pid: number?, start: string?): any
	return { state = state, pid = pid, start = start, updated = 1 }
end
local function always(_: number, _: string?): boolean
	return true
end
local function never(_: number, _: string?): boolean
	return false
end

return t.spec("c0165 reuse decisions and the learning plan", function(it)
	it("AC3: decide gives the table's action for every row", function()
		-- fresh: always run, whatever the row
		for _, r in { nil :: any, row("passed"), row("failed"), row("running", 7, "s") } do
			t.expect(reuseplan.decide(r, true, always)).toBe("run")
			t.expect(reuseplan.decide(r, true, never)).toBe("run")
		end
		t.expect(reuseplan.decide(nil, false, always)).toBe("run")
		t.expect(reuseplan.decide(row("passed", 7, "s"), false, always)).toBe("reuse")
		t.expect(reuseplan.decide(row("passed", 7, "s"), false, never)).toBe("reuse")
		t.expect(reuseplan.decide(row("failed", 7, "s"), false, always)).toBe("run")
		t.expect(reuseplan.decide(row("failed", 7, "s"), false, never)).toBe("run")
		t.expect(reuseplan.decide(row("running", 7, "s"), false, always)).toBe("wait")
		t.expect(reuseplan.decide(row("running", 7, "s"), false, never)).toBe("run")
	end)

	it("AC3: decide asks holds about the row's own owner, start id included", function()
		local asked: { string } = {}
		local function holds(pid: number, start: string?): boolean
			table.insert(asked, `{pid}/{start}`)
			-- pid 7 is alive, but its start id is now "other": a reused pid, so it no longer holds
			return pid == 7 and start == "other"
		end
		t.expect(reuseplan.decide(row("running", 7, "s"), false, holds)).toBe("run")
		t.expect(asked).toEqual({ "7/s" })
		t.expect(reuseplan.decide(row("running", 7, "other"), false, holds)).toBe("wait")
	end)

	it("AC8: only failures the selector didn't pick are misses; ALL picked everything", function()
		local failed = { "tests/a.spec.luau", "tests/b.spec.luau", "tests/c.spec.luau" }
		t.expect(learn.misses(failed, { "tests/b.spec.luau" }))
			.toEqual({ "tests/a.spec.luau", "tests/c.spec.luau" })
		t.expect(learn.misses(failed, "ALL")).toEqual({})
		t.expect(learn.misses(failed, {})).toEqual(failed)
		t.expect(learn.misses({}, {})).toEqual({})
	end)

	it(
		"AC8: the plan reproduces, checks the base, then tries one candidate at a time up to the cap",
		function()
			local plan = learn.plan({ "x.md", "y.luau" }, 16)
			t.expect(#plan).toBe(4)
			t.expect(plan[1]).toEqual({ name = "all", apply = { "x.md", "y.luau" } })
			t.expect(plan[2]).toEqual({ name = "base", apply = {} })
			t.expect(plan[3]).toEqual({ name = "one", apply = { "x.md" } })
			t.expect(plan[4]).toEqual({ name = "one", apply = { "y.luau" } })
			-- over the cap: only the reproduction and the base, so every candidate becomes an input (unbisected)
			local many: { string } = {}
			for i = 1, 17 do
				table.insert(many, `f{string.format("%02d", i)}`)
			end
			local capped = learn.plan(many, 16)
			t.expect(#capped).toBe(2)
			t.expect(capped[1].name).toBe("all")
			t.expect(capped[2].name).toBe("base")
			t.expect(#learn.plan(many, 17)).toBe(19)
		end
	)

	it(
		"AC8: a total budget: a plan that doesn't fit what is left is empty, and the rest is handed back",
		function()
			local plan, left = learn.plan({ "x.md", "y.luau" }, 16, 40)
			t.expect(#plan).toBe(4)
			t.expect(left).toBe(36)
			-- three left: (a), (b) and the two candidates don't fit, so nothing is tried and nothing is spent
			local none, still = learn.plan({ "x.md", "y.luau" }, 16, 3)
			t.expect(#none).toBe(0)
			t.expect(still).toBe(3)
			-- over the per-miss cap, (a) and (b) alone fit in two
			local many: { string } = {}
			for i = 1, 17 do
				table.insert(many, `f{string.format("%02d", i)}`)
			end
			local capped, rest = learn.plan(many, 16, 2)
			t.expect(#capped).toBe(2)
			t.expect(rest).toBe(0)
			-- no budget given: no total cap
			local free, freeLeft = learn.plan({ "x.md" }, 16, nil)
			t.expect(#free).toBe(3)
			t.expect(freeLeft).toBe(nil)
		end
	)

	it(
		"AC8: the results teach the candidates the spec fails with, and nothing when it doesn't reproduce",
		function()
			local cands = { "x.md", "y.luau" }
			local plan = learn.plan(cands, 16)
			local function outcome(
				failedAll: boolean,
				failedBase: boolean,
				failedX: boolean,
				failedY: boolean
			): any
				return learn.inputs(cands, {
					{ trial = plan[1], failed = failedAll },
					{ trial = plan[2], failed = failedBase },
					{ trial = plan[3], failed = failedX },
					{ trial = plan[4], failed = failedY },
				})
			end
			t.expect(outcome(true, false, false, true))
				.toEqual({ outcome = "learned", inputs = { "y.luau" }, unbisected = false })
			t.expect(outcome(true, false, true, true))
				.toEqual({ outcome = "learned", inputs = cands, unbisected = false })
			-- fails only with both: every candidate, unbisected
			t.expect(outcome(true, false, false, false))
				.toEqual({ outcome = "learned", inputs = cands, unbisected = true })
			t.expect(outcome(false, false, false, false))
				.toEqual({ outcome = "not-reproduced", inputs = {}, unbisected = false })
			t.expect(outcome(true, true, true, true))
				.toEqual({ outcome = "base-fails", inputs = {}, unbisected = false })
			-- capped plan: only the first two trials ran
			local many = { "a", "b", "c" }
			local capped = learn.plan(many, 2)
			t.expect(learn.inputs(many, {
				{ trial = capped[1], failed = true },
				{ trial = capped[2], failed = false },
			})).toEqual({ outcome = "learned", inputs = many, unbisected = true })
		end
	)
end)
