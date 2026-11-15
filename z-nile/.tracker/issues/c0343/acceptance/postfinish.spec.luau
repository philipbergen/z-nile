--!strict
-- c0343 AC2: the raft's own spend.md is one of the files a commit may touch after a layer's finish commit, in both
-- places that rule is written: `layergit.isPostFinishPath` (what `./zn work next` and `./zn finish` read to call a
-- layer finished) and `trace.staleReason` (what `./zn trace --check` and `./zn done` read). `./zn commit` rewrites
-- that file in every commit, so without it no commit made the allowed way could follow a finish commit. Nothing else
-- joins the set: another raft's ledger, a ticket's, a spend.md elsewhere and the raft's harvest stay outside, and a
-- source file after the finish is still refused. Pure: no repository is read or written.
local layergit = require("@znile/engine/layergit")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local RAFT = "R0010"
local raftDir = "pickman/.tracker/rafts/active/R0010"
local ROW = "pickman/.tracker/issues/active/c0020/spend.d/host-1234.tsv"
local LEDGER = `{raftDir}/spend.md`
local TABLE = `{raftDir}/trace.md`
local FINAL = `{raftDir}/final-review-001.md`

local function issue(id: string): trace.IssueDoc
	return {
		id = id,
		docPath = `pickman/.tracker/issues/active/{id}/{id}.md`,
		checkPath = `pickman/.tracker/issues/active/{id}/check.sh`,
		dirPath = `pickman/.tracker/issues/active/{id}`,
		home = "pickman",
		capturedText = "",
		docText = "",
	}
end
local issues: { trace.IssueDoc } = { issue("c0010"), issue("c0020") }

-- a finished two-layer stack whose top layer carries `after`, one list of files per commit, above its finish commit
local function stale(after: { { string } }): string?
	local top: { trace.LayerCommit } = {
		{ sha = "fin2", parent = "fin1", subject = "c0020: beta", files = { "pickman/src/beta.luau" } },
	}
	local parent = "fin2"
	for i, files in after do
		local sha = `post{i}`
		table.insert(top, { sha = sha, parent = parent, subject = `R0010: commit {i}`, files = files })
		parent = sha
	end
	local layers: { trace.LayerHistory } = {
		{
			name = "R0010/1/c0010",
			issue = "c0010",
			title = "alpha",
			base = "main0",
			tip = "fin1",
			stackedOnBelow = true,
			commits = {
				{
					sha = "fin1",
					parent = "main0",
					subject = "c0010: alpha",
					files = { "pickman/src/alpha.luau" },
				},
			},
		},
		{
			name = "R0010/2/c0020",
			issue = "c0020",
			title = "beta",
			base = "fin1",
			tip = parent,
			stackedOnBelow = true,
			commits = top,
		},
	}
	return (trace.staleReason(RAFT, raftDir, issues, layers, "fin2"))
end

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

-- paths that look like the raft's ledger and are not
local NOT_THE_LEDGER = {
	"pickman/.tracker/rafts/active/R0020/spend.md", -- another raft's
	"pickman/.tracker/issues/active/c0020/spend.md", -- a ticket's
	`{raftDir}/sub/spend.md`,
	`{raftDir}/spend.md.bak`,
	`{raftDir}/my-spend.md`,
	"pickman/src/spend.md",
	"spend.md",
	`{raftDir}/harvest.md`,
	`{raftDir}/check.sh`,
}

return t.spec("c0343 the raft's spend ledger may follow a finish commit", function(it)
	it("AC2: the table's commit, as ./zn commit makes it, leaves the table fresh", function()
		t.expect(stale({ { TABLE, LEDGER, ROW } })).toBe(nil)
		-- the final review after the table, and a review answer before it, each with the ledger
		t.expect(stale({ { TABLE, LEDGER, ROW }, { FINAL, LEDGER, ROW } })).toBe(nil)
		t.expect(stale({ { `{raftDir}/refute-001.md`, LEDGER, ROW }, { TABLE, LEDGER, ROW } })).toBe(nil)
		t.expect(stale({ { TABLE, FINAL, LEDGER, ROW }, { `{raftDir}/R0010.md`, LEDGER } })).toBe(nil)
		-- the ledger alone is no table: a top layer with commits above its finish still needs trace.md among them
		t.expect(has(stale({ { LEDGER, ROW } }), "before trace.md")).toBe(true)
	end)

	it(
		"AC2: a source file after the finish commit is still stale, with or without the ledger beside it",
		function()
			t.expect(
				has(
					stale({ { TABLE, LEDGER, "pickman/src/beta.luau" } }),
					"touches non-tracker file pickman/src/beta.luau"
				)
			).toBe(true)
			t.expect(has(stale({ { TABLE, LEDGER }, { LEDGER, "pickman/src/beta.luau" } }), "after trace.md"))
				.toBe(true)
			t.expect(has(stale({ { TABLE }, { "pickman/tests/unit/beta.spec.luau" } }), "after trace.md"))
				.toBe(true)
			-- a commit with no file at all is still refused
			t.expect(has(stale({ { TABLE, LEDGER }, {} }), "after trace.md")).toBe(true)
		end
	)

	it("AC2: nothing else joins the set, before or after the table", function()
		for _, path in NOT_THE_LEDGER do
			t.expect(`{path} {has(stale({ { TABLE, path } }), "touches non-tracker file " .. path)}`)
				.toBe(`{path} true`)
			t.expect(`{path} {has(stale({ { TABLE }, { FINAL, path } }), "after trace.md")}`)
				.toBe(`{path} true`)
			t.expect(`{path} {layergit.isPostFinishPath(path, RAFT)}`).toBe(`{path} false`)
		end
	end)

	it("AC2: the worker's rule and the table's rule agree on every file of the raft", function()
		t.expect(layergit.isPostFinishPath(LEDGER, RAFT)).toBe(true)
		t.expect(layergit.isPostFinishPath(LEDGER, "R0020")).toBe(false)
		local raftFiles = {
			LEDGER,
			TABLE,
			FINAL,
			ROW,
			`{raftDir}/R0010.md`,
			`{raftDir}/review-001.md`,
			`{raftDir}/refute-001.md`,
			`{raftDir}/final-refute-001.md`,
			"pickman/.tracker/issues/active/c0020/c0020.md",
			`{raftDir}/harvest.md`,
			`{raftDir}/check.sh`,
			`{raftDir}/sub/spend.md`,
			"pickman/.tracker/issues/active/c0020/spend.md",
			"pickman/.tracker/issues/active/c0020/check.sh",
			"pickman/src/beta.luau",
		}
		for _, path in raftFiles do
			-- a commit of that one file between the finish commit and the table's
			local fresh = stale({ { path }, { TABLE } }) == nil
			t.expect(`{path} {layergit.isPostFinishPath(path, RAFT)}`).toBe(`{path} {fresh}`)
		end
	end)
end)
