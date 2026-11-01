--!strict
-- c0180: selection by command, on a hand-built select.Context (c0165's types plus `commands`): an engine Luau file is an
-- input of a tooling spec through its requires, a declaration, `*`, a missing record, or a recorded command whose
-- module closure (plus the dispatch core) reaches it; engine files force z-nile only when no records were loaded.
local fingerprint = require("@znile/lib/fingerprint")
local select = require("@znile/lib/select")
local t = require("@tests/lib/t")

local E = "z-nile/engine/"
local SH = "z-nile/lib/sh.luau"
local T = "z-nile/tests/lib/t.luau"
local X = "z-nile/tests/acceptance/x/"
local LISTS, UNKNOWN, VANISHED, NONE =
	X .. "lists.spec.luau", X .. "unknown.spec.luau", X .. "vanished.spec.luau", X .. "none.spec.luau"
local REQUIRER, DECLARED, STAR = X .. "requirer.spec.luau", X .. "declared.spec.luau", X .. "star.spec.luau"
local PICK = "pickman/tests/unit/p.spec.luau"

local deps: { [string]: { string } } = {
	[E .. "main.luau"] = {
		E .. "cli.luau",
		SH,
		E .. "cmd/list.luau",
		E .. "cmd/new.luau",
		E .. "cmd/find.luau",
	},
	[E .. "cli.luau"] = { SH },
	[SH] = {},
	[E .. "cmd/list.luau"] = { E .. "cli.luau", E .. "store.luau" },
	[E .. "cmd/new.luau"] = { E .. "cli.luau", E .. "front.luau" },
	[E .. "cmd/find.luau"] = { E .. "cli.luau" },
	[E .. "store.luau"] = {},
	[E .. "front.luau"] = { E .. "store.luau" },
	[T] = {},
	[LISTS] = { T },
	[UNKNOWN] = { T },
	[VANISHED] = { T },
	[NONE] = { T },
	[REQUIRER] = { T, E .. "front.luau" },
	[DECLARED] = { T },
	[STAR] = { T },
	[PICK] = {},
}
local files: { string } = {}
for file in deps do
	table.insert(files, file)
end
table.sort(files)

local rules: select.Rules = {
	homes = { { name = "pickman", prefix = "pickman/" }, { name = "z-nile", prefix = "z-nile/" } },
	roots = { "pickman/.tracker", "z-nile/.tracker" },
}
local ctx: select.Context = {
	rules = rules,
	graph = { files = files, deps = deps, unresolved = {}, dynamic = {} } :: any,
	inputs = { [DECLARED] = { E }, [STAR] = { "*" } },
	commands = {
		[LISTS] = { "list" },
		[VANISHED] = { "gone" },
		[NONE] = {},
		[REQUIRER] = {},
		[DECLARED] = {},
		[STAR] = {},
	},
}

local function keys(set: { [string]: boolean }?): { string }?
	if set == nil then
		return nil
	end
	local out = {}
	for k in set :: { [string]: boolean } do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end
local function sorted(list: { string } | string): { string } | string
	if type(list) == "string" then
		return list
	end
	local out = table.clone(list :: { string })
	table.sort(out)
	return out
end

return t.spec("c0180 selection by command", function(it)
	it("engine Luau files force z-nile only when no records were loaded", function()
		t.expect(select.forces(rules, E .. "cmd/list.luau", {})).toBe(nil)
		t.expect(select.forces(rules, E .. "sub/deep.luau", {})).toBe(nil)
		t.expect(select.forces(rules, E .. "main.luau", {})).toBe(nil)
		t.expect(select.forces(rules, E .. "cmd/list.luau", nil)).toBe("z-nile")
		t.expect(select.forces(rules, E .. "board.html", {})).toBe("z-nile")
		t.expect(select.forces(rules, "z-nile/templates/issue.md", {})).toBe("z-nile")
		t.expect(select.forces(rules, "z-nile/check.sh", {})).toBe("z-nile")
		t.expect(select.forces(rules, SH, {})).toBe("all")
	end)

	it("a command uses its module's closure and the core, which does not follow the cmd/ edges", function()
		t.expect(keys(select.engineUses(ctx, "list"))).toEqual({
			E .. "cli.luau",
			E .. "cmd/list.luau",
			E .. "main.luau",
			E .. "store.luau",
			SH,
		})
		t.expect(keys(select.engineUses(ctx, "new"))).toEqual({
			E .. "cli.luau",
			E .. "cmd/new.luau",
			E .. "front.luau",
			E .. "main.luau",
			E .. "store.luau",
			SH,
		})
		t.expect(keys(select.engineUses(ctx, "gone"))).toBe(nil)
	end)

	it("a recorded command makes exactly the files it uses inputs", function()
		t.expect(select.isInput(ctx, LISTS, E .. "cmd/list.luau")).toBe(true)
		t.expect(select.isInput(ctx, LISTS, E .. "store.luau")).toBe(true)
		t.expect(select.isInput(ctx, LISTS, E .. "main.luau")).toBe(true)
		t.expect(select.isInput(ctx, LISTS, E .. "cli.luau")).toBe(true)
		t.expect(select.isInput(ctx, LISTS, E .. "cmd/new.luau")).toBe(false)
		t.expect(select.isInput(ctx, LISTS, E .. "front.luau")).toBe(false)
		t.expect(select.isInput(ctx, LISTS, E .. "cmd/find.luau")).toBe(false)
	end)

	it(
		"a spec with no record, or with a command that has no module, has every engine file as input",
		function()
			for _, file in { "cmd/new.luau", "front.luau", "cmd/find.luau", "sub/deep.luau" } do
				t.expect(select.isInput(ctx, UNKNOWN, E .. file)).toBe(true)
				t.expect(select.isInput(ctx, VANISHED, E .. file)).toBe(true)
			end
		end
	)

	it(
		"a spec that ran no command takes engine files only through its requires, declarations or *",
		function()
			t.expect(select.isInput(ctx, NONE, E .. "main.luau")).toBe(false)
			t.expect(select.isInput(ctx, NONE, E .. "store.luau")).toBe(false)
			t.expect(select.isInput(ctx, REQUIRER, E .. "front.luau")).toBe(true)
			t.expect(select.isInput(ctx, REQUIRER, E .. "store.luau")).toBe(true)
			t.expect(select.isInput(ctx, REQUIRER, E .. "cmd/new.luau")).toBe(false)
			t.expect(select.isInput(ctx, DECLARED, E .. "cmd/find.luau")).toBe(true)
			t.expect(select.isInput(ctx, STAR, E .. "cmd/find.luau")).toBe(true)
		end
	)

	it("the command rule is the tooling home's only: a pickman spec takes no engine file", function()
		t.expect(select.isInput(ctx, PICK, E .. "cmd/list.luau")).toBe(false)
		t.expect(select.isInput(ctx, PICK, E .. "main.luau")).toBe(false)
	end)

	it("affected selects by command, and still forces for other tooling files", function()
		t.expect(sorted(select.affected(ctx, { E .. "cmd/list.luau" }, nil))).toEqual({
			DECLARED,
			LISTS,
			STAR,
			UNKNOWN,
			VANISHED,
		})
		t.expect(sorted(select.affected(ctx, { E .. "front.luau" }, nil))).toEqual({
			DECLARED,
			REQUIRER,
			STAR,
			UNKNOWN,
			VANISHED,
		})
		t.expect(sorted(select.affected(ctx, { E .. "main.luau" }, nil))).toEqual({
			DECLARED,
			LISTS,
			STAR,
			UNKNOWN,
			VANISHED,
		})
		t.expect(select.affected(ctx, { E .. "board.html" }, nil)).toBe("ALL")
		t.expect(select.affected(ctx, { E .. "cmd/list.luau", "z-nile/templates/issue.md" }, nil)).toBe("ALL")
		t.expect(sorted(select.affected(ctx, { E .. "cmd/list.luau" }, "pickman"))).toEqual({})
		local noRecords: select.Context = table.clone(ctx)
		noRecords.commands = nil
		t.expect(select.affected(noRecords, { E .. "cmd/list.luau" }, nil)).toBe("ALL")
	end)

	it("a spec's fingerprint inputs hold exactly the engine files isInput holds", function()
		local blobs: { [string]: string } = {}
		for _, file in files do
			blobs[file] = "100644 " .. string.rep("1", 40)
		end
		blobs[E .. "sub/deep.luau"] = "100644 " .. string.rep("2", 40)
		local engineInputs = {}
		for _, path in fingerprint.inputs(ctx, LISTS, blobs) do
			if string.sub(path, 1, #E) == E then
				table.insert(engineInputs, path)
			end
		end
		table.sort(engineInputs)
		t.expect(engineInputs)
			.toEqual({ E .. "cli.luau", E .. "cmd/list.luau", E .. "main.luau", E .. "store.luau" })
	end)
end)
