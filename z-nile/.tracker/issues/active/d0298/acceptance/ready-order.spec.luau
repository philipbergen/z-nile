--!strict
-- d0298 (E3): `ready` judges a raft's `grouped:` record before its members' approvals, so a member redesigned since
-- z-raft grouped it is named with both record hashes (what z-raft must redo), even though its approval no longer
-- holds either; a member whose record holds and whose approval does not is still refused for the approval; and a raft
-- whose record and approvals all hold is readied. Fixture under .cache/d0298-order (tests/lib/trackerfix).
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local PREPARING = "preparing-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local TRACKER = "pickman/.tracker"

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: s-{id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-12\nsize: 100\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Design\nPlain.\n`
end
local function raftDoc(id: string, slug: string, issues: string, grouped: string, status: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-12\ngrouped: {grouped}\nstatus: {status or PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`
end

local f: trackerfix.Fixture

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end
-- a member's record as z-raft takes it: its committed design files (approval.md is not one of them)
local function record(id: string): string
	local dir = `{f.main}/{TRACKER}/issues/{id}`
	if not fs.isDir(dir) then
		dir = `{f.main}/{TRACKER}/issues/done/{id}`
	end
	return raftplan.recordHash(
		id,
		{ [`{id}.md`] = fs.readFile(`{dir}/{id}.md`), ["check.sh"] = fs.readFile(`{dir}/check.sh`) }
	)
end
local function onOrigin(path: string): boolean
	fixture.git(f.main, { "fetch", "-q", "origin" })
	return fixture.exec(f.main, "git", { "cat-file", "-e", `origin/main:{path}` }).ok
end

return t.spec("d0298 ready judges the grouped record before the approvals", function(it)
	it("sets up three grouped rafts: one redesigned member, one stale approval, one that holds", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			[`{TRACKER}/architecture.md`] = "# Architecture\n",
			["z-nile/next"] = "issue 900 quiet-copper-falcon\nraft 900 quiet-copper-falcon\n",
			[`{TRACKER}/issues/c0510/c0510.md`] = issue("c0510", "R0500"),
			[`{TRACKER}/issues/c0520/c0520.md`] = issue("c0520", "R0500"),
			[`{TRACKER}/issues/c0610/c0610.md`] = issue("c0610", "R0600"),
			[`{TRACKER}/issues/c0710/c0710.md`] = issue("c0710", "R0700"),
			[`{TRACKER}/issues/c0810/c0810.md`] = issue("c0810", "R0800"),
			[`{TRACKER}/issues/done/c0910/c0910.md`] = issue("c0910", "R0900"),
		}
		for _, id in { "c0510", "c0520", "c0610", "c0710", "c0810" } do
			seed[`{TRACKER}/issues/{id}/check.sh`] = CHECK
		end
		seed[`{TRACKER}/issues/done/c0910/check.sh`] = CHECK
		f = trackerfix.new("d0298-order", seed)
		-- z-raft groups them from what landed (the seed, with its approvals)
		local g5 = raftplan.renderGrouped({ c0510 = record("c0510"), c0520 = record("c0520") })
		local g6 = raftplan.renderGrouped({ c0610 = record("c0610") })
		local g7 = raftplan.renderGrouped({ c0710 = record("c0710") })
		local g8 = raftplan.renderGrouped({ c0810 = record("c0810") })
		local g9 = raftplan.renderGrouped({ c0910 = record("c0910") })
		trackerfix.elsewhere(f, {
			[`{TRACKER}/rafts/R0500/R0500.md`] = raftDoc("R0500", "redesigned", "c0510, c0520", g5),
			[`{TRACKER}/rafts/R0500/design-review-001.md`] = `# Review 001\n\nGrouped: {g5}\n\nVerdict: approve\n`,
			[`{TRACKER}/rafts/R0500/check.sh`] = CHECK,
			[`{TRACKER}/rafts/R0600/R0600.md`] = raftDoc("R0600", "approval", "c0610", g6),
			[`{TRACKER}/rafts/R0600/check.sh`] = CHECK,
			[`{TRACKER}/rafts/R0700/R0700.md`] = raftDoc("R0700", "holds", "c0710", g7),
			[`{TRACKER}/rafts/R0700/check.sh`] = CHECK,
			-- a raft still being rafted (not prepared) and a raft that is done, each with a member redesigned since
			[`{TRACKER}/rafts/R0800/R0800.md`] = raftDoc("R0800", "rafting", "c0810", g8, PREPARING),
			[`{TRACKER}/rafts/R0800/check.sh`] = CHECK,
			[`{TRACKER}/rafts/done/R0900/R0900.md`] = raftDoc("R0900", "finished", "c0910", g9, "done"),
			[`{TRACKER}/rafts/done/R0900/check.sh`] = CHECK,
		}, "tracker: rafts")
		-- c0510 is redesigned after grouping (record and approval both change); c0610's approval alone goes stale
		local doc = fs.readFile(`{f.main}/{TRACKER}/issues/c0510/c0510.md`)
		local doc8 = fs.readFile(`{f.main}/{TRACKER}/issues/c0810/c0810.md`)
		local doc9 = fs.readFile(`{f.main}/{TRACKER}/issues/done/c0910/c0910.md`)
		local zero = string.rep("0", 64)
		trackerfix.elsewhere(f, {
			[`{TRACKER}/issues/c0510/c0510.md`] = (
				string.gsub(doc, "Plain%.", "REDESIGNED: a new interface.", 1)
			),
			[`{TRACKER}/issues/c0810/c0810.md`] = (
				string.gsub(doc8, "Plain%.", "REDESIGNED: a new interface.", 1)
			),
			[`{TRACKER}/issues/done/c0910/c0910.md`] = (
				string.gsub(doc9, "Plain%.", "REDESIGNED: a new interface.", 1)
			),
			[`{TRACKER}/issues/c0610/approval.md`] = contract.render({
				{
					when = "2026-11-01T00:00:00Z",
					who = "someone",
					hash = zero,
					parts = { design = zero, ["check.sh"] = zero },
				},
			}),
		}, "tracker: c0510 redesigned, c0610 approved an older contract")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
	end)

	it(
		"a member redesigned since grouping is named with both record hashes, ahead of its stale approval",
		function()
			local r = trackerfix.tr(f, f.main, { "ready", "R0500" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "changed on origin/main since")).toBe(true)
			t.expect(string.match(r.stderr, "c0510 %(%x+ → %x+%)") ~= nil).toBe(true)
			t.expect(has(r.stderr, "contract changed since approval")).toBe(false)
			t.expect(onOrigin(`{TRACKER}/rafts/active/R0500/R0500.md`)).toBe(false)
		end
	)

	it("a raft that is not a prepared backlog raft is refused as today, not for its record", function()
		for _, id in { "R0800", "R0900" } do
			local r = trackerfix.tr(f, f.main, { "ready", id })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "only a prepared raft is readied")).toBe(true)
			t.expect(has(r.stderr, "changed on origin/main since")).toBe(false)
		end
	end)

	it("work next names a redesigned member by its record, ahead of its stale approval", function()
		local r = trackerfix.tr(f, f.main, { "work", "next", "R0500" })
		local say = r.stdout .. r.stderr
		t.expect(string.match(say, "c0510 %(%x+ → %x+%)") ~= nil).toBe(true)
		t.expect(has(say, "changed since approval")).toBe(false)
	end)

	it("a member whose record holds and whose approval does not is refused for the approval", function()
		local r = trackerfix.tr(f, f.main, { "ready", "R0600" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0610's contract changed since approval")).toBe(true)
		t.expect(onOrigin(`{TRACKER}/rafts/active/R0600/R0600.md`)).toBe(false)
	end)

	it("a raft whose record and approvals hold is readied", function()
		trackerfix.trOk(f, f.main, { "ready", "R0700" })
		t.expect(onOrigin(`{TRACKER}/rafts/active/R0700/R0700.md`)).toBe(true)
	end)
end)
