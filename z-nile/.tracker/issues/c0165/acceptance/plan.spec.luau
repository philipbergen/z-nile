--!strict
-- c0165 AC3, AC5 (pure part): what the orchestrator does with each spec given its db row (reuseplan.decide: reuse a
-- pass, else run), and which runs may record (reuseplan.records: only the host's strongest jail).
local reuseplan = require("@znile/lib/reuseplan")
local t = require("@tests/lib/t")

local function row(state: string): any
	return { state = state, updated = 1 }
end

return t.spec("c0165 reuse decisions", function(it)
	it("AC3: decide gives the table's action for every row", function()
		-- a passed row is reused; no row and a failed row run; --fresh runs every row
		t.expect(reuseplan.decide(nil, false)).toBe("run")
		t.expect(reuseplan.decide(row("passed"), false)).toBe("reuse")
		t.expect(reuseplan.decide(row("failed"), false)).toBe("run")
		t.expect(reuseplan.decide(nil, true)).toBe("run")
		t.expect(reuseplan.decide(row("passed"), true)).toBe("run")
		t.expect(reuseplan.decide(row("failed"), true)).toBe("run")
	end)

	it("AC5: only a run in the host's strongest jail records", function()
		t.expect(reuseplan.records("sandbox-exec", "macos")).toBe(true)
		t.expect(reuseplan.records("outer sandbox (a fixture of a guarded checkout)", "macos")).toBe(true)
		t.expect(reuseplan.records("outer sandbox (protects the repository)", "macos")).toBe(false)
		t.expect(reuseplan.records("none (not macOS)", "macos")).toBe(false)
		t.expect(reuseplan.records("", "macos")).toBe(false)
		t.expect(reuseplan.records("none (not macOS)", "linux")).toBe(true)
		t.expect(reuseplan.records("outer sandbox (a fixture of a guarded checkout)", "linux")).toBe(false)
		-- an empty jail is no jail the runner chose: it records nothing, on any host
		t.expect(reuseplan.records("", "linux")).toBe(false)
	end)
end)
