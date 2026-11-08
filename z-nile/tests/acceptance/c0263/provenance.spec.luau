--!strict
-- c0263 AC1, AC4, AC5: the record's pure rules. The actor grammar and its resolution, the record (rows, append-only,
-- the closed event list, the publish rule's event check, the union of two writers), audit's check and the
-- documentation. Everything here is text in, text out. (The derivations from git are c0280's, the approval check is
-- c0283's.)
local fs = require("@lune/fs")
local process = require("@lune/process")
local provenance = require("@znile/engine/provenance")
local t = require("@tests/lib/t")
local trail = require("@znile/engine/trail")

local OPUS = "agent:claude-opus-5-5 effort high"

return t.spec("c0263 the provenance record", function(it)
	it("grammar and resolution", function()
		for _, ok in
			{
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
			}
		do
			t.expect(provenance.isValid(ok)).toBe(true)
		end
		for _, bad in
			{
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
			}
		do
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
		t.expect((provenance.resolve(nil, nil, { agent = true, effort = nil }, "Git")))
			.toBe("agent:unknown effort unknown")
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

	it("the record", function()
		local now = "2026-11-08 10:00"
		local one =
			provenance.record(nil, "c0010", "approved", "human:Ann", 'design=1a2b3c4d5e6f; said="yes"', now)
		t.expect(one ~= nil).toBe(true)
		local rows, why = provenance.parse(one :: string)
		t.expect(why).toBe(nil)
		t.expect(#(rows :: { any })).toBe(1)
		t.expect((rows :: { any })[1].event).toBe("approved")
		t.expect((rows :: { any })[1].actor).toBe("human:Ann")
		-- render is the form record writes: parse then render is the identity, and rows carry no number
		t.expect(provenance.render("c0010", rows :: { any })).toBe(one)
		t.expect((string.find(one :: string, "| 1 |", 1, true))).toBe(nil)
		local two =
			provenance.record(one, "c0010", "unblocked", OPUS, "block=design-gap", "2026-11-08 11:00") :: string
		t.expect(#(provenance.parse(two) :: { any })).toBe(2)
		-- a separator or a newline in a detail cannot split a row
		local messy =
			provenance.record(two, "c0010", "confirmed", "human:Ann", 'said="a | b\nc"', now) :: string
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
		for _, bad in
			{
				"| 2026-11-08 10:00 | approved | human:Ann |\n", -- three cells
				"| yesterday | approved | human:Ann | design=aaaaaaaaaaaa |\n", -- a bad when
				"| 2026-11-08 10:00 | approved | human:Ann | design=aaaaaaaaaaaa\n", -- no closing bar
				"| 2026-11-08 10:00 | approved | none | |\n", -- an actor nothing records
			}
		do
			t.expect((provenance.parse(head .. bad))).toBe(nil)
			t.expect(#provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", head .. bad)).toBe(1)
		end
		-- append-only: the old rows unchanged and in place, at least one more; nothing edited, removed or reordered
		t.expect(provenance.appendOnly(one, two, "c0010")).toBe(nil)
		t.expect(provenance.appendOnly(nil, one :: string, "c0010")).toBe(nil)
		t.expect(provenance.appendOnly(two, one :: string, "c0010") ~= nil).toBe(true) -- a row removed
		t.expect(provenance.appendOnly(two, two, "c0010") ~= nil).toBe(true) -- nothing appended
		-- every cell of an old row is pinned: the actor, the detail (a stale approval made current) and the when
		t.expect(provenance.appendOnly(one, (string.gsub(two, "human:Ann", "human:Eve", 1)), "c0010") ~= nil)
			.toBe(true)
		t.expect(
			provenance.appendOnly(
				one,
				(string.gsub(two, "design=1a2b3c4d5e6f", "design=ffffffffffff", 1)),
				"c0010"
			) ~= nil
		).toBe(true)
		t.expect(
			provenance.appendOnly(
				one,
				(string.gsub(two, "2026%-11%-08 10:00", "2026-11-08 10:01", 1)),
				"c0010"
			) ~= nil
		).toBe(true)
		t.expect(provenance.appendOnly(one, two, "c0011") ~= nil).toBe(true) -- another item's record
		t.expect(provenance.appendOnly(nil, "garbage", "c0010") ~= nil).toBe(true) -- a create that does not parse
		-- the publish rule: append-only, and every new row's event is one `./zn record` may publish (the allowed list)
		t.expect(provenance.publishProblem(one, two, "c0010", provenance.PUBLISHED)).toBe(nil)
		t.expect(provenance.publishProblem(nil, one :: string, "c0010", provenance.PUBLISHED) ~= nil)
			.toBe(true) -- approved
		t.expect(provenance.publishProblem(one, two, "c0010", { "confirmed" }) ~= nil).toBe(true) -- not in this list
		t.expect(provenance.publishProblem(two, one :: string, "c0010", provenance.PUBLISHED) ~= nil)
			.toBe(true)

		-- union: two sides that each appended to the same base keep both rows, base first, no row twice
		local ours =
			provenance.record(one, "c0010", "rafted", OPUS, "raft=R0010", "2026-11-08 10:30") :: string
		local theirs =
			provenance.record(one, "c0010", "unblocked", "human:Bee", "", "2026-11-08 10:35") :: string
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
		-- repeated rows: a base that holds the same row twice keeps both, and main stays a prefix of the result
		local twice = provenance.record(
			one,
			"c0010",
			"approved",
			"human:Ann",
			'design=1a2b3c4d5e6f; said="yes"',
			"2026-11-08 10:00"
		) :: string
		local oursR =
			provenance.record(twice, "c0010", "rafted", OPUS, "raft=R0010", "2026-11-08 10:30") :: string
		local theirsR =
			provenance.record(twice, "c0010", "ranked", "human:Bee", "rank=3", "2026-11-08 10:35") :: string
		local unitedR = provenance.union(twice, oursR, theirsR)
		t.expect(#(provenance.parse(unitedR) :: { any })).toBe(4)
		t.expect(provenance.appendOnly(theirsR, unitedR, "c0010")).toBe(nil)
		-- the same row appended on both sides is once, with ours' extra row after it
		local sameRow =
			provenance.record(one, "c0010", "ranked", "human:Bee", "rank=3", "2026-11-08 10:35") :: string
		local oursPlus =
			provenance.record(sameRow, "c0010", "rafted", OPUS, "raft=R0010", "2026-11-08 10:40") :: string
		local unitedS = provenance.parse(provenance.union(one :: string, oursPlus, sameRow)) :: { any }
		t.expect(#unitedS).toBe(3)
		t.expect(unitedS[2].event).toBe("ranked")
		t.expect(unitedS[3].event).toBe("rafted")
		t.expect(provenance.union(nil :: any, ours, theirs) ~= nil).toBe(true) -- both sides created it
		-- a record is not a document: trail must not count it as the item's life
		t.expect(trail.isDoc("provenance.md")).toBe(false)
		t.expect(trail.isDoc("c0010.md")).toBe(true)
	end)

	it("audit", function()
		local good = provenance.record(
			nil,
			"c0010",
			"approved",
			"human:Ann",
			"design=aaaaaaaaaaaa",
			"2026-11-08 10:00"
		) :: string
		t.expect(provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", good)).toEqual({})
		t.expect(#provenance.problems("z-nile/.tracker/issues/c0010/provenance.md", "garbage")).toBe(1)
		-- a raft may have one (c0250 blocks whole rafts); a header that names another id may not
		local raft = provenance.record(
			nil,
			"R0010",
			"unblocked",
			"human:Ann",
			"block=needs-decision",
			"2026-11-08 10:00"
		) :: string
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
			"./zn record",
			"ZN_ACTOR",
			"--actor",
			"CLAUDECODE",
			"./zn sync"
		)
		has("z-nile/README.md", "provenance")
	end)
end)
