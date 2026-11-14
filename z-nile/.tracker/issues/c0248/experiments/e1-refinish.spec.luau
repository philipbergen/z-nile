--!strict
-- c0248 E1: a review file committed in the issue folder after a finish keeps the layer finished; a re-finish squashes
-- it into the finish commit and the newest review is still readable from the tip tree (the layer is then complete only
-- once a review names the new finish commit). One experiment, run on the prototype; not promoted.
-- Fixture: .cache/c0248-e1.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local DOC =
	"---\nid: c0010\ntype: chore\ntitle: one\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# c0010\n\n## Problem\nA.\n\n## Solution\nB.\n\n## Acceptance criteria\n- AC1: ok\n"
local RAFT =
	"---\nid: R0010\ntype: chore\ntitle: one\nslug: one\nsingle: true\nissues: [c0010]\ndesign: ready\ncreated: 2026-10-06\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n\n## Order & dependencies\nc0010\n"

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

return t.spec("c0248 E1: a review after finish, and a re-finish", function(it)
	it(
		"keeps the layer finished, squashes into a re-finish, and reads the newest review from the tip",
		function()
			local f = trackerfix.new("c0248-e1", {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/.tracker/rafts/R0010/R0010.md"] = RAFT,
				["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0010/c0010.md"] = DOC,
				["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
			})
			local function zn(dir: string, args: { string }): string
				local r = trackerfix.tr(f, dir, args)
				if not r.ok then
					error(`./zn {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
				end
				return (string.gsub(r.stdout, "%s+$", ""))
			end
			trackerfix.trOk(f, f.main, { "ready", "R0010" })
			local wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
			local function git(args: { string }): string
				return fixture.git(wt, args)
			end
			zn(wt, { "start", "R0010" })
			fs.writeDir(`{wt}/pickman/src`)
			fs.writeFile(`{wt}/pickman/src/a.luau`, "return 1\n")
			git({ "add", "-A" })
			git({ "commit", "-qm", "work" })
			zn(wt, { "finish", "c0010" })
			local finish1 = git({ "rev-parse", "HEAD" })
			local review = `{wt}/pickman/.tracker/issues/active/c0010/review-001.md`
			fs.writeFile(review, `# Review 001\n\nCommit: {finish1}\nVerdict: approve\n`)
			git({ "add", "-A" })
			git({ "commit", "-qm", "tracker: review c0010" })
			git({ "push", "-q" })
			t.expect(has(zn(wt, { "stack", "R0010" }), "c0010 complete")).toBe(true)
			-- more work, then a re-finish: the review commit is squashed into the new finish commit
			fs.writeFile(`{wt}/pickman/src/a.luau`, "return 2\n")
			git({ "add", "-A" })
			git({ "commit", "-qm", "fix" })
			git({ "push", "-q" })
			t.expect(has(zn(wt, { "stack", "R0010" }), "c0010 claimed")).toBe(true)
			zn(wt, { "finish", "c0010" })
			local finish2 = git({ "rev-parse", "HEAD" })
			t.expect(finish2 ~= finish1).toBe(true)
			t.expect(git({ "rev-list", "--count", "origin/main..HEAD" })).toBe("1")
			-- the review file survives in the tip tree and is readable, but names the old commit: finished, not complete
			t.expect(has(git({ "show", "HEAD:pickman/.tracker/issues/active/c0010/review-001.md" }), finish1))
				.toBe(true)
			t.expect(has(zn(wt, { "stack", "R0010" }), "c0010 finished")).toBe(true)
			fs.writeFile(review, `# Review 001\n\nCommit: {finish2}\nVerdict: approve\n`)
			git({ "add", "-A" })
			git({ "commit", "-qm", "tracker: review c0010" })
			git({ "push", "-q" })
			t.expect(has(zn(wt, { "stack", "R0010" }), "c0010 complete")).toBe(true)
		end
	)
end)
