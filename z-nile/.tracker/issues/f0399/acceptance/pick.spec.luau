--!strict
-- f0399: what `./zn work next` picks with no raft named, the two tiers, `wait`, and a named issue. Pure.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local ADA = "Ada <ada@example>"

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function raft(over: { [string]: any }): work.RaftFact
	local r: work.RaftFact = {
		id = "R0010",
		title = "t",
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = { "c0010" },
		layers = {},
		holder = "",
		since = "",
		stacked = false,
		codeReview = "none",
		finalReview = "none",
		trace = false,
		traceOk = false,
		root = "z-nile/.tracker",
	}
	for k, v in over do
		(r :: any)[k] = v
	end
	return r
end

local function issue(id: string, over: { [string]: any }?): work.IssueFact
	local i: work.IssueFact = {
		id = id,
		root = "z-nile/.tracker",
		status = "new",
		raft = "",
		designReady = false,
		sized = false,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function prepared(id: string, over: { [string]: any }?): work.IssueFact
	local i = issue(id, { status = "prepared", designReady = true, sized = true })
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function layer(position: number, id: string, finished: boolean): work.LayerFact
	return {
		position = position,
		issue = id,
		name = `R/{position}/{id}`,
		commits = 1,
		onlyStart = false,
		finished = finished,
	}
end

-- an active raft whose every gate has passed: forRaft says done unless something waits
local function built(id: string, over: { [string]: any }?): work.RaftFact
	local r = raft({
		id = id,
		where = "active",
		status = "active",
		holder = ADA,
		issues = { "c0010" },
		layers = { layer(1, "c0010", true) },
		stacked = true,
		codeReview = "resolved",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		lands = true,
	})
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

local function decide(rafts: { work.RaftFact }, issues: { work.IssueFact }?, asked: string?): work.Decision
	return work.decide({ asked = asked, author = ADA, rafts = rafts, issues = issues })
end

return t.spec("f0399: z-work picks every ticket's next step", function(it)
	it("with nothing unmet it lands a held approved raft, then readies, then rafts, then drafts", function()
		local land = built("R0050")
		local ready = raft({ id = "R0040" })
		local toRaft = prepared("c0030")
		local toDraft = issue("c0020")
		local all = { toDraft, toRaft }
		local d1 = decide({ ready, land }, all)
		t.expect(d1.raft).toBe("R0050")
		t.expect(d1.action).toBe("done")
		local d2 = decide({ ready }, all)
		t.expect(d2.raft).toBe("R0040")
		t.expect(d2.action).toBe("ready")
		local d3 = decide({}, all)
		t.expect(d3.raft).toBe("")
		t.expect(d3.ticket).toBe("c0030")
		t.expect(d3.action).toBe("rafting")
		t.expect(has(d3.why, "./zn raft-plan --apply")).toBe(true)
		local d4 = decide({}, { toDraft })
		t.expect(d4.ticket).toBe("c0020")
		t.expect(d4.action).toBe("draft")
		t.expect(has(d4.why, "./zn status c0020 preparing")).toBe(true)
		t.expect(has(d4.why, "./zn guess")).toBe(true)
	end)

	it("the lowest id wins inside one kind of pick", function()
		t.expect(decide({}, { prepared("c0031"), prepared("c0030") }).ticket).toBe("c0030")
		t.expect(decide({}, { issue("f0022"), issue("c0021") }).ticket).toBe("c0021")
		t.expect(decide({ built("R0051"), built("R0050") }, {}).raft).toBe("R0050")
	end)

	it("a held raft is taken only when its next action is done, and only this author's", function()
		local building = built("R0050", { finalReview = "none", traceOk = false })
		local others = built("R0049", { holder = "Bo <bo@example>" })
		local d = decide({ building, others }, { issue("c0020") })
		t.expect(d.ticket).toBe("c0020")
		t.expect(d.action).toBe("draft")
	end)

	it(
		"it never picks a held design, an unchallenged idea, an unsized issue, a closed one, an added issue or a member",
		function()
			local none = decide({}, {
				issue("c0001", { status = "preparing" }),
				issue(
					"c0002",
					{ draftBlock = "no idea-review-001.md (the idea was not challenged): ./zn idea c0002" }
				),
				prepared("c0003", { sized = false }),
				issue("c0004", { status = "closed" }),
				prepared("c0005", { added = true }),
				prepared("c0006", { raft = "R0099" }),
			})
			t.expect(none.action).toBe("none")
			t.expect(none.ticket).toBe("")
			t.expect(has(none.why, "c0001: is being designed (preparing): name it to resume")).toBe(true)
			t.expect(has(none.why, "c0002: its idea needs the person (no idea-review-001.md")).toBe(true)
			t.expect(has(none.why, "c0003: has no size:")).toBe(true)
			t.expect(has(none.why, "c0004")).toBe(false)
			t.expect(has(none.why, "c0005")).toBe(false)
			t.expect(has(none.why, "c0006")).toBe(false)
			t.expect(has(work.say(none), "nothing to do - ")).toBe(true)
		end
	)

	it("a ticket with an unmet dependency is picked only when no ticket without one has a pick", function()
		-- c0030 is prepared but depends on c0020, which is new: the capture's own example
		local dep = issue("c0020")
		local dependent = prepared("c0030", { deps = { "c0020" } })
		local d = decide({}, { dependent, dep })
		t.expect(d.ticket).toBe("c0020")
		t.expect(d.action).toBe("draft")
		-- a designed, unlanded dependency: the prepared dependent could be rafted, but a captured ticket
		-- with no dependency comes first
		local designed = prepared("c0021", { status = "active", raft = "R0060" })
		local second = prepared("c0032", { deps = { "c0021" } })
		local first = issue("c0099")
		local tier = decide({}, { second, first, designed })
		t.expect(tier.ticket).toBe("c0099")
		t.expect(tier.action).toBe("draft")
		-- a dependency that is done is not in the list: nothing unmet
		local free = prepared("c0031", { deps = { "c0009" } })
		t.expect(decide({}, { free, dep }).ticket).toBe("c0031")
	end)

	it("tier 2 rafts or drafts a ticket only when every unmet dependency is designed", function()
		local held = issue("c0020", { status = "preparing" })
		local onHeld = prepared("c0030", { deps = { "c0020" } })
		local none = decide({}, { onHeld, held })
		t.expect(none.action).toBe("none")
		t.expect(has(none.why, "c0030: depends on c0020, which is not designed")).toBe(true)
		-- the dependency is prepared and in a raft that is being built: designed, not landed
		local designed = prepared("c0021", { status = "active", raft = "R0060" })
		local toRaft = prepared("c0032", { deps = { "c0021" } })
		local toDraft = issue("c0033", { deps = { "c0021" } })
		local d1 = decide({}, { toDraft, toRaft, designed })
		t.expect(d1.ticket).toBe("c0032")
		t.expect(d1.action).toBe("rafting")
		local d2 = decide({}, { toDraft, designed })
		t.expect(d2.ticket).toBe("c0033")
		t.expect(d2.action).toBe("draft")
		t.expect(has(d2.why, "It depends on c0021, not landed")).toBe(true)
	end)

	it(
		"tier 2 readies a raft on the one active raft that holds its dependencies, once every layer there is finished",
		function()
			local dep = prepared("c0021", { status = "active", raft = "R0060" })
			local member = prepared("f0041", { raft = "R0070", deps = { "c0021" } })
			local base = raft({
				id = "R0060",
				where = "active",
				status = "active",
				holder = "Bo <bo@example>",
				issues = { "c0021" },
				layers = { layer(1, "c0021", true) },
			})
			local onIt = raft({
				id = "R0070",
				issues = { "f0041" },
				depsMet = false,
				block = "f0041 depends on c0021, which is active on origin/main: it must be done first",
				blockOn = "",
				outside = { "c0021" },
			})
			local d = decide({ base, onIt }, { dep, member })
			t.expect(d.raft).toBe("R0070")
			t.expect(d.action).toBe("ready")
			t.expect(has(d.why, "./zn ready R0070 --on R0060")).toBe(true)
			-- a tier 1 pick comes first
			t.expect(decide({ base, onIt }, { dep, member, issue("c0099") }).ticket).toBe("c0099")
			-- an unfinished layer in the base: not yet
			local unfinished = table.clone(base)
			unfinished.layers = { layer(1, "c0021", false) }
			local wait = decide({ unfinished, onIt }, { dep, member })
			t.expect(wait.action).toBe("none")
			-- something else still refuses it (blockOn is ready's reason with the base taken as done)
			local refused = table.clone(onIt)
			refused.blockOn = "R0070: open to the human (F1)"
			t.expect(decide({ base, refused }, { dep, member }).action).toBe("none")
			-- dependencies in two unlanded rafts: a raft is built on one
			local dep2 = prepared("c0022", { status = "active", raft = "R0061" })
			local base2 = raft({
				id = "R0061",
				where = "active",
				status = "active",
				issues = { "c0022" },
				layers = { layer(1, "c0022", true) },
			})
			local two = table.clone(onIt)
			two.outside = { "c0021", "c0022" }
			t.expect(decide({ base, base2, two }, { dep, dep2, member }).action).toBe("none")
			local id, why = work.baseFor(two, { base, base2, two }, { dep, dep2, member })
			t.expect(id).toBe(nil)
			t.expect(has(why, "a raft is built on one raft")).toBe(true)
		end
	)

	it(
		"wait names each unapproved member once the gates have passed, and is not offered as a pick",
		function()
			local waiting = built("R0050", {
				issues = { "c0010", "f0011" },
				layers = { layer(1, "c0010", true), layer(2, "f0011", true) },
				unapproved = { "c0010 (changed: guesses)", "f0011 (no approval)" },
			})
			local d = decide({ waiting }, {}, "R0050")
			t.expect(d.action).toBe("wait")
			t.expect(has(d.why, "./zn approve c0010, f0011")).toBe(true)
			t.expect(has(d.why, "c0010 (changed: guesses)")).toBe(true)
			t.expect(has(d.why, "./zn guesses R0050")).toBe(true)
			t.expect(has(work.say(d), "R0050: wait - ")).toBe(true)
			-- unnamed: it is skipped with its reason and the next ticket is taken
			local next = decide({ waiting }, { issue("c0020") })
			t.expect(next.ticket).toBe("c0020")
			local none = decide({ waiting }, {})
			t.expect(none.action).toBe("none")
			t.expect(
				has(none.why, "R0050: waits for approval: c0010 (changed: guesses), f0011 (no approval)")
			)
				.toBe(true)
			-- before the final review is approved it is not a wait
			local early = table.clone(waiting)
			early.finalReview = "none"
			early.traceOk = false
			t.expect(decide({ early }, {}, "R0050").action).toBe("final-review")
		end
	)

	it("an approved raft built on an unlanded raft waits for it, and lands once it has landed", function()
		local on = built("R0070", { on = "R0060", onLanded = false })
		local d = decide({ on }, {}, "R0070")
		t.expect(d.action).toBe("wait")
		t.expect(has(d.why, "R0070 is built on R0060, which has not landed")).toBe(true)
		local landed = built("R0070", { on = "R0060", onLanded = true })
		t.expect(decide({ landed }, {}, "R0070").action).toBe("done")
		t.expect(decide({ landed }, {}).action).toBe("done")
	end)

	it("a raft without lands goes to done as before, whatever its approvals", function()
		local legacy = built("R0050", { lands = false })
		t.expect(decide({ legacy }, {}, "R0050").action).toBe("done")
	end)

	it("an issue can be named: draft, a held design to resume, rafting, or its raft's action", function()
		local all = {
			issue("c0020"),
			issue("c0021", { status = "preparing" }),
			prepared("c0030"),
			prepared("c0010", { status = "active", raft = "R0050" }),
			issue("c0022", { draftBlock = "open to the human (F1)" }),
		}
		local rafts = { built("R0050") }
		local d1 = decide(rafts, all, "c0020")
		t.expect(d1.action).toBe("draft")
		t.expect(work.say(d1):sub(1, 15)).toBe("c0020: draft - ")
		local d2 = decide(rafts, all, "c0021")
		t.expect(d2.action).toBe("draft")
		t.expect(has(d2.why, "c0021 is being designed: resume its prep worktree")).toBe(true)
		t.expect(decide(rafts, all, "c0030").action).toBe("rafting")
		local d4 = decide(rafts, all, "c0010")
		t.expect(d4.raft).toBe("R0050")
		t.expect(d4.action).toBe("done")
		local d5 = decide(rafts, all, "c0022")
		t.expect(d5.action).toBe("none")
		t.expect(has(d5.why, "its idea needs the person")).toBe(true)
		t.expect(decide(rafts, all, "c0999").action).toBe("none")
	end)

	it("a project's folder sees only its own issues", function()
		local mine = issue("f0020", { root = "pickman/.tracker" })
		local theirs = issue("c0010")
		local d =
			work.decide({ author = ADA, scope = "pickman/.tracker", rafts = {}, issues = { theirs, mine } })
		t.expect(d.ticket).toBe("f0020")
		-- a dependency in another project still counts
		local dependent = prepared("f0021", { root = "pickman/.tracker", deps = { "c0010" } })
		local none = work.decide({
			author = ADA,
			scope = "pickman/.tracker",
			rafts = {},
			issues = { theirs, dependent },
		})
		t.expect(none.action).toBe("none")
		t.expect(has(none.why, "f0021: depends on c0010, which is not designed")).toBe(true)
	end)

	it("with no issue facts every pick is today's", function()
		local d = work.decide({ rafts = { raft({ id = "R0009" }), raft({ id = "R0020" }) } })
		t.expect(d.raft).toBe("R0009")
		t.expect(d.action).toBe("ready")
		local none = work.decide({ rafts = { raft({ id = "R0030", where = "active" }) } })
		t.expect(none.action).toBe("none")
		t.expect(has(none.why, "R0030: is held")).toBe(true)
		t.expect(work.report({ rafts = {} }, work.decide({ rafts = {} })))
			.toBe("nothing to do - no claimable raft")
	end)

	it("the report lists the issues that were not picked under the head line", function()
		local input: work.Input = {
			author = ADA,
			rafts = {},
			issues = { issue("c0001", { status = "preparing" }), prepared("c0003", { sized = false }) },
		}
		local text = work.report(input, work.decide(input))
		t.expect(has(text, "nothing to do - no claimable raft\n")).toBe(true)
		t.expect(has(text, "\nc0001: is being designed (preparing): name it to resume")).toBe(true)
		t.expect(has(text, "\nc0003: has no size:")).toBe(true)
	end)
end)
