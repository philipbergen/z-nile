--!strict
-- c0420: no spec names a legacy-layout document path (<ID>-<slug>.md). Documents are <ID>.md, so a spec
-- (or a prepped raft's acceptance spec) that writes or expects the old name breaks the moment it runs
-- against the real tracker. The naming spec builds legacy names on purpose and is exempt by name.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local LEGACY = "[fdcR]%d%d%d%d%-[a-z][%w%-]*%.md"
local EXEMPT = "naming.spec.luau" -- c0420's own spec, promoted to tests/acceptance/c0420/

local function specs(dir: string, out: { string })
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			specs(path, out)
		elseif string.match(name, "%.spec%.luau$") and name ~= EXEMPT then
			table.insert(out, path)
		end
	end
end

return t.spec("legacy document names in specs", function(it)
	it("no spec under tests/ or tracker/ names a <ID>-<slug>.md document", function()
		local files: { string } = {}
		specs("tests", files)
		specs("tracker", files)
		t.expect(#files > 0).toBe(true)
		local bad: { string } = {}
		for _, path in files do
			for n, line in string.split(fs.readFile(path), "\n") do
				local hit = string.match(line, LEGACY)
				if hit then
					table.insert(bad, `{path}:{n}: {hit}`)
				end
			end
		end
		t.expect(table.concat(bad, "\n")).toBe("")
	end)
end)
