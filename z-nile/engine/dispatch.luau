--!strict
-- The dispatcher's rules (c0117), pure: which steps are scripts and which need a model, the prompt a model step gets,
-- and the chain: from an item's tracker state, the next step, merge or stop. dispatcher.luau reads the state, runs the
-- steps and records their spend; it never reads a model's prose to decide.
local models = require("./models")
local serde = require("@lune/serde")

local dispatch = {}

export type Step = {
	kind: "model" | "script",
	lessons: string?, -- "design" or "build": the lessons a model step reads (`./zn lessons --when <it>`)
	phase: string?, -- the spend phase of the step's own session row
	argv: { string }?, -- a script step: the ./zn command ("{id}" is the item)
	where: string?, -- a script step runs in the main checkout ("main") or the step's worktree ("worktree")
}

-- Every z-nile skill and every script the chain runs, classified. Ready, stop, recombine and recording spend need
-- no model: they are script steps, and nothing starts an agent for them.
dispatch.STEPS = {
	["z-ticket"] = { kind = "model", lessons = "design", phase = "capture" },
	["z-design"] = { kind = "model", lessons = "design", phase = "prep" },
	["z-raft"] = { kind = "model", lessons = "design", phase = "prep" },
	["z-run"] = { kind = "model", lessons = "build", phase = "deliver" },
	["zz-review"] = { kind = "model", lessons = "design", phase = "design-review" },
	-- the waiting step (c0261): a cheap model babysits one bounded poll; its row takes the phase of the gate it waits at
	["z-wait"] = { kind = "model", lessons = "build", phase = "prep" },
	["z-ready"] = { kind = "script", argv = { "ready", "{id}" }, where = "main" },
	["z-stop"] = { kind = "script", argv = { "stop", "{id}" }, where = "main" },
	["raft-plan"] = { kind = "script", argv = { "raft-plan", "--apply" }, where = "worktree" },
	["recombine"] = { kind = "script", argv = { "recombine" }, where = "worktree" },
	["fold"] = { kind = "script", argv = { "fold" }, where = "worktree" },
	["release"] = { kind = "script", argv = { "release", "{id}" }, where = "worktree" },
	["spend"] = { kind = "script", argv = { "spend", "{id}" }, where = "worktree" },
	["zz-stats"] = { kind = "script", argv = { "metrics" }, where = "main" },
} :: { [string]: Step }
-- Skills read inside a step, never run as one.
dispatch.READ_INSIDE = { ["zz-rules"] = true, ["zz-arch"] = true, ["zz-test"] = true, ["zz-execute"] = true }
-- zz-review's modes: the lessons each reads and the phase of its row.
dispatch.REVIEW_MODES = {
	design = { lessons = "design", phase = "design-review", activity = "zz-review-design" },
	raft = { lessons = "design", phase = "design-review", activity = "zz-review-raft" },
	code = { lessons = "build", phase = "code-review", activity = "zz-review-code" },
	-- a stream's review (z-run Phase 2B) under the dispatcher: the model `zz-review-stream` names, cheap (c0261)
	stream = { lessons = "build", phase = "code-review", activity = "zz-review-stream" },
	-- the final review of the whole stack (zz-review --mode final): the expensive, bound round
	final = { lessons = "build", phase = "code-review", activity = "zz-review-final" },
} :: { [string]: { lessons: string, phase: string, activity: string } }

-- The step `name` is, or an error naming it: a skill read inside steps, a project's skill, or an unknown name.
function dispatch.step(name: string): Step
	local s = dispatch.STEPS[name]
	if s then
		return s
	end
	if dispatch.READ_INSIDE[name] then
		error(`{name} is not a step: it is read inside one`, 0)
	end
	if not string.match(name, "^zz?%-") and string.match(name, "^[a-z][a-z0-9]*%-") then
		error(`{name} is a project's skill, read inside a step: it is not a step`, 0)
	end
	error(`unknown step {name} (model steps: z-ticket, z-design, z-raft, z-run, z-wait, zz-review)`, 0)
end

