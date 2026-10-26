--!strict
-- c0153 AC2: the five promoted specs that round-tripped a snapshot or frame exactly now use plain.roundTrip within
-- 1e-9 (`git grep -nE 'serde\.decode\("json", (serde\.encode|text\))' -- pickman/tests` found them: f0013 snapshot,
-- f0018 frame, f0030 frame, f0032 frame, f0100 drops), and nothing else in them changed. Each narrowed file is
-- pinned whole, by the SHA-256 of its exact text with only item ids masked (so a compaction cannot break it) and line
-- endings made LF: no whitespace is tolerated, because a newline ends a line comment and spaces inside a string are
-- part of what it asserts (zz-test/narrowing-pins-the-whole-file). This spec reads them as text, so `--affected`
-- never selects it (only `--full` runs it): any later change to one of them must update its digest here (`exact` the
-- file's text, then `serde.hash("sha256", …)`).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- Each pin names its spec by its full path, and the item folder's id comes from that path: a compaction renames the
-- item and its tests/acceptance folder and rewrites `tests/acceptance/<id>` paths in this file, but not a bare id.
-- renamed.id would be wrong here: the map's f0100 is an id from before a compaction, not today's f0100, so it would
-- send this f0100 to f0011.
local PINS: { { path: string, sha: string } } = {
	{
		path = "tests/acceptance/f0013/snapshot.spec.luau",
		sha = "7ec2325e8fe6ed4103fcb141a7de3428a77720c63fdb0cecd97a2774689fdbc9",
	},
	{
		path = "tests/acceptance/f0018/frame.spec.luau",
		sha = "17a59c7a7222fd4a96d7cf6212cc70834643c9003c67124b412e04d70d322ffa",
	},
	{
		path = "tests/acceptance/f0030/frame.spec.luau",
		sha = "95470b48f0e4f9ae4d2bbbcf0d242a4ac64d330156caa981a001061de8592d4b",
	},
	{
		path = "tests/acceptance/f0032/frame.spec.luau",
		sha = "257cded3f840c62c822e2e9198e0007adb4cee64afbc223cb2db4fb1c1c88b04",
	},
	{
		path = "tests/acceptance/f0100/drops.spec.luau",
		sha = "c57510229cbd36e94ddf728d9cfa67edf09f356c8eedddc70c69fe5c391c45f2",
	},
}

local function file(pin: { path: string }): string
	return string.match(pin.path, "[^/]+$") :: string
end

local function item(pin: { path: string }): string
	return string.match(pin.path, "^tests/acceptance/([^/]+)/") :: string
end

-- the text with item ids masked and CRLF made LF; nothing else changes
local function exact(text: string): string
	text = string.gsub(text, "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

return t.spec("c0153 the five JSON round trips, narrowed and pinned whole", function(it)
	it("the five specs are still there, and their items' check.sh files still run them", function()
		for _, pin in PINS do
			t.expect(fs.isFile(pin.path)).toBe(true)
			local check = fs.readFile(".tracker/issues/done/" .. item(pin) .. "/check.sh")
			t.expect(string.find(check, `"$A/{file(pin)}"`, 1, true) ~= nil).toBe(true)
		end
	end)

	for _, pin in PINS do
		it(`{pin.path} is exactly the narrowed file`, function()
			t.expect(serde.hash("sha256", exact(fs.readFile(pin.path)))).toBe(pin.sha)
		end)
	end

	it("a check joined onto the comment line above it changes the pinned text", function()
		local src = exact(fs.readFile(PINS[1].path))
		local comment = exact(
			"-- c0153: plain data, and a JSON round trip within 1e-9 (the encoder keeps about 16 significant digits)"
		)
		local at = string.find(src, comment .. "\n", 1, true)
		t.expect(at ~= nil).toBe(true)
		local cut = (at :: number) + #comment
		local joined = string.sub(src, 1, cut - 1)
			.. " "
			.. string.gsub(string.sub(src, cut + 1), "^[ \t]+", "", 1)
		t.expect(serde.hash("sha256", joined) == PINS[1].sha).toBe(false)
		t.expect(exact("a\r\nb") == exact("a\nb")).toBe(true)
		t.expect(exact("-- x\nassert()") == exact("-- x assert()")).toBe(false)
	end)
end)
