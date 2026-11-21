--!strict
-- f0423 AC1, AC2: `waiting.of` returns the verdict of the first rule that matches, `waiting.unit` combines the
-- members' verdicts, and `waiting.order` puts the bottom of a stack first.
local t = require("@tests/lib/t")
local waiting = require("@znile/engine/waiting")

local function fact(over: { [string]: any }): waiting.Fact
	local f: any = {
		stage = "designed",
		approval = "holds",
		changed = {},
		guesses = 0,
		lands = false,
		reworkOpen = false,
		reworkSince = nil,
	}
	for k, v in over do
		f[k] = v
	end
	return f :: waiting.Fact
end

-- the rules restated as data, first match wins: the oracle the sweep compares with
local function expected(f: waiting.Fact): string
	local rules: { { match: boolean, state: string } } = {
		{ match = f.stage == "draft" or f.reworkOpen, state = "working" },
		{ match = f.approval == "bad", state = "waits" },
		{ match = f.reworkSince ~= nil, state = "waits" },
		{ match = f.approval == "guesses" or f.approval == "stale", state = "waits" },
		{ match = f.approval == "none" and (f.guesses > 0 or f.lands), state = "waits" },
		{ match = true, state = "clear" },
	}
	for _, r in rules do
		if r.match then
			return r.state
		end
	end
	return "clear"
end

return t.spec("waiting: what waits for approval", function(it)
	it("rule 1: a draft design or an open rework is being worked, whatever else is true", function()
		t.expect(waiting.of(fact({ stage = "draft", approval = "bad", guesses = 3 })).state).toBe("working")
		t.expect(waiting.of(fact({ reworkOpen = true, approval = "none", guesses = 3 })).state)
			.toBe("working")
	end)

	it("rule 2: an approval.md that does not parse waits", function()
		local v = waiting.of(fact({ approval = "bad", reworkSince = 2 }))
		t.expect(v).toEqual({ state = "waits", why = "approval.md does not parse" })
	end)

	it("rule 3: a rework newer than the approval waits, even though the approval holds", function()
		local v = waiting.of(fact({ approval = "holds", reworkSince = 2 }))
		t.expect(v).toEqual({ state = "waits", why = "reworked since approval (W2)" })
	end)

	it("rule 4: a guess recorded since, or any other change, waits and names the parts", function()
		t.expect(waiting.of(fact({ approval = "guesses", changed = { "guesses" } }))).toEqual({
			state = "waits",
			why = "changed: guesses",
		})
		t.expect(waiting.of(fact({ approval = "stale", changed = { "design", "check" } })).why)
			.toBe("changed: design, check")
		t.expect(waiting.of(fact({ approval = "stale" })).why).toBe("changed: design")
	end)

	it("rule 5: no approval waits only with guesses or a Lands: approved raft", function()
		t.expect(waiting.of(fact({ approval = "none", guesses = 2 }))).toEqual({
			state = "waits",
			why = "no approval (2 guesses)",
		})
		t.expect(waiting.of(fact({ approval = "none", lands = true })).state).toBe("waits")
		t.expect(waiting.of(fact({ approval = "none" })).state).toBe("clear")
	end)

	it("rule 6: a standing approval is clear", function()
		t.expect(waiting.of(fact({ approval = "holds", guesses = 4, lands = true })).state).toBe("clear")
	end)

	it("every combination of the facts gets the verdict of the first matching rule", function()
		local count = 0
		for _, stage in { "draft", "designed", "built" } do
			for _, approval in { "none", "bad", "holds", "guesses", "stale" } do
				for _, guesses in { 0, 2 } do
					for _, lands in { false, true } do
						for _, open in { false, true } do
							for _, since in { 0, 3 } do
								local f = fact({
									stage = stage,
									approval = approval,
									guesses = guesses,
									lands = lands,
									reworkOpen = open,
									reworkSince = if since == 0 then nil else since,
								})
								t.expect(waiting.of(f).state).toBe(expected(f))
								count += 1
							end
						end
					end
				end
			end
		end
		t.expect(count).toBe(3 * 5 * 2 * 2 * 2 * 2)
	end)

	it("a unit waits if any member waits, else is working if any is, else is clear", function()
		local waits: waiting.Verdict = { state = "waits", why = "x" }
		local working: waiting.Verdict = { state = "working", why = "x" }
		local clear: waiting.Verdict = { state = "clear", why = "x" }
		t.expect(waiting.unit({ clear, working, waits })).toBe("waits")
		t.expect(waiting.unit({ clear, working })).toBe("working")
		t.expect(waiting.unit({ clear, clear })).toBe("clear")
		t.expect(waiting.unit({})).toBe("clear")
	end)

	it(
		"order puts the raft a stack is built on first, then layers, then ids; sorting by id alone would not",
		function()
			local placed: { waiting.Placed } = {
				{ id = "c0001", unit = "R0060", layer = 1 }, -- the lowest id, in the top raft
				{ id = "c0020", unit = "R0050", layer = 2 },
				{ id = "c0010", unit = "R0050", layer = 1 },
				{ id = "c0005", unit = "c0005", layer = 1 }, -- a raftless ticket with nothing under it
			}
			local bands = { R0050 = 0, R0060 = 1, c0005 = 0 }
			t.expect(waiting.order(placed, bands)).toEqual({ "c0010", "c0020", "c0005", "c0001" })
			-- a unit missing from the bands is band 0
			t.expect(waiting.order({ { id = "c0001", unit = "X", layer = 1 } }, {})).toEqual({ "c0001" })
		end
	)
end)
