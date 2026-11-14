--!strict
-- c0283 AC1: the pure half. `provenance.approved` writes the approved row of a design approval (the human, and the first
-- 12 hex of approval.md's hash as `design=`), and `provenance.hint` reads the one list of agent markers.
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")

local HASH = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

return t.spec("c0283 the approved row", function(it)
	it("is one row: the human, the first 12 hex of the hash, and the record it joins", function()
		local text = provenance.approved(nil, "c0010", "Ann Lee", HASH, "2026-11-12 09:00") :: string
		local rows = provenance.parse(text) :: { provenance.Row }
		t.expect(#rows).toBe(1)
		t.expect(rows[1]).toEqual({
			when = "2026-11-12 09:00",
			event = "approved",
			actor = "human:Ann Lee",
			detail = "design=0123456789ab",
		})
		-- a later approval appends: the old row is kept as it was
		local again = provenance.approved(
			text,
			"c0010",
			"Bob",
			"f" .. string.sub(HASH, 2),
			"2026-11-12 10:00"
		) :: string
		local both = provenance.parse(again) :: { provenance.Row }
		t.expect(#both).toBe(2)
		t.expect(both[1]).toEqual(rows[1])
		t.expect(both[2].detail).toBe("design=f123456789ab")
		t.expect(provenance.appendOnly(text, again, "c0010")).toBe(nil)
	end)

	it("refuses a name the record cannot hold and a record that does not parse, writing nothing", function()
		for _, name in { "Ann | Lee", "Ann\nLee", "" } do
			local text, why = provenance.approved(nil, "c0010", name, HASH, "2026-11-12 09:00")
			t.expect(text).toBe(nil)
			t.expect(why ~= nil).toBe(true)
		end
		local text, why = provenance.approved("not a record\n", "c0010", "Ann", HASH, "2026-11-12 09:00")
		t.expect(text).toBe(nil)
		t.expect(why ~= nil).toBe(true)
	end)

	it("takes each agent marker as an agent session, and none of them as a human one", function()
		t.expect(provenance.AGENT_VARS)
			.toEqual({ "CLAUDECODE", "AI_AGENT", "CURSOR_AGENT", "GROK_SESSION_ID", "ZN_DISPATCH" })
		for _, name in provenance.AGENT_VARS do
			t.expect(provenance.hint({ [name] = "1" }).agent).toBe(true)
			t.expect(provenance.hint({ [name] = "" }).agent).toBe(false)
		end
		t.expect(provenance.hint({ CLAUDE_EFFORT = "high", ZN_ACTOR = "human:Ann" }).agent).toBe(false)
	end)
end)
