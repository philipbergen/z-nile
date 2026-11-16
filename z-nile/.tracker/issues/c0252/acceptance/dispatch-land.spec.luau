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
	}
	for k, v in over or {} do
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
		"AC6: the landing and the block are script steps of the raft's own worktree, with the dispatcher's environment",
		function()
			local land = dispatch.step("z-land")
			t.expect(land.kind).toBe("script")
			t.expect(land.where).toBe("run")
			t.expect(dispatch.scriptArgv("z-land", "R0010", { "--through", "c0010" })).toEqual({
				"./zn",
				"done",
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
		"AC6: auto_merge takes run, still refuses anything else, and merge_attempts is a whole number defaulting to 2",
		function()
			t.expect(table.find(models.GATES, "run") ~= nil).toBe(true)
			local ok, layer = pcall(
				models.parse,
				'[dispatch]\nauto_merge = ["prep", "raft", "run"]\nmerge_attempts = 3\n',
				"t.toml"
			)
			t.expect(ok).toBe(true)
			t.expect((layer :: any).settings.mergeAttempts).toBe(3)
			t.expect(models.mergeAttempts({ layer :: any })).toBe(3)
			t.expect(models.mergeAttempts({})).toBe(2)
			local bad, why = pcall(models.parse, '[dispatch]\nauto_merge = ["merge"]\n', "t.toml")
			t.expect(bad).toBe(false)
			t.expect(has(tostring(why), "dispatch.auto_merge names merge")).toBe(true)
			local zero, why0 = pcall(models.parse, "[dispatch]\nmerge_attempts = 0\n", "t.toml")
			t.expect(zero).toBe(false)
			t.expect(has(tostring(why0), "merge_attempts")).toBe(true)
		end
	)
end)
