--!strict
-- c0261: the activity a dispatched step runs: a review round in its mode, the final round with `--final`, a stream never
-- final, the raft, idea and full-force reviews always final; the waiting step and its poll; the chain waits for green
-- CI at a gate once per head. Pure: engine/dispatch.
local dispatch = require("@znile/engine/dispatch")
local t = require("@tests/lib/t")

local d = dispatch :: any -- the API this issue adds, reached through `any` until the code exists (promote-check)

local function errorOf(f: () -> ()): string
	local ok: boolean, e: any = pcall(f)
	if ok then
		error("expected an error", 2)
	end
	return tostring(e)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0261 dispatcher activities", function(it)
	it("a design or code review round is its own activity, and --final names the final round's (AC3)", function()
		t.expect(d.activityOf("zz-review", "design", false)).toBe("zz-review-design")
		t.expect(d.activityOf("zz-review", "design", true)).toBe("zz-review-design-final")
		t.expect(d.activityOf("zz-review", "code", false)).toBe("zz-review-code")
		t.expect(d.activityOf("zz-review", "code", true)).toBe("zz-review-code-final")
	end)

	it("the raft review is always final, the stream review never (AC3)", function()
		t.expect(d.activityOf("zz-review", "raft", false)).toBe("zz-review-raft")
		t.expect(d.activityOf("zz-review", "raft", true)).toBe("zz-review-raft")
		t.expect(d.activityOf("zz-review", "stream", false)).toBe("zz-review-stream")
		t.expect(has(errorOf(function()
			d.activityOf("zz-review", "stream", true)
		end), "stream")).toBe(true)
	end)

	it("every review mode names its activity; the idea and full-force reviews are final ones whenever they exist (AC3)", function()
		for mode, entry in dispatch.REVIEW_MODES do
			local e: any = entry
			t.expect(`{mode}: {type(e.activity)}`).toBe(`{mode}: string`)
		end
		for _, mode in { "idea", "final" } do
			if dispatch.REVIEW_MODES[mode] then
				local a: string = d.activityOf("zz-review", mode, false)
				t.expect(d.activityOf("zz-review", mode, true)).toBe(a)
				t.expect(a).toBe(`zz-review-{mode}`)
			end
		end
	end)

	it("the other commands are their own activity (AC3)", function()
		for _, step in { "z-ticket", "z-design", "z-raft", "z-run", "z-wait" } do
			t.expect(d.activityOf(step, nil, false)).toBe(step)
		end
	end)

	it("z-wait is a model step; its poll is a loop with its own clock and three outcomes (AC4)", function()
		local s = dispatch.STEPS["z-wait"]
		t.expect(s ~= nil and s.kind == "model").toBe(true)
		for _, what in { "checks", "merged" } do
			local c: string = d.waitCommand(what, 42, 600, 30)
			t.expect(has(c, "./zn run --time 660 --")).toBe(true) -- deadline + one sleep + a margin for gh itself
			t.expect(has(c, "end=$((SECONDS+600))")).toBe(true)
			t.expect(has(c, "[ $((SECONDS+30)) -lt $end ] || break; sleep 30")).toBe(true) -- sleeps only if the next poll fits
			t.expect(has(c, "exit 0")).toBe(true)
			t.expect(has(c, "exit 2")).toBe(true)
			t.expect(has(c, "exit 3")).toBe(true)
		end
		t.expect(has(d.waitCommand("checks", 42, 600, 30), "gh pr checks 42")).toBe(true)
		t.expect(has(d.waitCommand("merged", 42, 600, 30), "gh pr view 42")).toBe(true)
		t.expect(has(d.waitCommand("merged", 42, 600, 30), "CLOSED")).toBe(true)
		t.expect(has(errorOf(function()
			d.waitCommand("tomorrow", 42, 600)
		end), "checks, mergeable, merged")).toBe(true)
		t.expect(has(errorOf(function()
			d.waitCommand("checks", 42, 0)
		end), "seconds")).toBe(true)
	end)

	it("the wait prompt runs the one command with a tool timeout, again on 3, stops on 0 or 2, and does nothing else (AC4)", function()
		local p: string = d.waitPrompt("./zn run --time 660 -- true", 6)
		t.expect(has(p, "./zn run --time 660 -- true")).toBe(true)
		t.expect(has(p, "tool timeout of 660000 ms")).toBe(true)
		t.expect(has(p, "exit code 3")).toBe(true)
		t.expect(has(p, "at most 6 times")).toBe(true)
		t.expect(has(p, "exit code 0 or 2, or with any other exit code")).toBe(true)
		t.expect(has(p, "Do nothing else")).toBe(true)
	end)

	local function pr(over: { [string]: any }?): any
		local p: { [string]: any } = { number = 7, state = "OPEN", draft = false, green = true, mergeable = true, head = "abc123" }
		local extra: { [string]: any } = if over then over else {}
		for k, v in extra do
			p[k] = v
		end
		return p
	end
	local function facts(over: { [string]: any }): any
		local f: { [string]: any } = {
			id = "c0010", folder = "pickman/.tracker/issues/c0010", root = "tracker", kind = "issue", where = "backlog",
			status = "preparing", design = "ready", raft = "", ownClaim = true, localRaft = "", pr = pr(), questions = false,
			last = nil, uncovered = {}, autoMerge = { "prep", "raft" }, description = nil, waitedHead = nil,
		}
		for k, v in over do
			f[k] = v
		end
		return f
	end

	it("a gate that only waits for green CI starts the wait once per head, then stops as before (AC5)", function()
		local a: any = dispatch.next(facts({ pr = pr({ green = false }) }))
		t.expect(a.kind).toBe("step")
		t.expect(a.step).toBe("z-wait")
		t.expect(a.waitFor).toBe("checks")
		t.expect(a.pr).toBe(7)
		local again: any = dispatch.next(facts({ pr = pr({ green = false }), waitedHead = "abc123" }))
		t.expect(again.kind).toBe("stop")
		t.expect(again.code).toBe(4)
		t.expect(has(again.why, "waits for green CI")).toBe(true)
		-- a new head is a new wait
		local moved: any = dispatch.next(facts({ pr = pr({ green = false, head = "def456" }), waitedHead = "abc123" }))
		t.expect(moved.step).toBe("z-wait")
	end)

	it("no wait for a draft, a human's merge, a red-free ready PR or the run gate (AC5)", function()
		t.expect((dispatch.next(facts({ pr = pr({ green = false, draft = true }) })) :: any).kind).toBe("stop")
		t.expect((dispatch.next(facts({ pr = pr({ green = false }), autoMerge = {} })) :: any).kind).toBe("stop")
		t.expect((dispatch.next(facts({ pr = pr() })) :: any).kind).toBe("merge")
		local run = facts({ kind = "raft", where = "active", status = "active", pr = pr({ green = false }) })
		t.expect((dispatch.next(run) :: any).kind).toBe("stop")
	end)

	it("the wait step's prompt is the poll and nothing else: no skill to read, no lessons, no spend line (AC4)", function()
		local p: string = dispatch.prompt({
			step = "z-wait", id = "c0010", skillPath = "z-nile/skills/z-wait/SKILL.md", worktree = "/w", stateDir = "/s",
			waitCommand = "./zn run --time 660 -- true", waitTimes = 6,
		} :: any)
		t.expect(has(p, "./zn run --time 660 -- true")).toBe(true)
		for _, w in { "SKILL.md", "./zn lessons", "Record your own spend" } do
			t.expect(has(p, w)).toBe(false)
		end
	end)

	it("a review mode with no activity of its own is zz-review-<mode>, final when it is a final review by nature (AC3)", function()
		local modes: any = dispatch.REVIEW_MODES
		local had = modes.idea
		modes.idea = { lessons = "design", phase = "design-review" }
		local ok, a1, a2 = pcall(function()
			return d.activityOf("zz-review", "idea", false), d.activityOf("zz-review", "idea", true)
		end)
		modes.idea = had
		t.expect(ok).toBe(true)
		t.expect(a1).toBe("zz-review-idea")
		t.expect(a2).toBe("zz-review-idea")
		modes.novel = { lessons = "design", phase = "design-review" }
		local never = errorOf(function()
			d.activityOf("zz-review", "novel", true)
		end)
		modes.novel = nil
		t.expect(has(never, "never final")).toBe(true)
	end)

	it("a gate waits for its checks only when a human has nothing to judge: not for a conflict, a carried change, an unknown head (AC5)", function()
		t.expect((dispatch.next(facts({ pr = pr({ green = false, conflicting = true }) })) :: any).kind).toBe("stop")
		t.expect((dispatch.next(facts({ pr = pr({ green = false, judged = "it carries c0099" }) })) :: any).kind).toBe("stop")
		t.expect((dispatch.next(facts({ pr = pr({ green = false, head = "" }) })) :: any).kind).toBe("stop")
		-- GitHub still computing the merge state (UNKNOWN: mergeable false, conflicting false) waits
		t.expect((dispatch.next(facts({ pr = pr({ green = false, mergeable = false, conflicting = false }) })) :: any).step).toBe("z-wait")
	end)

	it("a green PR whose merge state GitHub is still computing waits for it, and a failed check waits for nothing (AC5)", function()
		local unknown: any = dispatch.next(facts({ pr = pr({ green = true, mergeable = false, mergeState = "UNKNOWN" }) }))
		t.expect(unknown.step).toBe("z-wait")
		t.expect(unknown.waitFor).toBe("mergeable")
		local red: any = dispatch.next(facts({ pr = pr({ green = false, failed = true }) }))
		t.expect(red.kind).toBe("stop")
		t.expect(has(red.why, "waits for green CI")).toBe(true)
		local pending: any = dispatch.next(facts({ pr = pr({ green = false, failed = false }) }))
		t.expect(pending.waitFor).toBe("checks")
	end)

	it("the mergeable poll ends 0 when GitHub says MERGEABLE and 2 when CONFLICTING (AC4)", function()
		local c: string = d.waitCommand("mergeable", 42, 600, 30)
		t.expect(has(c, "gh pr view 42 --json mergeable")).toBe(true)
		t.expect(has(c, "MERGEABLE")).toBe(true)
		t.expect(has(c, "CONFLICTING")).toBe(true)
	end)
end)
