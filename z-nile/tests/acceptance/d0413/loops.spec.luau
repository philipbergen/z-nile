--!strict
-- d0413: the two loops f0399 added are bounded `for` loops the loop scan proves end, with the results they had.
-- `guesses.parse` still ignores trailing empty lines; the raft planner keeps its dependency order (the ring fallback
-- included) and, for a list that repeats an id, returns with every entry once instead of never returning. The
-- repeated-id call runs in a bounded child (tests/lib/hostile), so a planner that hangs fails here within the limit.
local fs = require("@lune/fs")
local guesses = require("@znile/engine/guesses")
local hostile = require("@tests/lib/hostile")
local loops = require("@tests/lib/loops")
local raftplan = require("@znile/engine/raftplan")
local scanners = require("@tests/lib/scanners")
local t = require("@tests/lib/t")

local ROOT = "z-nile/.tracker"

local function cand(id: string, deps: { string }?): raftplan.Issue
	return {
		id = id,
		type = "feature",
		root = ROOT,
		state = "backlog",
		status = "prepared",
		design = "ready",
		raft = "",
		size = 100,
		solo = false,
		touched = nil,
		deps = deps,
	}
end

-- the planned rafts' members, one raft per entry, in the plan's order
local function planned(list: { raftplan.Issue }): { string }
	local ops = raftplan.plan(list, {})
	local out: { string } = {}
	for _, op in ops do
		table.insert(out, table.concat(op.issues, ","))
	end
	return out
end

-- built in parts: the graph scanner would take literal require text in this file for a real require
local REQ = "re" .. "quire"
local DRIVER = `local raftplan = {REQ}("@znile/engine/raftplan")\n`
	.. [==[
local function cand(id, deps)
	return { id = id, type = "feature", root = "z-nile/.tracker", state = "backlog", status = "prepared",
		design = "ready", raft = "", size = 100, solo = false, touched = nil, deps = deps }
end
local ops = raftplan.plan({ cand("f0010"), cand("f0010"), cand("f0011", { "f0010" }) }, {})
local parts = {}
for _, op in ops do
	table.insert(parts, table.concat(op.issues, ","))
end
print("planned " .. table.concat(parts, " | "))
]==]

return t.spec("d0413 loops the scan proves end", function(it)
	it("the loop scan finds no problem in guesses.luau or raftplan.luau", function()
		local files = loops.files()
		for _, path in { "z-nile/engine/guesses.luau", "z-nile/engine/raftplan.luau" } do
			t.expect(files[path] ~= nil).toBe(true)
			t.expect(loops.problems(path, files[path], loops.ALLOWED[path], scanners.files())).toEqual({})
		end
	end)

	it("guesses.parse ignores trailing empty lines, however many and however they end", function()
		local base =
			guesses.append(nil, "design", "2026-11-16", "Which file holds it.", "guesses.md.", "One list.")
		local want = guesses.parse(base :: string)
		t.expect(want ~= nil).toBe(true)
		t.expect(#(want :: { guesses.Guess })).toBe(1)
		for _, tail in { "\n", "\n\n\n", "\r\n\r\n", "\n\r\n\n" } do
			local got, err = guesses.parse((base :: string) .. tail)
			t.expect(err).toBe(nil)
			t.expect(got).toEqual(want)
		end
		-- the text with no final line end at all
		local bare = string.sub(base :: string, 1, -2)
		t.expect((guesses.parse(bare))).toEqual(want)
		-- only the header, and the header with empty lines after it
		t.expect((guesses.parse("# guesses\n"))).toEqual({})
		t.expect((guesses.parse("# guesses\n\n\n"))).toEqual({})
		-- an empty line that is not trailing is still a line, and is refused as before
		local mid, why = guesses.parse("# guesses\n\n" .. string.sub(base :: string, 11))
		t.expect(mid).toBe(nil)
		t.expect(why ~= nil).toBe(true)
	end)

	it("the planner keeps its dependency order, lowest id first among the free", function()
		t.expect(planned({ cand("f0013", { "f0011" }), cand("f0011", { "f0010" }), cand("f0010") }))
			.toEqual({ "f0010,f0011,f0013" })
		-- a dependency on an issue outside the list, and on itself, holds nothing back
		t.expect(planned({ cand("f0011", { "f0099", "f0011" }), cand("f0010", { "f0011" }) }))
			.toEqual({ "f0011,f0010" })
		-- an issue that names only itself is free at once, before the issue listed after it
		t.expect(planned({ cand("f0010", { "f0012" }), cand("f0011", { "f0011" }), cand("f0012") }))
			.toEqual({ "f0011", "f0012,f0010" })
	end)

	it("a ring takes the lowest id left, then goes on in dependency order", function()
		t.expect(
			planned({ cand("f0010", { "f0011" }), cand("f0011", { "f0010" }), cand("f0012", { "f0010" }) })
		)
			.toEqual({ "f0010,f0011,f0012" })
		t.expect(planned({
			cand("f0012", { "f0010" }),
			cand("f0011", { "f0012" }),
			cand("f0010", { "f0011" }),
			cand("f0009"),
		})).toEqual({ "f0009", "f0010,f0012,f0011" })
	end)

	it("a list that repeats an id is planned, every entry once, instead of never returning", function()
		local dir = ".cache/d0413-dup"
		if fs.isDir(dir) then
			fs.removeDir(dir)
		end
		fs.writeDir(dir)
		fs.writeFile(`{dir}/driver.luau`, DRIVER)
		local r = hostile.bounded(10, { "lune", "run", `{dir}/driver.luau` })
		fs.removeDir(dir)
		t.expect(r.code).toBe(0)
		-- the whole output: one raft holding the two entries of f0010 and f0011, and nothing more
		t.expect((string.gsub(r.stdout, "%s+$", ""))).toBe("planned f0010,f0010,f0011")
	end)
end)
