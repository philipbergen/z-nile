--!strict
-- c0122 AC3: the places that restate the ref guard's fetch rule agree with the hook. c0131 made the hook accept the
-- empty ref transaction of a fetch with nothing new (outside spec runs), but the zz-test skill's Ref guard bullet and
-- fence.sh's header still described only a fetch that creates or moves a ref. The hook's own header already says it.
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

return t.spec("c0122 the ref guard's fetch rule is stated the same everywhere", function(it)
	it(
		"AC3: the zz-test skill's Ref guard bullet says a fetch with nothing new is accepted, and a spec run's is not",
		function()
			local skill = fs.readFile(`{root}/z-nile/skills/zz-test/SKILL.md`)
			local bullet = lineStarting(skill, "  - **Ref guard**:")
			t.expect(bullet ~= "").toBe(true)
			t.expect(missing(bullet, {
				"Only a `check.sh` flow started outside any spec run may fetch: it may create or move refs under `refs/remotes/` (not delete one)",
				"a fetch with nothing new, which git runs as an empty ref transaction, is accepted too (c0131)",
				"so a check can fetch whether or not anything is new.",
				"A fetch that writes any other ref is refused, as is one that prunes a ref or follows a tag into `refs/tags/` (`--prune`, `fetch.prune`, `fetch.pruneTags`, `remote.<name>.prune`, `remote.<name>.pruneTags` and `remote.<name>.tagOpt` can turn either on), and so is one whose remote's own refspecs (`remote.<name>.fetch`) write outside `refs/remotes/`",
				"the whole fetch is refused only with `--atomic` (git 2.50.1 may refuse a plain fetch ref by ref, after it has moved some `refs/remotes/` refs)",
				"so a check fetches with `git fetch --atomic --no-prune --no-prune-tags --no-tags origin`, which overrides those settings but not the refspecs",
				"during a spec run every update is refused, an empty one included (for a plain fetch with nothing new, git 2.50.1 starts no transaction at all)",
			})).toBe("")
			-- the new sentence replaces the old one: the narrower form must not stay beside it
			t.expect(has(bullet, "may fetch (create or move refs under")).toBe(false)
		end
	)

	it("AC3: fence.sh's header says a check.sh flow may fetch even when nothing is new", function()
		local text = fs.readFile(`{root}/z-nile/lib/fence.sh`)
		local line = lineStarting(text, "#   - refuses ref updates in the real repository")
		t.expect(line ~= "").toBe(true)
		t.expect(missing(line, {
			"check.sh flows may still fetch into refs/remotes/, even a fetch with nothing new",
		})).toBe("")
	end)

	it("AC3: the gate scan's allowance for the two end-to-end specs is in place", function()
		local text = fs.readFile(`{root}/z-nile/tests/tooling/repo-fence.spec.luau`)
		-- built by concatenation: this file must not name the fence variables itself
		local name = "PICKMAN" .. "_FENCE_"
		t.expect(missing(text, {
			'local C0122 = renamed.id("c0122")',
			'for _, name in { "fetch.spec.luau", "refuse.spec.luau" } do',
			"ALLOWED[`z-nile/tests/acceptance/{C0122}/{name}`] = {",
			`{name} = "fences a .cache fixture in one bash process and sets or clears {name}SPECS for that process only (c0122)",`,
		})).toBe("")
	end)

	it("AC3: the hook's own header says the same, so the three places agree", function()
		local text = fs.readFile(`{root}/z-nile/lib/git-hooks/reference-transaction`)
		t.expect(has(text, "and the empty transaction of a fetch with nothing new.")).toBe(true)
	end)
end)
