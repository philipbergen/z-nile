--!strict
-- The dispatcher's rules (c0117), pure: which steps are scripts and which need a model, the prompt a model step gets,
-- and the chain: from an item's tracker state, the next step, merge or stop. dispatcher.luau reads the state, runs the
-- steps and records their spend; it never reads a model's prose to decide.
local models = require("./models")
local raftplan = require("./raftplan")
local rounds = require("./rounds")
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
dispatch.READ_INSIDE = {
	["zz-rules"] = true,
	["zz-arch"] = true,
	["zz-test"] = true,
	["zz-execute"] = true,
	-- the worker a person starts by hand. It is not a dispatch step.
	["z-work"] = true,
}
-- zz-review's modes: the lessons each reads and the phase of its row.
dispatch.REVIEW_MODES = {
	design = { lessons = "design", phase = "design-review" },
	raft = { lessons = "design", phase = "design-review" },
	code = { lessons = "build", phase = "code-review" },
	-- a stream's review (z-run Phase 2B) under the dispatcher: the review model of the CLI, like a code review
	stream = { lessons = "build", phase = "code-review" },
	final = { lessons = "build", phase = "code-review" },
} :: { [string]: { lessons: string, phase: string } }

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
	error(`unknown step {name} (model steps: z-ticket, z-design, z-raft, z-run, zz-review)`, 0)
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

