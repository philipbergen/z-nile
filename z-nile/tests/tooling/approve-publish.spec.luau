--!strict
-- An approval of a design already on main is published from the worktree, and work next then offers the raft.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ID = "c0001"
local RAFT = "R0001"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{ID}/check.sh\n` .. "finish\n"

local function doc(): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: hold\nraft: {RAFT}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\nHash the contract.\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("approve publishes onto origin/main", function(it)
	it("from approve to work next offering the raft", function()
		local f = trackerfix.new("approve-publish", {
			[`{ROOT}/rafts/{RAFT}/{RAFT}.md`] = `---\nid: {RAFT}\ntype: chore\ntitle: Hold\nslug: hold\nsingle: true\nissues: [{ID}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n\n## Theme\nThe contract stays put.\n`,
			[`{ROOT}/rafts/{RAFT}/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n',
			[`{ISSUE}/{ID}.md`] = doc(),
			[`{ISSUE}/check.sh`] = CHECK,
			[`{ISSUE}/acceptance/hold.spec.luau`] = "--!strict\n",
		})
		fs.removeFile(`{f.main}/{ISSUE}/approval.md`)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", "the design, with no approval" })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local before = fixture.exec(f.main, "./zn", { "work", "next" })
		local said = before.stdout .. before.stderr
		if not before.ok then
			error(said)
		end
		-- f0399: the raft is offered before its approval (done asks for it); the publish below still
		-- carries the approval to origin/main
		t.expect(has(said, "R0001: ready")).toBe(true)

		local wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-c0001", wt, "HEAD" })
		local env = { PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
		local recorded = fixture.exec(
			wt,
			"script",
			{ "-q", "/dev/null", "./zn", "approve", ID },
			{ env = env }
		)
		if not recorded.ok then
			error(recorded.stdout .. recorded.stderr)
		end
		t.expect(has(recorded.stdout, `./zn approve {ID} --publish`)).toBe(true)
		local published = fixture.exec(
			wt,
			"script",
			{ "-q", "/dev/null", "./zn", "approve", ID, "--publish" },
			{ env = env }
		)
		if not published.ok then
			error(published.stdout .. published.stderr)
		end
		t.expect(has(published.stdout, "published")).toBe(true)
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		t.expect(fs.isFile(`{f.main}/{ISSUE}/approval.md`)).toBe(true)
		local after = fixture.exec(f.main, "./zn", { "work", "next" })
		local offered = after.stdout .. after.stderr
		if not after.ok then
			error(offered)
		end
		t.expect(has(offered, "R0001: ready")).toBe(true)
	end)
end)
