--!strict
-- c0180: the three promoted specs this chore overrides hold exactly their narrowings (narrowings.luau): each holds the
-- new text once and the old text nowhere, and the whole file matches its digest, so no other line of it changed.
-- CRLF is written LF and item ids ID before hashing, so a checkout's line endings and a compaction leave the digests
-- valid. Runs from z-nile's home.
local fs = require("@lune/fs")
local narrowings = require("./narrowings")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local A = "tests/" .. "acceptance/"

local function count(text: string, needle: string): number
	local n, at = 0, 1
	while true do
		local s, e = string.find(text, needle, at, true)
		if not s then
			return n
		end
		n += 1
		at = (e :: number) + 1
	end
end

return t.spec("c0180 the overridden specs hold exactly their narrowings", function(it)
	for _, n in narrowings do
		it(`{n.id}/{n.file} holds its narrowing and nothing else changed`, function()
			local text = fs.readFile(`{A}{renamed.id(n.id)}/{n.file}`)
			t.expect(count(text, n.new)).toBe(1)
			t.expect(count(text, n.old)).toBe(0)
			local normalised = string.gsub((string.gsub(text, "\r\n", "\n")), "[cdfR]%d%d%d%d", "ID")
			t.expect(serde.hash("sha256", normalised)).toBe(n.digest)
		end)
	end
end)
