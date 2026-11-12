--!strict
-- c0280: `./zn who <id>` merges what git says with the record. The history is
-- built here with distinct authors in a repository with a bare origin: a capture, status changes, a rafting merge, an
-- unfold, a second rafting, the move to done/ with an agent trailer, and a stored record whose rows win over the git
-- fallbacks. An old item (no record) is answered from git alone, with nothing written.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{fixture.physical(".")}/.cache/c0280-who`
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

return t.spec("c0280 who", function(it)
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
		commit(
			"Bob",
			"tracker: raft R0010 demo\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
			"2026-10-04T09:00:00Z"
		)
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
				{
					when = "2026-10-06 10:00",
					subject = "work",
					added = 1,
					removed = 0,
					minutes = 1,
					how = "focus",
					phase = "deliver",
					tokens = 5,
					model = "claude-opus-5-5-high",
				},
			})
		)
		commit("Fay", "tracker: record c0010", "2026-10-06T09:40:00Z")
		fs.writeDir(`{dir}/{IDS}/done`)
		git(dir, { "mv", `{IDS}/c0010`, `{IDS}/done/c0010` }, "Cy", "2026-10-07T09:00:00Z")
		commit(
			"Cy",
			"R0011: demo (#1)\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>",
			"2026-10-07T09:00:00Z"
		)
		-- c0020: an old backlog item, captured by Eve, no record
		put("c0020", doc("c0020", "", "new-a-b-c"))
		-- a trailer is never read for the idea
		commit(
			"Eve",
			"tracker: new c0020 beta\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
			"2026-10-08T09:00:00Z"
		)
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
		put("c0040", doc("c0040", "", "preparing-a-b-c"))
		commit("Rex", "tracker: rename ids (#9)", "2026-10-12T09:00:00Z")
		put("c0040", doc("c0040", "", "new-b-b-b"))
		commit("Dee", "tracker: c0040 new", "2026-10-13T09:00:00Z")
		put("c0040", doc("c0040", "", "preparing-b-b-b"))
		commit("Dee", "tracker: c0040 preparing", "2026-10-13T12:00:00Z")
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
		-- a Signed-off-by trailer is no agent, and a Co-Authored-By whose email is a commit author's (Ann, in other
		-- letters; Eve, who only ever committed c0020) is a person: the rafter stays Bob
		commit(
			"Bob",
			"tracker: raft R0020 epsilon\n\nSigned-off-by: Bob Jr <bobjr@elsewhere.invalid>\nCo-Authored-By: Ann <ANN@example.invalid>\nCo-Authored-By: Eve <eve@example.invalid>",
			"2026-10-16T09:00:00Z"
		)
		fs.writeDir(`{dir}/{IDS}/active`)
		git(dir, { "mv", `{IDS}/c0050`, `{IDS}/active/c0050` }, "Hal", "2026-10-17T09:00:00Z")
		fs.writeFile(`{dir}/{IDS}/active/c0050/c0050.md`, doc("c0050", "R0020", "active-a-b-c"))
		commit("Hal", "tracker: ready R0020 epsilon", "2026-10-17T09:00:00Z")
		git(dir, { "mv", `{IDS}/active/c0050`, `{IDS}/done/c0050` }, "Cy", "2026-10-18T09:00:00Z")
		commit("Cy", "R0020: epsilon (#3)", "2026-10-18T09:00:00Z")
		-- c0060: a life cut at a compaction (one commit rewrites the document and the map), readied, delivered, and its done
		-- folder moved to another root afterwards
		put("c0060", doc("c0060", "", "new-a-b-c"))
		commit("Ann", "tracker: new c0060 zeta", "2026-10-22T09:00:00Z")
		put("c0060", doc("c0060", "R0030", "prepared-a-b-c"))
		local map = `{dir}/z-nile/compaction.txt`
		fs.writeFile(map, (if fs.isFile(map) then fs.readFile(map) else "") .. "# c0280 fixture\n")
		commit(
			"Phil",
			"tracker: compact ids (#64)\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
			"2026-10-23T09:00:00Z"
		)
		git(dir, { "mv", `{IDS}/c0060`, `{IDS}/active/c0060` }, "Hal", "2026-10-24T09:00:00Z")
		fs.writeFile(`{dir}/{IDS}/active/c0060/c0060.md`, doc("c0060", "R0030", "active-a-b-c"))
		commit("Hal", "tracker: ready R0030 zeta", "2026-10-24T09:00:00Z")
		git(dir, { "mv", `{IDS}/active/c0060`, `{IDS}/done/c0060` }, "Cy", "2026-10-25T09:00:00Z")
		commit("Cy", "R0030: zeta (#4)", "2026-10-25T09:00:00Z")
		fs.writeDir(`{dir}/z-nile/.tracker/issues/done`)
		git(
			dir,
			{ "mv", `{IDS}/done/c0060`, "z-nile/.tracker/issues/done/c0060" },
			"Rex",
			"2026-10-26T09:00:00Z"
		)
		commit("Rex", "R0043: z-nile 2, the tracker moves into z-nile", "2026-10-26T09:00:00Z")
		-- c0070: landed by a `--no-ff` merge whose top layer commit carries the agent's trailer and the merge commit
		-- none; the merge commit is what brings the document into done/
		put("c0070", doc("c0070", "R0040", "prepared-a-b-c"))
		commit("Ann", "tracker: new c0070 eta", "2026-10-27T09:00:00Z")
		git(dir, { "checkout", "-q", "-b", "layer" }, "Dev", "2026-10-28T09:00:00Z")
		fs.writeFile(`{dir}/{IDS}/c0070/note.txt`, "work\n")
		commit(
			"Dev",
			"c0070: eta\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>",
			"2026-10-28T10:00:00Z"
		)
		git(dir, { "checkout", "-q", "main" }, "Gus", "2026-10-29T09:00:00Z")
		git(dir, { "merge", "-q", "--no-ff", "--no-commit", "layer" }, "Gus", "2026-10-29T09:00:00Z")
		git(dir, { "mv", `{IDS}/c0070`, `{IDS}/done/c0070` }, "Gus", "2026-10-29T09:00:00Z")
		fs.writeFile(`{dir}/{IDS}/done/c0070/c0070.md`, doc("c0070", "R0040", "done-a-b-c"))
		git(dir, { "add", "-A" }, "Gus", "2026-10-29T09:00:00Z")
		git(dir, { "commit", "-q", "-m", "R0040: bind c0070" }, "Gus", "2026-10-29T09:00:00Z")
		-- R0020: a done raft whose spend.md is a roll-up of its issues, with a stored row
		local raftDir = `{dir}/pickman/.tracker/rafts`
		fs.writeDir(`{raftDir}/R0020`)
		fs.writeFile(
			`{raftDir}/R0020/R0020.md`,
			"---\nid: R0020\nslug: epsilon-raft\nstatus: active-a-b-c\n---\n\n# R0020\n"
		)
		commit("Raf", "tracker: new raft R0020 epsilon", "2026-10-30T09:00:00Z")
		fs.writeDir(`{raftDir}/done`)
		git(
			dir,
			{ "mv", `pickman/.tracker/rafts/R0020`, "pickman/.tracker/rafts/done/R0020" },
			"Cy",
			"2026-10-31T09:00:00Z"
		)
		fs.writeFile(
			`{raftDir}/done/R0020/spend.md`,
			"# Spend: R0020 epsilon\n\n| issue | type | emergent | +lines | -lines | minutes | tokens |\n|---|---|---|---|---|---|---|\n| c0050 | chore | no | 1 | 0 | 1.0 | 0 |\n"
		)
		fs.writeFile(
			`{raftDir}/done/R0020/provenance.md`,
			"# Provenance: R0020\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-10-30 12:00 | unblocked | human:Ann | block=x |\n"
		)
		commit("Cy", "R0020: epsilon (#3)", "2026-10-31T09:00:00Z")
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

	it(
		"who prints the derived entries and the record, oldest first by date, the record winning over a git fallback",
		function()
			local before = git(W, { "status", "--porcelain" })
			local r = zn(W, { "who", "c0010" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			local out = r.stdout
			-- one line is `<when>  <event>  <actor>  <detail>  (<source>)`, the detail left out when empty
			t.expect(has(out, "2026-10-01 09:00  idea  human:Ann (from git)  (git)\n")).toBe(true)
			t.expect(has(out, "status:preparing  human:Dee (from git)")).toBe(true)
			-- a status change by a commit that is not a `tracker: <id> <word>` publish (a prep PR's squash, with an agent
			-- trailer) is read from the document's own status word
			t.expect(has(out, "status:prepared  agent:claude-opus-5-5 effort unknown (from git)")).toBe(true)
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
			-- and the merge is a derived entry of its own: the same commit's agent trailer, the user's rule
			t.expect(has(out, "merged  agent:claude-sonnet-5-5 effort unknown (from git)")).toBe(true)
			-- oldest first, by the dates the fixture set
			local order: { string } = {}
			for line in string.gmatch(out, "[^\n]+") do
				local event = string.match(line, "^%S+ %S+%s+(%S+)")
				if event then
					table.insert(order, event)
				end
			end
			t.expect(order).toEqual({
				"idea",
				"status:preparing",
				"unblocked",
				"status:prepared",
				"approved",
				"rafted",
				"delivered",
				"merged",
			})
			-- it reads and writes nothing
			t.expect(git(W, { "status", "--porcelain" })).toBe(before)
		end
	)

	it("an old item with no record is answered from git alone, and who runs in the main checkout", function()
		local r = zn(dir, { "who", "c0020" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "idea  human:Eve (from git)")).toBe(true)
		t.expect(fs.isFile(`{dir}/{IDS}/c0020/provenance.md`)).toBe(false)
		t.expect(zn(dir, { "who", "c0099" }).ok).toBe(false)
	end)

	it(
		"an idea taken from a first add says so, and a give-back is covered per commit, not per event",
		function()
			local r = zn(W, { "who", "c0040" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "idea  human:Rex (from git, first add)")).toBe(true)
			-- the old give-back has no stored row: derived; the newer one's commit also wrote the row: stored, not repeated
			t.expect(has(r.stdout, "unblocked  human:Dee (from git)")).toBe(true)
			t.expect(has(r.stdout, "unblocked  human:Fay  block=design-gap  (record)")).toBe(true)
			local _, n = string.gsub(r.stdout, "unblocked", "")
			t.expect(n).toBe(2)
		end
	)

	it(
		"the rafter of an old item is who made raft: the current value, not the readier or the merger",
		function()
			local r = zn(W, { "who", "c0050" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "rafted  human:Bob (from git)  raft=R0020")).toBe(true)
			t.expect(has(r.stdout, "rafted  human:Hal")).toBe(false)
			t.expect(has(r.stdout, "rafted  human:Cy")).toBe(false)
			-- the readier's status change is read from the document (a move to active/ that set the word), and a landing
			-- with no agent trailer has no merge actor
			t.expect(has(r.stdout, "status:active  human:Hal (from git)")).toBe(true)
			t.expect(has(r.stdout, "delivered  human:Cy (from git)  raft=R0020")).toBe(true)
			t.expect(has(r.stdout, "merged  unknown  (git)")).toBe(true)
			-- a trailer whose email is an author's elsewhere (Eve's only commits are another item's) is a person
			t.expect(has(r.stdout, "agent:eve")).toBe(false)
		end
	)

	it("a reused number is a new life: nothing of the first leaks into who", function()
		local r = zn(W, { "who", "c0030" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "idea  human:Yan (from git)")).toBe(true)
		t.expect(has(r.stdout, "Zoe")).toBe(false)
		t.expect(has(r.stdout, "unblocked")).toBe(false)
	end)

	it(
		"a life cut at a compaction says so, derives only the marked idea, and a later root move is no delivery",
		function()
			local r = zn(W, { "who", "c0060" })
			t.expect(r.ok).toBe(true)
			-- the commit that starts the followed history is the marked idea; nothing before it, no rafter from it
			t.expect(has(r.stdout, "idea  human:Phil (from git, first add)  history before ")).toBe(true)
			t.expect(has(r.stdout, "not followed: it changed z-nile/compaction.txt")).toBe(true)
			t.expect(has(r.stdout, "human:Ann")).toBe(false)
			t.expect(has(r.stdout, "rafted")).toBe(false)
			t.expect(has(r.stdout, "status:active  human:Hal (from git)")).toBe(true)
			-- the delivery is the first arrival in done/ (Cy), not the move into another root afterwards (Rex)
			t.expect(has(r.stdout, "delivered  human:Cy (from git)  raft=R0030")).toBe(true)
			t.expect(has(r.stdout, "Rex")).toBe(false)
			local _, n = string.gsub(r.stdout, "delivered", "")
			t.expect(n).toBe(1)
		end
	)

	it(
		"a --no-ff landing is the first-parent merge commit, with its second parent's agent trailer",
		function()
			local r = zn(W, { "who", "c0070" })
			t.expect(r.ok).toBe(true)
			t.expect(
				has(
					r.stdout,
					"2026-10-29 09:00  delivered  agent:claude-opus-5-5 effort unknown (from git)  raft=R0040"
				)
			).toBe(true)
			t.expect(
				has(r.stdout, "2026-10-29 09:00  merged  agent:claude-opus-5-5 effort unknown (from git)")
			)
				.toBe(true)
		end
	)

	it(
		"a raft is answered from git and its record, and its roll-up spend.md is not read as a ledger",
		function()
			local r = zn(W, { "who", "R0020" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(has(r.stdout, "idea  human:Raf (from git, first add)")).toBe(true)
			t.expect(has(r.stdout, "unblocked  human:Ann  block=x  (record)")).toBe(true)
			t.expect(has(r.stdout, "delivered  human:Cy (from git)")).toBe(true)
			t.expect(has(r.stdout, "worker=")).toBe(false)
		end
	)

	it("who reads the published history only, and an item with no published history is refused", function()
		-- a commit this worktree has and origin/main lacks is not history yet
		local doc20 = fs.readFile(`{W}/{IDS}/c0020/c0020.md`)
		fs.writeFile(
			`{W}/{IDS}/c0020/c0020.md`,
			(string.gsub(doc20, "status: new%-a%-b%-c", "status: preparing-q-q-q"))
		)
		git(W, { "add", "-A" }, "Loc", "2026-11-01T09:00:00Z")
		git(W, { "commit", "-q", "-m", "tracker: c0020 preparing" }, "Loc", "2026-11-01T09:00:00Z")
		local local1 = zn(W, { "who", "c0020" })
		git(W, { "reset", "-q", "--hard", "origin/main" })
		t.expect(local1.ok).toBe(true)
		t.expect(has(local1.stdout, "Loc")).toBe(false)
		-- an item that only exists in the working tree
		fs.writeDir(`{W}/{IDS}/c0099`)
		fs.writeFile(`{W}/{IDS}/c0099/c0099.md`, doc("c0099", "", "new-a-b-c"))
		local r = zn(W, { "who", "c0099" })
		fs.removeDir(`{W}/{IDS}/c0099`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "no history for c0099")).toBe(true)
		t.expect(has(r.stdout, "idea")).toBe(false)
	end)

	it("a spend.md that does not parse is refused naming the file", function()
		fs.writeFile(`{W}/{IDS}/c0020/spend.md`, "# Spend: c0020 beta\n\n| 1 | only | three |\n")
		local r = zn(W, { "who", "c0020" })
		fs.removeFile(`{W}/{IDS}/c0020/spend.md`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "c0020/spend.md")).toBe(true)
	end)

	it("a record that does not parse is refused naming the file, and nothing is printed", function()
		fs.writeFile(`{W}/{IDS}/c0020/provenance.md`, "not a record\n")
		local r = zn(W, { "who", "c0020" })
		fs.removeFile(`{W}/{IDS}/c0020/provenance.md`)
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "c0020/provenance.md")).toBe(true)
		t.expect(has(r.stdout, "idea")).toBe(false)
	end)
end)
