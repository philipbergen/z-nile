--!strict
-- c0180: on the real tree, read only: z-nile/recordkey keys every spec of every home, and no spec's require closure
-- reaches a file the one graph never built (the forwarders included). It reads every home's specs and what they require,
-- so it is declared `*` in z-nile/tests/inputs.tsv. Runs from z-nile's home.
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

return t.spec("c0180 the record's keys on the real tree", function(it)
	it("on the real tree, no spec's closure reaches a file the graph didn't build, read only", function()
		local listed = process.exec("git", { "ls-files", "*.spec.luau" }, { cwd = root })
		local argv = { "run", "z-nile/recordkey", "--", "--dangling" }
		local n = 0
		for line in string.gmatch(listed.stdout, "[^\n]+") do
			if string.match(line, "^[^/]+/tests/") then
				table.insert(argv, line)
				n += 1
			end
		end
		t.expect(n > 300).toBe(true)
		local r = process.exec("lune", argv, { cwd = root })
		t.expect(r.ok).toBe(true)
		t.expect(r.stdout).toBe("")
	end)

	it("on the real tree, z-nile/recordkey keys every spec of every home, read only", function()
		local listed = process.exec("git", { "ls-files", "*.spec.luau" }, { cwd = root })
		t.expect(listed.ok).toBe(true)
		local specs: { string } = {}
		for line in string.gmatch(listed.stdout, "[^\n]+") do
			if string.match(line, "^[^/]+/tests/") then
				table.insert(specs, line)
			end
		end
		t.expect(#specs > 300).toBe(true)
		local argv = { "run", "z-nile/recordkey", "--" }
		for _, s in specs do
			table.insert(argv, s)
		end
		local r = process.exec("lune", argv, { cwd = root })
		t.expect(r.ok).toBe(true)
		local keyed = 0
		for line in string.gmatch(r.stdout, "[^\n]+") do
			if string.sub(line, 1, 5) ~= "tree\t" then
				local s, key = string.match(line, "^(.-)\t(%x+)$")
				t.expect(s ~= nil and #(key :: string) == 64).toBe(true)
				keyed += 1
			end
		end
		t.expect(keyed).toBe(#specs)
		t.expect(string.match(r.stdout, "^tree\t(%a+)\n") ~= nil).toBe(true)
	end)
end)
