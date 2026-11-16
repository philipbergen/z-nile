--!strict
-- c0195 AC8: the places that restate the repository guards say what the fence's git does and what it can't see: the
-- zz-test skill (its own bullet after the Ref guard bullet), fence.sh's header, zz-arch's row for z-nile/lib/, and
-- the gate scan's allowance for the two specs that name a jail or a fence variable (wiring.spec, closed.spec).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- The first line of `text` that starts with `prefix`, or "" (so a missing line fails its own case, never passes by absence)
local function lineStarting(text: string, prefix: string): string
	for line in string.gmatch(text, "[^\n]+") do
		if string.sub(line, 1, #prefix) == prefix then
			return line
		end
	end
	return ""
end

local function missing(line: string, phrases: { string }): string
	local out = {}
	for _, p in phrases do
		if not has(line, p) then
			table.insert(out, p)
		end
	end
	return table.concat(out, " | ")
end

return t.spec("c0195 the fence's git is stated where the guards are", function(it)
	it("AC8: the zz-test skill has a Fence's git bullet right after the Ref guard bullet", function()
		local skill = fs.readFile(`{root}/z-nile/skills/zz-test/SKILL.md`)
		local lines = string.split(skill, "\n")
		local at = 0
		for i, line in lines do
			if string.sub(line, 1, 18) == "  - **Ref guard**:" then
				at = i
			end
		end
		t.expect(at > 0).toBe(true)
		local bullet = lines[at + 1] or ""
		t.expect(string.sub(bullet, 1, 21)).toBe("  - **Fence's git**: ")
		t.expect(missing(bullet, {
			"so `git` is `z-nile/lib/git-hooks/git` (c0195)",
			"`git branch -c`/`-C` copy a branch without calling `reference-transaction` at all",
			"a `git branch -m`/`-M` the hook refuses has already moved the branch's reflog aside",
			"refuses a branch copy or rename in any spelling, and any command that is not one of git's own (an alias or an external command, whose expansion it can't see)",
			"everything in a fixture, goes straight to the real git",
			"git's own exec path first on their `PATH`",
			"nor one called by its full path: review catches those",
		})).toBe("")
	end)

	it("AC8: fence.sh's header names the fence's git", function()
		local text = fs.readFile(`{root}/z-nile/lib/fence.sh`)
		local line = lineStarting(text, "#   - where it sets those hooks, finds git first in their folder")
		t.expect(line ~= "").toBe(true)
		t.expect(has(line, "(git-hooks/git, c0195)")).toBe(true)
	end)

	it("AC8: zz-arch's row for z-nile/lib/ names the fence's git", function()
		local text = fs.readFile(`{root}/z-nile/skills/zz-arch/SKILL.md`)
		local row = lineStarting(text, "| `z-nile/lib/` |")
		t.expect(row ~= "").toBe(true)
		t.expect(has(row, "`git-hooks/git` (the fence's git, c0195)")).toBe(true)
	end)

	it(
		"AC8: the gate scan's allowance for the two specs that name a jail or a fence variable is in place",
		function()
			local text = fs.readFile(`{root}/z-nile/tests/tooling/repo-fence.spec.luau`)
			-- built by concatenation: this file must not name the jail or the fence variables itself
			local fence, jail = "PICKMAN" .. "_FENCE_", "sandbox" .. "-exec"
			t.expect(missing(text, {
				'local C0195 = renamed.id("c0195")',
				"ALLOWED[`z-nile/tests/acceptance/{C0195}/wiring.spec.luau`] = {",
				`["{jail}"] = "fences a .cache fixture as the jailed runner does, to prove the jail's fence takes the fence's git off the PATH (c0195)",`,
				"ALLOWED[`z-nile/tests/acceptance/{C0195}/closed.spec.luau`] = {",
				`{fence} = "clears {fence}HOOKS for one fence call in a fixture, and runs the fence's git with {fence}GIT unset, missing or itself (c0195)",`,
			})).toBe("")
		end
	)
end)
