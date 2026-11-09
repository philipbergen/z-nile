--!strict
-- EXCERPT of c0263 provenance.spec for c0280 (who): trailers and commits, derive and merge, trail log. Needs the c0280 pure module (fromTrailer, fromCommit, select, merge, workerOf) and trail.Commit author/email/trailers.
-- resolution, the trailer and commit actors, the record (rows, append-only, the closed event list), the approval check
-- against the design hash, the per-item selector over the git log and the merge `who` prints, and the documentation.
-- Everything here is text in, text out.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local OPUS = "agent:claude-opus-5-5 effort high"

return t.spec("c0263 ticket provenance", function(it)
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
		local life = {
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
		-- the delivery is the commit that first added the document under done/, and it is also the merge
		t.expect((d.delivered :: provenance.Entry).actor)
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		-- who merged is the commit's author, trailers ignored (a squash is authored by the user with the agent as co-author)
		t.expect((d.merged :: provenance.Entry).actor).toBe("human:Cy (from git)")
		-- an unfolded item (raft: empty) has no rafter, and a backlog item no delivery or merge
		local open = provenance.select({ life[8], life[9], life[10] }, "c0010", "backlog", "", people, raftAt)
		t.expect(open.rafted).toBe(nil)
		t.expect(open.delivered).toBe(nil)
		t.expect(open.merged).toBe(nil)
		-- a `new` commit that also changed the item's record is covered by its stored row; any other prints as derived
		local give = commit(8, "Eli", "tracker: c0010 new", {}, "M", DOC)
		local rec = table.clone(give)
		rec.path = "z-nile/.tracker/issues/c0010/provenance.md"
		rec.order += 1
		t.expect(
			#provenance.select({ give, rec, life[10] }, "c0010", "backlog", "", people, raftAt).unblocked
		)
			.toBe(0)
		t.expect(#provenance.select({ give, life[10] }, "c0010", "backlog", "", people, raftAt).unblocked)
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

end)
