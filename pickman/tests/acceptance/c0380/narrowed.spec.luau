--!strict
-- c0380 AC1: the board pins f0186 (Boards show revives) changes are narrowed, and pinned whole. f0186 adds a run's
-- revives after the level on every board line and the best line, drops f0145's lives figure from the boards, shows the
-- price of a game on sale and drops "lives spent" from game-design.md. So nine cases of d0124's and f0026's specs pin
-- each board line up to the level (a local `upToLevel`: the line, then nothing or a space and anything), and five of
-- f0145's keep everything but its lives display, its buy line's words and the phrase. f0026's adapters.spec is pinned by
-- digest in c0128's golden.spec, so that one value moves with the narrowing. Each of the ten changed files is pinned
-- whole, by the SHA-256 of its exact text with only item ids masked (so a compaction cannot break it) and line endings
-- made LF: no whitespace is tolerated, because a newline ends a line comment (zz-test/narrowing-pins-the-whole-file;
-- c0176's model). This spec reads the files as text: any later change to one of them must update its digest here
-- (`exact` the file's text, then `serde.hash("sha256", …)`). That the files pass, before and after f0186, is their own
-- runs (AC2; E2 and E3 on the prototypes).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

-- Each pin names its spec by its full path, and the item folder's id comes from that path: a compaction renames the
-- item and its tests/acceptance folder and rewrites `tests/acceptance/<id>` paths in this file, but not a bare id.
-- `cuts` is how many board texts the file passes through `upToLevel` (its definition not counted).
local PINS: { { path: string, sha: string, cuts: number } } = {
	{
		path = "tests/acceptance/d0124/lobby.spec.luau",
		sha = "9c9edcda2bc0a636240582eff8267dc75e04250b66df3d79bbebe691fb49ecfc",
		cuts = 4,
	},
	{
		path = "tests/acceptance/d0124/adapters.spec.luau",
		sha = "c8deae007a520d56020936e98f769cb124e9823fedc81209b13f4825721c46c4",
		cuts = 2,
	},
	{
		path = "tests/acceptance/f0026/adapters.spec.luau",
		sha = "34555206b46322c51223d3ecf8f7e22193b1eb1975c018fb08fa7ca11e516f1a",
		cuts = 3,
	},
	{
		path = "tests/acceptance/f0026/endtoend.spec.luau",
		sha = "8a93fc25d3db10e7caae1133e9a2e10371aaa33e9f1d4a67060b95b61515e980",
		cuts = 1,
	},
	{
		path = "tests/acceptance/f0026/lobby.spec.luau",
		sha = "1a565dfca38e0d3125b1904a2a4ce5bd8183bac33f2249ca64689fdf47a5d3f8",
		cuts = 1,
	},
	{
		path = "tests/acceptance/f0145/lives.spec.luau",
		sha = "a163257672bd45b858fc8cffb9c71ad4a5a8e76d3d3b0d0c51b296acfd4b39eb",
		cuts = 1,
	},
	{
		path = "tests/acceptance/f0145/top.spec.luau",
		sha = "4de3afeb25d91c72640f0eda428b37a42611b6962b9a9b6ee99a4f6836bbdf8d",
		cuts = 1,
	},
	{
		path = "tests/acceptance/f0145/views.spec.luau",
		sha = "c3dd409a1f2e42b3e235287ede1559ad652c9aff7059bc3da679ee5e0bda1a37",
		cuts = 0,
	},
	{
		path = "tests/acceptance/f0145/place.spec.luau",
		sha = "f66efcf08fb129b3c2a5cff0ffde724909f5994bc336c2943276dc6b70955ff9",
		cuts = 0,
	},
	-- c0128's whole-file pin of f0026's adapters.spec, whose digest moved with the narrowing
	{
		path = "tests/acceptance/c0128/golden.spec.luau",
		sha = "9ba74b18c59a619bf956f3bae5e5ac5a9fc4679df6f6c1b5f245eb153f57d178",
		cuts = 0,
	},
}

-- c0128's digest of f0026's adapters.spec before the narrowing, and after it (c0128's own normalisation)
local OLD_D26 = "744eeb0f1d525ee47f52c01dd8cab3c4bcd511fd2edf28919f894712f64cbfc6"
local NEW_D26 = "edfd74c3cd76d3eccd827af745ee6e671262c6f607232fef5a02713b4ef63074"

-- the one cut every narrowed file defines, word for word
local HELPER = [[
local function upToLevel(text: any, want: string): any
	if type(text) ~= "string" then
		return text
	end
	local got, keep = string.split(text, "\n"), string.split(want, "\n")
	for i, line in got do
		local w = keep[i]
		if w ~= nil and (line == w or string.sub(line, 1, #w + 1) == w .. " ") then
			got[i] = w
		end
	end
	return table.concat(got, "\n")
end
]]

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

return t.spec("c0380 the board pins f0186 changes, narrowed and pinned whole", function(it)
	it("the ten specs are still there, and their items' check.sh files still run them", function()
		for _, pin in PINS do
			t.expect(fs.isFile(pin.path)).toBe(true)
			local ran = false
			local check = exact(fs.readFile(".tracker/issues/done/" .. item(pin) .. "/check.sh"))
			for line in string.gmatch(check, "[^\n]+") do
				if string.sub(line, 1, 7) == 'check "' and string.find(line, `/{file(pin)}"`, 1, true) then
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

	-- the searches the narrowing came from: every board text these files compared exactly is cut at the level now, and
	-- no pin of f0145's lives display, of its buy line's words or of the phrase "lives spent" is left
	it("every board text is compared up to the level, and nothing f0186 removes is pinned", function()
		for _, pin in PINS do
			local src = exact(fs.readFile(pin.path))
			if pin.cuts > 0 then
				t.expect(count(src, exact(HELPER))).toBe(1)
				t.expect(count(src, "upToLevel(")).toBe(pin.cuts + 1)
			else
				t.expect(count(src, "upToLevel(")).toBe(0)
			end
			t.expect(count(src, "livesText")).toBe(0)
			t.expect(count(src, "LIVES_MARK")).toBe(0)
			t.expect(count(src, "1 ROBUX A GAME")).toBe(0)
			t.expect(count(src, '"lives spent"')).toBe(0)
		end
		local golden = exact(fs.readFile(PINS[10].path))
		t.expect(count(golden, OLD_D26)).toBe(0)
		t.expect(count(golden, NEW_D26)).toBe(1)
	end)

	it("a line joined onto the comment above it changes the pinned text", function()
		local src = exact(fs.readFile(PINS[1].path))
		local comment = exact(
			"-- the best line ends as the row of the same score and level ends (nothing, or f0186's revives)"
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