export type FilingInput = {
	mode: string?, -- zz-review's mode
	dir: string, -- the folder the review lands in (repository-relative, for the messages)
	prefix: string, -- `design-review-`, `review-`, `final-review-` or `stream-review-<id>-`
	raftId: string, -- the item the review is for (a raft's, in raft mode)
	reviews: { [string]: string }, -- file name -> text of the folder's files that start with `prefix`
	grouped: string?, -- raft mode: the raft document's `grouped:` value
	step: rounds.Step?, -- f0421: what rounds.next says for a design, code or final review; nil keeps one round
}
export type Filing = { number: number?, refusal: string? } -- the round to file, or why not

-- Where a dispatched review is filed, or why it is refused (d0415), from the folder's state alone, so the dispatcher
-- asks it before it starts a reviewer and again when the review is ready. With a `step` (rounds.next, for a design,
-- code or final review) it files the step's round, or refuses with the step's reason; with none, and in stream mode, it
-- files one round and refuses a second. Raft mode files one review per `grouped:` record: the next number when no
-- review in the folder quotes the current record, a refusal when one does. A raft with no record is one round.
function dispatch.filing(p: FilingInput): Filing
	local last = 0
	for name in p.reviews do
		local n = tonumber(string.match(string.sub(name, #p.prefix + 1), "^(%d+)%.md$"))
		if string.sub(name, 1, #p.prefix) == p.prefix and n and n > last then
			last = n
		end
	end
	local step = p.step
	if step ~= nil and p.mode ~= "raft" and p.mode ~= "stream" then
		local file = `{p.dir}/{p.prefix}{string.format("%03d", step.number)}.md`
		if step.kind == "file" then
			return { number = step.number }
		elseif step.kind == "malformed" or step.kind == "rule" then
			return { refusal = if step.reason then `{p.dir}/{step.reason}` else file }
		elseif step.kind == "answer" then
			if step.number >= step.max then
				return {
					refusal = `{file} is not answered: it is round {step.number} of {step.max}, the last; what stays open goes to the human`,
				}
			end
			return {
				refusal = `{file} is not answered: answer every finding in its refute file before round {step.number + 1}`,
			}
		end
		return {
			refusal = `{file} settled the review (approve, or answered at round {step.number} of {step.max}): there is no further round`,
		}
	end
	if p.mode == "raft" then
		local map, problem = raftplan.parseGrouped(p.grouped)
		if problem then
			return { refusal = `{p.raftId}: {problem}: fix it before a review runs` }
		end
		if next(map) ~= nil then
			local covering = raftplan.coveringReview(p.reviews, map)
			if covering then
				return {
					refusal = `{p.dir} already has {covering}, which quotes {p.raftId}'s current grouped: record: one review per record, then the author answers it; there is no second round of it`,
				}
			end
			return { number = last + 1 }
		end
	end
	if last >= 1 then
		return {
			refusal = `{p.dir} already has {p.prefix}{string.format("%03d", last)}.md: one round, then the author answers it; there is no second round`,
		}
	end
	return { number = 1 }
end

-- Whether a pending spend row can be written now, from where its item stands on origin/main (d0415): a run's `deliver`
-- row once its raft is done, any other row while its item is in the backlog. `state` is nil when origin does not list it.
-- A raft's row is shared among its members, so one that names none (recorded before d0415) is never written.
function dispatch.rowWritable(id: string, phase: string, state: string?, hasMembers: boolean): boolean
	if state == nil or (string.sub(id, 1, 1) == "R" and not hasMembers) then
		return false
	end
	return if phase == "deliver" then state == "done" else state == "backlog"
end

-- What a person is told about a pending row: when it is written, or that it never is and what to do about it.
function dispatch.pendingFate(id: string, phase: string, state: string?, hasMembers: boolean): string
	if dispatch.rowWritable(id, phase, state, hasMembers) then
		return `written by the next run of {id}`
	elseif string.sub(id, 1, 1) == "R" and not hasMembers then
		return `never written: {id}'s row was recorded before d0415 and names no members (or its document was not in the step's worktree)`
	elseif state == nil then
		return `never written while origin/main does not list {id}`
	elseif phase == "deliver" and state ~= "done" then
		return `written once {id} is done on origin/main: a deliver row waits for done`
	end
	return `never written: {id} is {state} on origin/main, and a {phase} row waits for {if phase
			== "deliver"
		then "done"
		else "backlog"}`
end

export type PromptInput = {
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
	round: number?, -- zz-review in design, code or final mode: the round it files (above 1: a check of the answers)
	light: boolean?, -- f0420: zz-review in final mode of a raft that took the light path: its only review, code included
}

-- The prompt of a model step. It names the skill's file, which every CLI reads itself; no skill text,
-- architecture map or other issue is pasted (the user's "Name the files in the prompt").
-- c0136 (R0068 review-001 F5): every dispatched reviewer checks its own step lines before it ends, wherever its file is
local function checkReview(stateDir: string): string
	return `Before you end, run \`./zn lessons --check-review {stateDir}/review.md\` and fix every problem it names.`
end

function dispatch.prompt(p: PromptInput): string
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
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in stream mode. This is the one round. Read the stream's diff and run its checks in \`{p.streamWorktree or `.worktree/ws-{p.id}`}\` (read only there). Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into the raft's folder as \`stream-review-{p.id}-001.md\`. {checkReview(
				p.stateDir
			)}`
	elseif p.step == "zz-review" and p.mode == "final" then
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in final mode. The skeleton is already committed as \`trace.md\`. Fill it, then verify with \`./zn trace {p.id} --check\`: a stale line names a commit that came after the table. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into place as \`final-review-NNN.md\`.{if p.light
				then require("./work").lightNote(p.id)
				else ""} {checkReview(p.stateDir)}`
	elseif p.step == "zz-review" then
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in {p.mode or "design"} mode. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into place as that mode's file ({if p.mode
					== "code"
				then "`review-NNN.md`"
				else "`design-review-NNN.md`"}). {checkReview(p.stateDir)}`
	else
		what = `Read \`{p.skillPath}\` and follow it for {p.id}.`
	end
	if
		p.step == "zz-review"
		and p.round ~= nil
		and p.round > 1
		and p.mode ~= "stream"
		and p.mode ~= "raft"
	then
		local kind = if p.mode == "code" then "code" elseif p.mode == "final" then "final" else "design"
		local num = string.format("%03d", p.round - 1)
		what ..= ` This is round {p.round}, not round 1. {rounds.laterRule(
			`{rounds.KINDS[kind][1]}{num}.md`,
			`{rounds.KINDS[kind][2]}{num}.md`
		)}`
	end
	local lines = {
		`You are running the z-nile step {p.step}{if p.id ~= "" then ` for {p.id}` else ""}, headless and unattended, under ./zn dispatch.`,
		what,
		"Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.",
		`Work only in \`{p.worktree}\`: it is your working directory. Never edit the main checkout.`,
		`Nobody will answer a question. When a decision needs the user (a scope change, a missing credential), write \`{p.stateDir}/questions.md\`, one \`## Q<n>\` heading per question with the options and what each costs, and stop. A review that leaves a refutation or an unclosed high is not a guess: write \`## Open to the human\` in the item's document, one bullet per finding (\`- F2: <finding>. Answer: <your answer>. Decision: <what the human must decide>\`; for a review after round 1 of its kind, name its file: \`- review-002 F2: ...\`), do not rule on it yourself, and stop.`,
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
}
export type Action = {
	kind: "step" | "merge" | "stop",
	step: string?, -- kind step: the step to run
	target: string?, -- the item it runs on
	gate: string?, -- kind merge or a gate stop: "prep", "raft" or "run"
	pr: number?,
	head: string?, -- a merge: the head commit it is pinned to
	why: string?,
	code: number?, -- kind stop: 0 done, 1 failure, 3 needs the user, 4 waiting at a merge gate
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
-- (a pull request merged into main, G20; review 003 F6: into main only, never another branch).
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
			`a gate merge did not land on the main it was judged against (state.json names it): look at main, then run ./zn dispatch retry {f.id}: nothing else clears it`
		)
	end
	if f.last and f.last.outcome == "tripwire" then
		return stop(
			dispatch.EXIT.tripwire,
			`{f.last.step} tripped the wire: main or the main checkout moved in a way the dispatcher did not make (state.json names it); a human looks first, then runs ./zn dispatch retry {f.id}: nothing else clears it`
		)
	end
	if f.last and f.last.outcome ~= "ok" then
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
		-- c0278: a closed issue's chain is finished, not failed
		if f.status == "closed" then
			return stop(dispatch.EXIT.done, `{f.id} is closed (won't do): nothing to run`)
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

-- The one line a model step would start, for --dry-run (f0421 step 6: one CLI, no order), or the refusal when the CLI
-- cannot deliver the activity.
function dispatch.describe(spec: models.Spec?, refusal: string?): { string }
	if spec == nil then
		return { `refused: {refusal or "no model"}` }
	end
	return {
		`cli={spec.cli} runtime={spec.runtime} model={models.id(spec)} max_tokens={spec.maxTokens}`
			.. (if spec.maxCalls then ` max_calls={spec.maxCalls}` else "")
			.. (if spec.maxMinutes then ` max_minutes={spec.maxMinutes}` else ""),
	}
end

-- The last few stream lines of a running step, and its token count. `running` is the step's own word.
function dispatch.trailReport(text: string, tokens: number, running: boolean): { string }
	local lines: { string } = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if line ~= "" then
			table.insert(lines, line)
		end
	end
	local out: { string } = {}
	local n = #lines
	if n == 0 then
		table.insert(out, "trail: none")
	else
		local from = math.max(1, n - 7)
		table.insert(out, `trail: {n} lines, last {n - from + 1}`)
		for i = from, n do
			table.insert(out, "  " .. lines[i])
		end
	end
	table.insert(out, `tokens: {tokens}{if running then " running" else ""}`)
	return out
end

return dispatch
