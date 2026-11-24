--!strict
-- f0437 slice 2 (review F16): the page's tests need node. A bare run may skip them (and says so); the gate (check.sh sets
-- ZN_MEASURE_KIND around its run) must fail when node is missing, naming what to install, so the page is never untested by accident.
local fs = require("@lune/fs")
local nodecheck = require("@tests/lib/nodecheck")
local t = require("@tests/lib/t")

return t.spec("f0437 slice 2: a missing node fails the gate and only skips a bare run", function(it)
	it("node present: the tests run", function()
		t.expect(nodecheck.available(true, true)).toBe(true)
		t.expect(nodecheck.available(true, false)).toBe(true)
	end)

	it("node missing in a bare run: skipped, said so", function()
		t.expect(nodecheck.available(false, false)).toBe(false)
	end)

	it("node missing under the gate: fails and names what to install", function()
		local ok, err = pcall(nodecheck.available, false, true)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "install node", 1, true) ~= nil).toBe(true)
	end)

	it("every spec that runs the page's node tests asks it", function()
		for _, name in { "app-md", "app-links", "app-cli" } do
			local text = fs.readFile(`tests/tooling/{name}.spec.luau`)
			t.expect(string.find(text, "nodecheck", 1, true) ~= nil).toBe(true)
		end
	end)
end)
