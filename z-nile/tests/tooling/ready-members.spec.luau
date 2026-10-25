--!strict
-- R0025 review 001 F1, review 002 F1-F2, review 003 F1/F3: `ready` refuses a raft whose issues: list disagrees with
-- its members' raft: fields, either way; `ready` and `start` stamp the raft and its members with one claim, and
-- `stop`, readied or legacy, gives back exactly the issues carrying that claim. An issue only listed, owned by another
-- raft, or filed naming the raft after the claim is never touched (the last is named in a warning), and a claimed
-- issue whose raft: was edited since still comes back. Fixture under .cache/ready-members (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

-- the checkout's top, for reading repository files: specs run in their home (c0120)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

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
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`), -- ignores prompt.md
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			-- R0010 leaves out c0020, which names it
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0010"),
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "R0010"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "R0010"),
			-- R0020 owns c0030; R0030 lists it too, and its own member c0040
			["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "c0030"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "R0020"),
			["pickman/.tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "c0040, c0030"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "R0030"),
		}
		for _, dir in
			{
				"pickman/.tracker/rafts/R0010",
				"pickman/.tracker/issues/c0010",
				"pickman/.tracker/issues/c0020",
				"pickman/.tracker/rafts/R0020",
				"pickman/.tracker/issues/c0030",
				"pickman/.tracker/rafts/R0030",
				"pickman/.tracker/issues/c0040",
			}
		do
			seed[`{dir}/check.sh`] = CHECK
		end
		-- the prompt's skills come with the copied tooling (z-nile/skills, c0115)
		f = trackerfix.new("ready-members", seed)
	end)

	it(
		"ready refuses a raft whose issues: list and members' raft: fields disagree, naming the member",
		function()
			refusedNaming({ "ready", "R0010" }, "c0020", "disagree") -- names R0010 but is not listed
			refusedNaming({ "ready", "R0030" }, "c0030", "disagree") -- listed, but its raft: is R0020
		end
	)

	it("stop moves back every claimed issue, whatever its list or raft: field says since", function()
		trackerfix.elsewhere(
			f,
			{ ["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "c0010, c0020") },
			"list"
		)
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		t.expect(onOrigin("pickman/.tracker/issues/active/c0020/c0020.md")).toBe(true)
		-- drift after ready: the raft's list loses c0020 and gains c0030, which R0020 owns
		local doc = "pickman/.tracker/rafts/active/R0010/R0010.md"
		local text = fs.readFile(`{f.main}/{doc}`)
		trackerfix.elsewhere(
			f,
			{ [doc] = (string.gsub(text, "issues: %[c0010, c0020%]", "issues: [c0010, c0030]")) },
			"drift"
		)
		-- after the claim: c0050 is filed naming R0010 (never claimed), and c0020's raft: is edited away (still claimed)
		local claimedC0020 = originText("pickman/.tracker/issues/active/c0020/c0020.md")
		trackerfix.elsewhere(f, {
			["pickman/.tracker/issues/c0050/c0050.md"] = (
				string.gsub(issue("c0050", "R0010"), PREPARED, "new-a-b-c")
			),
			["pickman/.tracker/issues/active/c0020/c0020.md"] = (
				string.gsub(claimedC0020, "raft: R0010", "raft: R0099")
			),
		}, "after the claim")
		local c0030 = originText("pickman/.tracker/issues/c0030/c0030.md")
		local c0050 = originText("pickman/.tracker/issues/c0050/c0050.md")
		local r = trackerfix.tr(f, f.main, { "stop", "R0010" })
		t.expect(r.ok).toBe(true)
		local out = r.stdout
		t.expect(string.find(r.stderr, "c0050", 1, true) ~= nil).toBe(true) -- named in the warning
		t.expect(originText("pickman/.tracker/issues/c0050/c0050.md")).toBe(c0050) -- never claimed: untouched
		for _, id in { "c0010", "c0020" } do
			t.expect(onOrigin(`pickman/.tracker/issues/active/{id}/{id}.md`)).toBe(false)
			t.expect(onOrigin(`pickman/.tracker/issues/{id}/{id}.md`)).toBe(true)
		end
		t.expect(onOrigin("pickman/.tracker/rafts/R0010/R0010.md")).toBe(true)
		t.expect(originText("pickman/.tracker/issues/c0030/c0030.md")).toBe(c0030) -- only listed: untouched
		t.expect(string.find(out, "stopped R0010 (c0010, c0020)", 1, true) ~= nil).toBe(true)
	end)

	it("stop gives back a legacy claim to exactly the claimed issues", function()
		-- R0030 started the legacy way: start claims R0030 and c0040 (its raft: members), not the listed c0030
		trackerfix.elsewhere(
			f,
			{ ["pickman/.tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "c0040") },
			"agree"
		)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "R0030" })
		trackerfix.trOk(f, wt, { "start", "R0030" })
		t.expect(trackerfix.trOk(f, f.main, { "status", "c0040" })).toBe("active")
		-- drift on main afterwards: R0030's list names c0030 again (only that line changes; the claim stays)
		local claimed = originText("pickman/.tracker/rafts/R0030/R0030.md")
		trackerfix.elsewhere(f, {
			["pickman/.tracker/rafts/R0030/R0030.md"] = (
				string.gsub(claimed, "issues: %[c0040%]", "issues: [c0040, c0030]")
			),
		}, "relist")
		-- after the claim: c0060 is filed naming R0030; it carries no claim of R0030, so stop leaves it
		trackerfix.elsewhere(f, {
			["pickman/.tracker/issues/c0060/c0060.md"] = (
				string.gsub(issue("c0060", "R0030"), PREPARED, "new-a-b-c")
			),
		}, "late member")
		local c0030 = originText("pickman/.tracker/issues/c0030/c0030.md")
		local c0060 = originText("pickman/.tracker/issues/c0060/c0060.md")
		local r = trackerfix.tr(f, f.main, { "stop", "R0030" })
		t.expect(r.ok).toBe(true)
		local out = r.stdout
		t.expect(string.find(r.stderr, "c0060", 1, true) ~= nil).toBe(true)
		t.expect(originText("pickman/.tracker/issues/c0060/c0060.md")).toBe(c0060)
		t.expect(trackerfix.trOk(f, f.main, { "status", "R0030" })).toBe("prepared")
		t.expect(trackerfix.trOk(f, f.main, { "status", "c0040" })).toBe("prepared")
		t.expect(originText("pickman/.tracker/issues/c0030/c0030.md")).toBe(c0030)
		t.expect(string.find(out, "stopped R0030 (c0040)", 1, true) ~= nil).toBe(true)
	end)
	it("stop refuses a raft with no claim stamp, and moves nothing", function()
		-- a raft in active/ with no status: line (made by hand): its effective status is active, but no claim names it
		local doc = (string.gsub(raftDoc("R0040", "c0090"), "status: [^\n]*\n", ""))
		trackerfix.elsewhere(f, { ["pickman/.tracker/rafts/active/R0040/R0040.md"] = doc }, "unstamped")
		refusedNaming({ "stop", "R0040" }, "R0040", "claim stamp", "by hand")
	end)
	it("a resumed legacy start claims a member published meanwhile with the raft's own stamp", function()
		trackerfix.elsewhere(f, {
			["pickman/.tracker/rafts/R0050/R0050.md"] = raftDoc("R0050", "c0070"),
			["pickman/.tracker/rafts/R0050/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "R0050"),
			["pickman/.tracker/issues/c0070/check.sh"] = CHECK,
		}, "R0050")
		trackerfix.trOk(f, f.main, { "sync" })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "R0050" })
		-- a local edit of the raft's status line makes the merge of origin's claim conflict: start dies after it
		local doc = `{wt}/pickman/.tracker/rafts/R0050/R0050.md`
		fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\nstatus: [^\n]*", "\nstatus: prepared-zz-zz-zz")))
		fixture.git(wt, { "commit", "-q", "-am", "local edit of the status line" })
		t.expect(trackerfix.tr(f, wt, { "start", "R0050" }).ok).toBe(false)
		-- meanwhile another terminal adds a member; this terminal resolves the conflict and starts again
		trackerfix.elsewhere(f, {
			["pickman/.tracker/issues/c0080/c0080.md"] = issue("c0080", "R0050"),
			["pickman/.tracker/issues/c0080/check.sh"] = CHECK,
		}, "a member meanwhile")
		fixture.git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		trackerfix.trOk(f, wt, { "sync" })
		trackerfix.trOk(f, wt, { "start", "R0050" })
		local claim = string.match(originText("pickman/.tracker/rafts/R0050/R0050.md"), "\nstatus: (%S+)")
		t.expect(string.match(originText("pickman/.tracker/issues/c0080/c0080.md"), "\nstatus: (%S+)"))
			.toBe(claim)
		t.expect(string.match(originText("pickman/.tracker/issues/c0070/c0070.md"), "\nstatus: (%S+)"))
			.toBe(claim)
		local r = trackerfix.tr(f, f.main, { "stop", "R0050" })
		t.expect(r.ok).toBe(true)
		t.expect(string.find(r.stderr, "warning", 1, true) == nil).toBe(true)
		t.expect(string.find(r.stdout, "stopped R0050 (c0070, c0080)", 1, true) ~= nil).toBe(true)
	end)
end)
