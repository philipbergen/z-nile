--!strict
-- c0116 AC10 (review 003 F4): `compact` and `renumber` rewrite ids in member documents, which changes their record
-- hash. Both re-record every `grouped:` entry that matched before the rewrite, in the raft's document and in the
-- `Grouped:` line its coherence review quotes, so `ready` still takes a raft nothing redesigned; an entry that did not
-- match before still refuses. Fixture under .cache/c0116-compact (tests/lib/trackerfix): renumber, land, compact,
-- land, then ready.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string, mention: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: s-{id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 100\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Design\nSee {mention or id}.\n`
end
local function raftDoc(id: string, slug: string, issues: string, grouped: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-20\ngrouped: {grouped}\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`
end
-- the record of a seeded member: its document and check.sh, as recordHash reads a folder
local function record(id: string, text: string): string
	return raftplan.recordHash(id, { [`{id}.md`] = text, ["check.sh"] = CHECK })
end

local f: trackerfix.Fixture
local W, X = "", ""

local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function land(wt: string)
	fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
	fixture.git(f.main, { "pull", "-q", "origin", "main" })
end
-- the raft whose document has this slug, after the ids changed
local function raftBySlug(slug: string): string
	for _, state in { "", "active/" } do
		local base = `{f.main}/tracker/rafts/{state}`
		for _, name in fs.readDir(base) do
			local doc = `{base}{name}/{name}.md`
			if
				string.match(name, "^R%d+$")
				and fs.isFile(doc)
				and string.find(fs.readFile(doc), `\nslug: {slug}\n`, 1, true)
			then
				return name
			end
		end
	end
	error(`no raft with slug {slug}`)
end

return t.spec("c0116 compact and renumber keep a grouped raft's record", function(it)
	it("sets up landed grouped rafts, one whose record no longer matches", function()
		local a, b = issue("c0510", "R0500", "c0520"), issue("c0520", "R0500")
		local c, d = issue("c0710", "R0700"), issue("c0720", "R0700", "c0710")
		local e = issue("c0610", "R0600")
		local w1, w2 = issue("c0951", "R0950"), issue("c0952", "R0950", "c0951")
		local g9 = raftplan.renderGrouped({ c0951 = record("c0951", w1), c0952 = record("c0952", w2) })
		local g5 = raftplan.renderGrouped({ c0510 = record("c0510", a), c0520 = record("c0520", b) })
		local g7 = raftplan.renderGrouped({ c0710 = record("c0710", c), c0720 = record("c0720", d) })
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(".gitignore"),
			["tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 900 quiet-copper-falcon\nraft 900 quiet-copper-falcon\n",
			["tracker/issues/c0510/c0510.md"] = a,
			["tracker/issues/c0520/c0520.md"] = b,
			["tracker/rafts/R0500/R0500.md"] = raftDoc("R0500", "kept", "c0510, c0520", g5),
			["tracker/rafts/R0500/design-review-001.md"] = `# Review 001\n\nGrouped: {g5}\n\nVerdict: approve\n`,
			["tracker/issues/c0710/c0710.md"] = c,
			["tracker/issues/c0720/c0720.md"] = d,
			["tracker/rafts/R0700/R0700.md"] = raftDoc("R0700", "renamed", "c0710, c0720", g7),
			["tracker/rafts/R0700/design-review-001.md"] = `# Review 001\n\nGrouped: {g7}\n\nVerdict: approve\n`,
			["tracker/issues/c0610/c0610.md"] = e,
			-- review 005 F1: renumbered while an untracked work file sits in a member's folder
			["tracker/issues/c0951/c0951.md"] = w1,
			["tracker/issues/c0952/c0952.md"] = w2,
			["tracker/rafts/R0950/R0950.md"] = raftDoc("R0950", "wip", "c0951, c0952", g9),
			["tracker/rafts/R0950/design-review-001.md"] = `# Review 001\n\nGrouped: {g9}\n\nVerdict: approve\n`,
			-- prepared and raftless: rafted while the compaction lands (review 004 F2)
			["tracker/issues/c0810/c0810.md"] = issue("c0810", ""),
			["tracker/issues/c0820/c0820.md"] = issue("c0820", "", "c0810"),
			-- a record that already did not match: a rewrite must not make it match
			["tracker/rafts/R0600/R0600.md"] = raftDoc("R0600", "stale", "c0610", "[c0610@000000000000]"),
		}
		for _, p in
			{
				"tracker/issues/c0510",
				"tracker/issues/c0520",
				"tracker/issues/c0710",
				"tracker/issues/c0720",
				"tracker/issues/c0610",
				"tracker/issues/c0951",
				"tracker/issues/c0952",
				"tracker/rafts/R0950",
				"tracker/issues/c0810",
				"tracker/issues/c0820",
				"tracker/rafts/R0500",
				"tracker/rafts/R0700",
				"tracker/rafts/R0600",
			}
		do
			seed[`{p}/check.sh`] = CHECK
		end
		f = trackerfix.new("c0116-compact", seed)
		W = trOk(f.main, { "worktree", "ids" })
		X = trOk(f.main, { "worktree", "raft-open" })
	end)

	it("renumber of a member re-records its raft, and the review's quote with it", function()
		trOk(W, { "renumber", "c0710", "c0790" })
		local doc = fs.readFile(`{W}/tracker/rafts/R0700/R0700.md`)
		local map = raftplan.parseGrouped(string.match(doc, "\ngrouped: ([^\n]*)\n"))
		t.expect(map.c0710).toBe(nil)
		local member = fs.readFile(`{W}/tracker/issues/c0790/c0790.md`)
		t.expect(map.c0790)
			.toBe(raftplan.recordHash("c0790", { ["c0790.md"] = member, ["check.sh"] = CHECK }))
		t.expect(
			string.find(
				fs.readFile(`{W}/tracker/rafts/R0700/design-review-001.md`),
				`c0790@{map.c0790}`,
				1,
				true
			) ~= nil
		).toBe(true)
		fixture.git(W, { "add", "-A" })
		fixture.git(W, { "commit", "-q", "-m", "renumber c0710" })
		land(W)
	end)

	it(
		"renumber with an untracked work file in a member's folder keeps the record (review 005 F1)",
		function()
			fixture.git(W, { "fetch", "-q", "origin" })
			fixture.git(W, { "reset", "-q", "--hard", "origin/main" })
			fs.writeDir(`{W}/tracker/issues/c0952/acceptance`)
			fs.writeFile(`{W}/tracker/issues/c0952/acceptance/wip.spec.luau`, "--!strict\nreturn nil\n")
			trOk(W, { "renumber", "c0952", "c0958" })
			-- the work file is not committed: the rename alone lands
			-- the work folder was never tracked (c0952 had no acceptance specs): remove it whole
			if fs.isDir(`{W}/tracker/issues/c0958/acceptance`) then
				fs.removeDir(`{W}/tracker/issues/c0958/acceptance`)
			end
			fixture.git(W, { "add", "-A" })
			fixture.git(W, { "commit", "-q", "-m", "renumber c0952" })
			land(W)
			trOk(f.main, { "ready", "R0950" })
		end
	)

	it(
		"after compact, ready takes the rafts nothing redesigned and still refuses the stale record",
		function()
			fixture.git(W, { "fetch", "-q", "origin" })
			fixture.git(W, { "reset", "-q", "--hard", "origin/main" })
			-- a rafting is open while the compaction lands; and an ignored file sits in a member's folder (review 004 F1)
			local RO =
				string.match(trOk(X, { "new", "raft", "chore", "open", "c0810", "c0820" }), "(R%d+)") :: string
			local doc = `{X}/tracker/rafts/{RO}/{RO}.md`
			local text = fs.readFile(doc)
			text = (string.gsub(text, "design: draft", "design: ready", 1))
			text = (string.gsub(text, "## Theme\n<!%-%-.-%-%->", "## Theme\nTwo chores.", 1))
			text = (
				string.gsub(
					text,
					"## Order & dependencies\n<!%-%-.-%-%->",
					"## Order & dependencies\nBy id.",
					1
				)
			)
			fs.writeFile(doc, text)
			local grouped = string.match(text, "\ngrouped: ([^\n]*)\n") :: string
			fs.writeFile(
				`{X}/tracker/rafts/{RO}/design-review-001.md`,
				`# Review 001\n\nGrouped: {grouped}\n\nVerdict: approve\n`
			)
			fixture.git(X, { "add", "-A" })
			fixture.git(X, { "commit", "-q", "-m", "tracker: raft (open)" })
			fixture.git(W, { "fetch", "-q", "origin" })
			fixture.git(W, { "reset", "-q", "--hard", "origin/main" })
			fs.writeDir(`{W}/tracker/issues/c0510/acceptance`)
			fs.writeFile(`{W}/tracker/issues/c0510/acceptance/.DS_Store`, "finder")
			trOk(W, { "compact", "--force" })
			land(W)
			local kept, renamed, stale = raftBySlug("kept"), raftBySlug("renamed"), raftBySlug("stale")
			t.expect(kept ~= "R0500").toBe(true) -- the ids really changed
			trOk(f.main, { "ready", kept })
			trOk(f.main, { "ready", renamed })
			local r = trackerfix.tr(f, f.main, { "ready", stale })
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr, "changed on origin/main since", 1, true) ~= nil).toBe(true)
		end
	)

	it(
		"remap re-records an open rafting's record and its review, so it prepares, lands and readies",
		function()
			trOk(X, { "remap" })
			local open = nil :: string?
			for _, name in fs.readDir(`{X}/tracker/rafts`) do
				local d = `{X}/tracker/rafts/{name}/{name}.md`
				if
					string.match(name, "^R%d+$")
					and fs.isFile(d)
					and string.find(fs.readFile(d), "\nslug: open\n", 1, true)
				then
					open = name
				end
			end
			local RO = open :: string
			trOk(X, { "status", RO, "prepared" })
			fixture.git(X, { "add", "-A" })
			fixture.git(X, { "commit", "-q", "-m", "tracker: raft (open, prepared)" })
			fixture.git(X, { "fetch", "-q", "origin" })
			fixture.git(X, { "merge", "-q", "--no-edit", "origin/main" })
			land(X)
			trOk(f.main, { "ready", RO })
		end
	)
end)
