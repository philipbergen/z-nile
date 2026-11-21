--!strict
-- R0138 review 001 F6: a lock guard that cannot be taken over fails closed. The case waits out the guard's 100 tries (about
-- 10 s), so it has a file of its own (each spec file stays under 30 s).
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local t = require("@tests/lib/t")
local watch = require("@znile/lib/watch")

local has = netfix.has

return t.spec("a lock guard that cannot be taken over", function(it)
	it("a lock guard that cannot be taken over ends the net with one line, and no suite runs", function()
		local g = netfix.world("r0138-guard", { standing = true })
		-- a guard that is not an empty folder: neither the take-over's rmdir nor its mkdir can work
		local guard = `{watch.filesDir(g.main)}/guard`
		fs.writeDir(guard)
		fs.writeFile(`{guard}/stuck`, "x\n")
		local r = netfix.kick(g, g.raft)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "watch-net: cannot take the lock's guard")).toBe(true)
		t.expect(fs.isFile(`{g.hold}/runs`)).toBe(false)
		t.expect(fs.isFile(`{watch.filesDir(g.main)}/lock`)).toBe(false)
	end)
end)
