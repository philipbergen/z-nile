--!strict
-- c0284: the board shows each item's provenance, the same entries `./zn who` prints for it. The history is c0280's
-- (copied: a promoted spec is never shared between tickets): distinct authors in a repository with a bare origin, a
-- reused number, a compaction cut, a root move, a `--no-ff` landing with a trailer on its second parent, a raft.
local board = require("@znile/engine/board")
local boardprov = require("@znile/engine/boardprov")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{fixture.physical(".")}/.cache/c0284-board`
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

return t.spec("c0284 board provenance", function(it)
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
				.. `| 2026-10-05 12:00 | approved | human:Ann | design=aaaaaaaaaaaa; said="<b>x</b> & y" |\n`
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
		fs.writeFile(
			map,
			(if fs.isFile(map) then fs.readFile(map) else "") .. "# c0284 fixture\nc0960 c0060\n"
		)
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
		-- c0075: a second `--no-ff` landing, its top layer carrying another agent's trailer (the second parents of both
		-- merges are read in one process)
		put("c0075", doc("c0075", "R0041", "prepared-a-b-c"))
		commit("Ann", "tracker: new c0075 theta", "2026-10-29T10:00:00Z")
		git(dir, { "checkout", "-q", "-b", "layer2" }, "Dev", "2026-10-29T10:30:00Z")
		fs.writeFile(`{dir}/{IDS}/c0075/note.txt`, "work\n")
		commit(
			"Dev",
			"c0075: theta\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>",
			"2026-10-29T11:00:00Z"
		)
		git(dir, { "checkout", "-q", "main" }, "Gus", "2026-10-29T12:00:00Z")
		git(dir, { "merge", "-q", "--no-ff", "--no-commit", "layer2" }, "Gus", "2026-10-29T12:00:00Z")
		git(dir, { "mv", `{IDS}/c0075`, `{IDS}/done/c0075` }, "Gus", "2026-10-29T12:00:00Z")
		fs.writeFile(`{dir}/{IDS}/done/c0075/c0075.md`, doc("c0075", "R0041", "done-a-b-c"))
		git(dir, { "add", "-A" }, "Gus", "2026-10-29T12:00:00Z")
		git(dir, { "commit", "-q", "-m", "R0041: bind c0075" }, "Gus", "2026-10-29T12:00:00Z")
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
		local made = zn(dir, { "worktree", "board-a" })
		if not made.ok then
			error(made.stdout .. made.stderr)
		end
		W = (string.gsub(made.stdout, "%s+$", ""))
		-- unpublished commits of the worktree, never pushed: a status change of c0020, and c0080, an item that exists
		-- here only (with a stored row). origin/main, the history `who` and the board read, holds neither.
		fs.writeFile(`{W}/{IDS}/c0020/c0020.md`, doc("c0020", "", "preparing-w-w-w"))
		fs.writeDir(`{W}/{IDS}/c0080`)
		fs.writeFile(`{W}/{IDS}/c0080/c0080.md`, doc("c0080", "", "new-w-w-w"))
		fs.writeFile(
			`{W}/{IDS}/c0080/provenance.md`,
			"# Provenance: c0080\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-10-31 09:00 | unblocked | human:Ann | block=x |\n"
		)
		git(W, { "add", "-A" }, "Wip", "2026-11-01T09:00:00Z")
		git(W, { "commit", "-q", "-m", "tracker: c0020 preparing" }, "Wip", "2026-11-01T09:00:00Z")
	end)

	local IDS_ALL = { "c0010", "c0020", "c0030", "c0040", "c0050", "c0060", "c0070", "c0075", "R0020" }

	-- the lines `who` prints for an item
	local function whoLines(id: string): { string }
		local r = zn(W, { "who", id })
		if not r.ok then
			error(`who {id}: {r.stdout}{r.stderr}`)
		end
		local out: { string } = {}
		for line in string.gmatch(r.stdout, "[^\n]+") do
			table.insert(out, line)
		end
		return out
	end
	local function linesOf(entries: any): { string }
		local out: { string } = {}
		for _, e in entries do
			table.insert(out, provenance.line(e))
		end
		return out
	end
	local function pageData(extra: { [string]: string }?, out: string): (any, string)
		local r = fixture.exec(
			W,
			"bash",
			{ "scripts/tracker.sh", "board", "-O", "--out", out },
			{ env = extra or {} }
		)
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local html = fs.readFile(out)
		local json = string.match(html, '<script type="application/json" id="board%-data">(.-)</script>')
		t.expect(json ~= nil).toBe(true)
		return serde.decode("json", json :: string), html
	end
	local function find(node: any, id: string): any
		if type(node) == "table" then
			if node.id == id and node.title ~= nil and node.kind ~= nil then
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

	it(
		"the page carries, for every item, the entries who prints for it, line for line, and writes a Provenance section",
		function()
			local data, html = pageData(nil, `{base}/board.html`)
			for _, id in IDS_ALL do
				local item = find(data, id)
				t.expect(item ~= nil).toBe(true)
				t.expect(item.provenance ~= nil).toBe(true)
				t.expect(linesOf(item.provenance)).toEqual(whoLines(id))
			end
			-- an item that exists in the worktree only (c0080, committed there and never pushed) is not history: `who`
			-- refuses it and the board shows its stored row alone; c0020's unpublished status change is not shown either
			t.expect(zn(W, { "who", "c0080" }).ok).toBe(false)
			t.expect(linesOf(find(data, "c0080").provenance)).toEqual({
				"2026-10-31 09:00  unblocked  human:Ann  block=x  (record)",
			})
			for _, e in find(data, "c0020").provenance do
				t.expect(e.event ~= "status:preparing").toBe(true)
			end
			-- the kinds of item are there, not only the plain life: a stored row, a cut life's mark, a `--no-ff` landing's
			-- merge by the agent trailer of its second parent, and a raft's stored row
			local sources: { [string]: string } = {}
			for _, e in find(data, "c0010").provenance do
				sources[e.event] = e.source
			end
			t.expect(sources.approved).toBe("record")
			t.expect(sources.idea).toBe("git")
			t.expect(has(find(data, "c0060").provenance[1].detail, "not followed")).toBe(true)
			local last = find(data, "c0070").provenance
			t.expect(has(last[#last].actor, "agent:claude-opus-5-5")).toBe(true)
			local raft = find(data, "R0020").provenance
			local stored = ""
			for _, e in raft do
				if e.source == "record" then
					stored = e.event
				end
			end
			t.expect(stored).toBe("unblocked")
			-- the view's script (outside the JSON) writes the section, for an issue and for a raft
			local script =
				string.gsub(html, '<script type="application/json" id="board%-data">.-</script>', "")
			local _, calls = string.gsub(script, "provenanceOf%(", "")
			t.expect(calls >= 3).toBe(true)
			t.expect(has(script, "<h3>Provenance</h3>")).toBe(true)
		end
	)

	it("the model reads the checkout it is given, not the folder it runs in", function()
		local m = board.collect(nil, W)
		local byId: { [string]: any } = {}
		for _, i in m.issues do
			byId[i.id] = i
		end
		for _, r in m.rafts do
			byId[r.id] = r
		end
		for _, id in IDS_ALL do
			t.expect(byId[id] ~= nil and byId[id].provenance ~= nil).toBe(true)
			t.expect(linesOf(byId[id].provenance)).toEqual(whoLines(id))
		end
	end)

	it(
		"the history is read once for any number of items: one mainline log, one people log, one cuts log, one cat-file, one read of every merge's second parent",
		function()
			local trace = `{base}/trace.txt`
			pageData({ GIT_TRACE = trace }, `{base}/board-trace.html`)
			local text = fs.readFile(trace)
			-- each process is matched by the arguments only it has, so another reader of `./zn board` (the heartbeat's
			-- landing log, a stats read) is not counted
			local seen = { mainline = 0, people = 0, cuts = 0, batch = 0, sides = 0, perMerge = 0 }
			for line in string.gmatch(text, "[^\n]+") do
				if has(line, "built-in: git log") then
					if has(line, "%ct %s%n@A") then
						seen.mainline += 1
					elseif has(line, "--format=%ae") then
						seen.people += 1
					elseif has(line, "--diff-filter=AM") then
						seen.cuts += 1
					elseif has(line, "--no-walk") then
						seen.sides += 1
					elseif has(line, "log -1") and has(line, "trailers") then
						seen.perMerge += 1
					end
				elseif has(line, "built-in: git cat-file --batch") then
					seen.batch += 1
				end
			end
			t.expect(seen).toEqual({ mainline = 1, people = 1, cuts = 1, batch = 1, sides = 1, perMerge = 0 })
		end
	)

	it(
		"a record that does not parse is named, its item shows no provenance, the other items are unchanged",
		function()
			local path = `{W}/{IDS}/c0020/provenance.md`
			fs.writeFile(path, "not a record\n")
			local data = pageData(nil, `{base}/board-bad.html`)
			fs.removeFile(path)
			local named = false
			for _, p in (data :: any).problems do
				named = named or has(p, `{IDS}/c0020/provenance.md does not parse`)
			end
			t.expect(named).toBe(true)
			t.expect(find(data, "c0020").provenance).toBe(nil)
			t.expect(linesOf(find(data, "c0010").provenance)).toEqual(whoLines("c0010"))
		end
	)

	it(
		"a tree without git history shows the stored rows alone, and an item with none shows nothing",
		function()
			local plain = `{base}/plain/tracker`
			fs.writeDir(`{plain}/issues/c0001`)
			fs.writeDir(`{plain}/issues/c0002`)
			fs.writeFile(`{plain}/issues/c0001/c0001.md`, doc("c0001", "", "new-a-b-c"))
			fs.writeFile(`{plain}/issues/c0002/c0002.md`, doc("c0002", "", "new-a-b-c"))
			fs.writeFile(
				`{plain}/issues/c0001/provenance.md`,
				"# Provenance: c0001\n\n| when | event | actor | detail |\n|---|---|---|---|\n| 2026-10-05 12:00 | approved | human:Ann | design=aaaaaaaaaaaa |\n"
			)
			local m = board.collect(plain)
			t.expect(m.history).toBe(false)
			t.expect(m.issues[1].id).toBe("c0001")
			t.expect(m.issues[1].provenance ~= nil).toBe(true)
			t.expect(linesOf(m.issues[1].provenance)).toEqual({
				"2026-10-05 12:00  approved  human:Ann  design=aaaaaaaaaaaa  (record)",
			})
			t.expect(m.issues[2].provenance).toBe(nil)
		end
	)

	-- the page's own script, run by node against a fake DOM (as c0118's page spec does): it opens on the item named by
	-- the hash and the pane is read back
	local HARNESS = [==[
const load = m => module["req" + "uire"](m);
const fs = load("fs"), vm = load("vm");
const html = fs.readFileSync(process.argv[2], "utf8"), hash = process.argv[3] || "";
const scripts = [...html.matchAll(/<script([^>]*)>([\s\S]*?)<\/script>/g)];
const els = {};
function el(id) {
  const ls = {}, cl = new Set(), attrs = {};
  return els[id] = { id, innerHTML: "", textContent: "", value: "", scrollTop: 0,
    classList: { add: c => cl.add(c), remove: c => cl.delete(c), contains: c => cl.has(c),
      toggle: (c, f) => { const on = f === undefined ? !cl.has(c) : !!f; on ? cl.add(c) : cl.delete(c); return on; } },
    addEventListener: (t, f) => (ls[t] = ls[t] || []).push(f), dispatch: (t, e) => (ls[t] || []).forEach(f => f(e)),
    setAttribute: (n, v) => (attrs[n] = String(v)), removeAttribute: n => delete attrs[n], hasAttribute: n => n in attrs,
    getAttribute: n => (n in attrs ? attrs[n] : null), focus() {}, blur() {}, select() {}, scrollIntoView() {},
    querySelectorAll: () => [] };
}
["tab-board", "tab-rafts", "tab-issues", "search", "projects", "board", "columns", "charts", "window", "range", "as-of",
 "list", "pane", "board-data", "stats"].forEach(el);
els.board.setAttribute("hidden", "");
els["board-data"].textContent = scripts.find(s => /id="board-data"/.test(s[1]))[2];
const doc = el("document");
const sandbox = { document: { getElementById: i => els[i] || null, querySelector: () => null, addEventListener: doc.addEventListener },
  location: { hash }, history: { replaceState: (a, b, h) => (sandbox.location.hash = h) }, navigator: {},
  console, JSON, Math, String, Array, Object, Number, Date, decodeURIComponent, encodeURIComponent };
sandbox.window = sandbox; sandbox.globalThis = sandbox;
vm.createContext(sandbox);
for (const s of scripts) if (!/type="application\/json"/.test(s[1])) vm.runInContext(s[2], sandbox);
console.log(JSON.stringify({ pane: els.pane.innerHTML }));
]==]
	local function paneOf(page: string, hash: string): string
		fs.writeFile(`{base}/harness.js`, HARNESS)
		local ok, r = pcall(process.exec, "node", { `{base}/harness.js`, page, hash })
		if not ok then
			error(`node is required for this spec: {r}`)
		end
		if not r.ok then
			error(r.stderr)
		end
		return (serde.decode("json", r.stdout) :: any).pane
	end

	it(
		"the item view writes the entries as rows in the model's order, escapes every cell, and draws nothing for an item without any",
		function()
			local data = pageData(nil, `{base}/board-node.html`)
			for _, id in { "c0010", "R0020", "c0080" } do
				local pane = paneOf(`{base}/board-node.html`, `#{id}`)
				t.expect(has(pane, "<h3>Provenance</h3>")).toBe(true)
				local events: { string } = {}
				for event in string.gmatch(pane, "<tr><td>[^<]*</td><td>([^<]*)</td>") do
					table.insert(events, event)
				end
				local want: { string } = {}
				for _, e in find(data, id).provenance do
					table.insert(want, e.event)
				end
				t.expect(events).toEqual(want)
			end
			-- the stored detail holds markup and an ampersand: it is text in the pane
			local pane = paneOf(`{base}/board-node.html`, "#c0010")
			t.expect(has(pane, "said=&quot;&lt;b&gt;x&lt;/b&gt; &amp; y&quot;")).toBe(true)
			t.expect(has(pane, "<b>x</b>")).toBe(false)
			-- an item the model gives no provenance shows no section: c0020's record does not parse
			local path = `{W}/{IDS}/c0020/provenance.md`
			fs.writeFile(path, "not a record\n")
			pageData(nil, `{base}/board-node-bad.html`)
			fs.removeFile(path)
			t.expect(has(paneOf(`{base}/board-node-bad.html`, "#c0020"), "Provenance")).toBe(false)
		end
	)

	it(
		"an issue whose spend.md does not parse shows no provenance, as who refuses it, and is named once",
		function()
			local path = `{W}/{IDS}/c0040/spend.md`
			fs.writeFile(path, "# Spend: c0040 x\n\n| 1 | only | three |\n")
			local data = pageData(nil, `{base}/board-spend.html`)
			fs.removeFile(path)
			local named = 0
			for _, p in (data :: any).problems do
				if has(p, `{IDS}/c0040/spend.md does not parse`) then
					named += 1
				end
			end
			t.expect(named).toBe(1)
			t.expect(find(data, "c0040").provenance).toBe(nil)
			t.expect(linesOf(find(data, "c0010").provenance)).toEqual(whoLines("c0010"))
		end
	)

	it("a shallow clone shows what who prints for it, the truncated log read the same way", function()
		local clone = `{base}/shallow`
		local r = fixture.exec(dir, "git", { "clone", "-q", "--depth", "3", `file://{origin}`, clone })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local out = `{base}/board-shallow.html`
		local built = zn(clone, { "board", "-O", "--out", out })
		if not built.ok then
			error(built.stdout .. built.stderr)
		end
		local html = fs.readFile(out)
		local json = string.match(html, '<script type="application/json" id="board%-data">(.-)</script>')
		local data = serde.decode("json", json :: string)
		t.expect((data :: any).history).toBe(false)
		for _, id in { "c0075", "R0020" } do
			local told = zn(clone, { "who", id })
			t.expect(told.ok).toBe(true)
			local lines: { string } = {}
			for line in string.gmatch(told.stdout, "[^\n]+") do
				table.insert(lines, line)
			end
			t.expect(find(data, id).provenance ~= nil).toBe(true)
			t.expect(linesOf(find(data, id).provenance)).toEqual(lines)
		end
	end)

	it("the buckets are the item folders", function()
		local function c(sha: string, path: string): any
			return { sha = sha, time = 1, subject = "s", status = "M", path = path, order = 1, doc = true }
		end
		local by = boardprov.bucket({
			c("a", "p/.tracker/issues/c0010/c0010.md"),
			c("b", "p/.tracker/issues/done/c0010/c0010.md"),
			c("c", "p/.tracker/rafts/R0001/R0001.md"),
		})
		t.expect(#by.c0010).toBe(2)
		t.expect(#by.R0001).toBe(1)
		t.expect(by.c0010[2].sha).toBe("b")
	end)
end)
