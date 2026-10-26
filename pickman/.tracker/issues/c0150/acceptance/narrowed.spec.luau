--!strict
-- c0150 AC1: two promoted pins are narrowed, not deleted, so f0126 can bind F to the wall pick and pass the hop's
-- length to Hop.rise. f0104's key map still pins its ten bindings, the arrows and Space not moving, the unbound keys
-- (all but F) and the frozen map, and now allows more keys; f0101's camera case still pins the eye as the standing
-- height plus Hop.rise of the server's hop at the shown tick, in one CFrame, and now allows further arguments.
-- Each narrowed file is pinned whole, by the SHA-256 of its exact text with only item ids masked (so a compaction
-- cannot break it) and line endings made LF: no whitespace is tolerated, because a newline ends a line comment and
-- spaces inside a string are part of what it asserts (design review 001 F3). `stylua` leaves the narrowed files as
-- they are. This spec reads them as text, so `--affected` never selects it (only `--full` runs it): any later
-- change to either file must update the digest here.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- spelled in two parts so a compaction does not rewrite them; the ids are mapped through the compaction map
local KEYS = "tests/" .. "acceptance/" .. renamed.id("f0104") .. "/keys.spec.luau"
local PLACE = "tests/" .. "acceptance/" .. renamed.id("f0101") .. "/place.spec.luau"

-- the file's text with item ids masked and CRLF made LF; nothing else changes
local function exact(path: string): string
	local text = string.gsub(fs.readFile(path), "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

local KEYS_SHA = "5c0b8c38db40ae532222f545e2a627dee93606596f41a9415c842dab11457d6c"
local PLACE_SHA = "4c1a590829848fbcefd0955a53f441a96bf96640da4f489a03517b1eae9916a5"

return t.spec("c0150 the key-map and hop-camera pins, narrowed", function(it)
	it("both specs are still there, and their items' check.sh files still run them", function()
		t.expect(fs.isFile(KEYS)).toBe(true)
		t.expect(fs.isFile(PLACE)).toBe(true)
		local keysCheck = fs.readFile(".tracker/issues/done/" .. renamed.id("f0104") .. "/check.sh")
		local placeCheck = fs.readFile(".tracker/issues/done/" .. renamed.id("f0101") .. "/check.sh")
		t.expect(string.find(keysCheck, '"$A/keys.spec.luau"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(placeCheck, '"$A/place.spec.luau"', 1, true) ~= nil).toBe(true)
	end)

	it(
		"the key map is exactly the narrowed one: the ten bindings pinned, more keys allowed each with an action of its own, F free",
		function()
			local text = exact(KEYS)
			t.expect(string.find(text, "t.expect(n >= 10).toBe(true)", 1, true) ~= nil).toBe(true)
			t.expect((string.find(text, '"Q", "F",', 1, true))).toBe(nil)
			t.expect(serde.hash("sha256", text)).toBe(KEYS_SHA)
		end
	)

	it(
		"the camera case is exactly the narrowed one: Hop.rise of the hop at the shown tick, more arguments allowed",
		function()
			local text = exact(PLACE)
			t.expect(string.find(text, "([%w_]+)%s*[,%)]", 1, true) ~= nil).toBe(true)
			t.expect(serde.hash("sha256", text)).toBe(PLACE_SHA)
		end
	)
end)
