--!strict
-- c0161 AC7, "Check at next read": a prepared issue whose newest design review round quotes a record must still match it
-- as the issue is on origin/main when `new raft`, `fold`, `recombine` (the last two share one check) or `ready` reads it, so
-- a design edited after the move to prepared (a gate fix, a PR answer, a conflict resolved in the document) is caught
-- before the issue is rafted or readied. An issue none of whose rounds quotes a record was prepared by an engine that
-- predates the rule and is exempt. Fixture under .cache/c0161-review-read (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local f: trackerfix.Fixture
local wt = ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function issueDoc(id: string, body: string, raft: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft or ""}\ndepends_on: []\nemergent: false\ndesign: ready\nsize: 10\ncreated: 2026-01-01\nstatus: {PREPARED}\n---\n\n# {id}\n{body}`
end
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Raft\nslug: raft\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-01-01\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Theme\nOne.\n\n## Order & dependencies\nBy id.\n\n## Risks & rollback\n`
end
local function quoted(id: string, doc: string, check: string?): string
	return raftplan.designRecord(id, { [`{id}.md`] = doc, ["check.sh"] = check or CHECK })
end
local function approve(hash: string): string
	return `# Review 001\n\nVerdict: approve\n\nDesign record: {hash}\n`
end
local function path(id: string, name: string): string
	return `pickman/.tracker/issues/{id}/{name}`
end
local EDITED = "\n## Design\nOne.\n\n## Design\nEdited after the round.\n"
-- the raft: line of an issue's document in the rafting worktree (the accepted result of new raft, fold and recombine)
local function raftOf(id: string): string
	return string.match(fs.readFile(`{wt}/{path(id, `{id}.md`)}`), "\nraft: ([^\n]*)\n") or "?"
end
-- raft-plan's output by id: the ids named in a line that starts `./zn ` (planned) and in a line that starts `skip <id>:`.
-- A take assertion needs both sides, because a skip line names the id in its reason too (design review 006 F1).
local function plan(stdout: string): ({ [string]: boolean }, { [string]: boolean })
	local planned: { [string]: boolean } = {}
	local skipped: { [string]: boolean } = {}
	for line in string.gmatch(stdout, "[^\n]+") do
		if string.sub(line, 1, 5) == "./zn " then
			for token in string.gmatch(line, "%S+") do
				planned[token] = true
			end
		else
			local id = string.match(line, "^skip (%S+):")
			if id then
				skipped[id] = true
			end
		end
	end
	return planned, skipped
end
local function planTakes(stdout: string, id: string)
	local planned, skipped = plan(stdout)
	if not planned[id] or skipped[id] then
		error(`raft-plan should plan {id} in a ./zn line and not skip it: {stdout}`, 2)
	end
end
local function planSkips(stdout: string, id: string)
	local planned, skipped = plan(stdout)
	if planned[id] or not skipped[id] then
		error(`raft-plan should skip {id} and not plan it: {stdout}`, 2)
	end
end
local function push(files: { [string]: string }, message: string)
	trackerfix.elsewhere(f, files, message)
	trackerfix.trOk(f, wt, { "sync" })
end
local function refused(args: { string }, ...: string)
	local r = trackerfix.tr(f, wt, args)
	t.expect(r.ok).toBe(false)
	for _, needle in { ... } do
		if not has(r.stderr, needle) then
			error(`{table.concat(args, " ")}: stderr lacks {needle}: {r.stderr}`, 2)
		end
	end
end

return t.spec("c0161 a prepared issue is checked against its quoted record when it is next read", function(it)
	it("sets up a fixture, a prep worktree and prepared issues with and without a quoted round", function()
		f = trackerfix.new("c0161-review-read", nil)
		wt = trackerfix.trOk(f, f.main, { "worktree", "prep-read" })
		local files: { [string]: string } = {}
		for _, id in { "c0950", "c0951", "c0953", "c0954" } do
			local doc = issueDoc(id, "\n## Design\nOne.\n")
			files[path(id, `{id}.md`)] = doc
			files[path(id, "check.sh")] = CHECK
			files[path(id, "design-review-001.md")] = approve(quoted(id, doc))
		end
		-- c0952: prepared before the rule, no round at all
		files[path("c0952", "c0952.md")] = issueDoc("c0952", "\n## Design\nOne.\n")
		files[path("c0952", "check.sh")] = CHECK
		-- a prepared backlog raft for `fold`
		files["pickman/.tracker/rafts/R0960/R0960.md"] = raftDoc("R0960", "")
		files["pickman/.tracker/rafts/R0960/check.sh"] = CHECK
		push(files, "prepared issues with quoted rounds")
		-- c0951 and c0954 are edited after their rounds: a post-move edit
		push({
			[path("c0951", "c0951.md")] = issueDoc(
				"c0951",
				"\n## Design\nOne.\n\n## Design\nEdited after the round.\n"
			),
			[path("c0954", "c0954.md")] = issueDoc(
				"c0954",
				"\n## Design\nOne.\n\n## Design\nEdited after the round.\n"
			),
		}, "design edits after the move to prepared")
		-- more prepared issues, in prepared rafts, for `ready`, `recombine` and a local edit that is not on origin
		local more: { [string]: string } = {}
		local rafts: { [string]: string } =
			{ c0956 = "R0962", c0957 = "R0970", c0958 = "R0971", c0959 = "R0971" }
		for id, raft in rafts do
			local doc = issueDoc(id, "\n## Design\nOne.\n", raft)
			-- c0956's check.sh names its own backlog folder, which `ready` rewrites when it moves the item
			local check = if id == "c0956" then `# pickman/.tracker/issues/{id}\n{CHECK}` else CHECK
			more[path(id, `{id}.md`)] = doc
			more[path(id, "check.sh")] = check
			more[path(id, "design-review-001.md")] = approve(quoted(id, doc, check))
		end
		local doc61 = issueDoc("c0961", "\n## Design\nOne.\n")
		more[path("c0961", "c0961.md")] = doc61
		more[path("c0961", "check.sh")] = CHECK
		more[path("c0961", "design-review-001.md")] = approve(quoted("c0961", doc61))
		-- c0965 stays raftless: a committed local edit to it (not on origin) must not make raft-plan skip it
		local doc65 = issueDoc("c0965", "\n## Design\nOne.\n")
		more[path("c0965", "c0965.md")] = doc65
		more[path("c0965", "check.sh")] = CHECK
		more[path("c0965", "design-review-001.md")] = approve(quoted("c0965", doc65))
		-- c0966 and c0967: rafted by the end-to-end recovery cases; c0968: taken by new raft after round 002
		for _, id in { "c0966", "c0967", "c0968" } do
			local d = issueDoc(id, "\n## Design\nOne.\n")
			more[path(id, `{id}.md`)] = d
			more[path(id, "check.sh")] = CHECK
			more[path(id, "design-review-001.md")] = approve(quoted(id, d))
		end
		more["pickman/.tracker/rafts/R0962/R0962.md"] = raftDoc("R0962", "c0956")
		more["pickman/.tracker/rafts/R0962/check.sh"] = CHECK
		more["pickman/.tracker/rafts/R0970/R0970.md"] = raftDoc("R0970", "c0957")
		more["pickman/.tracker/rafts/R0970/check.sh"] = CHECK
		more["pickman/.tracker/rafts/R0971/R0971.md"] = raftDoc("R0971", "c0958, c0959")
		more["pickman/.tracker/rafts/R0971/check.sh"] = CHECK
		push(more, "prepared rafts with quoted members")
		-- c0959 is edited after its round
		push({
			[path("c0959", "c0959.md")] = issueDoc(
				"c0959",
				"\n## Design\nOne.\n\n## Design\nEdited after the round.\n",
				"R0971"
			),
		}, "c0959 edited after its round")
	end)

	it(
		"raft-plan skips a stale prepared issue and plans, in a command line, each matching or exempt one",
		function()
			local r = trackerfix.tr(f, wt, { "raft-plan" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "skip c0951: is prepared on origin/main but design-review-001.md"))
				.toBe(true)
			-- per id: a stale issue is skipped and never in a command (so --apply cannot stop half way on it) ...
			planSkips(r.stdout, "c0951")
			planSkips(r.stdout, "c0954")
			-- ... and each matching quoted issue and the exempt one is in a ./zn line and on no skip line (the plan groups them,
			-- so no exact line is pinned)
			for _, id in { "c0950", "c0952", "c0953", "c0961", "c0965" } do
				planTakes(r.stdout, id)
			end
		end
	)

	it(
		"new raft refuses an issue edited after its quoted round, naming the issue and the file, and takes a matching one",
		function()
			refused(
				{ "new", "raft", "chore", "stale-one", "c0951", "--project", "pickman" },
				"c0951",
				"design-review-001.md",
				"prepared on origin/main"
			)
			t.expect(raftOf("c0950")).toBe("")
			trackerfix.trOk(f, wt, { "new", "raft", "chore", "fresh-one", "c0950", "--project", "pickman" })
			t.expect(string.match(raftOf("c0950"), "^R%d+$") ~= nil).toBe(true)
			t.expect(raftOf("c0951")).toBe("")
		end
	)

	it("an issue no round of which quotes a record predates the rule and is rafted as before", function()
		trackerfix.trOk(f, wt, { "new", "raft", "chore", "exempt-one", "c0952", "--project", "pickman" })
		t.expect(string.match(raftOf("c0952"), "^R%d+$") ~= nil).toBe(true)
	end)

	it(
		"fold (and recombine, through the same check) refuses a stale issue and folds a matching or an exempt one",
		function()
			refused({ "fold", "R0960", "c0954" }, "c0954", "design-review-001.md", "prepared on origin/main")
			t.expect(raftOf("c0954")).toBe("")
			trackerfix.trOk(f, wt, { "fold", "R0960", "c0953" })
			t.expect(raftOf("c0953")).toBe("R0960")
		end
	)

	it("ready refuses a raft whose member was edited after its round, and names the member", function()
		local stale = issueDoc("c0955", "\n## Design\nOne.\n")
		local ok = quoted("c0955", stale)
		local edited = issueDoc("c0955", "\n## Design\nOne.\n\n## Design\nEdited.\n")
		local doc = string.gsub(edited, "raft: \n", "raft: R0961\n")
		trackerfix.elsewhere(f, {
			[path("c0955", "c0955.md")] = (string.gsub(stale, "raft: \n", "raft: R0961\n")),
			[path("c0955", "check.sh")] = CHECK,
			[path("c0955", "design-review-001.md")] = approve(ok),
			["pickman/.tracker/rafts/R0961/R0961.md"] = raftDoc("R0961", "c0955"),
			["pickman/.tracker/rafts/R0961/check.sh"] = CHECK,
		}, "a prepared raft with a member")
		trackerfix.elsewhere(f, { [path("c0955", "c0955.md")] = doc }, "the member is edited after its round")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = trackerfix.tr(f, f.main, { "ready", "R0961" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "c0955")).toBe(true)
		t.expect(has(r.stderr, "prepared on origin/main")).toBe(true)
		-- nothing moved
		t.expect(fs.isFile(`{f.main}/{path("c0955", "c0955.md")}`)).toBe(true)
		-- an approving round 002 that quotes the edited design makes it current: ready takes the raft
		trackerfix.elsewhere(f, {
			[path("c0955", "design-review-002.md")] = approve(quoted("c0955", edited)),
		}, "c0955 gets a round 002 that quotes the edited design")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local again = trackerfix.tr(f, f.main, { "ready", "R0961" })
		if not again.ok then
			error(`ready R0961 refused a member made current by round 002: {again.stderr}`)
		end
		t.expect(fs.isFile(`{f.main}/pickman/.tracker/issues/active/c0955/c0955.md`)).toBe(true)
		t.expect(fs.isFile(`{f.main}/pickman/.tracker/rafts/active/R0961/R0961.md`)).toBe(true)
		fs.removeFile(`{f.main}/pickman/.tracker/rafts/active/R0961/prompt.md`) -- ready's prompt is untracked in this fixture
	end)

	it(
		"an approving round that quotes the edited design makes a stale issue current for new raft and fold (a forged newer round does not)",
		function()
			-- the recovery z-design 5.3 and z-raft 2 name: a design round for the issue, landed with the edit
			local edited = issueDoc("c0951", EDITED)
			push(
				{ [path("c0951", "design-review-002.md")] = approve(quoted("c0951", edited)) },
				"c0951 gets a round 002"
			)
			trackerfix.trOk(f, wt, { "fold", "R0960", "c0951" })
			t.expect(raftOf("c0951")).toBe("R0960")
			-- c0968 is edited after its round on origin, new raft refuses it, and round 002 lets new raft take it
			local doc68 = issueDoc("c0968", EDITED)
			push({ [path("c0968", "c0968.md")] = doc68 }, "c0968 edited after its round")
			refused(
				{ "new", "raft", "chore", "again-one", "c0968", "--project", "pickman" },
				"c0968",
				"design-review-001.md"
			)
			push(
				{ [path("c0968", "design-review-002.md")] = approve(quoted("c0968", doc68)) },
				"c0968 gets a round 002"
			)
			trackerfix.trOk(f, wt, { "new", "raft", "chore", "again-one", "c0968", "--project", "pickman" })
			t.expect(string.match(raftOf("c0968"), "^R%d+$") ~= nil).toBe(true)
			-- a forged newer round that quotes another design does not
			push(
				{ [path("c0954", "design-review-002.md")] = approve("000000000000") },
				"c0954 gets a wrong round 002"
			)
			refused({ "fold", "R0960", "c0954" }, "c0954", "design-review-002.md", "000000000000")
		end
	)

	it(
		"fold and raft-plan read the issue as it is on origin/main: a committed local edit that is not there does not stale it",
		function()
			for _, id in { "c0961", "c0965" } do
				local p = `{wt}/{path(id, `{id}.md`)}`
				fs.writeFile(p, fs.readFile(p) .. "\n## Design\nA local edit, committed here, not pushed.\n")
			end
			fixture.git(wt, { "add", "-A" })
			fixture.git(wt, { "commit", "-q", "-m", "local edits to prepared issues" })
			-- raft-plan, a second time: c0965 is still raftless and its origin copy still matches its round
			planTakes(trackerfix.trOk(f, wt, { "raft-plan" }), "c0965")
			trackerfix.trOk(f, wt, { "fold", "R0960", "c0961" }) -- origin still matches the quoted round: judged at ready
			t.expect(raftOf("c0961")).toBe("R0960")
		end
	)

	it("recombine refuses a member edited after its round, naming it, and moves a matching one", function()
		refused(
			{ "recombine", "R0970", "R0971", "c0959" },
			"c0959",
			"design-review-001.md",
			"prepared on origin/main"
		)
		t.expect(raftOf("c0959")).toBe("R0971")
		trackerfix.trOk(f, wt, { "recombine", "R0970", "R0971", "c0958" })
		t.expect(raftOf("c0958")).toBe("R0970")
	end)

	it(
		"ready takes a raft whose member still matches its quoted round, although the move rewrites its check.sh",
		function()
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			local r = trackerfix.tr(f, f.main, { "ready", "R0962" })
			if not r.ok then
				error(`ready R0962 refused a matching member: {r.stderr}`)
			end
			t.expect(has(r.stdout .. r.stderr, "R0962")).toBe(true)
			t.expect(fs.isFile(`{f.main}/pickman/.tracker/rafts/active/R0962/R0962.md`)).toBe(true)
			t.expect(fs.isFile(`{f.main}/pickman/.tracker/issues/active/c0956/c0956.md`)).toBe(true)
		end
	)

	-- the recovery z-raft 2 words for a rafted member (design review 007 F1): `grouped:` is recorded from origin/main, so a
	-- member's edit and its round must land before it is folded again
	local function prepareAndLand(w: string, raft: string)
		local rd = `{w}/pickman/.tracker/rafts/{raft}/{raft}.md`
		local text = fs.readFile(rd)
		text = string.gsub(text, "## Theme\n[^#]*", "## Theme\nOne member.\n\n")
		text = string.gsub(text, "## Order & dependencies\n[^#]*", "## Order & dependencies\nBy id.\n\n")
		text = string.gsub(text, "\ndesign: [^\n]*", "\ndesign: ready")
		fs.writeFile(rd, text)
		trackerfix.trOk(f, w, { "status", raft, "prepared" })
		fixture.git(w, { "add", "-A" })
		fixture.git(w, { "commit", "-q", "-m", `rafting {raft}` })
		trackerfix.trOk(f, w, { "sync" })
		fixture.git(w, { "push", "-q", "origin", "HEAD:main" })
	end
	local function editWithRound(w: string, id: string)
		local doc = `{w}/{path(id, `{id}.md`)}`
		fs.writeFile(doc, fs.readFile(doc) .. "\n## Design\nChanged inside the raft.\n")
		fs.writeFile(
			`{w}/{path(id, "design-review-002.md")}`,
			approve(raftplan.designRecord(id, { [`{id}.md`] = fs.readFile(doc), ["check.sh"] = CHECK }))
		)
	end
	local function readyFromMain(raft: string): { ok: boolean, stderr: string }
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = trackerfix.tr(f, f.main, { "ready", raft })
		if r.ok then
			fs.removeFile(`{f.main}/pickman/.tracker/rafts/active/{raft}/prompt.md`) -- untracked in this fixture
		end
		return r
	end

	it(
		"a member changed inside a landed raft and re-folded in the same PR is refused by ready on grouped:",
		function()
			fs.removeFile(`{f.main}/pickman/.tracker/rafts/active/R0962/prompt.md`) -- left by the ready case before
			local w = trackerfix.trOk(f, f.main, { "worktree", "prep-naive" })
			trackerfix.trOk(f, w, { "sync" })
			trackerfix.trOk(f, w, { "new", "raft", "chore", "naive", "c0966", "--project", "pickman" })
			local raft = string.match(fs.readFile(`{w}/{path("c0966", "c0966.md")}`), "\nraft: (R%d+)") or "?"
			prepareAndLand(w, raft) -- landing 0: the raft with its member
			editWithRound(w, "c0966") -- the edit and its round in the rafting worktree, no unfold
			fixture.git(w, { "add", "-A" })
			fixture.git(w, { "commit", "-q", "-m", "edit and round inside the raft" })
			trackerfix.trOk(f, w, { "sync" })
			fixture.git(w, { "push", "-q", "origin", "HEAD:main" })
			local r = readyFromMain(raft)
			t.expect(r.ok).toBe(false)
			if not has(r.stderr, "changed on origin/main since") then
				error(`ready should refuse on grouped: {r.stderr}`)
			end
			t.expect(has(r.stderr, "prepared on origin/main but")).toBe(false) -- not on the design record
		end
	)

	it(
		"a rafted member takes two landings: unfold with the edit and its round, then fold again; ready takes it",
		function()
			local w = trackerfix.trOk(f, f.main, { "worktree", "prep-twice" })
			trackerfix.trOk(f, w, { "sync" })
			trackerfix.trOk(f, w, { "new", "raft", "chore", "twice", "c0967", "--project", "pickman" })
			local raft = string.match(fs.readFile(`{w}/{path("c0967", "c0967.md")}`), "\nraft: (R%d+)") or "?"
			prepareAndLand(w, raft) -- landing 0: the raft with its member
			-- landing 1: the member leaves the raft with its edit and an approving round 002
			trackerfix.trOk(f, w, { "unfold", raft, "c0967" })
			editWithRound(w, "c0967")
			prepareAndLand(w, raft) -- the unfold claimed the raft; its remaining (no) members are prepared again
			-- landing 2: a second rafting folds it again, which records the landed design
			local w2 = trackerfix.trOk(f, f.main, { "worktree", "prep-twice2" })
			trackerfix.trOk(f, w2, { "sync" })
			trackerfix.trOk(f, w2, { "fold", raft, "c0967" })
			prepareAndLand(w2, raft)
			local r = readyFromMain(raft)
			if not r.ok then
				error(`ready {raft} refused after the second landing: {r.stderr}`)
			end
			t.expect(fs.isFile(`{f.main}/pickman/.tracker/issues/active/c0967/c0967.md`)).toBe(true)
		end
	)
end)
