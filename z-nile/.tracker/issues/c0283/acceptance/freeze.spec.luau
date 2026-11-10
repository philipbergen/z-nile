--!strict
-- c0283 AC13: the frozen list. `./zn provenance freeze` writes z-nile/provenance-exempt.txt once, from the prepared
-- backlog issues of every project: `<id> <design hash>` lines. It refuses in the main checkout and once the list is on
-- the base (frozen). With the list on the base, a listed issue passes `audit` only while its design is the listed one.
-- A tree whose base has no list enforces nothing (approve.spec's fixtures with a list drive the doors).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0283-freeze"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES = "pickman/.tracker/issues"
local LIST = "z-nile/provenance-exempt.txt"
local HUMAN: { [string]: string } =
	{ CLAUDECODE = "", AI_AGENT = "", CLAUDE_EFFORT = "", ZN_ACTOR = "", ZN_DISPATCH = "" }

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

return t.spec("c0283 the frozen list", function(it)
	it("sets up two prepared issues, a draft and an active one", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			["z-nile/next"] = "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n",
		}
		local states: { [string]: string } =
			{ c0010 = "prepared-a-b-c", c0020 = "prepared-d-e-f", c0030 = "new-g-h-i" }
		for id, st in states do
			seed[`{ISSUES}/{id}/{id}.md`] = issue(id, st, if id == "c0030" then "draft" else "ready")
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		-- an issue readied by a raft is listed too (stop gives it back prepared); a done one is not
		seed[`{ISSUES}/active/c0050/c0050.md`] = (
			string.gsub(issue("c0050", "active-j-k-l", "ready"), "raft: \n", "raft: R0050\n", 1)
		)
		seed["pickman/.tracker/rafts/active/R0050/R0050.md"] =
			"---\nid: R0050\ntype: chore\ntitle: Held\nslug: held\nsingle: false\nissues: [c0050]\ndesign: ready\ncreated: 2026-10-20\nstatus: active-j-k-l\n---\n\n# R0050\n"
		seed["pickman/.tracker/rafts/active/R0050/check.sh"] = CHECK
		seed[`{ISSUES}/active/c0050/check.sh`] = CHECK
		seed[`{ISSUES}/done/c0060/c0060.md`] = issue("c0060", "done-m-n-o", "ready")
		seed[`{ISSUES}/done/c0060/check.sh`] = CHECK
		-- a landed prepared raft to fold into
		seed["pickman/.tracker/rafts/R0100/R0100.md"] =
			"---\nid: R0100\ntype: chore\ntitle: Landed\nslug: landed\nsingle: false\nissues: []\ndesign: ready\ncreated: 2026-10-20\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0100\n\n## Theme\nLanded.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n"
		seed["pickman/.tracker/rafts/R0100/check.sh"] = CHECK
		f = trackerfix.new(NAME, seed)
		W = trackerfix.trOk(f, f.main, { "worktree", "freeze-a" })
	end)

	it("a tree whose base has no list enforces nothing at the doors", function()
		-- c0010 and c0020 are prepared with no approval; with no list on origin/main audit and raft-plan leave them alone
		local clean = tr(W, { "audit" })
		if not clean.ok then
			error(clean.stdout .. clean.stderr)
		end
		local plan = tr(W, { "raft-plan" })
		t.expect(plan.ok).toBe(true)
		t.expect(has(plan.stdout, "skip c0010")).toBe(false)
		t.expect(has(plan.stdout, "skip c0020")).toBe(false)
	end)

	it(
		"freeze lists the prepared backlog issues with their design hashes, and refuses the main checkout",
		function()
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
					[`{id}.md`] = issue(
						id,
						if id == "c0010" then "prepared-a-b-c" else "prepared-d-e-f",
						"ready"
					),
					["check.sh"] = CHECK,
				})
				t.expect(has(text, `\n{id} {hash}\n`)).toBe(true)
			end
			t.expect(has(text, "c0030")).toBe(false) -- a draft is not prepared
			t.expect(has(text, "c0060")).toBe(false) -- nor is a done issue
			t.expect(has(text, "\nc0050 ")).toBe(true) -- a readied one is listed: stop gives it back prepared
			t.expect(string.sub(text, 1, 1)).toBe("#")
			-- --check compares the committed list with the tree, both directions
			local uncommitted = tr(W, { "provenance", "freeze", "--check" })
			t.expect(uncommitted.ok).toBe(false)
			t.expect(has(uncommitted.stderr, "not committed")).toBe(true)
			fixture.git(W, { "add", "-A" })
			fixture.git(W, { "commit", "-q", "-m", "the list" })
			local green = tr(W, { "provenance", "freeze", "--check" })
			if not green.ok then
				error(green.stdout .. green.stderr)
			end
			local function broken(edit: (string) -> string, needle: string)
				fs.writeFile(`{W}/{LIST}`, edit(text))
				fixture.git(W, { "commit", "-q", "-am", "a wrong list" })
				local r = tr(W, { "provenance", "freeze", "--check" })
				t.expect(r.ok).toBe(false)
				if not has(r.stderr, needle) then
					error(`--check lacks {needle}: {r.stderr}`)
				end
				fixture.git(W, { "reset", "-q", "--hard", "HEAD~1" })
			end
			broken(function(t0)
				return t0 .. "c0099 aaaaaaaaaaaa\n"
			end, "c0099 is listed")
			broken(function(t0)
				return (string.gsub(t0, "\nc0010 %x+\n", "\nc0010 aaaaaaaaaaaa\n"))
			end, "c0010 is listed at aaaaaaaaaaaa")
			broken(function(t0)
				return (string.gsub(t0, "\nc0020 %x+\n", "\n"))
			end, "c0020 is prepared")
			broken(function(t0)
				return (string.gsub(t0, "\nc0050 %x+\n", "\n"))
			end, "c0050 is prepared")
		end
	)

	it(
		"once the list is on the base it is frozen, and audit holds a listed issue to the listed design",
		function()
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
			-- the list is the base's: a working-tree edit that lists c0040 exempts nothing
			local hash = raftplan.recordHash("c0040", {
				["c0040.md"] = issue("c0040", "prepared-j-k-l", "ready"),
				["check.sh"] = CHECK,
			})
			fs.writeFile(`{W}/{LIST}`, fs.readFile(`{W}/{LIST}`) .. `c0040 {hash}\n`)
			local own = tr(W, { "audit" })
			t.expect(own.ok).toBe(false)
			t.expect(has(own.stdout .. own.stderr, "c0040")).toBe(true)
			fixture.git(W, { "checkout", "--", LIST })
			fs.removeDir(`{W}/{ISSUES}/c0040`)
		end
	)

	it(
		"a list that was on the base and is gone, or does not parse, refuses everything that reads it",
		function()
			local function land(message: string)
				fixture.git(W, { "add", "-A" })
				fixture.git(W, { "commit", "-q", "-m", message })
				fixture.git(W, { "fetch", "-q", "origin" })
				fixture.git(W, { "merge", "-q", "--no-edit", "origin/main" })
				fixture.git(W, { "push", "-q", "origin", "HEAD:main" })
			end
			local function everyoneRefused(why: string)
				local audit = tr(W, { "audit" })
				t.expect(audit.ok).toBe(false)
				local said = audit.stdout .. audit.stderr
				t.expect(has(said, "c0010")).toBe(true)
				t.expect(has(said, "c0020")).toBe(true)
				if not has(said, why) then
					error(`audit lacks {why}: {said}`)
				end
				local plan = tr(W, { "raft-plan" })
				t.expect(has(plan.stdout, "skip c0010")).toBe(true)
				local fold = tr(W, { "fold", "R0100", "c0010" })
				t.expect(fold.ok).toBe(false)
				t.expect(has(fold.stderr, "c0010")).toBe(true)
			end
			-- deleted after it was there: in force with nothing exempt, and audit names the file
			fixture.git(W, { "rm", "-q", LIST })
			land("a PR deletes the list")
			everyoneRefused("exempt-list-gone")
			-- malformed: refuses, and says why
			fs.writeFile(`{W}/{LIST}`, "stray text\n")
			land("a PR garbles the list")
			everyoneRefused("does not parse")
		end
	)
end)
