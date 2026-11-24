--!strict
-- f0421 step 8b (the capability filter in `work next`): a worker is handed an activity only when its CLI can deliver the model
-- that activity needs at the unit's risk level. Pure: a fixture config (the design's seed, here as text), facts in, answers out.
--   - a unit whose next activity the worker's CLI lacks is skipped for one it can do, and stays in the facts (a dependent never
--     reads it as landed);
--   - when every unit open to it needs what its CLI lacks, the answer is a wait that starts `waiting for a worker with `
--     (work.WAITING, the words ./zn model's exit 1 prints too) and the z-work skill matches that same constant;
--   - a worker that cannot be named (nil capability) gets what it always got.
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local work = require("@znile/engine/work")
local workcan = require("@znile/engine/workcan")
local workerlive = require("@znile/engine/workerlive")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

-- A fixture configuration: claude has all four aliases, grok only light, kimi only heavy (an invented fixture, not the seed).
local CONFIG = [[
[clis.claude]
xlight = { model = "claude-haiku-5-5", effort = "low" }
light = { model = "claude-sonnet-5-5", effort = "medium" }
heavy = { model = "claude-opus-5-5", effort = "high" }
ultra = { model = "claude-fable-5-2", effort = "xhigh" }
[clis.grok]
light = { model = "grok-4.7", effort = "high" }
[clis.kimi]
heavy = { model = "kimi-code-k3.1-pro" }
[activities.idea]
max_tokens = 300000
all = "heavy"
[activities.idea-challenge]
max_tokens = 300000
all = "ultra"
[activities.design]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.design-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.raft]
max_tokens = 3000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.raft-review]
max_tokens = 3000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.code]
max_tokens = 12000000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.code-review]
max_tokens = 2000000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.final-review]
max_tokens = 2000000
all = "ultra"
[activities.approve]
max_tokens = 3000000
all = "heavy"
]]

local LAYERS = { models.parse(CONFIG, ".models.toml") }

local function cap(cli: string): work.Capability
	return workcan.of(LAYERS, cli)
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

-- An active raft whose one layer is finished and stacked: its next action is the code review, round 1.
local function reviewable(id: string, ticket: string, over: { [string]: any }?): work.RaftFact
	local r = raft(id, {
		where = "active",
		issues = { ticket },
		layers = {
			{
				position = 1,
				issue = ticket,
				name = `{id}/1/{ticket}`,
				commits = 3,
				onlyStart = false,
				finished = true,
			},
		},
		stacked = true,
	})
	for k, v in (over or {}) :: { [string]: any } do
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

