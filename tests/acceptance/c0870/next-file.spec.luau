--!strict
-- c0870: the real tracker carries tracker/next and it parses. Whether it is above every number in use is not a gate
-- rule (a branch's counter lags after an emergent issue reserves on origin): R0270's RC3 checks it once, at done.
local fs = require("@lune/fs")
local ids = require("@scripts/tracker/ids")
local t = require("@tests/lib/t")

return t.spec("c0870 the real tracker/next", function(it)
	it("exists and parses", function()
		t.expect(fs.isFile(ids.FILE)).toBe(true)
		t.expect(ids.parse(fs.readFile(ids.FILE)) ~= nil).toBe(true)
	end)
end)
