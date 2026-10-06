--!strict
-- R0025 review 001 F1, review 002 F1-F2: a raft's members, for every move, are the items whose raft: field names it
-- (what `ready` and `start` claim). `ready` refuses a raft whose issues: list disagrees with that set, either way;
-- `stop`, readied or legacy, gives back exactly that set and never touches an item that is only listed, or that
-- another raft owns. Fixture under .cache/ready-members (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Members\nslug: members\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n`
end

local f: trackerfix.Fixture
local function onOrigin(path: string): boolean
	return fixture.exec(f.origin, "git", { "cat-file", "-e", `main:{path}` }).ok
end
local function originText(path: string): string
	return fixture.git(f.origin, { "show", `main:{path}` })
end
local function refusedNaming(args: { string }, ...: string)
	local before = fixture.git(f.origin, { "rev-parse", "main" })
	local r = trackerfix.tr(f, f.main, args)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		t.expect(string.find(r.stderr, needle, 1, true) ~= nil).toBe(true)
	end
	t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
end

return t.spec("ready and stop agree on a raft's members", function(it)
	it("sets up prepared rafts whose issues: lists disagree with their members, both ways", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(".gitignore"), -- ignores prompt.md
			["tracker/architecture.md"] = fs.readFile("tracker/architecture.md"),
			-- R0010 leaves out c0020, which names it
			["tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0010"),
			["tracker/issues/c0010/c0010.md"] = issue("c0010", "R0010"),
			["tracker/issues/c0020/c0020.md"] = issue("c0020", "R0010"),
			-- R0020 owns c0030; R0030 lists it too, and its own member c0040
			["tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "c0030"),
			["tracker/issues/c0030/c0030.md"] = issue("c0030", "R0020"),
			["tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "c0040, c0030"),
			["tracker/issues/c0040/c0040.md"] = issue("c0040", "R0030"),
		}
		for _, dir in
			{
				"tracker/rafts/R0010",
				"tracker/issues/c0010",
				"tracker/issues/c0020",
				"tracker/rafts/R0020",
				"tracker/issues/c0030",
				"tracker/rafts/R0030",
				"tracker/issues/c0040",
			}
		do
			seed[`{dir}/check.sh`] = CHECK
		end
		for _, s in { "execute-raft", "tracker", "architecture", "testing", "review" } do
			seed[`.claude/skills/{s}/SKILL.md`] = fs.readFile(`.claude/skills/{s}/SKILL.md`)
		end
		f = trackerfix.new("ready-members", seed)
	end)

	it(
		"ready refuses a raft whose issues: list and members' raft: fields disagree, naming the member",
		function()
			refusedNaming({ "ready", "R0010" }, "c0020", "disagree") -- names R0010 but is not listed
			refusedNaming({ "ready", "R0030" }, "c0030", "disagree") -- listed, but its raft: is R0020
		end
	)

	it("stop moves back every member that names the raft, even one its issues: list dropped later", function()
		trackerfix.elsewhere(
			f,
			{ ["tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0010, c0020") },
			"list"
		)
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		t.expect(onOrigin("tracker/issues/active/c0020/c0020.md")).toBe(true)
		-- drift after ready: the raft's list loses c0020 and gains c0030, which R0020 owns
		local doc = "tracker/rafts/active/R0010/R0010.md"
		local text = fs.readFile(`{f.main}/{doc}`)
		trackerfix.elsewhere(
			f,
			{ [doc] = (string.gsub(text, "issues: %[c0010, c0020%]", "issues: [c0010, c0030]")) },
			"drift"
		)
		local c0030 = originText("tracker/issues/c0030/c0030.md")
		local out = trackerfix.trOk(f, f.main, { "stop", "R0010" })
		for _, id in { "c0010", "c0020" } do
			t.expect(onOrigin(`tracker/issues/active/{id}/{id}.md`)).toBe(false)
			t.expect(onOrigin(`tracker/issues/{id}/{id}.md`)).toBe(true)
		end
		t.expect(onOrigin("tracker/rafts/R0010/R0010.md")).toBe(true)
		t.expect(originText("tracker/issues/c0030/c0030.md")).toBe(c0030) -- only listed: untouched
		t.expect(string.find(out, "stopped R0010 (c0010, c0020)", 1, true) ~= nil).toBe(true)
	end)

	it("stop gives back a legacy claim by the members' raft: fields, never an item only listed", function()
		-- R0030 started the legacy way: start claims R0030 and c0040 (its raft: members), not the listed c0030
		trackerfix.elsewhere(f, { ["tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "c0040") }, "agree")
		local wt = trackerfix.trOk(f, f.main, { "worktree", "R0030" })
		trackerfix.trOk(f, wt, { "start", "R0030" })
		t.expect(trackerfix.trOk(f, f.main, { "status", "c0040" })).toBe("active")
		-- drift on main afterwards: R0030's list names c0030 again (only that line changes; the claim stays)
		local claimed = originText("tracker/rafts/R0030/R0030.md")
		trackerfix.elsewhere(f, {
			["tracker/rafts/R0030/R0030.md"] = (
				string.gsub(claimed, "issues: %[c0040%]", "issues: [c0040, c0030]")
			),
		}, "relist")
		local c0030 = originText("tracker/issues/c0030/c0030.md")
		local out = trackerfix.trOk(f, f.main, { "stop", "R0030" })
		t.expect(trackerfix.trOk(f, f.main, { "status", "R0030" })).toBe("prepared")
		t.expect(trackerfix.trOk(f, f.main, { "status", "c0040" })).toBe("prepared")
		t.expect(originText("tracker/issues/c0030/c0030.md")).toBe(c0030)
		t.expect(string.find(out, "stopped R0030 (c0040)", 1, true) ~= nil).toBe(true)
	end)
end)
