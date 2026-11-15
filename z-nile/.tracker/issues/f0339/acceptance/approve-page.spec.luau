--!strict
-- f0339 AC2: `./zn explain <id>` and `./zn approve <id>` with the explainer page. approve refuses a missing,
-- uncommitted or broken page before it opens anything, opens a good page with the system's opener, asks y/n at the
-- terminal and records only on y, and records nothing when the contract changed while the page was open.
-- The fixture is .cache/f0339-approve, a worktree of a tracker fixture; nothing is pushed. Approving goes through
-- `script`, which gives ./zn a terminal: `yes <answer> |` types the answer (a pipe that ends at once loses its
-- line to script's end-of-input), and the exit code is echoed inside script, whose own code is not ./zn's.
-- The opener is a stub first on PATH that logs its argument; F0339_OPEN=fail makes it fail and F0339_OPEN=edit
-- makes it commit a change to the design, as a person editing while the page is open would.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "f0339-approve"
local ID = "c0001"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local PAGE = `{ISSUE}/explainer.html`
local TOUCHED = "z-nile/engine/hold.luau"
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. "finish\n"
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"

local function doc(ready: boolean, design: string?): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: hold\nraft: \ndepends_on: []\nemergent: false\ndesign: {if ready
		then "ready"
		else "draft"}\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\n{design or "Hash the contract."}\n\n### Touched modules\n- \`{TOUCHED}\`\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end

local function page(hash: string, extra: string?): string
	return `<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>{ID}</title>{extra or ""}</head><body>`
		.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
		.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
		.. `<section id="changes"><ul><li><code>{TOUCHED}</code>: hold()</li></ul></section>`
		.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
		.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
		.. "</body></html>\n"
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("f0339 approve shows the explainer page and asks y/n", function(it)
	local f: trackerfix.Fixture
	local wt = ""
	local stubs = ""
	local log = ""

	local function say(r: fixture.Result): string
		return r.stderr .. r.stdout
	end
	local function commit(message: string)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", message })
	end
	local function head(): string
		return fixture.git(wt, { "rev-parse", "HEAD" })
	end
	local function opened(): string
		return if fs.isFile(log) then fs.readFile(log) else ""
	end
	local function env(mode: string?): { [string]: string }
		return {
			PATH = `{stubs}:{process.env.PATH or ""}`,
			HOME = process.env.HOME or "",
			F0339_LOG = log,
			F0339_OPEN = mode or "",
			F0339_WT = wt,
		}
	end
	-- `./zn approve` with a terminal; answer nil gives it a terminal that closes at once (no answer).
	local function approve(answer: string?, mode: string?): (fixture.Result, string?)
		if fs.isFile(log) then
			fs.removeFile(log)
		end
		local inner = `script -q /dev/null sh -c './zn approve {ID}; echo "zn-exit=$?"'`
		local line = if answer then `yes {answer} | {inner}` else `{inner} < /dev/null`
		local r = fixture.exec(wt, "sh", { "-c", line }, { env = env(mode) })
		return r, string.match(r.stdout, "zn%-exit=(%d+)")
	end
	local function explain(): (fixture.Result, string?)
		local r = fixture.exec(wt, "./zn", { "explain", ID }, { env = env() })
		return r, string.match(r.stdout, "\ncontract (%x+)\n")
	end

	it("sets up a design-ready issue in a worktree and a recording opener", function()
		f = trackerfix.new(NAME, {
			-- a ready seed would carry an approval (trackerfix seals it), so the seed is a draft
			[`{ISSUE}/{ID}.md`] = doc(false),
			[`{ISSUE}/check.sh`] = CHECK,
			[`{ISSUE}/acceptance/hold.spec.luau`] = SPEC,
		})
		wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-c0001", wt, "HEAD" })
		fs.writeFile(`{wt}/{ISSUE}/{ID}.md`, doc(true))
		commit("design ready")
		stubs = `{f.base}/stubs`
		log = `{f.base}/opened.log`
		fs.writeDir(stubs)
		local stub = table.concat({
			"#!/bin/sh",
			'echo "$1" >> "$F0339_LOG"',
			'if [ "$F0339_OPEN" = fail ]; then exit 1; fi',
			'if [ "$F0339_OPEN" = edit ]; then',
			`  sed 's/^Hash the contract\\.$/Hash the contract, and more./' "$F0339_WT/{ISSUE}/{ID}.md" > "$F0339_WT/{ISSUE}/{ID}.md.tmp"`,
			`  mv "$F0339_WT/{ISSUE}/{ID}.md.tmp" "$F0339_WT/{ISSUE}/{ID}.md"`,
			`  git -C "$F0339_WT" commit -q -am 'edited while open' || exit 9`,
			"fi",
			"exit 0",
			"",
		}, "\n")
		for _, name in { "open", "xdg-open" } do
			fs.writeFile(`{stubs}/{name}`, stub)
			process.exec("chmod", { "+x", `{stubs}/{name}` })
		end
	end)

	it("AC2: explain prints the page path and the contract hash, and names a missing page", function()
		local r, hash = explain()
		t.expect(r.ok).toBe(false)
		t.expect(string.match(r.stdout, "^[^\n]+") or "").toBe(PAGE)
		t.expect(hash ~= nil and #(hash :: string) == 64).toBe(true)
		t.expect(has(r.stdout, `{ID} has no explainer page ({PAGE})`)).toBe(true)
		t.expect(has(r.stdout, "z-nile/templates/explainer.html")).toBe(true)
		t.expect(has(r.stdout, "\nok\n")).toBe(false)
	end)

	it("AC2: approve refuses a missing page before it opens or asks anything", function()
		local before = head()
		local r, code = approve("y")
		t.expect(code ~= nil and code ~= "0").toBe(true)
		t.expect(has(say(r), `{ID} has no explainer page ({PAGE})`)).toBe(true)
		t.expect(has(say(r), "[y/N]")).toBe(false)
		t.expect(opened()).toBe("")
		t.expect(head()).toBe(before)
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)
	end)

	it("AC2: approve refuses an uncommitted page, a page for another contract, one missing a Touched module and one that fetches", function()
		local _, hash = explain()
		fs.writeFile(`{wt}/{PAGE}`, page(hash :: string))
		local dirty, dcode = approve("y")
		t.expect(dcode ~= nil and dcode ~= "0").toBe(true)
		t.expect(has(say(dirty), "commit the contract first")).toBe(true)
		t.expect(has(say(dirty), "explainer.html")).toBe(true)
		t.expect(opened()).toBe("")

		fs.writeFile(`{wt}/{PAGE}`, page(string.rep("0", 64)))
		commit("a stale page")
		local before = head()
		local stale, scode = approve("y")
		t.expect(scode ~= nil and scode ~= "0").toBe(true)
		t.expect(
			has(
				say(stale),
				`explains contract 000000000000, but the contract is now {string.sub(hash :: string, 1, 12)}`
			)
		).toBe(true)
		t.expect(has(say(stale), "[y/N]")).toBe(false)
		t.expect(opened()).toBe("")
		t.expect(head()).toBe(before)
		local ex = explain()
		t.expect(ex.ok).toBe(false)
		t.expect(has(ex.stdout, "explains contract 000000000000")).toBe(true)

		-- a page whose changes leave out the issue's Touched module: approve passes it the issue's own list
		local good = page(hash :: string)
		local at = string.find(good, TOUCHED, 1, true) :: number
		fs.writeFile(`{wt}/{PAGE}`, string.sub(good, 1, at - 1) .. "z-nile/engine/other.luau" .. string.sub(good, at + #TOUCHED))
		commit("a page that leaves out a Touched module")
		local unnamed, ucode = approve("y")
		t.expect(ucode ~= nil and ucode ~= "0").toBe(true)
		t.expect(has(say(unnamed), `does not name {TOUCHED} (a Touched module)`)).toBe(true)
		t.expect(opened()).toBe("")
		local ux = explain()
		t.expect(ux.ok).toBe(false)
		t.expect(has(ux.stdout, `does not name {TOUCHED}`)).toBe(true)

		fs.writeFile(`{wt}/{PAGE}`, page(hash :: string, '<link rel="stylesheet" href="https://example.invalid/a.css">'))
		commit("a page that fetches")
		local fetches, fcode = approve("y")
		t.expect(fcode ~= nil and fcode ~= "0").toBe(true)
		t.expect(has(say(fetches), 'fetches href="https://example.invalid/a.css"')).toBe(true)
		t.expect(opened()).toBe("")
	end)

	it("AC2: explain passes a good page", function()
		local _, hash = explain()
		fs.writeFile(`{wt}/{PAGE}`, page(hash :: string))
		commit("a good page")
		local r, again = explain()
		t.expect(r.ok).toBe(true)
		t.expect(again).toBe(hash)
		t.expect(has(r.stdout, "\nok\n")).toBe(true)
	end)

	it("AC2: approve opens the page, asks, and records nothing on n or on no answer", function()
		local before = head()
		local no, code = approve("n")
		t.expect(code ~= nil and code ~= "0").toBe(true)
		t.expect(opened()).toBe(`{wt}/{PAGE}\n`)
		t.expect(has(say(no), `Approve {ID}, contract `)).toBe(true)
		t.expect(has(say(no), "[y/N]")).toBe(true)
		t.expect(has(say(no), `{ID}: not approved (n); nothing recorded`)).toBe(true)
		t.expect(head()).toBe(before)
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)

		local silent, scode = approve(nil)
		t.expect(scode ~= nil and scode ~= "0").toBe(true)
		t.expect(opened()).toBe(`{wt}/{PAGE}\n`)
		t.expect(has(say(silent), "nothing recorded")).toBe(true)
		t.expect(head()).toBe(before)
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)
	end)

	it("AC2: a contract changed while the page was open is not approved", function()
		local before = head()
		local r, code = approve("y", "edit")
		t.expect(code ~= nil and code ~= "0").toBe(true)
		t.expect(has(say(r), "the contract changed while the page was open")).toBe(true)
		t.expect(has(say(r), "nothing recorded")).toBe(true)
		-- the stub's commit is the only new one: no approval was committed on top of it
		t.expect(fixture.git(wt, { "rev-parse", "HEAD~1" })).toBe(before)
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)
		local _, hash = explain()
		fs.writeFile(`{wt}/{PAGE}`, page(hash :: string))
		commit("the page for the edited design")
	end)

	it("AC2: y records the contract the page names, and a failed opener only warns", function()
		local _, hash = explain()
		local r, code = approve("y", "fail")
		t.expect(code).toBe("0")
		t.expect(opened()).toBe(`{wt}/{PAGE}\n`)
		t.expect(has(say(r), `could not open {wt}/{PAGE}`)).toBe(true)
		t.expect(has(say(r), "[y/N]")).toBe(true)
		t.expect(has(r.stdout, `approved {ID} {hash}`)).toBe(true)
		t.expect(has(fs.readFile(`{wt}/{ISSUE}/approval.md`), `\t{hash}\t`)).toBe(true)
		t.expect(fixture.git(wt, { "log", "-1", "--format=%s" })).toBe(`tracker: approve {ID}`)

		fixture.git(wt, { "reset", "-q", "--hard", "HEAD~1" })
		local yes, ycode = approve("yes")
		t.expect(ycode).toBe("0")
		t.expect(opened()).toBe(`{wt}/{PAGE}\n`)
		t.expect(has(say(yes), "could not open")).toBe(false)
		t.expect(has(yes.stdout, `approved {ID} {hash}`)).toBe(true)
	end)
end)
