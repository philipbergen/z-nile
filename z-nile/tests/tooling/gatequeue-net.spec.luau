--!strict
-- d0426 F4: a gate that did not start (exit 75, another gate held the machine) is neither a pass nor a failure for the
-- watch net: no defect, no pass recorded, nothing pushed. The fixture's stub suite (tests/lib/netfix) exits with the
-- code the spec writes to hold/exit-code.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local netfix = require("@tests/lib/netfix")
local t = require("@tests/lib/t")

local has, read = netfix.has, netfix.read

return t.spec("d0426 the watch net reads exit 75 as not run", function(it)
	it("a gate that did not start records no pass and opens no defect", function()
		local w = netfix.world("d0426-net-notstarted", { standing = true })
		fs.writeFile(`{w.hold}/exit-code`, "75\n")
		local before = fixture.git(w.f.main, { "ls-remote", w.f.origin, "refs/heads/main" })
		local r = netfix.kick(w, w.raft)
		t.expect(r.code).toBe(0)
		local log = netfix.logOf(r.stdout) :: string
		t.expect(netfix.settle(log)).toBe("0")
		t.expect(has(read(log), "the gate did not start")).toBe(true)
		t.expect(has(read(log), "named no spec")).toBe(false)
		t.expect(fixture.git(w.f.main, { "ls-remote", w.f.origin, "refs/heads/main" })).toBe(before)
	end)
end)
