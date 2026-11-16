--!strict
-- The idea stage: design refuses an unchallenged idea, an older ticket has no idea key, a failed
-- first model falls through, and the author's model is never its own challenger. Stub CLIs only.
local fs = require("@lune/fs")
local idea = require("@znile/engine/idea")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end

local OLD = [[---
id: c0099
type: chore
title: Old
slug: old
raft: 
depends_on: []
emergent: false
design: draft
created: 2026-01-01
status: new-amber-otter-lynx
---

# Old
]]

local ROLES = [[
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
fallbacks = ["kimi", "grok"]

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = ["kimi", "grok"]
]]

local SAME = [[
[roles.idea]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 300000
fallbacks = []

[roles.idea-challenge]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 300000
author = "idea"
fallbacks = []
]]

local DRAFT = [[## Problem
- The board hides a finished card before a person can read it.

## Solution
- A finished card stays visible until the person dismisses it.

## Non-goals
- The board does not change how a card is scored.

## Open
- none
]]

local REVIEW = [[## Findings
- none

## Verdict
approve
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

local KIMI = [=[#!/bin/bash
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
echo '{"type":"usage.record","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0}}'
exit 0
]=]

return t.spec("idea: challenged before design, and a fallback is the model the row names", function(it)
	it("designRefusal names the missing review, the open point, and a ruled idea", function()
		local plain = "---\nid: c0001\nstatus: new-amber-otter-lynx\n---\n\n# t\n"
		t.expect(idea.designRefusal(plain, nil, "c0001")).toBe(nil)
		local fresh = "---\nid: c0001\nidea: unchallenged\nstatus: new-amber-otter-lynx\n---\n\n# t\n"
		t.expect(idea.designRefusal(fresh, nil, "c0001"))
			.toBe("no idea-review-001.md (the idea was not challenged): ./zn idea c0001")
		local openDoc =
			"---\nid: c0001\nidea: challenged\n---\n\n## Open to the human\n- F1: A sentence stays disputed.\n"
		local pending = idea.designRefusal(openDoc, "# Idea review 001\n", "c0001")
		t.expect(has(pending, "F1")).toBe(true)
		local ruled =
			"---\nid: c0001\nidea: challenged\n---\n\n## Open to the human\n- F1: A sentence stays disputed. Ruled (user, 2026-11-11): keep it.\n"
		t.expect(idea.designRefusal(ruled, "# Idea review 001\n", "c0001")).toBe(nil)
	end)

	it("a draft sentence is one a later claim can check", function()
		local draft = idea.parseDraft(DRAFT)
		t.expect(draft ~= nil).toBe(true)
		t.expect((draft :: idea.Draft).problem[1])
			.toBe("The board hides a finished card before a person can read it.")
		local _, verdict = idea.parseReview(REVIEW)
		t.expect(verdict).toBe("approve")
	end)

	it("design refuses an unchallenged idea, accepts it after, and claims an older ticket", function()
		local f = trackerfix.new("idea-design", {
			["pickman/.tracker/issues/c0099/c0099.md"] = OLD,
			["pickman/.tracker/issues/c0099/check.sh"] = "#!/bin/sh\nexit 0\n",
		})
		local wt = trackerfix.trOk(f, f.main, { "worktree", "idea-design" })
		trackerfix.trOk(f, wt, { "sync" })
		trackerfix.trOk(f, wt, { "status", "c0099", "preparing" })
		t.expect(trackerfix.trOk(f, wt, { "status", "c0099" })).toBe("preparing")
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "fresh-idea", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		local refused = trackerfix.tr(f, wt, { "status", id, "preparing" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, `no idea-review-001.md (the idea was not challenged): ./zn idea {id}`))
			.toBe(true)
		local path = `{wt}/pickman/.tracker/issues/{id}/{id}.md`
		fs.writeFile(path, (string.gsub(fs.readFile(path), "idea: unchallenged", "idea: challenged", 1)))
		fs.writeFile(
			`{wt}/pickman/.tracker/issues/{id}/idea-review-001.md`,
			"# Idea review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n"
		)
		local fixture = require("@tests/lib/fixture")
		fixture.git(wt, { "add", "-A" })
		fixture.git(wt, { "commit", "-q", "-m", `tracker: idea {id}` })
		fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
		trackerfix.trOk(f, wt, { "status", id, "preparing" })
		t.expect(trackerfix.trOk(f, wt, { "status", id })).toBe("preparing")
	end)

	it("a failed first model falls through, and the author is refused as its own challenger", function()
		local f = trackerfix.new("idea-stage", { [".models.toml"] = ROLES })
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(`{bin}/claude`, CLAUDE)
		fs.writeFile(`{bin}/kimi`, KIMI)
		process.exec("chmod", { "+x", `{bin}/claude`, `{bin}/kimi` })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "idea-run" })
		trackerfix.trOk(f, wt, { "sync" })
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "fallback-idea", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		local path = process.env.PATH or ""
		local env = { PATH = `{bin}:{path}`, IDEA_STUB_FAIL_FABLE = "1" }
		local ran = trackerfix.tr(f, wt, { "idea", id, "--text", "The board hides a finished card." }, env)
		if not ran.ok then
			error(`idea failed ({ran.code}): {ran.stderr}{ran.stdout}`, 0)
		end
		local out = ran.stdout
		t.expect(has(out, "idea: idea model claude-fable-5-2")).toBe(true)
		t.expect(has(out, "idea: idea model kimi-code-k3.1-pro")).toBe(true)
		t.expect(has(out, "idea: idea-challenge model claude-opus-5-5")).toBe(true)
		local fableAt = string.find(out, "idea: idea model claude-fable-5-2", 1, true) :: number
		local kimiAt = string.find(out, "idea: idea model kimi-code-k3.1-pro", 1, true) :: number
		t.expect(fableAt < kimiAt).toBe(true)
		local buffer = `{wt}/.{string.sub("xcache", 2)}/measure.tsv`
		t.expect(has(fs.readFile(buffer), "kimi-code-k3.1-pro")).toBe(true)
		local other = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "same-model", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		fs.writeFile(`{wt}/.models.toml`, SAME)
		local refused = trackerfix.tr(
			f,
			wt,
			{ "idea", other, "--text", "Same model." },
			{ PATH = `{bin}:{path}` }
		)
		t.expect(refused.ok).toBe(false)
		t.expect(
			has(
				refused.stderr,
				"idea-challenge: the only model left is the author's (claude-fable-5-2); a challenge is never run by the model that wrote the text"
			)
		).toBe(true)
		-- an approval with no findings does not call the author again
		local ideaLines = 0
		local from = 1
		while true do
			local at = string.find(out, "idea: idea model ", from, true)
			if not at then
				break
			end
			ideaLines += 1
			from = at + 1
		end
		t.expect(ideaLines).toBe(2)
		t.expect(has(out, "idea: calls 3")).toBe(true)
		t.expect(has(out, "cpu unmeasured")).toBe(false)
	end)

	it("a stalled stub is killed at the stall limit and the outcome is recorded", function()
		local stallRoles = [[
[dispatch]
stall_seconds = 2

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
		local f = trackerfix.new("idea-stall", { [".models.toml"] = stallRoles })
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(`{bin}/claude`, "#!/bin/bash\nsleep 30\necho hi\n")
		process.exec("chmod", { "+x", `{bin}/claude` })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "idea-stall" })
		trackerfix.trOk(f, wt, { "sync" })
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "stalled-idea", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		local path = process.env.PATH or ""
		local ran = trackerfix.tr(
			f,
			wt,
			{ "idea", id, "--text", "The board hides a finished card." },
			{ PATH = `{bin}:{path}` }
		)
		t.expect(ran.ok).toBe(false)
		local said = ran.stdout .. ran.stderr
		t.expect(has(said, "stalled")).toBe(true)
		t.expect(has(said, "no output for 2 s")).toBe(true)
		local buffer = `{wt}/.{string.sub("xcache", 2)}/measure.tsv`
		t.expect(has(fs.readFile(buffer), "claude-fable-5-2")).toBe(true)
		t.expect(has(fs.readFile(buffer), "stalled")).toBe(true)
	end)

	it("records every finding, and leaves a disputed one and an ignored one open", function()
		local f = trackerfix.new("idea-three", { [".models.toml"] = ROLES })
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(`{bin}/claude`, CLAUDE)
		process.exec("chmod", { "+x", `{bin}/claude` })
		local wt = trackerfix.trOk(f, f.main, { "worktree", "idea-three" })
		trackerfix.trOk(f, wt, { "sync" })
		local id = string.match(
			trackerfix.trOk(f, wt, { "new", "issue", "c", "three-findings", "--project", "pickman" }),
			"(c%d+)"
		) :: string
		local path = process.env.PATH or ""
		local ran = trackerfix.tr(
			f,
			wt,
			{ "idea", id, "--text", "The board hides a finished card." },
			{ PATH = `{bin}:{path}`, IDEA_STUB_THREE = "1" }
		)
		if not ran.ok then
			error(`idea failed ({ran.code}): {ran.stderr}{ran.stdout}`, 0)
		end
		t.expect(has(ran.stdout, "idea: calls 3")).toBe(true)
		local dir = `{wt}/pickman/.tracker/issues/{id}`
		local review = fs.readFile(`{dir}/idea-review-001.md`)
		t.expect(has(review, "- F1: The problem names no person who is blocked.")).toBe(true)
		t.expect(has(review, "- F2: The solution does not say what stays on the board.")).toBe(true)
		t.expect(has(review, "- F3: A non-goal is missing.")).toBe(true)
		t.expect(has(review, "revise")).toBe(true)
		local refute = fs.readFile(`{dir}/idea-refute-001.md`)
		t.expect(has(refute, "- F1: revised")).toBe(true)
		t.expect(has(refute, "- F2: disputed: The solution already says the card stays visible.")).toBe(true)
		t.expect(has(refute, "F3")).toBe(false)
		local doc = fs.readFile(`{dir}/{id}.md`)
		local openAt = string.find(doc, "## Open to the human", 1, true) :: number
		local open = string.sub(doc, openAt)
		t.expect(has(open, "- F2:")).toBe(true)
		t.expect(has(open, "- F3:")).toBe(true)
		t.expect(has(open, "disputed: The solution already says the card stays visible.")).toBe(true)
		t.expect(has(open, "- F1:")).toBe(false)
	end)
end)
