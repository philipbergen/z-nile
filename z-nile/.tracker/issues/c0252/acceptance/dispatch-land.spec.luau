--!strict
-- c0252 AC5 and AC6: the chain's rule for an active raft (dispatch.next, pure) and the settings that arm it
-- (models: the `run` gate and merge_attempts). Facts are built from a base and one change at a time.
local dispatch = require("@znile/engine/dispatch")
local models = require("@znile/engine/models")
local t = require("@tests/lib/t")

local TIP = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

local function facts(over: { [string]: any }): dispatch.Facts
	local base: { [string]: any } = {
		id = "R0010",
		folder = "pickman/.tracker/rafts/active/R0010",
		root = "pickman/.tracker",
		kind = "raft",
		where = "active",
		status = "active",
		design = "ready",
		raft = "",
		ownClaim = false,
		localRaft = "",
		pr = nil,
		questions = false,
		blocked = nil,
		openHuman = {},
		last = { step = "z-run", outcome = "ok" },
		uncovered = {},
		autoMerge = { "run" },
		description = nil,
		layered = true,
		land = nil,
		blockRequest = nil,
	}
	for k, v in over do
		base[k] = v
	end
	return base :: any
end

local function land(action: string, over: { [string]: any }?): any
	local l: { [string]: any } = {
		action = action,
		through = nil,
		tip = TIP,
		lines = { "ci-pending (wait): CI is still running on c0020's head: static" },
		problems = {},
		reason = nil,
		layer = nil,
		tries = 0,
		sig = "ci-pending@aaaa",
	}
	local changes: { [string]: any } = over or {}
	for k, v in changes do
		l[k] = v
	end
	return l
end

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

