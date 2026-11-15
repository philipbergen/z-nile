--!strict
-- c0116 AC5: z-design works on one issue with no raft, and its design reviews live on the issue. `status <id>
-- preparing` claims the issue alone (published) and the carried `status <id> prepared` lands with the design PR; the
-- design-review spend goes on the issue; `lessons --uncovered <id>` finds an issue's unharvested finding. `metrics`
-- counts design rounds per issue and rolls them up to the raft through `raft:` (the raft's own coherence review plus
-- its members'), takes the format from a member's first review when the raft has none, and sets each counted issue's
-- `size:` against its changed lines. Fixtures under .cache/c0116-issue-design (tests/lib/trackerfix) and
-- .cache/c0116-metrics (a plain tree: metrics only reads).
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local SB = ".cache/c0116-metrics"
local REVIEW = "# Review 001\n\n### F1 [low] x\nWhere: a\nEvidence: b\nCritique: c\nConsequences: none\n"
	.. "Recommendation: d\n\nVerdict: approve\n"
local HEAD = "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
	.. "|---|---|---|---|---|---|---|---|---|\n"

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function hasLine(text: string, line: string): boolean
	return string.find("\n" .. text .. "\n", "\n" .. line .. "\n", 1, true) ~= nil
end
local function write(path: string, text: string)
	fs.writeDir(string.match(path, "^(.*)/[^/]*$") :: string)
	fs.writeFile(path, text)
end
local function doc(id: string, raft: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\n{extra or ""}---\n\n# {id}\n`
end
local function raftDoc(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\n---\n\n# {id}\n`
end
local function ledger(id: string, added: number, removed: number): string
	return `# Spend: {id} {id}\n\n{HEAD}| 1 | 2026-10-01 10:00 | s | {added} | {removed} | 3.0 | spend | build |  |\n`
		.. "| 2 | 2026-10-01 11:00 | design-review-001 | 0 | 0 | 2.0 | spend | design-review | 100 |\n"
end
-- the table that starts at `header`, up to the next blank line
local function tableAt(text: string, header: string): string
	local s = string.find(text, header, 1, true)
	assert(s, `no table: {header}`)
	local e = string.find(text, "\n\n", s, true) or #text + 1
	return string.sub(text, s, e - 1)
end

return t.spec("c0116 z-design designs one issue with no raft; its reviews roll up to the raft", function(it)
	it("claims an issue alone and carries its move to prepared, with no raft", function()
		local f = trackerfix.new("c0116-issue-design", nil)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "prep-solo" })
		trackerfix.trOk(f, wt, { "sync" })
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "solo-thing", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		-- ./zn new leaves the idea unchallenged; design starts only after the review is on origin
		local ideaPath = `{wt}/pickman/.tracker/issues/{id}/{id}.md`
		fs.writeFile(
			ideaPath,
			(string.gsub(fs.readFile(ideaPath), "idea: unchallenged", "idea: challenged", 1))
		)
		fs.writeFile(
			`{wt}/pickman/.tracker/issues/{id}/idea-review-001.md`,
			"# Idea review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n"
		)
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", `tracker: idea {id}` })
		fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
		local before = fixture.git(f.origin, { "rev-parse", "main" })
		trackerfix.trOk(f, wt, { "status", id, "preparing" })
		local changed = fixture.git(f.origin, { "diff", "--name-only", before, "main" })
		t.expect(changed).toBe(`pickman/.tracker/issues/{id}/{id}.md`)
		t.expect(trackerfix.trOk(f, wt, { "status", id })).toBe("preparing")
		-- the reviewer's file and the spend are the issue's
		local dir = `{wt}/pickman/.tracker/issues/{id}`
		write(`{dir}/design-review-001.md`, REVIEW)
		local uncovered = trackerfix.tr(f, wt, { "lessons", "--uncovered", id })
		t.expect(uncovered.ok).toBe(false)
		t.expect(has(uncovered.stdout, `{id} design-review-001 F1`)).toBe(true)
		trackerfix.trOk(f, wt, {
			"spend",
			id,
			"--phase",
			"design-review",
			"--time",
			"4",
			"--tokens",
			"50",
			"--note",
			"design-review-001",
		})
		local names = fs.readDir(`{dir}/spend.d`)
		table.sort(names)
		local spent = fs.readFile(`{dir}/spend.d/{names[#names]}`)
		t.expect(has(spent, "design-review-001")).toBe(true)
		t.expect(has(spent, "design-review")).toBe(true)
		-- design ready, then the carried move: nothing published, the local document prepared, raft: still empty
		local path = `{dir}/{id}.md`
		local text = fs.readFile(path)
		local s, e = string.find(text, "\ndesign: draft\n", 1, true)
		assert(s and e, "design: line")
		fs.writeFile(path, string.sub(text, 1, s) .. "design: ready\n" .. string.sub(text, e + 1))
		local mid = fixture.git(f.origin, { "rev-parse", "main" })
		trackerfix.trOk(f, wt, { "status", id, "prepared" })
		t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(mid)
		t.expect(string.match(fs.readFile(path), "\nstatus: prepared%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
		t.expect(string.match(fs.readFile(path), "\nraft: *\n") ~= nil).toBe(true)
		-- once that lands, ready refuses the raftless issue and names z-raft
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", `tracker: prep {id}` })
		fixture.git(wt, { "fetch", "-q", "origin" })
		fixture.git(wt, { "merge", "-q", "--no-edit", "origin/main" })
		fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local ready = trackerfix.tr(f, f.main, { "ready", id })
		t.expect(ready.ok).toBe(false)
		t.expect(has(ready.stderr, `{id} has no raft: z-raft makes one`)).toBe(true)
	end)

	it(
		"metrics counts design rounds per issue and rolls them up to the raft, with size against changed lines",
		function()
			if fs.isDir(SB) then
				fs.removeDir(SB)
			end
			fs.writeDir(SB)
			engine.copy(".", SB)
			fs.copy(`{engine.TOP}/.luaurc`, `{SB}/.luaurc`) -- the checkout's top: specs run from z-nile/ (c0120)
			fs.copy(`{engine.TOP}/rokit.toml`, `{SB}/rokit.toml`)
			local tr = `{SB}/pickman/.tracker`
			-- R0910 (done): its own coherence review, and its members' design reviews in their folders
			write(`{tr}/rafts/done/R0910/R0910.md`, raftDoc("R0910"))
			write(`{tr}/rafts/done/R0910/design-review-001.md`, REVIEW)
			write(`{tr}/issues/done/c0911/c0911.md`, doc("c0911", "R0910", "size: 100\n"))
			write(`{tr}/issues/done/c0911/design-review-001.md`, REVIEW)
			write(`{tr}/issues/done/c0911/design-review-002.md`, REVIEW)
			write(`{tr}/issues/done/c0911/spend.md`, ledger("c0911", 120, 30))
			write(`{tr}/issues/done/c0912/c0912.md`, doc("c0912", "R0910"))
			write(`{tr}/issues/done/c0912/design-review-001.md`, REVIEW)
			write(`{tr}/issues/done/c0912/spend.md`, ledger("c0912", 10, 0))
			-- R0920 (backlog): no review of its own; its member's first review gives the format
			write(`{tr}/rafts/R0920/R0920.md`, raftDoc("R0920"))
			write(`{tr}/issues/c0921/c0921.md`, doc("c0921", "R0920"))
			write(`{tr}/issues/c0921/design-review-001.md`, REVIEW)
			-- c0930: designed, not rafted yet
			write(`{tr}/issues/c0930/c0930.md`, doc("c0930", ""))
			write(`{tr}/issues/c0930/design-review-001.md`, REVIEW)
			local r = process.exec("scripts/tracker.sh", { "metrics" }, { cwd = SB })
			if not r.ok then
				error(r.stderr .. r.stdout)
			end
			local out = r.stdout
			local rounds = tableAt(out, "| raft | design rounds | code rounds | format |")
			t.expect(hasLine(rounds, "| R0910 | 4 | 0 | second-order |")).toBe(true)
			t.expect(hasLine(rounds, "| R0920 | 1 | 0 | second-order |")).toBe(true)
			local cost = tableAt(
				out,
				"| raft | design rounds | design-review minutes | minutes/round | tokens/round |"
			)
			t.expect(hasLine(cost, "| R0910 | 4 | 4.0 | 1.0 | 50 |")).toBe(true)
			local perIssue = tableAt(out, "| issue | raft | design rounds |")
			t.expect(hasLine(perIssue, "| c0911 | R0910 | 2 |")).toBe(true)
			t.expect(hasLine(perIssue, "| c0912 | R0910 | 1 |")).toBe(true)
			t.expect(hasLine(perIssue, "| c0921 | R0920 | 1 |")).toBe(true)
			t.expect(hasLine(perIssue, "| c0930 |  | 1 |")).toBe(true)
			local sizes = tableAt(out, "| issue | size | changed lines | ratio |")
			t.expect(hasLine(sizes, "| c0911 | 100 | 150 | 1.50 |")).toBe(true)
			t.expect(has(sizes, "c0912")).toBe(false) -- no size: line
		end
	)
end)
