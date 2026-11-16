--!strict
-- The worker's pull loop (c0253): `./zn next`, then the dispatcher's chain for what it printed, until stopped. It owns the
-- order of the turns and none of the reading: everything it learns or does comes through a `World`, which workedge builds
-- from `./zn` commands, the flock, the clock and the state folder, and which a spec fills. The loop runs no model: a model
-- step is the dispatcher's (`./zn dispatch <id> --worker`), with its wrapper, broker, tripwire, measured rows and gates.
local supervise = require("./supervise")
local work = require("./work")

local workloop = {}

export type World = {
	next: () -> (string, string, number), -- ./zn next: stdout, stderr, exit code
	dispatch: (args: { string }) -> number, -- ./zn <args> (a dispatch run) in the main checkout: its exit code
	lock: (id: string) -> boolean, -- one worker per item; held until unlock
	unlock: (id: string) -> (),
	now: () -> number,
	sleep: (seconds: number) -> (), -- slices that look for a stop
	stopped: () -> boolean, -- a stop was asked (the stop file)
	state: (s: supervise.State) -> (), -- the state file
	say: (line: string) -> (),
	held: string, -- the item the state file names as held when this run began ("" for none)
	cli: string?, -- the CLI the person started (Q8)
	noRun: boolean, -- this host does not land (G1)
	idleSeconds: number?,
}

export type Options = {
	once: boolean, -- --once: take one item, never wait for work
	maxItems: number?, -- --max-items
}

type Tally = { moved: { string }, blocked: { string } }

local function publish(world: World, state: string, item: string, held: string, tally: Tally)
	world.state({
		pid = 0, -- the edge fills pid and since
		state = state,
		item = item,
		cli = world.cli or "",
		since = "",
		moved = #tally.moved,
		blocked = #tally.blocked,
		held = held,
	})
end

-- Carries one pick through the dispatcher until its chain ends. Returns "done", "blocked", "park" (a draft waits for the
-- person's approval), "lock" (another worker has it), "stopped" (a stop was asked: the claim stays held) or "stop" with why.
function workloop.item(world: World, pick: supervise.Pick, tally: Tally): (string, string)
	if not world.lock(pick.id) then
		world.say(`{pick.id}: another worker holds it`)
		return "lock", ""
	end
	publish(world, "working", pick.id, pick.id, tally)
	local tries = 0
	local retrying = false
	local waitedFrom: number? = nil
	local result, why = "stop", "the loop ran out of turns"
	-- a bounded turn count, not a `while`: a chain reaches a gate in a handful of runs
	for _ = 1, supervise.MAX_TURNS do
		if world.stopped() then
			result, why = "stopped", `stop asked: {pick.id} stays held, ./zn work run resumes it`
			break
		end
		local code = world.dispatch(
			supervise.dispatchArgs(pick, { cli = world.cli, noRun = world.noRun, retry = retrying })
		)
		retrying = false
		local move = supervise.afterDispatch(pick.kind, code, tries)
		if move.kind == "done" then
			result, why = "done", move.why
			break
		elseif move.kind == "blocked" then
			result, why = "blocked", move.why
			break
		elseif move.kind == "park" then
			result, why = "park", move.why
			break
		elseif move.kind == "retry" then
			tries += 1
			retrying = true
			world.say(`{pick.id}: {move.why}`)
		elseif move.kind == "wait" then
			local from = waitedFrom or world.now()
			waitedFrom = from
			if world.now() - from >= supervise.GATE_WAIT_SECONDS then
				result, why =
					"stop",
					`{pick.id}: its gate stayed pending for {supervise.GATE_WAIT_SECONDS} seconds: look at it, then ./zn work run`
				break
			end
			publish(world, "waiting", pick.id, pick.id, tally)
			world.say(`{pick.id}: {move.why}`)
			world.sleep(supervise.IDLE_SECONDS)
		else
			result, why = "stop", `{pick.id}: {move.why}`
			break
		end
	end
	if result ~= "stopped" and result ~= "stop" then
		publish(world, "working", "", "", tally)
	end
	world.unlock(pick.id)
	return result, why
end

-- The pull loop. Returns the summary.
function workloop.run(world: World, opts: Options): supervise.Summary
	local tally: Tally = { moved = {}, blocked = {} }
	local stopped = "the stack is empty"
	local blockedInARow = 0
	local taken = 0
	local failedReads = 0
	local resumeFirst = world.held
	local heldAtEnd = ""
	for _ = 1, supervise.MAX_TURNS do
		if world.stopped() then
			stopped = "stop asked"
			break
		end
		if opts.maxItems and taken >= opts.maxItems then
			stopped = `--max-items {opts.maxItems} reached`
			break
		end
		if blockedInARow >= work.BLOCKED_IN_A_ROW then
			stopped = work.blockedWhy()
			break
		end
		local pick: supervise.Pick? = nil
		if resumeFirst ~= "" then
			-- a raft this clone held when the last run ended is carried on before anything new is asked of `next`
			pick = {
				id = resumeFirst,
				kind = if string.sub(resumeFirst, 1, 1) == "R" then "raft" else "draft",
				why = "held by the previous run",
			}
			resumeFirst = ""
		else
			local out, err, code = world.next()
			local read = supervise.parseNext(out, err, code)
			if read.kind == "failed" then
				failedReads += 1
				world.say(`read failed ({failedReads} of {supervise.READ_RETRIES}): {read.why}`)
				if failedReads >= supervise.READ_RETRIES then
					stopped = `{supervise.READ_RETRIES} reads of ./zn next failed in a row: {read.why}`
					break
				end
				publish(world, "waiting", "", "", tally)
				world.sleep(supervise.IDLE_SECONDS)
				continue
			end
			failedReads = 0
			if read.kind == "none" then
				if opts.once then
					stopped = "nothing claimable (--once)"
					break
				end
				publish(world, "idle", "", "", tally)
				world.sleep(world.idleSeconds or supervise.IDLE_SECONDS)
				continue
			end
			pick = read.pick
		end
		local p = pick :: supervise.Pick
		taken += 1
		local r, why = workloop.item(world, p, tally)
		if r == "done" then
			table.insert(tally.moved, p.id)
			blockedInARow = 0
		elseif r == "blocked" then
			table.insert(tally.blocked, p.id)
			blockedInARow += 1
		elseif r == "park" then
			blockedInARow = 0
		elseif r == "stopped" then
			stopped = "stop asked"
			heldAtEnd = p.id
			world.say(why)
			break
		elseif r == "stop" then
			stopped = why
			heldAtEnd = p.id
			break
		else
			taken -= 1
			world.sleep(world.idleSeconds or supervise.IDLE_SECONDS)
		end
		if opts.once then
			stopped = "--once"
			break
		end
	end
	local summary = { moved = tally.moved, blocked = tally.blocked, stopped = stopped }
	publish(world, "stopped", "", heldAtEnd, tally)
	world.say(supervise.summary(summary))
	return summary
end

return workloop
