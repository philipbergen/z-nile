--!strict
-- c0195 AC4: in a repository the fence protects, its git refuses every command that is not one of git's own (an alias,
-- whose expansion it can't see, in any form: a git command, `!` a shell command, git's own options first; and an
-- external command): the repository stays as it was. The same aliases run in a fixture the fence does not protect.
-- On every git this machine has (harness.luau).
local fs = require("@lune/fs")
local h = require("./harness")
local t = require("@tests/lib/t")

local OTHERS: { { string } } = {
	{ "-c", "alias.cp=branch -c", "cp", "main", "evil" },
	{ "-c", "alias.cp=!git branch -c main evil", "cp" },
	{ "-c", "alias.nb=-c core.abbrev=12 branch -c main evil", "nb" },
	{ "-c", "alias.rn=branch -m side moved", "rn" },
}

local base = h.fresh("others")

return t.spec("c0195 an alias or an external command is refused in a protected repository", function(it)
	for _, g in h.GITS do
		it(
			`AC4: an alias is refused in a protected repository, and runs in a fixture ({g.version})`,
			function()
				h.refusedHereRunsThere(base, g, "others", OTHERS, h.REFUSED_OTHER)
			end
		)

		it(`AC4: an external command is refused in a protected repository ({g.version})`, function()
			-- one git would look for as git-<name> on the PATH
			local b =
				h.runForms(base, g, "external", { { where = "real", args = { "c0195-no-such-command" } } })
			t.expect(b.ran[1].code ~= 0).toBe(true)
			t.expect(h.has(b.ran[1].stderr, h.REFUSED_OTHER)).toBe(true)
			t.expect(b.after).toBe(b.before)
		end)
	end

	it("cleans up", function()
		h.remove(base)
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
