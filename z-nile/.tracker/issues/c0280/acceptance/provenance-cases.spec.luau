--!strict
-- c0280: the trailers and commits, what a ticket's life says (select, merge, workerOf) and the trail log format.
-- Everything here is text in, text out.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local OPUS = "agent:claude-opus-5-5 effort high"

return t.spec("c0280 provenance from git", function(it)
	it("trailers and commits", function()
		t.expect(provenance.fromTrailer("Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"))
			.toBe("agent:claude-opus-5-5 effort unknown (from git)")
		t.expect(provenance.fromTrailer("Co-authored-by: Grok 4.7 <noreply@x.ai>"))
			.toBe("agent:grok-4-7 effort unknown (from git)")
		t.expect(provenance.fromTrailer("Signed-off-by: Phil <p@x>")).toBe(nil)
		-- every commit author's email in the log: a trailer with one of these is a person
		local people = { ["p@x"] = true, ["philip.bergen@me.com"] = true }
		local sonnet = "Claude Sonnet 5.5 <noreply@anthropic.com>"
		t.expect(provenance.fromCommit("Phil", { sonnet }, people))
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		t.expect(provenance.fromCommit("Phil", {}, people)).toBe("human:Phil (from git)")
		-- a trailer whose email is a commit author's elsewhere is a person, whatever name the commit's author has
		t.expect(provenance.fromCommit("Phil", { "Philip Bergen <philip.bergen@me.com>" }, people))
			.toBe("human:Phil (from git)")
		-- a person's trailer beside an agent's: the agent
		t.expect(
			provenance.fromCommit(
				"Phil",
				{ "Philip Bergen <p@x>", "Claude Opus 5.5 <noreply@anthropic.com>" },
				people
			)
		).toBe("agent:claude-opus-5-5 effort unknown (from git)")
		-- the last agent trailer wins
		t.expect(provenance.fromCommit("Phil", { "Claude Opus 5.5 <a@anthropic.com>", sonnet }, people))
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
	end)

	it("derive and merge", function()
		local DOC = "z-nile/.tracker/issues/c0010/c0010.md"
		local DONE = "z-nile/.tracker/issues/done/c0010/c0010.md"
		local sonnet = { "Claude Sonnet 5.5 <noreply@anthropic.com>" }
		local opus = { "Claude Opus 5.5 <noreply@anthropic.com>" }
		local n = 0
		local raftAt: { [string]: string } = {}
		-- 1790000000 is 2026-09-21 14:13:20 UTC; `day` counts from there; `raft` is the document's raft: after the commit
		local function commit(
			day: number,
			author: string,
			subject: string,
			trailers: { string },
			status: string,
			path: string,
			raft: string?
		): trail.Commit
			n += 1
			local sha = `sha{n}`
			if raft ~= nil then
				raftAt[sha] = raft
			end
			return {
				sha = sha,
				time = 1790000000 + day * 86400,
				subject = subject,
				status = status,
				path = path,
				order = n,
				doc = true,
				id = "c0010",
				author = author,
				email = `{author}@example.invalid`,
				trailers = trailers,
			}
		end
		local ACTIVE = "z-nile/.tracker/issues/active/c0010/c0010.md"
		local function sameSha(c: trail.Commit, status: string, path: string): trail.Commit
			local other = table.clone(c)
			other.status = status
			other.path = path
			other.order += 1
			return other
		end
		-- the item's life, newest first (what trail.read returns): 09-22 capture, 09-23 preparing, 09-24 new, 09-25 a
		-- rafting into R0011 (Bob), 09-26 unfold, 09-27 raft R0011 again (Fay), 09-28 ready (moves backlog -> active),
		-- 09-29 a restamp, 09-30 the move to done/ (a delete of the active path and an add of the done path in one commit)
		local done = commit(9, "Cy", "R0011: demo (#1)", sonnet, "A", DONE, "R0011")
		-- a later edit of the document under done/ is no delivery
		local later = commit(10, "Zed", "tracker: fix typo", {}, "M", DONE, "R0011")
		local life = {
			later,
			done,
			sameSha(done, "D", ACTIVE),
			commit(8, "Ida", "tracker: R0011 prepared", {}, "M", ACTIVE, "R0011"),
			commit(7, "Hal", "tracker: ready R0011 demo", {}, "A", ACTIVE, "R0011"),
			commit(6, "Fay", "tracker: raft R0011 again", {}, "M", DOC, "R0011"),
			commit(5, "Gus", "tracker: unfold c0010", {}, "M", DOC, ""),
			commit(4, "Bob", "tracker: prep R0010-R0011 rafts for c0010 (#12)", opus, "M", DOC, "R0011"),
			commit(3, "Dee", "tracker: c0010 new", {}, "M", DOC, ""),
			commit(2, "Dee", "tracker: c0010 preparing", {}, "M", DOC, ""),
			commit(1, "Ann", "tracker: new c0010 alpha", {}, "A", DOC, ""),
		}
		local people: { [string]: boolean } = {}
		for _, c in life do
			people[c.email or ""] = true
		end
		local d = provenance.select(life, "c0010", "done", "R0011", people, raftAt)
		t.expect((d.idea :: provenance.Entry).actor).toBe("human:Ann (from git)")
		-- a status commit is an entry of its own with its author; a `new` commit is the unblock; the capture is neither
		t.expect(#d.statuses).toBe(1)
		t.expect(d.statuses[1].event).toBe("status:preparing")
		t.expect(d.statuses[1].actor).toBe("human:Dee (from git)")
		t.expect(#d.unblocked).toBe(1)
		t.expect(d.unblocked[1].actor).toBe("human:Dee (from git)")
		-- the rafter is whoever made `raft:` the current value and it stayed so: Fay (09-27), not Bob (09-25, undone by the
		-- unfold), not the ready, the restamp or the move to done/ that kept the value
		t.expect((d.rafted :: provenance.Entry).actor).toBe("human:Fay (from git)")
		t.expect((d.rafted :: provenance.Entry).detail).toBe("raft=R0011")
		-- with no `raftAt` (the board reads none) there is no derived rafter, and the rest is as it was
		local blind = provenance.select(life, "c0010", "done", "R0011", people, {})
		t.expect(blind.rafted).toBe(nil)
		t.expect((blind.idea :: provenance.Entry).actor).toBe("human:Ann (from git)")
		t.expect(#blind.statuses).toBe(1)
		-- the delivery is the commit that first added the document under done/, and it is also the merge
		t.expect((d.delivered :: provenance.Entry).actor)
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		-- who merged is the commit's author, trailers ignored (a squash is authored by the user with the agent as co-author)
		t.expect((d.merged :: provenance.Entry).actor).toBe("human:Cy (from git)")
		-- an unfolded item (raft: empty) has no rafter, and a backlog item no delivery or merge
		local open =
			provenance.select({ life[9], life[10], life[11] }, "c0010", "backlog", "", people, raftAt)
		t.expect(open.rafted).toBe(nil)
		t.expect(open.delivered).toBe(nil)
		t.expect(open.merged).toBe(nil)
		-- a `new` commit that also changed the item's record is covered by its stored row; any other prints as derived
		local give = commit(8, "Eli", "tracker: c0010 new", {}, "M", DOC)
		local rec = table.clone(give)
		rec.path = "z-nile/.tracker/issues/c0010/provenance.md"
		rec.order += 1
		t.expect(
			#provenance.select({ give, rec, life[11] }, "c0010", "backlog", "", people, raftAt).unblocked
		)
			.toBe(0)
		t.expect(#provenance.select({ give, life[11] }, "c0010", "backlog", "", people, raftAt).unblocked)
			.toBe(1)
		-- an idea taken from a first add (no commit names the item) says so
		local weak = provenance.select(
			{ commit(1, "Zed", "tracker: rename things", {}, "A", DOC) },
			"c0010",
			"backlog",
			"",
			people,
			{}
		)
		t.expect((weak.idea :: provenance.Entry).actor).toBe("human:Zed (from git, first add)")
		t.expect((d.idea :: provenance.Entry).actor).toBe("human:Ann (from git)")
		-- merge: a stored row wins over a derived fallback of its event; oldest first by date, a derived entry before a
		-- stored one in the same minute. The stored dates fall inside the derived range (09-22 14:13 .. 09-28 14:13).
		local text = provenance.record(
			nil,
			"c0010",
			"confirmed",
			"human:Ann",
			'said="yes"',
			"2026-09-22 14:13"
		) :: string
		text = provenance.record(
			text,
			"c0010",
			"approved",
			"human:Ann",
			"design=aaaaaaaaaaaa",
			"2026-09-24 20:00"
		) :: string
		text = provenance.record(text, "c0010", "rafted", OPUS, "raft=R0011", "2026-09-27 15:00") :: string
		local rows = provenance.parse(text) :: { provenance.Row }
		local merged = provenance.merge(d, rows, "claude-opus-5-5-high")
		local events: { string } = {}
		for _, e in merged do
			table.insert(events, `{e.event}:{e.source}`)
		end
		t.expect(events).toEqual({
			"idea:git",
			"confirmed:record", -- the same minute as the idea: derived first, then stored
			"status:preparing:git",
			"unblocked:git",
			"approved:record",
			"rafted:record", -- the stored row; Fay's derived rafting is not repeated
			"delivered:git",
			"merged:git",
		})
		for _, e in merged do
			if e.event == "rafted" then
				t.expect(e.actor).toBe(OPUS)
			end
			if e.event == "delivered" then
				t.expect(string.find(e.detail, "worker=claude-opus-5-5-high", 1, true) ~= nil).toBe(true)
			end
		end
		-- the worker comes from a spend row: the model column today, host and CLI once c0254 adds them
		t.expect(provenance.workerOf({ model = "claude-opus-5-5-high" })).toBe("claude-opus-5-5-high")
		t.expect(provenance.workerOf({ model = "claude-opus-5-5-high", host = "h1", cli = "claude" }))
			.toBe("h1/claude/claude-opus-5-5-high")
		t.expect(provenance.workerOf({})).toBe(nil)
		t.expect(provenance.workerOf(nil)).toBe(nil)
	end)

	it("trail log", function()
		-- the log format: a header, three tagged lines, then the change lines; a trailer value can look like anything
		local log = "@@abc123 1790000000 tracker: c0010 new\n@ADee\n@Edee@example.invalid\n@TClaude Opus 5.5 <noreply@anthropic.com>\31M\tpath <x>\n"
			.. "M\tz-nile/.tracker/issues/c0010/c0010.md\n"
			.. "A\tz-nile/.tracker/issues/c0010/provenance.md\n"
		local commits = trail.parse(log, { "z-nile/.tracker/issues/c0010" }, function(_: string): boolean
			return true
		end)
		-- provenance.md is not the item's document
		t.expect(#commits).toBe(2)
		t.expect(commits[1].author).toBe("Dee")
		t.expect(commits[1].email).toBe("dee@example.invalid")
		t.expect(commits[1].subject).toBe("tracker: c0010 new")
		t.expect(commits[1].doc).toBe(true)
		t.expect(commits[2].doc).toBe(false)
		t.expect(#(commits[1].trailers :: { string })).toBe(2)
		t.expect((commits[1].trailers :: { string })[2]).toBe("M\tpath <x>")
	end)

	it(
		"a stored row wins over the git fallback of its event only for the same raft; the worker row",
		function()
			local derived: provenance.Derived = {
				statuses = {},
				unblocked = {},
				rafted = {
					when = "2026-10-06 09:00",
					event = "rafted",
					actor = "human:Fay (from git)",
					detail = "raft=R0011",
					source = "git",
				},
				delivered = {
					when = "2026-10-07 09:00",
					event = "delivered",
					actor = "human:Cy (from git)",
					detail = "raft=R0011",
					source = "git",
				},
			}
			local function stored(event: string, detail: string): provenance.Row
				return { when = "2026-10-06 12:00", event = event, actor = OPUS, detail = detail }
			end
			local function events(rows: { provenance.Row }): { string }
				local out: { string } = {}
				for _, e in provenance.merge(derived, rows, "m") do
					table.insert(out, `{e.event}:{e.source}:{e.detail}`)
				end
				return out
			end
			-- a stored row for an earlier raft is history: the git fallback of the current raft stays
			t.expect(events({ stored("rafted", "raft=R0010") })).toEqual({
				"rafted:git:raft=R0011",
				"rafted:record:raft=R0010",
				"delivered:git:raft=R0011; worker=m",
			})
			-- a stored row for the current raft replaces it, and the worker joins the stored delivered row too
			t.expect(events({ stored("rafted", "raft=R0011"), stored("delivered", "raft=R0011; via=x") }))
				.toEqual({
					"rafted:record:raft=R0011",
					"delivered:record:raft=R0011; via=x; worker=m",
				})
			-- the worker: the newest deliver row with a model, else the newest build row with one, else none
			local function spend(phase: string, model: string?): provenance.Spend
				return { phase = phase, model = model }
			end
			local picked =
				provenance.workerRow({ spend("deliver", "a"), spend("build", "b"), spend("deliver", "c") })
			t.expect((picked :: provenance.Spend).model).toBe("c")
			picked = provenance.workerRow({
				spend("deliver", nil),
				spend("build", "b"),
				spend("build", "d"),
				spend("prep", "e"),
			})
			t.expect((picked :: provenance.Spend).model).toBe("d")
			t.expect(provenance.workerRow({ spend("deliver", nil), spend("prep", "e") })).toBe(nil)
		end
	)

	it("docs", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local function has(path: string, ...: string)
			local text = fs.readFile(`{top}/{path}`)
			for _, needle in { ... } do
				if not string.find(text, needle, 1, true) then
					error(`{path} lacks {needle}`, 2)
				end
			end
		end
		has(
			"z-nile/skills/zz-rules/SKILL.md",
			"| who | `./zn who <id>` |",
			"`who <id>` (it reads the history and writes nothing)",
			"(from git, first add)",
			"status:<status>",
			"worker="
		)
		has("z-nile/README.md", "./zn who <id>")
		has("z-nile/engine/main.luau", "  who <id>")
	end)

	it("cut: the last life, a compaction cut starts it, and the note names the map", function()
		local function c(sha: string, time: number, status: string, order: number): trail.Commit
			return {
				sha = sha,
				time = time,
				subject = "x",
				status = status,
				path = "z-nile/.tracker/issues/c0010/c0010.md",
				order = order,
				doc = true,
				id = "c0010",
			}
		end
		local commits = { c("bbbbbbbbbb", 3, "M", 1), c("aaaaaaaaaa", 2, "M", 2), c("9999999999", 1, "A", 3) }
		local plain, none = trail.cut(commits, {})
		t.expect(#plain).toBe(3)
		t.expect(#none).toBe(0)
		local cut, notes = trail.cut(commits, { aaaaaaaaaa = "z-nile/compaction.txt" })
		t.expect(#cut).toBe(2)
		t.expect(cut[2].sha).toBe("aaaaaaaaaa")
		t.expect(#notes).toBe(1)
		t.expect(notes[1].file).toBe("z-nile/compaction.txt")
		t.expect(notes[1].sha).toBe("aaaaaaa")
	end)
end)
