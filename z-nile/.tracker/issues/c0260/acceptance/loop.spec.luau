--!strict
-- c0260 AC12 (the user's ruling of 2026-11-13, F15): `./zn idea` loops. The challenger reviews, the author revises and
-- answers, and the challenger reviews the revised idea again, until it approves or has challenged idea.MAX_ROUNDS (5, the
-- owner's cap, ruled for c0260 on 2026-11-19) times; the cases read the cap from the module, and one pins the number; the last
-- challenge is never followed by a revision. Each pass is a review (and, with findings the author answered, a refute)
-- file numbered on from the last and written when the pass completes; a finding raised for the user (`ask:`) and what the
-- last challenge found stay open; the model that wrote a text never challenges it, a fallback included; a dispatched run
-- beats. An agent-filed ticket (F6) runs the same loop. Stub CLIs only; a fixture under .cache/c0260-loop.
local capturecheck = require("@znile/engine/capturecheck")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ideaMod = require("@znile/engine/idea")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local CAP = ideaMod.MAX_ROUNDS

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local ROLES = [[
[dispatch]
stall_seconds = 30

[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = []

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = []
]]

-- Both roles carry an effort and the same fallbacks, as the real .models.toml does: a model's id then differs between
-- the author's use and the challenger's, which is what an exclusion by id would miss.
local WITH_FALLBACKS = [[
[dispatch]
stall_seconds = 30

[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
effort = "medium"
fallbacks = FALLBACKS

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
effort = "xhigh"
author = "idea"
fallbacks = FALLBACKS
]]

local function rolesWith(fallbacks: string): string
	return (string.gsub(WITH_FALLBACKS, "FALLBACKS", fallbacks))
end

-- The challenger's call number n replies by the n-th word of $LOOP_REPLIES (f: a finding, a: approve, af: approve with a
-- finding, r0: revise with none, ask: a question for the user, mix: a question and a finding); with none it finds fault
-- for its first $LOOP_UNTIL calls and approves after. $LOOP_FAIL_AT makes that call exit 1. The author answers every
-- finding revised or disputed ($LOOP_ANSWER), changes the Solution when it revises, and can fail after its first call
-- ($LOOP_FABLE_ONCE). Every prompt is logged by role.
local CLAUDE = [=[#!/bin/bash
args="$*"
if [[ "$args" == *opus* ]]; then
  echo "$args" >> "$LOOP_LOG.challenge"
  n=$(cat "$LOOP_LOG.count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$LOOP_LOG.count"
  if [[ "$n" == "$LOOP_FAIL_AT" ]]; then echo "quota" >&2; exit 1; fi
  reply=$(echo "$LOOP_REPLIES" | cut -d, -f$n)
  if [[ -z "$reply" ]]; then if [[ $n -le ${LOOP_UNTIL:-0} ]]; then reply=f; else reply=a; fi; fi
  case $reply in
    f) printf '## Findings\n- F1: finding from call %s.\n\n## Verdict\nrevise\n' $n ;;
    af) printf '## Findings\n- F1: finding from call %s.\n\n## Verdict\napprove\n' $n ;;
    r0) printf '## Findings\n- none\n\n## Verdict\nrevise\n' ;;
    ask) printf '## Findings\n- F1: ask: which ghost first?\n\n## Verdict\nrevise\n' ;;
    mix) printf '## Findings\n- F1: ask: which ghost first?\n- F2: finding from call %s.\n\n## Verdict\nrevise\n' $n ;;
    *) printf '## Findings\n- none\n\n## Verdict\napprove\n' ;;
  esac
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
echo "$args" >> "$LOOP_LOG.author"
if [[ -n "$LOOP_SLEEP" ]]; then sleep "$LOOP_SLEEP"; fi
m=$(cat "$LOOP_LOG.fable" 2>/dev/null || echo 0); m=$((m+1)); echo $m > "$LOOP_LOG.fable"
if [[ -n "$LOOP_FABLE_ONCE" && $m -gt 1 ]]; then echo "quota" >&2; exit 1; fi
if [[ "$args" == *"answer each finding"* ]]; then
  n=$(cat "$LOOP_LOG.revisions" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$LOOP_LOG.revisions"
  printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound, version %s.\n\n## Non-goals\n- Ghost speed does not change.\n\n## Answers\n' $n
  if [[ "$LOOP_ANSWER" == revised ]]; then echo '- F1: revised'; echo '- F2: revised'; else echo '- F1: disputed: the ask names no person.'; echo '- F2: disputed: no.'; fi
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":4,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound.\n\n## Non-goals\n- Ghost speed does not change.\n'
echo '{"type":"result","subtype":"success","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"output_tokens":5}}'
exit 0
]=]

