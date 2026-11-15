--!strict
-- c0177 AC1: f0125's promoted speeds.spec measures f0125's 10% against the same config untuned (f0147's ramp kept)
-- instead of the classic tables, passes the ghosts' ramp, takes a ramp's fractional rates, and tests the too-fast
-- bound on clones without a ramp and, when the shipped config has one, up to the ramp's top, so it holds before f0147 (no ramp, no Levels.ghostRate) and after it. Nothing
-- else in it changes. The file is pinned whole, by the SHA-256 of its exact text with only item ids masked (so a
-- compaction cannot break it) and line endings made LF: no whitespace is tolerated, because a newline ends a line
-- comment (zz-test/narrowing-pins-the-whole-file; c0153's model). This spec reads the file as text: any later change
-- to it must update the digest here (`exact` the file's text, then `serde.hash("sha256", …)`). That the file
-- passes, today and on f0147's ramp, is its own run (AC2; E2).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- The pin names its spec by its full path, and the item folder's id comes from that path: a compaction renames the
-- item and its tests/acceptance folder and rewrites `tests/acceptance/<id>` paths in this file, but not a bare id.
local PIN = {
	path = "tests/acceptance/f0125/speeds.spec.luau",
	sha = "7e0838d0f32ddb2bcc64f72736dd37e97d858610d2e6c0a7e699794ca5dafc8d",
}
local FILE = string.match(PIN.path, "[^/]+$") :: string
local ITEM = string.match(PIN.path, "^tests/acceptance/([^/]+)/") :: string

-- the text with item ids masked and CRLF made LF; nothing else changes. Every read of the pinned file goes through it.
local function exact(text: string): string
	text = string.gsub(text, "\r\n", "\n")
	text = string.gsub(text, "%f[%w_][fdcR]%d+%f[^%w_]", "ID")
	return text
end

local function count(text: string, needle: string): number
	local n, at = 0, 1
	while true do
		local from, to = string.find(text, needle, at, true)
		if not from then
			return n
		end
		n += 1
		at = (to :: number) + 1
	end
end

return t.spec("c0177 f0125's speed pins, narrowed for the ramp and pinned whole", function(it)
	it("the spec is still there, and f0125's check.sh still runs it for its five criteria", function()
		t.expect(fs.isFile(PIN.path)).toBe(true)
		local ran = 0
		local check = exact(fs.readFile(".tracker/issues/done/" .. ITEM .. "/check.sh"))
		for line in string.gmatch(check, "[^\n]+") do
			if
				string.sub(line, 1, 7) == 'check "'
				and string.find(line, `lune run tests/run -- "$A/{FILE}"`, 1, true)
			then
				ran += 1
			end
		end
		t.expect(ran).toBe(5)
	end)

	it(`{PIN.path} is exactly the narrowed file`, function()
		t.expect(serde.hash("sha256", exact(fs.readFile(PIN.path)))).toBe(PIN.sha)
	end)

	-- the searches the narrowing came from (`grep -c` over the base file): both edge compares, the three ghost-speed
	-- compares and both bound clones changed, and no old spelling is left
	it(
		"no compare of the shipped config against the classic tables, and no ghost speed without the ramp, is left",
		function()
			local src = exact(fs.readFile(PIN.path))
			t.expect(count(src, "edge(Session.DEFAULT_CONFIG")).toBe(0)
			t.expect(count(src, "edge(untunedOf(Session.GAME_CONFIG), level)")).toBe(2)
			t.expect(count(src, "set.tuning)")).toBe(0)
			t.expect(count(src, "set.tuning, ramp)")).toBe(3)
			t.expect(count(src, ".ramp = nil -- ID: the bound on the classic tables")).toBe(2)
			t.expect(count(src, "if d ~= want then")).toBe(0)
			t.expect(count(src, "keep twice level 1's player speed")).toBe(0)
			t.expect(count(src, "the classic edge")).toBe(0)
			t.expect(count(src, "if (Session.GAME_CONFIG :: any).ramp then")).toBe(1) -- the bound up to the ramp's top
		end
	)

	it("a line joined onto the comment above it changes the pinned text", function()
		local src = exact(fs.readFile(PIN.path))
		local comment = exact("\t-- tenth of a unit on average")
		local at = string.find(src, comment .. "\n", 1, true)
		t.expect(at ~= nil).toBe(true)
		local cut = (at :: number) + #comment
		local joined = string.sub(src, 1, cut - 1) .. " " .. string.sub(src, cut + 1)
		t.expect(serde.hash("sha256", joined) == PIN.sha).toBe(false)
		t.expect(exact("a\r\nb") == exact("a\nb")).toBe(true)
		t.expect(exact("-- x\nassert()") == exact("-- x assert()")).toBe(false)
	end)
end)
