--!strict
-- c0195 AC2: in a repository the fence protects, its git refuses a branch rename in every spelling git accepts
-- (`branch -m`/`-M`/`--move`, an abbreviation, a cluster) before git runs, so the branch's reflog is not moved aside
-- (git 2.50 and 2.54 leave it at logs/refs/.tmp-renamed-log when the hook refuses the rename). The same command line
-- renames the branch in a fixture the fence does not protect. On every git this machine has (harness.luau).
local fs = require("@lune/fs")
local h = require("./harness")
local t = require("@tests/lib/t")

local RENAMES: { { string } } = {
	{ "branch", "-m", "side", "moved" },
	{ "branch", "-M", "side", "main2" },
	{ "branch", "--move", "side", "moved" },
	{ "branch", "--mo", "side", "moved" },
	{ "branch", "--mov", "side", "moved" },
	{ "branch", "-m", "renamed" }, -- the current branch
	{ "branch", "-fm", "side", "main2" },
	{ "branch", "-Mf", "side", "main2" }, -- the move flag first in its cluster
}

local base = h.fresh("rename")

return t.spec("c0195 a branch rename is refused in a protected repository", function(it)
	for _, g in h.GITS do
		it(
			`AC2: every spelling of a branch rename is refused before git moves the reflog ({g.version})`,
			function()
				h.refusedHereRunsThere(base, g, "rename", RENAMES, h.REFUSED_COPY)
			end
		)
	end

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
