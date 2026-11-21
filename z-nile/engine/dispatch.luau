--!strict
-- The dispatcher's rules (c0117), pure: which steps are scripts and which need a model, the prompt a model step gets,
-- and the chain: from an item's tracker state, the next step, merge or stop. dispatcher.luau reads the state, runs the
-- steps and records their spend; it never reads a model's prose to decide.
local models = require("./models")
local raftplan = require("./raftplan")
local serde = require("@lune/serde")
local stack = require("./stack")

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
	-- c0248: a final review per landing (a raft readied with `layers: reviewed`): the round numbers of `prefix` in the
	-- folder on origin/main. With it the round is `stack.nextRound(onMain, local)`, and only a review of that round
	-- already in the folder (this landing's) refuses: an earlier landing's review never does.
	onMain: { number }?,
	-- c0248: a code review in a marked layer's issue folder: whether the folder's newest round is current for the
	-- layer's finish (`completion.current`); false files the next round, nil and true keep one round per folder
	current: boolean?,
	-- c0248: why the folder's newest round is not answered yet (`completion.reviewProblem`), or nil; a next round is
	-- filed only for an answered round that is not current
	unanswered: string?,
	-- c0262: a ticket's final review (an issue id). `known` is the highest round of the ticket's reviews on origin/main
	-- and on its layer (a re-prepped ticket keeps its earlier ones), so the next number continues after them; `again` is
	-- finalview.state's review-again (the view changed since the last review), the one case a further round is filed
	known: number?,
	again: boolean?,
}
export type Filing = { number: number?, refusal: string? } -- the round to file, or why not

