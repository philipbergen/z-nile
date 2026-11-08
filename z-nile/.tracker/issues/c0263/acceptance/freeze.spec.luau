--!strict
-- c0263 AC13: the frozen list. `./zn provenance freeze` writes z-nile/provenance-exempt.txt once, from the prepared
-- backlog issues of every project: `<id> <design hash>` lines. It refuses in the main checkout and once the list is on
-- the base (frozen). With the list on the base, a listed issue passes `audit` only while its design is the listed one.
-- A tree whose base has no list enforces nothing (approve.spec's fixtures with a list drive the doors).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0263-freeze"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES = "pickman/.tracker/issues"
local LIST = "z-nile/provenance-exempt.txt"
local HUMAN: { [string]: string } = { CLAUDECODE = "", AI_AGENT = "", CLAUDE_EFFORT = "", ZN_ACTOR = "", ZN_DISPATCH = "" }

local function issue(id: string, status: string, design: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: {design}\ncreated: 2026-10-20\nsize: 300\nstatus: {status}\n---\n\n# {id}\n`
end

local f: trackerfix.Fixture
local W = ""
local function tr(cwd: string, args: { string }): fixture.Result
	return trackerfix.tr(f, cwd, args, HUMAN)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0263 the frozen list", function(it)
	it("sets up two prepared issues, a draft and an active one", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n",
		}
		local states: { [string]: string } = { c0010 = "prepared-a-b-c", c0020 = "prepared-d-e-f", c0030 = "new-g-h-i" }
		for id, st in states do
			seed[`{ISSUES}/{id}/{id}.md`] = issue(id, st, if id == "c0030" then "draft" else "ready")
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		f = trackerfix.new(NAME, seed)
		W = trackerfix.trOk(f, f.main, { "worktree", "freeze-a" })
	end)

	it("freeze lists the prepared backlog issues with their design hashes, and refuses the main checkout", function()
		local main = tr(f.main, { "provenance", "freeze" })
		t.expect(main.ok).toBe(false)
		t.expect(has(main.stderr, "worktree")).toBe(true)
		local r = tr(W, { "provenance", "freeze" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local text = fs.readFile(`{W}/{LIST}`)
		for _, id in { "c0010", "c0020" } do
			local hash = raftplan.recordHash(id, {
				[`{id}.md`] = issue(id, if id == "c0010" then "prepared-a-b-c" else "prepared-d-e-f", "ready"),
				["check.sh"] = CHECK,
			})
			t.expect(has(text, `\n{id} {hash}\n`)).toBe(true)
		end
		t.expect(has(text, "c0030")).toBe(false) -- a draft is not prepared
		t.expect(string.sub(text, 1, 1)).toBe("#")
	end)

	it("once the list is on the base it is frozen, and audit holds a listed issue to the listed design", function()
		fixture.git(W, { "add", "-A" })
		fixture.git(W, { "commit", "-q", "-m", "tracker: freeze provenance" })
		fixture.git(W, { "fetch", "-q", "origin" })
		fixture.git(W, { "merge", "-q", "--no-edit", "origin/main" })
		fixture.git(W, { "push", "-q", "origin", "HEAD:main" })
		local again = tr(W, { "provenance", "freeze" })
		t.expect(again.ok).toBe(false)
		t.expect(has(again.stderr, "frozen")).toBe(true)
		-- listed and unchanged: audit passes
		local clean = tr(W, { "audit" })
		if not clean.ok then
			error(clean.stdout .. clean.stderr)
		end
		-- redone: the listed hash no longer matches, so it needs a fresh approval
		local doc = `{W}/{ISSUES}/c0010/c0010.md`
		fs.writeFile(doc, fs.readFile(doc) .. "\nRedone.\n")
		local redone = tr(W, { "audit" })
		t.expect(redone.ok).toBe(false)
		t.expect(has(redone.stdout .. redone.stderr, "redesigned since the freeze")).toBe(true)
		t.expect(has(redone.stdout .. redone.stderr, "c0010")).toBe(true)
		-- a new prepared issue with no approval and no listing is an error
		fixture.git(W, { "checkout", "--", `{ISSUES}/c0010/c0010.md` })
		fs.writeDir(`{W}/{ISSUES}/c0040`)
		fs.writeFile(`{W}/{ISSUES}/c0040/c0040.md`, issue("c0040", "prepared-j-k-l", "ready"))
		fs.writeFile(`{W}/{ISSUES}/c0040/check.sh`, CHECK)
		local fresh = tr(W, { "audit" })
		t.expect(fresh.ok).toBe(false)
		t.expect(has(fresh.stdout .. fresh.stderr, "c0040")).toBe(true)
		t.expect(has(fresh.stdout .. fresh.stderr, "without an approval")).toBe(true)
	end)
end)
