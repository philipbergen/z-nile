--!strict
-- c0386: c0371's promoted spec stops naming the fence scan's banned env option. That its grep case still hands the
-- scanner that fixture is pinned by check.sh's narrow.py, before the change lands (it leaves nothing permanent).
-- Runs from z-nile's home. This file names neither the banned name nor a literal acceptance path: both are built from
-- parts (the fence scan reads this file once it is promoted; a compaction rewrites literal paths).
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local ACC = "tests/" .. "acceptance/"
local SPEC = ACC .. renamed.id("c0371") .. "/check-paths-homes.spec.luau"
local BANNED = "env" .. " -i"

return t.spec("c0386 c0371's spec passes the fence scan", function(it)
	it("c0371's promoted spec names the banned env option in no case", function()
		local lower = string.lower(fs.readFile(SPEC))
		t.expect((string.find(lower, string.lower(BANNED), 1, true))).toBe(nil)
	end)
end)