return t.spec("c0252 the chain lands a green stack", function(it)
	it(
		"AC5: a finished layered raft whose checks pass is landed, through the layer the verdict names",
		function()
			local a: any = dispatch.next(facts({ land = land("land") }))
			t.expect(a.kind).toBe("land")
			t.expect(a.target).toBe("R0010")
			t.expect(a.tip).toBe(TIP)
			t.expect(a.through).toBe(nil)
			local part: any = dispatch.next(facts({ land = land("land", { through = "c0010" }) }))
			t.expect(part.through).toBe("c0010")
		end
	)

	it(
		"AC5: with run left out of auto_merge the chain stops at the gate and names the command, and lands nothing",
		function()
			local a = dispatch.next(facts({ land = land("land"), autoMerge = { "prep", "raft" } }))
			t.expect(a.kind).toBe("stop")
			t.expect(a.code).toBe(dispatch.EXIT.gate)
			t.expect(has(a.why or "", "./zn done R0010")).toBe(true)
			t.expect(has(a.why or "", "auto_merge")).toBe(true)
		end
	)

	it(
		"AC5: a wait stops at the gate with the reasons, a fixable problem runs the worker again as a counted try",
		function()
			local w = dispatch.next(facts({ land = land("wait") }))
			t.expect(w.kind).toBe("stop")
			t.expect(w.code).toBe(dispatch.EXIT.gate)
			t.expect(has(w.why or "", "ci-pending")).toBe(true)
			local r: any =
				dispatch.next(facts({ land = land("redo", { lines = { "trace-stale (redo): x" } }) }))
			t.expect(r.kind).toBe("step")
			t.expect(r.step).toBe("z-run")
			t.expect(r.redo).toBe(true)
			-- no verdict is due before the run step has ended: the worker runs, not a landing
			local first: any = dispatch.next(facts({ last = nil }))
			t.expect(first.kind).toBe("step")
			t.expect(first.step).toBe("z-run")
			t.expect(first.redo).toBe(nil)
		end
	)

	it(
		"AC5: a verdict of block files a block with its reason and Layer, and a blocked raft stops first",
		function()
			local b: any =
				dispatch.next(facts({ land = land("block", { reason = "red-gate", layer = "c0020" }) }))
			t.expect(b.kind).toBe("block")
			t.expect(b.reason).toBe("red-gate")
			t.expect(b.layer).toBe("c0020")
			local stopped = dispatch.next(facts({ status = "blocked", blocked = "red-gate" }))
			t.expect(stopped.kind).toBe("stop")
			t.expect(stopped.code).toBe(dispatch.EXIT.user)
		end
	)

	it(
		"AC5: a block request lands the green layers below first, then files the block; a red prefix lands nothing",
		function()
			local req = { reason = "design-gap", layer = "c0030" }
			local first: any = dispatch.next(facts({
				blockRequest = req,
				land = land("land", { through = "c0020" }),
				last = { step = "z-run", outcome = "ok" },
			}))
			t.expect(first.kind).toBe("land")
			t.expect(first.through).toBe("c0020")
			-- after that landing nothing is below: the block is filed
			local second: any = dispatch.next(facts({ blockRequest = req, land = nil }))
			t.expect(second.kind).toBe("block")
			t.expect(second.reason).toBe("design-gap")
			t.expect(second.layer).toBe("c0030")
			-- a prefix that is not green is not landed (no regression through a block)
			local red: any =
				dispatch.next(facts({ blockRequest = req, land = land("redo", { through = "c0020" }) }))
			t.expect(red.kind).toBe("block")
			-- a prefix whose CI still runs waits at the gate and keeps the request: Q3 says the green layers land, so it
			-- does not block now
			local waiting: any =
				dispatch.next(facts({ blockRequest = req, land = land("wait", { through = "c0020" }) }))
			t.expect(waiting.kind).toBe("stop")
			t.expect(waiting.code).toBe(dispatch.EXIT.gate)
			t.expect(has(waiting.why or "", "before it is filed")).toBe(true)
			-- without run in auto_merge the prefix waits for a person
			local human = dispatch.next(
				facts({ blockRequest = req, land = land("land", { through = "c0020" }), autoMerge = {} })
			)
			t.expect(human.kind).toBe("stop")
			t.expect(human.code).toBe(dispatch.EXIT.gate)
		end
	)

	it(
		"AC5: an old single-branch raft keeps its pull request and the human's merge, and the lookup of a layered raft is not stale",
		function()
			local pr: dispatch.Pr = {
				number = 7,
				state = "OPEN",
				draft = false,
				green = true,
				mergeable = true,
				head = "abc",
				judged = nil,
				judgedMain = nil,
				itemIds = nil,
			}
			local legacy = dispatch.next(facts({ layered = false, pr = pr, land = nil }))
			t.expect(legacy.kind).toBe("stop")
			t.expect(legacy.code).toBe(dispatch.EXIT.gate)
			t.expect(has(legacy.why or "", "human's to merge")).toBe(true)
			-- a layered raft ignores the one-branch pull request name entirely
			local layered: any = dispatch.next(facts({ layered = true, pr = pr, land = land("land") }))
			t.expect(layered.kind).toBe("land")
			-- the old stop "z-run ended but the PR is still a draft" is for an old raft only
			local draft: dispatch.Pr = table.clone(pr)
			draft.draft = true
			local old = dispatch.next(facts({ layered = false, pr = draft }))
			t.expect(old.kind).toBe("stop")
			t.expect(has(old.why or "", "still a draft")).toBe(true)
			local newer: any = dispatch.next(facts({ layered = true, pr = nil, land = land("land") }))
			t.expect(newer.kind).toBe("land")
		end
	)

	it(
		"AC5: a worker's block request on a raft with no layer branches is filed, not stopped as a run that left a draft",
		function()
			local filed: any = dispatch.next(
				facts({ layered = false, pr = nil, blockRequest = { reason = "red-gate" }, land = nil })
			)
			t.expect(filed.kind).toBe("block")
			t.expect(filed.reason).toBe("red-gate")
			t.expect(filed.layer).toBe(nil)
			-- without a request the same facts are the old raft's run that ended with no pull request
			local stopped = dispatch.next(facts({ layered = false, pr = nil, land = nil }))
			t.expect(stopped.kind).toBe("stop")
			t.expect(stopped.code).toBe(dispatch.EXIT.failure)
		end
	)

	it(
		"AC6: the landing and the block are script steps of the raft's own worktree, with the dispatcher's environment",
		function()
			local landStep = dispatch.step("z-land")
			t.expect(landStep.kind).toBe("script")
			t.expect(landStep.where).toBe("run")
			t.expect(dispatch.scriptArgv("z-land", "R0010", { "--through", "c0010" })).toEqual({
				"./zn",
				"done",
				"R0010",
				"--through",
				"c0010",
			})
			local gateStep = dispatch.step("z-gate")
			t.expect(gateStep.kind).toBe("script")
			t.expect(gateStep.where).toBe("run")
			t.expect(dispatch.scriptArgv("z-gate", "R0010", { "--through", "c0010" })).toEqual({
				"./zn",
				"land-gate",
				"R0010",
				"--through",
				"c0010",
			})
			t.expect(dispatch.scriptArgv("z-block", "R0010", { "red-gate", "--layer", "c0020" })).toEqual({
				"./zn",
				"block",
				"R0010",
				"red-gate",
				"--layer",
				"c0020",
			})
		end
	)

	it(
		"AC6: auto_merge takes run, still refuses anything else, and merge_retries is a whole number defaulting to 2",
		function()
			t.expect(table.find(models.GATES, "run") ~= nil).toBe(true)
			local ok, layer = pcall(
				models.parse,
				'[dispatch]\nauto_merge = ["prep", "raft", "run"]\nmerge_retries = 3\n',
				"t.toml"
			)
			t.expect(ok).toBe(true)
			t.expect((layer :: any).settings.mergeRetries).toBe(3)
			t.expect(models.mergeRetries({ layer :: any })).toBe(3)
			t.expect(models.mergeRetries({})).toBe(2)
			t.expect(models.MERGE_RERUN_CAP).toBe(10)
			local bad, why = pcall(models.parse, '[dispatch]\nauto_merge = ["merge"]\n', "t.toml")
			t.expect(bad).toBe(false)
			t.expect(has(tostring(why), "dispatch.auto_merge names merge")).toBe(true)
			local zero, why0 = pcall(models.parse, "[dispatch]\nmerge_retries = 0\n", "t.toml")
			t.expect(zero).toBe(false)
			t.expect(has(tostring(why0), "merge_retries")).toBe(true)
			local old, why1 = pcall(models.parse, "[dispatch]\nmerge_attempts = 2\n", "t.toml")
			t.expect(old).toBe(false)
			t.expect(has(tostring(why1), "not a setting")).toBe(true)
		end
	)

	it(
		"AC5: a rerun worker is told which checks it runs again for, and a first run is told nothing of the kind",
		function()
			local function prompt(rerun: { string }?): string
				return dispatch.prompt({
					step = "z-run",
					id = "R0010",
					mode = nil,
					skillPath = "z-nile/skills/z-run/SKILL.md",
					worktree = "/w",
					stateDir = "/state",
					promptPath = "/p",
					streamWorktree = nil,
					description = nil,
					project = nil,
					exchange = nil,
					exchangeAsker = nil,
					exchangeNoReply = nil,
					exchangeUnknownReply = nil,
					exchangeLastStep = nil,
					parentExchange = nil,
					parentStateDir = nil,
					rerun = rerun,
				} :: any)
			end
			local again = prompt({
				"ci-failed (redo): CI failed on c0020's head: static",
				"trace-stale (redo): row Commit is stale",
			})
			t.expect(
				has(
					again,
					"You are running again because the dispatcher's checks before landing R0010 failed"
				)
			)
				.toBe(true)
			t.expect(has(again, "ci-failed (redo): CI failed on c0020's head: static")).toBe(true)
			t.expect(has(again, "trace-stale (redo)")).toBe(true)
			t.expect(has(again, "./zn land-check R0010")).toBe(true)
			t.expect(has(prompt(nil), "running again")).toBe(false)
			t.expect(has(prompt({}), "running again")).toBe(false)
		end
	)
	-- c0251's frontier floor (user, 2026-11-16): the dispatcher runs one extra review round on a frontier model
	it(
		"AC23: a verdict of review runs the extra frontier round (through the layer the verdict names), and stops at the gate when run is left out of auto_merge",
		function()
			local whole: any = dispatch.next(facts({
				land = land("review", {
					lines = {
						"no-frontier-review (review): no review of the landed code ran on a frontier model",
					},
				}),
			}))
			t.expect(whole.kind).toBe("review")
			t.expect(whole.target).toBe("R0010")
			t.expect(whole.through).toBe(nil)
			t.expect(whole.tip).toBe(TIP)
			local prefix: any = dispatch.next(facts({ land = land("review", { through = "c0010" }) }))
			t.expect(prefix.kind).toBe("review")
			t.expect(prefix.through).toBe("c0010")
			-- the round is the dispatcher's own work toward a landing: with run left out it is a person's, named exactly
			local off: any = dispatch.next(
				facts({ land = land("review", { through = "c0010" }), autoMerge = { "prep", "raft" } })
			)
			t.expect(off.kind).toBe("stop")
			t.expect(off.code).toBe(dispatch.EXIT.gate)
			t.expect(has(off.why, "./zn dispatch zz-review R0010 --mode final --frontier --through c0010"))
				.toBe(true)
			t.expect(has(off.why, "auto_merge")).toBe(true)
		end
	)

	it(
		"AC23: a block request whose green layers below lack the frontier review gets the round through the prefix before they land, and before the block is filed",
		function()
			local req = { reason = "review-exhausted", layer = "c0020", tip = TIP }
			local round: any = dispatch.next(facts({
				blockRequest = req,
				land = land("review", { through = "c0010" }),
			}))
			t.expect(round.kind).toBe("review")
			t.expect(round.through).toBe("c0010")
			-- with the floor met the prefix lands as before, and with no verdict the block is filed
			local landed: any =
				dispatch.next(facts({ blockRequest = req, land = land("land", { through = "c0010" }) }))
			t.expect(landed.kind).toBe("land")
			-- a blocked verdict on the prefix (the round ran, the floor is unmet) is filed, not rerun
			local filed: any = dispatch.next(facts({
				blockRequest = req,
				land = land("block", { through = "c0010", reason = "needs-decision" }),
			}))
			t.expect(filed.kind).toBe("block")
		end
	)

	it(
		"AC23: a verdict that blocks the whole stack after the round is filed under needs-decision, never a second round",
		function()
			local b: any =
				dispatch.next(facts({ land = land("block", { reason = "needs-decision", layer = nil }) }))
			t.expect(b.kind).toBe("block")
			t.expect(b.reason).toBe("needs-decision")
		end
	)
end)
