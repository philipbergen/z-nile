--!strict
-- f0420 step 4c (pure): the notice a worker that lost its claim is shown, the history line of `work status`, and the
-- carrier rows an expiry frees. The daemon's own rules (expiry, marker, restart, race) are Go tests in go/internal/live.
local liveloss = require("@znile/engine/liveloss")
local liveview = require("@znile/engine/liveview")
local t = require("@tests/lib/t")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local LOSS: liveloss.Loss = {
	worker = "claude-7@h",
	unit = "R0100",
	activity = "code",
	at = 1_700_000_000,
	since = 1_699_990_000,
	reason = "silent for 1800 s",
	holder = "grok-3@h",
	session = "sess-1",
}

return t.spec("f0420 step 4c: claim expiry, as the worker and the board see it", function(it)
	it("the notice names the unit, the activity, the time, the holder and what to do", function()
		local text = liveloss.notice(LOSS, 1_700_000_100)
		t.expect(string.sub(text, 1, 10)).toBe("LOST CLAIM")
		t.expect(has(text, "R0100")).toBe(true)
		t.expect(has(text, "code")).toBe(true)
		t.expect(has(text, "grok-3@h")).toBe(true)
		t.expect(has(text, "PST") or has(text, "PDT")).toBe(true)
		t.expect(has(text, "do not push")).toBe(true)
		t.expect(has(text, "./zn work next")).toBe(true)
	end)

	it("the notice says so when nobody holds the unit now", function()
		local free = table.clone(LOSS)
		free.holder = nil
		t.expect(has(liveloss.notice(free, 1_700_000_100), "nobody holds it now")).toBe(true)
	end)

	it("the answer of work next is a wait that starts with the notice", function()
		local d = liveloss.answer({ LOSS }, 1_700_000_100)
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, 10)).toBe("LOST CLAIM")
		t.expect(d.raft).toBe("")
	end)

	it("freeCarriers drops only the rows of the lost worker's session on that unit", function()
		local carriers = {
			R0100 = { session = "sess-1", age = 5 },
			R0200 = { session = "sess-1", age = 5 },
			R0300 = { session = "sess-2", age = 5 },
		}
		local freed = liveloss.freeCarriers(carriers, { LOSS })
		t.expect(freed.R0100).toBe(nil)
		t.expect(freed.R0200 ~= nil).toBe(true)
		t.expect(freed.R0300 ~= nil).toBe(true)
		t.expect(carriers.R0100 ~= nil).toBe(true) -- the input is not changed
	end)

	it("work status shows an expired claim as expired, with the time, and who holds it now", function()
		local live = liveview.slim({
			ok = true,
			at = 1_700_000_100,
			workers = {},
			claims = {},
			losses = { LOSS },
		} :: any)
		t.expect(live ~= nil).toBe(true)
		local lines = liveview.lossLines(live :: any)
		t.expect(#lines).toBe(1)
		t.expect(has(lines[1], "R0100")).toBe(true)
		t.expect(has(lines[1], "expired")).toBe(true)
		t.expect(has(lines[1], "claude-7@h")).toBe(true)
		t.expect(has(lines[1], "grok-3@h")).toBe(true)
	end)
end)
