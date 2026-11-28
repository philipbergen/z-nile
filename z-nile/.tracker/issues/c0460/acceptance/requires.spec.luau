--!strict
-- c0460: an acceptance spec of a z-nile ticket that carries `Mutants: mutants.md` requires only @tests/lib/* and
-- @lune/*. The scanner reads every spelling of require; the walk reads (never writes) the checkout's z-nile tickets
-- and this ticket's own folder. This spec itself requires only @tests/lib/* and @lune/*.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ITEMS = `{TOP}/z-nile/.tracker/issues`
-- This spec's own folder, from its own path: the ticket's folder in the backlog, in active/ or, once promoted,
-- tests/acceptance/c0460. It always holds this spec, so the walk below is never empty.
local OWN = string.match(debug.info(1, "s"), "^(.*)/[^/]+$") :: string

-- The same arming test as the engine's: a Test plan line outside a fence that trims to the line (a `- ` allowed).
local function carries(plan: string): boolean
	local fenced = false
	for line in string.gmatch(plan .. "\n", "([^\n]*)\n") do
		if string.match(line, "^%s*```") or string.match(line, "^%s*~~~") then
			fenced = not fenced
		elseif not fenced then
			local bare = string.gsub(string.gsub(line, "^%s*[-*+]%s+", ""), "%s+$", "")
			if string.gsub(bare, "^%s+", "") == "Mutants: mutants.md" then
				return true
			end
		end
	end
	return false
end

-- The aliases a text requires that the rule does not allow, whatever the spelling of the call.
local function foreign(text: string): { string }
	local bad: { string } = {}
	for alias in string.gmatch(text, "require%s*%(?%s*[\"'](@[^\"']*)[\"']") do
		if
			not (
				string.find(alias, "@tests/lib/", 1, true) == 1
				or string.find(alias, "@lune/", 1, true) == 1
			)
		then
			table.insert(bad, alias)
		end
	end
	return bad
end

-- Every `acceptance/*.luau` file of the ticket folders (any state folder) whose document carries the line.
local function armed(): { string }
	local files: { string } = {}
	local function walk(dir: string, depth: number)
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isDir(path) and depth < 3 then
				walk(path, depth + 1)
			elseif name == `{string.match(dir, "([^/]+)$")}.md` and fs.isFile(path) then
				local plan = string.match(fs.readFile(path), "\n## Test plan\n(.-)\n## ")
				if plan and carries(plan) then
					local acc = `{dir}/acceptance`
					if fs.isDir(acc) then
						for _, f in fs.readDir(acc) do
							if string.match(f, "%.luau$") then
								table.insert(files, `{acc}/{f}`)
							end
						end
					end
				end
			end
		end
	end
	walk(ITEMS, 0)
	return files
end

return t.spec("acceptance requires of z-nile tickets (c0460)", function(it)
	it("the scanner finds every spelling of a require of another alias", function()
		-- the quote and the alias are built apart, so this file's own text holds no require of another alias
		local function call(open: string, alias: string, close: string): string
			return "local e = require" .. open .. alias .. close
		end
		t.expect(#foreign(call('("', "@znile/engine/x", '")'))).toBe(1)
		t.expect(#foreign(call("('", "@znile/engine/x", "')"))).toBe(1)
		t.expect(#foreign(call(' "', "@znile/engine/x", '"'))).toBe(1)
		t.expect(#foreign(call(' ( "', "@scripts/y", '" )'))).toBe(1)
		t.expect(#foreign(call('("', "@tests/lib/t", '")') .. call('("', "@lune/fs", '")'))).toBe(0)
	end)

	it(
		"every acceptance file of this ticket and of every ticket carrying the line requires only the two aliases",
		function()
			local own = OWN
			local files = armed()
			if fs.isDir(own) then
				for _, f in fs.readDir(own) do
					if string.match(f, "%.luau$") then
						table.insert(files, `{own}/{f}`)
					end
				end
			end
			t.expect(#files > 0).toBe(true)
			for _, file in files do
				local bad = foreign(fs.readFile(file))
				if #bad > 0 then
					error(`{file} requires {table.concat(bad, ", ")}`, 0)
				end
			end
		end
	)

	it("the arming test reads the plain, marker and fenced forms like the engine", function()
		t.expect(carries("a\nMutants: mutants.md\nb")).toBe(true)
		t.expect(carries("- Mutants: mutants.md")).toBe(true)
		t.expect(carries("```\nMutants: mutants.md\n```")).toBe(false)
		t.expect(carries("Mutants: mutants.txt")).toBe(false)
	end)
end)
