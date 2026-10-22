--!strict
-- c0870: the real tracker carries its counter and it parses. Whether it is above every number in use is not a gate
-- rule (a branch's counter lags after an emergent issue reserves on origin): R0270's RC3 checks it once, at done.
-- c0114: the counter is z-nile/next once origin has moved it, and the old file until then (the branch never moves it).
local fs = require("@lune/fs")
local ids = require("@scripts/tracker/ids")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- c0120 override: specs run from z-nile's home, so the real counter is read from the checkout's top
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0870 the real tracker/next", function(it)
	it("exists and parses", function()
		local file = if fs.isFile(`{TOP}/{ids.FILE}`) then `{TOP}/{ids.FILE}` else `{TOP}/{ids.OLD_FILE}`
		t.expect(fs.isFile(file)).toBe(true)
		t.expect(ids.parse(fs.readFile(file)) ~= nil).toBe(true)
	end)
end)
