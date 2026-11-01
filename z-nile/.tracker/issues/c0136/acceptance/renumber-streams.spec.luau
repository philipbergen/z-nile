--!strict
-- c0136 AC7: a stream review or refute names its issue (stream-review-<issue>-NNN.md) in its raft's folder, and a
-- harvest entry names the file. `renumber` (and `compact` and `remap`, which share compact.apply) rewrites the id in
-- the entry; the file moves with it, so the entry still resolves: `lessons --check` is ok and `--uncovered` is
-- silent afterwards, and a stream file of another issue stays as it was. Fixture under .cache/c0136-renumber
-- (tests/lib/trackerfix): a worktree of the fixture's own repository; nothing else is written.
local compact = require("@znile/engine/compact")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local ISSUE =
	`---\nid: c0510\ntype: chore\ntitle: c0510\nslug: s-c0510\nraft: R0500\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 100\nstatus: {PREPARED}\n---\n\n# c0510\n\n## Design\nSee c0510.\n`
local OTHER =
	`---\nid: c0520\ntype: chore\ntitle: c0520\nslug: s-c0520\nraft: R0500\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nsize: 100\nstatus: {PREPARED}\n---\n\n# c0520\n\n## Design\nSee c0520.\n`
local function record(id: string, text: string): string
	return raftplan.recordHash(id, { [`{id}.md`] = text, ["check.sh"] = CHECK })
end
local GROUPED = raftplan.renderGrouped({ c0510 = record("c0510", ISSUE), c0520 = record("c0520", OTHER) })
local RAFT =
	`---\nid: R0500\ntype: chore\ntitle: kept\nslug: kept\nsingle: false\nissues: [c0510, c0520]\ndesign: ready\ncreated: 2026-10-20\ngrouped: {GROUPED}\nstatus: {PREPARED}\n---\n\n# R0500\n\n## Theme\nSeeded.\n\n## Order & dependencies\nBy id.\n`

local function skill(name: string): string
	return `---\nname: {name}\ndescription: x\n---\n\n# {name}\n`
end
local function review(): string
	return "# Review 001\n\n### F1 [low] claim\nEvidence: x\nErred: zz-execute\nUpstream: none\n\nVerdict: changes\n"
end

