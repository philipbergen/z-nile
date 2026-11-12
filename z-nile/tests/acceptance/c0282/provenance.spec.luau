--!strict
-- c0282 AC6, AC7 (the pure parts): the dispatcher step a script step runs under (`ZN_VIA`) is `dispatch:<step>` or
-- nothing, and a lifecycle row that names a raft says `raft=<R-id>` and then `via=` only when a step ran it; the docs
-- name the lifecycle rows.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")

return t.spec("c0282 lifecycle rows, the pure parts", function(it)
	it("via accepts dispatch:<step>, nothing for unset or empty, and refuses the rest", function()
		t.expect((provenance.via("dispatch:raft-plan"))).toBe("dispatch:raft-plan")
		t.expect((provenance.via("dispatch:z-ready"))).toBe("dispatch:z-ready")
		t.expect((provenance.via(nil))).toBe(nil)
		t.expect((provenance.via(""))).toBe(nil)
		t.expect(select(2, provenance.via(nil))).toBe(nil)
		for _, bad in
			{
				"dispatch",
				"dispatch:",
				"dispatch:Raft",
				"dispatch:a b",
				"x:y",
				"dispatch:a; raft=R9",
				"dispatch:a|b",
			}
		do
			local value, why = provenance.via(bad)
			t.expect(value).toBe(nil)
			t.expect(why ~= nil and string.find(why :: string, "ZN_VIA", 1, true) ~= nil).toBe(true)
		end
	end)

	it("raftDetail names the raft, and the step only when there is one", function()
		t.expect(provenance.raftDetail("R0100", nil)).toBe("raft=R0100")
		t.expect(provenance.raftDetail("R0100", "dispatch:raft-plan"))
			.toBe("raft=R0100; via=dispatch:raft-plan")
		-- the detail is a record cell: it round-trips through record and parse
		local text = provenance.record(
			nil,
			"c0010",
			"rafted",
			"agent:claude-opus-5-5 effort high",
			provenance.raftDetail("R0100", "dispatch:raft-plan"),
			"2026-11-09 10:00"
		) :: string
		local rows = (provenance.parse(text)) :: { provenance.Row }
		t.expect(rows[1].detail).toBe("raft=R0100; via=dispatch:raft-plan")
	end)

	it("docs", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local function has(path: string, ...: string)
			local text = fs.readFile(`{top}/{path}`)
			for _, needle in { ... } do
				if not string.find(text, needle, 1, true) then
					error(`{path} lacks {needle}`, 2)
				end
			end
		end
		has(
			"z-nile/skills/zz-rules/SKILL.md",
			"**Lifecycle rows**",
			"`status <id> new` publishes an `unblocked` row",
			"`new raft`, `fold`, `recombine` and an emergent `new issue --raft` append `rafted",
			"`done` appends `delivered",
			"ZN_VIA",
			"only as appended `rafted` rows",
			"and the `unblocked` row `status <id> new` adds to its own commit",
			"(which records who gave it back)",
			"appends a `delivered` row to each member's `provenance.md` (staged with the moves"
		)
		has("z-nile/README.md", "`unblocked`, `rafted` and `delivered` rows")
	end)
end)
