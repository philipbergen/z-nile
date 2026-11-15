--!strict
-- c0301: a tests-only ticket's code cells cite the spec files it touched; a ticket that changed a source file still
-- cites source. Pure: the check runs over texts and layer records, as tests/tooling/trace.spec does.
local raftplan = require("@znile/engine/raftplan")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local SRC = "pickman/src/alpha.luau"
local SPEC_A = "pickman/tests/unit/alpha.spec.luau"
local SPEC_B = "pickman/tests/unit/beta.spec.luau"
local SPEC_OLD = "pickman/tests/unit/old.spec.luau" -- touched by nobody in the stack
local SPEC_GONE = "pickman/tests/unit/gone.spec.luau" -- deleted by the stack: absent at the commit
local HELPER = "pickman/tests/lib/helper.luau" -- a source file under tests/

local function doc(id: string, touched: { string }?): string
	local lines = {
		"---",
		`id: {id}`,
		"---",
		`# {id}: x`,
		"## Problem",
		"Broken.",
		"## Solution",
		"<!-- x -->",
		"## Design",
		"Fix it.",
		"### Touched modules",
	}
	local list: { string } = touched or {}
	for _, p in list do
		table.insert(lines, `- \`{p}\``)
	end
	for _, l in { "", "### Affected specs", "none", "## Acceptance criteria", "- AC1: Fixed." } do
		table.insert(lines, l)
	end
	return table.concat(lines, "\n")
end

local function issueOf(id: string, touched: { string }?): trace.IssueDoc
	local text = doc(id, touched)
	return {
		id = id,
		docPath = `pickman/.tracker/issues/active/{id}/{id}.md`,
		checkPath = `pickman/.tracker/issues/active/{id}/check.sh`,
		dirPath = `pickman/.tracker/issues/active/{id}`,
		home = "pickman",
		capturedText = doc(id, nil), -- the capture has no Touched modules: the check reads the document at the commit
		docText = text,
		checkText = 'source "ac.sh"\ncheck "AC1: fixed" true\nfinish\n',
		resultsPath = `pickman/.tracker/issues/active/{id}/results.txt`,
		resultsText = "",
	}
end

local function layer(id: string, files: { string }): trace.LayerHistory
	return {
		name = `R0010/x/{id}`,
		issue = id,
		title = "x",
		base = "m",
		tip = `{id}-tip`,
		stackedOnBelow = true,
		commits = { { sha = `{id}-tip`, parent = "m", subject = `{id}: x`, files = files } },
	}
end

-- A stack of layers in order: each is based on the finish commit below it, as `./zn trace --check` reads them.
local function chain(list: { trace.LayerHistory }): { trace.LayerHistory }
	local base = "m"
	for _, l in list do
		l.base = base
		l.commits[1].parent = base
		base = l.commits[1].sha
	end
	return list
end

type Case = {
	issues: { trace.IssueDoc },
	layers: { trace.LayerHistory }?,
	changedSources: { string },
	changedFiles: { string }?,
	filesAtBase: { [string]: trace.FileMeta }?,
	codes: { [string]: string }, -- ticket id -> the code cell of each of its rows
}

-- The source-changing ticket c0010 (alpha.luau and its spec) and the tests-only ticket c0020 (beta.spec only).
local function stack(overrides: { codes: { [string]: string }?, touched20: { string }?, changedFiles: { string }? }): Case
	local touched20 = overrides.touched20 or { SPEC_B }
	return {
		issues = { issueOf("c0010", { SRC, SPEC_A }), issueOf("c0020", touched20) },
		layers = chain({
			layer("c0010", { SRC, SPEC_A, "pickman/.tracker/issues/active/c0010/results.txt" }),
			layer("c0020", { SPEC_B, "pickman/.tracker/issues/active/c0020/c0020.md", "pickman/tests/unit/beta.watch.txt" }),
		}),
		changedSources = { SRC },
		changedFiles = overrides.changedFiles or { SRC, SPEC_A, SPEC_B, "pickman/tests/unit/beta.watch.txt" },
		codes = overrides.codes or { c0010 = `{SRC}:2`, c0020 = `{SPEC_B}:2` },
	}
end