local R = "pickman/.tracker/rafts/R0500"
local SEED: { [string]: string } = {
	[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
	["pickman/.tracker/architecture.md"] = "# Architecture\n",
	["z-nile/next"] = "issue 900 quiet-copper-falcon\nraft 900 quiet-copper-falcon\n",
	["pickman/.tracker/issues/c0510/c0510.md"] = ISSUE,
	["pickman/.tracker/issues/c0510/check.sh"] = CHECK,
	["pickman/.tracker/issues/c0520/c0520.md"] = OTHER,
	["pickman/.tracker/issues/c0520/check.sh"] = CHECK,
	[`{R}/R0500.md`] = RAFT,
	[`{R}/check.sh`] = CHECK,
	[`{R}/stream-review-c0510-001.md`] = review(),
	[`{R}/stream-refute-c0510-001.md`] = "- F1: fixed\n",
	[`{R}/stream-review-c0520-001.md`] = review(),
	[`{R}/harvest.md`] = "- stream-review-c0510-001 F1 (erred zz-execute): zz-execute/pin\n"
		.. "- stream-review-c0520-001 F1 (erred zz-execute): zz-execute/pin\n",
	-- two stream files whose ids swap (a map where one issue takes the other's old number)
	["z-nile/swap/stream-review-c0610-001.md"] = "A\n",
	["z-nile/swap/stream-review-c0620-001.md"] = "B\n",
	["z-nile/skills/zz-execute/SKILL.md"] = skill("zz-execute"),
	["z-nile/skills/zz-execute/lessons/pin.md"] = "---\ntitle: Pin\nwhen: build\ntags: [wiring]\ncheck: Is it pinned?\nfrom: a user\n---\nPin it.\n",
}

local f: trackerfix.Fixture
local W = ""

return t.spec("c0136 renumber keeps a stream review's name and its harvest entry together", function(it)
	it("sets up a raft with two issues' stream reviews and a harvest naming them", function()
		f = trackerfix.new("c0136-renumber", SEED, { noLessons = true })
		W = trackerfix.trOk(f, f.main, { "worktree", "ids" })
		-- a refute the lead has written and not committed yet: it moves too, by the plain filesystem call
		fs.writeFile(`{W}/{R}/stream-refute-c0510-002.md`, "- F1: refuted\n")
		local out = trackerfix.trOk(f, W, { "lessons", "--check" })
		t.expect(string.find(out, "ok", 1, true) ~= nil).toBe(true)
	end)

	it("a map that swaps two ids swaps the files, none lost or overwritten (two phases)", function()
		compact.moveStreams(f.main, { "z-nile/swap" }, { c0610 = "c0620", c0620 = "c0610" })
		t.expect(fs.readFile(`{f.main}/z-nile/swap/stream-review-c0620-001.md`)).toBe("A\n")
		t.expect(fs.readFile(`{f.main}/z-nile/swap/stream-review-c0610-001.md`)).toBe("B\n")
	end)

	it("renumber moves the stream files of the renumbered issue, and only those", function()
		trackerfix.trOk(f, W, { "renumber", "c0510", "c0590" })
		local dir = `{W}/{R}`
		t.expect(fs.isFile(`{dir}/stream-review-c0590-001.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/stream-refute-c0590-001.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/stream-refute-c0590-002.md`)).toBe(true) -- the untracked one
		t.expect(fs.isFile(`{dir}/stream-refute-c0510-002.md`)).toBe(false)
		t.expect(fs.isFile(`{dir}/stream-review-c0510-001.md`)).toBe(false)
		t.expect(fs.isFile(`{dir}/stream-refute-c0510-001.md`)).toBe(false)
		t.expect(fs.isFile(`{dir}/stream-review-c0520-001.md`)).toBe(true) -- another issue's stays
		local harvest = fs.readFile(`{dir}/harvest.md`)
		t.expect(string.find(harvest, "- stream-review-c0590-001 F1 (erred zz-execute)", 1, true) ~= nil)
			.toBe(true)
		t.expect((string.find(harvest, "c0510", 1, true))).toBe(nil)
	end)

	it("the entry still resolves: --check is ok and --uncovered is silent", function()
		fixture.git(W, { "add", "-A" })
		fixture.git(W, { "commit", "-q", "-m", "renumber c0510" })
		local check = trackerfix.tr(f, W, { "lessons", "--check" })
		t.expect(check.code).toBe(0)
		local uncovered = trackerfix.tr(f, W, { "lessons", "--uncovered", "R0500" })
		t.expect(uncovered.code).toBe(0)
	end)
	it("compact moves them by its map too: every harvest entry still names a file", function()
		fixture.git(W, { "push", "-q", "origin", "HEAD:main" })
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		fixture.git(W, { "fetch", "-q", "origin" })
		fixture.git(W, { "reset", "-q", "--hard", "origin/main" })
		trackerfix.trOk(f, W, { "compact", "--force" })
		local raft = ""
		for _, name in fs.readDir(`{W}/pickman/.tracker/rafts`) do
			if string.match(name, "^R%d+$") then
				raft = name
			end
		end
		local dir = `{W}/pickman/.tracker/rafts/{raft}`
		local harvest = fs.readFile(`{dir}/harvest.md`)
		local seen = 0
		for _, name in fs.readDir(dir) do
			local stem = string.match(name, "^(stream%-review%-c%d+%-%d+)%.md$")
			if stem then
				seen += 1
				t.expect(string.find(harvest, `- {stem} F1`, 1, true) ~= nil).toBe(true)
				t.expect((string.find(stem, "c0510", 1, true))).toBe(nil)
				t.expect((string.find(stem, "c0590", 1, true))).toBe(nil)
			end
		end
		t.expect(seen).toBe(2)
		t.expect(trackerfix.tr(f, W, { "lessons", "--check" }).code).toBe(0)
		t.expect(trackerfix.tr(f, W, { "lessons", "--uncovered", raft }).code).toBe(0)
	end)
end)
