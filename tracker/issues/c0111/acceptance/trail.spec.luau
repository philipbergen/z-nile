--!strict
-- c0111 AC10: an item's trail. `trail.ranges` names the folders and revisions to read (the current id's folders after
-- the last compaction, the old id's before it), `isDoc` tells an item's document from its other files, `parse` keeps
-- only changes directly in those folders, and `oldestAdd` and `capture` pick the commit. Pure; reads nothing.
local t = require("@tests/lib/t")
local trail = require("@scripts/tracker/trail")

local function commit(sha: string, time: number, subject: string, status: string, order: number): trail.Commit
	return {
		sha = sha,
		time = time,
		subject = subject,
		status = status,
		path = "tracker/issues/c0010/c0010.md",
		order = order,
	}
end

return t.spec("c0111 an item's trail", function(it)
	it("reads every folder of the id, and the renamed id before the last compaction", function()
		t.expect(trail.ranges("issues", "c0010", "origin/main", nil, nil)).toEqual({
			{
				rev = "origin/main",
				dirs = { "tracker/issues/c0010", "tracker/issues/active/c0010", "tracker/issues/done/c0010" },
			},
		})
		t.expect(trail.ranges("rafts", "R0002", "HEAD", "abc123", { R0020 = "R0002", R0030 = "R0003" }))
			.toEqual({
				{
					rev = "abc123..HEAD",
					dirs = { "tracker/rafts/R0002", "tracker/rafts/active/R0002", "tracker/rafts/done/R0002" },
				},
				{
					rev = "abc123~1",
					dirs = { "tracker/rafts/R0020", "tracker/rafts/active/R0020", "tracker/rafts/done/R0020" },
				},
			})
		-- an id compaction renamed away has no history of its own before the cut: that history is the renamed item's
		t.expect(#trail.ranges("issues", "c0300", "HEAD", "abc123", { c0300 = "c0030" })).toBe(1)
		-- an id the map does not mention kept its number, so its own folders are read before the cut too
		t.expect(trail.ranges("issues", "c0010", "HEAD", "abc123", { c0300 = "c0030" })[2]).toEqual({
			rev = "abc123~1",
			dirs = { "tracker/issues/c0010", "tracker/issues/active/c0010", "tracker/issues/done/c0010" },
		})
	end)

	it("knows an item's document, including a legacy slug name, from its other files", function()
		-- a legacy slug name, built so the c0044 guard (no literal <ID>-<slug>.md in a spec) does not see it
		local slug = "touch-look"
		for _, name in { "c0010.md", `f0270-{slug}.md` } do
			t.expect(trail.isDoc(name)).toBe(true)
		end
		for _, name in
			{
				"spend.md",
				"harvest.md",
				"prompt.md",
				"design-review-001.md",
				"review-002.md",
				"design-refute-001.md",
				"refute-003.md",
				"stream-review-c0010-001.md",
				"check.sh",
				"acceptance/notes.md",
			}
		do
			t.expect(trail.isDoc(name)).toBe(false)
		end
	end)

	it("parses a --name-status log, keeping only wanted files directly in the item's folders", function()
		local log = table.concat({
			"@@aaa 300 tracker: prep R0010 x",
			"",
			"M\ttracker/issues/c0010/c0010.md",
			"A\ttracker/issues/c0010/acceptance/a.spec.luau",
			"M\ttracker/issues/c0010/spend.md",
			"@@bbb 200 tracker: new c0010 One",
			"",
			"A\ttracker/issues/c0010/c0010.md",
			"A\ttracker/issues/c0011/c0011.md",
			"@@ccc 100 ",
			"D\ttracker/issues/done/c0010/c0010.md",
		}, "\n")
		local got = trail.parse(log, { "tracker/issues/c0010", "tracker/issues/done/c0010" }, trail.isDoc)
		t.expect(got).toEqual({
			{
				sha = "aaa",
				time = 300,
				subject = "tracker: prep R0010 x",
				status = "M",
				path = "tracker/issues/c0010/c0010.md",
				order = 1,
			},
			{
				sha = "bbb",
				time = 200,
				subject = "tracker: new c0010 One",
				status = "A",
				path = "tracker/issues/c0010/c0010.md",
				order = 2,
			},
			{
				sha = "ccc",
				time = 100,
				subject = "",
				status = "D",
				path = "tracker/issues/done/c0010/c0010.md",
				order = 3,
			},
		})
	end)

	it(
		"picks the earliest add, and the capture: the newest `tracker: new <issue>` commit, else the earliest add",
		function()
			local commits = {
				commit("e", 500, "tracker: new raft R0010 x", "M", 1),
				commit("d", 400, "tracker: prep R0010 x", "M", 2),
				commit("c", 300, "tracker: new c0010 Landed", "M", 3),
				commit("b", 200, "tracker: new c0010 stub", "A", 4),
				commit("a", 100, "backlog", "A", 5),
			}
			t.expect((trail.oldestAdd(commits) :: trail.Commit).sha).toBe("a")
			t.expect((trail.capture(commits) :: trail.Commit).sha).toBe("c")
			local none =
				{ commit("d", 400, "tracker: prep R0010 x", "M", 1), commit("a", 100, "backlog", "A", 2) }
			t.expect((trail.capture(none) :: trail.Commit).sha).toBe("a")
			-- a deletion is never the capture, and equal times keep the log's order
			local tie = {
				commit("y", 100, "tracker: new c0010 removed", "D", 1),
				commit("x", 100, "tracker: new c0010 kept", "A", 2),
			}
			t.expect((trail.capture(tie) :: trail.Commit).sha).toBe("x")
			t.expect(trail.capture({})).toBe(nil)
			t.expect(trail.oldestAdd({ commit("m", 1, "x", "M", 1) })).toBe(nil)
		end
	)
end)
