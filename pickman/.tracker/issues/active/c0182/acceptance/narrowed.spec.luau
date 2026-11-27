--!strict
-- c0182 AC1: the promoted touch specs that d0149's circles replace are narrowed or removed, and every kept file is
-- pinned whole by the SHA-256 of its exact text (item ids masked, CRLF made LF; no whitespace tolerated, because a
-- newline ends a line comment: zz-test/narrowing-pins-the-whole-file). Four files with no surviving rule on both sides
-- of d0149 are removed together with their lines in their owners' check.sh files (landed in c0182's prep PR per
-- z-design/finished-overrides-land-before-ready): f0027/swipe, f0027/track, f0028/hit and f0110/hunt. The other 18
-- narrowed files stay, keep every rule d0149 keeps, and their owners' check.sh files still run them.
-- This spec reads the files as text: any later change to one of them must update its digest here (`exact` the file's
-- text, then `serde.hash("sha256", ...)`).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- Each pin names its spec by its full `tests/acceptance/<id>/...` path, which a compaction rewrites with the folder.
local PINS: { { path: string, sha: string } } = {
	{
		path = "tests/acceptance/f0027/place.spec.luau",
		sha = "e7d05051825c72bfb64e8d772e0ace90b844acc6a53c94f80da0300394f9f0de",
	},
	{
		path = "tests/acceptance/f0027/screen.spec.luau",
		sha = "4a956a5b792f9cb20c30f77ebc5053e9ca27347dc9329e99ddc2aa03eccb2f0e",
	},
	{
		path = "tests/acceptance/f0028/look.spec.luau",
		sha = "4abc3ebe20765526154513618a5fb25bfaebf314d0ed554f9b10c3c18465a06f",
	},
	{
		path = "tests/acceptance/f0028/place.spec.luau",
		sha = "ba5e6af3c6195dadd5b960673b0b4d73f1cfa6cb1785326ab4ef6dc44ff640c8",
	},
	{
		path = "tests/acceptance/f0029/button.spec.luau",
		sha = "29fee3b1793059369cf5906c5e678698b2995cca92ff6c79d8840c04a751218c",
	},
	{
		path = "tests/acceptance/f0029/jump.spec.luau",
		sha = "805da0c1025a1dabd8700c68e497c1426f6687219daaa56ee48c16e4840a683e",
	},
	{
		path = "tests/acceptance/f0029/phone.spec.luau",
		sha = "61cbb6105b7aba8d507c8d1739368a14c3fd8a8426bb2f45effa8740e12e9ebb",
	},
	{
		path = "tests/acceptance/f0029/place.spec.luau",
		sha = "7f4f0f648c348bd1da562ee65a43693dccfcf4e132cde537f7f5bf7d034a9ef8",
	},
	{
		path = "tests/acceptance/f0110/adapters.spec.luau",
		sha = "b04c453aacfae00589a7fc5af490e9d13522f0a1480db00e3ddfe2f779a40dba",
	},
	{
		path = "tests/acceptance/f0110/buttons.spec.luau",
		sha = "28376873b9c958130a14883f85a66e048740344bd199b1c0074492c7c06cbeb1",
	},
	{
		path = "tests/acceptance/f0110/fold.spec.luau",
		sha = "ab07d9d6e2ef641d95fab6a722e657a73f03125469dc730488a92201e678c5a7",
	},
	{
		path = "tests/acceptance/f0126/controls.spec.luau",
		sha = "67a8e65bebc8583404ca5f17580a23db248bac2fc640a8ee4cae269805a3ae77",
	},
	{
		path = "tests/acceptance/f0126/parts.spec.luau",
		sha = "ff7e1438b6992fe16a680a8fa9a2939fff0c0bbb84f0814c61e84d92ff526760",
	},
	{
		path = "tests/acceptance/f0126/touch.spec.luau",
		sha = "2fff9897695cc18707f05afce865e7e1b0020faa708541d9c99101d81377c2a4",
	},
	{
		path = "tests/acceptance/f0143/controls.spec.luau",
		sha = "ce7aff6591e12a6f2c4ff42e0172295ec8db7257c41d72aeb8f4576acf5c2461",
	},
	{
		path = "tests/acceptance/f0143/place.spec.luau",
		sha = "ed04b1a415ad48e30c5612539a3644c315f7cbed59b0f1ff36ba8a8c5564ccea",
	},
	{
		path = "tests/acceptance/f0158/clear.spec.luau",
		sha = "34437e3fddde0b58d4c03670d29a302688374a055212676d6e0971cf4a0fd799",
	},
	{
		path = "tests/acceptance/c0155/narrowed.spec.luau",
		sha = "a78f29aeb8a85c4d46be2e9a0fdc16322ade4b13b38f4897c896ba28c6c0dbb3",
	},
}

local REMOVED: { string } = {
	"tests/acceptance/f0027/swipe.spec.luau",
	"tests/acceptance/f0027/track.spec.luau",
	"tests/acceptance/f0028/hit.spec.luau",
	"tests/acceptance/f0110/hunt.spec.luau",
}

local function file(path: string): string
	return string.match(path, "[^/]+$") :: string
end

local function item(path: string): string
	return string.match(path, "^tests/acceptance/([^/]+)/") :: string
end

-- Exact text with item ids masked and CRLF made LF; nothing else changes.
local function exact(text: string): string
	text = string.gsub(text, "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

local function checkRuns(id: string, name: string): boolean
	local text = fs.readFile(".tracker/issues/done/" .. id .. "/check.sh")
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, 7) == 'check "' and string.find(line, `"$A/{name}"`, 1, true) then
			return true
		end
	end
	return false
end

return t.spec("c0182 touch pins narrowed for d0149", function(it)
	it(
		"the four files with no surviving rule are removed and their owners' check.sh no longer run them",
		function()
			for _, path in REMOVED do
				t.expect(fs.isFile(path)).toBe(false)
				t.expect(checkRuns(item(path), file(path))).toBe(false)
			end
		end
	)

	it("all 18 narrowed specs are still there and their owners' check.sh still run them", function()
		for _, pin in PINS do
			t.expect(fs.isFile(pin.path)).toBe(true)
			t.expect(checkRuns(item(pin.path), file(pin.path))).toBe(true)
		end
	end)

	for _, pin in PINS do
		it(pin.path .. " is exactly the narrowed file", function()
			local text = exact(fs.readFile(pin.path))
			t.expect(serde.hash("sha256", text)).toBe(pin.sha)
		end)
	end
end)