-- A script step's command line, `./zn` first.
function dispatch.scriptArgv(name: string, id: string, extra: { string }?): { string }
	local s = dispatch.step(name)
	if s.kind ~= "script" then
		error(`{name} is a model step`, 0)
	end
	local out = { "./zn" }
	for _, a in s.argv :: { string } do
		table.insert(out, (string.gsub(a, "{id}", id)))
	end
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(out, a)
	end
	return out
end

-- The lessons a model step reads, and the phase of its row (zz-review's depend on its mode).
function dispatch.lessonsOf(name: string, mode: string?): string
	if name == "zz-review" then
		local m = dispatch.REVIEW_MODES[mode or "design"]
		if not m then
			error(`zz-review has no mode {tostring(mode)} (design, raft, code, stream, final)`, 0)
		end
		return m.lessons
	end
	local s = dispatch.step(name)
	if s.kind ~= "model" then
		error(`{name} is a script step: it takes no model`, 0)
	end
	return s.lessons or "design"
end

function dispatch.phaseOf(name: string, mode: string?): string
	if name == "zz-review" then
		dispatch.lessonsOf(name, mode)
		return dispatch.REVIEW_MODES[mode or "design"].phase
	end
	return dispatch.step(name).phase or "build"
end

-- The activity a step runs, the key of its table in .models.toml (c0261): a review by its mode (design, raft, final,
-- code, stream), a mode that names none is `zz-review-<mode>`; every other step is its own activity.
function dispatch.activityOf(name: string, mode: string?): string
	if name == "zz-review" then
		local m = dispatch.REVIEW_MODES[mode or "design"]
		if not m then
			error(`zz-review has no mode {tostring(mode)}`, 0)
		end
		return (m :: any).activity or `zz-review-{mode or "design"}`
	end
	dispatch.step(name)
	return name
end

-- The poll a wait step runs: one condition, a loop with its own clock below the runner's bound; exit 0 when it holds,
-- 2 when it can no longer hold (a failed check, a closed PR), 3 when the time ran out.
function dispatch.waitCommand(untilWhat: string, pr: number, seconds: number, every: number?): string
	local gap = every or 30
	if seconds < 1 or seconds ~= math.floor(seconds) or gap < 0 or gap ~= math.floor(gap) then
		error("a wait is a whole number of seconds, at least 1, between polls of 0 or more", 0)
	end
	local body: string
	if untilWhat == "checks" then
		body =
			`out=$(gh pr checks {pr} 2>&1); rc=$?; [ $rc -eq 0 ] && exit 0; if [ $rc -eq 8 ]; then bad=0; else case "$out" in *"no checks"*) bad=0;; *) bad=$((bad+1)); [ $bad -ge 3 ] && exit 2;; esac; fi`
	elseif untilWhat == "mergeable" then
		body =
			`s=$(gh pr view {pr} --json mergeable -q .mergeable); [ "$s" = MERGEABLE ] && exit 0; [ "$s" = CONFLICTING ] && exit 2`
	elseif untilWhat == "merged" then
		body =
			`s=$(gh pr view {pr} --json state -q .state); [ "$s" = MERGED ] && exit 0; [ "$s" = CLOSED ] && exit 2`
	else
		error(`wait until {untilWhat}: one of checks, mergeable, merged`, 0)
	end
	-- the loop is its own clock: it polls, then sleeps only if the next poll still fits before its deadline, so its end
	-- is exit 3; the runner's bound sits above the deadline by one sleep and a margin for gh itself
	local loop =
		`bad=0; end=$((SECONDS+{seconds})); while [ $SECONDS -lt $end ]; do {body}; [ $((SECONDS+{gap})) -lt $end ] || break; sleep {gap}; done; exit 3`
	return `./zn run --time {seconds + gap + 30} -- bash -c '{loop}'`
end

-- The wait step's prompt: the one command, again on exit 3, at most `times` times, nothing else.
function dispatch.waitPrompt(command: string, times: number): string
	local ms = 0
	local bound = string.match(command, "%-%-time (%d+)")
	if bound then
		ms = (tonumber(bound) :: number) * 1000
	end
	return `Run this command in the shell, with a tool timeout of {ms} ms:\n\n{command}\n\nIf it ends with exit code 3, run it again, at most {times} times in all. Stop when it ends with exit code 0 or 2, or with any other exit code. Do nothing else: read no files, edit nothing, run no other command.`
end

export type PromptInput = {
	waitCommand: string?, -- z-wait: the poll (dispatch.waitCommand)
	waitTimes: number?, -- z-wait: how many times at most
	step: string,
	id: string, -- the item, or "" for z-ticket
	mode: string?, -- zz-review's mode
	skillPath: string, -- the skill's real SKILL.md (z-nile/skills/<name>/SKILL.md)
	worktree: string,
	stateDir: string, -- where questions.md goes
	promptPath: string?, -- z-run: the raft's readied prompt.md
	streamWorktree: string?, -- zz-review in stream mode: the stream's worktree (ws-<issue>), read only
	description: string?, -- z-ticket: the user's words
	project: string?, -- z-ticket: the project to capture into
}

-- The prompt of a model step. It names the skill's file, which every CLI reads itself; no skill text,
-- architecture map or other issue is pasted (the user's "Name the files in the prompt").
function dispatch.prompt(p: PromptInput): string
	if p.step == "z-wait" then
		-- the wait step has no skill and no lessons to read: its prompt is the poll and nothing else (c0261)
		return dispatch.waitPrompt(p.waitCommand or "", p.waitTimes or 1) .. "\n"
	end
	local what: string
	if p.step == "z-ticket" then
		what = `Read \`{p.skillPath}\` and follow it to capture this as one issue{if p.project
			then ` in the {p.project} project`
			else ""}: "{p.description or ""}".`
	elseif p.step == "z-run" then
		what =
			`Read \`{p.skillPath}\` and follow it for {p.id}: its input is the raft's prompt, \`{p.promptPath or `./zn prompt {p.id} --path`}\`; read the whole file first.`
	elseif p.step == "zz-review" and p.mode == "stream" then
		-- a dispatched run has no caller to return text to: the reviewer writes review.md in its own state folder and
		-- the dispatcher numbers it into the raft's folder (design review 008 F1). One round: there is no later one.
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in stream mode. This is the one round. Read the stream's diff and run its checks in \`{p.streamWorktree or `.worktree/ws-{p.id}`}\` (read only there). Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into the raft's folder as \`stream-review-{p.id}-001.md\`.`
	elseif p.step == "zz-review" and p.mode == "final" then
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in final mode. Run \`./zn trace {p.id}\`, fill \`trace.md\` in {p.id}'s folder, verify it with \`./zn trace {p.id} --check\`, and write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into place as \`final-review-NNN.md\`.`
	elseif p.step == "zz-review" then
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in {p.mode or "design"} mode. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into place as that mode's file ({if p.mode
					== "code"
				then "`review-NNN.md`"
				else "`design-review-NNN.md`"}).`
	else
		what = `Read \`{p.skillPath}\` and follow it for {p.id}.`
	end
	local lines = {
		`You are running the z-nile step {p.step}{if p.id ~= "" then ` for {p.id}` else ""}, headless and unattended, under ./zn dispatch.`,
		what,
		"Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.",
		`Work only in \`{p.worktree}\`: it is your working directory. Never edit the main checkout.`,
		`Nobody will answer a question. When a decision needs the user (a scope change, a missing credential), write \`{p.stateDir}/questions.md\`, one \`## Q<n>\` heading per question with the options and what each costs, and stop. A review that leaves a refutation or an unclosed high is not a guess: write \`## Open to the human\` in the item's document, one bullet per finding (\`- F2: <finding>. Answer: <your answer>. Decision: <what the human must decide>\`), do not rule on it yourself, and stop.`,
		"Never merge a pull request and never push to main yourself: the dispatcher merges at its gates, and `git` and `gh` refuse.",
		"Do not pass --time or --tokens. The dispatcher records this session's wall, CPU, tokens and model.",
	}
	return table.concat(lines, "\n") .. "\n"
