--!strict
-- f0420: the raft a rafting step makes carries its members' common tributary: line, so a theme keeps its tickets once they
-- are rafted. `new raft` (and raft-plan --apply, which runs it) and `fold` write it when every member agrees, and leave
-- it empty when they differ. Driven through ./zn in worktrees of a fixture under .cache (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 300\n{extra or ""}status: {PREPARED}\n---\n\n# {id}\n`
end
local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Landed\nslug: landed\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nLanded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end

local function raftDocT(id: string, issues: string, tributary: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Landed\nslug: landed\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\n{tributary}status: {PREPARED}\n---\n\n# {id}\n\n## Theme\nLanded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end

local f: trackerfix.Fixture
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function lineOf(text: string, key: string): string
	return string.match(text, `\n{key}:[ ]*([^\n]*)\n`) or ""
end

return t.spec("f0420: a raft carries its members' common tributary", function(it)
	it("new raft writes it when every member agrees and leaves it empty when they differ", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "", "tributary: worker\n"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "", "tributary: worker\n"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "", "tributary: worker\n"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "", "tributary: board\n"),
			["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "", "tributary: worker\n"),
			["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", "", "tributary: board\n"),
			["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "R0090", "tributary: worker\n"),
			["pickman/.tracker/issues/c0071/c0071.md"] = issue("c0071", "R0091", "tributary: worker\n"),
			["pickman/.tracker/rafts/R0090/R0090.md"] = raftDocT("R0090", "c0070", ""),
			["pickman/.tracker/rafts/R0091/R0091.md"] = raftDocT("R0091", "c0071", "tributary: worker\n"),
			["pickman/.tracker/rafts/R0090/check.sh"] = CHECK,
			["pickman/.tracker/rafts/R0091/check.sh"] = CHECK,
		}
		for _, id in { "c0010", "c0020", "c0030", "c0040", "c0050", "c0060", "c0070", "c0071" } do
			seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
		end
		f = trackerfix.new("f0420-tributary-source", seed)
		local A = trackerfix.trOk(f, f.main, { "worktree", "raft-a" })
		local B = trackerfix.trOk(f, f.main, { "worktree", "raft-b" })
		local C = trackerfix.trOk(f, f.main, { "worktree", "raft-c" })
		local D = trackerfix.trOk(f, f.main, { "worktree", "raft-d" })
		local agree = string.match(
			trackerfix.trOk(
				f,
				A,
				{ "new", "raft", "chore", "pair", "c0010", "c0020", "--project", "pickman" }
			),
			"(R%d+)"
		) :: string
		t.expect(lineOf(onOrigin(`pickman/.tracker/rafts/{agree}/{agree}.md`) or "", "tributary"))
			.toBe("worker")
		local differ = string.match(
			trackerfix.trOk(f, B, { "new", "raft", "chore", "mix", "c0030", "c0040", "--project", "pickman" }),
			"(R%d+)"
		) :: string
		t.expect(lineOf(onOrigin(`pickman/.tracker/rafts/{differ}/{differ}.md`) or "", "tributary")).toBe("")
		-- fold: the raft's line follows its members
		trackerfix.trOk(f, C, { "fold", "R0090", "c0050" })
		t.expect(has(fs.readFile(`{C}/pickman/.tracker/rafts/R0090/R0090.md`), "\ntributary: worker\n"))
			.toBe(true)
		trackerfix.trOk(f, D, { "fold", "R0091", "c0060" })
		t.expect(lineOf(fs.readFile(`{D}/pickman/.tracker/rafts/R0091/R0091.md`), "tributary")).toBe("")
	end)
end)
