--!strict
-- c0193 AC5: loops.problems judges one file's loops against its entries of the reviewed list: every loop that does not
-- provably advance must be the next entry, in file order, with a reason, and a loop that reads text names the scanners
-- case that sweeps it (or false). A stale or out-of-order entry is a problem too, and each problem names the file, the
-- line, the lesson and the fix.
local loops = require("@tests/lib/loops")
local t = require("@tests/lib/t")

local function src(...: string): string
	return table.concat({ ... }, "\n") .. "\n"
end

-- the scanners cases by name, each with the file of its module
local SWEEPS: { [string]: string } = { ["graph.stripComments"] = "a.luau", ["elsewhere"] = "b.luau" }

local ADVANCES = src("while i <= n do", "\ti += 1", "end")
local FOREVER = src("while true do", "\tbreak", "end")
local TWO_FOREVER = src("while true do", "\tbreak", "end", "while true do", "\tbreak", "end")
local READS = src("while true do", "\tlocal a = string.find(s, 'x', p, true)", "\tbreak", "end")

local function entry(loop: string, why: string, sweep: (string | boolean)?): loops.Allowed
	return { loop = loop, why = why, sweep = sweep }
end

local function joined(list: { string }): string
	return table.concat(list, "\n")
end

return t.spec("c0193 loops.problems", function(it)
	it("has nothing to say about a file whose loops all provably advance, with or without a list", function()
		t.expect(loops.problems("a.luau", ADVANCES, nil, SWEEPS)).toEqual({})
		t.expect(loops.problems("a.luau", "local x = 1\n", nil, SWEEPS)).toEqual({})
		t.expect(loops.problems("a.luau", ADVANCES, {}, SWEEPS)).toEqual({})
	end)

	it("names the file, line, loop, lesson and fix for an unlisted loop", function()
		local p = loops.problems("z-nile/engine/x.luau", src("local a = 1", FOREVER), nil, SWEEPS)
		t.expect(#p).toBe(1)
		t.expect(string.find(p[1], "z-nile/engine/x.luau:2:", 1, true) ~= nil).toBe(true)
		t.expect(string.find(p[1], 'loop "while true do"', 1, true) ~= nil).toBe(true)
		t.expect(string.find(p[1], "zz-arch/scanning-loops-advance", 1, true) ~= nil).toBe(true)
		t.expect(string.find(p[1], "scan.advance", 1, true) ~= nil).toBe(true)
		t.expect(string.find(p[1], "z-nile/tests/lib/loops.luau", 1, true) ~= nil).toBe(true)
	end)

	it("accepts a listed loop that has a reason", function()
		t.expect(
			loops.problems("a.luau", FOREVER, { entry("while true do", "breaks on the first pass") }, SWEEPS)
		)
			.toEqual({})
	end)

	it("pairs loops and entries in file order, so the same header twice needs two entries", function()
		local one = { entry("while true do", "breaks on the first pass") }
		local two = { one[1], entry("while true do", "breaks on the first pass too") }
		t.expect(#loops.problems("a.luau", TWO_FOREVER, one, SWEEPS)).toBe(1)
		t.expect(loops.problems("a.luau", TWO_FOREVER, two, SWEEPS)).toEqual({})
	end)

	it("reports an entry that is not the loop found at its place, naming both", function()
		local p = loops.problems("a.luau", FOREVER, { entry("repeat", "runs once and leaves") }, SWEEPS)
		t.expect(#p).toBe(1)
		t.expect(string.find(p[1], 'is not the listed loop "repeat"', 1, true) ~= nil).toBe(true)
	end)

	it("reports a stale entry: its loop is gone, or now provably advances", function()
		local stale = { entry("while true do", "breaks on the first pass") }
		local p = loops.problems("a.luau", "local x = 1\n", stale, SWEEPS)
		t.expect(#p).toBe(1)
		t.expect(string.find(p[1], "no longer there", 1, true) ~= nil).toBe(true)
		t.expect(#loops.problems("a.luau", ADVANCES, stale, SWEEPS)).toBe(1)
	end)

	it("reports an entry with no reason, or a reason of a few characters", function()
		t.expect(#loops.problems("a.luau", FOREVER, { entry("while true do", "") }, SWEEPS)).toBe(1)
		t.expect(#loops.problems("a.luau", FOREVER, { entry("while true do", "ok") }, SWEEPS)).toBe(1)
		local p = loops.problems("a.luau", FOREVER, { entry("while true do", "   ") }, SWEEPS)
		t.expect(string.find(joined(p), "gives no reason", 1, true) ~= nil).toBe(true)
	end)

	it("makes a loop that reads text name the case that sweeps it, or false", function()
		local why = "moves past each match of a non-empty needle"
		t.expect(#loops.problems("a.luau", READS, { entry("while true do", why) }, SWEEPS)).toBe(1)
		t.expect(
			loops.problems("a.luau", READS, { entry("while true do", why, "graph.stripComments") }, SWEEPS)
		)
			.toEqual({})
		t.expect(loops.problems("a.luau", READS, { entry("while true do", why, false) }, SWEEPS)).toEqual({})
		local p = loops.problems("a.luau", READS, { entry("while true do", why, "no.such") }, SWEEPS)
		t.expect(#p).toBe(1)
		t.expect(string.find(p[1], 'the scanners case "no.such", which does not exist', 1, true) ~= nil)
			.toBe(true)
	end)

	it("refuses a sweep that names a case whose module is another file", function()
		local why = "moves past each match of a non-empty needle"
		local p = loops.problems("a.luau", READS, { entry("while true do", why, "elsewhere") }, SWEEPS)
		t.expect(#p).toBe(1)
		t.expect(
			string.find(p[1], 'the scanners case "elsewhere", whose module is b.luau, not this file', 1, true)
				~= nil
		).toBe(true)
	end)

	it("does not ask a loop that reads no text for a sweep", function()
		t.expect(
			loops.problems("a.luau", FOREVER, { entry("while true do", "breaks on the first pass") }, SWEEPS)
		)
			.toEqual({})
	end)
end)
