--!strict
-- c0275: the automatic beats' pure rules (z-nile/engine/heartbeat.luau): the one lease rule, the worktree's throttle mark,
-- when a beat is due, when a claim starts its background beater and with what command, which session and worktree end
-- it, and what the dispatcher beats and does with the child's answer. No I/O, no clock.
local heartbeat = require("@znile/engine/heartbeat")
local t = require("@tests/lib/t")

local A = "preparing-quiet-copper-falcon"
local B = "active-brisk-amber-otter"
local NOW = 1800000000

local function beat(stamp: string, epoch: number)
	return { stamp = stamp, epoch = epoch, ref = heartbeat.branch(stamp), sha = `sha-{stamp}-{epoch}` }
end
local function leaseOf(plan: heartbeat.Push): string?
	return if plan.write then plan.write.lease else nil
end
local function facts(over: { [string]: any }?): heartbeat.BeaterFacts
	local base: heartbeat.BeaterFacts = {
		dispatched = false,
		main = false,
		guarded = false,
		running = false,
		held = true,
		specRun = false,
		forced = false,
	}
	for k, v in (over or {}) :: { [string]: any } do
		(base :: any)[k] = v
	end
	return base
end

return t.spec("c0275 automatic beats' rules", function(it)
	it(
		"the lease is the sha this checkout last wrote when it remembers one, else the sha seen, else empty",
		function()
			local seen = { beat(A, NOW) }
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, seen, { [A] = true }, NOW + 300, "mine")))
				.toBe("mine")
			-- the branch is gone: the remembered sha is still the lease, so the push is rejected and the beat learns why
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, {}, { [A] = true }, NOW + 300, "mine")))
				.toBe("mine")
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, seen, { [A] = true }, NOW + 300, nil)))
				.toBe(`sha-{A}-{NOW}`)
			t.expect(leaseOf(heartbeat.plan(A, NOW + 300, {}, { [A] = true }, NOW + 300, nil))).toBe("")
			-- a beat that is not newer writes nothing, whatever it remembers
			t.expect(heartbeat.plan(A, NOW, seen, { [A] = true }, NOW, "mine").write).toBe(nil)
		end
	)

	it("a throttle mark is its stamp, epoch and sha; anything else is no mark", function()
		local m = { stamp = A, epoch = NOW, sha = "0123abc" }
		t.expect(heartbeat.markText(m)).toBe(`{A} {NOW} 0123abc`)
		t.expect(heartbeat.markParse(heartbeat.markText(m))).toEqual(m)
		t.expect(heartbeat.markParse(`{A} {NOW} \n`)).toEqual({ stamp = A, epoch = NOW, sha = "" })
		t.expect(heartbeat.markParse("")).toBe(nil)
		t.expect(heartbeat.markParse(`{A} later 0123abc`)).toBe(nil)
		t.expect(heartbeat.markParse(`{A} {NOW} not-a-sha`)).toBe(nil)
	end)

	it(
		"a beat is due when none was made, a full interval has passed, or the mark is dated in the future",
		function()
			local every = heartbeat.INTERVAL
			t.expect(heartbeat.due(nil, NOW, every)).toBe(true)
			t.expect(heartbeat.due(NOW, NOW + every - 1, every)).toBe(false)
			t.expect(heartbeat.due(NOW, NOW + every, every)).toBe(true)
			t.expect(heartbeat.due(NOW + heartbeat.SKEW, NOW, every)).toBe(false)
			t.expect(heartbeat.due(NOW + heartbeat.SKEW + 1, NOW, every)).toBe(true) -- a clock that went back
		end
	)

	it(
		"a failed attempt advances the mark and keeps the sha it knew; a written beat records its sha",
		function()
			local before = { stamp = A, epoch = NOW, sha = "aaa" }
			t.expect(heartbeat.markAfter(A, NOW + 300, before, nil))
				.toEqual({ stamp = A, epoch = NOW + 300, sha = "aaa" })
			t.expect(heartbeat.markAfter(A, NOW + 300, before, "bbb"))
				.toEqual({ stamp = A, epoch = NOW + 300, sha = "bbb" })
			-- a mark for another stamp lends nothing: a new claim starts with no sha
			t.expect(heartbeat.markAfter(B, NOW + 300, before, nil))
				.toEqual({ stamp = B, epoch = NOW + 300, sha = "" })
			t.expect(heartbeat.leaseOf(before, A)).toBe("aaa")
			t.expect(heartbeat.leaseOf(before, B)).toBe(nil)
			t.expect(heartbeat.leaseOf({ stamp = A, epoch = NOW, sha = "" }, A)).toBe(nil)
			t.expect(heartbeat.leaseOf(nil, A)).toBe(nil)
		end
	)

	it(
		"a claim starts its beater unless the dispatcher beats, it is the main checkout, a check protects it or one runs",
		function()
			t.expect(heartbeat.beaterStart(facts())).toBe(true)
			t.expect(heartbeat.beaterStart(facts({ dispatched = true }))).toBe(false)
			t.expect(heartbeat.beaterStart(facts({ main = true }))).toBe(false)
			t.expect(heartbeat.beaterStart(facts({ guarded = true }))).toBe(false)
			t.expect(heartbeat.beaterStart(facts({ running = true }))).toBe(false)
			-- a worktree that no longer remembers the claim would have its beater refused at once, and again at every command
			t.expect(heartbeat.beaterStart(facts({ held = false }))).toBe(false)
			-- a spec run starts none unless the spec asks for the real one
			t.expect(heartbeat.beaterStart(facts({ specRun = true }))).toBe(false)
			t.expect(heartbeat.beaterStart(facts({ specRun = true, forced = true }))).toBe(true)
			t.expect(heartbeat.beaterStart(facts({ specRun = true, forced = true, guarded = true })))
				.toBe(false)
			-- asking for it outside a spec run changes nothing
			t.expect(heartbeat.beaterStart(facts({ forced = true }))).toBe(true)
		end
	)

	it("the beater is ./zn run's hour of beat --watch, tied to the session that started it", function()
		t.expect(heartbeat.BEATER_SECONDS).toBe(3600)
		t.expect(heartbeat.beaterArgv("/w/repo", "c0010", nil)).toEqual({
			"/w/repo/zn",
			"run",
			"--time",
			"3600",
			"--",
			"/w/repo/zn",
			"beat",
			"c0010",
			"--watch",
		})
		t.expect(heartbeat.beaterArgv("/w/repo", "R0010", 4242)).toEqual({
			"/w/repo/zn",
			"run",
			"--time",
			"3600",
			"--",
			"/w/repo/zn",
			"beat",
			"R0010",
			"--watch",
			"--session",
			"4242",
		})
	end)

	it("a beater is running only while its pid answers and its hour has not passed", function()
		t.expect(heartbeat.beaterRunning(`123 {NOW + 100}\n`, NOW, true)).toBe(true)
		t.expect(heartbeat.beaterRunning(`123 {NOW + 100}\n`, NOW, false)).toBe(false) -- the pid is gone
		t.expect(heartbeat.beaterRunning(`123 {NOW}\n`, NOW, true)).toBe(false) -- a reused pid after the hour
		t.expect(heartbeat.beaterRunning("", NOW, true)).toBe(false)
		t.expect(heartbeat.beaterRunning("garbled", NOW, true)).toBe(false)
	end)

	it("the session is the nearest claude ancestor; another CLI has none", function()
		local chain = {
			{ pid = 90, command = "lune run engine/main.luau beat c0010" },
			{ pid = 80, command = "/bin/zsh -c source /Users/me/.claude/shell-snapshots/snapshot-zsh.sh" },
			{ pid = 70, command = "/Users/me/.local/bin/claude --resume" },
			{ pid = 60, command = "/Applications/Terminal.app/Contents/MacOS/Terminal" },
		}
		t.expect(heartbeat.sessionPid(chain)).toBe(70)
		-- the other CLIs the repository dispatches to
		for _, program in
			{
				"/Users/me/.local/bin/grok",
				"/Users/me/.kimi-code/bin/kimi",
				"/Users/me/.local/bin/agent",
				"cursor-agent",
			}
		do
			t.expect(heartbeat.sessionPid({
				chain[1],
				chain[2],
				{ pid = 71, command = `{program} --resume` },
				chain[4],
			})).toBe(71)
		end
		t.expect(heartbeat.sessionPid({ chain[1], { pid = 72, command = "/usr/local/bin/codex" } })).toBe(nil) -- not named in .models.toml
		t.expect(heartbeat.sessionPid({ chain[1], chain[2], chain[4] })).toBe(nil)
		t.expect(heartbeat.sessionPid({})).toBe(nil)
	end)

	it("the watch loop stops for a restamped claim first, then a place gone, then its bound", function()
		local every = 300
		t.expect(heartbeat.watch(A, A, NOW, NOW + 3600, every, nil)).toBe("beat")
		t.expect(heartbeat.watch(A, A, NOW, NOW + 3600, every, "its session ended")).toBe("stop-gone")
		t.expect(heartbeat.watch(A, B, NOW, NOW + 3600, every, "its session ended")).toBe("stop-restamped")
		t.expect(heartbeat.watch(A, nil, NOW, NOW + 3600, every, nil)).toBe("stop-restamped")
		t.expect(heartbeat.watch(A, A, NOW, NOW + 100, every, "its worktree is gone")).toBe("stop-gone")
		t.expect(heartbeat.watch(A, A, NOW, NOW + 100, every, nil)).toBe("stop-bound")
	end)

	it(
		"a loop has a place to beat from while its session lives, its worktree exists and still holds the claim",
		function()
			t.expect(heartbeat.gone(nil, true, true)).toBe(nil) -- no session known: its time and worktree bound it
			t.expect(heartbeat.gone(true, true, true)).toBe(nil)
			t.expect(heartbeat.gone(false, true, true)).toBe("its session ended")
			t.expect(heartbeat.gone(true, false, true)).toBe("its worktree is gone")
			t.expect(heartbeat.gone(true, true, false)).toBe("its worktree no longer holds the claim")
		end
	)

	it(
		"the dispatcher beats the claim its step's worktree remembers, else the one main showed at the step's start",
		function()
			t.expect(heartbeat.dispatchStamp(A, nil)).toBe(A)
			t.expect(heartbeat.dispatchStamp(A, "")).toBe(A)
			t.expect(heartbeat.dispatchStamp(A, B)).toBe(B)
			t.expect(heartbeat.dispatchStamp(nil, B)).toBe(B)
			t.expect(heartbeat.dispatchStamp(nil, nil)).toBe(nil)
			-- a document's status counts as a claim only when it is one
			t.expect(heartbeat.stampIn(A)).toBe(A)
			t.expect(heartbeat.stampIn(B)).toBe(B)
			t.expect(heartbeat.stampIn("prepared-quiet-copper-falcon")).toBe(nil)
			t.expect(heartbeat.stampIn("new-a-b-c")).toBe(nil)
			t.expect(heartbeat.stampIn(nil)).toBe(nil)
		end
	)

	it("a claim whose kind changed is ended, not taken over", function()
		t.expect(heartbeat.lostKind(A, nil)).toBe("ended")
		t.expect(heartbeat.lostKind(A, "preparing-lucky-violet-heron")).toBe("taken")
		t.expect(heartbeat.lostKind(A, B)).toBe("ended") -- a prep that ended normally, the item readied later
		t.expect(heartbeat.lostKind(B, A)).toBe("ended")
	end)

	it("the child's answer is a beat, a lost claim, no claim yet, or a failure", function()
		t.expect(heartbeat.dispatchOutcome(true, "")).toBe("beat")
		t.expect(heartbeat.dispatchOutcome(false, "c0010's claim was taken over (now preparing-a-b-c)"))
			.toBe("lost")
		t.expect(heartbeat.dispatchOutcome(false, "c0010's claim ended")).toBe("lost")
		t.expect(
			heartbeat.dispatchOutcome(
				false,
				"beat: c0010 is new on origin/main: no claim to beat (claim it with ./zn status c0010 preparing)"
			)
		).toBe("none")
		t.expect(heartbeat.dispatchOutcome(false, "beat: c0010: timed out after 10 s")).toBe("failed")
	end)
end)
