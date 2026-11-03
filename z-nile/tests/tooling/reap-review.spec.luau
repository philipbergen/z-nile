--!strict
-- c0191 code review 001 (F6): the reaper refuses a --root that contains the home folder (`/Users` with --min-age 0 would
-- cover every user folder), and still accepts a folder inside the repository.
local reap = require("@znile/engine/reap")
local t = require("@tests/lib/t")

local function over(roots: { string }): string?
	return reap.checkOptions({
		roots = roots,
		under = nil,
		underIsClaude = false,
		minAge = 0,
		home = "/Users/me",
	})
end

return t.spec("reaper option refusals from review", function(it)
	it("a --root that holds the home folder is refused, a folder inside the repository is not", function()
		local parent = over({ "/Users" })
		t.expect(parent ~= nil and string.find(parent, "contains the home folder", 1, true) ~= nil).toBe(true)
		t.expect(over({ "/Users/" }) ~= nil).toBe(true)
		t.expect(over({ "/Users/me/code/pickman/.cache/reapfix-review" })).toBe(nil)
		t.expect(over({ "/fixture" })).toBe(nil)
		t.expect(over({ "/Users/mel" })).toBe(nil)
	end)
end)
