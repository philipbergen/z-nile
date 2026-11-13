--!strict
-- d0298 (E2): an id rewrite (`renumber`, `compact`) rewrites ids inside a member's design sections, which changes its
-- approval contract. An approval whose last row held before the rewrite, judged from the files git tracks, is
-- re-recorded in place after it (the same row: same when and who, the new hash and parts; no new row); one that did
-- not hold is left as it was. Fixture under .cache/d0298-carry (tests/lib/trackerfix): one landed seed, a renumber in
-- one worktree, a compaction in another.
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES = "pickman/.tracker/issues"

-- slugs carry no id, so a compaction leaves them as they are and the spec finds each issue by its slug; a done issue
-- (c0550) reads its acceptance specs from the promoted folder, pickman/tests/acceptance/<id>; c0560 and c0550 keep a
-- spec one folder down; c0510 has two approval rows (a re-approval) and c0580 an older row that matches and a last one
-- that does not
local function issue(id: string, slug: string, design: string, status: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-12\nsize: 100\nstatus: {status or PREPARED}\n---\n\n# {id}\n\n## Design\n{design}\n`
end

local f: trackerfix.Fixture
local W, C = "", ""

local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end
local function rows(path: string): { contract.Row }
	local parsed, err = contract.parse(fs.readFile(path))
	if not parsed then
		error(`{path}: {err}`)
	end
	return parsed
end
-- the id of the issue (in checkout `wt`, backlog or done/) whose document has this slug, and its folder
local function bySlug(wt: string, slug: string): (string, string)
	for _, state in { "", "done/" } do
		for _, name in fs.readDir(`{wt}/{ISSUES}/{state}`) do
			local doc = `{wt}/{ISSUES}/{state}{name}/{name}.md`
			if
				fs.isDir(`{wt}/{ISSUES}/{state}{name}`)
				and fs.isFile(doc)
				and has(fs.readFile(doc), `\nslug: {slug}\n`)
			then
				return name, `{wt}/{ISSUES}/{state}{name}`
			end
		end
	end
	error(`no issue with slug {slug}`)
end

return t.spec("d0298 an id rewrite carries every approval that held", function(it)
	it("sets up approved issues that name each other, and one approval that no longer holds", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 900 quiet-copper-falcon\nraft 900 quiet-copper-falcon\n",
			[`{ISSUES}/c0510/c0510.md`] = issue("c0510", "alpha", "See c0520."),
			[`{ISSUES}/c0520/c0520.md`] = issue("c0520", "beta", "Alone."),
			[`{ISSUES}/c0530/c0530.md`] = issue("c0530", "gamma", "See c0520."),
			[`{ISSUES}/c0540/c0540.md`] = issue("c0540", "delta", "See c0520."),
			[`{ISSUES}/c0540/acceptance/a.spec.luau`] = "--!strict\n-- pins c0520\nreturn nil\n",
			[`{ISSUES}/done/c0550/c0550.md`] = issue("c0550", "epsilon", "See c0520.", "done"),
			[`{ISSUES}/done/c0550/check.sh`] = CHECK,
			["pickman/tests/acceptance/c0550/sub/p.spec.luau"] = "--!strict\n-- pins c0520\nreturn nil\n",
			[`{ISSUES}/c0560/c0560.md`] = issue("c0560", "eta", "See c0520."),
			[`{ISSUES}/c0560/acceptance/sub/n.spec.luau`] = "--!strict\n-- pins c0520\nreturn nil\n",
			[`{ISSUES}/c0580/c0580.md`] = issue("c0580", "zeta", "See c0520."),
		}
		for _, id in { "c0510", "c0520", "c0530", "c0540", "c0560", "c0580" } do
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		-- the seed seals only live issues: the done one's approval is written here, over its promoted spec
		local parts = contract.build(
			seed[`{ISSUES}/done/c0550/c0550.md`],
			CHECK,
			{ ["sub/p.spec.luau"] = seed["pickman/tests/acceptance/c0550/sub/p.spec.luau"] }
		) :: contract.Parts
		seed[`{ISSUES}/done/c0550/approval.md`] = contract.render({
			{
				when = "2026-11-12T00:00:00Z",
				who = "seed",
				hash = contract.hash(parts),
				parts = contract.partHashes(parts),
			},
		})
		f = trackerfix.new("d0298-carry", seed)
		for _, dir in { "c0510", "c0520", "c0530", "c0540", "done/c0550", "c0560", "c0580" } do
			t.expect(fs.isFile(`{f.main}/{ISSUES}/{dir}/approval.md`)).toBe(true)
		end
		-- the done issue's approval covers its promoted spec
		t.expect(has(fs.readFile(`{f.main}/{ISSUES}/done/c0550/approval.md`), "sub/p.spec.luau=")).toBe(true)
		-- c0530's design changes after its approval, so its approval no longer holds before any rewrite; c0510 was
		-- approved once before (an older row), and c0580's last row approves another contract (only its first matches)
		local doc = fs.readFile(`{f.main}/{ISSUES}/c0530/c0530.md`)
		local zero = string.rep("0", 64)
		local function other(when: string, who: string): contract.Row
			return { when = when, who = who, hash = zero, parts = { design = zero, ["check.sh"] = zero } }
		end
		local sealed510 = rows(`{f.main}/{ISSUES}/c0510/approval.md`)[1]
		local sealed580 = rows(`{f.main}/{ISSUES}/c0580/approval.md`)[1]
		trackerfix.elsewhere(f, {
			[`{ISSUES}/c0530/c0530.md`] = (
				string.gsub(doc, "See c0520%.", "See c0520. Edited after approval.", 1)
			),
			[`{ISSUES}/c0510/approval.md`] = contract.render({
				other("2026-10-01T00:00:00Z", "earlier"),
				sealed510,
			}),
			[`{ISSUES}/c0580/approval.md`] = contract.render({
				sealed580,
				other("2026-11-12T01:00:00Z", "later"),
			}),
		}, "c0530 edited after its approval; c0510 re-approved; c0580 approved another contract")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		W = trOk(f.main, { "worktree", "ids" })
		C = trOk(f.main, { "worktree", "compaction" })
		for _, wt in { W, C } do
			fixture.git(wt, { "fetch", "-q", "origin" })
			fixture.git(wt, { "reset", "-q", "--hard", "origin/main" })
		end
		t.expect(trackerfix.tr(f, W, { "approve", "c0530", "--check" }).ok).toBe(false)
		t.expect(trackerfix.tr(f, W, { "approve", "c0580", "--check" }).ok).toBe(false)
		trOk(W, { "approve", "c0510", "--check" })
	end)

	it(
		"approve reads a spec one folder down, in an issue's acceptance/ and in its promoted folder",
		function()
			for _, case in
				{
					{
						id = "c0560",
						path = `{ISSUES}/c0560/acceptance/sub/n.spec.luau`,
						name = "sub/n.spec.luau",
					},
					{
						id = "c0550",
						path = "pickman/tests/acceptance/c0550/sub/p.spec.luau",
						name = "sub/p.spec.luau",
					},
				}
			do
				trOk(W, { "approve", case.id, "--check" })
				fs.writeFile(`{W}/{case.path}`, fs.readFile(`{W}/{case.path}`) .. "-- edited\n")
				local r = trackerfix.tr(f, W, { "approve", case.id, "--check" })
				fixture.git(W, { "checkout", "-q", "--", case.path })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr, case.name)).toBe(true)
			end
		end
	)

	it("renumber re-records each approval that held as the same row, from what git tracks", function()
		local before = rows(`{W}/{ISSUES}/c0510/approval.md`)
		local stale = fs.readFile(`{W}/{ISSUES}/c0530/approval.md`)
		local other = fs.readFile(`{W}/{ISSUES}/c0580/approval.md`)
		-- an untracked work file in an approved issue's folder is not what the rewrite commits, so it does not decide
		fs.writeDir(`{W}/{ISSUES}/c0510/acceptance`)
		fs.writeFile(`{W}/{ISSUES}/c0510/acceptance/wip.spec.luau`, "--!strict\nreturn nil\n")
		trOk(W, { "renumber", "c0520", "c0590" })
		fs.removeDir(`{W}/{ISSUES}/c0510/acceptance`)
		t.expect(has(fs.readFile(`{W}/{ISSUES}/c0510/c0510.md`), "See c0590.")).toBe(true) -- the design changed
		for _, id in { "c0510", "c0590", "c0540", "c0550", "c0560" } do
			trOk(W, { "approve", id, "--check" })
		end
		local after = rows(`{W}/{ISSUES}/c0510/approval.md`)
		t.expect(#after).toBe(2) -- re-recorded, not re-approved, and the older row kept
		t.expect(contract.render({ after[1] })).toBe(contract.render({ before[1] }))
		t.expect(after[#after].when).toBe(before[#before].when)
		t.expect(after[#after].who).toBe(before[#before].who)
		t.expect(after[#after].hash ~= before[#before].hash).toBe(true)
		-- an approval that did not hold before the rewrite is left as it was, and still does not hold
		t.expect(fs.readFile(`{W}/{ISSUES}/c0530/approval.md`)).toBe(stale)
		t.expect(fs.readFile(`{W}/{ISSUES}/c0580/approval.md`)).toBe(other) -- held by its first row only: not carried
		local r = trackerfix.tr(f, W, { "approve", "c0530", "--check" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "contract changed since approval")).toBe(true)
	end)

	it("compact re-records them inside its own commit", function()
		trOk(C, { "compact", "--force" })
		t.expect(fixture.git(C, { "status", "--porcelain" })).toBe("")
		local alpha = bySlug(C, "alpha")
		t.expect(alpha ~= "c0510").toBe(true) -- the ids really changed
		for _, slug in { "alpha", "beta", "delta", "epsilon", "eta" } do
			trOk(C, { "approve", (bySlug(C, slug)), "--check" })
		end
		local before = rows(`{f.main}/{ISSUES}/c0510/approval.md`)
		local after = rows(`{C}/{ISSUES}/{alpha}/approval.md`)
		t.expect(#after).toBe(2)
		t.expect(contract.render({ after[1] })).toBe(contract.render({ before[1] }))
		t.expect(after[2].when).toBe(before[2].when)
		t.expect(after[2].who).toBe(before[2].who)
		for _, slug in { "gamma", "zeta" } do
			local r = trackerfix.tr(f, C, { "approve", (bySlug(C, slug)), "--check" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "contract changed since approval")).toBe(true)
		end
	end)
end)
