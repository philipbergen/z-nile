--!strict
-- c0261: `./zn spend <R-id> --phase design-review --note design-review-NNN` spreads the row over the raft's members under
-- the subject "<R-id>: design-review-NNN", so a member's own design-review-NNN row cannot stand in for the raft's round
-- (finalround.luau); any other phase keeps the note as written. Fixture under .cache/c0261-final-round-raft
-- (tests/lib/trackerfix): a prepared raft R0010 of c0011 and c0012.
local spend = require("@znile/engine/spend")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local function issue(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 200\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local RAFT =
	`---\nid: R0010\ntype: chore\ntitle: R0010\nslug: r0010\nsingle: false\nissues: [c0011, c0012]\ndesign: ready\ncreated: 2026-10-20\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`

return t.spec("c0261 a raft's design round is recorded under its own subject", function(it)
	it(
		'spend <R-id> writes "<R-id>: design-review-NNN" into each member, and only for the design-review phase',
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
				["pickman/.tracker/rafts/R0010/R0010.md"] = RAFT,
				["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0011/c0011.md"] = issue("c0011"),
				["pickman/.tracker/issues/c0011/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0012/c0012.md"] = issue("c0012"),
				["pickman/.tracker/issues/c0012/check.sh"] = CHECK,
			}
			local f = trackerfix.new("c0261-final-round-raft", seed)
			local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-raft" })
			trackerfix.trOk(f, wt, { "sync" })
			trackerfix.trOk(f, wt, {
				"spend",
				"R0010",
				"--phase",
				"design-review",
				"--model",
				"claude-opus-5-5",
				"--note",
				"design-review-001",
			})
			trackerfix.trOk(f, wt, { "spend", "R0010", "--phase", "prep", "--note", "raft prep" })
			for _, id in { "c0011", "c0012" } do
				local design, prep
				for _, r in spend.rowsIn(`{wt}/pickman/.tracker/issues/{id}`) do
					if r.phase == "design-review" then
						design = r
					elseif r.phase == "prep" then
						prep = r
					end
				end
				t.expect(design.subject).toBe("R0010: design-review-001")
				t.expect(design.model).toBe("claude-opus-5-5")
				t.expect(prep.subject).toBe("raft prep") -- another phase keeps its note as written
			end
			-- an issue's own round keeps the plain subject
			trackerfix.trOk(f, wt, {
				"spend",
				"c0011",
				"--phase",
				"design-review",
				"--note",
				"design-review-001",
			})
			local own = spend.rowsIn(`{wt}/pickman/.tracker/issues/c0011`)
			t.expect(own[#own].subject).toBe("design-review-001")
		end
	)
end)
