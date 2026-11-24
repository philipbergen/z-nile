--!strict
-- f0428 step 4: claims.remember writes a remembered claim into a checkout's cache folder; started by a host's front door
-- (front), it refuses a cache folder that is a link, writes nothing through it, and says what to do. Fixtures under
-- .cache/claim-remember.
local claims = require("@znile/engine/claims")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local base = ""

local function isLink(p: string): boolean
	return process.exec("test", { "-L", p }).ok
end

return t.spec("claims.remember", function(it)
	it("sets up a checkout whose cache folder is a link to a folder outside it", function()
		local root = fixture.physical(".") :: string
		base = `{root}/.cache/claim-remember`
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(`{base}/linked`)
		fs.writeDir(`{base}/target`)
		fs.writeDir(`{base}/plain`)
		t.expect(process.exec("ln", { "-s", `{base}/target`, `{base}/linked/.cache` }).ok).toBe(true)
		t.expect(isLink(`{base}/linked/.cache`)).toBe(true)
	end)

	it(
		"in a host's tracker, a cache folder that is a link is refused and nothing is written through it",
		function()
			local why = claims.remember(`{base}/linked/.cache/tracker-claim-R0010`, "active-x", true)
			t.expect(why ~= nil).toBe(true)
			local said = why :: string
			t.expect(string.find(said, `{base}/linked/.cache is a link`, 1, true) ~= nil).toBe(true)
			t.expect(string.find(said, "Remove it, then run the command again", 1, true) ~= nil).toBe(true)
			t.expect(#fs.readDir(`{base}/target`)).toBe(0)
			t.expect(isLink(`{base}/linked/.cache`)).toBe(true)
		end
	)

	it("in a host's tracker, a plain cache folder is made and the claim written", function()
		t.expect(claims.remember(`{base}/plain/.cache/tracker-claim-R0010`, "active-y", true)).toBe(nil)
		t.expect(fs.readFile(`{base}/plain/.cache/tracker-claim-R0010`)).toBe("active-y")
	end)

	it("outside a host the claim is written as before", function()
		t.expect(claims.remember(`{base}/plain/.cache/tracker-claim-R0020`, "active-z", false)).toBe(nil)
		t.expect(fs.readFile(`{base}/plain/.cache/tracker-claim-R0020`)).toBe("active-z")
	end)
end)
