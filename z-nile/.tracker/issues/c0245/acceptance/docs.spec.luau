--!strict
-- c0245 AC6: the skills that restate the seatbelt's tooling rule say it decides by the file the path reaches, never by
-- its suffix, and how a TOOLING entry is written (z-design/restated-rules-move-together).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local ROOT = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(rel: string): string
	local path = `{ROOT}/{rel}`
	if not fs.isFile(path) then
		error(`{rel} is missing`, 0)
	end
	return fs.readFile(path)
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0245 the skills state the tooling rule by file", function(it)
	it(
		"AC6: zz-test's hook paragraph says a target counts by the file it reaches, never by its suffix",
		function()
			local test = read("z-nile/skills/zz-test/SKILL.md")
			local hook = string.match(test, "%- %*%*The hook%*%*[^\n]*") or ""
			t.expect(
				has(
					hook,
					"a target counts by the file it reaches in this checkout or one of its worktrees, written relative or absolute, never by its suffix (c0245)"
				)
			).toBe(true)
			-- c0244's wording stays beside it
			t.expect(
				has(
					hook,
					"each registered home's `tests/run` counts without an entry, from the registry, c0244"
				)
			).toBe(true)
		end
	)

	it("AC6: zz-arch says a TOOLING entry is the entry's path from the top of the tree", function()
		local arch = read("z-nile/skills/zz-arch/SKILL.md")
		t.expect(has(arch, "joins `TOOLING` in `z-nile/engine/boundcmd.luau`")).toBe(true)
		t.expect(has(arch, "as its path from the top of the tree (`z-nile/affected`)")).toBe(true)
		t.expect(has(arch, "by the file the path reaches, never by its suffix (c0245)")).toBe(true)
	end)
end)
