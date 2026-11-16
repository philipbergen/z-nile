--!strict
-- c0322 AC3: c0084's commit-phase.spec is the spec that was red, and the fix meets its expectation instead of
-- changing it. This pins that the case and its expectation are still there, by their text; that this issue's branch
-- left the whole file alone is check.sh's own line (a comparison with the merge base, never promoted: other items
-- edit other cases of that file, and a promoted digest would charge each of them).
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

return t.spec("c0322 the spec that was red still expects the plain bind subject", function(it)
	it("commit-phase.spec holds the case and its subject expectation", function()
		local text = fs.readFile("tests/acceptance/c0084/commit-phase.spec.luau")
		local case = string.find(
			text,
			'it("done records its own commit as deliver, and the raft summary shows each phase"',
			1,
			true
		)
		t.expect(case ~= nil).toBe(true)
		local expectation =
			string.find(text, "t.expect(ra[#ra].subject).toBe(`{raft}: bind {a}, {b}`)", 1, true)
		t.expect(expectation ~= nil and (expectation :: number) > (case :: number)).toBe(true)
	end)
end)