-- kimi and grok: one stub for both, which writes what it is asked for and logs who ran
local FALLBACK = [=[#!/bin/bash
args="$*"
if [[ "$args" == *"Challenge this idea"* ]]; then
  echo "NAME" >> "$LOOP_LOG.fallback-challenge"
  printf '## Findings\n- none\n\n## Verdict\napprove\n'
elif [[ "$args" == *"answer each finding"* ]]; then
  echo "NAME" >> "$LOOP_LOG.fallback-revision"
  printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound, by NAME.\n\n## Non-goals\n- Ghost speed does not change.\n\n## Answers\n- F1: revised\n'
else
  printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound.\n\n## Non-goals\n- Ghost speed does not change.\n'
fi
echo '{"type":"usage.record","usage":{"inputOther":10,"output":5,"inputCacheRead":0,"inputCacheCreation":0}}'
echo '{"type":"result","subtype":"success","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}'
exit 0
]=]

local function fallbackCli(name: string): string
	return (string.gsub(FALLBACK, "NAME", name))
end

local RECORD =
	"## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n\n## Interview\n### Q1\nQuestion: how?\nAnswer: sound\n"

return t.spec(
	"c0260 ./zn idea loops until the challenger approves, at most idea.MAX_ROUNDS times",
	function(it)
		local f = trackerfix.new("c0260-loop", {
			[".models.toml"] = ROLES,
			["z-nile/.tracker/capture-since"] = "marker\n",
		})
		local bin = `{f.base}/bin`
		local log = `{f.base}/loop`
		fs.writeDir(bin)
		fs.writeFile(`{bin}/claude`, CLAUDE)
		fs.writeFile(`{bin}/kimi`, fallbackCli("kimi"))
		fs.writeFile(`{bin}/grok`, fallbackCli("grok"))
		process.exec("chmod", { "+x", `{bin}/claude`, `{bin}/kimi`, `{bin}/grok` })
		local path = process.env.PATH or ""
		local wt = trackerfix.trOk(f, f.main, { "worktree", "loop-run" })
		trackerfix.trOk(f, wt, { "sync" })
		local function idea(args: { string }, env: { [string]: string }?)
			for _, name in
				{
					"count",
					"revisions",
					"challenge",
					"author",
					"fable",
					"fallback-challenge",
					"fallback-revision",
				}
			do
				pcall(fs.removeFile, `{log}.{name}`)
			end
			local e: { [string]: string } = { PATH = `{bin}:{path}`, LOOP_LOG = log, LOOP_ANSWER = "revised" }
			for k, v in env or {} do
				e[k] = v
			end
			return trackerfix.tr(f, wt, args, e)
		end
		local function ticket(slug: string, extra: { string }?): (string, string)
			local args = { "new", "issue", "c", slug, "--project", "pickman" }
			for _, a in extra or {} do
				table.insert(args, a)
			end
			local id = string.match(trackerfix.trOk(f, wt, args), "(c%d+)") :: string
			return id, `{wt}/pickman/.tracker/issues/{id}`
		end
		local function record(id: string, text: string?)
			local file = `{f.base}/record.md`
			fs.writeFile(file, text or RECORD)
			local r = trackerfix.tr(f, wt, { "idea", id, "--record", file }, { PATH = `{bin}:{path}` })
			if not r.ok then
				error(`--record failed: {r.stderr}{r.stdout}`, 0)
			end
		end
		local function ok(r: fixture.Result): fixture.Result
			if not r.ok then
				error(`idea failed ({r.code}): {r.stderr}{r.stdout}`, 0)
			end
			return r
		end
		local function openPart(dir: string, id: string): string
			local doc = fs.readFile(`{dir}/{id}.md`)
			return string.sub(doc, string.find(doc, "## Open to the human", 1, true) :: number)
		end
		local function lines(text: string, needle: string): number
			local n, from = 0, 1
			while true do
				local at = string.find(text, needle, from, true)
				if not at then
					return n
				end
				n += 1
				from = at + 1
			end
		end

		it(
			"AC12: an approval at the first challenge ends the loop: one pass, no refute, two calls",
			function()
				local id, dir = ticket("approved-at-once")
				record(id)
				local r = ok(idea({ "idea", id, "--text", "Ghosts." }))
				t.expect(has(r.stdout, `idea: rounds 1 of at most {CAP}, approved`)).toBe(true)
				t.expect(has(r.stdout, "idea: calls 2")).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(false)
				t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(false)
			end
		)

		it(
			"AC12: findings, a revision, and a second challenge that approves: two reviews, one refute, nothing left open",
			function()
				local id, dir = ticket("approved-at-second")
				record(id)
				local r = ok(idea({ "idea", id, "--text", "Ghosts." }, { LOOP_UNTIL = "1" }))
				t.expect(has(r.stdout, `idea: rounds 2 of at most {CAP}, approved`)).toBe(true)
				t.expect(has(r.stdout, "idea: calls 4")).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-refute-002.md`)).toBe(false) -- the approving pass has no findings to answer
				t.expect(fs.isFile(`{dir}/idea-review-003.md`)).toBe(false)
				local doc = fs.readFile(`{dir}/{id}.md`)
				t.expect(has(doc, "version 1")).toBe(true) -- the revised idea is the one written
				t.expect(has(openPart(dir, id), "- F1:")).toBe(false)
				-- the second challenge is given the first round's findings and the author's answers; the revision is given the idea
				local challenges = fs.readFile(`{log}.challenge`)
				t.expect(lines(challenges, "challenged before and revised")).toBe(1)
				t.expect(has(challenges, "F1: finding from call 1. => revised")).toBe(true)
				t.expect(has(fs.readFile(`{log}.author`), "Current idea (revise this one):")).toBe(true)
				-- every review names the state of the idea it judged: the first the draft, the last the one the user sees
				local first = capturecheck.reviewState(fs.readFile(`{dir}/idea-review-001.md`))
				local last = capturecheck.reviewState(fs.readFile(`{dir}/idea-review-002.md`))
				t.expect(last).toBe(capturecheck.roundState(doc))
				t.expect(first ~= last).toBe(true)
				-- the spend rows carry the review number of the pass
				local buffer = `{wt}/.{string.sub("xcache", 2)}/measure.tsv`
				t.expect(has(fs.readFile(buffer), `{id} round 2 ok`)).toBe(true)
			end
		)

		it(
			"AC12: a challenger that never approves is stopped at the last challenge (the cap, five), which no revision follows: all it found stays open",
			function()
				-- the owner's cap (2026-11-18: "a new review round and so on up to 5 times"), ruled for c0260 on 2026-11-19
				t.expect(CAP).toBe(5)
				local id, dir = ticket("never-approved")
				record(id)
				local r = ok(
					idea({ "idea", id, "--text", "Ghosts." }, { LOOP_UNTIL = "99", LOOP_ANSWER = "revised" })
				)
				t.expect(has(r.stdout, `idea: rounds {CAP} of at most {CAP}, not approved`)).toBe(true)
				t.expect(has(r.stdout, `idea: calls {2 * CAP}`)).toBe(true) -- a draft, CAP challenges, CAP - 1 revisions
				for n = 1, CAP do
					t.expect(fs.isFile(`{dir}/{ideaMod.reviewName(n)}`)).toBe(true)
				end
				t.expect(fs.isFile(`{dir}/{ideaMod.refuteName(CAP - 1)}`)).toBe(true)
				t.expect(fs.isFile(`{dir}/{ideaMod.refuteName(CAP)}`)).toBe(false) -- nothing was answered after the last challenge
				t.expect(fs.isFile(`{dir}/{ideaMod.reviewName(CAP + 1)}`)).toBe(false)
				-- the author said `revised` each time and the challenger raised the point again: the user is not shown a closed point
				local open = openPart(dir, id)
				t.expect(has(open, `- F1: finding from call {CAP}.`)).toBe(true)
				t.expect(has(open, "finding from call 1.")).toBe(false)
				local doc = fs.readFile(`{dir}/{id}.md`)
				t.expect(capturecheck.reviewState(fs.readFile(`{dir}/{ideaMod.reviewName(CAP)}`)))
					.toBe(capturecheck.roundState(doc))
				local c = idea({ "idea", id, "--confirm", "ok" })
				t.expect(c.ok).toBe(false)
				t.expect(has(c.stderr, "open to the human")).toBe(true)
			end
		)

		it(
			"AC12: a dispute a later challenge accepts leaves nothing open; a finding the last challenge raises is open in its own words",
			function()
				local id, dir = ticket("dispute-accepted")
				record(id)
				ok(
					idea(
						{ "idea", id, "--text", "Ghosts." },
						{ LOOP_REPLIES = "f,a", LOOP_ANSWER = "disputed" }
					)
				)
				t.expect(has(openPart(dir, id), "- F1:")).toBe(false)
				local other, odir = ticket("dispute-kept")
				record(other)
				ok(
					idea(
						{ "idea", other, "--text", "Ghosts." },
						{ LOOP_REPLIES = string.rep("f,", CAP - 1) .. "f", LOOP_ANSWER = "disputed" }
					)
				)
				local open = openPart(odir, other)
				t.expect(has(open, `finding from call {CAP}.`)).toBe(true)
				t.expect(has(open, "finding from call 1.")).toBe(false)
			end
		)

		it(
			"AC12: an approval that still lists a finding does not end the loop, and a revise with no finding is not an answer",
			function()
				local id, dir = ticket("approve-with-finding")
				record(id)
				local r = ok(idea({ "idea", id, "--text", "Ghosts." }, { LOOP_REPLIES = "af,a" }))
				t.expect(has(r.stdout, `idea: rounds 2 of at most {CAP}, approved`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true)
				local bad, bdir = ticket("revise-with-nothing")
				record(bad)
				local r0 = idea({ "idea", bad, "--text", "Ghosts." }, { LOOP_REPLIES = "r0" })
				t.expect(r0.ok).toBe(false)
				t.expect(fs.isFile(`{bdir}/idea-review-001.md`)).toBe(false) -- no usable challenge, nothing to write
			end
		)

		it(
			"AC12: a question for the user is never answered by the author and never closed: it stays open to the end",
			function()
				local id, dir = ticket("question-only")
				record(id)
				local r = ok(idea({ "idea", id, "--text", "Ghosts." }, { LOOP_REPLIES = "ask" }))
				t.expect(has(r.stdout, "idea: calls 2")).toBe(true) -- a pass with only questions makes no revision call
				t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(false)
				t.expect(has(openPart(dir, id), "- F1: which ghost first?")).toBe(true)
				local c = idea({ "idea", id, "--confirm", "ok" })
				t.expect(c.ok).toBe(false)
				t.expect(has(c.stderr, "open to the human")).toBe(true)
				local other, odir = ticket("question-and-finding")
				record(other)
				ok(idea({ "idea", other, "--text", "Ghosts." }, { LOOP_REPLIES = "mix,a" }))
				local revision = fs.readFile(`{log}.author`)
				t.expect(has(revision, "finding from call 1")).toBe(true)
				t.expect(lines(revision, "which ghost first?")).toBe(0) -- the author is not asked about the question
				local open = openPart(odir, other)
				t.expect(has(open, "- F1: which ghost first?")).toBe(true) -- a later approval did not close it
				t.expect(has(open, "finding from call")).toBe(false)
			end
		)

		it(
			"AC12: a pass is written when it completes: a failure later keeps the passes already paid for, and a rerun numbers on",
			function()
				local id, dir = ticket("stopped-partway")
				record(id)
				local r = idea({ "idea", id, "--text", "Ghosts." }, { LOOP_UNTIL = "99", LOOP_FAIL_AT = "2" })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stderr .. r.stdout, "pass(es) are written")).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(false)
				t.expect(has(fs.readFile(`{dir}/{id}.md`), "version 1")).toBe(true)
				t.expect(has(fs.readFile(`{dir}/{id}.md`), "idea: challenged")).toBe(true)
				-- the stopped run is not confirmable: the idea is not the one review 001 judged
				local c = idea({ "idea", id, "--confirm", "ok" })
				t.expect(c.ok).toBe(false)
				t.expect(has(c.stderr, "changed since round 1")).toBe(true)
				ok(idea({ "idea", id }))
				t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true) -- numbered on
			end
		)

		it("AC12: a dispatched run beats into the step's folder while a model works", function()
			local id = ticket("beats")
			record(id)
			local dispatchDir = `{f.base}/dispatch-step`
			fs.writeDir(dispatchDir)
			ok(
				idea(
					{ "idea", id, "--text", "Ghosts." },
					{ ZN_DISPATCH = "1", ZN_DISPATCH_DIR = dispatchDir, LOOP_SLEEP = "2" }
				)
			)
			t.expect(fs.isFile(`{dispatchDir}/idea-call-1/beat`)).toBe(true)
			-- an interactive run leaves nothing there
			local quiet = `{f.base}/interactive-step`
			fs.writeDir(quiet)
			local other = ticket("no-beats")
			record(other)
			ok(idea({ "idea", other, "--text", "Ghosts." }, { ZN_DISPATCH_DIR = quiet, LOOP_SLEEP = "2" }))
			t.expect(#fs.readDir(quiet)).toBe(0)
		end)

		it(
			"AC12: a change of the user's after the loop starts a loop of its own, numbered on; its spend rows carry the new numbers",
			function()
				local id, dir = ticket("changed-after")
				record(id)
				-- the one function the loop asks where it starts: numbered on from the highest review, and a folder with no
				-- review starts with the whole cap (what a later version of the function keeps; how many are left after
				-- earlier rounds is pinned only through ./zn idea's own cases)
				local start = ideaMod.loopStart(
					"",
					{ "idea-review-001.md", "idea-review-002.md", "idea-refute-001.md" }
				)
				t.expect(start.first).toBe(3)
				local fresh = ideaMod.loopStart("", {})
				t.expect(fresh.first).toBe(1)
				t.expect(fresh.left).toBe(CAP)
				ok(idea({ "idea", id, "--text", "Ghosts." }, { LOOP_UNTIL = "1" })) -- reviews 001 and 002
				record(id, "## Ask (verbatim)\n### Message 2026-11-08\n```\nand louder\n```\n")
				ok(idea({ "idea", id }, { LOOP_UNTIL = "1" }))
				t.expect(fs.isFile(`{dir}/idea-review-003.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-004.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-review-005.md`)).toBe(false)
				local buffer = `{wt}/.{string.sub("xcache", 2)}/measure.tsv`
				t.expect(has(fs.readFile(buffer), `{id} round 4 ok`)).toBe(true)
				local c = idea({ "idea", id, "--confirm", "yes" })
				if not c.ok then
					error(`--confirm failed: {c.stderr}{c.stdout}`, 0)
				end
				t.expect(has(fs.readFile(`{dir}/{id}.md`), ') after round 4: "yes"')).toBe(true)
			end
		)

		it(
			"AC12: an agent-filed ticket (F6) runs the same loop with no user words to compare against, and is claimed only once its challenge is on origin",
			function()
				local id, dir = ticket("agent-filed-loop", { "--filed-by", "lesson:z-ticket/anything" })
				t.expect(has(fs.readFile(`{dir}/{id}.md`), "idea: unchallenged")).toBe(true)
				t.expect(has(fs.readFile(`{dir}/{id}.md`), "## Filed by (agent)")).toBe(true)
				local before = trackerfix.tr(f, wt, { "status", id, "preparing" })
				t.expect(before.ok).toBe(false)
				t.expect(has(before.stderr, "the idea was not challenged")).toBe(true)
				local r = ok(idea({ "idea", id, "--text", "A lesson about ghosts." }, { LOOP_UNTIL = "1" }))
				t.expect(has(r.stdout, `idea: rounds 2 of at most {CAP}, approved`)).toBe(true)
				t.expect(has(fs.readFile(`{dir}/{id}.md`), "idea: challenged")).toBe(true)
				t.expect(has(fs.readFile(`{log}.challenge`), "The user's own words follow the idea"))
					.toBe(false)
				fixture.git(wt, { "add", "-A" })
				fixture.git(wt, { "commit", "-q", "-m", `tracker: idea {id}` })
				fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
				trackerfix.trOk(f, wt, { "status", id, "preparing" })
			end
		)

		it(
			"AC12: the model that wrote a text, a fallback included and whatever its effort, never challenges it",
			function()
				fs.writeFile(`{wt}/.models.toml`, rolesWith('["kimi", "grok"]'))
				local id, dir = ticket("fallback-excluded")
				record(id)
				-- the author's first model fails from its second call on, so kimi writes the revision; the challenger's first model
				-- fails at its second challenge, and kimi (who wrote the revision) must not take it over: grok does
				ok(
					idea(
						{ "idea", id, "--text", "Ghosts." },
						{ LOOP_UNTIL = "1", LOOP_FABLE_ONCE = "1", LOOP_FAIL_AT = "2" }
					)
				)
				t.expect(has(fs.readFile(`{log}.fallback-revision`), "kimi")).toBe(true)
				t.expect(has(fs.readFile(`{log}.fallback-challenge`), "grok")).toBe(true)
				t.expect(has(fs.readFile(`{log}.fallback-challenge`), "kimi")).toBe(false)
				t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true)
				-- with grok gone the second challenge fails rather than let kimi challenge its own revision
				fs.writeFile(`{wt}/.models.toml`, rolesWith('["kimi"]'))
				local other, odir = ticket("fallback-none-left")
				record(other)
				local r = idea(
					{ "idea", other, "--text", "Ghosts." },
					{ LOOP_UNTIL = "1", LOOP_FABLE_ONCE = "1", LOOP_FAIL_AT = "2" }
				)
				t.expect(r.ok).toBe(false)
				t.expect(fs.isFile(`{odir}/idea-review-001.md`)).toBe(true) -- pass 1 stays
				t.expect(fs.isFile(`{log}.fallback-challenge`)).toBe(false) -- kimi wrote the revision and did not take over the challenge
				fs.writeFile(`{wt}/.models.toml`, ROLES)
				fs.removeDir(f.base)
			end
		)
	end
)
