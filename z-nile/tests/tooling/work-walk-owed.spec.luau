--!strict
-- f0420 review 001 F1: every unit answer in the walk is an action the session can take or something the person owes;
-- a named call never ends on a bare `none`. One case per state the review found ending stuck, and a property case.
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function raft(id: string, over: { [string]: any }?): work.RaftFact
	local r: work.RaftFact = {
		id = id,
		title = id,
		where = "backlog",
		status = "prepared",
		designReady = true,
		depsMet = true,
		questions = false,
		issues = {},
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
	for k, v in (over or {}) :: { [string]: any } do
		(r :: any)[k] = v
	end
	return r
end

local function issue(id: string, over: { [string]: any }?): work.IssueFact
	local i: work.IssueFact = {
		id = id,
		root = "z-nile/.tracker",
		status = "prepared",
		raft = "",
		designReady = true,
		sized = true,
		deps = {},
		draftBlock = "",
	}
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function layer(position: number, id: string, finished: boolean): work.LayerFact
	return {
		position = position,
		issue = id,
		name = `x/{position}/{id}`,
		commits = 2,
		onlyStart = false,
		finished = finished,
	}
end

local function awaiting(id: string, member: string): work.RaftFact
	return raft(id, {
		where = "active",
		status = "active",
		issues = { member },
		layers = { layer(1, member, true) },
		stacked = true,
		codeReview = "resolved",
		finalReview = "approved",
		trace = true,
		traceOk = true,
		lands = true,
		unapproved = { `{member} (no approval)` },
	})
end

-- R0100 (member c0101) waits on c0090.
local function top(extra: { [string]: any }?): work.RaftFact
	local over: { [string]: any } = { issues = { "c0101" }, outside = { "c0090" }, depsMet = false }
	for k, v in (extra or {}) :: { [string]: any } do
		over[k] = v
	end
	return raft("R0100", over)
end

local function member(deps: { string }?, over: { [string]: any }?): work.IssueFact
	local i = issue("c0101", { raft = "R0100", deps = deps or { "c0090" } })
	for k, v in (over or {}) :: { [string]: any } do
		(i :: any)[k] = v
	end
	return i
end

local function decide(rafts: { work.RaftFact }, issues: { work.IssueFact }): work.Decision
	return work.decide({ asked = "R0100", rafts = rafts, issues = issues })
end

local function owedCommands(d: work.Decision): { string }
	local out: { string } = {}
	for _, o in (d.owed or {}) :: { work.Owed } do
		table.insert(out, o.command)
	end
	return out
end

return t.spec("f0420 review F1: nothing is stuck", function(it)
	local function mineRaft(state: string, number: number?): work.RaftFact
		return raft("R0100", {
			status = "preparing",
			issues = { "c0101" },
			mine = true,
			worktree = ".worktree/unfold-c0283",
			prState = state,
			prNumber = number,
		})
	end

	it(
		"a/N1: a claim whose pull request is open is finished there, with the pull request merged when green",
		function()
			local d = decide({ mineRaft("open", 676) }, { member({}) })
			t.expect(d.action).toBe("rafting")
			t.expect(d.raft).toBe("R0100")
			t.expect(has(d.why, ".worktree/unfold-c0283, where its pull request #676 is open")).toBe(true)
			t.expect(
				has(d.why, "merge origin/main, run the carried ./zn status R0100 prepared, commit, push")
			)
				.toBe(true)
			t.expect(has(d.why, "merge the pull request when it is green")).toBe(true)
			t.expect(has(d.why, "./zn release")).toBe(false)
		end
	)

	it(
		"N1: a merged, closed or missing pull request means the claim is released from its worktree",
		function()
			local cases: { { state: string, number: number?, text: string } } = {
				{
					state = "merged",
					number = 655,
					text = "Its pull request #655 already merged without giving the claim back.",
				},
				{ state = "closed", number = 12, text = "Its pull request #12 was closed without merging." },
				{ state = "none", number = nil, text = "No pull request was found for its branch." },
			}
			for _, c in cases do
				local d = decide({ mineRaft(c.state, c.number) }, { member({}) })
				t.expect(d.action).toBe("rafting")
				t.expect(has(d.why, c.text)).toBe(true)
				t.expect(
					has(
						d.why,
						"From .worktree/unfold-c0283 run ./zn release R0100 (it is this checkout's own claim, so no --force): it gives the claim back and the raft returns to prepared (new when its design is not ready); then ask again."
					)
				).toBe(true)
				t.expect(has(d.why, "when it is green")).toBe(false)
			end
		end
	)

	it(
		"a: a preparing raft that may not be this checkout's is owed its give-back, pastable with a note",
		function()
			local r = raft("R0100", { status = "preparing", issues = { "c0101" } })
			local d = decide({ r }, { member({}) })
			t.expect(d.action).toBe("wait")
			t.expect(owedCommands(d)).toEqual({ "./zn release R0100 --force" })
			t.expect(
				has(
					d.why,
					"./zn release R0100 --force # run from any worktree; safe only when no session is rafting it and no open pull request carries its claim\n"
				)
			).toBe(true)
		end
	)

	it("N4: a claim another live session carries is waited on, never owed and never forced", function()
		local mine = mineRaft("open", 676)
		local input: work.Input = {
			asked = "R0100",
			rafts = { mine },
			issues = { member({}) },
			session = "me",
			carriers = { R0100 = { session = "other", age = 10 } },
		}
		local carried = work.decide(input)
		t.expect(carried.action).toBe("wait")
		t.expect(has(carried.why, "held by other: it is rafting R0100 now")).toBe(true)
		t.expect(has(carried.why, "--force")).toBe(false)
		t.expect(carried.owed).toEqual({})
		t.expect(work.walk(input, "R0100").answers.R0100.kind).toBe("waits")
		-- the same for a design this checkout remembers
		local ours = issue("c0090", { status = "preparing", designReady = false, mine = true })
		local dep: work.Input = {
			asked = "R0100",
			rafts = { top() },
			issues = { member(), ours },
			session = "me",
			carriers = { c0090 = { session = "other", age = 10 } },
		}
		t.expect(work.walk(dep, "R0100").answers.c0090.kind).toBe("waits")
		t.expect(has(work.decide(dep).why, "held by other: it is designing c0090 now")).toBe(true)
	end)

	it("N3: the claim lookup is made only for a unit of a named walk", function()
		local calls: { string } = {}
		local mine = raft("R0100", { status = "preparing", issues = { "c0101" } })
		local base: work.Input = {
			rafts = { mine },
			issues = { member({}) },
			claimOf = function(r: work.RaftFact): work.ClaimFact?
				table.insert(calls, r.id)
				return { worktree = ".worktree/w", pr = "none" }
			end,
		}
		work.decide(base) -- unnamed
		base.asked = "R0100"
		base.one = true
		work.decide(base) -- --one, and dispatch
		t.expect(calls).toEqual({})
		base.one = nil
		local d = work.decide(base)
		t.expect(calls).toEqual({ "R0100" })
		t.expect(d.action).toBe("rafting")
	end)

	it("b/N2: an empty raft is retired by a keeper when one exists, with the exact command", function()
		local empty = raft("R0100", { issues = {}, kind = "chore" })
		local keepers = {
			raft("R0050", { issues = { "c0050" }, kind = "chore" }),
			raft("R0030", { issues = { "c0030" }, kind = "chore" }),
			raft("R0010", { issues = { "c0010" }, kind = "defect" }), -- another type
			raft("R0020", { issues = { "c0020" }, kind = "chore", root = "pickman/.tracker" }), -- another project
			raft("R0021", { issues = { "c0021" }, kind = "chore", status = "preparing" }), -- being rafted
			raft("R0022", { issues = { "c0022" }, kind = "chore", where = "active", status = "active" }),
			raft("R0005", { issues = {}, kind = "chore" }), -- itself empty: not a place to retire into
		}
		local rafts = { empty }
		for _, k in keepers do
			table.insert(rafts, k)
		end
		local d = decide(rafts, {})
		t.expect(d.action).toBe("fix")
		t.expect(d.raft).toBe("R0100")
		t.expect(has(d.why, "./zn recombine R0030 R0100")).toBe(true)
		t.expect(
			has(
				d.why,
				"retires R0100 (its folder moves to rafts/retired/ in that branch, carried by the rafting pull request)"
			)
		).toBe(true)
		t.expect(
			has(
				d.why,
				"Then run ./zn status R0030 prepared, merge the rafting pull request when it is green, then ask again."
			)
		).toBe(true)
		-- no keeper: owed, by the raft document
		local alone = decide({ empty, keepers[3], keepers[4] }, {})
		t.expect(alone.action).toBe("wait")
		t.expect(owedCommands(alone)).toEqual({ "z-nile/.tracker/rafts/R0100/R0100.md" })
		t.expect(has(alone.why, "no keeper to retire it into")).toBe(true)
	end)

	it("b/N2: an empty preparing raft is owed its give-back, in two steps", function()
		local empty = raft("R0100", { status = "preparing", issues = {} })
		local d = decide({ empty }, {})
		t.expect(d.action).toBe("wait")
		t.expect(owedCommands(d)).toEqual({ "./zn release R0100 --force" })
		t.expect(
			has(d.why, "safe only when no session is rafting it and no open pull request carries its claim")
		)
			.toBe(true)
		t.expect(has(d.why, "it then shows as an empty raft to retire")).toBe(true)
	end)

	it(
		"b/N2: a new raft that has members is not an empty raft: its members' state says what is next",
		function()
			local fresh = raft("R0100", { status = "new", designReady = false, issues = { "c0101" } })
			local m = member({}, { status = "new", designReady = false })
			local d = decide({ fresh }, { m })
			t.expect(d.action).toBe("fix")
			t.expect(d.ticket).toBe("c0101")
			t.expect(has(d.why, "an empty raft")).toBe(false)
			local idea = decide(
				{ fresh },
				{ member({}, { status = "new", designReady = false, draftBlock = "no idea-review-001.md" }) }
			)
			t.expect(owedCommands(idea)).toEqual({ "./zn idea c0101" })
		end
	)

	it("b: an empty raft elsewhere does not stand in the way of a walk", function()
		local other = raft("R0040", { status = "new", issues = {} })
		local ok = decide(
			{ top(), other },
			{ member(), issue("c0090", { status = "new", designReady = false }) }
		)
		t.expect(ok.action).toBe("draft")
		t.expect(ok.ticket).toBe("c0090")
	end)

	it("c: a closed dependency is owed on the depending ticket's document, whoever depends on it", function()
		local closed = issue("c0090", { status = "closed" })
		local d = decide({ top() }, { member(), closed })
		t.expect(d.action).toBe("wait")
		t.expect(owedCommands(d)).toEqual({ "z-nile/.tracker/issues/c0101/c0101.md" })
		t.expect(has(d.why, "# depends on c0090, which was closed: remove the dependency or reopen it"))
			.toBe(true)
		-- a raftless dependency that itself depends on a closed ticket
		local loose = issue("c0095", { deps = { "c0090" } })
		local d2 = decide({ top({ outside = { "c0095" } }) }, { member({ "c0095" }), loose, closed })
		t.expect(owedCommands(d2)).toEqual({ "z-nile/.tracker/issues/c0095/c0095.md" })
	end)

	it(
		"d: a preparing dependency is resumed where this checkout remembers it, otherwise owed its give-back",
		function()
			local theirs = issue("c0090", { status = "preparing", designReady = false })
			local d = decide({ top() }, { member(), theirs })
			t.expect(d.action).toBe("wait")
			t.expect(owedCommands(d)).toEqual({ "./zn status c0090 new" })
			local ours = issue("c0090", { status = "preparing", designReady = false, mine = true })
			local r = decide({ top() }, { member(), ours })
			t.expect(r.action).toBe("draft")
			t.expect(r.ticket).toBe("c0090")
			-- a member of the raft that is preparing and not ours
			local m = member({}, { status = "preparing", designReady = false })
			local d2 = decide({ raft("R0100", { issues = { "c0101" }, designReady = false }) }, { m })
			t.expect(owedCommands(d2)).toEqual({ "./zn status c0101 new" })
		end
	)

	it(
		"e: a raft member that is new or not design: ready is fixed by unfolding it, not drafted in the raft",
		function()
			local m = member({}, { status = "new", designReady = false })
			local d = decide({ raft("R0100", { issues = { "c0101" }, designReady = false }) }, { m })
			t.expect(d.action).toBe("fix")
			t.expect(d.ticket).toBe("c0101")
			t.expect(has(d.why, "./zn unfold R0100 c0101")).toBe(true)
			t.expect(has(d.why, "z-design")).toBe(true)
		end
	)

	it("f: a dependency whose raft is retired or missing is fixed by unfolding it", function()
		local lost = issue("c0090", { raft = "R0050" })
		local d = decide({ top() }, { member(), lost })
		t.expect(d.action).toBe("fix")
		t.expect(d.ticket).toBe("c0090")
		t.expect(has(d.why, "./zn unfold R0050 c0090")).toBe(true)
	end)

	it("g: an added issue is never picked: it is owed by file", function()
		local added = issue("c0090", { status = "new", designReady = false, added = true })
		local d = decide({ top() }, { member(), added })
		t.expect(d.action).toBe("wait")
		t.expect(owedCommands(d)).toEqual({ "z-nile/.tracker/issues/c0090/c0090.md" })
	end)

	it("h: a bad risk or rounds setting on an active raft is owed by file and sentence", function()
		local r = awaiting("R0100", "c0101")
		r.unapproved = nil
		r.roundsProblem = "c0101: risk is high: easy, normal or risky"
		local d = decide({ r }, { member({}, { status = "active" }) })
		t.expect(d.action).toBe("wait")
		t.expect(owedCommands(d)).toEqual({ "z-nile/.tracker/issues/c0101/c0101.md" })
		t.expect(has(d.why, "# c0101: risk is high: easy, normal or risky")).toBe(true)
		r.roundsProblem = "[rounds] code: not a number"
		local d2 = decide({ r }, { member({}, { status = "active" }) })
		t.expect(owedCommands(d2)).toEqual({ ".models.toml" })
	end)

	it(
		"i: a raft built on an unlanded base lists the base's owed items, never 'ask again with no raft'",
		function()
			local base = raft("R0090", { status = "preparing", issues = { "c0090" } })
			local built = awaiting("R0100", "c0101")
			built.unapproved = nil
			built.on = "R0090"
			built.onLanded = false
			built.outside = { "c0090" }
			local d = decide(
				{ built, base },
				{ member({ "c0090" }, { status = "active" }), issue("c0090", { raft = "R0090" }) }
			)
			t.expect(d.action).toBe("wait")
			t.expect(owedCommands(d)).toEqual({ "./zn release R0090 --force" })
			t.expect(has(d.why, "ask again with no raft")).toBe(false)
			-- a base that is not even among the dependencies is still waited on, never left out
			local lone = awaiting("R0100", "c0101")
			lone.unapproved = nil
			lone.on = "R0090"
			lone.onLanded = false
			lone.outside = {}
			local d2 = decide(
				{ lone, base },
				{ member({}, { status = "active" }), issue("c0090", { raft = "R0090" }) }
			)
			t.expect(owedCommands(d2)).toEqual({ "./zn release R0090 --force" })
		end
	)

	it(
		"property: whatever mix of these states, a named raft is never answered none and nothing is stuck",
		function()
			local variants: { { label: string, build: () -> ({ work.RaftFact }, { work.IssueFact }) } } = {}
			local function add(label: string, build: () -> ({ work.RaftFact }, { work.IssueFact }))
				table.insert(variants, { label = label, build = build })
			end
			for _, depState in { "new", "preparing", "closed", "prepared", "added", "lost", "mine" } do
				for _, memberState in { "ready", "new", "preparing" } do
					for _, rState in { "backlog", "preparing", "empty", "questions", "mine" } do
						add(`{depState}/{memberState}/{rState}`, function()
							local dep = issue("c0090")
							if depState == "new" then
								dep.status, dep.designReady, dep.sized = "new", false, false
							elseif depState == "preparing" then
								dep.status, dep.designReady = "preparing", false
							elseif depState == "closed" then
								dep.status = "closed"
							elseif depState == "added" then
								dep.status, dep.designReady, dep.added = "new", false, true
							elseif depState == "lost" then
								dep.raft = "R0050"
							elseif depState == "mine" then
								dep.status, dep.designReady, dep.mine = "preparing", false, true
							end
							local m = member()
							if memberState == "new" then
								m.status, m.designReady = "new", false
							elseif memberState == "preparing" then
								m.status, m.designReady = "preparing", false
							end
							local r = top()
							if rState == "preparing" then
								r.status = "preparing"
							elseif rState == "empty" then
								r.issues = {}
							elseif rState == "questions" then
								r.questions = true
							elseif rState == "mine" then
								r.status, r.mine, r.worktree = "preparing", true, ".worktree/w"
							end
							return { r }, { m, dep }
						end)
					end
				end
			end
			t.expect(#variants).toBe(105)
			for _, v in variants do
				local rafts, issues = v.build()
				local d = decide(rafts, issues)
				if d.action == "none" then
					error(`{v.label}: answered none: {d.why}`)
				end
				local w = work.walk({ asked = "R0100", rafts = rafts, issues = issues }, "R0100")
				for id, a in w.answers do
					if a.kind ~= "act" and a.kind ~= "owed" and a.kind ~= "waits" then
						error(`{v.label}: {id} is {a.kind}`)
					end
					if a.kind == "waits" and #a.on == 0 then
						error(`{v.label}: {id} waits on nothing`)
					end
				end
				if d.action == "wait" or d.action == "end" then
					t.expect(#(d.owed or {}) > 0 or d.action == "end").toBe(true)
				end
			end
		end
	)

	it("a changed approved contract is owed as the approve command itself", function()
		local r = raft("R0100", {
			issues = { "c0101" },
			block = "c0101's contract changed since approval: design. Run ./zn approve c0101 again.",
		})
		local d = decide({ r }, { member({}) })
		t.expect(d.action).toBe("wait")
		t.expect(owedCommands(d)).toEqual({ "./zn approve c0101" })
	end)

	it("M32: the stop counts units that owe, not their items", function()
		local r = awaiting("R0100", "c0101")
		r.issues = { "c0101", "c0102" }
		r.layers = { layer(1, "c0101", true), layer(2, "c0102", true) }
		r.unapproved = { "c0101 (no approval)", "c0102 (no approval)" }
		local d = decide(
			{ r },
			{ member({}, { status = "active" }), issue("c0102", { raft = "R0100", status = "active" }) }
		)
		t.expect(d.action).toBe("wait")
		t.expect(#(d.owed or {})).toBe(2)
		t.expect(string.match(d.why, "^[^\n]*") :: string)
			.toBe("R0100 is not landed yet: 1 unit needed, 0 can be worked now, 1 wait for you")
	end)
end)
