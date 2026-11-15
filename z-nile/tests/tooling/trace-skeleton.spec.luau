--!strict
-- R0109 code review 001 F1, and final review 001 F1, F3 and F4: the skeleton is committed before
-- the final review, the prompt is the one dispatch builds, and two commits that touch trace.md
-- are judged from the last of them.
local dispatch = require("@znile/engine/dispatch")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trace = require("@znile/engine/trace")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function read(path: string): string
	return fs.readFile(`{root}/{path}`)
end

local function section(text: string, name: string): string
	local from = string.find(text, `\n## {name}`, 1, true)
	if not from then
		error(`no section {name}`)
	end
	local to = string.find(text, "\n## ", from + 1, true) or #text + 1
	return string.sub(text, from, to - 1)
end

local function at(body: string, needle: string): number
	local found = string.find(body, needle, 1, true)
	if not found then
		error(`missing: {needle}`)
	end
	return found
end

local RAFT = "z-nile/.tracker/rafts/active/R0109"
local DOC = "z-nile/.tracker/issues/active/d0333/d0333.md"
local ROW = "z-nile/.tracker/issues/active/d0333/spend.d/host-1234abcd.tsv"
local SPEND = `{RAFT}/spend.md`

local issues: { trace.IssueDoc } = {
	{
		id = "d0333",
		docPath = DOC,
		checkPath = "z-nile/.tracker/issues/active/d0333/check.sh",
		dirPath = "z-nile/.tracker/issues/active/d0333",
		home = "z-nile",
		capturedText = "",
		docText = "",
	},
}

-- one finished layer, then one commit per list of files, in order
local function stack(after: { { string } }): { trace.LayerHistory }
	local commits: { trace.LayerCommit } = {
		{ sha = "fin1", parent = "main0", subject = "d0333: alpha", files = { "z-nile/engine/trace.luau" } },
	}
	local tip = "fin1"
	for i, files in after do
		local sha = `post{i}`
		table.insert(commits, { sha = sha, parent = tip, subject = `post {i}`, files = files })
		tip = sha
	end
	return {
		{
			name = "R0109/1/d0333",
			issue = "d0333",
			title = "alpha",
			base = "main0",
			tip = tip,
			stackedOnBelow = true,
			commits = commits,
		},
	}
end

local function stale(after: { { string } }): string
	return (trace.staleReason("R0109", RAFT, issues, stack(after), "fin1")) or ""
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("the trace skeleton is committed before the final review", function(it)
	it(
		"Phase 5 step 3 commits the skeleton before the final review, then the filled table, then the check",
		function()
			local p5 = section(read("z-nile/skills/zz-execute/SKILL.md"), "Phase 5")
			local from = string.find(p5, "\n3. ", 1, true)
			local to = if from then string.find(p5, "\n4. ", from, true) else nil
			if not from or not to then
				error("Phase 5 has no step 3")
			end
			local step = string.sub(p5, from, to - 1)
			t.expect(at(step, "skeleton") < at(step, "final review")).toBe(true)
			-- deleting "commit that skeleton …" leaves the weaker find above green (final review 001 F3)
			local skeletonCommit = at(step, "commit that skeleton as `trace.md` with `./zn commit`")
			local reviewOnce = at(step, "Then run the final review once")
			local filled = at(step, "Commit `trace.md` and the final review files")
			t.expect(skeletonCommit < reviewOnce and reviewOnce < filled).toBe(true)
			local commit =
				at(step, "Commit `trace.md` and the final review files with `./zn commit --phase code-review")
			local after =
				at(step, "after step 1's commit (an issue document committed after the table makes it stale)")
			local verify = at(step, "then verify that `./zn trace <R-id> --check` passes")
			t.expect(commit < after and after < verify).toBe(true)
			t.expect((string.find(step, "--check` passes and commit `trace.md`", 1, true))).toBe(nil)
		end
	)

	it("zz-review and the final-mode prompt say the skeleton is already committed", function()
		local review = section(read("z-nile/skills/zz-review/SKILL.md"), "Final mode")
		at(review, "the skeleton is committed before this review starts")
		at(review, "A stale line that names a commit means that commit came after the table")
		local base: dispatch.PromptInput = {
			step = "zz-review",
			id = "R0109",
			skillPath = "z-nile/skills/zz-review/SKILL.md",
			worktree = "/w/.worktree/R0109",
			stateDir = "/w/.cache/dispatch/R0109",
		}
		local finalInput = table.clone(base)
		finalInput.mode = "final"
		local final = dispatch.prompt(finalInput)
		-- the source stores the sentence escaped; the prompt the reviewer is given does not
		at(final, "The skeleton is already committed as `trace.md`")
		at(final, "a stale line names a commit that came after the table")
		local codeInput = table.clone(base)
		codeInput.mode = "code"
		t.expect((string.find(dispatch.prompt(codeInput), "The skeleton is already committed as", 1, true)))
			.toBe(nil)
	end)

	-- lastTraceIdx is the last commit that touches trace.md. Taking it from the first makes the
	-- first assertion fail: the filled table touches trace.md, which isAllowedAfterTrace does not name.
	it("two commits that touch trace.md are judged from the last of them", function()
		local skeleton = { `{RAFT}/trace.md`, SPEND, ROW }
		local filled = { `{RAFT}/trace.md`, `{RAFT}/final-review-001.md`, SPEND, ROW }
		t.expect(stale({
			{ `{RAFT}/R0109.md`, SPEND, ROW },
			skeleton,
			filled,
			{ `{RAFT}/final-refute-001.md`, SPEND, ROW },
		})).toBe("")
		t.expect(stale({ skeleton, { DOC, SPEND, ROW }, filled })).toBe("")
		t.expect(has(stale({ skeleton, { "z-nile/engine/trace.luau", SPEND, ROW }, filled }), "after finish"))
			.toBe(true)
		t.expect(has(stale({ skeleton, filled, { DOC, SPEND, ROW } }), "after trace.md")).toBe(true)
	end)
end)
