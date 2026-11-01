--!strict
-- c0180: the spec-commands record (`<home>/.cache/spec-commands.tsv`) and its closure key, through their one reader,
-- z-nile/lib/commandrecord.luau. Pure: no files, no processes.
local cr = require("@znile/lib/commandrecord")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

local KEY_A = string.rep("a", 64)
local KEY_B = string.rep("0123456789abcdef", 4)

local function sha(text: string): string
	return serde.hash("sha256", text)
end

local FILES: { [string]: string } = {
	["tests/a.spec.luau"] = "return 1\n",
	["tests/lib/t.luau"] = "return {}\n",
	["tests/lib/u.luau"] = "return 2\n",
}
local function bytes(path: string): string
	local text = FILES[path]
	assert(text, `unexpected read of {path}`)
	return text
end

local function refused(text: string, why: string)
	local records, problem = cr.parse(text)
	t.expect(records).toBe(nil)
	t.expect(type(problem)).toBe("string")
	t.expect((string.find(problem :: string, why, 1, true)) ~= nil).toBe(true)
end

return t.spec("c0180 command record", function(it)
	it("the key is the sha256 of the versioned text of sorted paths and their content hashes", function()
		local expected = sha(
			"spec commands key v1\n"
				.. `tests/a.spec.luau\t{sha(FILES["tests/a.spec.luau"])}\n`
				.. `tests/lib/t.luau\t{sha(FILES["tests/lib/t.luau"])}\n`
		)
		t.expect(cr.key({ "tests/lib/t.luau", "tests/a.spec.luau" }, bytes)).toBe(expected)
	end)

	it("the key ignores the order and repeats of the paths it is given", function()
		local one = cr.key({ "tests/a.spec.luau", "tests/lib/t.luau" }, bytes)
		t.expect(cr.key({ "tests/lib/t.luau", "tests/a.spec.luau", "tests/lib/t.luau" }, bytes)).toBe(one)
	end)

	it("the key changes with one byte of a closure file and with an added file", function()
		local one = cr.key({ "tests/a.spec.luau", "tests/lib/t.luau" }, bytes)
		t.expect(cr.key({ "tests/a.spec.luau", "tests/lib/t.luau", "tests/lib/u.luau" }, bytes) ~= one)
			.toBe(true)
		FILES["tests/lib/t.luau"] = "return {} \n"
		t.expect(cr.key({ "tests/a.spec.luau", "tests/lib/t.luau" }, bytes) ~= one).toBe(true)
		FILES["tests/lib/t.luau"] = "return {}\n"
		t.expect(cr.key({ "tests/a.spec.luau", "tests/lib/t.luau" }, bytes)).toBe(one)
	end)

	it("parse and render round-trip, sorted by spec, with - for a spec that ran no command", function()
		local text = "# spec commands v1\n"
			.. `tests/a.spec.luau\t{KEY_A}\tlist,new,raft-plan,worktree-prune\n`
			.. `tests/tooling/b.spec.luau\t{KEY_B}\t-\n`
		local records = cr.parse(text) :: cr.Records
		t.expect(records["tests/a.spec.luau"]).toEqual({
			key = KEY_A,
			commands = { "list", "new", "raft-plan", "worktree-prune" },
		})
		t.expect(records["tests/tooling/b.spec.luau"]).toEqual({ key = KEY_B, commands = {} })
		t.expect(cr.render(records)).toBe(text)
		-- render sorts by spec path whatever order the table was built in
		local built: cr.Records = {}
		built["tests/tooling/b.spec.luau"] = { key = KEY_B, commands = {} }
		built["tests/a.spec.luau"] =
			{ key = KEY_A, commands = { "list", "new", "raft-plan", "worktree-prune" } }
		t.expect(cr.render(built)).toBe(text)
		t.expect(cr.render({})).toBe("# spec commands v1\n")
	end)

	it("parse refuses every malformed record, naming the line", function()
		local H = "# spec commands v1\n"
		refused("", "line 1")
		refused(`tests/a.spec.luau\t{KEY_A}\tnew\n`, "line 1")
		refused(`# spec commands v2\ntests/a.spec.luau\t{KEY_A}\tnew\n`, "line 1")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tnew\textra\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{string.rep("a", 63)}\tnew\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{string.rep("A", 64)}\tnew\n`, "line 2")
		refused(H .. `src/a.spec.luau\t{KEY_A}\tnew\n`, "line 2")
		refused(H .. `tests/a.luau\t{KEY_A}\tnew\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tNew\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\traft_plan\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\t1new\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tnew,list\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tlist,list\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\t\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tlist,\n`, "line 2")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tnew\ntests/a.spec.luau\t{KEY_B}\tlist\n`, "line 3")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tnew\n\ntests/b.spec.luau\t{KEY_B}\tlist\n`, "line 3")
		refused(H .. `tests/a.spec.luau\t{KEY_A}\tnew`, "line 2")
	end)

	it("merge puts every new entry over the old, keeps the rest, and drops what keep lacks", function()
		local old: cr.Records = {
			["tests/a.spec.luau"] = { key = KEY_A, commands = { "new" } },
			["tests/b.spec.luau"] = { key = KEY_A, commands = { "list" } },
			["tests/gone.spec.luau"] = { key = KEY_A, commands = { "find" } },
		}
		local new: cr.Records = {
			["tests/a.spec.luau"] = { key = KEY_B, commands = { "status" } },
			["tests/c.spec.luau"] = { key = KEY_B, commands = {} },
		}
		t.expect(cr.merge(old, new, nil)).toEqual({
			["tests/a.spec.luau"] = { key = KEY_B, commands = { "status" } },
			["tests/b.spec.luau"] = { key = KEY_A, commands = { "list" } },
			["tests/c.spec.luau"] = { key = KEY_B, commands = {} },
			["tests/gone.spec.luau"] = { key = KEY_A, commands = { "find" } },
		})
		local keep =
			{ ["tests/a.spec.luau"] = true, ["tests/b.spec.luau"] = true, ["tests/c.spec.luau"] = true }
		t.expect(cr.merge(old, new, keep)).toEqual({
			["tests/a.spec.luau"] = { key = KEY_B, commands = { "status" } },
			["tests/b.spec.luau"] = { key = KEY_A, commands = { "list" } },
			["tests/c.spec.luau"] = { key = KEY_B, commands = {} },
		})
		-- the inputs are not changed
		t.expect(old["tests/a.spec.luau"].key).toBe(KEY_A)
	end)
end)
