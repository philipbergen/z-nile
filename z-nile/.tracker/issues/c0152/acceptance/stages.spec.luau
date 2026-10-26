--!strict
-- c0152 AC1 (design review 002 F2): z-nile/tests/merge-stages.txt is the one list of gate stages that read tracker
-- files, and it is complete: every promoted spec the search below finds is a `run` line or a reasoned `skip` line, every
-- listed spec exists, and audit, check-paths and classified run. A new spec that walks the real tree's items must
-- join the list (or say why not) in the change that adds it.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- the search the list came from (c0152 Design, design review 002 F2)
local PATTERN = "real tree|every unfinished|this checkout.s working tree|reads the real|the real checkout"
	.. "|audit\\.(run|scan|leftovers)\\((TOP|root)|board\\.collect\\(nil, (TOP|root)\\)|lessons\\.load\\(TOP"
	.. '|cwd = TOP[ ,}]|\\{(TOP|root)\\}/issues|rewrites\\.premove\\(TOP|readFile\\("\\.tracker/'

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function listed(): ({ [string]: string }, { string })
	local kind: { [string]: string } = {}
	local runs: { string } = {}
	for l in string.gmatch(fs.readFile(`{TOP}/z-nile/tests/merge-stages.txt`), "[^\n]+") do
		local home, spec, why = string.match(l, "^run%s+(%S+)%s+(%S+)%s+%-%-%s+(%S.*)$")
		if home and spec and why then
			t.expect(kind[`{home}/{spec}`]).toBe(nil)
			kind[`{home}/{spec}`] = "run"
			table.insert(runs, `{home}/{spec}`)
		else
			local path, reason = string.match(l, "^skip%s+(%S+)%s+%-%-%s+(%S.*)$")
			if path and reason then
				t.expect(kind[path]).toBe(nil)
				kind[path] = "skip"
			else
				t.expect(string.match(l, "^#") ~= nil).toBe(true) -- nothing else: a run or skip without its reason fails
			end
		end
	end
	return kind, runs
end

return t.spec("c0152 the gate stages that read tracker files are one complete list", function(it)
	it("every spec the search finds is run or skipped with a reason", function()
		local kind = listed()
		local r = process.exec(
			"git",
			{ "grep", "-lE", PATTERN, "--", "z-nile/tests/**/*.spec.luau", "pickman/tests/**/*.spec.luau" },
			{ cwd = TOP }
		)
		t.expect(r.ok).toBe(true)
		local missing: { string } = {}
		for p in string.gmatch(r.stdout, "[^\n]+") do
			if not kind[p] then
				table.insert(missing, p)
			end
		end
		t.expect(table.concat(missing, "\n")).toBe("")
	end)

	it("every listed spec exists, and audit, check-paths and classified run", function()
		local kind, runs = listed()
		for p in kind do
			t.expect(fs.isFile(`{TOP}/{p}`)).toBe(true)
		end
		for _, p in
			{
				"z-nile/tests/acceptance/c0082/real-tree.spec.luau",
				"z-nile/tests/acceptance/c0120/check-paths.spec.luau",
				"z-nile/tests/acceptance/c0114/classified.spec.luau",
			}
		do
			t.expect(table.find(runs, p) ~= nil).toBe(true)
		end
	end)
end)
