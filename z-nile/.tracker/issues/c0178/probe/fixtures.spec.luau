--!strict
-- c0178 check-only probe (never promoted: it lives outside acceptance/): one run makes ten trackerfix fixtures with the
-- skills' lessons and five without, each with one seeded file, so check.sh can meter what a fixture costs (AC2). It asserts
-- only that each fixture is a usable repository; the numbers are the check's.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local SEED = { ["z-nile/c0178-probe.txt"] = "probe\n" }

return t.spec("c0178 probe: fixtures in one run", function(it)
	it("makes ten fixtures with lessons and five without", function()
		for i = 1, 15 do
			local f = trackerfix.new(`c0178-probe-{i}`, SEED, { noLessons = i > 10 })
			t.expect(fs.readFile(`{f.main}/z-nile/c0178-probe.txt`)).toBe("probe\n")
			t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
		end
	end)
end)
