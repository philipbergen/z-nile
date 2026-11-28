--!strict
-- f0464 AC7, AC5: `./zn raft-plan` makes no raft by default: for every prepared ticket in no raft it prints one
-- `skip <id>:` line naming `./zn ready <id>` and no `./zn fold` or `./zn new raft` command, even for a backlog the old
-- policy would fold and group, and `--apply` (in a worktree) publishes and changes nothing. A raft of two or more
-- issues still needs a coherence review that covers its grouping record before ready accepts it (readycheck.record).
-- The CLI cases drive scripts/tracker.sh in a fixture under .cache/f0464-plan.
local fixture = require("@tests/lib/fixture")
local raftplan = require("@znile/engine/raftplan")
local readycheck = require("@znile/engine/readycheck")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local KINDS = { f = "feature", d = "defect", c = "chore" }

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function issue(id: string, raft: string, front: string, touched: { string }?): string
	local list = ""
	for _, p in (touched or {}) :: { string } do
		list ..= `- \`{p}\`\n`
	end
	return `---\nid: {id}\ntype: {KINDS[string.sub(id, 1, 1)]}\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-28\n{front}status: {PREPARED}\n---\n\n# {id}\n\n## Design\n\n### Touched modules\n{list}\n### Affected specs\n\n## Unknowns & experiments\n`
end
local function raftDoc(id: string, kind: string, issues: string): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {id}\nslug: {string.lower(id)}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-28\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`
end

local f: trackerfix.Fixture
local W = ""

return t.spec("f0464 raft-plan makes no raft by default", function(it)
	it("sets up a backlog the old policy would fold and group", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
		}
		local function add(path: string, text: string)
			seed[path] = text
			seed[string.gsub(path, "/[^/]+$", "/check.sh")] = CHECK
		end
		-- two defects and an open prepared defect raft (folded before), two features on one surface (grouped)
		add("pickman/.tracker/issues/d0010/d0010.md", issue("d0010", "", "size: 200\n"))
		add("pickman/.tracker/issues/d0020/d0020.md", issue("d0020", "", "size: 200\n"))
		add("pickman/.tracker/issues/d0031/d0031.md", issue("d0031", "R0030", "size: 100\n"))
		add("pickman/.tracker/rafts/R0030/R0030.md", raftDoc("R0030", "defect", "d0031"))
		add(
			"pickman/.tracker/issues/f0060/f0060.md",
			issue("f0060", "", "size: 100\n", { "pickman/src/Maze" })
		)
		add(
			"pickman/.tracker/issues/f0070/f0070.md",
			issue("f0070", "", "size: 100\n", { "pickman/src/Maze/grid.luau" })
		)
		-- no size: is no longer a reason to skip (size was the policy's input)
		add("pickman/.tracker/issues/c0050/c0050.md", issue("c0050", "", ""))
		-- not candidates: a draft
		add(
			"pickman/.tracker/issues/c0110/c0110.md",
			(string.gsub(issue("c0110", "", "size: 100\n"), "design: ready", "design: draft"))
		)
		f = trackerfix.new("f0464-plan", seed)
		W = trackerfix.trOk(f, f.main, { "worktree", "raft-w" })
	end)

	it(
		"AC5: prints one skip line per prepared ticket in no raft, naming ./zn ready, and no command",
		function()
			local before = fixture.git(f.origin, { "rev-parse", "main" })
			local out = trackerfix.trOk(f, f.main, { "raft-plan" })
			local lines = string.split(out, "\n")
			local ids: { string } = {}
			for _, line in lines do
				t.expect(has(line, "./zn fold")).toBe(false)
				t.expect(has(line, "./zn new raft")).toBe(false)
				local id = string.match(line, "^skip (%a%d+): ")
				t.expect(id ~= nil).toBe(true)
				t.expect(has(line, `./zn ready {id}`)).toBe(true)
				table.insert(ids, id :: string)
			end
			t.expect(ids).toEqual({ "c0050", "d0010", "d0020", "f0060", "f0070" })
			t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
			t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
		end
	)

	it("AC5: --apply in a worktree runs nothing: no commit, no publish, no raft: line written", function()
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		local head = fixture.git(W, { "rev-parse", "HEAD" })
		local out = trackerfix.trOk(f, W, { "raft-plan", "--apply" })
		t.expect(has(out, "./zn fold")).toBe(false)
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
		t.expect(fixture.git(W, { "rev-parse", "HEAD" })).toBe(head)
		t.expect(fixture.git(W, { "status", "--porcelain" })).toBe("")
		-- the main checkout is still refused for --apply
		local r = trackerfix.tr(f, f.main, { "raft-plan", "--apply" })
		t.expect(r.ok).toBe(false)
	end)

	it("AC5: a raft of two issues is readied only with a coherence review that covers its record", function()
		local files = { ["c0010.md"] = "---\nid: c0010\n---\n", ["check.sh"] = CHECK }
		local other = { ["c0011.md"] = "---\nid: c0011\n---\n", ["check.sh"] = CHECK }
		local members: { readycheck.Member } = {
			{
				id = "c0010",
				design = "ready",
				doc = "",
				deps = {},
				files = files,
				specs = {},
				approval = nil,
				approvalFile = "",
			},
			{
				id = "c0011",
				design = "ready",
				doc = "",
				deps = {},
				files = other,
				specs = {},
				approval = nil,
				approvalFile = "",
			},
		}
		local record = raftplan.renderGrouped({
			c0010 = raftplan.recordHash("c0010", files),
			c0011 = raftplan.recordHash("c0011", other),
		})
		local refused = readycheck.record("R0010", record, members, {})
		t.expect(has(refused, "coherence review")).toBe(true)
		-- one member needs none
		local one = raftplan.renderGrouped({ c0010 = raftplan.recordHash("c0010", files) })
		t.expect(readycheck.record("R0011", one, { members[1] }, {})).toBe(nil)
	end)
end)
