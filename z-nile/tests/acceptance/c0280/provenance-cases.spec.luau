--!strict
-- c0280: the trailers and commits, what a ticket's life says (select, merge, workerOf) and the trail log format.
-- Everything here is text in, text out.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local OPUS = "agent:claude-opus-5-5 effort high"
local NOMARK: provenance.Mark = { note = "", cut = false }

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
		-- fromTrailer reads one line with the same rule: a person's email is no agent, a value with no email is one
		t.expect(provenance.fromTrailer("Co-Authored-By: Philip Bergen <PHILIP.bergen@me.com>", people))
			.toBe(nil)
		t.expect(provenance.fromTrailer("Co-Authored-By: Cursor", people))
			.toBe("agent:cursor effort unknown (from git)")
		t.expect(provenance.fromCommit("Phil", { "Cursor" }, people))
			.toBe("agent:cursor effort unknown (from git)")
		t.expect(provenance.fromCommit("Phil", { "Philip Bergen <PHILIP.BERGEN@me.com>" }, people))
			.toBe("human:Phil (from git)")
		-- the last agent trailer wins
		t.expect(provenance.fromCommit("Phil", { "Claude Opus 5.5 <a@anthropic.com>", sonnet }, people))
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
	end)

	it("derive and merge", function()
		local DOC = "z-nile/.tracker/issues/c0010/c0010.md"
		local ACTIVE = "z-nile/.tracker/issues/active/c0010/c0010.md"
		local DONE = "z-nile/.tracker/issues/done/c0010/c0010.md"
		local OTHER_DONE = "pickman/.tracker/issues/done/c0010/c0010.md"
		local REC = "z-nile/.tracker/issues/c0010/provenance.md"
		local sonnet = { "Claude Sonnet 5.5 <noreply@anthropic.com>" }
		local opus = { "Claude Opus 5.5 <noreply@anthropic.com>" }
		local n = 0
		local fronts: { [string]: provenance.Front } = {}
		-- 1790000000 is 2026-09-21 14:13:20 UTC; `day` counts from there; `front` is the document's status word and
		-- raft: after the commit (keyed by the path the commit added or modified)
		local function commit(
			day: number,
			author: string,
			subject: string,
			trailers: { string },
			status: string,
			path: string,
			word: string?,
			raft: string?,
			secs: number?
		): trail.Commit
			n += 1
			local sha = `sha{n}`
			if word ~= nil and status ~= "D" then
				fronts[`{sha}:{path}`] = { status = `{word}-a-b-c`, raft = raft or "" }
			end
			return {
				sha = sha,
				time = 1790000000 + day * 86400 + (secs or 0),
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
		-- a second row of the same sha (a move is a delete and an add in one commit)
		local function alsoRow(c: trail.Commit, status: string, path: string, word: string?, raft: string?)
			local other = table.clone(c)
			other.status = status
			other.path = path
			other.order += 1
			if word ~= nil and status ~= "D" then
				fronts[`{c.sha}:{path}`] = { status = `{word}-a-b-c`, raft = raft or "" }
			end
			return other
		end
		-- the item's life, newest first (what trail.read returns): 09-22 capture, 09-23 preparing, 09-24 new (the unblock),
		-- 09-25 a prep PR's squash with an agent trailer that also rafts into R0011 (prepared), 09-26 unfold, 09-27 raft
		-- R0011 again (Fay), 09-28 ready (moves backlog -> active/, status active), 09-29 a restamp, 09-30 the move to
		-- done/, 10-01 a later edit under done/
		local capture = commit(1, "Ann", "tracker: new c0010 alpha", {}, "A", DOC, "new", "")
		local preparing = commit(2, "Dee", "tracker: c0010 preparing", {}, "M", DOC, "preparing", "")
		local give = commit(3, "Dee", "tracker: c0010 new", {}, "M", DOC, "new", "")
		local prep = commit(
			4,
			"Bob",
			"tracker: prep R0010-R0011 rafts for c0010 (#12)",
			opus,
			"M",
			DOC,
			"prepared",
			"R0011"
		)
		local unfold = commit(5, "Gus", "tracker: unfold c0010", {}, "M", DOC, "prepared", "")
		local again = commit(6, "Fay", "tracker: raft R0011 again", {}, "M", DOC, "prepared", "R0011")
		local ready = commit(7, "Hal", "tracker: ready R0011 demo", {}, "A", ACTIVE, "active", "R0011")
		local restamp = commit(8, "Ida", "tracker: R0011 prepared", {}, "M", ACTIVE, "active", "R0011")
		local done = commit(9, "Cy", "R0011: demo (#1)", sonnet, "A", DONE, "done", "R0011")
		local later = commit(10, "Zed", "tracker: fix typo", {}, "M", DONE, "done", "R0011")
		local life = {
			later,
			done,
			alsoRow(done, "D", ACTIVE, nil),
			restamp,
			ready,
			alsoRow(ready, "D", DOC, nil),
			again,
			unfold,
			prep,
			give,
			preparing,
			capture,
		}
		-- a delete-only change of the document carries no front, and one given anyway is never read
		fronts[`{done.sha}:{ACTIVE}`] = { status = "active-a-b-c", raft = "R9999" }
		local people: { [string]: boolean } = {}
		for _, c in life do
			people[c.email or ""] = true
		end
		local d = provenance.select(life, people, fronts, NOMARK)
		t.expect((d.idea :: provenance.Entry).actor).toBe("human:Ann (from git)")
		-- every change of the status word is an entry with the author of the commit that made it (a squash with an
		-- agent trailer is the agent's); a restamp (same word) is none; a move that also changes the word is one entry
		local words: { string } = {}
		for _, e in d.statuses do
			table.insert(words, `{e.event}:{e.actor}`)
		end
		t.expect(words).toEqual({
			"status:preparing:human:Dee (from git)",
			"status:prepared:agent:claude-opus-5-5 effort unknown (from git)",
			"status:active:human:Hal (from git)",
		})
		-- the `new` back to a word is the unblock, once, and never also a status line
		t.expect(#d.unblocked).toBe(1)
		t.expect(d.unblocked[1].actor).toBe("human:Dee (from git)")
		-- the rafter is whoever made `raft:` the current value and it stayed so: Fay (09-27), not Bob (09-25, undone by
		-- the unfold), not the ready, the restamp or the move to done/ that kept the value
		t.expect((d.rafted :: provenance.Entry).actor).toBe("human:Fay (from git)")
		t.expect((d.rafted :: provenance.Entry).detail).toBe("raft=R0011")
		-- the delivery is the commit that first brought the document into done/; the merge names the same commit's
		-- agent trailer (the user's rule), and the later edit under done/ is neither
		t.expect((d.delivered :: provenance.Entry).actor)
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		t.expect((d.delivered :: provenance.Entry).detail).toBe("raft=R0011")
		t.expect((d.merged :: provenance.Entry).actor)
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		-- a landing without an agent trailer: the delivery names the author, the merge no actor
		local plain = commit(9, "Cy", "R0011: demo (#1)", {}, "A", DONE, "done", "R0011")
		local landed = provenance.select({ plain, ready, capture }, people, fronts, NOMARK)
		t.expect((landed.delivered :: provenance.Entry).actor).toBe("human:Cy (from git)")
		t.expect((landed.merged :: provenance.Entry).actor).toBe("unknown")
		-- a `--no-ff` landing: the merge commit has no trailer, its second parent (the stack's top layer) does
		local bound = commit(9, "Cy", "R0011: bind c0010", {}, "A", DONE, "done", "R0011")
		bound.parents = { "p1", "p2" }
		bound.sideTrailers = opus
		local noff = provenance.select({ bound, ready, capture }, people, fronts, NOMARK)
		t.expect((noff.delivered :: provenance.Entry).actor)
			.toBe("agent:claude-opus-5-5 effort unknown (from git)")
		t.expect((noff.merged :: provenance.Entry).actor)
			.toBe("agent:claude-opus-5-5 effort unknown (from git)")
		-- a move between roots after the delivery (a delete and an add under done/ of another root) is no arrival
		local moved = commit(
			11,
			"Rex",
			"R0043: z-nile 2, the tracker moves into z-nile",
			{},
			"A",
			OTHER_DONE,
			"done",
			"R0011"
		)
		local both = provenance.select(
			{ moved, alsoRow(moved, "D", DONE, nil), done, alsoRow(done, "D", ACTIVE, nil), ready, capture },
			people,
			fronts,
			NOMARK
		)
		t.expect((both.delivered :: provenance.Entry).actor)
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		-- no `raftAt` front, no rafter; with no fronts at all there are no status changes, and the idea stays
		local blind = provenance.select(life, people, {}, NOMARK)
		t.expect(blind.rafted).toBe(nil)
		t.expect(#blind.statuses).toBe(0)
		t.expect((blind.idea :: provenance.Entry).actor).toBe("human:Ann (from git)")
		-- a life cut at a compaction: the commit that starts it gives the marked idea and nothing else (no rafter, no
		-- delivery from a re-add under done/)
		local mark: provenance.Mark =
			{ note = "history before aaaaaaa not followed: it changed z-nile/compaction.txt", cut = true }
		local start = commit(20, "Phil", "tracker: compact ids (#64)", opus, "M", DOC, "prepared", "R0011")
		local after = commit(21, "Hal", "tracker: ready R0011 demo", {}, "A", ACTIVE, "active", "R0011")
		local cut = provenance.select({ after, alsoRow(after, "D", DOC, nil), start }, people, fronts, mark)
		t.expect((cut.idea :: provenance.Entry).detail).toBe(mark.note)
		t.expect((cut.idea :: provenance.Entry).actor).toBe("human:Phil (from git, first add)")
		t.expect(cut.rafted).toBe(nil)
		local uncut =
			provenance.select({ after, alsoRow(after, "D", DOC, nil), start }, people, fronts, NOMARK)
		t.expect((uncut.rafted :: provenance.Entry).actor)
			.toBe("agent:claude-opus-5-5 effort unknown (from git)")
		local readd = commit(22, "Phil", "tracker: compact ids (#64)", opus, "A", DONE, "done", "R0011")
		t.expect(provenance.select({ readd }, people, fronts, mark).delivered).toBe(nil)
		-- nor is a later edit under done/ of a life that started there
		local edit = commit(23, "Zed", "tracker: fix typo", {}, "M", DONE, "done", "R0011")
		t.expect(provenance.select({ edit, readd }, people, fronts, mark).delivered).toBe(nil)
		-- a reopened item delivered again: the delivery is the first arrival
		local reopen = commit(24, "Hal", "tracker: reopen c0010", {}, "A", ACTIVE, "active", "R0011")
		local again2 = commit(25, "Zed", "R0012: again (#9)", {}, "A", DONE, "done", "R0011")
		local twice = provenance.select(
			{ again2, reopen, alsoRow(reopen, "D", DONE, nil), done, ready, capture },
			people,
			fronts,
			NOMARK
		)
		t.expect((twice.delivered :: provenance.Entry).actor)
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		-- a `release` give-back (preparing -> new, not by a `tracker: <id> new` commit) is a status change; a raft's
		-- give-back `tracker: R0011 new` that changes this issue is the unblock; a commit that kept the word is nothing
		local base = commit(30, "Ann", "tracker: new c0010 alpha", {}, "A", DOC, "preparing", "")
		local released = commit(31, "Rel", "tracker: release R0083", {}, "M", DOC, "new", "")
		local raftBack = commit(32, "Ray", "tracker: R0011 new", {}, "M", DOC, "preparing", "")
		local raftNew = commit(33, "Ray", "tracker: R0011 new", {}, "M", DOC, "new", "")
		local members = commit(34, "Mem", "tracker: R0065 members", {}, "M", DOC, "new", "")
		local g = provenance.select({ members, raftNew, raftBack, released, base }, people, fronts, NOMARK)
		local got: { string } = {}
		for _, e in g.statuses do
			table.insert(got, `{e.event}:{e.actor}`)
		end
		t.expect(got).toEqual({ "status:new:human:Rel (from git)", "status:preparing:human:Ray (from git)" })
		t.expect(#g.unblocked).toBe(1)
		t.expect(g.unblocked[1].actor).toBe("human:Ray (from git)")
		-- a `new` commit that also changed the item's record is covered by its stored row
		local cover = commit(36, "Eli", "tracker: c0010 new", {}, "M", DOC, "preparing", "")
		local coverNew = commit(37, "Eli", "tracker: c0010 new", {}, "M", DOC, "new", "")
		local rec = table.clone(coverNew)
		rec.path = REC
		rec.order += 1
		t.expect(#provenance.select({ coverNew, rec, cover, base }, people, fronts, NOMARK).unblocked).toBe(0)
		t.expect(#provenance.select({ coverNew, cover, base }, people, fronts, NOMARK).unblocked).toBe(1)
		-- an idea taken from a first add (no commit names the item) says so
		local weak = provenance.select(
			{ commit(1, "Zed", "tracker: rename things", {}, "A", DOC, "new", "") },
			people,
			fronts,
			NOMARK
		)
		t.expect((weak.idea :: provenance.Entry).actor).toBe("human:Zed (from git, first add)")
		-- derived entries in one minute order by the commit's time, not by kind
		local m0 = 1790000000 - 20 + 86400 * 40 -- a minute boundary
		local function at(secs: number, c: trail.Commit): trail.Commit
			c.time = m0 + secs
			return c
		end
		local s1 = at(5, commit(40, "Dee", "tracker: c0010 preparing", {}, "M", DOC, "preparing", ""))
		local s2 = at(20, commit(40, "Eli", "tracker: c0010 new", {}, "M", DOC, "new", ""))
		local s3 = at(40, commit(40, "Fay", "tracker: c0010 preparing", {}, "M", DOC, "preparing", ""))
		local first = at(0, commit(40, "Ann", "tracker: new c0010 alpha", {}, "A", DOC, "new", ""))
		first.time = m0 - 60
		local sameMinute = provenance.select({ s3, s2, s1, first }, people, fronts, NOMARK)
		local order: { string } = {}
		for _, e in provenance.merge(sameMinute, {}, nil) do
			table.insert(order, e.event)
		end
		t.expect(order).toEqual({ "idea", "status:preparing", "unblocked", "status:preparing" })
		-- merge: a stored row wins over a derived fallback of its event; oldest first by date, a derived entry before a
		-- stored one in the same minute. The stored dates fall inside the derived range (09-22 14:13 .. 09-30 14:13).
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
			"status:prepared:git",
			"rafted:record", -- the stored row; Fay's derived rafting is not repeated
			"status:active:git",
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
		local log = "@@abc123 1790000000 tracker: c0010 new\n@ADee\n@Edee@example.invalid\n@Pdef456 0a1b2c\n@TClaude Opus 5.5 <noreply@anthropic.com>\31M\tpath <x>\n"
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
		t.expect(commits[1].parents).toEqual({ "def456", "0a1b2c" })
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
			"`status:<word>`",
			"worker=",
			"(that commit's agent trailer, or its second parent's for a `--no-ff` landing; `unknown` with none",
			"every change of the document's `status:` word"
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
