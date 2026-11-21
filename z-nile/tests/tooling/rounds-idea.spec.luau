--!strict
-- f0421 AC11: `./zn idea` challenges up to [rounds] idea times. A challenger that always says revise gets idea-review-001
-- to idea-review-00M and then the loop stops; a first challenge that approves with no findings writes only
-- idea-review-001.md. Stub CLIs only.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local KIMI = [=[#!/bin/bash
cat <<'EOF'
## Problem
- The board hides a finished card before a person can read it (REVISED BY KIMI).

## Solution
- A finished card stays visible until the person dismisses it.

## Non-goals
- The board does not change how a card is scored.

## Open
- none
EOF
echo '{"type":"usage.record","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0}}'
exit 0
]=]

-- the author falls back to kimi after its first call, and so does the challenger: a challenger is never the model whose
-- text it reads
local TWO_MODELS = [[
[dispatch]
stall_seconds = 30

[rounds]
idea = 2

[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = ["kimi"]

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = ["kimi"]
]]

local ROLES = [[
[dispatch]
stall_seconds = 30

[rounds]
idea = 2

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

local CLAUDE = [=[#!/bin/bash
args="$*"
if [[ "$args" == *fable* && "$IDEA_STUB_FAIL_FABLE" == 1 ]]; then
  echo failed >&2
  exit 1
fi
if [[ "$args" == *fable* && -n "$IDEA_STUB_FABLE_COUNT" ]]; then
  f=$(cat "$IDEA_STUB_FABLE_COUNT" 2>/dev/null || echo 0)
  f=$((f+1))
  echo "$f" > "$IDEA_STUB_FABLE_COUNT"
  if [[ "$f" -ge 2 ]]; then
    echo failed >&2
    exit 1
  fi
fi
if [[ "$args" == *opus* ]]; then
  echo "$args" >> "$IDEA_STUB_LOG"
  n=$(cat "$IDEA_STUB_COUNT" 2>/dev/null || echo 0)
  n=$((n+1))
  echo "$n" > "$IDEA_STUB_COUNT"
  if [[ "$IDEA_STUB_FAIL_AT" == "$n" ]]; then
    echo failed >&2
    exit 1
  fi
  if [[ "$IDEA_STUB_THREE" == 1 ]]; then
    cat <<'EOF'
## Findings
- F1: The problem names no person who is blocked.
- F2: The solution does not say what stays on the board.
- F3: A non-goal is missing.

## Verdict
revise
EOF
  else
    cat <<'EOF'
## Findings
- none

## Verdict
approve
EOF
  fi
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
if [[ "$args" == *"answer each finding"* ]]; then
  cat <<'EOF'
## Problem
- The board hides a finished card before a person can read it (REVISED).

## Solution
- A finished card stays visible until the person dismisses it.

## Non-goals
- The board does not change how a card is scored.

## Answers
- F1: revised
- F2: disputed: The solution already says the card stays visible.
EOF
  echo '{"type":"result","subtype":"success","usage":{"input_tokens":4,"cache_creation_input_tokens":0,"output_tokens":2}}'
  exit 0
fi
cat <<'EOF'
## Problem
- The board hides a finished card before a person can read it.

## Solution
- A finished card stays visible until the person dismisses it.

## Non-goals
- The board does not change how a card is scored.

## Open
- none
EOF
echo '{"type":"result","subtype":"success","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"output_tokens":5}}'
exit 0
]=]

type Ran = { f: trackerfix.Fixture, wt: string, id: string, dir: string, env: { [string]: string } }

local function setup(name: string, roles: string?): Ran
	local f = trackerfix.new(name, { [".models.toml"] = roles or ROLES })
	local bin = `{f.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/claude`, CLAUDE)
	fs.writeFile(`{bin}/kimi`, KIMI)
	process.exec("chmod", { "+x", `{bin}/claude`, `{bin}/kimi` })
	local wt = trackerfix.trOk(f, f.main, { "worktree", name })
	trackerfix.trOk(f, wt, { "sync" })
	local id = string.match(
		trackerfix.trOk(f, wt, { "new", "issue", "c", `rounds-{name}`, "--project", "pickman" }),
		"(c%d+)"
	) :: string
	return {
		f = f,
		wt = wt,
		id = id,
		dir = `{wt}/pickman/.tracker/issues/{id}`,
		env = {
			PATH = `{bin}:{process.env.PATH or ""}`,
			IDEA_STUB_LOG = `{f.base}/challenges.log`,
			IDEA_STUB_COUNT = `{f.base}/challenge-count`,
		},
	}
end

local function idea(r: Ran, extra: { [string]: string }): fixture.Result
	local all = table.clone(r.env)
	for k, v in extra do
		all[k] = v
	end
	pcall(fs.removeFile, all.IDEA_STUB_COUNT)
	pcall(fs.removeFile, all.IDEA_STUB_FABLE_COUNT)
	return trackerfix.tr(r.f, r.wt, { "idea", r.id, "--text", "The board hides a finished card." }, all)
end

local function run(name: string, extra: { [string]: string }): (string, string, Ran)
	local r = setup(name)
	local ran = idea(r, extra)
	if not ran.ok then
		error(`idea failed ({ran.code}): {ran.stderr}{ran.stdout}`, 0)
	end
	return r.dir, ran.stdout, r
end

return t.spec("f0421: ./zn idea challenges up to [rounds] idea times", function(it)
	it("a challenger that always says revise gets rounds 1 to M and the loop stops", function()
		local dir, out = run("idea-rounds-revise", { IDEA_STUB_THREE = "1" })
		t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-refute-002.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-review-003.md`)).toBe(false)
		t.expect(has(out, "idea: calls 5")).toBe(true)
	end)

	it(
		"every round's disputes are carried to the open list, qualified by their round, in round order (F8)",
		function()
			local dir = run("idea-rounds-open", { IDEA_STUB_THREE = "1" })
			local doc = fs.readFile(`{dir}/{string.match(dir, "(c%d+)$")}.md`)
			local first = string.find(doc, "- idea-review-001 F2:", 1, true)
			local second = string.find(doc, "- idea-review-002 F2:", 1, true)
			t.expect(first ~= nil and second ~= nil).toBe(true)
			t.expect((first :: number) < (second :: number)).toBe(true)
			t.expect(string.find(doc, "- idea-review-001 F3:", 1, true) ~= nil).toBe(true) -- unanswered counts too
			t.expect(string.find(doc, "\n- F2:", 1, true) == nil).toBe(true)
		end
	)

	it("round 2 challenges the revision, not the original prose (F14)", function()
		local _, _, r = run("idea-rounds-prose", { IDEA_STUB_THREE = "1" })
		-- the original draft has no (REVISED) mark; only the revision does, so only a round-2 prompt can carry it
		local log = fs.readFile(r.env.IDEA_STUB_LOG)
		local challenges = 0
		for _ in string.gmatch(log, "[^\n]+") do
			challenges += 1
		end
		t.expect(challenges >= 2).toBe(true)
		t.expect(string.find(log, "(REVISED)", 1, true) ~= nil).toBe(true)
	end)

	it("a challenger that fails in round 2 leaves the folder as it was (F11)", function()
		local r = setup("idea-rounds-fail")
		local ran = idea(r, { IDEA_STUB_THREE = "1", IDEA_STUB_FAIL_AT = "2" })
		t.expect(ran.ok).toBe(false)
		t.expect(fs.isFile(`{r.dir}/idea-review-001.md`)).toBe(false)
		t.expect(fs.isFile(`{r.dir}/idea-refute-001.md`)).toBe(false)
		t.expect(string.find(fs.readFile(`{r.dir}/{r.id}.md`), "idea: unchallenged", 1, true) ~= nil)
			.toBe(true)
	end)

	it("a rerun removes the files an earlier run wrote above or beside its own rounds (F11)", function()
		local r = setup("idea-rounds-rerun")
		t.expect(idea(r, { IDEA_STUB_THREE = "1" }).ok).toBe(true)
		t.expect(fs.isFile(`{r.dir}/idea-review-002.md`)).toBe(true)
		t.expect(fs.isFile(`{r.dir}/idea-refute-002.md`)).toBe(true)
		t.expect(idea(r, {}).ok).toBe(true) -- the first challenge approves with no findings
		t.expect(fs.isFile(`{r.dir}/idea-review-001.md`)).toBe(true)
		t.expect(fs.isFile(`{r.dir}/idea-review-002.md`)).toBe(false)
		t.expect(fs.isFile(`{r.dir}/idea-refute-001.md`)).toBe(false)
		t.expect(fs.isFile(`{r.dir}/idea-refute-002.md`)).toBe(false)
	end)

	it("a first challenge that approves with no findings writes only idea-review-001.md", function()
		local dir, out = run("idea-rounds-approve", {})
		t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(false)
		t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(false)
		t.expect(has(out, "idea: calls 2")).toBe(true)
	end)

	it(
		"round 2's challenge names the reviser's model as the author: the reviser is never its own challenger",
		function()
			local r = setup("idea-rounds-reviser", TWO_MODELS)
			-- round 1: fable writes; its second call (the answer) fails, so kimi revises. Round 2's challenger (opus) fails and
			-- would fall back to kimi, the model whose text it reads, so that fallback is dropped
			local ran = idea(r, {
				IDEA_STUB_THREE = "1",
				IDEA_STUB_FAIL_AT = "2",
				IDEA_STUB_FABLE_COUNT = `{r.f.base}/fable-count`,
			})
			t.expect(ran.ok).toBe(false)
			local said = ran.stderr .. ran.stdout
			t.expect(has(said, "idea: idea model kimi-code-k3.1-pro")).toBe(true) -- kimi revised round 1
			t.expect(has(said, "idea: idea-challenge model claude-opus-5-5")).toBe(true) -- round 2's challenger was tried
			-- and the fallback to kimi was never tried: kimi wrote the text this round challenges
			t.expect(has(said, "idea: idea-challenge model kimi-code-k3.1-pro")).toBe(false)
		end
	)
end)
