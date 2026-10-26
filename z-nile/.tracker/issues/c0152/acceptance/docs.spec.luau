--!strict
-- c0152 AC2: zz-rules' Merging step 4 states the exception through `./zn merge-check`, and the commands table, the main
-- checkout's list and the usage name it, each with both rules and the trial (design review 002 F4).
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0152 the merging rule names merge-check", function(it)
	it("zz-rules states the exception, lists the command and keeps the old path", function()
		local zr = fs.readFile(`{TOP}/z-nile/skills/zz-rules/SKILL.md`)
		local merging = string.match(zr, "\n## Merging\n(.-)\n## ") or ""
		t.expect(has(merging, "If `main` moved since, first run `./zn merge-check <the green head>`")).toBe(true)
		t.expect(has(merging, "merge without another cycle")).toBe(true)
		t.expect(has(merging, "--match-head-commit <the sha it prints>")).toBe(true)
		-- both rules and the trial, in step 4 and in the table row (design review 002 F4)
		t.expect(has(merging, "edits no existing item's `check.sh` and touches no file this PR changes")).toBe(true)
		t.expect(
			has(merging, "as its own repository in a fresh folder under `$TMPDIR` (never a worktree of this checkout)")
		)
			.toBe(true)
		t.expect(has(merging, "`z-nile/tests/merge-stages.txt`")).toBe(true)
		t.expect(has(merging, "merge `origin/main` in with plain `git`")).toBe(true) -- the old path still holds
		local row = string.match(zr, "\n(| merge%-check | [^\n]*)") or ""
		t.expect(has(row, "| merge-check | `./zn merge-check [<head>]` | writes only under `$TMPDIR`.")).toBe(true)
		t.expect(has(row, "edits no existing item's `check.sh`")).toBe(true)
		t.expect(
			has(row, "the run lines of `z-nile/tests/merge-stages.txt`")
				or has(row, "the `run` lines of `z-nile/tests/merge-stages.txt`")
		).toBe(true)
		t.expect(
			has(
				zr,
				"`merge-check` (it writes only under `$TMPDIR`, its trial merge, removed before it answers), `lessons`, `raft-plan` (without `--apply`)"
			)
		).toBe(true)
	end)

	it("the usage lists it", function()
		local usage = process.exec("bash", { `{TOP}/zn` })
		t.expect(has(usage.stdout, "merge-check [<head>]")).toBe(true)
	end)
end)
