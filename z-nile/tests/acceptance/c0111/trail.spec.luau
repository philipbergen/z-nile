--!strict
-- c0111 AC10: an item's trail. `life` finds where an item's life under one id starts and `since` narrows it to a
-- later commit that starts one (a compaction); `isDoc` tells an item's document from its
-- other files; `parse` keeps only changes directly in the item's folders; `namedIds` reads a `tracker: new` subject;
-- `oldestAdd` and `capture` pick the commit; `ambiguous` finds two items that held one id at once. Pure; reads nothing.
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
		doc = true,
		id = "c0010",
	}
end

-- a document change of c0070 at `path`, in commit `sha` made at `time`
local function d(sha: string, time: number, status: string, path: string): trail.Commit
	return {
		sha = sha,
		time = time,
		subject = sha,
		status = status,
		path = path,
		order = 0,
		doc = true,
		id = "c0070",
	}
end

local function shas(list: { trail.Commit }): string
	local out = {}
	for _, c in list do
		table.insert(out, c.sha)
	end
	return table.concat(out, ",")
end

return t.spec("c0111 an item's trail", function(it)
	it("starts an item's life where its document last went from absent to present", function()
		local B, A = "tracker/issues/c0070/c0070.md", "tracker/issues/done/c0070/c0070.md"
		-- a removed item, then a new one at the same number: only the new life counts
		local reused = { d("e", 500, "M", B), d("c", 300, "A", B), d("b", 200, "D", B), d("a", 100, "A", B) }
		local lived, start = trail.life(reused)
		t.expect(shas(lived)).toBe("e,c")
		t.expect((start :: trail.Commit).sha).toBe("c")
		-- a move to done/ deletes and adds in one commit: the same life
		local moved = { d("b", 200, "D", B), d("b", 200, "A", A), d("a", 100, "A", B) }
		t.expect((select(2, trail.life(moved)) :: trail.Commit).sha).toBe("a")
		-- a rename within one folder (legacy slug to <id>.md) is the same life too
		local slug = "old"
		local legacy = `tracker/issues/c0070/c0070-{slug}.md`
		local renamed = { d("b", 200, "A", B), d("b", 200, "D", legacy), d("a", 100, "A", legacy) }
		t.expect((select(2, trail.life(renamed)) :: trail.Commit).sha).toBe("a")
		-- a commit that touched only other files is not a start; no document change at all gives every commit
		local review = d("x", 50, "A", "tracker/issues/c0070/review-001.md")
		review.doc = false
		local none, nostart = trail.life({ review })
		t.expect(shas(none)).toBe("x")
		t.expect(nostart).toBe(nil)
	end)

	it(
		"narrows a life to a newer commit that starts one, such as a compaction renaming onto the id",
		function()
			local B = "tracker/issues/c0040/c0040.md"
			local lived = { d("c", 300, "M", B), d("b", 200, "M", B), d("a", 100, "A", B) }
			local start = lived[3]
			local narrowed, at = trail.since(lived, start, function(c: trail.Commit): boolean
				return c.sha == "b"
			end)
			t.expect(shas(narrowed)).toBe("c,b")
			t.expect((at :: trail.Commit).sha).toBe("b")
			local same, keep = trail.since(lived, start, function(_: trail.Commit): boolean
				return false
			end)
			t.expect(shas(same)).toBe("c,b,a")
			t.expect(keep).toBe(start)
		end
	)

	it("finds two items holding one id at once, but not a move or a rename in one folder", function()
		local function c(sha: string, time: number, status: string, path: string): trail.Commit
			return {
				sha = sha,
				time = time,
				subject = "x",
				status = status,
				path = path,
				order = 0,
				doc = true,
				id = "c0070",
			}
		end
		local moved = {
			c("b", 200, "D", "tracker/issues/c0070/c0070.md"),
			c("b", 200, "A", "tracker/issues/done/c0070/c0070.md"),
			c("a", 100, "A", "tracker/issues/c0070/c0070.md"),
		}
		t.expect(trail.ambiguous(moved)).toBe(false)
		-- a legacy slug name, built so the c0044 guard (no literal <ID>-<slug>.md in a spec) does not see it
		local slug = "old"
		local legacy = `tracker/issues/c0070/c0070-{slug}.md`
		local renamedInPlace = {
			c("b", 200, "A", "tracker/issues/c0070/c0070.md"),
			c("b", 200, "D", legacy),
			c("a", 100, "A", legacy),
		}
		t.expect(trail.ambiguous(renamedInPlace)).toBe(false)
		local twoCopies = {
			c("b", 200, "A", "tracker/issues/done/c0070/c0070.md"),
			c("a", 100, "A", "tracker/issues/c0070/c0070.md"),
		}
		t.expect(trail.ambiguous(twoCopies)).toBe(true)
		-- the same folder under two ids (before and after a compaction) is not two items
		local other = c("a", 100, "A", "tracker/issues/c0700/c0700.md")
		other.id = "c0700"
		t.expect(trail.ambiguous({ c("b", 200, "A", "tracker/issues/done/c0070/c0070.md"), other }))
			.toBe(false)
	end)

	it("reads the ids a `tracker: new` subject names", function()
		t.expect(trail.namedIds("tracker: new c0114 c0115 c0116 z-nile chores"))
			.toEqual({ "c0114", "c0115", "c0116" })
		t.expect(trail.namedIds("tracker: new c0119 c0120; record decisions on c0114-c0118"))
			.toEqual({ "c0119", "c0120" })
		t.expect(trail.namedIds("tracker: new raft R0010 r")).toEqual({})
		t.expect(trail.namedIds("tracker: new c0810–c0850 leftovers")).toEqual({})
		t.expect(trail.namedIds("tracker: scope c0010 decided")).toEqual({})
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
				doc = true,
			},
			{
				sha = "bbb",
				time = 200,
				subject = "tracker: new c0010 One",
				status = "A",
				path = "tracker/issues/c0010/c0010.md",
				order = 2,
				doc = true,
			},
			{
				sha = "ccc",
				time = 100,
				subject = "",
				status = "D",
				path = "tracker/issues/done/c0010/c0010.md",
				order = 3,
				doc = true,
			},
		})
	end)

	it(
		"picks the earliest add, and the capture: the newest `tracker: new` naming the item's id then",
		function()
			local commits = {
				commit("f", 600, "tracker: scope c0010 the user decided", "M", 1),
				commit("e", 500, "tracker: new raft R0010 x", "M", 2),
				commit("g", 450, "tracker: new c0050 other; edits c0010 too", "M", 3),
				commit("d", 400, "tracker: prep R0010 x", "M", 4),
				commit("c", 300, "tracker: new c0010 Landed", "M", 5),
				commit("b", 200, "tracker: new c0010 stub", "A", 6),
				commit("a", 100, "backlog", "A", 7),
			}
			t.expect((trail.oldestAdd(commits) :: trail.Commit).sha).toBe("a")
			local got, isCapture = trail.capture(commits)
			t.expect((got :: trail.Commit).sha).toBe("c")
			t.expect(isCapture).toBe(true)
			-- before a compaction the item had another id, and the commit carries it
			local landedOld = commit("o", 60, "tracker: new c0100 Landed before", "M", 2)
			landedOld.id = "c0100"
			local stubOld = commit("p", 50, "backlog", "A", 3)
			stubOld.id = "c0100"
			local renamed = { commit("d", 400, "tracker: prep R0010 x", "M", 1), landedOld, stubOld }
			t.expect((trail.capture(renamed) :: trail.Commit).sha).toBe("o")
			local none =
				{ commit("d", 400, "tracker: prep R0010 x", "M", 1), commit("a", 100, "backlog", "A", 2) }
			local fallback, marked = trail.capture(none)
			t.expect((fallback :: trail.Commit).sha).toBe("a")
			t.expect(marked).toBe(false)
			-- a deletion is never the capture, and equal times keep the log's order
			local tie = {
				commit("y", 100, "tracker: new c0010 removed", "D", 1),
				commit("x", 100, "tracker: new c0010 kept", "A", 2),
			}
			t.expect((trail.capture(tie) :: trail.Commit).sha).toBe("x")
			t.expect((trail.capture({}))).toBe(nil)
			t.expect(trail.oldestAdd({ commit("m", 1, "x", "M", 1) })).toBe(nil)
			-- with no add at all, the fallback is the earliest commit
			local only, isCap = trail.capture({ commit("m", 2, "x", "M", 1), commit("n", 1, "y", "M", 2) })
			t.expect((only :: trail.Commit).sha).toBe("n")
			t.expect(isCap).toBe(false)
		end
	)
end)
