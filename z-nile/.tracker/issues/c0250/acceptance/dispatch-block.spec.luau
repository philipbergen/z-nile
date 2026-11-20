--!strict
-- c0250 AC8: the dispatcher's end of an item's block. A step that cannot go on writes escalation.md and runs
-- `./zn block`, the chain stops with exit 3 naming `./zn resolve`, `dispatch retry` waits for the resolve and then
-- carries the note's question and resolution into the re-run as the exchange's question and answer. c0256's answer
-- path (`questions.md`, `retry --answer`) stays beside the block, for a capture and for a step that still writes it. The pure rule is dispatch.next; the rest runs the real dispatcher against fake CLIs
-- (@tests/lib/fakecli) in a fixture under .cache/c0250-dispatch-block.
local dispatch = require("@znile/engine/dispatch")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep"]
stall_seconds = 30

[roles.idea]
model = "claude-sonnet-5"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 5000
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []
]]

-- what the fake z-design does: claims the issue, files its note, and blocks the item, through the tracker's own
-- commands (the claim and the block reach main through the publish broker, as a real step's would)
local BLOCKING_STEP = [[
./zn status "$id" preparing
mkdir -p pickman/.tracker/issues/$id
cat > pickman/.tracker/issues/$id/escalation.md <<'NOTE'
## Question
Should c0010 depend on the json library, or write its own reader?

## What was tried
Two design drafts; the reviewer wants a reader and the design has none.

## Open findings or error
F1: no way to read the file.

## Options
- approve: take the library (recommended)
- retry: one more attempt
- amend-design: redesign it
NOTE
./zn block "$id" needs-decision
]]

-- a prepared raft with one member, ready to be readied (z-run's step runs on it): the documents `ready` accepts
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local RAFT_DOC =
	"---\nid: R0010\ntype: chore\ntitle: R0010\nslug: r0010\nsingle: false\nissues: [c0050]\ndesign: ready\nrank: 3\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# R0010\n\n## Theme\nThe theme.\n\n## Order & dependencies\nc0050\n"
-- a draft raft being rafted (claimed, preparing) that lists a prepared issue whose raft: is still empty on origin/main
local DRAFT_RAFT_DOC =
	"---\nid: R0040\ntype: chore\ntitle: R0040\nslug: r0040\nsingle: false\nissues: [c0110]\ndesign: draft\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# R0040\n\n## Theme\nThe theme.\n"
local LISTED_DOC =
	"---\nid: c0110\ntype: chore\ntitle: title c0110\nslug: c0110\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# c0110\n\n## Problem\nThe thing is slow.\n"
local MEMBER_DOC =
	"---\nid: c0050\ntype: chore\ntitle: title c0050\nslug: c0050\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\nrank: 7\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# c0050\n\n## Problem\nThe thing is slow.\n\n## Solution\nMake it fast.\n\n## Acceptance criteria\n- AC1: it is fast\n"

local h: fakecli.Harness
local function issue(id: string, slug: string): string
	-- with the Problem a Decided line goes into
	return trackerfix.stub(id, slug, "new-quiet-copper-falcon") .. "\n## Problem\nThe thing is slow.\n"
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(text, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local TERMINAL = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	ZN_DISPATCH = "",
	CLAUDE_EFFORT = "",
	ZN_ACTOR = "",
	ZN_HEADLESS = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
local function dirOf(id: string): string
	return `{h.f.main}/.cache/dispatch/{id}`
end
local function onOrigin(path: string): string
	return fixture.git(h.f.origin, { "show", `main:{path}` })
end
local function exchangeFiles(id: string): { string }
	local dir = `{dirOf(id)}/exchange`
	local names = if fs.isDir(dir) then fs.readDir(dir) else {}
	table.sort(names)
	return names
end

-- the facts the chain reads, for the pure rule: only what next looks at before it routes
local function facts(over: { [string]: any }): dispatch.Facts
	local base: { [string]: any } = {
		id = "c0010",
		folder = "pickman/.tracker/issues/c0010",
		root = "pickman/.tracker",
		kind = "issue",
		where = "backlog",
		status = "preparing",
		design = "draft",
		raft = "",
		ownClaim = true,
		localRaft = "",
		pr = nil,
		questions = false,
		blocked = nil,
		blockedBy = nil,
		resolvedBy = nil,
		openHuman = {},
		last = nil,
		uncovered = {},
		autoMerge = {},
		description = nil,
	}
	for k, v in over do
		base[k] = v
	end
	return base :: any
end

return t.spec("c0250 the dispatcher and a blocked item", function(it)
	it("sets up a tracker with .models.toml, an issue and the fake CLIs", function()
		h = fakecli.new("c0250-dispatch-block", {
			[".models.toml"] = MODELS,
			[".gitignore"] = ".cache/\n.worktree/\n/*/.tracker/rafts/active/*/prompt.md\n",
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
			["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "seventh-thing"),
			["pickman/.tracker/issues/c0080/c0080.md"] = issue("c0080", "eighth-thing"),
			["pickman/.tracker/issues/c0090/c0090.md"] = issue("c0090", "ninth-thing"),
			["pickman/.tracker/rafts/R0040/R0040.md"] = DRAFT_RAFT_DOC,
			["pickman/.tracker/issues/c0110/c0110.md"] = LISTED_DOC,
			["pickman/.tracker/rafts/R0010/R0010.md"] = RAFT_DOC,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0050/c0050.md"] = MEMBER_DOC,
			["pickman/.tracker/issues/c0050/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0050/acceptance/.gitkeep"] = "",
		})
	end)

	it(
		"AC8: a step that blocks stops the chain with exit 3 naming resolve, and next stops first on a blocked item",
		function()
			-- the pure rule: a blocked item stops the chain first, before any state it would otherwise route on
			for _, over in
				{
					{ status = "blocked", blocked = "red-gate" },
					{ status = "blocked", blocked = "quota", where = "backlog", kind = "raft", id = "R0010" },
					{ status = "blocked", blocked = "design-gap", questions = true, ownClaim = false },
					{ status = "blocked", blocked = "needs-decision", design = "ready", where = "backlog" },
				}
			do
				local action = dispatch.next(facts(over))
				t.expect(action.kind).toBe("stop")
				t.expect(action.code).toBe(dispatch.EXIT.user)
				local id = (over :: any).id or "c0010"
				t.expect(has(action.why or "", `{id} is blocked ({(over :: any).blocked})`)).toBe(true)
				t.expect(has(action.why or "", `./zn resolve {id} <decision>`)).toBe(true)
			end
			-- a preparing issue that is not blocked still routes as before
			local routed = dispatch.next(facts({ status = "preparing", ownClaim = true }))
			t.expect(routed.kind).toBe("step")
			-- an unruled open list is a block (review-exhausted); the chain's own stop on it is only a fallback and names
			-- the command that blocks
			local fallback = dispatch.next(facts({ openHuman = { "F2", "F5" } }))
			t.expect(fallback.kind).toBe("stop")
			t.expect(fallback.code).toBe(dispatch.EXIT.user)
			t.expect(has(fallback.why or "", "F2, F5 under ## Open to the human with no ruling")).toBe(true)
			t.expect(has(fallback.why or "", "./zn block c0010 review-exhausted")).toBe(true)
			t.expect(has(fallback.why or "", "./zn rulings c0010")).toBe(true)
			-- on a readied raft the fallback names the layer to block (design review 005 F4)
			local raftFallback = dispatch.next(facts({
				id = "R0010",
				kind = "raft",
				where = "active",
				status = "active",
				folder = "pickman/.tracker/rafts/active/R0010",
				openHuman = { "F2" },
			}))
			t.expect(raftFallback.kind).toBe("stop")
			t.expect(has(raftFallback.why or "", "./zn block R0010 review-exhausted --layer <issue>"))
				.toBe(true)
			-- the command a stop names: an issue in an active raft is blocked through its raft (the nested stop, the
			-- fallback and the prompt share it; design review 006 F3)
			t.expect(dispatch.blockCommand("c0010", nil, "<reason>")).toBe("./zn block c0010 <reason>")
			t.expect(dispatch.blockCommand("R0010", nil, "red-gate"))
				.toBe("./zn block R0010 red-gate --layer <issue>")
			t.expect(dispatch.blockCommand("c0050", "R0010", "<reason>"))
				.toBe("./zn block R0010 <reason> --layer c0050")
			-- the nested stop's words, one pure function for every place that prints it (design review 008 F1, F2)
			local own = dispatch.nestedStop("c0020", nil)
			t.expect(has(own, "this step needs the user, and only the step that started it can ask"))
				.toBe(true)
			t.expect(has(own, "writes escalation.md in c0020's folder and runs ./zn block c0020 <reason>"))
				.toBe(true)
			local layerStop = dispatch.nestedStop("c0050", "R0010")
			t.expect(
				has(
					layerStop,
					"writes escalation.md in R0010's folder and runs ./zn block R0010 <reason> --layer c0050"
				)
			).toBe(true)
			t.expect(has(layerStop, "c0050's folder")).toBe(false)
			-- the step a carried resolution is asked by: the model step the item resumes with, never a script step
			-- (design review 006 F2)
			t.expect(
				dispatch.resumeStep(
					facts({ id = "R0010", kind = "raft", where = "backlog", status = "prepared" })
				)
			).toBe("z-run")
			t.expect(
				dispatch.resumeStep(
					facts({ id = "R0010", kind = "raft", where = "active", status = "active" })
				)
			)
				.toBe("z-run")
			t.expect(dispatch.resumeStep(facts({ id = "c0110", status = "prepared", resolvedBy = "R0040" })))
				.toBe("z-raft")
			t.expect(dispatch.resumeStep(facts({ id = "c0010", status = "new" }))).toBe("z-design")
			t.expect(dispatch.resumeStep(facts({ id = "c0010", status = "preparing" }))).toBe("z-design")
			-- the prompt says to block, not to write questions.md, for a step on an item
			local prompt = dispatch.prompt({
				step = "z-design",
				id = "c0010",
				mode = nil,
				skillPath = "z-nile/skills/z-design/SKILL.md",
				worktree = "/w",
				stateDir = "/state",
				promptPath = nil,
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
			})
			t.expect(has(prompt, "escalation.md")).toBe(true)
			t.expect(has(prompt, "./zn block c0010 <")).toBe(true)
			-- a raft's block names the layer the step is on (design review 004 F1)
			t.expect(has(prompt, "--layer <issue>")).toBe(true)
			t.expect(has(prompt, "/state/questions.md")).toBe(false)
			-- under the dispatcher a step never lands layers itself, and an unruled open list is a block (F1, F7)
			t.expect(has(prompt, "do not run `./zn done`: the dispatcher lands the layers below (c0252)"))
				.toBe(true)
			t.expect(has(prompt, "run `./zn block c0010 review-exhausted`")).toBe(true)
			t.expect(has(prompt, "run `./zn rulings c0010`")).toBe(true)
			-- and a capture, which has no item yet, still writes the local questions.md
			local capture = dispatch.prompt({
				step = "z-ticket",
				id = "",
				mode = nil,
				skillPath = "z-nile/skills/z-ticket/SKILL.md",
				worktree = "/w",
				stateDir = "/state",
				promptPath = nil,
				streamWorktree = nil,
				description = "a thing",
				project = nil,
				exchange = nil,
				exchangeAsker = nil,
				exchangeNoReply = nil,
				exchangeUnknownReply = nil,
				exchangeLastStep = nil,
				parentExchange = nil,
				parentStateDir = nil,
			})
			t.expect(has(capture, "/state/questions.md")).toBe(true)
			t.expect(has(capture, "./zn block")).toBe(false)
			-- the real dispatcher: z-design blocks the item, and the chain stops with exit 3 naming resolve
			fakecli.clear(h)
			fakecli.mode(h, "claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, BLOCKING_STEP)
			local r = zn({ "dispatch", "c0010" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "c0010 is blocked (needs-decision)")).toBe(true)
			t.expect(has(r.stdout, "./zn resolve c0010 <decision>")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			-- the state is on origin/main, where every host sees it
			local doc = onOrigin("pickman/.tracker/issues/c0010/c0010.md")
			t.expect(string.match(doc, "\nstatus: blocked%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
			t.expect(has(doc, "\nblocked: needs-decision\n")).toBe(true)
			t.expect(has(onOrigin("pickman/.tracker/issues/c0010/escalation.md"), "Reason: needs-decision"))
				.toBe(true)
			-- no local questions.md: the note is the question
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(false)
			t.expect(fakecli.state(h, "c0010").outcome).toBe("ok")
			-- the question went into the run's exchange, asked by the step that blocked
			t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md" })
			local question = fs.readFile(`{dirOf("c0010")}/exchange/001-question.md`)
			t.expect(has(question, "step: z-design")).toBe(true)
			t.expect(has(question, "Should c0010 depend on the json library, or write its own reader?"))
				.toBe(true)
			-- a second run stops at once: no step starts on a blocked item
			local again = zn({ "dispatch", "c0010" })
			t.expect(again.code).toBe(3)
			t.expect(has(again.stdout, "c0010 is blocked (needs-decision)")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md" })
		end
	)

	it(
		"AC8: retry is refused while blocked, and after resolve the re-run step's exchange holds the question and the resolution as its answer",
		function()
			local before = count(fakecli.log(h), "claude step=z-design")
			local refused = zn({ "dispatch", "retry", "c0010" })
			t.expect(refused.code).toBe(1)
			t.expect(has(refused.stdout, "c0010 is blocked: ./zn resolve c0010 <decision> first")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(before)
			t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md" })
			-- an answer flag does not get past the block either: the answer is the resolution's
			for _, flag in
				{ { "--answer", "go ahead" }, { "--answer-file", `{h.f.base}/blocked-answer.txt` } }
			do
				fs.writeFile(`{h.f.base}/blocked-answer.txt`, "go ahead\n")
				local withAnswer = zn({ "dispatch", "retry", "c0010", flag[1], flag[2] })
				t.expect(withAnswer.code).toBe(1)
				t.expect(has(withAnswer.stdout, "c0010 is blocked: ./zn resolve c0010 <decision> first"))
					.toBe(true)
				t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(before)
				t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md" })
			end
			-- the human resolves it: the answer is the resolution's, in git
			local resolved = zn({ "resolve", "c0010", "approve", "--answer", "take the library" }, TERMINAL)
			t.expect(resolved.ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			-- the re-run: the exchange gets the resolution as the answer, and the step is told
			fakecli.mode(h, "claude", "ok")
			local retry = zn({ "dispatch", "retry", "c0010" })
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(before + 1)
			t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md", "002-answer.md" })
			local answer = fs.readFile(`{dirOf("c0010")}/exchange/002-answer.md`)
			t.expect(has(answer, "Decision: approve")).toBe(true)
			t.expect(has(answer, "Answer: take the library")).toBe(true)
			local log = fakecli.log(h)
			local ran = string.sub(log, string.find(log, "claude step=z-design mode=ok", 1, true) :: number)
			t.expect(has(ran, "This is a re-run: you stopped this run with a question")).toBe(true)
			t.expect(has(ran, "001-question.md, 002-answer.md")).toBe(true)
			t.expect(has(ran, "The last file is an answer")).toBe(true)
			-- a retry with nothing left to carry adds no second answer
			zn({ "dispatch", "retry", "c0010" })
			t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md", "002-answer.md" })
			t.expect(has(retry.stdout, "is blocked")).toBe(false)
		end
	)

	it(
		"AC8: c0256's answer path stays beside the block: an item whose step wrote questions.md, and a capture, are answered with --answer",
		function()
			-- after the resolve the item holds no question: an answer flag is refused as c0256 refuses it, and nothing moves
			local late = zn({ "dispatch", "retry", "c0010", "--answer", "go ahead" })
			t.expect(late.ok).toBe(false)
			t.expect(has(late.stdout .. late.stderr, "no question waits")).toBe(true)
			t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md", "002-answer.md" })
			-- an item whose step still writes questions.md: c0256's question stop, answered by retry --answer
			fakecli.clear(h)
			fakecli.mode(h, "claude.z-design", "questions")
			local asked = zn({ "dispatch", "c0040" })
			t.expect(asked.code).toBe(3)
			t.expect(has(asked.stdout, "needs the user")).toBe(true)
			t.expect(has(asked.stdout, "is blocked")).toBe(false)
			t.expect(fs.isFile(`{dirOf("c0040")}/questions.md`)).toBe(true)
			t.expect(exchangeFiles("c0040")).toEqual({ "001-question.md" })
			t.expect(has(onOrigin("pickman/.tracker/issues/c0040/c0040.md"), "\nblocked:")).toBe(false)
			fakecli.mode(h, "claude.z-design", "ok")
			local answered = zn({ "dispatch", "retry", "c0040", "--answer", "the small scope" })
			t.expect(has(answered.stdout .. answered.stderr, "the answer is the resolution's")).toBe(false)
			t.expect(exchangeFiles("c0040")).toEqual({ "001-question.md", "002-answer.md" })
			t.expect(has(fs.readFile(`{dirOf("c0040")}/exchange/002-answer.md`), "the small scope"))
				.toBe(true)
			t.expect(fs.isFile(`{dirOf("c0040")}/answered-1.md`)).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design mode=ok")).toBe(1)
			-- a capture: z-ticket asks in the local questions.md, and retry new --answer answers it
			fakecli.clear(h)
			fakecli.mode(h, "claude.z-ticket", "questions")
			local capture = zn({ "dispatch", "new", "a thing to capture" })
			t.expect(capture.code).toBe(3)
			t.expect(fs.isFile(`{dirOf("new")}/questions.md`)).toBe(true)
			fakecli.mode(h, "claude.z-ticket", "ok")
			local captured = zn({ "dispatch", "retry", "new", "--answer", "capture it as a chore" })
			t.expect(has(captured.stdout, "the answer is the resolution's")).toBe(false)
			local files = exchangeFiles("new")
			t.expect(files[#files]).toBe("003-answer.md")
			t.expect(has(fs.readFile(`{dirOf("new")}/exchange/{files[#files]}`), "capture it as a chore"))
				.toBe(true)
			t.expect(fs.isFile(`{dirOf("new")}/answered-1.md`)).toBe(true)
		end
	)
	it("AC8: a nested step that needs the user tells its author to block the item", function()
		-- the author (z-design) starts its review through the dispatcher, as the headless rule says; the reviewer asks
		fakecli.clear(h)
		fakecli.mode(h, "claude.z-design", "author")
		fakecli.mode(h, "claude.zz-review", "questions")
		zn({ "dispatch", "z-design", "c0020" })
		local log = fakecli.log(h)
		t.expect(has(log, "claude step=zz-review mode=questions")).toBe(true)
		-- the review's stop names the command its author runs, not a questions.md of its own
		t.expect(has(log, "this step needs the user, and only the step that started it can ask")).toBe(true)
		t.expect(has(log, "./zn block c0020 <reason>")).toBe(true)
		t.expect(has(log, "writes escalation.md in c0020's folder")).toBe(true) -- the item's own folder (design review 008 F1)
		t.expect(has(log, "write these questions")).toBe(false)
		t.expect(has(log, "$ZN_DISPATCH_DIR/questions.md")).toBe(false)
		t.expect(has(log, "review=1")).toBe(true) -- the nested step failed: its questions.md is set aside, never read
	end)
	it(
		"AC8: an unruled open list blocks with review-exhausted, and ./zn dispatch <id> after the resolve carries the resolution",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude", "script")
			-- the step records the open list in the item's document, as z-design 5.4 says, and blocks it
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[
./zn status "$id" preparing
printf '\n## Open to the human\n- F2: the reader is missing. Answer: refuted. Decision: keep it or not?\n- F5: the cache. Answer: refuted. Decision: defer it?\n' >> pickman/.tracker/issues/$id/$id.md
cat > pickman/.tracker/issues/$id/escalation.md <<'NOTE'
## Question
Rule on F2 and F5.

## What was tried
One review round and one revision.

## Open findings or error
- F2: the reader is missing. Answer: refuted. Decision: keep it or not?
- F5: the cache. Answer: refuted. Decision: defer it?

## Options
- retry: go on with your rulings (recommended)
- abort: stop
NOTE
./zn block "$id" review-exhausted
]]
			)
			local r = zn({ "dispatch", "c0030" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "c0030 is blocked (review-exhausted)")).toBe(true)
			local note = onOrigin("pickman/.tracker/issues/c0030/escalation.md")
			t.expect(has(note, "Reason: review-exhausted\n")).toBe(true)
			t.expect(has(note, "\nOpen: F2, F5\n")).toBe(true)
			t.expect(
				has(
					note,
					'resolve c0030 retry --answer "<your answer>" --rule F2="<your ruling>" --rule F5="<your ruling>"'
				)
			).toBe(true)
			t.expect(exchangeFiles("c0030")).toEqual({ "001-question.md" })
			-- the user resolves it with a ruling per open id; the next chain run copies the resolution first
			local before = count(fakecli.log(h), "claude step=")
			local noRules = zn({ "resolve", "c0030", "retry", "--answer", "go on" }, TERMINAL)
			t.expect(noRules.ok).toBe(false)
			local resolved = zn({
				"resolve",
				"c0030",
				"retry",
				"--answer",
				"go on",
				"--rule",
				"F2=keep the reader",
				"--rule",
				"F5=defer the cache",
			}, TERMINAL)
			t.expect(resolved.ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			fs.writeFile(`{h.fakes}/script.sh`, './zn status "$id" preparing\n') -- the re-run step claims the item again
			zn({ "dispatch", "c0030" }) -- not `retry`: the plain chain resumes the item
			t.expect(count(fakecli.log(h), "claude step=") > before).toBe(true)
			t.expect(exchangeFiles("c0030")).toEqual({ "001-question.md", "002-answer.md" })
			local answer = fs.readFile(`{dirOf("c0030")}/exchange/002-answer.md`)
			t.expect(has(answer, "Decision: retry")).toBe(true)
			t.expect(has(answer, "Answer: go on")).toBe(true)
			local log = fakecli.log(h)
			t.expect(has(log, "The last file is an answer")).toBe(true)
		end
	)

	it(
		"AC8: a step that blocks and also leaves questions.md: the block is the question, and the file is set aside unread",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				BLOCKING_STEP .. [[printf '## Q1\nWhich scope?\n' > "$ZN_DISPATCH_DIR/questions.md"
]]
			)
			local r = zn({ "dispatch", "c0060" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "c0060 is blocked (needs-decision)")).toBe(true)
			t.expect(has(r.stdout, "./zn resolve c0060 <decision>")).toBe(true)
			-- one question in the exchange, the note's, asked by the step that blocked
			t.expect(exchangeFiles("c0060")).toEqual({ "001-question.md" })
			local question = fs.readFile(`{dirOf("c0060")}/exchange/001-question.md`)
			t.expect(has(question, "Should c0010 depend on the json library")).toBe(true)
			t.expect(has(question, "Which scope?")).toBe(false)
			-- the file is set aside, never answered: no question waits outside the block
			t.expect(fs.isFile(`{dirOf("c0060")}/questions.md`)).toBe(false)
			t.expect(fs.isFile(`{dirOf("c0060")}/questions-refused-1.md`)).toBe(true)
			t.expect(has(fs.readFile(`{dirOf("c0060")}/questions-refused-1.md`), "Which scope?")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, "questions-refused-1.md")).toBe(true)
			-- and the block holds: retry is refused until the resolve
			local refused = zn({ "dispatch", "retry", "c0060", "--answer", "the small scope" })
			t.expect(refused.code).toBe(1)
			t.expect(has(refused.stdout, "c0060 is blocked: ./zn resolve c0060 <decision> first")).toBe(true)
			t.expect(exchangeFiles("c0060")).toEqual({ "001-question.md" })
		end
	)
	it("AC8: the resolution reaches the next step on a host that never saw the block, once", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude", "script")
		fs.writeFile(`{h.fakes}/script.sh`, BLOCKING_STEP)
		t.expect(zn({ "dispatch", "c0070" }).code).toBe(3)
		local resolved = zn({ "resolve", "c0070", "retry", "--answer", "use the library" }, TERMINAL)
		t.expect(resolved.ok).toBe(true)
		fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		-- another host: no run state and no exchange for the item
		fs.removeDir(dirOf("c0070"))
		fs.writeFile(`{h.fakes}/script.sh`, './zn status "$id" preparing\n')
		local before = count(fakecli.log(h), "claude step=z-design")
		zn({ "dispatch", "c0070" })
		t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(before + 1)
		-- the note's question, asked by the step the chain resumes, then the resolution as its answer
		t.expect(exchangeFiles("c0070")).toEqual({ "001-question.md", "002-answer.md" })
		local question = fs.readFile(`{dirOf("c0070")}/exchange/001-question.md`)
		t.expect(has(question, "step: z-design")).toBe(true)
		t.expect(has(question, "Should c0010 depend on the json library, or write its own reader?"))
			.toBe(true)
		local answer = fs.readFile(`{dirOf("c0070")}/exchange/002-answer.md`)
		t.expect(has(answer, "Decision: retry")).toBe(true)
		t.expect(has(answer, "Answer: use the library")).toBe(true)
		t.expect(has(fakecli.log(h), "The last file is an answer")).toBe(true)
		-- carried once: the note stays in the folder, and the next run adds nothing
		zn({ "dispatch", "retry", "c0070" })
		t.expect(exchangeFiles("c0070")).toEqual({ "001-question.md", "002-answer.md" })
	end)

	it(
		"AC8: a step started by hand on a blocked item starts nothing, and one started after the resolve carries it",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, BLOCKING_STEP)
			t.expect(zn({ "dispatch", "c0080" }).code).toBe(3)
			local steps = count(fakecli.log(h), "claude step=")
			for _, argv in
				{
					{ "dispatch", "z-design", "c0080" },
					{ "dispatch", "zz-review", "c0080", "--mode", "design" },
				}
			do
				local r = zn(argv)
				t.expect(r.code).toBe(3)
				t.expect(has(r.stdout, "c0080 is blocked (needs-decision): ./zn resolve c0080 <decision>"))
					.toBe(true)
				t.expect(count(fakecli.log(h), "claude step=")).toBe(steps)
				t.expect(exchangeFiles("c0080")).toEqual({ "001-question.md" })
			end
			t.expect(zn({ "resolve", "c0080", "retry", "--answer", "go on" }, TERMINAL).ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			fs.writeFile(`{h.fakes}/script.sh`, 'ls "$ZN_DISPATCH_DIR/exchange" > "$FAKE_DIR/seen"\n')
			local designs = count(fakecli.log(h), "claude step=z-design")
			zn({ "dispatch", "z-design", "c0080" })
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(designs + 1)
			-- the answer was in the exchange before the step started
			local seen = fs.readFile(`{h.fakes}/seen`)
			t.expect(has(seen, "001-question.md")).toBe(true)
			t.expect(has(seen, "002-answer.md")).toBe(true)
			t.expect(has(fs.readFile(`{dirOf("c0080")}/exchange/002-answer.md`), "Answer: go on")).toBe(true)
		end
	)

	it(
		"AC8: a c0256 question still waiting when the item is resolved is set aside, and the resolution is the answer",
		function()
			-- c0256's stop on the item: its question waits in the main checkout
			fakecli.clear(h)
			fakecli.mode(h, "claude.z-design", "questions")
			t.expect(zn({ "dispatch", "c0090" }).code).toBe(3)
			t.expect(fs.isFile(`{dirOf("c0090")}/questions.md`)).toBe(true)
			-- the item is claimed and blocked from a worktree (an interactive worker, or another host)
			local wt = `{h.f.base}/w-c0090`
			fixture.git(h.f.main, { "worktree", "add", "-q", "--detach", wt, "origin/main" })
			local env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_AGENT_TOKEN_FILE = h.token,
				GH_TOKEN = "the-users-token",
			}
			for k, v in TERMINAL do
				env[k] = v
			end
			t.expect(
				fixture.exec(
					wt,
					"bash",
					{ "scripts/tracker.sh", "status", "c0090", "preparing" },
					{ env = env }
				).ok
			).toBe(true)
			fs.writeFile(
				`{wt}/pickman/.tracker/issues/c0090/escalation.md`,
				"## Question\nTake the library?\n\n## What was tried\nOne draft.\n\n## Open findings or error\nNone.\n\n## Options\n- retry: go on (recommended)\n- abort: stop\n"
			)
			t.expect(
				fixture.exec(
					wt,
					"bash",
					{ "scripts/tracker.sh", "block", "c0090", "needs-decision" },
					{ env = env }
				).ok
			).toBe(true)
			t.expect(zn({ "resolve", "c0090", "retry", "--answer", "take it" }, TERMINAL).ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			-- an answer flag does not answer the old question past the resolution
			local flagged = zn({ "dispatch", "retry", "c0090", "--answer", "the small scope" })
			t.expect(flagged.code).toBe(1)
			t.expect(has(flagged.stdout .. flagged.stderr, "the resolution answered it")).toBe(true)
			t.expect(exchangeFiles("c0090")).toEqual({ "001-question.md" })
			t.expect(fs.isFile(`{dirOf("c0090")}/questions.md`)).toBe(true)
			-- the resume: the old question is closed with no reply, the note's question and the resolution follow
			fakecli.mode(h, "claude.z-design", "ok")
			local resumed = zn({ "dispatch", "retry", "c0090" })
			t.expect(exchangeFiles("c0090"))
				.toEqual({ "001-question.md", "002-answer.md", "003-question.md", "004-answer.md" })
			t.expect(
				has(
					fs.readFile(`{dirOf("c0090")}/exchange/002-answer.md`),
					"(no reply: the item was blocked, and its resolution answers in the next message)"
				)
			).toBe(true)
			t.expect(has(fs.readFile(`{dirOf("c0090")}/exchange/003-question.md`), "Take the library?"))
				.toBe(true)
			local answer = fs.readFile(`{dirOf("c0090")}/exchange/004-answer.md`)
			t.expect(has(answer, "Decision: retry")).toBe(true)
			t.expect(has(answer, "Answer: take it")).toBe(true)
			t.expect(has(answer, "the small scope")).toBe(false)
			t.expect(fs.isFile(`{dirOf("c0090")}/questions.md`)).toBe(false)
			t.expect(fs.isFile(`{dirOf("c0090")}/questions-refused-1.md`)).toBe(true)
			t.expect(has(resumed.stdout .. resumed.stderr, "questions-refused-1.md")).toBe(true)
			fixture.git(h.f.main, { "worktree", "remove", "--force", wt })
		end
	)

	it(
		"AC8: an issue a blocked draft raft lists waits on it, and its next step carries the raft's resolution once",
		function()
			-- the pure rule: an issue listed by a blocked raft stops first, naming the raft to resolve
			local action = dispatch.next(facts({
				id = "c0110",
				status = "prepared",
				design = "ready",
				ownClaim = false,
				blocked = "needs-decision",
				blockedBy = "R0040",
			}))
			t.expect(action.kind).toBe("stop")
			t.expect(action.code).toBe(dispatch.EXIT.user)
			t.expect(action.why)
				.toBe("c0110 waits on R0040, which is blocked (needs-decision): ./zn resolve R0040 <decision>")
			-- the rafting worktree blocks the draft raft (as a dispatched z-raft would)
			local wt = `{h.f.base}/w-R0040`
			fixture.git(h.f.main, { "worktree", "add", "-q", "--detach", wt, "origin/main" })
			local env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_AGENT_TOKEN_FILE = h.token,
				GH_TOKEN = "the-users-token",
			}
			for k, v in TERMINAL do
				env[k] = v
			end
			fs.writeFile(
				`{wt}/pickman/.tracker/rafts/R0040/escalation.md`,
				"## Question\nShould c0110 and c0120 share one raft?\n\n## What was tried\nOne grouping.\n\n## Open findings or error\nNone.\n\n## Options\n- retry: group them (recommended)\n- abort: stop\n"
			)
			t.expect(
				fixture.exec(
					wt,
					"bash",
					{ "scripts/tracker.sh", "block", "R0040", "needs-decision" },
					{ env = env }
				).ok
			).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			fakecli.clear(h)
			fakecli.mode(h, "claude", "ok")
			local WAITS =
				"c0110 waits on R0040, which is blocked (needs-decision): ./zn resolve R0040 <decision>"
			local chain = zn({ "dispatch", "c0110" })
			t.expect(chain.code).toBe(3)
			t.expect(has(chain.stdout, WAITS)).toBe(true)
			local hand = zn({ "dispatch", "z-design", "c0110" })
			t.expect(hand.code).toBe(3)
			t.expect(has(hand.stdout, WAITS)).toBe(true)
			local retry = zn({ "dispatch", "retry", "c0110" })
			t.expect(retry.code).toBe(1)
			t.expect(has(retry.stdout, "R0040 is blocked: ./zn resolve R0040 <decision> first")).toBe(true)
			t.expect(fakecli.log(h)).toBe("")
			-- resolved, the raft is new again and no longer blocked: the issue's next step still carries the raft's
			-- resolution, once, as z-raft's question and its answer (design review 005 F3)
			t.expect(zn({ "resolve", "R0040", "retry", "--answer", "group them" }, TERMINAL).ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			zn({ "dispatch", "z-raft", "c0110" })
			t.expect(count(fakecli.log(h), "claude step=z-raft")).toBe(1)
			t.expect(exchangeFiles("c0110")).toEqual({ "001-question.md", "002-answer.md" })
			local raftQuestion = fs.readFile(`{dirOf("c0110")}/exchange/001-question.md`)
			t.expect(has(raftQuestion, "step: z-raft")).toBe(true)
			t.expect(has(raftQuestion, "Should c0110 and c0120 share one raft?")).toBe(true)
			t.expect(has(fs.readFile(`{dirOf("c0110")}/exchange/002-answer.md`), "Answer: group them"))
				.toBe(true)
			t.expect(has(fakecli.log(h), "The last file is an answer")).toBe(true)
			zn({ "dispatch", "z-raft", "c0110" })
			t.expect(exchangeFiles("c0110")).toEqual({ "001-question.md", "002-answer.md" })
			fixture.git(h.f.main, { "worktree", "remove", "--force", wt })
		end
	)

	it(
		"AC8: a dispatched z-run step blocks an active raft: the chain stops with exit 3 and the move is on origin/main",
		function()
			fakecli.clear(h)
			local readied = zn({ "ready", "R0010" }, TERMINAL)
			t.expect(readied.ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			fakecli.mode(h, "claude", "script")
			-- the step is in the raft's worktree; it does not run ./zn done (a dispatched step never lands layers)
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[
cat > pickman/.tracker/rafts/active/R0010/escalation.md <<'NOTE'
## Question
The gate on c0050 stays red after two attempts: retry, or redesign?

## What was tried
Two fix attempts.

## Open findings or error
check.sh: AC1 failed.

## Options
- retry: one more attempt (recommended)
- amend-design: redesign c0050
NOTE
./zn block R0010 red-gate
]]
			)
			local r = zn({ "dispatch", "R0010" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "R0010 is blocked (red-gate)")).toBe(true)
			t.expect(has(r.stdout, "./zn resolve R0010 <decision>")).toBe(true)
			t.expect(has(fakecli.log(h), "claude step=z-run")).toBe(true)
			-- the raft and its member left active/ on origin/main, blocked, with the note beside the raft
			local raft = onOrigin("pickman/.tracker/rafts/R0010/R0010.md")
			t.expect(string.match(raft, "\nstatus: blocked%-%a+%-%a+%-%a+\n") ~= nil).toBe(true)
			t.expect(has(raft, "\nblocked: red-gate\n")).toBe(true)
			t.expect(
				has(onOrigin("pickman/.tracker/rafts/R0010/escalation.md"), "From: active\nLayer: c0050\n")
			)
				.toBe(true)
			t.expect(has(onOrigin("pickman/.tracker/issues/c0050/c0050.md"), "\nblocked: red-gate\n"))
				.toBe(true)
			local listed = fixture.git(h.f.origin, { "ls-tree", "-r", "--name-only", "main" })
			t.expect(has(listed, "pickman/.tracker/rafts/active/R0010/")).toBe(false)
			t.expect(has(listed, "pickman/.tracker/issues/active/c0050/")).toBe(false)
			t.expect(has(listed, "pickman/.tracker/rafts/done/R0010/")).toBe(false) -- no ./zn done was run
			-- a second run stops at once, with no new step
			local steps = count(fakecli.log(h), "claude step=")
			local again = zn({ "dispatch", "R0010" })
			t.expect(again.code).toBe(3)
			t.expect(count(fakecli.log(h), "claude step=")).toBe(steps)
		end
	)

	it(
		"AC8: a resolved raft's z-run is told the resolution answers its own question, on a host that never saw the block",
		function()
			t.expect(zn({ "resolve", "R0010", "retry", "--answer", "one more attempt" }, TERMINAL).ok)
				.toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			t.expect(zn({ "ready", "R0010" }, TERMINAL).ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			-- another host: no run state and no exchange for the raft
			fs.removeDir(dirOf("R0010"))
			fakecli.clear(h)
			fakecli.mode(h, "claude", "ok")
			zn({ "dispatch", "R0010" })
			local log = fakecli.log(h)
			t.expect(has(log, "claude step=z-run")).toBe(true)
			t.expect(exchangeFiles("R0010")).toEqual({ "001-question.md", "002-answer.md" })
			local question = fs.readFile(`{dirOf("R0010")}/exchange/001-question.md`)
			t.expect(has(question, "step: z-run")).toBe(true)
			t.expect(has(question, "The gate on c0050 stays red after two attempts")).toBe(true)
			t.expect(has(fs.readFile(`{dirOf("R0010")}/exchange/002-answer.md`), "Answer: one more attempt"))
				.toBe(true)
			local ran = string.sub(log, string.find(log, "claude step=z-run", 1, true) :: number)
			t.expect(has(ran, "The last file is an answer")).toBe(true)
			t.expect(has(ran, "They settle those steps' questions")).toBe(false)
		end
	)
	it(
		"AC8: a review started on a layer of a readied raft that needs the user tells its author to block the raft, in the raft's folder",
		function()
			-- R0010 is readied again (the case above); its z-run starts a review of the layer c0050, which asks
			fakecli.clear(h)
			fakecli.mode(h, "claude.z-run", "script")
			fakecli.mode(h, "claude.zz-review", "questions")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[( while :; do echo '{"type":"system"}'; sleep 0.5; done ) & hb=$!; ./zn dispatch zz-review c0050 --mode design >> "$FAKE_DIR/log" 2>&1; echo "review=$?" >> "$FAKE_DIR/log"; kill $hb
]]
			)
			zn({ "dispatch", "z-run", "R0010" }) -- a one-step run: the chain's last z-run ended ok
			local log = fakecli.log(h)
			t.expect(has(log, "claude step=zz-review mode=questions")).toBe(true)
			t.expect(has(log, "only the step that started it can ask")).toBe(true)
			t.expect(has(log, "writes escalation.md in R0010's folder")).toBe(true)
			t.expect(has(log, "./zn block R0010 <reason> --layer c0050")).toBe(true)
			t.expect(has(log, "escalation.md in c0050's folder")).toBe(false)
			t.expect(has(log, "./zn block c0050 <reason>")).toBe(false)
		end
	)
end)
