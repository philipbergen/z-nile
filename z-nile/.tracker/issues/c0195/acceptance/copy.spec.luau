--!strict
-- c0195 AC1: in a repository the fence protects, its git refuses a branch copy in every spelling git accepts
-- (`branch -c`/`-C`/`--copy`, an abbreviation, a cluster, git's own options before the command), before git runs:
-- the repository's refs and reflogs stay as they were. The same command line copies the branch in a fixture the fence
-- does not protect. On every git this machine has (harness.luau).
local fs = require("@lune/fs")
local h = require("./harness")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local COPIES: { { string } } = {
	{ "branch", "-c", "main", "evil" },
	{ "branch", "-C", "main", "side" },
	{ "branch", "--copy", "main", "evil" },
	{ "branch", "--cop", "main", "evil" },
	{ "branch", "--force", "--copy", "main", "side" },
	{ "branch", "-c", "evil" }, -- the current branch
	{ "branch", "-fc", "main", "side" },
	{ "branch", "-qc", "main", "evil" },
	{ "branch", "-vC", "main", "evil" },
	{ "branch", "-cf", "main", "side" }, -- the copy flag first in its cluster
	{ "branch", "-c", "--end-of-options", "main", "evil" },
	{ "-c", "core.abbrev=12", "branch", "-c", "main", "evil" },
	{ "--no-pager", "branch", "-C", "main", "evil" },
	{ "--namespace", "x", "--attr-source", "HEAD", "branch", "-c", "main", "evil" },
	{ "--shallow-file", "status", "branch", "-c", "main", "evil" }, -- git takes `status` as the option's value
}

local base = h.fresh("copy")

return t.spec("c0195 a branch copy is refused in a protected repository", function(it)
	it(
		"finds every git this machine has (on macOS with the Command Line Tools, theirs and the PATH's)",
		function()
			t.expect(#h.GITS >= 1).toBe(true)
			if process.os == "macos" and fs.isFile(h.CLT) then
				local clt = h.trim(process.exec(h.CLT, { "--version" }).stdout)
				local found = false
				for _, g in h.GITS do
					found = found or g.version == clt
				end
				t.expect(found).toBe(true)
			end
		end
	)

	for _, g in h.GITS do
		it(
			`AC1: every spelling of a branch copy is refused, and the repository stays as it was ({g.version})`,
			function()
				h.refusedHereRunsThere(base, g, "copy", COPIES, h.REFUSED_COPY)
			end
		)
	end

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
