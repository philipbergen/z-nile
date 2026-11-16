--!strict
-- c0386: c0371's promoted spec stops naming the fence scan's banned env option and still hands the scanner that fixture.
-- Runs from z-nile's home. This file names neither the banned name nor a literal acceptance path: both are built from
-- parts (the fence scan reads this file once it is promoted; a compaction rewrites literal paths).
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local ACC = "tests/" .. "acceptance/"
local SPEC = ACC .. renamed.id("c0371") .. "/check-paths-homes.spec.luau"
local BANNED = "env" .. " -i"
local FIXTURE = BANNED .. ' grep -qF "src/nothing" "$F"'
local TITLE = "grep's pattern is text as main reads it"

-- the source of the case titled TITLE, up to the next case of the spec
local function caseBody(text: string): string
	local at = string.find(text, TITLE, 1, true)
	t.expect(at ~= nil).toBe(true)
	local rest = string.sub(text, at :: number)
	local stop = string.find(rest, "\n\tit%(")
	return if stop then string.sub(rest, 1, stop) else rest
end

-- the text with every Luau concatenation of two string literals joined ("a" .. 'b' reads as ab)
local function joined(text: string): string
	return (string.gsub(text, "[\"']%s*%.%.%s*[\"']", ""))
end

return t.spec("c0386 c0371's spec passes the fence scan", function(it)
	it("c0371's promoted spec names the banned env option in no case", function()
		local lower = string.lower(fs.readFile(SPEC))
		t.expect((string.find(lower, string.lower(BANNED), 1, true))).toBe(nil)
	end)

	it(
		"its grep case still hands the scanner an unquoted grep after env and an option, and expects nothing",
		function()
			local body = caseBody(fs.readFile(SPEC))
			t.expect(string.find(joined(body), FIXTURE, 1, true) ~= nil).toBe(true)
			t.expect(
				string.find(body, 't.expect(findings("z-nile", {}, text .. "\\n")).toEqual({})', 1, true)
					~= nil
			)
				.toBe(true)
		end
	)
end)
