--!strict
-- c0250 AC8: the dispatcher's end of an item's block. A step that cannot go on writes escalation.md and runs
-- `./zn block`, the chain stops with exit 3 naming `./zn resolve`, `dispatch retry` waits for the resolve and then
-- carries the note's question and resolution into the re-run as the exchange's question and answer, and `--answer`
-- stays for a capture. The pure rule is dispatch.next; the rest runs the real dispatcher against fake CLIs
-- (@tests/lib/fakecli) in a fixture under .cache/c0250-dispatch-block.
local dispatch = require("@znile/engine/dispatch")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
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

local h: fakecli.Harness
local function issue(id: string, slug: string): string
	return trackerfix.stub(id, slug, "new-quiet-copper-falcon")
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
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
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
			t.expect(has(prompt, "/state/questions.md")).toBe(false)
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

	it("AC8: --answer is refused for an item and kept for a capture", function()
		-- an item: the answer is the resolution's
		local refused = zn({ "dispatch", "retry", "c0010", "--answer", "go ahead" })
		t.expect(refused.code).toBe(1)
		t.expect(has(refused.stdout, "the answer is the resolution's")).toBe(true)
		t.expect(has(refused.stdout, "./zn resolve c0010 <decision> --answer")).toBe(true)
		local file = `{h.f.base}/answer.txt`
		fs.writeFile(file, "go ahead\n")
		local viaFile = zn({ "dispatch", "retry", "c0010", "--answer-file", file })
		t.expect(viaFile.code).toBe(1)
		t.expect(has(viaFile.stdout, "the answer is the resolution's")).toBe(true)
		t.expect(exchangeFiles("c0010")).toEqual({ "001-question.md", "002-answer.md" })
		-- a capture: z-ticket asks in the local questions.md, and retry new --answer answers it
		fakecli.clear(h)
		fakecli.mode(h, "claude.z-ticket", "questions")
		local asked = zn({ "dispatch", "new", "a thing to capture" })
		t.expect(asked.code).toBe(3)
		t.expect(fs.isFile(`{dirOf("new")}/questions.md`)).toBe(true)
		fakecli.mode(h, "claude.z-ticket", "ok")
		local answered = zn({ "dispatch", "retry", "new", "--answer", "capture it as a chore" })
		t.expect(has(answered.stdout, "the answer is the resolution's")).toBe(false)
		local files = exchangeFiles("new")
		t.expect(files[#files]).toBe("003-answer.md")
		t.expect(has(fs.readFile(`{dirOf("new")}/exchange/{files[#files]}`), "capture it as a chore"))
			.toBe(true)
		t.expect(fs.isFile(`{dirOf("new")}/answered-1.md`)).toBe(true)
	end)
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
		t.expect(has(log, "write these questions")).toBe(false)
		t.expect(has(log, "$ZN_DISPATCH_DIR/questions.md")).toBe(false)
		t.expect(has(log, "review=3")).toBe(true) -- the nested step stopped for the user
	end)
end)
