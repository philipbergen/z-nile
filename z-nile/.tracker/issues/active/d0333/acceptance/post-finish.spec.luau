--!strict
-- d0333 AC1, AC2 (pure): the three post-finish path rules take the raft's own spend.md, the file every `./zn commit`
-- rewrites, and nothing else new. Before d0333 a `./zn commit` of trace.md or the final review after `./zn finish`
-- made the finished layer read as not finished (layergit) and the trace table stale (trace), so `./zn done` refused.
local layergit = require("@znile/engine/layergit")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local RAFT = "pickman/.tracker/rafts/active/R0010"
local DOC = "pickman/.tracker/issues/active/c0010/c0010.md"
local ROW = "pickman/.tracker/issues/active/c0010/spend.d/host-1234abcd.tsv"

local issues: { trace.IssueDoc } = {
	{
		id = "c0010",
		docPath = DOC,
		checkPath = "pickman/.tracker/issues/active/c0010/check.sh",
		dirPath = "pickman/.tracker/issues/active/c0010",
		home = "pickman",
		capturedText = "",
		docText = "",
	},
}

-- one finished layer, then one commit per list of files, in order
local function stack(after: { { string } }): { trace.LayerHistory }
	local commits: { trace.LayerCommit } = {
		{ sha = "fin1", parent = "main0", subject = "c0010: alpha", files = { "pickman/src/alpha.luau" } },
	}
	local tip = "fin1"
	for i, files in after do
		local sha = `post{i}`
		table.insert(commits, { sha = sha, parent = tip, subject = `post {i}`, files = files })
		tip = sha
	end
	return {
		{
			name = "R0010/1/c0010",
			issue = "c0010",
			title = "alpha",
			base = "main0",
			tip = tip,
			stackedOnBelow = true,
			commits = commits,
		},
	}
end

local function stale(after: { { string } }): string
	return (trace.staleReason("R0010", RAFT, issues, stack(after), "fin1")) or ""
end

return t.spec("d0333 a commit after finish keeps the layer finished", function(it)
	it("AC1: the post-finish rule takes the raft's own spend.md", function()
		t.expect(layergit.isPostFinishPath(`{RAFT}/spend.md`, "R0010")).toBe(true)
		t.expect(layergit.isPostFinishPath("z-nile/.tracker/rafts/active/R0102/spend.md", "R0102")).toBe(true)
		-- what it took before, it still takes
		t.expect(layergit.isPostFinishPath(`{RAFT}/trace.md`, "R0010")).toBe(true)
		t.expect(layergit.isPostFinishPath(`{RAFT}/final-review-001.md`, "R0010")).toBe(true)
		t.expect(layergit.isPostFinishPath(ROW, "R0010")).toBe(true)
	end)

	it("AC1: the post-finish rule takes no other new path", function()
		-- another raft's snapshot, a snapshot outside active/, and a file that only ends like one
		t.expect(layergit.isPostFinishPath("pickman/.tracker/rafts/active/R0020/spend.md", "R0010"))
			.toBe(false)
		t.expect(layergit.isPostFinishPath("pickman/.tracker/rafts/R0010/spend.md", "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath(`{RAFT}/notes/spend.md`, "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath(`{RAFT}/xspend.md`, "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath(`{RAFT}/spend.md.bak`, "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath("pickman/.tracker/issues/active/c0010/spend.md", "R0010"))
			.toBe(false)
		-- code, specs and the other tracker files still unfinish the layer
		t.expect(layergit.isPostFinishPath("pickman/src/alpha.luau", "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath("pickman/tests/unit/alpha.spec.luau", "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath(`{RAFT}/notes.md`, "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath(`{RAFT}/check.sh`, "R0010")).toBe(false)
		t.expect(layergit.isPostFinishPath("pickman/.tracker/issues/active/c0010/check.sh", "R0010"))
			.toBe(false)
	end)

	it("AC2: a trace commit that also rewrites the raft's spend.md leaves the table current", function()
		t.expect(stale({ { `{RAFT}/trace.md`, `{RAFT}/spend.md`, ROW } })).toBe("")
		-- before the table: a ./zn commit of the issue's log, then the table
		t.expect(stale({ { DOC, `{RAFT}/spend.md`, ROW }, { `{RAFT}/trace.md`, `{RAFT}/spend.md`, ROW } }))
			.toBe("")
	end)

	it("AC2: review commits after the table that rewrite the raft's spend.md leave it current", function()
		t.expect(stale({
			{ `{RAFT}/trace.md`, `{RAFT}/spend.md`, ROW },
			{ `{RAFT}/final-review-001.md`, `{RAFT}/spend.md`, ROW },
			{ `{RAFT}/final-refute-001.md`, `{RAFT}/R0010.md`, `{RAFT}/spend.md`, ROW },
		})).toBe("")
	end)

	it("AC2: any other file still makes the table stale, before and after it", function()
		local function has(text: string, needle: string): boolean
			return string.find(text, needle, 1, true) ~= nil
		end
		-- after the finish: code, another raft's snapshot, a file of the raft no rule names
		t.expect(
			has(
				stale({ { "pickman/src/alpha.luau", `{RAFT}/spend.md` }, { `{RAFT}/trace.md` } }),
				"after finish"
			)
		).toBe(true)
		t.expect(
			has(
				stale({ { `{RAFT}/trace.md`, "pickman/.tracker/rafts/active/R0020/spend.md" } }),
				"touches non-tracker file pickman/.tracker/rafts/active/R0020/spend.md"
			)
		).toBe(true)
		t.expect(has(stale({ { `{RAFT}/trace.md`, `{RAFT}/notes.md`, `{RAFT}/spend.md` } }), "notes.md"))
			.toBe(true)
		-- after the table: code, the issue's document (allowed before the table only), an unnamed file, a nested spend.md
		local table1 = { `{RAFT}/trace.md`, `{RAFT}/spend.md`, ROW }
		t.expect(has(stale({ table1, { "pickman/src/alpha.luau", `{RAFT}/spend.md` } }), "after trace.md"))
			.toBe(true)
		t.expect(has(stale({ table1, { DOC, `{RAFT}/spend.md` } }), "after trace.md")).toBe(true)
		t.expect(has(stale({ table1, { `{RAFT}/notes.md`, `{RAFT}/spend.md` } }), "after trace.md"))
			.toBe(true)
		t.expect(has(stale({ table1, { `{RAFT}/notes/spend.md` } }), "after trace.md")).toBe(true)
		-- a commit of the snapshot alone, with no table at all, is still "before trace.md"
		t.expect(has(stale({ { `{RAFT}/spend.md`, ROW } }), "before trace.md")).toBe(true)
	end)
end)
