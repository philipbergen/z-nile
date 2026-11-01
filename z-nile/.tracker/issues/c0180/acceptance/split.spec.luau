--!strict
-- c0180: the engine is split by command, on the real tree. Every command is its own module in engine/cmd/, dispatched
-- by main.luau through a literal lazy require; only main.luau and command modules (raft-plan runs fold and new) require
-- a command module, and nothing requires main.luau; the dispatch core (main.luau's closure without the cmd/ edges) is
-- main, cli and lib/sh, so a change elsewhere in the engine never selects every command by itself; there is no require
-- cycle. Runs from z-nile's home.
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local t = require("@tests/lib/t")

local MAIN = "engine/main.luau"
local CMD = "engine/cmd/"
local g = graph.build({ "engine", "lib" })

local function code(path: string): string
	return graph.stripComments(fs.readFile(path))
end
local function commandFiles(): { string }
	local out = {}
	for _, name in fs.readDir("engine/cmd") do
		if string.match(name, "%.luau$") then
			table.insert(out, (string.gsub(name, "%.luau$", "")))
		end
	end
	table.sort(out)
	return out
end
local function engineFiles(): { string }
	local out = {}
	for _, file in g.files do
		if string.sub(file, 1, 7) == "engine/" then
			table.insert(out, file)
		end
	end
	return out
end

return t.spec("c0180 the engine is split by command", function(it)
	it("every command has its module, and main.luau dispatches each by a literal require", function()
		local names = commandFiles()
		t.expect(#names >= 37).toBe(true)
		local main = code(MAIN)
		local dispatched = {}
		for name in string.gmatch(main, 'require%("%./cmd/([%w%-]+)"%)') do
			table.insert(dispatched, name)
		end
		table.sort(dispatched)
		t.expect(dispatched).toEqual(names)
		for _, name in names do
			t.expect(string.match(code(`{CMD}{name}.luau`), "\nreturn function%(") ~= nil).toBe(true)
		end
	end)

	it(
		"no engine file defines a cmd handler, only main.luau and command modules require a command module, nothing requires main.luau",
		function()
			local files = engineFiles()
			t.expect(#files > #commandFiles()).toBe(true)
			for _, file in files do
				local text = code(file)
				t.expect((string.find(text, "function cmd.", 1, true))).toBe(nil)
				t.expect((string.find(text, "cmd[", 1, true))).toBe(nil)
				for _, dep in (g.deps[file] or {}) :: { string } do
					t.expect(dep ~= MAIN).toBe(true)
					if string.sub(dep, 1, #CMD) == CMD then
						t.expect(file == MAIN or string.sub(file, 1, #CMD) == CMD).toBe(true)
					end
				end
			end
		end
	)

	it("the dispatch core is exactly main.luau, cli.luau and lib/sh.luau", function()
		local seen: { [string]: boolean } = {}
		local stack = { MAIN }
		while #stack > 0 do
			local file = table.remove(stack) :: string
			if not seen[file] then
				seen[file] = true
				for _, dep in (g.deps[file] or {}) :: { string } do
					if string.sub(dep, 1, #CMD) ~= CMD then
						table.insert(stack, dep)
					end
				end
			end
		end
		local core = {}
		for file in seen do
			table.insert(core, file)
		end
		table.sort(core)
		t.expect(core).toEqual({ "engine/cli.luau", MAIN, "lib/sh.luau" })
	end)

	it("no command module is named usage, the trace's name for the usage path", function()
		t.expect(fs.isFile(`{CMD}usage.luau`)).toBe(false)
	end)

	it("outside main.luau only raft-plan requires command modules: exactly fold and new", function()
		for _, file in engineFiles() do
			local cmds: { string } = {}
			for _, dep in (g.deps[file] or {}) :: { string } do
				if string.sub(dep, 1, #CMD) == CMD then
					table.insert(cmds, dep)
				end
			end
			table.sort(cmds)
			if file == `{CMD}raft-plan.luau` then
				t.expect(cmds).toEqual({ `{CMD}fold.luau`, `{CMD}new.luau` })
			elseif file ~= MAIN then
				t.expect(cmds).toEqual({})
			end
		end
	end)

	it(
		"the split narrows: a module every command reaches is the core or one the engine had before the split",
		function()
			local common: { [string]: boolean }? = nil
			for _, name in commandFiles() do
				local seen: { [string]: boolean } = {}
				local stack = { `{CMD}{name}.luau` }
				while #stack > 0 do
					local file = table.remove(stack) :: string
					if not seen[file] then
						seen[file] = true
						for _, dep in (g.deps[file] or {}) :: { string } do
							table.insert(stack, dep)
						end
					end
				end
				if common == nil then
					common = seen
				else
					for file in common :: { [string]: boolean } do
						if not seen[file] then
							(common :: { [string]: boolean })[file] = nil
						end
					end
				end
			end
			-- the engine's modules before the split (a fixed list): a new module every command needs would undo the split
			local before: { [string]: boolean } = { ["engine/cli.luau"] = true, ["lib/sh.luau"] = true }
			for _, m in
				{
					"audit",
					"board",
					"chart",
					"claims",
					"compact",
					"gate",
					"history",
					"ids",
					"ledger",
					"lessons",
					"paths",
					"projects",
					"publish",
					"raftplan",
					"skills",
					"spend",
					"stats",
					"status",
					"store",
					"trail",
				}
			do
				before[`engine/{m}.luau`] = true
			end
			t.expect(common ~= nil).toBe(true)
			for file in common :: { [string]: boolean } do
				t.expect(`{file}: {before[file] == true}`).toBe(`{file}: true`)
			end
		end
	)

	it("no engine file requires a computed path", function()
		for _, file in g.dynamic do
			t.expect(string.sub(file, 1, 7) ~= "engine/").toBe(true)
		end
	end)

	it("the engine's requires form no cycle", function()
		local state: { [string]: string } = {}
		local cycle: string? = nil
		local function visit(file: string, path: { string })
			if state[file] == "done" or cycle then
				return
			end
			if state[file] == "open" then
				cycle = table.concat(path, " -> ") .. " -> " .. file
				return
			end
			state[file] = "open"
			table.insert(path, file)
			for _, dep in (g.deps[file] or {}) :: { string } do
				visit(dep, path)
			end
			table.remove(path)
			state[file] = "done"
		end
		for _, file in engineFiles() do
			visit(file, {})
		end
		t.expect(cycle).toBe(nil)
	end)

	it("USAGE and the READ_ONLY declaration stay in main.luau", function()
		local main = fs.readFile(MAIN)
		t.expect((string.find(main, "\nlocal USAGE = [[", 1, true)) ~= nil).toBe(true)
		t.expect((string.find(main, "\nlocal READ_ONLY: { [string]: boolean } = {", 1, true)) ~= nil)
			.toBe(true)
	end)
end)
