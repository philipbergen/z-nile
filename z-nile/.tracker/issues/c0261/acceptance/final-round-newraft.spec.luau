--!strict
-- c0261 (design review 006 F1): a NEW raft of several issues is prepared when its raft review's row, recorded from the
-- author's worktree (where the members' `raft:` lines already are), is on a final-review model. `status <R-id> prepared`
-- refuses a Sonnet round, accepts a new Opus id, and a member's own Opus design-review-001 does not stand in. Fixture
-- under .cache/c0261-final-round-newraft (tests/lib/trackerfix): prepared c0011 and c0012, a root .models.toml.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local MODELS =
	'order = ["claude"]\n[zz-review.claude]\nmodel = "claude-opus-5-5"\nrank = 4\nruntime = "claude-cli"\nmax_tokens = 9\n'
local function issue(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 200\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0261 a new raft's review row is found by status prepared", function(it)
	it(
		"refuses a Sonnet raft round, accepts a new Opus id, and ignores a member's own round of the same number",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
				[".models.toml"] = MODELS,
				["pickman/.tracker/issues/c0011/c0011.md"] = issue("c0011"),
				["pickman/.tracker/issues/c0011/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0012/c0012.md"] = issue("c0012"),
				["pickman/.tracker/issues/c0012/check.sh"] = CHECK,
			}
			local f = trackerfix.new("c0261-final-round-newraft", seed)
			local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-raft" })
			trackerfix.trOk(f, wt, { "sync" })
			local out = trackerfix.trOk(
				f,
				wt,
				{ "new", "raft", "chore", "pair", "c0011", "c0012", "--project", "pickman" }
			)
			local rid = string.match(out, "(R%d+)") :: string
			local dir = `{wt}/pickman/.tracker/rafts/{rid}`
			local doc = fs.readFile(`{dir}/{rid}.md`)
			doc = string.gsub(doc, "\ndesign: draft\n", "\ndesign: ready\n")
			doc = string.gsub(doc, "## Theme\n[^#]*", "## Theme\nA pair.\n\n")
			doc = string.gsub(doc, "## Order & dependencies\n[^#]*", "## Order & dependencies\nBy id.\n\n")
			fs.writeFile(`{dir}/{rid}.md`, doc)
			local grouped = string.match(doc, "\ngrouped: ([^\n]*)\n") or "[]"
			fs.writeFile(
				`{dir}/design-review-001.md`,
				`# Review 001\n\nGrouped: {grouped}\n\nVerdict: approve\n`
			)
			local function spend(id: string, model: string)
				trackerfix.trOk(f, wt, {
					"spend",
					id,
					"--phase",
					"design-review",
					"--time",
					"4",
					"--tokens",
					"50",
					"--model",
					model,
					"--note",
					"design-review-001",
				})
			end
			-- the member's own Opus round of the same number, and the raft's round on a Sonnet
			spend("c0011", "claude-opus-5-5")
			spend(rid, "claude-sonnet-5-5-high")
			local refused = trackerfix.tr(f, wt, { "status", rid, "prepared" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stdout .. refused.stderr, "model claude-sonnet-5-5-high")).toBe(true)
			t.expect(has(refused.stdout .. refused.stderr, "--mode raft --final")).toBe(true)
			-- the round re-run on a new Opus id and recorded under the raft's subject
			spend(rid, "claude-opus-6-1")
			local ok = trackerfix.tr(f, wt, { "status", rid, "prepared" })
			if not ok.ok then
				error(ok.stdout .. ok.stderr)
			end
		end
	)
end)
