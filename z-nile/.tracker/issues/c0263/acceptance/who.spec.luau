--!strict
-- c0263 AC8, AC9: `./zn who <id>` merges what git says with the record, and the board shows the same. The history is
-- built here with distinct authors in a repository with a bare origin: a capture, status changes, a rafting merge, an
-- unfold, a second rafting, the move to done/ with an agent trailer, and a stored record whose rows win over the git
-- fallbacks. An old item (no record) is answered from git alone, with nothing written.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local serde = require("@lune/serde")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{fixture.physical(".")}/.cache/c0263-who`
local dir, origin = `{base}/main`, `{base}/origin.git`
local IDS = "pickman/.tracker/issues"
local OPUS = "agent:claude-opus-5-5 effort high"

-- every fixture commit has a fixed date, so "oldest first" is a statement about these dates and not the wall clock
local function env(name: string, date: string?): { [string]: string }
	local when = date or "2026-10-20T12:00:00Z"
	return {
		GIT_AUTHOR_NAME = name,
		GIT_AUTHOR_EMAIL = `{name}@example.invalid`,
		GIT_COMMITTER_NAME = name,
		GIT_COMMITTER_EMAIL = `{name}@example.invalid`,
		GIT_AUTHOR_DATE = when,
		GIT_COMMITTER_DATE = when,
		CLAUDECODE = "",
		AI_AGENT = "",
		CLAUDE_EFFORT = "",
		ZN_ACTOR = "",
	}
end
local function git(cwd: string, args: { string }, who: string?, date: string?): string
	local r = fixture.exec(cwd, "git", args, { env = env(who or "Ann", date) })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function zn(cwd: string, args: { string }): Result
	return fixture.exec(cwd, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = env("Zed") })
end
local function commit(who: string, message: string, date: string)
	git(dir, { "add", "-A" }, who, date)
	git(dir, { "commit", "-q", "-m", message }, who, date)
end
local function doc(id: string, raft: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-20\nstatus: {status}\n---\n\n# {id}\n`
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0263 who and the board", function(it)
	local W = ""
	it("builds the history, a bare origin and a worktree", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		process.exec("git", { "init", "-q", "-b", "main", dir })
		engine.copy(root, dir)
		engine.empty(dir)
		fs.writeFile(`{dir}/.gitignore`, ".cache/\n.worktree/\n")
		fs.writeFile(`{dir}/z-nile/next`, "issue 5000 quiet-copper-falcon\nraft 5000 quiet-copper-falcon\n")
		commit("Ann", "seed", "2026-09-01T12:00:00Z")
		local function put(id: string, text: string)
			fs.writeDir(`{dir}/{IDS}/{id}`)
			fs.writeFile(`{dir}/{IDS}/{id}/{id}.md`, text)
		end
		-- c0010: captured by Ann, unblocked by Dee, rafted by Bob (an agent trailer), unfolded by Gus, rafted again by
		-- Fay, delivered by Cy (an agent trailer); a record holds a rafted row and an approval that win over git
		put("c0010", doc("c0010", "", "new-a-b-c"))
		commit("Ann", "tracker: new c0010 alpha", "2026-10-01T09:00:00Z")
		put("c0010", doc("c0010", "", "preparing-a-b-c"))
		commit("Dee", "tracker: c0010 preparing", "2026-10-02T09:00:00Z")
		put("c0010", doc("c0010", "", "new-d-e-f"))
		commit("Dee", "tracker: c0010 new", "2026-10-03T09:00:00Z")
		put("c0010", doc("c0010", "R0010", "prepared-a-b-c"))
		commit("Bob", "tracker: raft R0010 demo\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>", "2026-10-04T09:00:00Z")
		put("c0010", doc("c0010", "", "prepared-a-b-c"))
		commit("Gus", "tracker: unfold c0010", "2026-10-05T09:00:00Z")
		put("c0010", doc("c0010", "R0011", "prepared-a-b-c"))
		commit("Fay", "tracker: raft R0011 again", "2026-10-06T09:00:00Z")
		fs.writeFile(
			`{dir}/{IDS}/c0010/provenance.md`,
			"# Provenance: c0010\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
				.. `| 2026-10-05 12:00 | approved | human:Ann | design=aaaaaaaaaaaa; said="ok" |\n`
				.. `| 2026-10-06 09:30 | rafted | {OPUS} | raft=R0011 |\n`
		)
		-- the spend ledger: a deliver row with the model that spent it (c0254 will add host and CLI)
		fs.writeFile(
			`{dir}/{IDS}/c0010/spend.md`,
			ledger.render("c0010", "alpha", {
				{ when = "2026-10-06 10:00", subject = "work", added = 1, removed = 0, minutes = 1, how = "focus", phase = "deliver", tokens = 5, model = "claude-opus-5-5-high" },
			})
		)
		commit("Fay", "tracker: record c0010", "2026-10-06T09:40:00Z")
		fs.writeDir(`{dir}/{IDS}/done`)
		git(dir, { "mv", `{IDS}/c0010`, `{IDS}/done/c0010` }, "Cy", "2026-10-07T09:00:00Z")
		commit("Cy", "R0011: demo (#1)\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>", "2026-10-07T09:00:00Z")
		-- c0020: an old backlog item, captured by Eve, no record
		put("c0020", doc("c0020", "", "new-a-b-c"))
		commit("Eve", "tracker: new c0020 beta", "2026-10-08T09:00:00Z")
		-- c0030: a number that was reused. Zoe's item is gone; Yan's is a new life whose history starts at its add
		put("c0030", doc("c0030", "", "preparing-z-z-z"))
		commit("Zoe", "tracker: new c0030 first-life", "2026-10-09T09:00:00Z")
		put("c0030", doc("c0030", "", "new-z-z-y"))
		commit("Zoe", "tracker: c0030 new", "2026-10-09T10:00:00Z")
		git(dir, { "rm", "-rq", `{IDS}/c0030` }, "Zoe", "2026-10-10T09:00:00Z")
		commit("Zoe", "tracker: drop c0030", "2026-10-10T09:00:00Z")
		put("c0030", doc("c0030", "", "new-y-y-y"))
		commit("Yan", "tracker: new c0030 second-life", "2026-10-11T09:00:00Z")
		-- c0040: its capture commit does not name it (renumbered), and two give-backs: an old one with no record, and a
		-- newer one whose commit also appends the stored row
		put("c0040", doc("c0040", "", "new-a-b-c"))
		commit("Rex", "tracker: rename ids (#9)", "2026-10-12T09:00:00Z")
		put("c0040", doc("c0040", "", "new-b-b-b"))
		commit("Dee", "tracker: c0040 new", "2026-10-13T09:00:00Z")
		put("c0040", doc("c0040", "", "new-c-c-c"))
		fs.writeFile(
			`{dir}/{IDS}/c0040/provenance.md`,
			"# Provenance: c0040\n\n| when | event | actor | detail |\n|---|---|---|---|\n"
				.. "| 2026-10-14 09:00 | unblocked | human:Fay | block=design-gap |\n"
		)
		commit("Fay", "tracker: c0040 new", "2026-10-14T09:00:00Z")
		-- c0050: rafted by Bob, readied by Hal (a move to active/), merged by Cy (a move to done/); no stored row
		put("c0050", doc("c0050", "", "new-a-b-c"))
		commit("Ann", "tracker: new c0050 epsilon", "2026-10-15T09:00:00Z")
		put("c0050", doc("c0050", "R0020", "prepared-a-b-c"))
		commit("Bob", "tracker: raft R0020 epsilon", "2026-10-16T09:00:00Z")
		fs.writeDir(`{dir}/{IDS}/active`)
		git(dir, { "mv", `{IDS}/c0050`, `{IDS}/active/c0050` }, "Hal", "2026-10-17T09:00:00Z")
		commit("Hal", "tracker: ready R0020 epsilon", "2026-10-17T09:00:00Z")
		git(dir, { "mv", `{IDS}/active/c0050`, `{IDS}/done/c0050` }, "Cy", "2026-10-18T09:00:00Z")
		commit("Cy", "R0020: epsilon (#3)", "2026-10-18T09:00:00Z")
		process.exec("git", { "clone", "-q", "--bare", dir, origin })
		git(dir, { "remote", "add", "origin", origin })
		git(dir, { "fetch", "-q", "origin" })
		git(dir, { "branch", "-q", "--set-upstream-to=origin/main", "main" })
		local made = zn(dir, { "worktree", "who-a" })
		if not made.ok then
			error(made.stdout .. made.stderr)
		end
		W = (string.gsub(made.stdout, "%s+$", ""))
	end)

	it("who prints the derived entries and the record, oldest first by date, the record winning over a git fallback", function()
		local before = git(W, { "status", "--porcelain" })
		local r = zn(W, { "who", "c0010" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local out = r.stdout
		t.expect(has(out, "idea  human:Ann (from git)")).toBe(true)
		t.expect(has(out, "status:preparing  human:Dee (from git)")).toBe(true)
		-- a `tracker: c0010 new` commit is the unblock (once, never also a status line), and no row is stored for it
		t.expect(has(out, "unblocked  human:Dee (from git)")).toBe(true)
		t.expect(has(out, "status:new")).toBe(false)
		-- the stored approval is the human's and its design hash; the stored rafted row beats the git rafter (Fay)
		t.expect(has(out, "approved  human:Ann")).toBe(true)
		t.expect(has(out, "design=aaaaaaaaaaaa")).toBe(true)
		t.expect(has(out, `rafted  {OPUS}`)).toBe(true)
		t.expect(has(out, "rafted  human:Fay")).toBe(false)
		-- a delivery nothing recorded comes from the done commit, the agent that merged it, with the worker read from
		-- the ticket's spend rows
		t.expect(has(out, "delivered  agent:claude-sonnet-5-5 effort unknown (from git)")).toBe(true)
		t.expect(has(out, "worker=claude-opus-5-5-high")).toBe(true)
		-- and who merged it is a derived entry of its own
		t.expect(has(out, "merged  human:Cy (from git)")).toBe(true)
		-- oldest first, by the dates the fixture set
		local order: { string } = {}
		for line in string.gmatch(out, "[^\n]+") do
			local event = string.match(line, "^%S+ %S+%s+(%S+)")
			if event then
				table.insert(order, event)
			end
		end
		t.expect(order).toEqual({ "idea", "status:preparing", "unblocked", "approved", "rafted", "delivered", "merged" })
		-- it reads and writes nothing
		t.expect(git(W, { "status", "--porcelain" })).toBe(before)
	end)

	it("an old item with no record is answered from git alone, and who runs in the main checkout", function()
		local r = zn(dir, { "who", "c0020" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "idea  human:Eve (from git)")).toBe(true)
		t.expect(fs.isFile(`{dir}/{IDS}/c0020/provenance.md`)).toBe(false)
		t.expect(zn(dir, { "who", "c0099" }).ok).toBe(false)
	end)

	it("an idea taken from a first add says so, and a give-back is covered per commit, not per event", function()
		local r = zn(W, { "who", "c0040" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "idea  human:Rex (from git, first add)")).toBe(true)
		-- the old give-back has no stored row: derived; the newer one's commit also wrote the row: stored, not repeated
		t.expect(has(r.stdout, "unblocked  human:Dee (from git)")).toBe(true)
		t.expect(has(r.stdout, "unblocked  human:Fay  block=design-gap  (record)")).toBe(true)
		local _, n = string.gsub(r.stdout, "unblocked", "")
		t.expect(n).toBe(2)
	end)

	it("the rafter of an old item is who made raft: the current value, not the readier or the merger", function()
		local r = zn(W, { "who", "c0050" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "rafted  human:Bob (from git)  raft=R0020")).toBe(true)
		t.expect(has(r.stdout, "rafted  human:Hal")).toBe(false)
		t.expect(has(r.stdout, "rafted  human:Cy")).toBe(false)
		t.expect(has(r.stdout, "merged  human:Cy (from git)")).toBe(true)
	end)

	it("a reused number is a new life: nothing of the first leaks into who", function()
		local r = zn(W, { "who", "c0030" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "idea  human:Yan (from git)")).toBe(true)
		t.expect(has(r.stdout, "Zoe")).toBe(false)
		t.expect(has(r.stdout, "unblocked")).toBe(false)
	end)

	it("the board model carries the same entries as who, and the item view writes a Provenance section", function()
		local page = `{base}/board.html`
		local r = zn(W, { "board", "-O", "--out", page })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local html = fs.readFile(page)
		local json = string.match(html, '<script type="application/json" id="board%-data">(.-)</script>')
		t.expect(json ~= nil).toBe(true)
		local data = serde.decode("json", json :: string)
		-- find an item's model wherever the board keeps its issues
		local function find(node: any, id: string): any
			if type(node) == "table" then
				if node.id == id and node.provenance ~= nil then
					return node
				end
				for _, v in node do
					local hit = find(v, id)
					if hit then
						return hit
					end
				end
			end
			return nil
		end
		-- the whole entries, not their names, for each kind of item: one that needs nothing but its log (c0010), a
		-- reused number (c0030), an idea from a first add with a stored and a derived give-back (c0040), and an old
		-- item with no record (c0050). The board reads the same life as who (the same cut, the same people); it leaves
		-- out the one entry that needs a read per commit, the derived `rafted` fallback, which only who prints.
		local expected: { [string]: { string } } = {
			c0010 = {
				"idea|human:Ann (from git)||git",
				"status:preparing|human:Dee (from git)||git",
				"unblocked|human:Dee (from git)||git",
				'approved|human:Ann|design=aaaaaaaaaaaa; said="ok"|record',
				`rafted|{OPUS}|raft=R0011|record`,
				"delivered|agent:claude-sonnet-5-5 effort unknown (from git)|raft=R0011; worker=claude-opus-5-5-high|git",
				"merged|human:Cy (from git)||git",
			},
			c0030 = { "idea|human:Yan (from git)||git" },
			c0040 = {
				"idea|human:Rex (from git, first add)||git",
				"unblocked|human:Dee (from git)||git",
				"unblocked|human:Fay|block=design-gap|record",
			},
			c0050 = {
				"idea|human:Ann (from git)||git",
				"delivered|human:Cy (from git)|raft=R0020|git",
				"merged|human:Cy (from git)||git",
			},
		}
		for id, want in expected do
			local item = find(data, id)
			t.expect(item ~= nil).toBe(true)
			local got: { string } = {}
			for _, e in item.provenance do
				table.insert(got, `{e.event}|{e.actor}|{e.detail}|{e.source}`)
			end
			t.expect(got).toEqual(want)
		end
		-- the view's script (outside the JSON) writes the section
		local script = string.gsub(html, '<script type="application/json" id="board%-data">.-</script>', "")
		t.expect(has(script, "Provenance")).toBe(true)
	end)
end)
