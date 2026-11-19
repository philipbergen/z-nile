--!strict
-- One `./zn approve` of a design already on main, run from the main checkout, records and publishes it, and work
-- next then offers the raft (c0369). The fixture's design carries an explainer page that names its contract, the
-- opener is a stub first on PATH and `yes y |` answers at the terminal, so the walk passes with or without a page
-- check and a y/n question in approve (c0368's outcome, carried by c0369). The exit code is echoed inside `script`,
-- whose own code is not ./zn's.
local contract = require("@znile/engine/contract")
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
local SPEC = "--!strict\n"
-- a person's terminal: the agent markers and session ids cleared (zz-test lesson terminal-fixtures-clear-the-agent-session)
local TERMINAL: { [string]: string } = {
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

local function doc(): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: hold\nraft: {RAFT}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\nHash the contract.\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end

-- an explainer page of f0339's shape that names the contract of `text`
local function page(text: string): string
	local hash = contract.hash((contract.build(text, CHECK, { ["hold.spec.luau"] = SPEC })) :: contract.Parts)
	return `<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>{ID}</title></head><body>`
		.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
		.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
		.. '<section id="changes"><ul><li><code>z-nile/engine/hold.luau</code>: hold()</li></ul></section>'
		.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
		.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
		.. "</body></html>\n"
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("approve publishes onto origin/main", function(it)
	it("from one approve in the main checkout to work next offering the raft", function()
		local f = trackerfix.new("approve-publish", {
			[`{ROOT}/rafts/{RAFT}/{RAFT}.md`] = `---\nid: {RAFT}\ntype: chore\ntitle: Hold\nslug: hold\nsingle: true\nissues: [{ID}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n\n## Theme\nThe contract stays put.\n`,
			[`{ROOT}/rafts/{RAFT}/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n',
			[`{ISSUE}/{ID}.md`] = doc(),
			[`{ISSUE}/check.sh`] = CHECK,
			[`{ISSUE}/acceptance/hold.spec.luau`] = SPEC,
			[`{ISSUE}/explainer.html`] = page(doc()),
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

		-- a stub opener first on PATH, so a page that is opened never reaches a browser
		local stubs = `{f.base}/stubs`
		fs.writeDir(stubs)
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{stubs}/{name}`, "#!/bin/sh\nexit 0\n")
			fixture.exec(f.main, "chmod", { "+x", `{stubs}/{name}` })
		end
		local env = table.clone(TERMINAL)
		env.PATH = `{stubs}:{process.env.PATH or ""}`
		env.HOME = process.env.HOME or ""
		local line = `yes y | script -q /dev/null sh -c './zn approve {ID}; echo "zn-exit=$?"'`
		local r = fixture.exec(f.main, "sh", { "-c", line }, { env = env })
		local out = r.stdout .. r.stderr
		t.expect(string.match(r.stdout, "zn%-exit=(%d+)")).toBe("0")
		t.expect(has(out, `{ID}: approving in origin/main`)).toBe(true)
		t.expect(has(out, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
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
