--!strict
-- c0116 AC4: `raft-plan [--apply]` reads the tree (each issue's type, project root, state, status, design, raft:,
-- size:, solo: and Touched modules; each raft's type, root, state, status, single: and members), prints raftplan's
-- plan as the commands that carry it out, one per line, then `skip <id>: <why>`, or `raft-plan: nothing to raft`.
-- It only reads, so it runs in the main checkout; `--apply` runs the commands in a worktree and refuses the main
-- checkout. Driven through scripts/tracker.sh in fixtures under .cache/c0116-plan-cli and .cache/c0116-plan-none.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local KINDS = { f = "feature", d = "defect", c = "chore" }

local function issue(id: string, raft: string, front: string, touched: { string }?): string
	local list = ""
	local paths: { string } = touched or {}
	for _, p in paths do
		list ..= `- \`{p}\`\n`
	end
	return `---\nid: {id}\ntype: {KINDS[string.sub(id, 1, 1)]}\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\n{front}status: {PREPARED}\n---\n\n# {id}\n\n## Design\n\n### Touched modules\n{list}\n### Affected specs\n\n## Unknowns & experiments\n`
end
local function raftDoc(id: string, kind: string, issues: string, single: boolean?): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {string.lower(id)}\nsingle: {if single
		then "true"
		else "false"}\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`
end

local f: trackerfix.Fixture
local W = ""

local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end

local EXPECTED = {
	"./zn new raft feature f0060 f0060 f0070",
	"./zn fold R0030 d0010 d0020",
	"./zn new raft chore c0040 c0040 --single",
	"./zn new raft chore c0100 c0100",
	"./zn new raft chore c0080 c0080 c0090",
	"skip c0050: no size: (z-design records its estimate of changed lines)",
}

return t.spec("c0116 raft-plan prints z-raft's plan as commands, and --apply runs them", function(it)
	it("sets up a backlog that exercises every rule the plan reads from the documents", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(".gitignore"),
			["tracker/architecture.md"] = "# Architecture\n",
		}
		local function add(path: string, text: string)
			seed[path] = text
			seed[string.gsub(path, "/[^/]+$", "/check.sh")] = CHECK
		end
		add("tracker/issues/d0010/d0010.md", issue("d0010", "", "size: 200\n"))
		add("tracker/issues/d0020/d0020.md", issue("d0020", "", "size: 200\n"))
		add("tracker/issues/d0031/d0031.md", issue("d0031", "R0030", "size: 1000\n"))
		add("tracker/rafts/R0030/R0030.md", raftDoc("R0030", "defect", "d0031"))
		-- a single raft and a raft being prepared take nothing
		add("tracker/issues/d0032/d0032.md", issue("d0032", "R0025", "size: 10\n"))
		add("tracker/rafts/R0025/R0025.md", raftDoc("R0025", "defect", "d0032", true))
		add("tracker/issues/c0040/c0040.md", issue("c0040", "", "size: 100\nsolo: true\n"))
		add("tracker/issues/c0050/c0050.md", issue("c0050", "", ""))
		add("tracker/issues/f0060/f0060.md", issue("f0060", "", "size: 100\n", { "pickman/src/Maze" }))
		add(
			"tracker/issues/f0070/f0070.md",
			issue("f0070", "", "size: 100\n", { "pickman/src/Maze/grid.luau" })
		)
		add("z-nile/.tracker/issues/c0080/c0080.md", issue("c0080", "", "size: 100\n"))
		add("z-nile/.tracker/issues/c0090/c0090.md", issue("c0090", "", "size: 100\n"))
		add("tracker/issues/c0100/c0100.md", issue("c0100", "", "size: 100\n"))
		-- not candidates: a draft, and a prepared issue that is already in a raft
		add(
			"tracker/issues/c0110/c0110.md",
			(string.gsub(issue("c0110", "", "size: 100\n"), "design: ready", "design: draft"))
		)
		f = trackerfix.new("c0116-plan-cli", seed)
		W = trOk(f.main, { "worktree", "raft-w" })
	end)

	it("prints the plan as commands and the skips, in the main checkout, writing nothing", function()
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local out = trOk(f.main, { "raft-plan" })
		t.expect(string.split(out, "\n")).toEqual(EXPECTED)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
		t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
	end)

	it("refuses --apply in the main checkout", function()
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local r = trackerfix.tr(f, f.main, { "raft-plan", "--apply" })
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "raft-plan --apply must run inside a worktree", 1, true) ~= nil)
			.toBe(true)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
	end)

	it(
		"--apply runs the commands in a worktree: rafts claimed, raft: lines written, only the skip left",
		function()
			trOk(W, { "raft-plan", "--apply" })
			t.expect(
				string.match(onOrigin("tracker/rafts/R0030/R0030.md") or "", "\nstatus: preparing%-") ~= nil
			)
				.toBe(true)
			local function raftOf(path: string): string?
				return string.match(fs.readFile(`{W}/{path}`), "\nraft: (%S*)\n")
			end
			t.expect(raftOf("tracker/issues/d0010/d0010.md")).toBe("R0030")
			t.expect(raftOf("tracker/issues/f0060/f0060.md")).toBe(raftOf("tracker/issues/f0070/f0070.md"))
			t.expect(raftOf("z-nile/.tracker/issues/c0080/c0080.md"))
				.toBe(raftOf("z-nile/.tracker/issues/c0090/c0090.md"))
			local solo = raftOf("tracker/issues/c0040/c0040.md") :: string
			t.expect(
				string.find(fs.readFile(`{W}/tracker/rafts/{solo}/{solo}.md`), "\nsingle: true\n", 1, true)
					~= nil
			).toBe(true)
			t.expect(fixture.git(W, { "status", "--porcelain" })).toBe("")
			t.expect(trOk(W, { "raft-plan" })).toBe(EXPECTED[6])
		end
	)

	it("says so when there is nothing to raft", function()
		f = trackerfix.new(
			"c0116-plan-none",
			{ ["tracker/issues/c0010/c0010.md"] = issue("c0010", "R0010", "size: 5\n") }
		)
		t.expect(trOk(f.main, { "raft-plan" }))
			.toBe("raft-plan: nothing to raft (no prepared issue without a raft)")
	end)
end)
