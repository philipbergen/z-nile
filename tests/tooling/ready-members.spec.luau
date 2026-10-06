--!strict
-- R0025 review 001 F1: `ready` and `stop` agree on a raft's members. `ready` refuses a raft whose issues: list and
-- its members' raft: fields disagree, and `stop` moves back every item that names the raft either way, so nothing
-- `ready` moved is ever left in active/. Fixture under .cache/ready-members (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function raft(issues: string): string
	return `---\nid: R0010\ntype: chore\ntitle: Members\nslug: members\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n`
end

local f: trackerfix.Fixture
local function onOrigin(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end

return t.spec("ready and stop agree on a raft's members", function(it)
	it("sets up a prepared raft whose issues: list leaves out a member", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(".gitignore"), -- ignores prompt.md
			["tracker/architecture.md"] = fs.readFile("tracker/architecture.md"),
			["tracker/rafts/R0010/R0010.md"] = raft("c0010"),
			["tracker/rafts/R0010/check.sh"] = CHECK,
			["tracker/issues/c0010/c0010.md"] = issue("c0010"),
			["tracker/issues/c0010/check.sh"] = CHECK,
			["tracker/issues/c0020/c0020.md"] = issue("c0020"),
			["tracker/issues/c0020/check.sh"] = CHECK,
		}
		for _, s in { "execute-raft", "tracker", "architecture", "testing", "review" } do
			seed[`.claude/skills/{s}/SKILL.md`] = fs.readFile(`.claude/skills/{s}/SKILL.md`)
		end
		f = trackerfix.new("ready-members", seed)
	end)

	it(
		"ready refuses a raft whose issues: list and members' raft: fields disagree, naming the member",
		function()
			local before = fixture.git(f.origin, { "rev-parse", "main" })
			local r = trackerfix.tr(f, f.main, { "ready", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(string.find(r.stderr, "c0020", 1, true) ~= nil).toBe(true)
			t.expect(string.find(r.stderr, "disagree", 1, true) ~= nil).toBe(true)
			t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
		end
	)

	it("stop moves back every item that names the raft, even one its issues: list dropped later", function()
		trackerfix.elsewhere(
			f,
			{ ["tracker/rafts/R0010/R0010.md"] = raft("c0010, c0020") },
			"list both members"
		)
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		t.expect(onOrigin("tracker/issues/active/c0020/c0020.md")).toBe(true)
		-- drift after ready: the raft's list loses c0020, its raft: field still names R0010
		local doc = "tracker/rafts/active/R0010/R0010.md"
		local text = fs.readFile(`{f.main}/{doc}`)
		trackerfix.elsewhere(
			f,
			{ [doc] = (string.gsub(text, "issues: %[c0010, c0020%]", "issues: [c0010]")) },
			"drop"
		)
		trackerfix.trOk(f, f.main, { "stop", "R0010" })
		for _, id in { "c0010", "c0020" } do
			t.expect(onOrigin(`tracker/issues/active/{id}/{id}.md`)).toBe(false)
			t.expect(onOrigin(`tracker/issues/{id}/{id}.md`)).toBe(true)
		end
		t.expect(onOrigin("tracker/rafts/R0010/R0010.md")).toBe(true)
	end)
end)
