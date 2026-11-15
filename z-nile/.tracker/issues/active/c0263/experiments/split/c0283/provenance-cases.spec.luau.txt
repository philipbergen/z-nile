--!strict
-- EXCERPT of c0263 provenance.spec for c0283 (approval gate): the approval check, the frozen list. Needs approval, approvalProblem, exemptParse, exemptRender.
-- resolution, the trailer and commit actors, the record (rows, append-only, the closed event list), the approval check
-- against the design hash, the per-item selector over the git log and the merge `who` prints, and the documentation.
-- Everything here is text in, text out.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local OPUS = "agent:claude-opus-5-5 effort high"

return t.spec("c0263 ticket provenance", function(it)
	it("the approval check", function()
		local function rows(text: string?): { any }
			return (provenance.parse(text :: string) or {}) :: { any }
		end
		local none = provenance.record(nil, "c0010", "unblocked", OPUS, "", "2026-11-08 09:00") :: string
		t.expect((provenance.approval(rows(none), "aaaaaaaaaaaa"))).toBe("none")
		local one = provenance.record(
			none,
			"c0010",
			"approved",
			"human:Ann",
			'design=aaaaaaaaaaaa; said="ok"',
			"2026-11-08 10:00"
		) :: string
		t.expect((provenance.approval(rows(one), "aaaaaaaaaaaa"))).toBe("current")
		-- a redesign changes the hash: stale, and it says what the approval covered
		local state, old = provenance.approval(rows(one), "bbbbbbbbbbbb")
		t.expect(state).toBe("stale")
		t.expect(old).toBe("aaaaaaaaaaaa")
		-- the newest approval decides, not the first and not a match anywhere in the history
		local two = provenance.record(
			one,
			"c0010",
			"approved",
			"human:Ann",
			"design=bbbbbbbbbbbb",
			"2026-11-08 11:00"
		) :: string
		t.expect((provenance.approval(rows(two), "bbbbbbbbbbbb"))).toBe("current")
		t.expect((provenance.approval(rows(two), "aaaaaaaaaaaa"))).toBe("stale")
		-- a row without a design hash approves nothing
		local bare =
			provenance.record(nil, "c0010", "approved", "human:Ann", 'said="ok"', "2026-11-08 10:00") :: string
		t.expect((provenance.approval(rows(bare), "aaaaaaaaaaaa"))).toBe("stale")
	end)

	it("the frozen list", function()
		local list = provenance.exemptParse("# comment\nc0260 1a2b3c4d5e6f\nf0010 aaaaaaaaaaaa\n")
		t.expect(list).toEqual({ c0260 = "1a2b3c4d5e6f", f0010 = "aaaaaaaaaaaa" })
		-- no file on the base: the rule is not in force (nil), not an empty list
		t.expect((provenance.exemptParse(nil))).toBe(nil)
		-- a malformed or repeated line is refused, not skipped
		for _, bad in
			{ "c0260\n", "c0260 nothex\n", "c0260 aaaaaaaaaaaa\nc0260 bbbbbbbbbbbb\n", "stray text\n" }
		do
			local got, why = provenance.exemptParse(bad)
			t.expect(got).toBe(nil)
			t.expect(why ~= nil).toBe(true)
		end
		-- render then parse is the identity, sorted, with the two comment lines first
		local rendered = provenance.exemptRender({ c0260 = "1a2b3c4d5e6f", c0010 = "aaaaaaaaaaaa" })
		t.expect(string.sub(rendered, 1, 1)).toBe("#")
		t.expect((provenance.exemptParse(rendered)))
			.toEqual({ c0260 = "1a2b3c4d5e6f", c0010 = "aaaaaaaaaaaa" })
		-- the doors: not in force without a list; a current approval passes; a listed issue passes only at its listed design
		local none = {} :: { provenance.Row }
		local current = provenance.parse(
			provenance.record(
				nil,
				"c0010",
				"approved",
				"human:Ann",
				"design=cccccccccccc",
				"2026-11-08 10:00"
			) :: string
		) :: { provenance.Row }
		t.expect(provenance.approvalProblem("c0010", "cccccccccccc", none, nil)).toBe(nil)
		t.expect(provenance.approvalProblem("c0010", "cccccccccccc", current, {})).toBe(nil)
		t.expect(provenance.approvalProblem("c0010", "dddddddddddd", none, { c0010 = "dddddddddddd" }))
			.toBe(nil)
		t.expect(
			string.find(
				provenance.approvalProblem("c0010", "eeeeeeeeeeee", none, { c0010 = "dddddddddddd" }) :: string,
				"redesigned since the freeze",
				1,
				true
			) ~= nil
		).toBe(true)
		t.expect(
			string.find(
				provenance.approvalProblem("c0011", "dddddddddddd", none, { c0010 = "dddddddddddd" }) :: string,
				"without an approval",
				1,
				true
			) ~= nil
		).toBe(true)
		t.expect(
			string.find(
				provenance.approvalProblem("c0010", "dddddddddddd", current, {}) :: string,
				"no longer covers",
				1,
				true
			) ~= nil
		).toBe(true)
		-- a listed issue with a stale approval at the listed design still passes (the list is its approval until it changes)
		t.expect(provenance.approvalProblem("c0010", "dddddddddddd", current, { c0010 = "dddddddddddd" }))
			.toBe(nil)
	end)

end)
