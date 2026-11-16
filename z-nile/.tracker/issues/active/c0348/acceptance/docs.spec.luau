--!strict
-- c0348 AC6: zz-execute and zz-rules name one route for a raft's deliver row: after `./zn done`, in the raft's
-- worktree, `./zn spend <R-id> --phase deliver`, which publishes the row to origin/main itself. Neither still tells
-- the reader to record it before the merge, or that the command pushes nothing whatever the phase. The engine's own
-- usage comment says the same. Reads the files as text, from z-nile's home.
local fs = require("@lune/fs")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
-- the one line of `text` that starts with `prefix`
local function line(text: string, prefix: string): string
	local found: string? = nil
	for l in string.gmatch(text, "[^\n]+") do
		if string.sub(l, 1, #prefix) == prefix then
			if found then
				error(`two lines start with "{prefix}"`, 2)
			end
			found = l
		end
	end
	return found or error(`no line starts with "{prefix}"`, 2)
end

return t.spec("c0348 the skills name one route for the deliver row", function(it)
	it("zz-execute's after-merge step runs it in the raft's worktree and says it publishes", function()
		local text = fs.readFile("skills/zz-execute/SKILL.md")
		local step = line(text, "2. After the merge and before the final report, ")
		t.expect(has(step, "`./zn spend R0010 --phase deliver` in the raft's worktree")).toBe(true)
		t.expect(has(step, "publishes it to `origin/main` itself")).toBe(true)
		t.expect(has(step, "`published R0010 deliver to origin/main <sha>`")).toBe(true)
		-- a failed publish is not left for the cleanup to throw away
		t.expect(has(step, "nothing was recorded")).toBe(true)
		t.expect(has(step, "run it again before the cleanup")).toBe(true)
		-- a row that stayed on the branch at this step would be lost with the worktree
		t.expect(has(step, "If it says the row stays on this branch, the cleanup would lose it")).toBe(true)
		t.expect(has(step, "post a `BLOCKED:` comment quoting that line")).toBe(true)
		t.expect(has(step, "Do not pass `--time` or `--tokens`")).toBe(true)
		-- the step still comes before the report and the cleanup
		local at = string.find(text, step, 1, true) :: number
		t.expect((string.find(text, "\n3. Write the final report", at, true) or 0) > at).toBe(true)
	end)

	it("zz-rules' spend row and its deliver line say the same, and the old advice is gone", function()
		local text = fs.readFile("skills/zz-rules/SKILL.md")
		local row = line(text, "| spend | `./zn spend <id> --phase")
		t.expect(has(row, "commits that file on the current branch")).toBe(true)
		t.expect(has(row, "a `deliver` row for work that is done on `origin/main` is also published there"))
			.toBe(true)
		t.expect(has(row, "it pushes nothing.")).toBe(false)
		local deliver = line(text, "- `deliver`: ")
		t.expect(has(deliver, "`./zn spend <R-id> --phase deliver` after `./zn done`")).toBe(true)
		t.expect(has(deliver, "in the raft's worktree")).toBe(true)
		t.expect(has(deliver, "publishes the row to `origin/main`")).toBe(true)
		t.expect(
			has(
				deliver,
				"For an item that is not done, or whose rows on this branch have not landed, it commits"
			)
		).toBe(true)
		t.expect(has(text, "record it before the merge")).toBe(false)
		t.expect(has(text, "commits its row on the current branch and pushes nothing")).toBe(false)
		-- the phases that ride a branch are as they were
		t.expect(has(text, "The command commits on the branch and pushes nothing.")).toBe(true)
	end)

	it(
		"zz-rules' direct-push rule lists the one measured-rows file a spend publishes, and keeps what it pinned",
		function()
			local rule = line(fs.readFile("skills/zz-rules/SKILL.md"), "- **The direct-push exception.**")
			t.expect(has(rule, "`./zn spend <id> --phase deliver` for work that is done on `origin/main`"))
				.toBe(true)
			t.expect(has(rule, "a done issue's `spend.d/<writer>.tsv`")).toBe(true)
			t.expect(has(rule, "rows appended only and only with a `deliver` row among them")).toBe(true)
			t.expect(has(rule, "is not pushed by `./zn spend`")).toBe(false)
			-- what c0081's, c0084's and c0072's checks read on this line is still there
			t.expect(has(rule, "`z-nile/next`")).toBe(true)
			t.expect(has(rule, "only go up")).toBe(true)
			t.expect(has(rule, "`spend.md`")).toBe(true)
			t.expect(has(rule, "`./zn land`")).toBe(true)
		end
	)

	it("no skill, and no line of the engine, still says a spend row is pushed nowhere", function()
		t.expect(has(fs.readFile("engine/main.luau"), "pushed nowhere")).toBe(false)
		for _, skill in fs.readDir("skills") do
			local path = `skills/{skill}/SKILL.md`
			if fs.isFile(path) then
				t.expect(has(fs.readFile(path), "record it before the merge")).toBe(false)
			end
		end
	end)
end)
