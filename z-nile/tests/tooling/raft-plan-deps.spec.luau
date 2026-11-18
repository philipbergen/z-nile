--!strict
-- f0399: `./zn raft-plan` passes each issue's depends_on to the planner, so an issue joins the raft of what it
-- depends on (even past the size cap), and a dependency that is done changes nothing. Read-only: the real
-- `./zn raft-plan` runs in a fixture under .cache/ (modeled on c0116's plan-cli spec).
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local KINDS = { f = "feature", d = "defect", c = "chore" }

local function issue(id: string, deps: string, size: number, touched: string): string
	return `---\nid: {id}\ntype: {KINDS[string.sub(id, 1, 1)]}\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: [{deps}]\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: {size}\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Design\n\n### Touched modules\n- \`{touched}\`\n\n### Affected specs\n\n## Unknowns & experiments\n`
end

local function seedOf(issues: { [string]: string }): { [string]: string }
	local seed: { [string]: string } = {
		[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
		["pickman/.tracker/architecture.md"] = "# Architecture\n",
	}
	for path, text in issues do
		seed[path] = text
		seed[(string.gsub(path, "/[^/]+$", "/check.sh"))] = CHECK
	end
	return seed
end

local function plan(name: string, issues: { [string]: string }): { string }
	local f = trackerfix.new(name, seedOf(issues))
	return string.split(trackerfix.trOk(f, f.main, { "raft-plan" }), "\n")
end

return t.spec("f0399 raft-plan passes depends_on to the planner", function(it)
	it("puts an issue in the raft of its dependency when their modules do not overlap", function()
		local apart = plan("f0399-plan-apart", {
			["pickman/.tracker/issues/f0060/f0060.md"] = issue("f0060", "", 100, "pickman/src/Maze"),
			["pickman/.tracker/issues/f0070/f0070.md"] = issue("f0070", "", 100, "pickman/src/Ghost"),
		})
		t.expect(#apart).toBe(2)
		local joined = plan("f0399-plan-joined", {
			["pickman/.tracker/issues/f0060/f0060.md"] = issue("f0060", "", 100, "pickman/src/Maze"),
			["pickman/.tracker/issues/f0070/f0070.md"] = issue("f0070", "f0060", 100, "pickman/src/Ghost"),
		})
		t.expect(joined).toEqual({ "./zn new raft feature f0060 f0060 f0070 --project pickman" })
	end)

	it("leaves the plan as it was when the dependency is done", function()
		local lines = plan("f0399-plan-done", {
			["pickman/.tracker/issues/done/f0050/f0050.md"] = issue("f0050", "", 100, "pickman/src/Pill"),
			["pickman/.tracker/issues/f0060/f0060.md"] = issue("f0060", "", 100, "pickman/src/Maze"),
			["pickman/.tracker/issues/f0070/f0070.md"] = issue("f0070", "f0050", 100, "pickman/src/Ghost"),
		})
		t.expect(#lines).toBe(2)
		for _, line in lines do
			t.expect(string.find(line, "f0050", 1, true) == nil).toBe(true)
		end
	end)
end)
