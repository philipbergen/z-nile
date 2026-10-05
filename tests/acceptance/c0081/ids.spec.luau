--!strict
-- c0870: the pure id rules (scripts/tracker/ids.luau): the next-number file, allocation by one, the compaction
-- map and the single-pass reference rewrite. No I/O.
local ids = require("@scripts/tracker/ids")
local t = require("@tests/lib/t")
-- test data spells `tests/acceptance/` in two parts: the real compaction rewrites every literal path to a
-- promoted folder in the repository, these specs included, and would change their data
local TA = "tests/" .. "acceptance/"

local function keys(map: { [string]: string }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

return t.spec("c0870 ids", function(it)
	it("names the two files", function()
		t.expect(ids.FILE).toBe("tracker/next")
		t.expect(ids.MAP_FILE).toBe("tracker/compaction.txt")
	end)

	it("f, d and c share the issue space; R is the raft space; anything else has none", function()
		t.expect(ids.spaceOf("f0010")).toBe("issue")
		t.expect(ids.spaceOf("d0001")).toBe("issue")
		t.expect(ids.spaceOf("c9999")).toBe("issue")
		t.expect(ids.spaceOf("R0270")).toBe("raft")
		t.expect(ids.spaceOf("x0010")).toBe(nil)
		t.expect(ids.spaceOf("c010")).toBe(nil)
		t.expect(ids.spaceOf("c00100")).toBe(nil)
	end)

	it("parses the two counter lines", function()
		local c = ids.parse("issue 891 quiet-copper-falcon\nraft 271 quiet-copper-falcon\n")
		t.expect(c ~= nil).toBe(true)
		t.expect((c :: ids.Counters).issue).toBe(891)
		t.expect((c :: ids.Counters).raft).toBe(271)
		-- the final newline is optional
		t.expect((ids.parse("issue 1 a\nraft 1 b") :: ids.Counters).raft).toBe(1)
	end)

	it("refuses anything that is not exactly the two lines", function()
		for _, bad in
			{
				"",
				"issue 891 word\n", -- raft line missing
				"raft 2 w\nissue 3 w\n", -- order
				"issue 891\nraft 2 w\n", -- no phrase
				"issue 0891 w\nraft 2 w\n", -- leading zero
				"issue 0 w\nraft 2 w\n", -- below 1
				"issue 10001 w\nraft 2 w\n", -- beyond the four-digit space (10000 means full)
				"issue -3 w\nraft 2 w\n",
				"issue 3 Word\nraft 2 w\n", -- phrase is lowercase words joined by hyphens
				"issue 3 w\nraft 2 w\nextra 1 w\n",
				"issue 3 w\n\nraft 2 w\n",
				"issue 3 w \nraft 2 w\n",
			}
		do
			t.expect(ids.parse(bad)).toBe(nil)
		end
		t.expect(ids.parse("issue 10000 w\nraft 2 w\n") ~= nil).toBe(true)
	end)

	it("formats both lines with one phrase, and parse reads it back", function()
		local text = ids.format({ issue = 12, raft = 3 }, "jolly-silver-walrus")
		t.expect(text).toBe("issue 12 jolly-silver-walrus\nraft 3 jolly-silver-walrus\n")
		local back = ids.parse(text) :: ids.Counters
		t.expect(back.issue).toBe(12)
		t.expect(back.raft).toBe(3)
	end)

	it("highest is per space and 0 when the space is empty", function()
		local list = { "c0090", "f0105", "R0400", "d0020", "junk" }
		t.expect(ids.highest("issue", list)).toBe(105)
		t.expect(ids.highest("raft", list)).toBe(400)
		t.expect(ids.highest("raft", { "c0090" })).toBe(0)
	end)

	it("the next number is the counter, counting by one, not the next multiple of ten", function()
		t.expect(ids.nextFree("issue", { issue = 891, raft = 271 }, { "c0890", "R0270" })).toBe(891)
		t.expect(ids.nextFree("raft", { issue = 891, raft = 271 }, { "c0890", "R0270" })).toBe(271)
		t.expect(ids.nextFree("issue", { issue = 12, raft = 1 }, { "c0011" })).toBe(12)
	end)

	it("a counter behind the ids in use never hands out a used number", function()
		t.expect(ids.nextFree("issue", { issue = 5, raft = 1 }, { "f0007", "c0003" })).toBe(8)
		t.expect(ids.nextFree("raft", { issue = 5, raft = 1 }, { "R0004", "c0900" })).toBe(5)
		-- the other space's ids do not count
		t.expect(ids.nextFree("issue", { issue = 5, raft = 1 }, { "R0900" })).toBe(5)
	end)

	it("plan numbers each space from 1 in the order of the old numbers", function()
		local map = ids.plan({ "c0890", "f0100", "R0270", "c0041", "d0500", "R0010", "R0100" })
		t.expect(keys(map)).toBe(7)
		t.expect(map.c0041).toBe("c0001")
		t.expect(map.f0100).toBe("f0002")
		t.expect(map.d0500).toBe("d0003")
		t.expect(map.c0890).toBe("c0004")
		t.expect(map.R0010).toBe("R0001")
		t.expect(map.R0100).toBe("R0002")
		t.expect(map.R0270).toBe("R0003")
	end)

	it("plan breaks a shared number by prefix: c before d before f", function()
		local map = ids.plan({ "f0420", "c0420", "d0420", "c0010" })
		t.expect(map.c0010).toBe("c0001")
		t.expect(map.c0420).toBe("c0002")
		t.expect(map.d0420).toBe("d0003")
		t.expect(map.f0420).toBe("f0004")
	end)

	it("plan does not depend on the order of its input", function()
		local a = ids.plan({ "f0420", "c0420", "c0010", "R0020", "R0005" })
		local b = ids.plan({ "R0005", "c0010", "R0020", "c0420", "f0420" })
		t.expect(a).toEqual(b)
	end)

	it("rewrite maps every whole id token in one pass", function()
		-- a chain: a sequential replace would turn c0100 into c0010 and then into c0001
		local map = { c0010 = "c0001", c0100 = "c0010", R0270 = "R0003" }
		t.expect(ids.rewrite("c0100 blocks c0010 (R0270)", map)).toBe("c0010 blocks c0001 (R0003)")
	end)

	it("rewrite leaves partial tokens and unmapped ids alone", function()
		local map = { c0010 = "c0001", f0100 = "f0002" }
		t.expect(ids.rewrite("xc0010 c00100 c0010x f01000 f0100.md c0011", map))
			.toBe("xc0010 c00100 c0010x f01000 f0002.md c0011")
		t.expect(ids.rewrite("tracker/issues/c0010/c0010.md", map)).toBe("tracker/issues/c0001/c0001.md")
		t.expect(ids.rewrite("R0010-slug and [c0010, f0100]", map)).toBe("R0010-slug and [c0001, f0002]")
	end)

	it("rewritePaths maps tests/acceptance/<id> paths that start a token, in one pass", function()
		local map = { c0010 = "c0001", c0100 = "c0010" }
		t.expect(ids.rewritePaths('"' .. TA .. 'c0100/a.spec.luau"', map))
			.toBe('"' .. TA .. 'c0010/a.spec.luau"')
		t.expect(ids.rewritePaths("`" .. TA .. "c0010` and (" .. TA .. "c0100)", map))
			.toBe("`" .. TA .. "c0001` and (" .. TA .. "c0010)")
		t.expect(ids.rewritePaths(TA .. "c0010/x\n  " .. TA .. "c0100/y", map))
			.toBe(TA .. "c0001/x\n  " .. TA .. "c0010/y")
		t.expect(ids.rewritePaths("A=" .. TA .. "c0010", map)).toBe("A=" .. TA .. "c0001")
	end)

	it("rewritePaths leaves fixture paths and bare ids alone", function()
		local map = { c0010 = "c0001" }
		for _, keep in
			{
				"`{dir}/tests/acceptance/c0010/alpha.spec.luau`", -- a path inside a fixture
				'"$PWD/tests/acceptance/c0010"',
				"x.tests/acceptance/c0010",
				"mytests/acceptance/c0010",
				"see c0010", -- ids are rewritten by `rewrite`, not here
				"tests/acceptance/c00100",
			}
		do
			t.expect(ids.rewritePaths(keep, map)).toBe(keep)
		end
	end)

	it("the map file round-trips, sorted by old id, comments ignored", function()
		local map = { c0100 = "c0010", R0270 = "R0003", c0010 = "c0001" }
		local text = ids.formatMap(map, "tracker.sh compact, 2026-10-05, from origin/main abc123")
		t.expect(text)
			.toBe(
				"# tracker.sh compact, 2026-10-05, from origin/main abc123\nR0270 R0003\nc0010 c0001\nc0100 c0010\n"
			)
		t.expect(ids.parseMap(text)).toEqual(map)
	end)

	it("parseMap refuses a malformed line, a prefix change and a repeated old id", function()
		t.expect(ids.parseMap("c0010 c0001\nnonsense\n")).toBe(nil)
		t.expect(ids.parseMap("c0010 f0001\n")).toBe(nil)
		t.expect(ids.parseMap("c0010 c0001\nc0010 c0002\n")).toBe(nil)
		t.expect(ids.parseMap("c0010 c0001\nc0020 c0001\n")).toBe(nil)
	end)
end)
