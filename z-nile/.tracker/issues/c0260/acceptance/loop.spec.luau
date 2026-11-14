--!strict
-- c0260 AC12 (the user's ruling of 2026-11-13, F15): `./zn idea` loops. The challenger reviews, the author revises and
-- answers, and the challenger reviews the revised idea again, until it approves or has challenged three times. Each
-- pass is a review (and, with findings, a refute) file numbered on from the last; what the last pass still disputes is
-- under `## Open to the human`; the last review names the state of the idea the user will see. An agent-filed ticket
-- (F6) runs the same loop. Stub CLIs only; a fixture under .cache/c0260-loop.
local capturecheck = require("@znile/engine/capturecheck")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

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

-- The challenger finds fault for its first $LOOP_UNTIL calls of a run and approves after; the author answers revised or
-- disputed ($LOOP_ANSWER) and changes the Solution when it revises. Every prompt is logged by role.
local CLAUDE = [=[#!/bin/bash
args="$*"
if [[ "$args" == *opus* ]]; then
  echo "$args" >> "$LOOP_LOG.challenge"
  n=$(cat "$LOOP_LOG.count" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$LOOP_LOG.count"
  if [[ $n -le ${LOOP_UNTIL:-0} ]]; then
    printf '## Findings\n- F1: The problem names no person who is blocked.\n\n## Verdict\nrevise\n'
  else
    printf '## Findings\n- none\n\n## Verdict\napprove\n'
  fi
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
echo "$args" >> "$LOOP_LOG.author"
if [[ "$args" == *"answer each finding"* ]]; then
  n=$(cat "$LOOP_LOG.revisions" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$LOOP_LOG.revisions"
  printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound, version %s.\n\n## Non-goals\n- Ghost speed does not change.\n\n## Answers\n' $n
  if [[ "$LOOP_ANSWER" == revised ]]; then echo '- F1: revised'; else echo '- F1: disputed: the ask names no person.'; fi
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":4,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
printf '## Problem\n- Every ghost sounds the same.\n\n## Solution\n- Every ghost gets a scarier sound.\n\n## Non-goals\n- Ghost speed does not change.\n'
echo '{"type":"result","subtype":"success","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"output_tokens":5}}'
exit 0
]=]

local RECORD =
	"## Ask (verbatim)\n### Message 2026-11-07\n```\nmake the ghosts scarrier, thx\n```\n\n## Interview\n### Q1\nQuestion: how?\nAnswer: sound\n"

return t.spec("c0260 ./zn idea loops until the challenger approves, at most three times", function(it)
	local f = trackerfix.new("c0260-loop", {
		[".models.toml"] = ROLES,
		["z-nile/.tracker/capture-since"] = "marker\n",
	})
	local bin = `{f.base}/bin`
	local log = `{f.base}/loop`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/claude`, CLAUDE)
	process.exec("chmod", { "+x", `{bin}/claude` })
	local path = process.env.PATH or ""
	local wt = trackerfix.trOk(f, f.main, { "worktree", "loop-run" })
	trackerfix.trOk(f, wt, { "sync" })
	local function idea(args: { string }, faultyPasses: number, answer: string)
		pcall(fs.removeFile, `{log}.count`)
		pcall(fs.removeFile, `{log}.revisions`)
		pcall(fs.removeFile, `{log}.challenge`)
		pcall(fs.removeFile, `{log}.author`)
		return trackerfix.tr(f, wt, args, {
			PATH = `{bin}:{path}`,
			LOOP_LOG = log,
			LOOP_UNTIL = tostring(faultyPasses),
			LOOP_ANSWER = answer,
		})
	end
	local function ticket(slug: string, extra: { string }?): (string, string)
		local args = { "new", "issue", "c", slug, "--project", "pickman" }
		for _, a in extra or {} do
			table.insert(args, a)
		end
		local id = string.match(trackerfix.trOk(f, wt, args), "(c%d+)") :: string
		return id, `{wt}/pickman/.tracker/issues/{id}`
	end
	local function recorded(id: string)
		local file = `{f.base}/record.md`
		fs.writeFile(file, RECORD)
		local r = trackerfix.tr(f, wt, { "idea", id, "--record", file }, { PATH = `{bin}:{path}` })
		if not r.ok then
			error(`--record failed: {r.stderr}{r.stdout}`, 0)
		end
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
		"AC12: an approval at the first challenge ends the loop: one pass, no refute, three calls fewer than a full loop",
		function()
			local id, dir = ticket("approved-at-once")
			recorded(id)
			local r = idea({ "idea", id, "--text", "Ghosts." }, 0, "revised")
			if not r.ok then
				error(`idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(has(r.stdout, "idea: rounds 1 of at most 3, approved")).toBe(true)
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
			recorded(id)
			local r = idea({ "idea", id, "--text", "Ghosts." }, 1, "revised")
			if not r.ok then
				error(`idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(has(r.stdout, "idea: rounds 2 of at most 3, approved")).toBe(true)
			t.expect(has(r.stdout, "idea: calls 4")).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-refute-002.md`)).toBe(false) -- the approving pass has no findings to answer
			t.expect(fs.isFile(`{dir}/idea-review-003.md`)).toBe(false)
			local doc = fs.readFile(`{dir}/{id}.md`)
			t.expect(has(doc, "version 1")).toBe(true) -- the revised idea is the one written
			local openAt = string.find(doc, "## Open to the human", 1, true) :: number
			t.expect(has(string.sub(doc, openAt), "- F1:")).toBe(false)
			-- the second challenge is given the first round's findings and the author's answers; the revision is given the idea
			local challenges = fs.readFile(`{log}.challenge`)
			t.expect(lines(challenges, "challenged before and revised")).toBe(1)
			t.expect(has(challenges, "F1: The problem names no person who is blocked. => revised")).toBe(true)
			t.expect(has(fs.readFile(`{log}.author`), "Current idea (revise this one):")).toBe(true)
			-- every pass names the state of the idea it judged, the last the one the user sees
			local first = capturecheck.reviewState(fs.readFile(`{dir}/idea-review-001.md`))
			local last = capturecheck.reviewState(fs.readFile(`{dir}/idea-review-002.md`))
			t.expect(last).toBe(capturecheck.roundState(doc))
			t.expect(first ~= last).toBe(true)
		end
	)

	it(
		"AC12: a challenger that never approves is stopped at the third challenge; what it still disputes is left open",
		function()
			local id, dir = ticket("never-approved")
			recorded(id)
			local r = idea({ "idea", id, "--text", "Ghosts." }, 9, "disputed")
			if not r.ok then
				error(`idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(has(r.stdout, "idea: rounds 3 of at most 3, not approved")).toBe(true)
			t.expect(has(r.stdout, "idea: calls 7")).toBe(true) -- a draft, three challenges, three revisions
			for _, n in { "001", "002", "003" } do
				t.expect(fs.isFile(`{dir}/idea-review-{n}.md`)).toBe(true)
				t.expect(fs.isFile(`{dir}/idea-refute-{n}.md`)).toBe(true)
			end
			t.expect(fs.isFile(`{dir}/idea-review-004.md`)).toBe(false)
			local doc = fs.readFile(`{dir}/{id}.md`)
			local openAt = string.find(doc, "## Open to the human", 1, true) :: number
			t.expect(has(string.sub(doc, openAt), "- F1: The problem names no person who is blocked. Answer: disputed"))
				.toBe(true)
			t.expect(lines(fs.readFile(`{log}.challenge`), "challenged before and revised")).toBe(2)
			-- the last review names the state of the idea the user sees (revised after its findings), not the one it judged
			t.expect(capturecheck.reviewState(fs.readFile(`{dir}/idea-review-003.md`)))
				.toBe(capturecheck.roundState(doc))
			-- the user is not asked to confirm past an unruled point
			local c = idea({ "idea", id, "--confirm", "ok" }, 0, "revised")
			t.expect(c.ok).toBe(false)
			t.expect(has(c.stderr, "open to the human")).toBe(true)
		end
	)

	it(
		"AC12: a change of the user's after the loop starts a loop of its own, numbered on, and the confirmation names its last review",
		function()
			local id, dir = ticket("changed-after")
			recorded(id)
			t.expect(idea({ "idea", id, "--text", "Ghosts." }, 1, "revised").ok).toBe(true) -- reviews 001 and 002
			local file = `{f.base}/more.md`
			fs.writeFile(file, "## Ask (verbatim)\n### Message 2026-11-08\n```\nand louder\n```\n")
			t.expect(trackerfix.tr(f, wt, { "idea", id, "--record", file }, { PATH = `{bin}:{path}` }).ok).toBe(true)
			local r = idea({ "idea", id }, 1, "revised")
			if not r.ok then
				error(`idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(fs.isFile(`{dir}/idea-review-003.md`)).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-review-004.md`)).toBe(true)
			t.expect(fs.isFile(`{dir}/idea-review-005.md`)).toBe(false)
			local c = idea({ "idea", id, "--confirm", "yes" }, 0, "revised")
			if not c.ok then
				error(`--confirm failed: {c.stderr}{c.stdout}`, 0)
			end
			t.expect(has(fs.readFile(`{dir}/{id}.md`), ') after round 4: "yes"')).toBe(true)
		end
	)

	it(
		"AC12: an agent-filed ticket (F6) runs the same loop with no user words to compare against, and is claimed only when challenged",
		function()
			local id, dir = ticket("agent-filed-loop", { "--filed-by", "lesson:z-ticket/anything" })
			t.expect(has(fs.readFile(`{dir}/{id}.md`), "idea: unchallenged")).toBe(true)
			t.expect(has(fs.readFile(`{dir}/{id}.md`), "## Filed by (agent)")).toBe(true)
			local r = idea({ "idea", id, "--text", "A lesson about ghosts." }, 1, "revised")
			if not r.ok then
				error(`idea failed: {r.stderr}{r.stdout}`, 0)
			end
			t.expect(has(r.stdout, "idea: rounds 2 of at most 3, approved")).toBe(true)
			t.expect(has(fs.readFile(`{dir}/{id}.md`), "idea: challenged")).toBe(true)
			t.expect(has(fs.readFile(`{log}.challenge`), "The user's own words follow the idea")).toBe(false)
			fs.removeDir(f.base)
		end
	)
end)
