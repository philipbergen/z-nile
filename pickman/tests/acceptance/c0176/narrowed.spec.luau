--!strict
-- c0176 AC1: four promoted specs build their sessions with the shipped rules less f0147's ramp (a local clone of
-- Session.GAME_CONFIG with `ramp = nil`), so they keep pinning the classic level 1 and the last pellet's clear once
-- f0147 puts a ramp in GAME_CONFIG; every assertion in them is as it was. `git grep -n 'Session.GAME_CONFIG)'` over
-- the four files found the eight calls changed: f0023 session-ghosts (2), f0100 drops (1) and shots (2), f0101
-- airborne (3). c0153's golden.spec pins f0100's drops.spec by digest, so that one value moves with the narrowing
-- (c0176 overrides it too). Each of the five changed files is pinned whole, by the SHA-256 of its exact text with
-- only item ids masked (so a compaction cannot break it) and line endings made LF: no whitespace is tolerated,
-- because a newline ends a line comment (zz-test/narrowing-pins-the-whole-file; c0153's model). This spec reads the
-- files as text: any later change to one of them must update its digest here (`exact` the file's text, then
-- `serde.hash("sha256", …)`). That the files pass, today and on f0147's ramp, is their own runs (AC2; E2).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- Each pin names its spec by its full path, and the item folder's id comes from that path: a compaction renames the
-- item and its tests/acceptance folder and rewrites `tests/acceptance/<id>` paths in this file, but not a bare id.
local PINS: { { path: string, sha: string, calls: number } } = {
	{
		path = "tests/acceptance/f0023/session-ghosts.spec.luau",
		sha = "1d1eae2e59718244846f703115b1f811e1d75926a16b66b7e2f38d73aac74db7",
		calls = 2,
	},
	{
		path = "tests/acceptance/f0100/drops.spec.luau",
		sha = "611b2ed37535ad74fb53fc216693f6e13708e18bb9b106e2079ebbca0a89feb7",
		calls = 1,
	},
	{
		path = "tests/acceptance/f0100/shots.spec.luau",
		sha = "99610158e59a6c40739b854a702dcf20bc2ef0036bd2909a7debea97e1d665b9",
		calls = 2,
	},
	{
		path = "tests/acceptance/f0101/airborne.spec.luau",
		sha = "6e33099630acd6f869f725dcaba3dc2bb8fa2ef87e0cdd1e098ac3a51fc3b59d",
		calls = 3,
	},
	-- c0153's pin of drops.spec, whose digest moved with the narrowing; it builds no session
	{
		path = "tests/acceptance/c0153/golden.spec.luau",
		sha = "d3ce9a21db546347ad00fdb48c151b22752085e38bf996c516315e0fa34df1ec",
		calls = 0,
	},
}

local function file(pin: { path: string }): string
	return string.match(pin.path, "[^/]+$") :: string
end

local function item(pin: { path: string }): string
	return string.match(pin.path, "^tests/acceptance/([^/]+)/") :: string
end

-- the text with item ids masked and CRLF made LF; nothing else changes. Every read of a pinned file goes through it.
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

return t.spec("c0176 the shipped-config level pins, narrowed and pinned whole", function(it)
	it("the five specs are still there, and their items' check.sh files still run them", function()
		for _, pin in PINS do
			t.expect(fs.isFile(pin.path)).toBe(true)
			local ran = false
			local check = exact(fs.readFile(".tracker/issues/done/" .. item(pin) .. "/check.sh"))
			for line in string.gmatch(check, "[^\n]+") do
				if
					string.sub(line, 1, 7) == 'check "'
					and string.find(line, `lune run tests/run -- "$A/{file(pin)}"`, 1, true)
				then
					ran = true
				end
			end
			t.expect(ran).toBe(true)
		end
	end)

	for _, pin in PINS do
		it(`{pin.path} is exactly the narrowed file`, function()
			t.expect(serde.hash("sha256", exact(fs.readFile(pin.path)))).toBe(pin.sha)
		end)
	end

	-- the search the narrowing came from: no session is built with the shipped config as it is, and each file
	-- builds as many with the classic clone as it built with the shipped config before
	it("every session the four specs build takes the shipped config less its ramp", function()
		for _, pin in PINS do
			local src = exact(fs.readFile(pin.path))
			t.expect(count(src, "Session.GAME_CONFIG)")).toBe(if pin.calls > 0 then 1 else 0) -- the clone itself
			t.expect(count(src, "CLASSIC_GAME)")).toBe(pin.calls)
			if pin.calls > 0 then
				t.expect(
					count(
						src,
						"local CLASSIC_GAME = table.clone(Session.GAME_CONFIG) :: any\nCLASSIC_GAME.ramp = nil\n"
					)
				).toBe(1)
				t.expect(count(src, "CLASSIC_GAME")).toBe(pin.calls + 2)
			end
		end
	end)

	it("a line joined onto the comment above it changes the pinned text", function()
		local src = exact(fs.readFile(PINS[1].path))
		local comment = exact(
			"-- c0176: the shipped rules less f0147's ramp, so these cases keep the classic level 1 and the last pellet's clear"
		)
		local at = string.find(src, comment .. "\n", 1, true)
		t.expect(at ~= nil).toBe(true)
		local cut = (at :: number) + #comment
		local joined = string.sub(src, 1, cut - 1) .. " " .. string.sub(src, cut + 1)
		t.expect(serde.hash("sha256", joined) == PINS[1].sha).toBe(false)
		t.expect(exact("a\r\nb") == exact("a\nb")).toBe(true)
		t.expect(exact("-- x\nassert()") == exact("-- x assert()")).toBe(false)
	end)
end)