end

-- The chain's view of an item, read from tracker state (origin/main, the step's worktree, the PR, the run state).
export type Pr = {
	number: number,
	state: string,
	draft: boolean,
	green: boolean,
	mergeable: boolean,
	conflicting: boolean?, -- GitHub says CONFLICTING (UNKNOWN, still computing, is not) (c0261)
	mergeState: string?, -- GitHub's mergeable: MERGEABLE, CONFLICTING, UNKNOWN or "" (c0261)
	failed: boolean?, -- a check already failed: no wait will turn it green (c0261)
	head: string, -- the head commit the gate checked (the merge is pinned to it)
	-- why its fetched head is not this gate's to merge (the one tracker-state function on the head, review 003 F5),
	-- or nil; the dispatcher judges it before the chain decides
	judged: string?,
	-- what the judgement saw (code review 007 F3): the main it judged against and the ids of the items the PR carries,
	-- for the comparison after the merge
	judgedMain: string?,
	itemIds: { string }?,
}
export type Facts = {
	id: string,
	folder: string, -- the item's folder on origin/main
	root: string, -- its project root
	kind: "issue" | "raft" | "none",
	where: string, -- origin/main: "backlog", "active", "done" or "none"
	status: string, -- the effective status on origin/main (new, preparing, prepared, active, done)
	design: string, -- origin/main's design: line
	raft: string, -- origin/main's raft: line (an issue)
	ownClaim: boolean, -- the preparing claim is the one this checkout's dispatcher made
	localRaft: string, -- the raft: line in the rafting worktree, when the dispatcher rafted it ("" when none)
	pr: Pr?, -- the PR of the step that holds the item now (prep, rafting or run)
	questions: boolean, -- the run state holds questions.md
	openHuman: { string }, -- unruled ids under ## Open to the human in the step's worktree document
	last: { step: string, outcome: string }?, -- the last step's outcome in the run state
	uncovered: { string }, -- `./zn lessons --uncovered <id>` in the step's worktree, after a review step
	autoMerge: { string },
	description: string?, -- `dispatch new`'s words
	waitedHead: string?, -- the head the last z-wait already waited on (c0261)
}
export type Action = {
	kind: "step" | "merge" | "stop",
	step: string?, -- kind step: the step to run
	target: string?, -- the item it runs on
	gate: string?, -- kind merge or a gate stop: "prep", "raft" or "run"
	pr: number?,
	head: string?, -- a merge: the head commit it is pinned to
	why: string?,
	waitFor: string?, -- the wait step: "checks" or "merged"
	code: number?, -- kind stop: 0 done, 1 failure, 3 needs the user, 4 a block or a gate left to a human (a draft, a conflict, a failed check, a PR a human must judge, the run PR until c0252)
}

