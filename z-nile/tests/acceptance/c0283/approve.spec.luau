--!strict
-- c0283 AC2, AC3: ./zn approve on top of #295's approval.md. It is refused in an agent session even with a terminal
-- (CLAUDECODE, AI_AGENT, CURSOR_AGENT, GROK_SESSION_ID), and it records the same approval as an `approved` row of the
-- issue's provenance.md (c0263's record) in the one commit that holds approval.md, authored by the git identity.
-- The fixture is .cache/c0283-approve. Approving goes through `script`, which allocates a terminal; the spec process
-- itself has none, and fixture.exec hands its children none of the session markers unless a case sets them.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0283-approve"
local ID = "c0001"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{ID}/check.sh\n` .. "finish\n"
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"

local function doc(design: string): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: hold\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\n{design}\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0283 approve in an agent session and the provenance row", function(it)
	local f: trackerfix.Fixture
	local wt = ""

	local function say(r: fixture.Result): string
		return r.stderr .. r.stdout
	end
	local function approve(env: { [string]: string }?, extra: { string }?): fixture.Result
		local merged: { [string]: string } = { PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
		for k, v in env or {} do
			merged[k] = v
		end
		local args = { "-q", "/dev/null", "./zn", "approve", ID }
		for _, a in extra or {} do
			table.insert(args, a)
		end
		return fixture.exec(wt, "script", args, { env = merged })
	end
	local function head(): string
		return fixture.git(wt, { "rev-parse", "HEAD" })
	end
	local function commit(message: string)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", message })
	end
	local function rows(file: string): { string }
		local out: { string } = {}
		for line in string.gmatch(fs.readFile(`{wt}/{ISSUE}/{file}`), "[^\n]+") do
			table.insert(out, line)
		end
		return out
	end

	it("sets up a designed issue in a worktree", function()
		f = trackerfix.new(NAME, {
			[`{ISSUE}/{ID}.md`] = doc("Hash the contract."),
			[`{ISSUE}/check.sh`] = CHECK,
			[`{ISSUE}/acceptance/hold.spec.luau`] = SPEC,
		})
		wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-c0001", wt, "HEAD" })
	end)

	it("is refused in an agent session even with a terminal, and writes and commits nothing", function()
		local before = head()
		local sessions: { { [string]: string } } = {
			{ CLAUDECODE = "1" },
			{ AI_AGENT = "claude-code_2" },
			{ CURSOR_AGENT = "1" },
			{ GROK_SESSION_ID = "probe" },
			{ CLAUDECODE = "1", ZN_ACTOR = `human:{NAME}` },
		}
		for _, env in sessions do
			local r = approve(env)
			t.expect(r.ok).toBe(false)
			if not has(say(r), "approve is refused in an agent session, terminal or not") then
				error(`no agent-session refusal for {next(env)}: {say(r)}`)
			end
			t.expect(has(say(r), "in your own terminal")).toBe(true)
		end
		-- a dispatched step keeps #295's own answer
		local dispatched = approve({ ZN_DISPATCH = "1" })
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(say(dispatched), "ZN_DISPATCH is set")).toBe(true)
		t.expect(head()).toBe(before)
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)
		t.expect(fs.isFile(`{wt}/{ISSUE}/provenance.md`)).toBe(false)
	end)

	it(
		"in a plain terminal records approval.md and the approved row in one commit by the git identity",
		function()
			local r = approve(nil)
			if not r.ok then
				error(say(r))
			end
			local hash = string.match(r.stdout, `approved {ID} (%x+)`) :: string
			t.expect(#hash).toBe(64)
			t.expect(fixture.git(wt, { "log", "-1", "--format=%an|%s" })).toBe(`{NAME}|tracker: approve {ID}`)
			local files = fixture.git(wt, { "show", "--name-only", "--format=", "HEAD" })
			t.expect(files).toBe(`{ISSUE}/approval.md\n{ISSUE}/provenance.md`)
			local lines = rows("provenance.md")
			t.expect(#lines).toBe(4) -- the title, the table header, the separator and one row (gmatch skips the blank line)
			t.expect(
				string.match(
					lines[4],
					`^| %d%d%d%d%-%d%d%-%d%d %d%d:%d%d | approved | human:{NAME} | contract={string.sub(
						hash,
						1,
						12
					)} |$`
				) ~= nil
			).toBe(true)
			t.expect(fixture.git(wt, { "status", "--porcelain" })).toBe("")
		end
	)

	it("a redesign and a second approval append a second row that agrees with approval.md", function()
		fs.writeFile(`{wt}/{ISSUE}/{ID}.md`, doc("Hash the contract, and say so."))
		commit("a redesign")
		local r = approve(nil)
		if not r.ok then
			error(say(r))
		end
		local hash = string.match(r.stdout, `approved {ID} (%x+)`) :: string
		local lines = rows("provenance.md")
		t.expect(#lines).toBe(5)
		t.expect(has(lines[5], `contract={string.sub(hash, 1, 12)} |`)).toBe(true)
		t.expect(has(lines[4], `contract={string.sub(hash, 1, 12)} |`)).toBe(false)
		local approvals = rows("approval.md")
		t.expect(has(approvals[#approvals], hash)).toBe(true)
	end)

	it(
		"refuses a provenance.md with uncommitted changes or one that does not parse, writing nothing",
		function()
			fs.writeFile(`{wt}/{ISSUE}/{ID}.md`, doc("A third design."))
			commit("a third design")
			local before = head()
			local approvals = fs.readFile(`{wt}/{ISSUE}/approval.md`)
			local good = fs.readFile(`{wt}/{ISSUE}/provenance.md`)
			fs.writeFile(`{wt}/{ISSUE}/provenance.md`, good .. "| stray\n")
			local dirty = approve(nil)
			t.expect(dirty.ok).toBe(false)
			t.expect(has(say(dirty), "commit")).toBe(true)
			commit("junk in the record")
			local junk = head()
			local bad = approve(nil)
			t.expect(bad.ok).toBe(false)
			t.expect(has(say(bad), "line")).toBe(true)
			t.expect(head()).toBe(junk)
			t.expect(fs.readFile(`{wt}/{ISSUE}/approval.md`)).toBe(approvals)
			t.expect(before ~= junk).toBe(true)
			fixture.git(wt, { "reset", "-q", "--hard", before })
		end
	)

	it("--check only reads, so it runs in an agent session", function()
		-- the second design is no longer the contract (the third replaced it): the check says so, and writes nothing
		local before = head()
		local r = fixture.exec(wt, "./zn", { "approve", ID, "--check" }, { env = { CLAUDECODE = "1" } })
		t.expect(has(say(r), "agent session")).toBe(false)
		t.expect(has(say(r), "contract changed since approval") or has(say(r), "approved ")).toBe(true)
		t.expect(head()).toBe(before)
	end)
end)
