--!strict
-- c0144: the fixture look.spec.luau and plain-base.luau share (items of every type and state in two projects, an
-- active raft with a check.sh, one seeded lesson), and the read-only commands with a look that both run in it.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local trackerfix = require("@tests/lib/trackerfix")

local seed = {}

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
seed.LONG = "A very long title that has to be cut short to fit a narrow terminal window"

local function doc(id: string, kind: string, title: string, status: string, extra: string?): string
	return `---\nid: {id}\ntype: {kind}\ntitle: {title}\nslug: s-{string.lower(id)}\n{extra or "raft: \n"}design: ready\ncreated: 2026-10-26\nstatus: {status}\n---\n\n# {id}\n`
end

local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: it holds" true\nfinish\n'

local LESSON = "---\ntitle: A seeded lesson\nwhen: both\ntags: [look]\nfrom: c0144 look.spec\n"
	.. "check: Does the seeded lesson show its check, wrapped under its id, with every word kept?\n---\nBody.\n"

-- Builds the fixture under .cache/<name>, every item pushed to its origin.
function seed.build(name: string): trackerfix.Fixture
	local files: { [string]: string } = {
		["z-nile/projects.toml"] = REGISTRY,
		["pickman/scripts/tracker.sh"] = fs.readFile(`{TOP}/pickman/scripts/tracker.sh`),
		["pickman/.tracker/issues/f0001/f0001.md"] = doc(
			"f0001",
			"feature",
			"Speed boost escape",
			"new-quiet-amber-otter"
		),
		["pickman/.tracker/issues/d0002/d0002.md"] = doc(
			"d0002",
			"defect",
			"Ghosts clip through walls",
			"preparing-brisk-lucky-heron"
		),
		["pickman/.tracker/rafts/active/R0003/R0003.md"] = doc(
			"R0003",
			"chore",
			"Frame tolerance",
			"active-jolly-sunny-copper",
			"issues: [c0004]\nsingle: false\n"
		),
		["pickman/.tracker/rafts/active/R0003/check.sh"] = CHECK,
		["pickman/.tracker/issues/active/c0004/c0004.md"] = doc(
			"c0004",
			"chore",
			"Frame roundtrip tolerance",
			"active-jolly-sunny-copper",
			"raft: R0003\n"
		),
		["pickman/.tracker/issues/active/c0004/check.sh"] = CHECK,
		["z-nile/.tracker/issues/c0005/c0005.md"] = doc(
			"c0005",
			"chore",
			seed.LONG,
			"prepared-mellow-violet-lynx"
		),
		["z-nile/.tracker/issues/c0005/check.sh"] = CHECK,
		["z-nile/.tracker/issues/c0005/acceptance/.gitkeep"] = "",
		["z-nile/skills/zz-test/lessons/seeded-look-lesson.md"] = LESSON,
	}
	for _, state in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
		files[`z-nile/.tracker/{state}/.gitkeep`] = ""
	end
	local f = trackerfix.new(name, files, { noLessons = true })
	fixture.exec(f.main, "chmod", { "+x", "pickman/scripts/tracker.sh" })
	fixture.git(f.main, { "commit", "-qam", "the forwarder is executable" })
	fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
	return f
end

-- the commands with a look, read-only against the fixture
seed.COMMANDS = {
	{ "status" },
	{ "list" },
	{ "members", "R0003" },
	{ "busy", "c0004" },
	{ "audit" },
	{ "workstreams", "R0003" },
	{ "lessons", "--skill", "zz-test" },
	{ "lessons", "--check" },
	{ "metrics" },
	{ "capture", "f0001" },
	{ "promote-check", "c0005" },
}

return seed
