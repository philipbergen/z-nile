--!strict
-- c0260 AC8 and AC4 (design-review-012 F1 and F5, design-review-013 F1 to F5): a dispatched z-design confirms an
-- unattended capture through c0250's block, and z-work never offers it as a draft. The real dispatcher runs against fake
-- CLIs (@tests/lib/fakecli) in a fixture under .cache/c0260-dispatch: the fake z-design claims the ticket, files its
-- note and blocks it; the user resolves; while the idea is still Unconfirmed the re-run blocks again, never stopping on
-- the open list of the run's own (older) copy of the document; once the user has ruled and confirmed in the prep
-- worktree, the re-run goes on to z-design.
local capturecheck = require("@znile/engine/capturecheck")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ideaMod = require("@znile/engine/idea")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local MODELS = [[
[dispatch]
stall_seconds = 30

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

-- An unattended capture as c0260 leaves it: marked, challenged, the Ask and the Interview recorded, a question for the
-- user left open (or, `approved`, nothing open), and the Confirmation's dispatched line. `confirmed` adds the user's
-- line after it.
local function ticket(id: string, slug: string, confirmed: boolean, approved: boolean?): string
	local doc = table.concat({
		"---",
		`id: {id}`,
		"type: chore",
		`title: title {id}`,
		`slug: {slug}`,
		"raft: ",
		"depends_on: []",
		"emergent: false",
		"idea: challenged",
		"design: draft",
		"capture: required",
		"created: 2026-11-10",
		"status: new-quiet-copper-falcon",
		"---",
		"",
		`# {id}`,
		"",
		"## Problem",
		"- Every ghost sounds the same.",
		"",
		"## Solution",
		"- Every ghost gets a scarier sound.",
		"",
		"## Non-goals",
		"- Ghost speed does not change.",
		"",
		"## Open to the human",
		if approved then "none" else "- F1: ask: which ghost first?",
		"",
		"## Ask (verbatim)",
		"### Message 2026-11-07",
		"```",
		"make the ghosts scarier",
		"```",
		"",
		"## Interview",
		"### Q1",
		"Question: how?",
		"Answer: sound",
		"",
		"## Confirmation",
		"Unconfirmed (unattended, 2026-11-07) after round 1: dispatched capture",
		"",
	}, "\n")
	if confirmed then
		doc = (
			string.gsub(
				doc,
				"%- F1: ask: which ghost first%?",
				"- F1: ask: which ghost first? Ruled (user, 2026-11-08): Blinky."
			)
		)
		doc ..= 'Confirmed (Ann, 2026-11-08) after round 1: "yes"\n'
	end
	return doc
end
local function review(doc: string, approved: boolean?): string
	if approved then
		return ideaMod.reviewText({}, "approve", 1, capturecheck.roundState(doc))
	end
	local found = ideaMod.parseReview("## Findings\n- F1: ask: which ghost first?\n\n## Verdict\nrevise\n")
	return ideaMod.reviewText(found, "revise", 1, capturecheck.roundState(doc))
end

-- what the fake z-design does on an unconfirmed idea, as the z-design bullet says: claim, file the note, block
local BLOCKING_STEP = [[
./zn status "$id" preparing
mkdir -p pickman/.tracker/issues/$id
cat > pickman/.tracker/issues/$id/escalation.md <<'NOTE'
## Question
Confirm the idea of this ticket as it stands: the Problem, Solution and Non-goals, and the open point F1.

## What was tried
The capture ran unattended.

## Open findings or error
- F1: ask: which ghost first?

## Options
- retry: confirm the idea, and z-design then designs it (recommended)
- abort: the idea is not what you meant: change it in a capture first (z-ticket 4a)
NOTE
./zn block "$id" needs-decision
]]

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

local h: fakecli.Harness
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
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
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
local OPEN_STOP = "under ## Open to the human with no ruling"

return t.spec("c0260 a dispatched capture is confirmed through the block", function(it)
	it("sets up an unconfirmed capture, a confirmed one, and the fake CLIs", function()
		local waiting = ticket("c0010", "first-thing", false)
		local approvedWaiting = ticket("c0030", "third-thing", false, true)
		local approvedDone = ticket("c0020", "second-thing", true, true)
		t.expect(capturecheck.check(waiting, { ["idea-review-001.md"] = review(waiting) })).toEqual({})
		h = fakecli.new("c0260-dispatch", {
			[".models.toml"] = MODELS,
			[".gitignore"] = ".cache/\n.worktree/\n",
			["z-nile/.tracker/capture-since"] = "marker\n",
			["pickman/.tracker/issues/c0010/c0010.md"] = waiting,
			["pickman/.tracker/issues/c0010/idea-review-001.md"] = review(waiting),
			["pickman/.tracker/issues/c0030/c0030.md"] = approvedWaiting,
			["pickman/.tracker/issues/c0030/idea-review-001.md"] = review(approvedWaiting, true),
			["pickman/.tracker/issues/c0020/c0020.md"] = approvedDone,
			["pickman/.tracker/issues/c0020/idea-review-001.md"] = review(
				ticket("c0020", "second-thing", false, true),
				true
			),
		})
	end)

	it(
		"AC4: z-work's draft pick names an Unconfirmed idea as the person's and offers a confirmed one",
		function()
			-- c0030's loop approved with nothing open: only the confirmation keeps it from the draft pick
			local waiting = zn({ "work", "next", "c0030" })
			t.expect(has(waiting.stdout, "the idea waits for the person's confirmation")).toBe(true)
			t.expect(has(waiting.stdout, "Design c0030 in guess mode")).toBe(false)
			local ready = zn({ "work", "next", "c0020" })
			t.expect(has(ready.stdout, "Design c0020 in guess mode")).toBe(true)
		end
	)

	it(
		"AC8: the dispatched z-design blocks an unconfirmed idea, and a resolve without the confirmation blocks it again, never stopping on the open list",
		function()
			fakecli.mode(h, "claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, BLOCKING_STEP)
			local r = zn({ "dispatch", "c0010" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "c0010 is blocked (needs-decision)")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			-- the user resolves without confirming: the run's prep worktree still holds the unruled, unconfirmed copy
			t.expect(zn({ "resolve", "c0010", "retry" }, TERMINAL).ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			local again = zn({ "dispatch", "retry", "c0010" })
			t.expect(has(again.stdout, OPEN_STOP)).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(2)
			t.expect(again.code).toBe(3)
			t.expect(has(again.stdout, "c0010 is blocked (needs-decision)")).toBe(true)
		end
	)

	it(
		"AC8: once the user has ruled and confirmed in the prep worktree and resolved, the re-run goes on to z-design",
		function()
			local wt = `{h.f.main}/.worktree/prep-first-thing`
			t.expect(fs.isDir(wt)).toBe(true)
			local path = `{wt}/pickman/.tracker/issues/c0010/c0010.md`
			fs.writeFile(
				path,
				(
					string.gsub(
						fs.readFile(path),
						"%- F1: ask: which ghost first%?",
						"- F1: ask: which ghost first? Ruled (user, 2026-11-08): Blinky."
					)
				)
			)
			local env: { [string]: string } = { PATH = `{h.bin}:{process.env.PATH}`, FAKE_DIR = h.fakes }
			for k, v in TERMINAL do
				env[k] = v
			end
			local c = fixture.exec(
				wt,
				"bash",
				{ "scripts/tracker.sh", "idea", "c0010", "--confirm", "yes" },
				{ env = env }
			)
			if not c.ok then
				error(`--confirm in the prep worktree failed: {c.stderr}{c.stdout}`, 0)
			end
			t.expect(has(fs.readFile(path), 'after round 1: "yes"')).toBe(true)
			fixture.git(wt, { "add", "-A", "pickman/.tracker/issues/c0010" })
			fixture.git(wt, { "commit", "-q", "-m", "tracker: c0010 confirmed" })
			t.expect(zn({ "resolve", "c0010", "retry" }, TERMINAL).ok).toBe(true)
			fixture.git(h.f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			fakecli.mode(h, "claude", "ok")
			local last = zn({ "dispatch", "retry", "c0010" })
			t.expect(has(last.stdout, OPEN_STOP)).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(3)
			fs.removeDir(h.f.base)
		end
	)
end)
