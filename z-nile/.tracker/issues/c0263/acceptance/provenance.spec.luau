--!strict
-- c0263 AC1, AC2, AC3, AC4 (pure parts), AC6, AC10: ticket provenance, the pure rules. The actor grammar and its
-- resolution, the trailer and commit actors, the record (rows, append-only, the closed event list), the approval check
-- against the design hash, the per-item selector over the git log and the merge `who` prints, and the documentation.
-- Everything here is text in, text out.
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
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
			"none",
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
		local people = { ["p@x"] = true, ["philip.bergen@me.com"] = true } -- every commit author's email in the log
		local body = "Models.\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\n"
		t.expect(provenance.fromCommit("Phil", body, people)).toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		t.expect(provenance.fromCommit("Phil", "no trailer\n", people)).toBe("human:Phil (from git)")
		-- a trailer whose email is a commit author's elsewhere is a person, whatever name the commit's author has
		t.expect(provenance.fromCommit("Phil", "x\n\nCo-authored-by: Philip Bergen <philip.bergen@me.com>\n", people))
			.toBe("human:Phil (from git)")
		-- a person's trailer beside an agent's: the agent
		t.expect(
			provenance.fromCommit(
				"Phil",
				"x\n\nCo-authored-by: Philip Bergen <p@x>\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n",
				people
			)
		).toBe("agent:claude-opus-5-5 effort unknown (from git)")
		-- the last agent trailer wins
		t.expect(
			provenance.fromCommit(
				"Phil",
				"x\n\nCo-Authored-By: Claude Opus 5.5 <a@anthropic.com>\nCo-Authored-By: Claude Sonnet 5.5 <b@anthropic.com>\n",
				people
			)
		).toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
	end)

	it("the record", function()
		local now = "2026-11-08 10:00"
		local one = provenance.record(nil, "c0010", "approved", "human:Ann", "design=1a2b3c4d5e6f; said=\"yes\"", now)
		t.expect(one ~= nil).toBe(true)
		local rows, why = provenance.parse(one :: string)
		t.expect(why).toBe(nil)
		t.expect(#(rows :: { any })).toBe(1)
		t.expect((rows :: { any })[1].n).toBe(1)
		t.expect((rows :: { any })[1].event).toBe("approved")
		t.expect((rows :: { any })[1].actor).toBe("human:Ann")
		-- render is the form record writes: parse then render is the identity
		t.expect(provenance.render("c0010", rows :: { any })).toBe(one)
		local two = provenance.record(one, "c0010", "unblocked", OPUS, "block=design-gap", "2026-11-08 11:00") :: string
		local both = provenance.parse(two) :: { any }
		t.expect(#both).toBe(2)
		t.expect(both[2].n).toBe(2)
		-- a separator or a newline in a detail cannot split a row
		local messy = provenance.record(two, "c0010", "confirmed", "human:Ann", "said=\"a | b\nc\"", now) :: string
		t.expect(#(provenance.parse(messy) :: { any })).toBe(3)
		t.expect(string.find(messy, "a / b c", 1, true) ~= nil).toBe(true)
		-- the closed event list and the stored grammar
		t.expect((provenance.record(two, "c0010", "invented", "human:Ann", "", now))).toBe(nil)
		t.expect((provenance.record(two, "c0010", "unblocked", "somebody", "", now))).toBe(nil)
		t.expect((provenance.record(two, "c0010", "unblocked", "human:Ann (from git)", "", now))).toBe(nil)
		-- the parser refuses what it would otherwise take as the last one
		local twice = (string.gsub(two, "| 2 |", "| 1 |", 1))
		t.expect((provenance.parse(twice))).toBe(nil)
		local unknownEvent = (string.gsub(two, "| unblocked |", "| made-up |", 1))
		t.expect((provenance.parse(unknownEvent))).toBe(nil)
		t.expect((provenance.parse("not a record"))).toBe(nil)
		-- append-only: the same rows plus at least one more; nothing edited, removed or renumbered
		t.expect(provenance.appendOnly(one, two, "c0010")).toBe(nil)
		t.expect(provenance.appendOnly(nil, one, "c0010")).toBe(nil)
		t.expect(provenance.appendOnly(two, one, "c0010") ~= nil).toBe(true) -- a row removed
		t.expect(provenance.appendOnly(two, two, "c0010") ~= nil).toBe(true) -- nothing appended
		t.expect(provenance.appendOnly(one, (string.gsub(two, "human:Ann", "human:Eve", 1)), "c0010") ~= nil).toBe(true)
		t.expect(provenance.appendOnly(one, two, "c0011") ~= nil).toBe(true) -- another item's record
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
		local trailer = "x\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>\n"
		local function commit(when: string, author: string, subject: string, body: string, added: { [string]: { string } }?, adds: { [string]: boolean }?)
			return {
				sha = subject,
				when = when,
				author = author,
				email = `{author}@example.invalid`,
				subject = subject,
				body = body,
				added = added or {},
				adds = adds or {},
			}
		end
		local log = {
			commit("2026-10-01 09:00", "Ann", "tracker: new c0010 alpha", "", { [DOC] = { "raft: " } }, { [DOC] = true }),
			commit("2026-10-02 09:00", "Dee", "tracker: c0010 preparing", "", { [DOC] = { "status: preparing-a-b-c" } }),
			commit("2026-10-03 09:00", "Dee", "tracker: c0010 new", "", { [DOC] = { "status: new-a-b-c" } }),
			commit("2026-10-04 09:00", "Bob", "tracker: raft R0010 demo", "x\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n", { [DOC] = { "raft: R0010" } }),
			commit("2026-10-05 09:00", "Gus", "tracker: unfold c0010", "", { [DOC] = { "raft: " } }),
			commit("2026-10-06 09:00", "Fay", "tracker: raft R0011 again", "", { [DOC] = { "raft: R0011" } }),
			-- the move to done/ re-adds the same raft: line (no renames): not a rafter
			commit("2026-10-07 09:00", "Cy", "R0011: demo (#1)", trailer, { [DONE] = { "raft: R0011", "status: done" } }, { [DONE] = true }),
		}
		local people: { [string]: boolean } = {}
		for _, c in log do
			people[c.email] = true
		end
		local d = provenance.select(log, "c0010", "done", "R0011", people)
		t.expect(d.idea.actor).toBe("human:Ann (from git)")
		-- a status commit is an entry of its own, with its author; the capture is not one
		t.expect(#d.statuses).toBe(3)
		t.expect(d.statuses[1].event).toBe("status:preparing")
		t.expect(d.statuses[1].actor).toBe("human:Dee (from git)")
		t.expect(d.statuses[3].event).toBe("status:new")
		-- the newest commit that set raft: to its current value, not the first and not the move to done/
		t.expect(d.rafted.actor).toBe("human:Fay (from git)")
		t.expect(d.rafted.detail).toBe("raft=R0011")
		t.expect(d.delivered.actor).toBe("agent:claude-sonnet-5-5 effort unknown (from git)")
		-- an unfolded item (raft: empty) has no rafter, and a backlog item no delivery
		local open = provenance.select(log, "c0010", "backlog", "", people)
		t.expect(open.rafted).toBe(nil)
		t.expect(open.delivered).toBe(nil)
		-- another item's commits are not this item's
		t.expect(provenance.select(log, "c0099", "backlog", "", people).idea).toBe(nil)
		-- merge: stored rows win over a derived fallback of the same event; rows and entries come out oldest first
		local rows = provenance.parse(
			provenance.record(
				provenance.record(nil, "c0010", "rafted", OPUS, "raft=R0011", "2026-10-06 09:30") :: string,
				"c0010",
				"approved",
				"human:Ann",
				"design=aaaaaaaaaaaa",
				"2026-10-05 12:00"
			) :: string
		) :: { any }
		local merged = provenance.merge(d, rows)
		local events: { string } = {}
		for _, e in merged do
			table.insert(events, `{e.event}:{e.source}`)
		end
		t.expect(events).toEqual({
			"idea:git",
			"status:preparing:git",
			"status:new:git",
			"approved:record",
			"rafted:record",
			"delivered:git",
		})
		-- a rafted row exists, so the derived rafter is not repeated; the record's actor is the live one
		for _, e in merged do
			if e.event == "rafted" then
				t.expect(e.actor).toBe(OPUS)
			end
		end
		-- the log text parses into those commits (one pass)
		local text = "@@C abc\031Ann\031ann@example.invalid\0312026-10-01 09:00\031tracker: c0010 new\031body line\n"
			.. "diff --git a/" .. DOC .. " b/" .. DOC .. "\nnew file mode 100644\n+++ b/" .. DOC .. "\n+raft: R0010\n"
		local parsed = provenance.parseLog(text)
		t.expect(#parsed).toBe(1)
		t.expect(parsed[1].author).toBe("Ann")
		t.expect(parsed[1].email).toBe("ann@example.invalid")
		t.expect(parsed[1].subject).toBe("tracker: c0010 new")
		t.expect(parsed[1].adds[DOC]).toBe(true)
		t.expect(parsed[1].added[DOC]).toEqual({ "raft: R0010" })
	end)

	it("audit", function()
		local good = provenance.record(nil, "c0010", "approved", "human:Ann", "design=aaaaaaaaaaaa", "2026-11-08 10:00") :: string
		t.expect(provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", good)).toEqual({})
		t.expect(#provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", "garbage")).toBe(1)
		t.expect(#provenance.problems("z-nile/.tracker/rafts/R0010/provenance.md", good)).toBe(1) -- a raft has none
		t.expect(#provenance.problems("z-nile/.tracker/issues/c0011/provenance.md", good)).toBe(1) -- names another id
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