-- Where a dispatched review is filed, or why it is refused (d0415), from the folder's state alone, so the dispatcher
-- asks it before it starts a reviewer and again when the review is ready. Every mode but raft files one round and
-- refuses a second. Raft mode files one review per `grouped:` record: the next number when no review in the folder
-- quotes the current record, a refusal when one does. A raft with no record is one round, like the others.
function dispatch.filing(p: FilingInput): Filing
	local last = 0
	for name in p.reviews do
		local n = tonumber(string.match(string.sub(name, #p.prefix + 1), "^(%d+)%.md$"))
		if string.sub(name, 1, #p.prefix) == p.prefix and n and n > last then
			last = n
		end
	end
	if p.known and p.known > last then
		last = p.known
	end
	if last >= 1 and p.again then
		return { number = last + 1 } -- c0262: the view changed since the last ticket review
	end
	if p.onMain then
		local here: { number } = {}
		for name in p.reviews do
			local n = tonumber(string.match(string.sub(name, #p.prefix + 1), "^(%d+)%.md$"))
			if string.sub(name, 1, #p.prefix) == p.prefix and n then
				table.insert(here, n)
			end
		end
		local round = stack.nextRound(p.onMain, here)
		if table.find(here, round) then
			return {
				refusal = `{p.dir} already has {p.prefix}{string.format("%03d", round)}.md for this landing: one round per landing, then the author answers it; there is no second round`,
			}
		end
		return { number = round }
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
	if last >= 1 and p.current == false and p.unanswered then
		return {
			refusal = `{p.dir}/{p.prefix}{string.format("%03d", last)}.md is not settled ({p.unanswered}): answer it in its refute, or have the human rule its bullet in the issue document's open list, before another round`,
		}
	end
	if last >= 1 and p.current == false then
		return { number = last + 1 } -- the layer's change since that round was reviewed: the next round reviews it
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
	viewDir: string?, -- zz-review in final mode on a ticket: the limited view folder it runs in (c0262)
	streamWorktree: string?, -- zz-review in stream mode: the stream's worktree (ws-<issue>), read only
	description: string?, -- z-ticket: the user's words
	project: string?, -- z-ticket: the project to capture into
	through: string?, -- zz-review final mode: the layers of this landing end at this issue (c0248)
	perLanding: boolean?, -- zz-review final mode: the raft has a final review and a trace per landing (c0248)
	itemDoc: string?, -- the item's document, where a review's `## Open to the human` goes
	exchange: { string }?, -- the run's exchange files, in order (c0256): a step reads them first
	exchangeAsker: string?, -- the step that asked the latest question
	exchangeNoReply: boolean?, -- the latest answer says no reply was given
	exchangeUnknownReply: boolean?, -- the latest answer says the question was copied at the retry
	exchangeLastStep: string?, -- the step the item's last attempt ran
	parentExchange: { string }?, -- a nested step: the files of the run that started it, read only
	parentStateDir: string?,
}

-- c0250 (design review 006 F3): the command a stop or a prompt names to block an item. An issue in an active raft is
-- blocked through its raft, naming the layer; a raft id names the layer as a placeholder.
function dispatch.blockCommand(id: string, raft: string?, reason: string): string
	if raft and raft ~= "" then
		return `./zn block {raft} {reason} --layer {id}`
	elseif string.match(id, "^R%d+$") then
		return `./zn block {id} {reason} --layer <issue>`
	end
	return `./zn block {id} {reason}`
end

-- c0250 (design review 008 F1, F2): the stop a nested step's author is told, one text for every place that prints it:
-- the note goes in the raft's folder for a layer of a readied raft, else in the item's own.
function dispatch.nestedStop(id: string, raft: string?): string
	local holder = if raft and raft ~= "" then raft else id
	return `this step needs the user, and only the step that started it can ask: say so in your review, and your author writes escalation.md in {holder}'s folder and runs {dispatch.blockCommand(
		id,
		raft,
		"<reason>"
	)}`
end

-- c0250 (design review 006 F2): the model step an item resumes with, which asks a carried question: z-run for a raft,
-- z-raft for an issue a raft blocked or resolved, z-design for any other issue.
function dispatch.resumeStep(f: Facts): string
	if f.kind == "raft" then
		return "z-run"
	elseif f.blockedBy or f.resolvedBy then
		return "z-raft"
	end
	return "z-design"
end

-- c0250: what a step does when a decision needs the user. A capture has no item yet, so z-ticket keeps c0256's local
-- questions.md; a step on an item files an escalation note and blocks the item, which every host and the board see.
local function askText(p: PromptInput): string
	local open =
		"A review that leaves a refutation or an unclosed high is not a guess: write `## Open to the human` in the item's document, one bullet per finding (`- F2: <finding>. Answer: <your answer>. Decision: <what the human must decide>`), do not rule on it yourself, and stop."
	if p.id == "" then
		return `Nobody will answer a question. When a decision needs the user (a scope change, a missing credential), write \`{p.stateDir}/questions.md\`, one \`## Q<n>\` heading per question with the options and what each costs, and stop. {open}`
	elseif p.step == "zz-review" then
		return `Nobody will answer a question. A review never blocks the item: when a decision needs the user, say so in your review, and the item's author blocks it. {open}`
	end
	return `Nobody will answer a question. When a decision needs the user (a scope change, a missing credential), write \`escalation.md\` in {p.id}'s folder (\`## Question\`, \`## What was tried\`, \`## Open findings or error\` and \`## Options\`, each option a bullet that starts with one of amend-design, approve, split, retry or abort and exactly one ending (recommended)) and run \`./zn block {p.id} <review-exhausted|design-gap|needs-decision|red-gate|quota|tripwire>\` (a readied raft: \`--layer <issue>\`, the layer whose ticket needs the decision), then stop. Under ./zn dispatch, do not run \`./zn done\`: the dispatcher lands the layers below (c0252). A review that leaves a refutation or an unclosed high is review-exhausted: write \`## Open to the human\` in the item's document (one bullet per finding: \`- F2: <finding>. Answer: <your answer>. Decision: <what the human must decide>\`), copy those bullets verbatim under \`## Open findings or error\` in \`escalation.md\`, run \`./zn block {p.id} review-exhausted\` (a readied raft: \`--layer <issue>\`, the layer whose ticket needs the decision), and never rule on them yourself. After the user resolves it, run \`./zn rulings {p.id}\` before you go on.`
end

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
	elseif p.step == "zz-review" and p.mode == "final" and p.viewDir then
		-- c0262: a ticket's final review reads only its limited view; no skill, lessons, trace or open list is named
		what =
			`You are the last review of ticket {p.id}. Your working directory is its limited view. Read \`README.md\` there first and follow it; read only the files in this folder. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into the ticket's folder as \`final-review-NNN.md\`.`
	elseif p.step == "zz-review" and p.mode == "final" then
		local scope = if p.through then ` --through {p.through}` else ""
		if p.perLanding then
			what =
				`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in final mode, for the layers of this landing only. Run \`./zn trace {p.id}{scope}\`, fill its table, and write the filled table to \`{p.stateDir}/trace.md\` and your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers them and moves them into the raft's folder as \`final-review-NNN.md\` and \`trace-NNN.md\` (the same NNN, one more than the last landing's). Findings you leave for the human go under \`## Open to the human\` in the raft document{if p.itemDoc
					then ` (\`{p.itemDoc}\`)`
					else ""}. {checkReview(p.stateDir)}`
		else
			what =
				`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in final mode. The skeleton is already committed as \`trace.md\`. Fill it, then verify with \`./zn trace {p.id} --check\`: a stale line names a commit that came after the table. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into place as \`final-review-NNN.md\`. {checkReview(
					p.stateDir
				)}`
		end
	elseif p.step == "zz-review" and p.mode == "code" then
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in code mode: the diff of {p.id}'s layer. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it, stamps it with the layer's \`Commit:\` and \`Patch:\`, and moves it into {p.id}'s folder as \`review-NNN.md\`. A finding that must wait for the human goes under \`## Open to the human\` in the issue's document{if p.itemDoc
				then ` (\`{p.itemDoc}\`)`
				else ""}, not the raft's. {checkReview(p.stateDir)}`
	elseif p.step == "zz-review" then
		what =
			`Read \`{p.skillPath}\` and act as the clean adversarial reviewer of {p.id} in {p.mode or "design"} mode. Write your review to \`{p.stateDir}/review.md\` and nothing else: the dispatcher numbers it and moves it into place as that mode's file ({if p.mode
					== "code"
				then "`review-NNN.md`"
				else "`design-review-NNN.md`"}). {checkReview(p.stateDir)}`
	else
		what = `Read \`{p.skillPath}\` and follow it for {p.id}.`
	end
	local lines: { string } = {
		`You are running the z-nile step {p.step}{if p.id ~= "" then ` for {p.id}` else ""}, headless and unattended, under ./zn dispatch.`,
		what,
		if p.viewDir
			then "Read nothing outside this folder: the limited view is the whole of your brief."
			else "Search with `./zn lessons <terms>` when you are about to do something a lesson might cover.",
		`Work only in \`{p.viewDir or p.worktree}\`: it is your working directory. Never edit the main checkout.`,
		if p.viewDir
			then `Nobody will answer a question. Your verdict is your output: write the review to \`{p.stateDir}/review.md\` and nothing else.`
			else askText(p),
		"Never merge a pull request and never push to main yourself: the dispatcher merges at its gates, and `git` and `gh` refuse.",
		"Do not pass --time or --tokens. The dispatcher records this session's wall, CPU, tokens and model.",
	}
	-- c0262: a ticket's final review reads no exchange, its own or its parent run's (R0093's raft-level rule)
	if p.exchange and #p.exchange > 0 and not p.viewDir then
		local files = table.concat(p.exchange :: { string }, ", ")
		local format =
			`Each starts with \`date: <UTC time>\` (a question also has a \`step:\` line naming the step that asked) and a blank line; the rest is the message exactly as it was written. An \`-ask\` is the user's own request, a \`-question\` is what a step stopped to ask (a restatement is a question), and an \`-answer\` is the user's reply to the question before it (an approval or a correction).`
		local last = (p.exchange :: { string })[#(p.exchange :: { string })]
		local lastIsAnswer = string.find(last, "%-answer%.md$") ~= nil
		local text: string
		if #(p.exchange :: { string }) == 1 and string.find(last, "%-ask%.md$") ~= nil then
			-- only the user's request so far: no step has exchanged anything (code review 001 F5)
			text =
				`The user's own request for this run, word for word, is \`{p.stateDir}/exchange/{last}\`: read it before you start. It starts with \`date: <UTC time>\` and a blank line; the rest is the request exactly as it was written. No step has asked the user anything yet.`
		elseif p.exchangeAsker == p.step and p.exchangeLastStep == p.step and lastIsAnswer then
			text = `This is a re-run: you stopped this run with a question and the user has been asked. Before you start, read every file in \`{p.stateDir}/exchange/\`, in this order: {files}. {format} `
				.. (
					if p.exchangeNoReply
						then "The last file says the user gave no reply: your question stands unanswered, so decide whether you can go on without it, and if not write questions.md again and stop."
						elseif
							p.exchangeUnknownReply
						then "The last file says your question was copied when the user retried: read the question file. Text the user added to your question is their answer. If it holds only your question, the user gave no reply and your question stands, so decide whether you can go on without it, and if not write questions.md again and stop."
						else "The last file is an answer: it replies to your latest question, so do not ask again what it settles."
				)
		elseif p.exchangeAsker == p.step and p.exchangeLastStep == p.step then
			text =
				`This is a re-run: you stopped this run with a question. Before you start, read every file in \`{p.stateDir}/exchange/\`, in this order: {files}. {format} The last file is a question: it has no reply.`
		else
			text =
				`Earlier steps of this run have already exchanged messages with the user. Before you start, read every file in \`{p.stateDir}/exchange/\`, in this order: {files}. {format} They settle those steps' questions, not yours: an approval there is not an answer to a question you must ask the user.`
		end
		table.insert(lines, 4, text)
	end
	if p.parentExchange and #p.parentExchange > 0 and not p.viewDir then
		local parentFiles = p.parentExchange :: { string }
		local parentLast = parentFiles[#parentFiles]
		local parentText: string
		if #parentFiles == 1 and string.find(parentLast, "%-ask%.md$") ~= nil then
			-- only the user's request so far: no step of that run has exchanged anything (review 007 F7)
			parentText =
				`The user's own request for the run that started you, word for word, is \`{p.parentStateDir}/exchange/{parentLast}\`: read it before you start. No step of that run has asked the user anything yet. You only read it.`
		else
			parentText =
				`The run that started you has exchanged messages with the user too: read every file in \`{p.parentStateDir}/exchange/\`, in this order: {table.concat(
					parentFiles,
					", "
				)}. An answer there may settle a question you asked before. You only read them.`
		end
		table.insert(lines, 4, parentText)
	end
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
	blocked: string?, -- c0250: the reason when the item, or the raft that lists it, is blocked on origin/main
	blockedBy: string?, -- c0250: the blocked raft that lists this issue (blocked is that raft's reason)
	resolvedBy: string?, -- c0250: a raft, not blocked, that lists this issue and holds a resolution this run has not carried
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
	if f.blockedBy then
		return stop(
			dispatch.EXIT.user,
			`{f.id} waits on {f.blockedBy}, which is blocked ({f.blocked or "no reason"}): ./zn resolve {f.blockedBy} <decision>`
		)
	end
	if f.status == "blocked" then
		return stop(
			dispatch.EXIT.user,
			`{f.id} is blocked ({f.blocked or "no reason"}): ./zn resolve {f.id} <decision> (amend-design, approve, split, retry or abort)`
		)
	end
	if f.questions then
		return stop(
			dispatch.EXIT.user,
			"needs the user: read questions.md, then ./zn dispatch retry "
				.. f.id
				.. ' --answer "<your answer>" (or --answer-file <path>, or write your answer into questions.md)'
		)
	end
	if #f.openHuman > 0 then
		return stop(
			dispatch.EXIT.user,
			`needs the user: {f.id} has {table.concat(f.openHuman, ", ")} under ## Open to the human with no ruling; write escalation.md with them under ## Open findings or error and run {dispatch.blockCommand(
				f.id,
				if f.kind == "issue" and f.where == "active" and f.raft ~= "" then f.raft else nil,
				"review-exhausted"
			)} (the user rules with ./zn resolve {f.id} <decision> --rule <Fn>=\"<ruling>\", then ./zn rulings {f.id})`
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