-- the most actions one chain run takes before it stops
dispatch.MAX_ACTIONS = 30

dispatch.EXIT = { done = 0, failure = 1, user = 3, gate = 4, tripwire = 5 }

local REVIEW_STEPS = { ["z-design"] = true, ["z-raft"] = true, ["z-run"] = true, ["zz-review"] = true }

local function stop(code: number, why: string): Action
	return { kind = "stop", code = code, why = why }
end

-- A skill lesson's path (`<z-nile or a project>/skills/<skill>/lessons/<name>.md`): a prep PR may carry those.
function dispatch.isLesson(path: string): boolean
	return string.match(path, "^[^/]+/skills/[^/]+/lessons/[^/]+%.md$") ~= nil
end

-- Whether GitHub's `commits/<sha>/pulls` answer names a pull request merged into main whose merge commit is `sha`
-- (the watermark's pull-request rule, G20; review 003 F6: into main only, never another branch).
function dispatch.prMergedFrom(text: string, sha: string): boolean
	local ok, list = pcall(function()
		return serde.decode("json", text)
	end)
	if not ok or type(list) ~= "table" then
		return false
	end
	for _, pr in list :: { any } do
		if
			type(pr) == "table"
			and type(pr.merged_at) == "string"
			and pr.merge_commit_sha == sha
			and type(pr.base) == "table"
			and pr.base.ref == "main"
		then
			return true
		end
	end
	return false
end

local function gate(f: Facts, name: string, pr: Pr): Action
	if pr.state == "CLOSED" then
		return stop(dispatch.EXIT.failure, `the {name} PR #{pr.number} was closed without merging`)
	end
	if pr.state == "MERGED" then
		return stop(
			dispatch.EXIT.failure,
			`the {name} PR #{pr.number} merged but origin/main does not show it: ./zn sync`
		)
	end
	local carries = if name ~= "run" then pr.judged else nil
	local head = pr.head or ""
	if
		name ~= "run"
		and table.find(f.autoMerge, name)
		and not pr.draft
		and pr.green
		and pr.mergeable
		and not carries
		and head ~= ""
	then
		return { kind = "merge", gate = name, pr = pr.number, target = f.id, head = head }
	end
	-- a gate that only waits for its checks, or for GitHub to finish computing its merge state, waits once per head on the
	-- waiting step (c0261); a failed check, a conflict, a draft or a PR a human must judge waits for nothing
	if
		name ~= "run"
		and table.find(f.autoMerge, name)
		and not pr.draft
		and not pr.failed
		and not pr.conflicting
		and not carries
		and head ~= ""
		and f.waitedHead ~= head
		and (not pr.green or pr.mergeState == "UNKNOWN")
	then
		return {
			kind = "step",
			step = "z-wait",
			target = f.id,
			gate = name,
			pr = pr.number,
			head = head,
			waitFor = if pr.green then "mergeable" else "checks",
		}
	end
	local why = if name == "run"
		then `ready to merge: the run PR #{pr.number} is a human's to merge (then ./zn dispatch {f.id} again)`
		elseif
			not table.find(f.autoMerge, name)
		then `the {name} PR #{pr.number} waits for a merge (dispatch.auto_merge leaves it to a human)`
		elseif pr.draft then `the {name} PR #{pr.number} is a draft`
		elseif not pr.green then `the {name} PR #{pr.number} waits for green CI`
		elseif not pr.mergeable then `the {name} PR #{pr.number} is not mergeable`
		elseif carries then `the {name} PR #{pr.number} waits for a human: {carries}`
		else `the {name} PR #{pr.number} waits for a human: its head commit is unknown`
	return { kind = "stop", code = dispatch.EXIT.gate, gate = name, pr = pr.number, why = why }
end

-- The next thing the chain does for the item. Stops first: questions.md, a failed step, a review step that left an
-- unharvested finding. Then by state: capture, design, the prep gate, raft-plan, z-raft, the rafting gate, ready,
-- run, the run's gate (always a human's), done.
function dispatch.next(f: Facts): Action
	if f.questions then
		return stop(
			dispatch.EXIT.user,
			"needs the user: answer questions.md, then ./zn dispatch retry " .. f.id
		)
	end
	if #f.openHuman > 0 then
		return stop(
			dispatch.EXIT.user,
			`needs the user: {f.id} has {table.concat(f.openHuman, ", ")} under ## Open to the human with no ruling; rule on each in the document, then ./zn dispatch retry {f.id}`
		)
	end
	if f.last and f.last.outcome == "tripwire" and f.last.step == "merge-check" then
		return stop(
			dispatch.EXIT.tripwire,
			`a gate merge did not land on the main it was judged against (state.json names it): look at main, then run ./zn dispatch vet and ./zn dispatch retry {f.id}: nothing else clears it`
		)
	end
	if f.last and f.last.outcome == "tripwire" then
		return stop(
			dispatch.EXIT.tripwire,
			`{f.last.step} tripped the wire: main or the main checkout moved in a way the dispatcher did not make (state.json names it); a human looks first, then runs ./zn dispatch vet and ./zn dispatch retry {f.id}: nothing else clears it`
		)
	end
	-- a wait that ended any way (ran out, failed, capped) is not a failed chain: the gate waited once for its head, and the
	-- PR is read again (c0261)
	if f.last and f.last.outcome ~= "ok" and f.last.step ~= "z-wait" then
		return stop(dispatch.EXIT.failure, `{f.last.step} ended {f.last.outcome}: ./zn dispatch retry {f.id}`)
	end
	if f.last and REVIEW_STEPS[f.last.step] and #f.uncovered > 0 then
		return stop(
			dispatch.EXIT.failure,
			`{f.last.step} left unharvested findings ({table.concat(f.uncovered, "; ")}): harvest them before the chain goes on`
		)
	end
	-- a step that ended ok but moved nothing stops the chain instead of running again
	local done = f.last and f.last.outcome == "ok" and f.last.step or nil
	if done == "z-design" and f.kind == "issue" and f.status == "new" then
		return stop(
			dispatch.EXIT.failure,
			`z-design ended but {f.id} is still new on origin/main: it claimed nothing`
		)
	elseif done == "z-design" and f.kind == "issue" and f.status == "preparing" and not f.pr then
		return stop(dispatch.EXIT.failure, `z-design ended without opening {f.id}'s prep PR`)
	elseif done == "raft-plan" and f.localRaft == "" then
		return stop(dispatch.EXIT.failure, `raft-plan put {f.id} in no raft (see its skip line)`)
	elseif done == "z-ready" and f.kind == "raft" and f.where == "backlog" then
		return stop(dispatch.EXIT.failure, `z-ready ended but {f.id} is not active on origin/main`)
	elseif done == "z-run" and f.kind == "raft" and f.where == "active" and (not f.pr or f.pr.draft) then
		return stop(
			dispatch.EXIT.failure,
			`z-run ended but {f.id}'s PR is still a draft: ./zn done did not run`
		)
	end
	if f.kind == "none" then
		if f.description then
			return { kind = "step", step = "z-ticket", target = "" }
		end
		return stop(dispatch.EXIT.failure, `{f.id} is not on origin/main`)
	end
	if f.kind == "issue" then
		if f.where == "done" then
			return stop(dispatch.EXIT.done, `{f.id} is done`)
		end
		if f.raft ~= "" and (f.where == "active" or f.status == "prepared") then
			return { kind = "step", step = "follow", target = f.raft }
		end
		if f.status == "new" or (f.status == "preparing" and f.ownClaim) then
			if f.pr then
				return gate(f, "prep", f.pr)
			end
			return { kind = "step", step = "z-design", target = f.id }
		end
		if f.status == "preparing" then
			return stop(dispatch.EXIT.failure, `{f.id} is being prepared by another terminal`)
		end
		if f.status == "prepared" and f.design == "ready" then
			if f.pr then
				return gate(f, "raft", f.pr)
			end
			if f.localRaft == "" then
				return { kind = "step", step = "raft-plan", target = f.id }
			end
			if not (f.last and f.last.step == "z-raft") then
				return { kind = "step", step = "z-raft", target = f.localRaft }
			end
			return stop(dispatch.EXIT.failure, `{f.localRaft} is rafted but its rafting PR is not open`)
		end
		return stop(dispatch.EXIT.failure, `{f.id} is {f.status} with design: {f.design}: nothing to run`)
	end
	-- a raft
	if f.where == "done" then
		return { kind = "stop", code = dispatch.EXIT.done, why = `{f.id} is done`, step = "flush" }
	end
	if f.where == "backlog" then
		if f.status == "prepared" then
			return { kind = "step", step = "z-ready", target = f.id }
		end
		return stop(dispatch.EXIT.failure, `{f.id} is {f.status} in the backlog: z-raft prepares it first`)
	end
	-- active: z-run, until its PR leaves draft (`./zn done`); the merge is always a human's
	if f.pr and f.pr.state == "OPEN" and not f.pr.draft then
		return gate(f, "run", f.pr)
	end
	return { kind = "step", step = "z-run", target = f.id }
end

-- One line per CLI a model step would try, for --dry-run.
function dispatch.describe(r: models.Resolved): { string }
	local out: { string } = {}
	for i, spec in models.tries(r) do
		table.insert(
			out,
			`try={i} cli={spec.cli} runtime={spec.runtime} model={models.id(spec)} rank={spec.rank} max_tokens={spec.maxTokens}`
				.. (if spec.maxCalls then ` max_calls={spec.maxCalls}` else "")
				.. (if spec.maxMinutes then ` max_minutes={spec.maxMinutes}` else "")
		)
	end
	return out
end

return dispatch
