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

-- a session that can be named, as Claude Code's and Kimi's are
local function decide(
	rafts: { work.RaftFact },
	issues: { work.IssueFact }?,
	asked: string?,
	carriers: { [string]: work.Carrier }?
): work.Decision
	return work.decide({
		asked = asked,
		author = ADA,
		session = "S1",
		carriers = carriers,
		rafts = rafts,
		issues = issues,
	})
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

	it(
		"it resumes this author's held raft that no live session carries, after one that only has to land and before a raft to ready",
		function()
			local building = built("R0030", { finalReview = "none", traceOk = false })
			local land = built("R0050")
			local ready = raft({ id = "R0020" })
			local d1 = decide({ ready, building, land }, {})
			t.expect(d1.raft).toBe("R0050")
			t.expect(d1.action).toBe("done")
			local d2 = decide({ ready, building }, {})
			t.expect(d2.raft).toBe("R0030")
			t.expect(d2.action).toBe("final-review")
			t.expect(has(d2.why, "Resuming R0030: you hold it and no live session carries it.")).toBe(true)
			-- a held raft that waits, or was released, is not a resume
			local waits = built("R0031", { unapproved = { "c0010 (no approval)" } })
			t.expect(decide({ ready, waits }, {}).raft).toBe("R0020")
		end
	)

	it(
		"a held raft is not resumed when another session carries it, the session cannot be named, or another person holds it, and a stale carrier frees it",
		function()
			local building = built("R0030", { finalReview = "none", traceOk = false })
			local land = built("R0050")
			local next = issue("c0020")
			local live = { R0030 = { session = "S2", age = 60 }, R0050 = { session = "S2", age = 60 } }
			local d = decide({ building, land }, { next }, nil, live)
			t.expect(d.ticket).toBe("c0020")
			-- every unnamed pick still says what this person holds
			t.expect(has(d.why, "you hold R0030, R0050: name one to resume it.")).toBe(true)
			local mine = { R0030 = { session = "S1", age = 60 } }
			t.expect(decide({ building }, { next }, nil, mine).raft).toBe("R0030")
			local stale = { R0030 = { session = "S2", age = work.STALE + 1 } }
			t.expect(decide({ building }, { next }, nil, stale).raft).toBe("R0030")
			local edge = { R0030 = { session = "S2", age = work.STALE } }
			t.expect(decide({ building }, { next }, nil, edge).ticket).toBe("c0020")
			local unnamed = work.decide({ author = ADA, rafts = { building, land }, issues = { next } })
			t.expect(unnamed.ticket).toBe("c0020")
			local others = built("R0049", { holder = "Bo <bo@example>" })
			t.expect(decide({ others }, { next }).ticket).toBe("c0020")
		end
	)

	it(
		"it never picks a held design of another checkout, an unchallenged idea, a closed issue, an added issue or a member",
		function()
			local none = decide({}, {
				issue("c0001", { status = "preparing" }),
				issue(
					"c0002",
					{ draftBlock = "no idea-review-001.md (the idea was not challenged): ./zn idea c0002" }
				),
				issue("c0003", { status = "preparing", mine = true }),
				issue("c0004", { status = "closed" }),
				prepared("c0005", { added = true }),
				prepared("c0006", { raft = "R0099" }),
			}, nil, { c0003 = { session = "S2", age = 60 } })
			t.expect(none.action).toBe("none")
			t.expect(none.ticket).toBe("")
			t.expect(has(none.why, "c0001: is being designed (preparing): name it to resume")).toBe(true)
			t.expect(has(none.why, "c0002: its idea needs the person (no idea-review-001.md")).toBe(true)
			-- its prep worktree is here, but another live session carries it
			t.expect(has(none.why, "c0003: is being designed (preparing): name it to resume")).toBe(true)
			t.expect(has(none.why, "c0004")).toBe(false)
			t.expect(has(none.why, "c0005")).toBe(false)
			t.expect(has(none.why, "c0006")).toBe(false)
			t.expect(has(work.say(none), "nothing to do - ")).toBe(true)
		end
	)

	it(
		"fix is offered for a raft ready refuses for a repairable reason and for a prepared issue with no size, and never for a dependency, questions or a changed approval",
		function()
			local stale = raft({
				id = "R0040",
				block = "R0040's coherence review predates its record: run a new raft-mode round (z-raft, zz-review); never edit a review that is already written",
			})
			local d = decide({ stale }, { prepared("c0030"), issue("c0020") })
			t.expect(d.raft).toBe("R0040")
			t.expect(d.action).toBe("fix")
			t.expect(has(d.why, "ready refuses R0040: R0040's coherence review predates its record"))
				.toBe(true)
			t.expect(has(work.say(d), "R0040: fix - ")).toBe(true)
			-- a raft ready accepts comes first
			t.expect(decide({ stale, raft({ id = "R0041", block = "" }) }, {}).action).toBe("ready")
			-- not repairable by the worker: the person approves again, answers questions.md, or the dependency lands
			local drifted = raft({
				id = "R0042",
				block = "c0010's contract changed since approval: design. Run ./zn approve c0010 again, then ./zn approve c0010 --publish.",
			})
			local asked = raft({ id = "R0043", questions = true, block = "R0043 has questions.md" })
			local waitsOn = raft({
				id = "R0044",
				depsMet = false,
				block = "c0010 depends on c0009, which is active on origin/main: it must be done first",
			})
			local none = decide({ drifted, asked, waitsOn }, {})
			t.expect(none.action).toBe("none")
			-- an unsized prepared issue: after an issue that can be rafted, before a draft
			local unsized = prepared("c0031", { sized = false })
			t.expect(decide({}, { unsized, prepared("c0035"), issue("c0020") }).ticket).toBe("c0035")
			local f = decide({}, { unsized, issue("c0020") })
			t.expect(f.ticket).toBe("c0031")
			t.expect(f.action).toBe("fix")
			t.expect(has(f.why, "c0031 is prepared with no size:")).toBe(true)
		end
	)

	it("a design whose prep worktree is in this checkout is resumed before a new draft", function()
		local mine = issue("c0025", { status = "preparing", mine = true })
		local fresh = issue("c0020")
		local d = decide({}, { fresh, mine })
		t.expect(d.ticket).toBe("c0025")
		t.expect(d.action).toBe("draft")
		t.expect(has(d.why, "c0025 is being designed and its prep worktree is here: resume it")).toBe(true)
		-- a prepared issue is further along
		t.expect(decide({}, { fresh, mine, prepared("c0030") }).ticket).toBe("c0030")
		-- another live session carries it
		t.expect(decide({}, { fresh, mine }, nil, { c0025 = { session = "S2", age = 60 } }).ticket)
			.toBe("c0020")
	end)

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
		-- a closed dependency never lands: the person has to change depends_on
		local closed = issue("c0040", { status = "closed" })
		local onClosed = prepared("c0041", { deps = { "c0040" } })
		local stuck = decide({}, { onClosed, closed })
		t.expect(stuck.action).toBe("none")
		t.expect(
			has(
				stuck.why,
				"c0041: depends on c0040, which is closed (won't do): its depends_on needs the person"
			)
		).toBe(true)
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
			-- f0420: the named wait lists one exact `./zn approve <id>` per member, and no longer says "ask again with no raft"
			t.expect(
				has(
					d.why,
					"./zn approve c0010 # in R0050 (changed: guesses); ./zn guesses R0050 lists what to review\n"
				)
			).toBe(true)
			t.expect(
				has(
					d.why,
					"./zn approve f0011 # in R0050 (no approval); ./zn guesses R0050 lists what to review\n"
				)
			).toBe(true)
			t.expect(has(d.why, "ask again with no raft")).toBe(false)
			t.expect(has(work.say(d), "R0050: wait - ")).toBe(true)
			-- --one keeps the raft's own answer, with the guesses and the members' reasons
			local alone = work.decide({ asked = "R0050", rafts = { waiting }, issues = {}, one = true })
			t.expect(alone.action).toBe("wait")
			t.expect(has(alone.why, "./zn approve c0010, f0011")).toBe(true)
			t.expect(has(alone.why, "c0010 (changed: guesses)")).toBe(true)
			t.expect(has(alone.why, "./zn guesses R0050")).toBe(true)
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
		-- f0420: a named ticket is walked like a named raft: what only the person can do is owed, as the Stops message
		local d5 = decide(rafts, all, "c0022")
		t.expect(d5.action).toBe("wait")
		t.expect(has(d5.why, "c0022 is not landed yet")).toBe(true)
		t.expect(has(d5.why, "open to the human (F1)")).toBe(true)
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
			issues = {
				issue("c0001", { status = "preparing" }),
				issue("c0003", { draftBlock = "open to the human (F1)" }),
			},
		}
		local text = work.report(input, work.decide(input))
		t.expect(has(text, "nothing to do - no claimable raft\n")).toBe(true)
		t.expect(has(text, "\nc0001: is being designed (preparing): name it to resume")).toBe(true)
		t.expect(has(text, "\nc0003: its idea needs the person (open to the human (F1))")).toBe(true)
	end)
end)
