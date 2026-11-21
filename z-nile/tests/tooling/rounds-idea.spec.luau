--!strict
-- f0421 AC11: `./zn idea` challenges up to [rounds] idea times. A challenger that always says revise gets idea-review-001
-- to idea-review-00M and then the loop stops; a first challenge that approves with no findings writes only
-- idea-review-001.md. Stub CLIs only.
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
if [[ "$args" == *opus* ]]; then
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
- The board hides a finished card before a person can read it.

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

local function run(name: string, env: { [string]: string }): (string, string)
	local f = trackerfix.new(name, { [".models.toml"] = ROLES })
	local bin = `{f.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(`{bin}/claude`, CLAUDE)
	process.exec("chmod", { "+x", `{bin}/claude` })
	local wt = trackerfix.trOk(f, f.main, { "worktree", name })
	trackerfix.trOk(f, wt, { "sync" })
	local id = string.match(
		trackerfix.trOk(f, wt, { "new", "issue", "c", `rounds-{name}`, "--project", "pickman" }),
		"(c%d+)"
	) :: string
	local all = { PATH = `{bin}:{process.env.PATH or ""}` }
	for k, v in env do
		all[k] = v
	end
	local ran = trackerfix.tr(f, wt, { "idea", id, "--text", "The board hides a finished card." }, all)
	if not ran.ok then
		error(`idea failed ({ran.code}): {ran.stderr}{ran.stdout}`, 0)
	end
	return `{wt}/pickman/.tracker/issues/{id}`, ran.stdout
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

	it("a first challenge that approves with no findings writes only idea-review-001.md", function()
		local dir, out = run("idea-rounds-approve", {})
		t.expect(fs.isFile(`{dir}/idea-review-001.md`)).toBe(true)
		t.expect(fs.isFile(`{dir}/idea-review-002.md`)).toBe(false)
		t.expect(fs.isFile(`{dir}/idea-refute-001.md`)).toBe(false)
		t.expect(has(out, "idea: calls 2")).toBe(true)
	end)
end)
