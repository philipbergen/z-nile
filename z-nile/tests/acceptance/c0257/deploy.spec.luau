--!strict
-- c0257 AC4: the place-deploy workflow ignores pushes that touch only the plugin, and keeps the tracker roots it ignored.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds the edited files (prep proved these specs against the prototype that way)
local TREE = process.env.ZN_C0257_TREE or TOP

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0257 AC4: deploy.yml ignores the plugin", function(it)
	it(
		"AC4: the push ignore list names z-nile-omarchy/** before z-nile/next and keeps the tracker roots",
		function()
			local wf = fs.readFile(`{TREE}/.github/workflows/deploy.yml`)
			local ignore = string.match(wf, "push:.-paths%-ignore: (%b[])") or ""
			t.expect(has(ignore, "'z-nile-omarchy/**', 'z-nile/next'")).toBe(true)
			t.expect(has(ignore, "'z-nile/.tracker/**'")).toBe(true)
			t.expect(has(ignore, "'pickman/.tracker/**'")).toBe(true)
		end
	)

	it("AC4: the one copy of the list the specs compare against names it too", function()
		local list = fs.readFile(`{TREE}/z-nile/tests/lib/deploylist.luau`)
		t.expect(has(list, 'table.insert(out, "z-nile-omarchy/**")')).toBe(true)
	end)

	it("AC4: pickman's entry-shape spec allows exactly that entry, and no other glob", function()
		local spec = fs.readFile(`{TREE}/pickman/tests/acceptance/c0015/workflow.spec.luau`)
		t.expect(has(spec, 'e == "z-nile-omarchy/**"')).toBe(true)
		t.expect(has(spec, "^[a-z][a-z0-9%-]*/%.tracker/%*%*$")).toBe(true)
	end)
end)
