--!strict
-- c0261: `./zn dispatch zz-review --mode <mode>` starts the CLI with the model of the activity its mode runs (a layer's
-- code review and a stream review cheap; the design, raft and final reviews expensive through the zz-review fallback),
-- writes the row with that model, and `--dry-run` names the activity. The wait poll and parsePr are pinned here too.
-- Fake CLIs (@tests/lib/fakecli), fixture under .cache/c0261-dispatch.
local buffer = require("@znile/engine/buffer")
local dispatch = require("@znile/engine/dispatch")
local dispatcher = require("@znile/engine/dispatcher")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude"]

[dispatch]
stall_seconds = 5
tool_seconds = 8

[z-design.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000

[zz-review-stream.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000
]]

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function znIn(dir: string, args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
			GH_TOKEN = "the-users-token",
		},
	})
end
local function reviewer()
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`sleep 1; printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
end
local function lastRow(id: string): any
	local rows = fakecli.rows(h, id)
	return rows and rows[#rows]
end

return t.spec("c0261 ./zn dispatch picks the model of the activity", function(it)
	it("sets up a tracker with the activity tables and a worktree for the issue", function()
		h = fakecli.new("c0261-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
		})
		local r = fakecli.zn(h, { "dispatch", "z-design", "c0010" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a design review starts the expensive model (zz-review) and records it (AC10)", function()
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		reviewer()
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(fakecli.log(h), "--model claude-opus-5-5")).toBe(true)
		t.expect(has(fakecli.log(h), "--model claude-sonnet-5")).toBe(false)
		t.expect(lastRow("c0010").model).toBe("claude-opus-5-5")
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/design-review-001.md`)
	end)

	it("a layer's code review starts the expensive model, like every review but a stream (AC10)", function()
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		reviewer()
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(fakecli.log(h), "--model claude-opus-5-5")).toBe(true)
		t.expect(has(fakecli.log(h), "--model claude-sonnet-5")).toBe(false)
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/review-001.md`)
	end)

	it(
		"the final review starts the expensive model, and --dry-run names each mode's activity (AC10)",
		function()
			local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
			fakecli.clear(h)
			fakecli.mode(h, "claude.zz-review", "script")
			reviewer()
			local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "final" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(has(fakecli.log(h), "--model claude-opus-5-5")).toBe(true)
			fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/final-review-001.md`)
			-- the row of a code, stream or final review is buffered in the author's worktree under the subject the dispatcher
			-- prints for the author's `./zn commit` ("<id>: <note>"), with the model the dispatcher ran
			local lines = buffer.parse(fs.readFile(`{wt}/.cache/measure.tsv`))
			local found = nil :: buffer.Line?
			for _, line in lines do
				if line.subject == "c0010: final-review-001" then
					found = line
				end
			end
			t.expect(found ~= nil).toBe(true)
			t.expect((found :: buffer.Line).model).toBe("claude-opus-5-5")
			t.expect((found :: buffer.Line).phase).toBe("code-review")
			local want: { [string]: { string } } = {
				design = { "zz-review-design", "claude-opus-5-5" },
				raft = { "zz-review-raft", "claude-opus-5-5" },
				final = { "zz-review-final", "claude-opus-5-5" },
				code = { "zz-review-code", "claude-opus-5-5" }, -- expensive: the user ruled it (2026-11-12)
				stream = { "zz-review-stream", "claude-sonnet-5" },
			}
			for mode, w in want do
				local d = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", mode, "--dry-run" })
				t.expect(`{mode}: {has(d.stdout, `activity={w[1]}`)}`).toBe(`{mode}: true`)
				t.expect(`{mode}: {has(d.stdout, `model={w[2]}`)}`).toBe(`{mode}: true`)
			end
		end
	)

	-- verbatim output of the real CLIs (2026-11-12): `grok models` whole, `agent --list-models` shortened to its head, the
	-- Opus 5.5 lines and its tail
	local GROK_LIST = [==[
You are logged in with grok.com.

Default model: grok-4.7-build-fast

Available models:
  - grok-4.7
  * grok-4.7-build-fast (default)
  - grok-4.6
  - grok-4.5
]==]
	local AGENT_LIST = [==[
Available models

auto - Auto (default)
gpt-5.3-codex-low - Codex 5.3 Low
gpt-5.3-codex-low-fast - Codex 5.3 Low Fast
gpt-5.3-codex - Codex 5.3
gpt-5.3-codex-fast - Codex 5.3 Fast
gpt-5.3-codex-high - Codex 5.3 High
gpt-5.3-codex-high-fast - Codex 5.3 High Fast
gpt-5.3-codex-xhigh - Codex 5.3 Extra High
gpt-5.3-codex-xhigh-fast - Codex 5.3 Extra High Fast
gpt-5.2 - GPT-5.2
composer-2.5 - Composer 2.5
claude-opus-5-thinking-high - Claude Opus 5 1M Thinking
claude-opus-5-thinking-high-fast - Claude Opus 5 1M Thinking Fast
gpt-5.6-sol-high - GPT-5.6 Sol 1M High
claude-opus-5-5-low - Claude Opus 5.5 1M Low
claude-opus-5-5-low-fast - Claude Opus 5.5 1M Low Fast
claude-opus-5-5-medium - Claude Opus 5.5 1M
claude-opus-5-5-medium-fast - Claude Opus 5.5 1M Fast
claude-opus-5-5-high - Claude Opus 5.5 1M High
claude-opus-5-5-high-fast - Claude Opus 5.5 1M High Fast
claude-opus-5-5-xhigh - Claude Opus 5.5 1M Extra High
claude-opus-5-5-xhigh-fast - Claude Opus 5.5 1M Extra High Fast
claude-opus-5-5-max - Claude Opus 5.5 1M Max
claude-opus-5-5-max-fast - Claude Opus 5.5 1M Max Fast
deepseek-v41-flash-1017-high - DeepSeek V4.1 Flash 1017 High
deepseek-v41-flash-1017-max - DeepSeek V4.1 Flash 1017 Max

Tip: use --model <id> (or /model <id> in interactive mode) to switch. Parameterized models also accept quoted overrides, e.g. --model 'claude-opus-4-8[context=1m,effort=high,fast=false]'.

]==]
	it("parseModelList reads the ids the real `grok models` and `agent --list-models` print (D7)", function()
		local grok: { string } = (dispatcher :: any).parseModelList(GROK_LIST)
		t.expect(grok).toEqual({ "grok-4.7", "grok-4.7-build-fast", "grok-4.6", "grok-4.5" })
		local agent: { string } = (dispatcher :: any).parseModelList(AGENT_LIST)
		t.expect(table.find(agent, "auto") ~= nil).toBe(true)
		t.expect(table.find(agent, "claude-opus-5-5-high") ~= nil).toBe(true)
		t.expect(table.find(agent, "claude-opus-5-5-xhigh") ~= nil).toBe(true)
		t.expect(table.find(agent, "deepseek-v41-flash-1017-max") ~= nil).toBe(true)
		for _, id in agent do
			t.expect(`{id}: {string.find(id, "[%s:]") == nil}`).toBe(`{id}: true`) -- no heading, tip or description in an id
		end
		t.expect(#agent).toBe(26)
		t.expect((dispatcher :: any).parseModelList('{"type":"result","subtype":"success"}\n')).toEqual({})
	end)

	-- the poll itself, run for real against a fake gh that counts its calls and answers a sequence of exit codes (the
	-- runner's `./zn run --time` wrapper is cut off: it only bounds). every = 0 and a deadline of 2 to 4 seconds keep it quick.
	it(
		"the wait command re-polls while checks are pending, ends 0 when they pass, 2 when one fails, 3 when time runs out (AC4)",
		function()
			fs.writeFile(
				`{h.bin}/gh`,
				'#!/bin/bash\ncase "$*" in\n "pr view"*) echo "$FAKE_STATE";;\n "pr checks"*)\n n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$FAKE_COUNT"\n seq=($FAKE_SEQ); rc=${seq[$((n-1))]:-${seq[${#seq[@]}-1]}}\n echo "$FAKE_OUT"; exit $rc;;\nesac\n'
			)
			process.exec("chmod", { "+x", `{h.bin}/gh` })
			local count = `{h.f.base}/gh-count`
			local function run(what: string, env: { [string]: string }, seconds: number?): (number, number)
				fs.writeFile(count, "0")
				-- a deadline of a few seconds, so a loaded machine cannot end a poll before its second call
				local command: string = (dispatch :: any).waitCommand(what, 42, seconds or 4, 0)
				local inner = string.match(command, "%-%- (bash %-c .*)$") :: string
				local e = { PATH = `{h.bin}:{process.env.PATH}`, FAKE_COUNT = count }
				for k, v in env do
					e[k] = v
				end
				local code = fixture.exec(h.f.main, "bash", { "-c", inner }, { env = e }).code
				return code, tonumber(fs.readFile(count)) :: number
			end
			local code, calls = run("checks", { FAKE_SEQ = "8", FAKE_OUT = "pending" }, 2)
			t.expect(code).toBe(3) -- pending until the deadline is "ran out", not "failed"
			t.expect(calls > 1).toBe(true) -- and it polled more than once
			code, calls = run("checks", { FAKE_SEQ = "8 0", FAKE_OUT = "x" })
			t.expect(code).toBe(0)
			t.expect(calls).toBe(2)
			code = run("checks", { FAKE_SEQ = "1 0", FAKE_OUT = "no checks reported on the branch" })
			t.expect(code).toBe(0)
			code = run("checks", { FAKE_SEQ = "1", FAKE_OUT = "build failed" })
			t.expect(code).toBe(2) -- the same unexplained failure three times in a row
			code = run("checks", { FAKE_SEQ = "1 8 1 0", FAKE_OUT = "gh: network error" })
			t.expect(code).toBe(0) -- a transient error between good polls is not a failed check
			code = run("checks", { FAKE_SEQ = "1 1 0", FAKE_OUT = "gh: network error" })
			t.expect(code).toBe(0)
			t.expect((run("merged", { FAKE_STATE = "MERGED" }))).toBe(0)
			t.expect((run("merged", { FAKE_STATE = "CLOSED" }))).toBe(2)
			t.expect((run("merged", { FAKE_STATE = "OPEN" }))).toBe(3)
		end
	)

	it(
		"parsePr reads GitHub's mergeable state: CONFLICTING conflicts, UNKNOWN (still computing) does not, missing does not (AC5)",
		function()
			local function pr(mergeable: string?): any
				local field = if mergeable then `,"mergeable":"{mergeable}"` else ""
				return dispatcher.parsePr(
					`\{"number":7,"state":"OPEN","isDraft":false,"headRefOid":"abc","statusCheckRollup":[]{field}\}`
				)
			end
			t.expect(pr("MERGEABLE").mergeable).toBe(true)
			t.expect(pr("MERGEABLE").conflicting).toBe(false)
			t.expect(pr("CONFLICTING").mergeable).toBe(false)
			t.expect(pr("CONFLICTING").conflicting).toBe(true)
			t.expect(pr("UNKNOWN").mergeable).toBe(false)
			t.expect(pr("UNKNOWN").conflicting).toBe(false)
			t.expect(pr(nil).conflicting).toBe(false)
			t.expect(pr("UNKNOWN").mergeState).toBe("UNKNOWN")
			t.expect(pr("MERGEABLE").mergeState).toBe("MERGEABLE")
			local function rollup(entries: string): any
				return dispatcher.parsePr(
					`\{"number":7,"state":"OPEN","isDraft":false,"headRefOid":"abc","mergeable":"MERGEABLE","statusCheckRollup":[{entries}]\}`
				)
			end
			t.expect(rollup('{"conclusion":"FAILURE"}').failed).toBe(true)
			t.expect(rollup('{"conclusion":"SUCCESS"},{"state":"PENDING"}').failed).toBe(false)
			t.expect(rollup('{"conclusion":"SUCCESS"},{"state":"PENDING"}').green).toBe(false)
		end
	)
end)