return t.spec("f0421 step 8b: the capability filter of work next", function(it)
	it("models.waiting is the one wording: the need and the CLIs that deliver it", function()
		t.expect(models.waiting(LAYERS, "code-review", "normal"))
			.toBe("code-review/normal (heavy: claude, kimi)")
		t.expect(models.waiting(LAYERS, "code-review", "risky")).toBe("code-review/risky (ultra: claude)")
	end)

	it(
		"a worker whose CLI lacks the next activity of the only unit waits, naming activity, unit and need",
		function()
			local d = work.decide({
				asked = "R0100",
				rafts = { reviewable("R0100", "c0100") },
				issues = { issue("c0100", { status = "active", raft = "R0100" }) },
				capable = cap("grok"),
			})
			t.expect(d.action).toBe("wait")
			t.expect(d.owed).toBe(nil)
			t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
			t.expect(has(d.why, "code-review/normal (heavy: claude, kimi)")).toBe(true)
			t.expect(has(d.why, "R0100")).toBe(true)
			t.expect(has(d.why, "grok")).toBe(true)
			t.expect(has(d.why, "is not landed yet:")).toBe(false) -- never the Stops text: the person owes nothing
			-- the same raft on a CLI that has heavy is handed the review
			local ok = work.decide({
				asked = "R0100",
				rafts = { reviewable("R0100", "c0100") },
				issues = { issue("c0100", { status = "active", raft = "R0100" }) },
				capable = cap("claude"),
			})
			t.expect(ok.action).toBe("review")
		end
	)

	it(
		"f0421 agy (the repository's own table): agy reviews at normal through its review alias, and waits at risky",
		function()
			local root = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			local agy = workcan.of(root, "agy")
			local normal = work.decide({
				asked = "R0100",
				rafts = { reviewable("R0100", "c0100") },
				issues = { issue("c0100", { status = "active", raft = "R0100" }) },
				capable = agy,
			})
			t.expect(normal.action).toBe("review")
			local risky = work.decide({
				asked = "R0300",
				rafts = { reviewable("R0300", "c0300", { level = "risky" }) },
				issues = { issue("c0300", { status = "active", raft = "R0300", level = "risky" }) },
				capable = agy,
			})
			t.expect(risky.action).toBe("wait")
			t.expect(string.sub(risky.why, 1, #work.WAITING)).toBe(work.WAITING)
			t.expect(has(risky.why, "code-review/risky (ultra: claude)")).toBe(true)
		end
	)

	it(
		"answering a review is the writer's activity, not the reviewer's: a worker that can code is handed it",
		function()
			local d = work.decide({
				asked = "R0100",
				rafts = { reviewable("R0100", "c0100", { codeReview = "open", codeRound = 1 }) },
				issues = { issue("c0100", { status = "active", raft = "R0100" }) },
				capable = cap("grok"), -- grok has light: code/normal
			})
			t.expect(d.action).toBe("review")
		end
	)

	it(
		"an unnamed pick skips the unit it cannot do for one it can, and the skipped one stays a fact",
		function()
			local issues = {
				issue("c0090"), -- design/normal: light
				issue("c0095", { level = "risky" }), -- design/risky: heavy
				issue("c0099", { deps = { "c0090" }, status = "prepared", designReady = true, sized = true }),
			}
			local claude =
				work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("claude") })
			t.expect(claude.ticket).toBe("c0090")
			local kimi = work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("kimi") })
			t.expect(kimi.ticket).toBe("c0095") -- kimi has heavy only
			t.expect(kimi.action).toBe("draft")
			-- a risky design grok lacks (heavy) with a dependent grok CAN raft (raft/normal is light): the dependent is never
			-- handed out as if the skipped one had landed
			local fact = work.decide({
				rafts = {},
				issues = {
					issue("c0090", { level = "risky" }),
					issue(
						"c0099",
						{ deps = { "c0090" }, status = "prepared", designReady = true, sized = true }
					),
				},
				session = "s",
				capable = cap("grok"),
			})
			t.expect(fact.action).toBe("wait")
			t.expect(fact.ticket).toBe("c0090")
			-- c0099 depends on the skipped c0090: it is never handed out as if c0090 had landed
			local grok = work.decide({
				rafts = {},
				issues = { issues[1], issues[3] },
				session = "s",
				capable = cap("kimi"),
			})
			t.expect(grok.action).toBe("wait")
			t.expect(grok.ticket ~= "c0099").toBe(true)
		end
	)

	it("when every unit needs what the CLI lacks, an unnamed worker waits with the same words", function()
		local d = work.decide({
			rafts = {},
			issues = { issue("c0090"), issue("c0091") },
			session = "s",
			capable = cap("kimi"),
		})
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d.why, "design/normal (light: claude, grok)")).toBe(true)
		t.expect(has(d.why, "c0090")).toBe(true)
		t.expect(d.ticket).toBe("c0090")
		t.expect(work.report({ rafts = {}, issues = {}, session = "s" }, d)).toBe(work.say(d))
	end)

	it("with no capability nothing changes", function()
		local d = work.decide({ rafts = {}, issues = { issue("c0090") }, session = "s" })
		t.expect(d.action).toBe("draft")
	end)

	it("a skipped unit of a named raft's closure goes to the unit that can be worked", function()
		local dep = reviewable("R0090", "c0090") -- its next action is a review: heavy
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090", "c0080" }, depsMet = false })
		local other = reviewable("R0080", "c0080", { codeReview = "open", codeRound = 1 }) -- an answer: code
		local issues = {
			issue("c0080", { status = "active", raft = "R0080" }),
			issue("c0090", { status = "active", raft = "R0090" }),
			issue("c0100", { status = "prepared", raft = "R0100", deps = { "c0090", "c0080" } }),
		}
		local d = work.decide({
			asked = "R0100",
			rafts = { top, dep, other },
			issues = issues,
			capable = cap("grok"),
		})
		t.expect(d.raft).toBe("R0080")
		-- when R0080 needs a review as well, nothing is left that grok can deliver: the wait names both, and R0100 stays blocked
		local second = reviewable("R0080", "c0080")
		local d2 = work.decide({
			asked = "R0100",
			rafts = { top, dep, second },
			issues = issues,
			capable = cap("grok"),
		})
		t.expect(d2.action).toBe("wait")
		t.expect(string.sub(d2.why, 1, #work.WAITING)).toBe(work.WAITING)
		t.expect(has(d2.why, "R0080")).toBe(true)
		t.expect(has(d2.why, "R0090")).toBe(true)
		t.expect(has(d2.why, "code-review/normal (heavy: claude, kimi)")).toBe(true)
		t.expect(has(d2.why, "grok cannot deliver it")).toBe(true)
		t.expect(d2.raft).toBe("R0100")
	end)

	it(
		"the next blocker (documents f0420 behaviour): an unnamed reviewer is not offered a raft another account's durable claim holds",
		function()
			-- grok built R0100 and asked again: its live claim is given up, and the review waits for a CLI with heavy. A claude worker
			-- that names the raft is handed the review (the named walk ignores who holds it), but one that asks with no raft is
			-- offered only the raft its own author holds, and the durable claim says grok's author. The filter works for a named
			-- raft; for an unnamed pick the raft must be released per activity (f0420 step 5) before the reviewer is ever offered it.
			local r = reviewable("R0100", "c0100", { holder = "Grok Worker <g@h>" })
			local issues = { issue("c0100", { status = "active", raft = "R0100" }) }
			local named = work.decide({
				asked = "R0100",
				rafts = { r },
				issues = issues,
				author = "Claude Worker <c@h>",
				capable = cap("claude"),
			})
			t.expect(named.action).toBe("review")
			local unnamed = work.decide({
				rafts = { r },
				issues = issues,
				author = "Claude Worker <c@h>",
				session = "s",
				capable = cap("claude"),
			})
			t.expect(unnamed.action ~= "review").toBe(true)
			-- and the same raft is offered to the author who holds it
			local holder = work.decide({
				rafts = { r },
				issues = issues,
				author = "Grok Worker <g@h>",
				session = "s",
				capable = cap("claude"),
			})
			t.expect(holder.action).toBe("review")
			-- the filter is what keeps grok, the holder, from being handed the review it cannot run
			local grok = work.decide({
				rafts = { r },
				issues = issues,
				author = "Grok Worker <g@h>",
				session = "s",
				capable = cap("grok"),
			})
			t.expect(grok.action).toBe("wait")
			t.expect(has(grok.why, "code-review/normal")).toBe(true)
		end
	)

	it(
		"a spec of the skill: z-work says what the wait is and what to do, with the engine's own words",
		function()
			local skill = fs.readFile(`{TOP}/z-nile/skills/z-work/SKILL.md`)
			t.expect(has(skill, work.WAITING)).toBe(true)
			t.expect(has(skill, "does not clear by itself")).toBe(true)
		end
	)

	it(
		"workerlive.capability names the worker's CLI from the environment, and never under dispatch",
		function()
			local function layersOf(): { any }?
				return LAYERS
			end
			local grok = workerlive.capability({ ZN_CLI = "grok" }, layersOf)
			t.expect(grok ~= nil).toBe(true)
			t.expect((grok :: work.Capability).cli).toBe("grok")
			t.expect((workerlive.capability({ ZN_CLI = "grok", ZN_DISPATCH = "1" }, layersOf))).toBe(nil)
			t.expect((workerlive.capability({}, layersOf))).toBe(nil) -- no CLI can be told: no filter
			t.expect((workerlive.capability({ ZN_CLI = "grok" }, function()
				return nil
			end))).toBe(nil) -- the file cannot be read: no filter
		end
	)

	it(
		"work status names a unit no registered worker can deliver, and the kind of worker it waits for",
		function()
			local r = reviewable("R0100", "c0100")
			local workers = { { id = "grok-1@h", cli = "grok", can = models.canList(LAYERS, "grok") } }
			local lines = workcan.waitingFor(
				{ r },
				workers,
				function(a: string, l: "easy" | "normal" | "risky"): string
					return models.waiting(LAYERS, a, l)
				end
			)
			t.expect(#lines).toBe(1)
			t.expect(lines[1])
				.toBe("R0100: waiting for a worker with code-review/normal (heavy: claude, kimi)")
			local both =
				{ workers[1], { id = "claude-2@h", cli = "claude", can = models.canList(LAYERS, "claude") } }
			t.expect(
				#workcan.waitingFor({ r }, both, function(a: string, l: "easy" | "normal" | "risky"): string
					return models.waiting(LAYERS, a, l)
				end)
			)
				.toBe(0)
			t.expect(#workcan.waitingFor({ r }, {}, function(): string
				return ""
			end)).toBe(0) -- no worker registered: nothing is said to wait
		end
	)

	it("work.WAITING is the literal the skill and ./zn model print", function()
		t.expect(work.WAITING).toBe("waiting for a worker with ")
	end)

	it("a raft's own level is the level it is judged at: risky review needs ultra", function()
		local risky = reviewable("R0300", "c0300", { level = "risky" })
		local issues = { issue("c0300", { status = "active", raft = "R0300", level = "risky" }) }
		-- kimi has heavy only: a normal review (heavy) is handed, a risky one (ultra) waits
		local normal = work.decide({
			asked = "R0300",
			rafts = { reviewable("R0300", "c0300") },
			issues = issues,
			capable = cap("kimi"),
		})
		t.expect(normal.action).toBe("review")
		local d = work.decide({ asked = "R0300", rafts = { risky }, issues = issues, capable = cap("kimi") })
		t.expect(d.action).toBe("wait")
		t.expect(has(d.why, "code-review/risky (ultra: claude)")).toBe(true)
	end)

	it("more lacking units than any counter: the last decision is checked too (finding 1)", function()
		local issues: { work.IssueFact } = {}
		for n = 1000, 1069 do
			table.insert(issues, issue(`c{n}`))
		end
		local d = work.decide({ rafts = {}, issues = issues, session = "s", capable = cap("kimi") })
		t.expect(d.action).toBe("wait")
		t.expect(string.sub(d.why, 1, #work.WAITING)).toBe(work.WAITING)
	end)

	it("a named raft: a unit held by another worker leads, the lacking unit follows (finding 4)", function()
		local held = reviewable("R0090", "c0090", { codeReview = "open", codeRound = 1 })
		local lacks = reviewable("R0080", "c0080")
		local top = raft("R0100", { issues = { "c0100" }, outside = { "c0090", "c0080" }, depsMet = false })
		local d = work.decide({
			asked = "R0100",
			rafts = { top, held, lacks },
			issues = {
				issue("c0080", { status = "active", raft = "R0080" }),
				issue("c0090", { status = "active", raft = "R0090" }),
				issue("c0100", { status = "prepared", raft = "R0100", deps = { "c0090", "c0080" } }),
			},
			claims = { R0090 = "claude-7@h" },
			capable = cap("grok"),
		})
		t.expect(d.action).toBe("wait")
		t.expect(has(d.why, "R0090 is held by claude-7@h")).toBe(true)
		t.expect(has(d.why, work.WAITING .. "code-review/normal")).toBe(true)
		t.expect(string.sub(d.why, 1, #work.WAITING) ~= work.WAITING).toBe(true) -- it clears by itself: not the stop
	end)

	it("ready hands out the raft only to a CLI that can build it (finding 7)", function()
		local r = raft("R0200", { issues = { "c0200" } })
		local issues =
			{ issue("c0200", { raft = "R0200", status = "prepared", designReady = true, sized = true }) }
		local claude = work.decide({ rafts = { r }, issues = issues, session = "s", capable = cap("claude") })
		t.expect(claude.action).toBe("ready")
		local kimi = work.decide({ rafts = { r }, issues = issues, session = "s", capable = cap("kimi") })
		t.expect(kimi.action).toBe("wait") -- code/normal is light, which kimi lacks
		t.expect(has(kimi.why, "code/normal (light: claude, grok)")).toBe(true)
	end)

	it("the whole action-to-activity map (findings 5, 6, 7)", function()
		local function of(action: string, raftId: string, ticket: string, rafts: { work.RaftFact }?)
			local d: work.Decision = { raft = raftId, layer = "", ticket = ticket, action = action, why = "" }
			local activity = work.activityOf({ rafts = rafts or {}, issues = {} }, d)
			return activity
		end
		local R = raft("R0001", { where = "active" })
		local function states(field: string, value: string, action: string): string?
			local r = raft("R0001", { where = "active" });
			(r :: any)[field] = value
			return of(action, "R0001", "", { r })
		end
		t.expect(of("draft", "", "c1")).toBe("design")
		t.expect(of("rafting", "", "c1")).toBe("raft")
		t.expect(of("implement", "R0001", "c1", { R })).toBe("code")
		t.expect(of("finish", "R0001", "c1", { R })).toBe("code")
		t.expect(of("trace", "R0001", "", { R })).toBe("code")
		t.expect(of("review", "R0001", "", { R })).toBe("code-review")
		t.expect(of("final-review", "R0001", "", { R })).toBe("final-review")
		t.expect(of("ready", "R0001", "", { R })).toBe("code")
		t.expect(of("ready", "", "c1")).toBe("code")
		t.expect(of("fix", "R0001", "", { R })).toBe("raft")
		t.expect(of("fix", "R0001", "c1", { R })).toBe("design")
		t.expect(of("fix", "", "c1")).toBe(nil)
		for _, mechanical in { "restack", "resume", "release", "done", "wait", "none", "end" } do
			t.expect(of(mechanical, "R0001", "", { R })).toBe(nil)
		end
		for _, state in { "open", "malformed", "rule" } do
			t.expect(states("codeReview", state, "review")).toBe("code")
			t.expect(states("finalReview", state, "final-review")).toBe("code")
		end
		t.expect(states("codeReview", "due", "review")).toBe("code-review")
		t.expect(states("finalReview", "due", "final-review")).toBe("final-review")
	end)

	it("a member that is new and needs z-design waits for a CLI with design (finding 5)", function()
		local r = raft("R0200", { issues = { "c0200" }, designReady = false })
		local d = work.decide({
			asked = "R0200",
			rafts = { r },
			issues = { issue("c0200", { raft = "R0200", status = "new", level = "risky" }) },
			capable = cap("kimi"), -- design/risky is heavy: kimi has it
		})
		t.expect(d.action).toBe("fix")
		local g = work.decide({
			asked = "R0200",
			rafts = { r },
			issues = { issue("c0200", { raft = "R0200", status = "new", level = "risky" }) },
			capable = cap("grok"),
		})
		t.expect(g.action).toBe("wait")
		t.expect(has(g.why, "design/risky (heavy: claude, kimi)")).toBe(true)
	end)

	it(
		"f0421: a worker whose CLI runs several models is filtered by the model its session runs (ZN_MODEL)",
		function()
			local root = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			local function layersOf(): { any }?
				return root
			end
			-- no model named: nothing is handed over, and the one plain line says what to set
			local bare = workerlive.capability({ ZN_CLI = "agy" }, layersOf)
			t.expect(bare ~= nil).toBe(true)
			t.expect(has(bare.lacks("code", "normal"), "agy runs more than one model")).toBe(true)
			t.expect(has(bare.lacks("code", "normal"), "ask the person to start agy with ZN_MODEL"))
				.toBe(true)
			local neon =
				workerlive.capability({ ZN_CLI = "agy", ZN_MODEL = "gemini-4-neon-medium" }, layersOf)
			t.expect(neon.lacks("code", "normal")).toBe(nil)
			t.expect(has(neon.lacks("code-review", "normal"), "agy running gemini-4-argon-high")).toBe(true)
			local argon =
				workerlive.capability({ ZN_CLI = "agy", ZN_MODEL = "gemini-4-argon-high" }, layersOf)
			t.expect(argon.lacks("code-review", "normal")).toBe(nil)
			t.expect(argon.lacks("code", "normal") ~= nil).toBe(true)
			-- `work next` hands the neon session no review, and the argon session one
			local facts = {
				asked = "R0100",
				rafts = { reviewable("R0100", "c0100") },
				issues = { issue("c0100", { status = "active", raft = "R0100" }) },
			}
			facts.capable = neon
			t.expect(work.decide(facts).action).toBe("wait")
			facts.capable = argon
			t.expect(work.decide(facts).action).toBe("review")
			-- a CLI with one model, and claude, ignore the variable
			local grok = workerlive.capability({ ZN_CLI = "grok", ZN_MODEL = "anything" }, layersOf)
			t.expect(grok.lacks("code", "normal")).toBe(nil)
			local claude = workerlive.capability({ ZN_CLI = "claude", ZN_MODEL = "anything" }, layersOf)
			t.expect(claude.lacks("code-review", "normal")).toBe(nil)
			-- the registration's list: the same filter, or the problem and no list
			local can, problem = workerlive.canFor("agy", { ZN_MODEL = "gemini-4-neon-medium" }, layersOf)
			t.expect(table.concat(can, ",")).toBe("design/normal,raft/normal,code/normal")
			t.expect(problem).toBe(nil)
			local none, why = workerlive.canFor("agy", {}, layersOf)
			t.expect(#none).toBe(0)
			t.expect(has(why, "ask the person to start agy with ZN_MODEL")).toBe(true)
			local kimi = workerlive.canFor("kimi", { ZN_MODEL = "x" }, layersOf)
			t.expect(#kimi > 0).toBe(true)
		end
	)

	it(
		"f0421 slice 3: a session's model is declared by the person, sent at registration and marked (declared)",
		function()
			local root = { models.parse(fs.readFile(`{TOP}/.models.toml`), ".models.toml") }
			local function layersOf(): { any }?
				return root
			end
			-- the registration's list comes with the session's model
			local can, problem, session =
				workerlive.canFor("agy", { ZN_MODEL = "gemini-4-neon-medium" }, layersOf)
			t.expect(#can > 0).toBe(true)
			t.expect(problem).toBe(nil)
			t.expect(session).toBe("gemini-4-neon-medium")
			local _, _, none = workerlive.canFor("kimi", { ZN_MODEL = "x" }, layersOf)
			t.expect(none).toBe(nil) -- one model: nothing is declared
			-- auto names no model
			local auto, why = workerlive.canFor("agy", { ZN_MODEL = "auto" }, layersOf)
			t.expect(#auto).toBe(0)
			t.expect(has(why, "ZN_MODEL auto lets agy pick its own model")).toBe(true)
			-- the registration's arguments: a declared model is sent, marked, and a CLI that declares none sends no model
			t.expect(
				workerlive.registerArgs(
					{ cli = "agy", pid = 4242 },
					{ "code/normal" },
					"gemini-4-neon-medium"
				)
			)
				.toEqual({
					"--cli",
					"agy",
					"--pid",
					"4242",
					"--mode",
					"session",
					"--can",
					"code/normal",
					"--model",
					"gemini-4-neon-medium (declared)",
				})
			t.expect(workerlive.registerArgs({ cli = "claude", pid = 7 }, {}, nil))
				.toEqual({ "--cli", "claude", "--pid", "7", "--mode", "session" })
			-- a row recorded on the session's declared model carries the mark; another model, or none named, does not
			local modelcmd = require("@znile/engine/modelcmd")
			local env: { [string]: string? } = { ZN_CLI = "agy", ZN_MODEL = "gemini-4-neon-medium" }
			t.expect(modelcmd.declaredNote("gemini-4-neon-medium", env)).toBe("(declared)")
			t.expect(modelcmd.declaredNote("Gemini-4-Neon-Medium", env)).toBe("(declared)")
			t.expect(modelcmd.declaredNote("gemini-4-neon-high", env)).toBe(nil)
			t.expect(modelcmd.declaredNote("gemini-4-neon-medium", { ZN_CLI = "agy" })).toBe(nil)
			t.expect(modelcmd.declaredNote(nil, env)).toBe(nil)
			-- claude and grok sessions name their model in a session file the engine reads: never declared
			t.expect(
				modelcmd.declaredNote("claude-opus-5-5", { ZN_CLI = "claude", ZN_MODEL = "claude-opus-5-5" })
			)
				.toBe(nil)
			t.expect(modelcmd.declaredNote("grok-4.7", { ZN_CLI = "grok", ZN_MODEL = "grok-4.7" })).toBe(nil)
		end
	)

	it("workerlive.capability fails open with a reason, and never raises (findings 2, 8)", function()
		local function layersOf(): { any }?
			return LAYERS
		end
		local cap1, why1 = workerlive.capability({ ZN_CLI = "claud" }, layersOf)
		t.expect(cap1).toBe(nil)
		t.expect(has(why1, "claud is not a supported CLI (claude, grok, agent, kimi, agy)")).toBe(true)
		local _, why2 =
			workerlive.capability({ CLAUDE_CODE_SESSION_ID = "a", GROK_SESSION_ID = "b" }, layersOf)
		t.expect(has(why2, "both set")).toBe(true)
		local _, why3 = workerlive.capability({}, layersOf)
		t.expect(has(why3, "no CLI")).toBe(true)
		local _, why4 = workerlive.capability({ ZN_CLI = "grok" }, function()
			return nil
		end)
		t.expect(has(why4, "cannot be read")).toBe(true)
		-- a file that parses but fails the merge: no filter, a reason, no error
		local bad = { models.parse('[activities.code]\nmax_tokens = 1\nall = "light"\n', ".models.toml") }
		local cap5, why5 = workerlive.capability({ ZN_CLI = "grok" }, function(): { any }?
			return bad
		end)
		t.expect(cap5).toBe(nil)
		t.expect(has(why5, "activities.idea has no setting for all")).toBe(true)
		-- a file that sets no role and no activity (a repository with rounds only) filters nothing: no worker is stranded
		local bare = { models.parse("[rounds]\ncode = { risky = 4 }\n", ".models.toml") }
		local cap7, why7 = workerlive.capability({ ZN_CLI = "claude" }, function(): { any }?
			return bare
		end)
		t.expect(cap7).toBe(nil)
		t.expect(has(why7, "sets any role or activity")).toBe(true)
		-- under dispatch it is silent
		local cap6, why6 = workerlive.capability({ ZN_CLI = "grok", ZN_DISPATCH = "1" }, layersOf)
		t.expect(cap6).toBe(nil)
		t.expect(why6).toBe(nil)
	end)

	it("workerlive.decide filters by the env's CLI and never under dispatch (M3b, M3c)", function()
		local before = process.env.ZN_LIVE
		process.env.ZN_LIVE = "off" -- no live layer: only the filter is under test
		local function layersOf(): { any }?
			return LAYERS
		end
		local seen: { any } = {}
		local lib = {
			decide = function(input: any): any
				table.insert(seen, input.capable)
				return { raft = "", layer = "", ticket = "", action = "none", why = "" }
			end,
		}
		workerlive.decide(lib, {}, { ZN_CLI = "grok" }, layersOf)
		t.expect(seen[1] ~= nil and seen[1].cli == "grok").toBe(true)
		workerlive.decide(lib, {}, { ZN_CLI = "grok", ZN_DISPATCH = "1" }, layersOf)
		t.expect(seen[2]).toBe(nil)
		workerlive.decide(lib, {}, {}, layersOf)
		t.expect(seen[3]).toBe(nil)
		-- the real library, end to end: the review grok lacks is a wait
		local d = workerlive.decide(work, {
			asked = "R0100",
			rafts = { reviewable("R0100", "c0100") },
			issues = { issue("c0100", { status = "active", raft = "R0100" }) },
		}, { ZN_CLI = "grok" }, layersOf)
		t.expect(d.action).toBe("wait")
		local ok = workerlive.decide(work, {
			asked = "R0100",
			rafts = { reviewable("R0100", "c0100") },
			issues = { issue("c0100", { status = "active", raft = "R0100" }) },
		}, { ZN_CLI = "claude" }, layersOf)
		t.expect(ok.action).toBe("review")
		process.env.ZN_LIVE = before
	end)

	it("workerlive reads the models file from origin/main", function()
		local layers = workerlive.layersAtMain()
		t.expect(layers ~= nil).toBe(true)
		t.expect(#models.canList(layers :: any, "claude") > 0).toBe(true)
	end)

	it(
		"work status: the level of the raft counts, backlog rafts do not, an unknown can is anything (finding 9)",
		function()
			local need = function(a: string, l: "easy" | "normal" | "risky"): string
				return models.waiting(LAYERS, a, l)
			end
			local kimi = { id = "kimi-1@h", cli = "kimi", can = models.canList(LAYERS, "kimi") }
			local normal = reviewable("R0100", "c0100")
			local risky = reviewable("R0300", "c0300", { level = "risky" })
			t.expect(#workcan.waitingFor({ normal }, { kimi }, need)).toBe(0)
			local lines = workcan.waitingFor({ risky }, { kimi }, need)
			t.expect(lines[1]).toBe("R0300: waiting for a worker with code-review/risky (ultra: claude)")
			local backlog = raft("R0200", { issues = { "c0200" } })
			t.expect(#workcan.waitingFor({ backlog }, { kimi }, need)).toBe(0)
			local unknown = { id = "grok-2@h", cli = "grok", can = {} }
			t.expect(#workcan.waitingFor({ risky }, { kimi, unknown }, need)).toBe(0)
			local viaLines = workerlive.waitingLines({ risky }, { kimi }, function(): { any }?
				return LAYERS
			end)
			t.expect(viaLines[1]).toBe(lines[1])
		end
	)

	it("the skill's wait stop applies named or unnamed (finding 3)", function()
		local skill = fs.readFile(`{TOP}/z-nile/skills/z-work/SKILL.md`)
		t.expect(has(skill, "whether or not a raft was named")).toBe(true)
	end)
end)