-- trace.check over the case: every row's design and test cells are valid, only the code cells differ. With layers
-- the check reads the finished tickets and the commit from them, as `./zn trace --check` does; without, they are given.
local function check(c: Case): { string }
	local files: { [string]: trace.FileMeta } = {}
	local top = if c.layers then c.layers[#c.layers].commits[1].sha else "abc"
	local lines = { "# Trace: R0010", "", `Commit: {top}`, "", "## Claims", "", "| claim | design | test | code |", "|---|---|---|---|" }
	local finished: { [string]: boolean } = {}
	for _, i in c.issues do
		files[i.docPath] = { lines = trace.splitLines(i.docText) }
		files[i.checkPath] = { lines = trace.splitLines(i.checkText :: string) }
		finished[i.id] = true
		for _, key in { "P1", "AC1" } do
			table.insert(lines, `| {i.id}:{key} | {i.docPath}:6 | {i.checkPath}:2 | {c.codes[i.id]} |`)
		end
	end
	for _, p in { SRC, SPEC_A, SPEC_B, SPEC_OLD, HELPER } do
		files[p] = { lines = { "--!strict", "return 1" } }
	end
	for _, l in { "", "## Source files", "", "| file | claims |", "|---|---|" } do
		table.insert(lines, l)
	end
	for _, s in c.changedSources do
		table.insert(lines, `| {s} | {c.issues[1].id}:P1 |`)
	end
	table.insert(lines, "")
	local input: trace.CheckInput = {
		raftId = "R0010",
		raftDir = "pickman/.tracker/rafts/active/R0010",
		tableText = table.concat(lines, "\n"),
		layers = c.layers,
		issues = c.issues,
		raftDocText = "",
		changedSources = c.changedSources,
		changedFiles = c.changedFiles,
		filesAtBase = c.filesAtBase,
		filesAtCommit = files,
	}
	if c.layers == nil then
		input.expectedCommit = top
		input.finishedIssues = finished
	end
	return trace.check(input)
end

local function codeFindings(findings: { string }): { string }
	local out: { string } = {}
	for _, f in findings do
		if string.find(f, ", code: ", 1, true) ~= nil then
			table.insert(out, f)
		end
	end
	return out
end

return t.spec("c0301: a tests-only ticket's code cells cite its own spec files", function(it)
	it("AC2: testsOnly names the tickets whose layer changed a spec file and no source file", function()
		local kinds = trace.testsOnly({
			layer("c0010", { SRC, SPEC_A }),
			layer("c0020", { SPEC_B, "pickman/tests/unit/beta.watch.txt", "pickman/.tracker/issues/active/c0020/c0020.md" }),
			layer("c0030", { SPEC_B, HELPER }), -- a helper under tests/ is a source file
			layer("c0040", { "z-nile/skills/zz-rules/SKILL.md", "pickman/.tracker/issues/active/c0040/c0040.md" }),
			layer("c0050", {}),
			-- a sequestered acceptance spec is the ticket's contract, not its change: no spec file
			layer("c0070", { "pickman/.tracker/issues/active/c0070/acceptance/alpha.spec.luau" }),
		})
		t.expect(kinds).toEqual({ c0020 = true })
		t.expect(trace.isSpecFile(SPEC_B)).toBe(true)
		t.expect(trace.isSpecFile("pickman/.tracker/issues/active/c0070/acceptance/alpha.spec.luau")).toBe(false)
		t.expect(trace.isSpecFile(".tracker/issues/c0070/acceptance/alpha.spec.luau")).toBe(false)
		t.expect(trace.isSpecFile(HELPER)).toBe(false)
		t.expect(trace.testsOnly(nil)).toEqual({})
		-- every commit of a layer counts, not only its first
		local twoCommits = layer("c0060", { SPEC_B })
		table.insert(twoCommits.commits, { sha = "s2", parent = "s", subject = "R0010: trace", files = { SRC } })
		t.expect(trace.testsOnly({ twoCommits })).toEqual({})
	end)

	it("AC2: a tests-only ticket's claims pass citing a spec file the stack changed that its layer changed or its Touched modules name", function()
		t.expect(check(stack({}))).toEqual({})
		-- its own layer changed it: no Touched modules needed
		t.expect(check(stack({ touched20 = {} }))).toEqual({})
		-- a spec file the other ticket's layer changed, named in this ticket's Touched modules (captured S2)
		t.expect(check(stack({ touched20 = { SPEC_B, SPEC_A }, codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:1` } })))
			.toEqual({})
		-- a Touched folder covers the spec files under it, written with or without a trailing slash
		t.expect(check(stack({ touched20 = { "pickman/tests/unit" }, codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:1` } })))
			.toEqual({})
		t.expect(check(stack({ touched20 = { "pickman/tests/unit/" }, codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:1` } })))
			.toEqual({})
		-- two refs in one cell
		t.expect(check(stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_B}:1 ; {SPEC_B}:2` } }))).toEqual({})
	end)

	it("AC2: in a stack that changed no source file a tests-only ticket may cite its spec file or write none", function()
		local c = stack({ codes = { c0010 = "none", c0020 = `{SPEC_B}:2` } })
		c.issues[1] = issueOf("c0010", { "z-nile/skills/zz-rules/SKILL.md" })
		c.layers = chain({ layer("c0010", { "z-nile/skills/zz-rules/SKILL.md" }), layer("c0020", { SPEC_B }) })
		c.changedSources = {}
		c.changedFiles = { "z-nile/skills/zz-rules/SKILL.md", SPEC_B }
		t.expect(check(c)).toEqual({})
		c.codes = { c0010 = "none", c0020 = "none" }
		t.expect(check(c)).toEqual({})
		-- the ticket that changed no spec and no source still writes none there
		c.codes = { c0010 = `{SPEC_B}:2`, c0020 = "none" }
		t.expect(codeFindings(check(c))).toEqual({
			'row c0010:P1, code: stack changed no source file (expected "none")',
			'row c0010:AC1, code: stack changed no source file (expected "none")',
		})
	end)

	it("AC2: a tests-only ticket's claim citing a source file fails, naming the row", function()
		local f = codeFindings(check(stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SRC}:2` } })))
		t.expect(f).toEqual({
			`row c0020:P1, code: ticket c0020 changed no source file; {SRC} is not a spec file it touched`,
			`row c0020:AC1, code: ticket c0020 changed no source file; {SRC} is not a spec file it touched`,
		})
		-- one bad ref among good ones still fails
		local mixed = codeFindings(check(stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_B}:2 ; {SRC}:2` } })))
		t.expect(#mixed).toBe(2)
		t.expect(has(mixed, "row c0020:P1, code:")).toBe(true)
	end)

	it("AC2: a tests-only ticket's spec citation fails when neither its layer nor its Touched modules has it, or the stack did not change it", function()
		local neither = `{SPEC_A} is neither changed by ticket c0020's layer nor in its Touched modules`
		-- changed by the stack (by c0010's layer), not by c0020's layer, not in c0020's Touched modules
		local outside = codeFindings(check(stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:2` } })))
		t.expect(outside).toEqual({ `row c0020:P1, code: {neither}`, `row c0020:AC1, code: {neither}` })
		-- a Touched path that only starts like the spec's folder
		local prefix = codeFindings(check(stack({ touched20 = { "pickman/tests/unit/alpha" }, codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:2` } })))
		t.expect(has(prefix, `row c0020:P1, code: {neither}`)).toBe(true)
		-- no Touched modules at all
		local none = codeFindings(check(stack({ touched20 = {}, codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:2` } })))
		t.expect(has(none, `row c0020:P1, code: {neither}`)).toBe(true)
		-- in its Touched modules, not changed by the stack
		local unchanged = codeFindings(check(stack({ touched20 = { SPEC_B, SPEC_OLD }, codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_OLD}:2` } })))
		t.expect(unchanged).toEqual({
			`row c0020:P1, code: {SPEC_OLD} was not changed by this stack`,
			`row c0020:AC1, code: {SPEC_OLD} was not changed by this stack`,
		})
		-- the stack's changed files are not known: no spec file counts as changed, its own layer's included
		local c = stack({})
		c.changedFiles = nil
		t.expect(has(codeFindings(check(c)), `row c0020:P1, code: {SPEC_B} was not changed by this stack`)).toBe(true)
		-- a line the file does not have
		local missing = codeFindings(check(stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_B}:9` } })))
		t.expect(has(missing, `row c0020:P1, code: {SPEC_B}:9 does not exist`)).toBe(true)
	end)

	it("AC2: a tests-only ticket's none is still refused when the stack changed a source file", function()
		local f = codeFindings(check(stack({ codes = { c0010 = `{SRC}:2`, c0020 = "none" } })))
		t.expect(f).toEqual({
			'row c0020:P1, code: "none" is only valid when the stack changed no source file',
			'row c0020:AC1, code: "none" is only valid when the stack changed no source file',
		})
	end)

	it("AC2: a Touched modules entry may be written from the ticket's home, matched by whole components", function()
		local other = { c0010 = `{SRC}:2`, c0020 = `{SPEC_A}:1` } -- c0010's layer changed SPEC_A, c0020's did not
		t.expect(check(stack({ touched20 = { "tests/unit/alpha.spec.luau" }, codes = other }))).toEqual({})
		t.expect(check(stack({ touched20 = { "tests/unit" }, codes = other }))).toEqual({})
		local neither = `row c0020:P1, code: {SPEC_A} is neither changed by ticket c0020's layer nor in its Touched modules`
		t.expect(has(codeFindings(check(stack({ touched20 = { "tests/unit/alp" }, codes = other }))), neither)).toBe(true)
		t.expect(has(codeFindings(check(stack({ touched20 = { "unit/alpha.spec.luau" }, codes = other }))), neither))
			.toBe(true)
		-- the root's home adds nothing: a root ticket's `tests/unit` is the top's tests/, not pickman's
		local root = stack({ touched20 = { "tests/unit" }, codes = other })
		root.issues[2].home = "."
		t.expect(has(codeFindings(check(root)), neither)).toBe(true)
	end)

	it("AC2: a tests-only ticket whose layer deleted a spec cites it at a line it had at the stack's base", function()
		local function deleting(code: string, base: { [string]: trace.FileMeta }?): Case
			local c = stack({ codes = { c0010 = `{SRC}:2`, c0020 = code } })
			c.issues[2] = issueOf("c0020", { SPEC_GONE })
			c.layers = chain({
				layer("c0010", { SRC, SPEC_A }),
				layer("c0020", { SPEC_GONE, "pickman/tests/unit/gone.watch.txt" }),
			})
			c.changedFiles = { SRC, SPEC_A, SPEC_GONE, "pickman/tests/unit/gone.watch.txt" }
			c.filesAtBase = base
			return c
		end
		local base = { [SPEC_GONE] = { lines = { "--!strict", "return 1", "-- end" } } }
		t.expect(check(deleting(`{SPEC_GONE}:1`, base))).toEqual({})
		t.expect(check(deleting(`{SPEC_GONE}:2-3`, base))).toEqual({})
		t.expect(codeFindings(check(deleting(`{SPEC_GONE}:9`, base)))).toEqual({
			`row c0020:P1, code: {SPEC_GONE}:9 does not exist at the stack's base (the stack deleted it)`,
			`row c0020:AC1, code: {SPEC_GONE}:9 does not exist at the stack's base (the stack deleted it)`,
		})
		-- no base texts given: a deleted spec cannot be cited
		t.expect(has(codeFindings(check(deleting(`{SPEC_GONE}:1`, nil))), `row c0020:P1, code: {SPEC_GONE}:1 does not exist at commit`))
			.toBe(true)
		-- the source the other ticket changed, and none, are still refused
		t.expect(has(codeFindings(check(deleting(`{SRC}:2`, base))), `row c0020:P1, code: ticket c0020 changed no source file; {SRC} is not a spec file it touched`))
			.toBe(true)
		t.expect(has(codeFindings(check(deleting("none", base))), 'row c0020:P1, code: "none" is only valid when the stack changed no source file'))
			.toBe(true)
		-- a base text is read only for a file absent at the commit: SPEC_B has 2 lines there, 20 at the base
		local longer: { string } = {}
		for i = 1, 20 do
			table.insert(longer, `-- {i}`)
		end
		local c = stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_B}:9` } })
		c.filesAtBase = { [SPEC_B] = { lines = longer } }
		t.expect(has(codeFindings(check(c)), `row c0020:P1, code: {SPEC_B}:9 does not exist (file has 2 lines)`)).toBe(true)
		-- a ticket that changed a source file gets the spec-file finding for a deleted spec too
		local src = deleting(`{SPEC_GONE}:1`, base)
		src.codes = { c0010 = `{SPEC_GONE}:1`, c0020 = `{SPEC_GONE}:1` }
		t.expect(has(codeFindings(check(src)), `row c0010:P1, code: {SPEC_GONE} is a spec file, not a source file this stack changed`))
			.toBe(true)
	end)

	it("AC2: a ticket that changed a source file still fails when its code cell cites a spec file", function()
		local f = codeFindings(check(stack({ codes = { c0010 = `{SPEC_A}:2`, c0020 = `{SPEC_B}:2` } })))
		t.expect(f).toEqual({
			`row c0010:P1, code: {SPEC_A} is a spec file, not a source file this stack changed`,
			`row c0010:AC1, code: {SPEC_A} is a spec file, not a source file this stack changed`,
		})
		-- a layer that changed a spec file and a source file under tests/ is no tests-only ticket
		local c = stack({ codes = { c0010 = `{SRC}:2`, c0020 = `{SPEC_B}:2` } })
		c.layers = chain({ layer("c0010", { SRC, SPEC_A }), layer("c0020", { SPEC_B, HELPER }) })
		c.changedSources = { SRC, HELPER }
		local both = codeFindings(check(c))
		t.expect(has(both, `row c0020:P1, code: {SPEC_B} is a spec file, not a source file this stack changed`)).toBe(true)
		-- without layers no ticket is tests-only, so the spec citation fails as before
		local noLayers = stack({})
		noLayers.layers = nil
		t.expect(has(codeFindings(check(noLayers)), `row c0020:P1, code: {SPEC_B} is a spec file`)).toBe(true)
	end)

	it("AC2: raftplan.touchedModules is the one reader of Touched modules", function()
		t.expect(raftplan.touchedModules(doc("c0020", { SPEC_B, "pickman/tests/unit/" }))).toEqual({
			SPEC_B,
			"pickman/tests/unit",
		})
		t.expect(raftplan.touchedModules(doc("c0020", {}))).toBe(nil)
		t.expect(raftplan.touchedModules("# c0020\n\n## Design\nx\n")).toBe(nil)
	end)
end)
