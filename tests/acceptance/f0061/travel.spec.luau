--!strict
-- f0670: Travel, whether a player may be sent to another place now: the configured destination, one request
-- at a time, a timeout when the engine never answers, a cool-down after a failure.
local Travel = require("@logic/Travel")
local t = require("@tests/lib/t")

-- the answer alone (request also returns a ticket)
local function ask(tr: Travel.Travel, id: string, now: number): Travel.Answer
	local answer: Travel.Answer = Travel.request(tr, id, now)
	return answer
end

return t.spec("f0670 Travel", function(it)
	it(
		"the defaults: 15 s after the engine call returns, 3 s of cool-down, a 60 s cap on a call that never returns",
		function()
			t.expect(Travel.DEFAULT.goingSeconds).toBe(15)
			t.expect(Travel.DEFAULT.coolSeconds).toBe(3)
			t.expect(Travel.DEFAULT.capSeconds).toBe(60)
			t.expect(table.isfrozen(Travel.DEFAULT)).toBe(true)
			t.expect(Travel.new().config).toBe(Travel.DEFAULT)
		end
	)

	it("a destination is a whole place id from 1 up, as a number or as digits", function()
		t.expect(Travel.destination(1)).toBe(1)
		t.expect(Travel.destination(123456789012)).toBe(123456789012)
		t.expect(Travel.destination("987654321")).toBe(987654321)
		t.expect(Travel.destination(Travel.MAX_PLACE_ID)).toBe(Travel.MAX_PLACE_ID)
	end)

	it(
		"anything else is not a destination: 0, negatives, fractions, NaN, too large, text, other types",
		function()
			local bads: { any } = {
				0,
				-1,
				1.5,
				0 / 0,
				math.huge,
				Travel.MAX_PLACE_ID + 2,
				"0",
				"",
				"12a",
				"-5",
				" 7",
				"1.5",
				"0x10",
				"1e3",
				"١٢٣",
				true,
				{},
			}
			for _, bad in bads do
				t.expect(Travel.destination(bad)).toBe(nil)
			end
			t.expect(Travel.destination(nil)).toBe(nil)
		end
	)

	it("an idle player may go, and is then busy: one request at a time", function()
		local tr = Travel.new()
		t.expect(Travel.status(tr, "a", 0)).toBe("idle")
		t.expect(ask(tr, "a", 0)).toBe("go")
		t.expect(Travel.status(tr, "a", 1)).toBe("going")
		t.expect(ask(tr, "a", 1)).toBe("busy")
		t.expect(ask(tr, "a", 14.9)).toBe("busy")
	end)

	it(
		"while the engine call has not returned the player stays going, past 15 s, up to the 60 s cap",
		function()
			local tr = Travel.new()
			Travel.request(tr, "a", 0)
			t.expect(Travel.status(tr, "a", 15)).toBe("going")
			t.expect(ask(tr, "a", 30)).toBe("busy")
			t.expect(Travel.status(tr, "a", 59.9)).toBe("going")
			t.expect(Travel.status(tr, "a", 60)).toBe("cooling")
			t.expect(ask(tr, "a", 62.9)).toBe("cooling")
			t.expect(ask(tr, "a", 63)).toBe("go")
		end
	)

	it("once the engine call has returned, nothing happening for 15 s is a failure", function()
		local tr = Travel.new()
		Travel.request(tr, "a", 100)
		Travel.answered(tr, "a", 102)
		t.expect(Travel.status(tr, "a", 116.9)).toBe("going")
		t.expect(ask(tr, "a", 116.9)).toBe("busy")
		t.expect(Travel.status(tr, "a", 117)).toBe("cooling")
		t.expect(ask(tr, "a", 119.9)).toBe("cooling")
		t.expect(ask(tr, "a", 120)).toBe("go")
	end)

	it("an answer that comes late never pushes the timeout past the cap", function()
		local tr = Travel.new()
		Travel.request(tr, "a", 0)
		Travel.answered(tr, "a", 55)
		t.expect(Travel.status(tr, "a", 59.9)).toBe("going")
		t.expect(Travel.status(tr, "a", 60)).toBe("cooling")
	end)

	it("an answer for a player who is not going changes nothing", function()
		local tr = Travel.new()
		Travel.answered(tr, "a", 0)
		t.expect(Travel.status(tr, "a", 0)).toBe("idle")
		Travel.request(tr, "a", 10)
		Travel.failed(tr, "a", 11)
		Travel.answered(tr, "a", 12) -- cooling until 14
		t.expect(Travel.status(tr, "a", 13.9)).toBe("cooling")
		t.expect(Travel.status(tr, "a", 14)).toBe("idle")
	end)

	it("a reported failure cools down for 3 s from the report, then the player may go again", function()
		local tr = Travel.new()
		Travel.request(tr, "a", 10)
		Travel.failed(tr, "a", 12)
		t.expect(Travel.status(tr, "a", 12)).toBe("cooling")
		t.expect(ask(tr, "a", 14.9)).toBe("cooling")
		t.expect(Travel.status(tr, "a", 15)).toBe("idle")
		t.expect(ask(tr, "a", 15)).toBe("go")
	end)

	it("a failure nobody asked for changes nothing", function()
		local tr = Travel.new()
		Travel.failed(tr, "a", 5)
		t.expect(Travel.status(tr, "a", 5)).toBe("idle")
		t.expect(ask(tr, "a", 5)).toBe("go")
	end)

	it(
		"a late failure changes nothing: it does not extend a cool-down or cool down a newer request",
		function()
			local tr = Travel.new()
			Travel.request(tr, "a", 0)
			Travel.failed(tr, "a", 1) -- cooling until 4
			Travel.failed(tr, "a", 3) -- a second report: ignored
			t.expect(Travel.status(tr, "a", 4)).toBe("idle")
			-- the first request timed out and a second began; the first one's failure arrives now
			Travel.request(tr, "a", 10)
			Travel.answered(tr, "a", 10)
			t.expect(Travel.status(tr, "a", 25)).toBe("cooling") -- timed out at 25
			t.expect(ask(tr, "a", 28)).toBe("go") -- the second request
			Travel.failed(tr, "a", 28.5) -- that is the second request's own failure: cools it down
			t.expect(Travel.status(tr, "a", 29)).toBe("cooling")
			Travel.failed(tr, "a", 30) -- late: nobody is going
			t.expect(Travel.status(tr, "a", 31.5)).toBe("idle")
		end
	)

	it("a go comes with a ticket that names the request; the other answers have none", function()
		local tr = Travel.new()
		local answer, ticket = Travel.request(tr, "a", 0)
		t.expect(answer).toBe("go")
		t.expect(type(ticket)).toBe("number")
		local busy, none = Travel.request(tr, "a", 1)
		t.expect(busy).toBe("busy")
		t.expect(none).toBe(nil)
		local other, otherTicket = Travel.request(tr, "b", 1)
		t.expect(other).toBe("go")
		t.expect(otherTicket ~= ticket).toBe(true)
	end)

	it("a report for an older request changes nothing: the newer one keeps its own wait", function()
		local tr = Travel.new()
		local _, first = Travel.request(tr, "a", 0)
		t.expect(Travel.status(tr, "a", 60)).toBe("cooling") -- given up on at the 60 s cap, free again at 63
		local answer, second = Travel.request(tr, "a", 64)
		t.expect(answer).toBe("go")
		Travel.failed(tr, "a", 65, first) -- the old request's failure: ignored
		t.expect(Travel.status(tr, "a", 65)).toBe("going")
		Travel.answered(tr, "a", 66, first) -- the old request's answer: ignored
		t.expect(Travel.status(tr, "a", 123.9)).toBe("going") -- still the new request's cap, 124
		t.expect(Travel.status(tr, "a", 124)).toBe("cooling")
		-- the new request's own answer and failure do count
		local _, third = Travel.request(tr, "a", 130)
		Travel.answered(tr, "a", 131, third)
		t.expect(Travel.status(tr, "a", 145.9)).toBe("going")
		t.expect(Travel.status(tr, "a", 146)).toBe("cooling")
		local _, fourth = Travel.request(tr, "a", 150)
		Travel.failed(tr, "a", 151, fourth)
		t.expect(Travel.status(tr, "a", 151)).toBe("cooling")
		t.expect(second ~= third).toBe(true)
	end)

	it(
		"a report with no ticket (the engine's init failure carries none) applies to the current request",
		function()
			local tr = Travel.new()
			Travel.request(tr, "a", 0)
			Travel.failed(tr, "a", 1)
			t.expect(Travel.status(tr, "a", 1)).toBe("cooling")
			Travel.request(tr, "b", 0)
			Travel.answered(tr, "b", 5)
			t.expect(Travel.status(tr, "b", 19.9)).toBe("going")
			t.expect(Travel.status(tr, "b", 20)).toBe("cooling")
		end
	)

	it("a player who leaves is forgotten", function()
		local tr = Travel.new()
		Travel.request(tr, "a", 0)
		Travel.left(tr, "a")
		t.expect(Travel.status(tr, "a", 1)).toBe("idle")
		t.expect(ask(tr, "a", 1)).toBe("go")
	end)

	it("players are separate", function()
		local tr = Travel.new()
		t.expect(ask(tr, "a", 0)).toBe("go")
		t.expect(ask(tr, "b", 0)).toBe("go")
		Travel.failed(tr, "a", 1)
		t.expect(Travel.status(tr, "b", 2)).toBe("going")
		t.expect(Travel.status(tr, "a", 2)).toBe("cooling")
	end)

	it("takes its times from the config it is given", function()
		local tr = Travel.new({ goingSeconds = 2, coolSeconds = 1, capSeconds = 5 })
		Travel.request(tr, "a", 0)
		Travel.answered(tr, "a", 0)
		t.expect(Travel.status(tr, "a", 2)).toBe("cooling")
		t.expect(Travel.status(tr, "a", 3)).toBe("idle")
	end)
end)
