--!strict
-- c0263 AC1, AC2, AC3, AC4 (pure parts), AC6, AC10: ticket provenance, the pure rules. The actor grammar and its
-- resolution, the trailer and commit actors, the record (rows, append-only, the closed event list), the approval check
-- against the design hash, the per-item selector over the git log and the merge `who` prints, and the documentation.
-- Everything here is text in, text out.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local trail = require("@znile/engine/trail")
local t = require("@tests/lib/t")

local OPUS = "agent:claude-opus-5-5 effort high"

return t.spec("c0263 ticket provenance", function(it)
	it("grammar and resolution", function()
		for _, ok in {
			"human:Philip Bergen",
			OPUS,
			"agent:grok-4-7 effort xhigh",
			"agent:claude-sonnet-5-thinking-high effort unknown",
			"agent:unknown effort high",
			"agent:claude-opus-5-5 effort unknown (from git)",
			"human:Phil (from git)",
			"unknown",
			"unknown (from git)",
			"human:Ann (from git, first add)",
		} do
			t.expect(provenance.isValid(ok)).toBe(true)
		end
		for _, bad in {
			"",
			"human:",
			"agent:claude-opus-5-5",
			"agent:claude opus effort high",
			"agent:grok-4.7 effort medium", -- the stored id has no dots (modelId)
			"robot:x",
			"unknown (from git) extra",
			"Philip",
			"none", -- the superseded design's value: nothing records it
			"human:A\nidea_by: human:B",
		} do
			t.expect(provenance.isValid(bad)).toBe(false)
		end
		-- one spelling per model, whichever side it comes from: every model of today's .models.toml
		t.expect(provenance.modelId("grok-4.7")).toBe("grok-4-7")
		t.expect(provenance.modelId("Grok 4.7")).toBe("grok-4-7")
		t.expect(provenance.modelId("Claude Opus 5.5")).toBe("claude-opus-5-5")
		t.expect(provenance.modelId("claude-opus-5-5")).toBe("claude-opus-5-5")
		t.expect(provenance.modelId("claude-opus-5-5-high")).toBe("claude-opus-5-5-high")
		t.expect(provenance.modelId("claude-sonnet-5-thinking-high")).toBe("claude-sonnet-5-thinking-high")
		t.expect(provenance.modelId("claude-sonnet-5")).toBe("claude-sonnet-5")
		local producers: { { model: string, effort: string? } } = {
			{ model = "grok-4.7", effort = "medium" },
			{ model = "grok-4.7", effort = "xhigh" },
			{ model = "claude-opus-5-5", effort = "high" },
			{ model = "claude-opus-5-5-high" },
			{ model = "claude-sonnet-5-thinking-high" },
		}
		for _, p in producers do
			local value = provenance.agent(p.model, p.effort)
			t.expect(provenance.isValid(value)).toBe(true)
			t.expect(provenance.isLive(value)).toBe(true)
		end
		t.expect(provenance.agent("grok-4.7", "medium")).toBe("agent:grok-4-7 effort medium")
		t.expect(provenance.agent("claude-opus-5-5", "high")).toBe(OPUS)
		t.expect(provenance.agent("claude-sonnet-5", nil)).toBe("agent:claude-sonnet-5 effort unknown")
		t.expect(provenance.human("Ann")).toBe("human:Ann")
		-- a live input is the recorded forms only: no suffix, no none, no unknown
		t.expect(provenance.isLive("human:A")).toBe(true)
		t.expect(provenance.isLive(OPUS)).toBe(true)
		for _, notLive in { "none", "unknown", "human:A (from git)", OPUS .. " (from git)" } do
			t.expect(provenance.isLive(notLive)).toBe(false)
		end
		-- flag, then env, then the session hint, then the git name
		local none = { agent = false, effort = nil }
		local session = { agent = true, effort = "high" }
		t.expect((provenance.resolve("human:Flag", "human:Env", session, "Git"))).toBe("human:Flag")
		t.expect((provenance.resolve(nil, "human:Env", session, "Git"))).toBe("human:Env")
		t.expect((provenance.resolve(nil, nil, session, "Git"))).toBe("agent:unknown effort high")
		t.expect((provenance.resolve(nil, nil, { agent = true, effort = nil }, "Git"))).toBe("agent:unknown effort unknown")
		t.expect((provenance.resolve(nil, nil, none, "Git"))).toBe("human:Git")
		t.expect((provenance.resolve("", "", none, "Git"))).toBe("human:Git")
		-- git has no identity: unknown, not a refusal
		t.expect((provenance.resolve(nil, nil, none, nil))).toBe("unknown")
		-- a given value outside the live grammar refuses, and never falls back
		for _, bad in { "nonsense", "none", "unknown", "human:A (from git)" } do
			local a, why = provenance.resolve(bad, "human:Env", none, "Git")
			t.expect(a).toBe(nil)
			t.expect(why ~= nil).toBe(true)
			local b, why2 = provenance.resolve(nil, bad, none, "Git")
			t.expect(b).toBe(nil)
			t.expect(why2 ~= nil).toBe(true)
		end
	end)

	it("trailers and commits", function()
		t.expect(provenance.fromTrailer("Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"))
			.toBe("agent:claude-opus-5-5 effort unknown (from git)")
		t.expect(provenance.fromTrailer("Co-authored-by: Grok 4.7 <noreply@x.ai>"))
			.toBe("agent:grok-4-7 effort unknown (from git)")
		t.expect(provenance.fromTrailer("Signed-off-by: Phil <p@x>")).toBe(nil)
		-- every commit author's email in the log: a trailer with one of these is a person
		local people = { ["p@x"] = true, ["philip.bergen@me.com"] = true }
		local sonnet = "Claude Sonnet 5.5 <noreply@anthropic.com>"
		t.expect(provenance.fromCommit("Phil", { sonnet }, people)).toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		t.expect(provenance.fromCommit("Phil", {}, people)).toBe("human:Phil (from git)")
		-- a trailer whose email is a commit author's elsewhere is a person, whatever name the commit's author has
		t.expect(provenance.fromCommit("Phil", { "Philip Bergen <philip.bergen@me.com>" }, people)).toBe("human:Phil (from git)")
		-- a person's trailer beside an agent's: the agent
		t.expect(provenance.fromCommit("Phil", { "Philip Bergen <p@x>", "Claude Opus 5.5 <noreply@anthropic.com>" }, people))
			.toBe("agent:claude-opus-5-5 effort unknown (from git)")
		-- the last agent trailer wins
		t.expect(provenance.fromCommit("Phil", { "Claude Opus 5.5 <a@anthropic.com>", sonnet }, people))
			.toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
	end)

	it("the record", function()
		local now = "2026-11-08 10:00"
		local one = provenance.record(nil, "c0010", "approved", "human:Ann", "design=1a2b3c4d5e6f; said=\"yes\"", now)
		t.expect(one ~= nil).toBe(true)
		local rows, why = provenance.parse(one :: string)
		t.expect(why).toBe(nil)
		t.expect(#(rows :: { any })).toBe(1)
		t.expect((rows :: { any })[1].event).toBe("approved")
		t.expect((rows :: { any })[1].actor).toBe("human:Ann")
		-- render is the form record writes: parse then render is the identity, and rows carry no number
		t.expect(provenance.render("c0010", rows :: { any })).toBe(one)
		t.expect((string.find(one :: string, "| 1 |", 1, true))).toBe(nil)
		local two = provenance.record(one, "c0010", "unblocked", OPUS, "block=design-gap", "2026-11-08 11:00") :: string
		t.expect(#(provenance.parse(two) :: { any })).toBe(2)
		-- a separator or a newline in a detail cannot split a row
		local messy = provenance.record(two, "c0010", "confirmed", "human:Ann", "said=\"a | b\nc\"", now) :: string
		t.expect(#(provenance.parse(messy) :: { any })).toBe(3)
		t.expect(string.find(messy, "a / b c", 1, true) ~= nil).toBe(true)
		-- the closed event list and the stored grammar
		t.expect((provenance.record(two, "c0010", "invented", "human:Ann", "", now))).toBe(nil)
		t.expect((provenance.record(two, "c0010", "unblocked", "somebody", "", now))).toBe(nil)
		t.expect((provenance.record(two, "c0010", "unblocked", "human:Ann (from git)", "", now))).toBe(nil)
		-- the parser refuses what it would otherwise misread
		local unknownEvent = (string.gsub(two, "| unblocked |", "| made-up |", 1))
		t.expect((provenance.parse(unknownEvent))).toBe(nil)
		t.expect((provenance.parse("not a record"))).toBe(nil)
		-- a malformed row under a valid header is refused, never skipped
		local head = (string.match(two, "^(.-\n|%-%-%-%S*\n)")) :: string
		for _, bad in {
			"| 2026-11-08 10:00 | approved | human:Ann |\n", -- three cells
			"| yesterday | approved | human:Ann | design=aaaaaaaaaaaa |\n", -- a bad when
			"| 2026-11-08 10:00 | approved | human:Ann | design=aaaaaaaaaaaa\n", -- no closing bar
			"| 2026-11-08 10:00 | approved | none | |\n", -- an actor nothing records
		} do
			t.expect((provenance.parse(head .. bad))).toBe(nil)
			t.expect(#provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", head .. bad)).toBe(1)
		end
		-- append-only: the old rows unchanged and in place, at least one more; nothing edited, removed or reordered
		t.expect(provenance.appendOnly(one, two, "c0010")).toBe(nil)
		t.expect(provenance.appendOnly(nil, one :: string, "c0010")).toBe(nil)
		t.expect(provenance.appendOnly(two, one :: string, "c0010") ~= nil).toBe(true) -- a row removed
		t.expect(provenance.appendOnly(two, two, "c0010") ~= nil).toBe(true) -- nothing appended
		t.expect(provenance.appendOnly(one, (string.gsub(two, "human:Ann", "human:Eve", 1)), "c0010") ~= nil).toBe(true)
		t.expect(provenance.appendOnly(one, two, "c0011") ~= nil).toBe(true) -- another item's record
		t.expect(provenance.appendOnly(nil, "garbage", "c0010") ~= nil).toBe(true) -- a create that does not parse
		-- union: two sides that each appended to the same base keep both rows, base first, no row twice
		local ours = provenance.record(one, "c0010", "rafted", OPUS, "raft=R0010", "2026-11-08 10:30") :: string
		local theirs = provenance.record(one, "c0010", "unblocked", "human:Bee", "", "2026-11-08 10:35") :: string
		local united = provenance.union(one :: string, ours, theirs)
		local urows = provenance.parse(united) :: { any }
		t.expect(#urows).toBe(3)
		t.expect(urows[1].event).toBe("approved")
		-- base first, then the target branch's (origin/main's) new rows, then ours: main's record stays a prefix, so the
		-- rafting gate's append-only rule still accepts the PR after a sync
		t.expect(urows[2].event).toBe("unblocked")
		t.expect(urows[3].event).toBe("rafted")
		t.expect(provenance.appendOnly(theirs, united, "c0010")).toBe(nil)
		t.expect(provenance.union(one :: string, ours, ours)).toBe(ours) -- the same append on both sides is one row
		t.expect(provenance.union(nil :: any, ours, theirs) ~= nil).toBe(true) -- both sides created it
		-- a record is not a document: trail must not count it as the item's life
		t.expect(trail.isDoc("provenance.md")).toBe(false)
		t.expect(trail.isDoc("c0010.md")).toBe(true)
	end)

	it("the approval check", function()
		local function rows(text: string?): { any }
			return (provenance.parse(text :: string) or {}) :: { any }
		end
		local none = provenance.record(nil, "c0010", "unblocked", OPUS, "", "2026-11-08 09:00") :: string
		t.expect((provenance.approval(rows(none), "aaaaaaaaaaaa"))).toBe("none")
		local one = provenance.record(none, "c0010", "approved", "human:Ann", "design=aaaaaaaaaaaa; said=\"ok\"", "2026-11-08 10:00") :: string
		t.expect((provenance.approval(rows(one), "aaaaaaaaaaaa"))).toBe("current")
		-- a redesign changes the hash: stale, and it says what the approval covered
		local state, old = provenance.approval(rows(one), "bbbbbbbbbbbb")
		t.expect(state).toBe("stale")
		t.expect(old).toBe("aaaaaaaaaaaa")
		-- the newest approval decides, not the first and not a match anywhere in the history
		local two = provenance.record(one, "c0010", "approved", "human:Ann", "design=bbbbbbbbbbbb", "2026-11-08 11:00") :: string
		t.expect((provenance.approval(rows(two), "bbbbbbbbbbbb"))).toBe("current")
		t.expect((provenance.approval(rows(two), "aaaaaaaaaaaa"))).toBe("stale")
		-- a row without a design hash approves nothing
		local bare = provenance.record(nil, "c0010", "approved", "human:Ann", "said=\"ok\"", "2026-11-08 10:00") :: string
		t.expect((provenance.approval(rows(bare), "aaaaaaaaaaaa"))).toBe("stale")
	end)

	it("derive and merge", function()
		local DOC = "z-nile/.tracker/issues/c0010/c0010.md"
		local DONE = "z-nile/.tracker/issues/done/c0010/c0010.md"
		local sonnet = { "Claude Sonnet 5.5 <noreply@anthropic.com>" }
		local opus = { "Claude Opus 5.5 <noreply@anthropic.com>" }
		local n = 0
		local raftAt: { [string]: string } = {}
		-- 1790000000 is 2026-09-21 14:13:20 UTC; `day` counts from there; `raft` is the document's raft: after the commit
		local function commit(day: number, author: string, subject: string, trailers: { string }, status: string, path: string, raft: string?): trail.Commit
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
		t.expect((d.delivered :: provenance.Entry).actor).toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
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
		t.expect(#provenance.select({ give, rec, life[10] }, "c0010", "backlog", "", people, raftAt).unblocked).toBe(0)
		t.expect(#provenance.select({ give, life[10] }, "c0010", "backlog", "", people, raftAt).unblocked).toBe(1)
		-- an idea taken from a first add (no commit names the item) says so
		local weak = provenance.select({ commit(1, "Zed", "tracker: rename things", {}, "A", DOC) }, "c0010", "backlog", "", people, {})
		t.expect((weak.idea :: provenance.Entry).actor).toBe("human:Zed (from git, first add)")
		t.expect((d.idea :: provenance.Entry).actor).toBe("human:Ann (from git)")
		-- merge: a stored row wins over a derived fallback of its event; oldest first by date, a derived entry before a
		-- stored one in the same minute. The stored dates fall inside the derived range (09-22 14:13 .. 09-28 14:13).
		local text = provenance.record(nil, "c0010", "confirmed", "human:Ann", "said=\"yes\"", "2026-09-22 14:13") :: string
		text = provenance.record(text, "c0010", "approved", "human:Ann", "design=aaaaaaaaaaaa", "2026-09-24 20:00") :: string
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
		t.expect(provenance.workerOf({ model = "claude-opus-5-5-high", host = "h1", cli = "claude" })).toBe("h1/claude/claude-opus-5-5-high")
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

	it("audit", function()
		local good = provenance.record(nil, "c0010", "approved", "human:Ann", "design=aaaaaaaaaaaa", "2026-11-08 10:00") :: string
		t.expect(provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", good)).toEqual({})
		t.expect(#provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", "garbage")).toBe(1)
		-- a raft may have one (c0250 blocks whole rafts); a header that names another id may not
		local raft = provenance.record(nil, "R0010", "unblocked", "human:Ann", "block=needs-decision", "2026-11-08 10:00") :: string
		t.expect(provenance.problems("z-nile/.tracker/rafts/R0010/provenance.md", raft)).toEqual({})
		t.expect(#provenance.problems("z-nile/.tracker/issues/c0011/provenance.md", good)).toBe(1)
	end)

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
			"provenance.md",
			"./zn approve",
			"./zn who",
			"./zn record",
			"ZN_ACTOR",
			"--actor",
			"CLAUDECODE"
		)
		has("z-nile/skills/z-design/SKILL.md", "./zn approve", "then run `./zn status <id> prepared`")
		has("z-nile/skills/z-raft/SKILL.md", "--actor")
		has("z-nile/skills/zz-execute/SKILL.md", "--actor")
		has("z-nile/README.md", "provenance")
	end)
end)
