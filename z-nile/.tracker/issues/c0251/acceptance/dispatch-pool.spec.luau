--!strict
-- c0251 AC3 (final), AC5, AC6, AC7, AC11, AC12, AC14 and AC17: the real dispatcher runs reviews against fake CLIs (@tests/lib/fakecli,
-- with a model-aware `claude` and a `kimi`) in a fixture under .cache/c0251-dispatch-pool, from a worktree of it. A review goes to the
-- first runnable pick of the picker (a model line other than the writer's and the previous round's), falls to the next on quota,
-- skips c0306's refused tries, stamps `Fallback:` only when the attempt that wrote it was the writer's own line, supersedes a flagged
-- round, and a role without `rotate` keeps the toml order. Each case has its own item: a round is consumed by the review that files it.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local M: any = models

local MODELS = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240

[families]
opus = ["claude-opus-"]
fable = ["claude-fable-"]
sonnet = ["claude-sonnet-"]
haiku = ["claude-haiku-"]
kimi = ["kimi-"]
grok = ["grok-"]

[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[fallback.agent]
model = "claude-opus-5-5"
runtime = "cursor-cli"
max_calls = 30
max_minutes = 60

[member.fable]
cli = "claude"
model = "claude-fable-5-2"
runtime = "claude-cli"

[member.opus]
cli = "claude"
model = "claude-opus-5-5"
runtime = "claude-cli"

[member.sonnet]
cli = "claude"
model = "claude-sonnet-5-5"
runtime = "claude-cli"

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.implementation]
model = "claude-sonnet-5-5"
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
rotate = true
pool = ["fable"]
fallbacks = ["kimi", "grok", "agent"]

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
author = "implementation"
rotate = true
pool = ["fable"]
fallbacks = ["kimi", "grok", "agent"]

[roles.final-review]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
rotate = true
pool = ["opus"]
fallbacks = ["kimi", "grok"]

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
rotate = true
pool = ["fable"]
fallbacks = ["kimi"]

[roles.stream-review]
model = "claude-haiku-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 5000
effort = "medium"
rotate = true
pool = ["sonnet"]
fallbacks = []
]]

-- the design-challenge role without its Fable member
local NO_POOL = "[roles.design-challenge]\npool = []\n"
-- the code-review role at effort high: a grok- try is not a review model there (c0306), so it is skipped
-- no rotate on the final-review role: it is tried in the toml order, its pool member after its own model
local PLAIN_FINAL = "[roles.final-review]\nrotate = false\n"
local AT_HIGH = '[roles.code-review]\neffort = "high"\n'
-- the code-review role with nothing but its own model
local OPUS_ONLY = "[roles.code-review]\npool = []\nfallbacks = []\n"

local IDEA_MODELS = [[
[dispatch]
stall_seconds = 30

[families]
opus = ["claude-opus-"]
fable = ["claude-fable-"]
kimi = ["kimi-"]

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
rotate = true
fallbacks = ["kimi"]
]]

local IDEA_REPLY = [=[
if [[ "$args" == *"Challenge this idea once"* ]]; then
  printf '## Findings\n- none\n\n## Verdict\napprove\n'
else
  printf '## Problem\n- The board hides a finished card before a person can read it.\n\n## Solution\n- A finished card stays visible until the person dismisses it.\n\n## Non-goals\n- The board does not change how a card is scored.\n\n## Open\n- none\n'
fi
]=]
local IDEA_CLAUDE = '#!/bin/bash\nargs="$*"\n'
	.. 'if [[ "$args" == *claude-fable* && "$IDEA_FAIL_FABLE" == 1 ]]; then echo failed >&2; exit 1; fi\n'
	.. 'if [[ "$args" == *claude-opus* && "$IDEA_FAIL_OPUS" == 1 ]]; then echo failed >&2; exit 1; fi\n'
	.. IDEA_REPLY
	.. 'echo \'{"type":"result","subtype":"success","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"output_tokens":5}}\'\n'
local IDEA_KIMI = '#!/bin/bash\nargs="$*"\n'
	.. IDEA_REPLY
	.. 'echo \'{"type":"usage.record","usage":{"inputOther":2061,"output":300,"inputCacheRead":15104,"inputCacheCreation":0}}\'\n'

local HEADER = "when\tsubject\tadded\tremoved\tphase\ttokens\tmodel\twall\tcpu\tai\ttest\tunmeasured\n"
local function spendRows(rows: { { string } }): string
	local text = HEADER
	for _, r in rows do
		text ..= `2026-11-15 08:00\t{r[3] or r[1]}\t0\t0\t{r[1]}\t\t{r[2]}\t\t\t\t\t\n`
	end
	return text
end

local function marked(id: string): string
	return (
		string.gsub(
			trackerfix.stub(id, id, "new-quiet-copper-falcon"),
			"design: draft\n",
			"design: draft\nreviews: judged\n",
			1
		)
	)
end

local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: demo\nslug: demo\nissues: [{issues}]\nreviews: judged\ncreated: 2026-01-01\nstatus: active-a-b-c\n---\n\n# {id}\n`
end

local OPUS_DESIGN = { { "prep", "claude-opus-5-5-high" } }
local SONNET_BUILD = { { "build", "claude-sonnet-5-5-high" } }
local function stamped(model: string, effort: string?, extra: string?): string
	return `Model: {model}\n{if effort then `Effort: {effort}\n` else ""}{extra or ""}# Review\n\nVerdict: approve\n`
end

local ITEMS: { [string]: string } = {}
local function item(
	id: string,
	rows: { { string } }?,
	files: { [string]: string }?,
	closer: string?,
	unmarked: boolean?
)
	ITEMS[`pickman/.tracker/issues/{id}/{id}.md`] = if unmarked
		then trackerfix.stub(id, id, "new-quiet-copper-falcon")
		else marked(id)
	if rows then
		ITEMS[`pickman/.tracker/issues/{id}/spend.d/m.local-1.tsv`] = spendRows(rows)
	end
	local more: { [string]: string } = files or {}
	for name, text in more do
		ITEMS[`pickman/.tracker/issues/{id}/{name}`] = text
	end
	if closer then
		ITEMS[`pickman/.tracker/issues/{id}/.models.toml`] = closer
	end
end

local h: fakecli.Harness
local wt = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

-- the fake claude of fakecli, taught to act by the model it is asked for: <fakes>/claude-<line> (fable, opus, haiku) beats the
-- step's and the CLI's own mode
local function modelAware(script: string): string
	local marker = 'case "$mode" in'
	local at = string.find(script, marker, 1, true) :: number
	local override =
		'for m in fable opus haiku sonnet; do case "$*" in *"--model claude-$m-"*) [ -f "$FAKE_DIR/claude-$m" ] && mode=$(cat "$FAKE_DIR/claude-$m");; esac; done\n'
	return string.sub(script, 1, at - 1) .. override .. string.sub(script, at)
end

local KIMI = table.concat({
	"#!/bin/sh",
	'step=$(printf "%s" "$*" | sed -n "s/.*z-nile step \\([a-z-]*\\).*/\\1/p" | head -n 1)',
	'id=$(printf "%s" "$*" | sed -n "s/.* for \\([cfdR][0-9][0-9][0-9][0-9]\\).*/\\1/p" | head -n 1)',
	'mode=ok; [ -f "$FAKE_DIR/kimi" ] && mode=$(cat "$FAKE_DIR/kimi")',
	'[ -f "$FAKE_DIR/kimi.$step" ] && mode=$(cat "$FAKE_DIR/kimi.$step")',
	'{ echo "kimi step=$step mode=$mode cwd=$(pwd -P)"; echo "args=$*"; } >> "$FAKE_DIR/log"',
	'usage=\'{"type":"usage.record","usage":{"inputOther":10,"output":5}}\'',
	'case "$mode" in',
	'ok) echo "$usage" ;;',
	'script) id="$id" step="$step" sh "$FAKE_DIR/script.sh" >> "$FAKE_DIR/log" 2>&1; echo "$usage" ;;',
	'quota) echo "Error: rate limit exceeded (too many requests)" >&2; exit 1 ;;',
	"fail) echo boom >&2; exit 1 ;;",
	"esac",
	"",
}, "\n")

local function znIn(args: { string }, extra: { [string]: string }?): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	local env: { [string]: string } = {
		FAKE_DIR = h.fakes,
		PATH = `{h.bin}:{process.env.PATH}`,
		ZN_AGENT_TOKEN_FILE = h.token,
		GH_TOKEN = "the-users-token",
		CLAUDECODE = "",
		AI_AGENT = "",
		CLAUDE_EFFORT = "",
		ZN_DISPATCH = "",
		ZN_HEADLESS = "",
		ZN_MODEL = "",
		CLAUDE_CODE_SESSION_ID = "",
		KIMI_SESSION_ID = "",
		KIMI_CODE_SESSION_ID = "",
	}
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return fixture.exec(wt, "bash", argv, { env = env })
end

-- the reviewer (whichever model is asked) writes this review, never a record
local function reviewer()
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
end

local function modes(m: { [string]: string })
	fakecli.clear(h)
	for name, value in m do
		fakecli.mode(h, name, value)
	end
	reviewer()
end

local function review(id: string, mode: string, author: string?, env: { [string]: string }?): fixture.Result
	local args = { "dispatch", "zz-review", id, "--mode", mode }
	if author then
		table.insert(args, "--author")
		table.insert(args, author)
	end
	return znIn(args, env)
end
local function reviewOk(id: string, mode: string, author: string?, env: { [string]: string }?): fixture.Result
	local r = review(id, mode, author, env)
	if not r.ok then
		error(`dispatch zz-review {id} --mode {mode} failed: {r.stdout}{r.stderr}`, 2)
	end
	return r
end
local function dry(id: string, mode: string, author: string?): string
	local args = { "dispatch", "zz-review", id, "--mode", mode, "--dry-run" }
	if author then
		table.insert(args, "--author")
		table.insert(args, author)
	end
	local r = znIn(args)
	if not r.ok then
		error(`dry-run {id} --mode {mode} failed: {r.stdout}{r.stderr}`, 2)
	end
	return r.stdout
end

local function filed(path: string): string
	return fs.readFile(`{wt}/{path}`)
end
local function exists(path: string): boolean
	return fs.isFile(`{wt}/{path}`)
end
local function folder(id: string): string
	return `pickman/.tracker/issues/{id}`
end

-- the CLIs and models the fakes were started with, in order: "claude:claude-fable-5-2"
local function started(): { string }
	local log = fakecli.log(h)
	local out = {}
	local positions: { { at: number, cli: string } } = {}
	for at, cli in string.gmatch(log, "()(%a+) step=%S+ mode=%S+ cwd=") do
		table.insert(positions, { at = at, cli = cli :: string })
	end
	for i, p in positions do
		local chunk = string.sub(log, p.at, (positions[i + 1] and positions[i + 1].at or #log + 1) - 1)
		local model = string.match(chunk, "%-%-model (%S+)") or string.match(chunk, " %-m (%S+)") or "?"
		table.insert(out, `{p.cli}:{(string.gsub(model, "%[.*$", ""))}`)
	end
	return out
end

local function line(text: string, prefix: string): string?
	for l in string.gmatch(text .. "\n", "([^\n]*)\n") do
		if string.sub(l, 1, #prefix) == prefix then
			return l
		end
	end
	return nil
end

return t.spec("c0251 the dispatcher runs reviews through the picker", function(it)
	it(
		"sets up a tracker with .models.toml, marked items with the writers' spend rows, and the fake CLIs",
		function()
			-- AC17, AC5: an Opus-written design (c0010; c0011 has no Fable member; c0012 sees Fable refused; c0014 sees everything but Opus refused)
			item("c0010", OPUS_DESIGN)
			item("c0011", OPUS_DESIGN, nil, NO_POOL)
			item("c0012", OPUS_DESIGN)
			item("c0014", OPUS_DESIGN)
			-- the author is not recorded: the design role's first choice (Opus) stands in, and the reason says so
			item("c0015", nil)
			-- AC5: a Sonnet-written code review goes to Opus first; Opus refused, the other Claude model on the same CLI runs
			item("c0013", SONNET_BUILD)
			item("c0022", SONNET_BUILD)
			item("c0025", SONNET_BUILD, nil, AT_HIGH)
			-- AC7: a flagged newest round allows the next, and the next one rotates away from it; an unflagged one does not
			item("c0016", SONNET_BUILD, {
				["review-001.md"] = stamped(
					"claude-opus-5-5",
					"xhigh",
					"Fallback: the model that wrote the text ran the review (claude-opus-5-5)\n"
				),
			})
			item("c0017", SONNET_BUILD, { ["review-001.md"] = stamped("claude-opus-5-5", "xhigh") })
			-- AC5: the only runnable try is the author's exact model
			item("c0018", { { "build", "claude-opus-5-5-high" } }, nil, OPUS_ONLY)
			-- AC11: a Sonnet-written layer (c0019, with a stamped earlier review that a stream review must not read) and a Haiku one (c0020)
			item("c0019", SONNET_BUILD, { ["review-001.md"] = stamped("claude-haiku-5-5", "medium") })
			item("c0020", { { "build", "claude-haiku-5-5-medium" } })
			-- AC11: a Haiku-written layer whose cheap Sonnet is refused is reviewed by Haiku itself, flagged (c0027)
			item("c0027", { { "build", "claude-haiku-5-5-medium" } })
			-- AC4, AC7 in an unmarked item: stamped rounds are priors, and a flagged round is superseded (c0029); an unflagged one is not (c0030)
			item("c0029", SONNET_BUILD, {
				["review-001.md"] = stamped(
					"claude-opus-5-5",
					"xhigh",
					"Fallback: the model that wrote the text ran the review\n"
				),
			}, nil, true)
			item(
				"c0030",
				SONNET_BUILD,
				{ ["review-001.md"] = stamped("claude-opus-5-5", "xhigh") },
				nil,
				true
			)
			-- AC17 (the live author): the rows say Opus wrote the design, the lead says Fable (c0031 by --author, c0032 by ZN_MODEL)
			item("c0031", OPUS_DESIGN)
			item("c0032", OPUS_DESIGN)
			-- AC3 final: idea by Fable, design by Opus, build by Sonnet; the final review's author is the build's only
			item("c0023", {
				{ "idea", "claude-fable-5-2-medium", "c0023 ok" },
				{ "prep", "claude-opus-5-5-high" },
				{ "build", "claude-sonnet-5-5-high" },
			})
			-- AC14: the final review of R0093 (built by Fable) runs on a role with no rotate
			item("c0024", { { "build", "claude-fable-5-2-high" } })
			-- raft-mode review with rotate: R0094's raft was written by Fable and its coherence round was Opus's; R0095's has no round
			item("c0033", { { "prep", "claude-fable-5-2-high", "raft-prep" } })
			item("c0034", { { "prep", "claude-fable-5-2-high", "raft-prep" } })
			ITEMS["pickman/.tracker/rafts/R0092/R0092.md"] = raftDoc("R0092", "c0023")
			ITEMS["pickman/.tracker/rafts/R0093/R0093.md"] = raftDoc("R0093", "c0024")
			ITEMS["pickman/.tracker/rafts/R0093/.models.toml"] = PLAIN_FINAL
			ITEMS["pickman/.tracker/rafts/R0094/R0094.md"] = raftDoc("R0094", "c0033")
			ITEMS["pickman/.tracker/rafts/R0094/design-review-001.md"] = stamped("claude-opus-5-5", "xhigh")
			ITEMS["pickman/.tracker/rafts/R0095/R0095.md"] = raftDoc("R0095", "c0034")
			ITEMS[".models.toml"] = MODELS
			h = fakecli.new("c0251-dispatch-pool", ITEMS)
			fs.writeFile(`{h.bin}/claude`, modelAware(fakecli.script("claude")))
			fs.writeFile(`{h.bin}/kimi`, KIMI)
			process.exec("chmod", { "+x", `{h.bin}/claude`, `{h.bin}/kimi` })
			wt = fixture.physical(`{h.f.base}/wt-pool`) or `{h.f.base}/wt-pool`
			fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "prep-pool", wt, "origin/main" })
			wt = fixture.physical(wt) :: string
			-- the raft folders (and the members' raft: lines) exist in this worktree only, as in a raft worktree
			local function toRaft(id: string, raft: string)
				local doc = `{wt}/{folder(id)}/{id}.md`
				fs.writeFile(doc, (string.gsub(fs.readFile(doc), "\nraft:[^\n]*", `\nraft: {raft}`, 1)))
			end
			for _, id in { "c0019", "c0020", "c0027" } do
				toRaft(id, "R0091")
			end
			toRaft("c0033", "R0094")
			toRaft("c0034", "R0095")
			toRaft("c0023", "R0092")
			toRaft("c0024", "R0093")
			fs.writeDir(`{wt}/pickman/.tracker/rafts/R0091`)
			fs.writeFile(
				`{wt}/pickman/.tracker/rafts/R0091/R0091.md`,
				raftDoc("R0091", "c0019, c0020, c0027")
			)
			-- the model-aware claude is the one on PATH; the kimi is new
			t.expect(fs.isFile(`{h.bin}/kimi`)).toBe(true)
		end
	)

	it(
		"AC17: an Opus-written design picks Fable first, on the claude fake, and the file records it with no Fallback:",
		function()
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0010", "design")
			t.expect(filed(`{folder("c0010")}/design-review-001.md`))
				.toBe("Model: claude-fable-5-2\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(started()).toEqual({ "claude:claude-fable-5-2" })
		end
	)

	it(
		"AC5: without the Fable member an Opus-written design goes to kimi first, and claude is never started",
		function()
			modes({ ["kimi.zz-review"] = "script", ["claude.zz-review"] = "script" })
			reviewOk("c0011", "design")
			t.expect(filed(`{folder("c0011")}/design-review-001.md`))
				.toBe("Model: kimi-code-k3.1-pro\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(started()).toEqual({ "kimi:kimi-code/k3.1-pro" })
		end
	)

	it("AC5: a Sonnet-written code review goes to Opus first, unflagged", function()
		modes({ ["claude.zz-review"] = "script" })
		reviewOk("c0022", "code")
		t.expect(filed(`{folder("c0022")}/review-001.md`))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
		t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
	end)

	it(
		"AC5: a quota on the first falls to the next pick, and AC17: even to the other model of the same CLI",
		function()
			modes({ ["claude.zz-review"] = "script", ["claude-opus"] = "quota" })
			reviewOk("c0013", "code")
			t.expect(started()).toEqual({ "claude:claude-opus-5-5", "claude:claude-fable-5-2" })
			t.expect(filed(`{folder("c0013")}/review-001.md`))
				.toBe("Model: claude-fable-5-2\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
		end
	)

	it(
		"AC17: with Fable refused kimi runs next, and AC6: the fall-through to a tier 1 pick stamps no Fallback:",
		function()
			modes({
				["claude.zz-review"] = "script",
				["claude-fable"] = "quota",
				["kimi.zz-review"] = "script",
			})
			reviewOk("c0012", "design")
			t.expect(started()).toEqual({ "claude:claude-fable-5-2", "kimi:kimi-code/k3.1-pro" })
			local text = filed(`{folder("c0012")}/design-review-001.md`)
			t.expect(text).toBe("Model: kimi-code-k3.1-pro\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(has(text, "Fallback:")).toBe(false)
		end
	)

	it(
		"AC17: with every other line refused, Opus runs last and the file carries Fallback: with the exact-model reason, and AC6: only the attempt that wrote it counts",
		function()
			modes({
				["claude.zz-review"] = "script",
				["claude-fable"] = "fail",
				["kimi"] = "fail",
				["grok"] = "fail",
			})
			local r = reviewOk("c0014", "design")
			t.expect(started()).toEqual({
				"claude:claude-fable-5-2",
				"kimi:kimi-code/k3.1-pro",
				"grok:grok-4.7",
				"claude:claude-opus-5-5",
			})
			local text = filed(`{folder("c0014")}/design-review-001.md`)
			t.expect(string.sub(text, 1, #"Model: claude-opus-5-5\nEffort: xhigh\nFallback: "))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\nFallback: ")
			local reason = string.match(text, "\nFallback: ([^\n]*)\n") :: string
			t.expect(has(reason, "claude-opus-5-5")).toBe(true)
			t.expect(has(reason, "assumed")).toBe(false)
			t.expect(#reason <= 120).toBe(true)
			-- the dispatcher says so on stderr
			t.expect(has(r.stderr .. r.stdout, "fallback review: ")).toBe(true)
		end
	)

	it(
		"AC6: Fallback: is stamped in the same call as Model:, naming an assumed author when no row records it",
		function()
			modes({
				["claude.zz-review"] = "script",
				["claude-fable"] = "fail",
				["kimi"] = "fail",
				["grok"] = "fail",
			})
			reviewOk("c0015", "design")
			local text = filed(`{folder("c0015")}/design-review-001.md`)
			t.expect(string.sub(text, 1, #"Model: claude-opus-5-5\n")).toBe("Model: claude-opus-5-5\n")
			local reason = string.match(text, "\nFallback: ([^\n]*)\n") :: string
			t.expect(has(reason, "assumed")).toBe(true)
			t.expect(has(reason, "role")).toBe(true)
			-- a review that an unflagged pick filed carries no Fallback: line
			t.expect(has(filed(`{folder("c0010")}/design-review-001.md`), "Fallback:")).toBe(false)
		end
	)

	it("AC5: a role whose only try is the author's exact model still runs it, flagged", function()
		modes({ ["claude.zz-review"] = "script" })
		reviewOk("c0018", "code")
		local text = filed(`{folder("c0018")}/review-001.md`)
		t.expect(string.sub(text, 1, #"Model: claude-opus-5-5\nEffort: xhigh\nFallback: "))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\nFallback: ")
		t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
	end)

	it(
		"AC5: c0306's refused tries are still skipped on the picked order: grok at effort high is never started",
		function()
			modes({
				["claude"] = "fail",
				["kimi"] = "fail",
				["agent.zz-review"] = "script",
			})
			local r = reviewOk("c0025", "code")
			-- Opus, Fable and kimi failed; grok at high is not a review model and is skipped, so the Opus on the agent runs
			t.expect(started()).toEqual({
				"claude:claude-opus-5-5",
				"claude:claude-fable-5-2",
				"kimi:kimi-code/k3.1-pro",
				"agent:claude-opus-5-5",
			})
			t.expect(has(r.stderr .. r.stdout, "grok-4.7 at effort high is not a review model: skipped"))
				.toBe(true)
			t.expect(filed(`{folder("c0025")}/review-001.md`))
				.toBe("Model: claude-opus-5-5\nEffort: high\n# Review\n\nVerdict: approve\n")
		end
	)

	it(
		"AC7: in a marked item the next round is allowed over a newest round that carries Fallback:",
		function()
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0016", "code")
			-- the flagged round stays as history, the new round takes the next number and rotates away from the flagged one's line
			t.expect(has(filed(`{folder("c0016")}/review-001.md`), "Fallback:")).toBe(true)
			t.expect(filed(`{folder("c0016")}/review-002.md`))
				.toBe("Model: claude-fable-5-2\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(started()).toEqual({ "claude:claude-fable-5-2" })
		end
	)

	it(
		"AC7: the round it filed counts as a prior for the next, and an unflagged newest round allows none",
		function()
			local out = dry("c0016", "code")
			t.expect(has(out, "previous=claude-fable-5-2")).toBe(true)
			modes({ ["claude.zz-review"] = "script" })
			local r = review("c0016", "code")
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "there is no second round")).toBe(true)
			t.expect(exists(`{folder("c0016")}/review-003.md`)).toBe(false)
			local plain = review("c0017", "code")
			t.expect(plain.ok).toBe(false)
			t.expect(has(plain.stdout .. plain.stderr, "there is no second round")).toBe(true)
			t.expect(exists(`{folder("c0017")}/review-002.md`)).toBe(false)
		end
	)

	it("AC17: a dispatched run orders by --author, the lead's own model, not by the rows", function()
		-- the rows say Opus wrote c0031's design; the lead is Fable, so Opus reviews first and nothing is flagged
		modes({ ["claude.zz-review"] = "script" })
		local out = dry("c0031", "design", "claude-fable-5-2")
		t.expect(has(out, "pool: author=claude-fable-5-2 (recorded via live) previous=none")).toBe(true)
		reviewOk("c0031", "design", "claude-fable-5-2")
		t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
		t.expect(filed(`{folder("c0031")}/design-review-001.md`))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
	end)

	it("AC17: a dispatched run with no --author takes ZN_MODEL, else the rows, and says which", function()
		modes({ ["claude.zz-review"] = "script" })
		reviewOk("c0032", "design", nil, { ZN_MODEL = "claude-fable-5-2" })
		t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
		-- the typed --author wins over ZN_MODEL
		local out = znIn({
			"dispatch",
			"zz-review",
			"c0010",
			"--mode",
			"design",
			"--dry-run",
			"--author",
			"claude-opus-5-5",
		}, {
			ZN_MODEL = "claude-fable-5-2",
		})
		t.expect(has(out.stdout, "pool: author=claude-opus-5-5 (recorded via live)")).toBe(true)
		-- no author at all: the rows
		t.expect(has(dry("c0010", "design"), "(recorded via row)")).toBe(true)
		-- no row either: the role's first choice, and the pool line says assumed
		t.expect(has(dry("c0015", "design"), "(assumed via role)")).toBe(true)
	end)

	it("AC17: the live author applies to the step a final review reads, the build", function()
		-- R0092's rows say Sonnet built it; a Fable lead's final review goes to Opus first and Fable is the fallback
		local out = dry("R0092", "final", "claude-fable-5-2")
		t.expect(has(out, "pool: author=claude-fable-5-2 (recorded via live)")).toBe(true)
		t.expect(has(out, "pick: claude claude-opus-5-5")).toBe(true)
		t.expect(has(out, "tier=3 family=fable fallback=yes")).toBe(true)
	end)

	it(
		"AC4: an unmarked item's stamped round is a previous reviewer, and a flagged one is superseded",
		function()
			local out = dry("c0029", "code")
			t.expect(has(out, "previous=claude-opus-5-5")).toBe(true)
			t.expect(has(out, "pick: claude claude-fable-5-2")).toBe(true)
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0029", "code")
			t.expect(filed(`{folder("c0029")}/review-002.md`))
				.toBe("Model: claude-fable-5-2\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(started()).toEqual({ "claude:claude-fable-5-2" })
		end
	)

	it("AC7: an unmarked item's unflagged round still allows no second one", function()
		modes({ ["claude.zz-review"] = "script" })
		local r = review("c0030", "code")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "there is no second round")).toBe(true)
		t.expect(exists(`{folder("c0030")}/review-002.md`)).toBe(false)
	end)

	it(
		"AC11: a stream review runs on stream-review, picks away from the author's family and reads no priors",
		function()
			modes({ ["claude.zz-review"] = "script" })
			local r = reviewOk("c0019", "stream")
			-- a Sonnet-written layer: the cheap Haiku role runs, though a stamped Haiku review sits in the folder (priors are not read)
			local out = filed("pickman/.tracker/rafts/R0091/stream-review-c0019-001.md")
			t.expect(out).toBe("Model: claude-haiku-5-5\nEffort: medium\n# Review\n\nVerdict: approve\n")
			t.expect(started()).toEqual({ "claude:claude-haiku-5-5" })
			local record = line(r.stdout, "record: ") :: string
			t.expect(has(record, "--model claude-haiku-5-5-medium")).toBe(true)
			t.expect(has(dry("c0019", "stream"), "previous=none")).toBe(true)
		end
	)

	it("AC11: a Haiku-written layer's stream review goes to the cheap Sonnet first, unflagged", function()
		modes({ ["claude.zz-review"] = "script" })
		reviewOk("c0020", "stream")
		t.expect(started()).toEqual({ "claude:claude-sonnet-5-5" })
		t.expect(filed("pickman/.tracker/rafts/R0091/stream-review-c0020-001.md"))
			.toBe("Model: claude-sonnet-5-5\nEffort: medium\n# Review\n\nVerdict: approve\n")
	end)

	it(
		"AC11: a stream review run by the layer writer's own line records Fallback:, and the next round supersedes it",
		function()
			modes({ ["claude.zz-review"] = "script", ["claude-sonnet"] = "fail" })
			local r = reviewOk("c0027", "stream")
			t.expect(started()).toEqual({ "claude:claude-sonnet-5-5", "claude:claude-haiku-5-5" })
			local text = filed("pickman/.tracker/rafts/R0091/stream-review-c0027-001.md")
			t.expect(string.sub(text, 1, #"Model: claude-haiku-5-5\nEffort: medium\nFallback: "))
				.toBe("Model: claude-haiku-5-5\nEffort: medium\nFallback: ")
			t.expect(has(r.stderr .. r.stdout, "fallback review: ")).toBe(true)
			-- a flagged stream review is superseded: the cross-model re-review files round 2, with Sonnet back
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0027", "stream")
			t.expect(filed("pickman/.tracker/rafts/R0091/stream-review-c0027-002.md"))
				.toBe("Model: claude-sonnet-5-5\nEffort: medium\n# Review\n\nVerdict: approve\n")
			t.expect(has(filed("pickman/.tracker/rafts/R0091/stream-review-c0027-001.md"), "Fallback:"))
				.toBe(true)
		end
	)

	it(
		"AC3: a final review's author is the writers of the build only, not the idea's and the design's",
		function()
			local out = dry("R0092", "final")
			t.expect(has(out, "pool: author=claude-sonnet-5-5 ")).toBe(true)
			-- Fable (idea) and Opus (design) are not authors, so the role's own first choice stays first, unflagged
			t.expect(has(out, "pick: claude claude-fable-5-2")).toBe(true)
			t.expect(has(out, "tier=3")).toBe(false)
		end
	)

	it("AC14: a role with no rotate tries in the toml order, whoever wrote the text", function()
		-- R0093 was built by Fable and its final-review role has rotate = false: Fable is still the first pick, with no tier above 1
		local out = dry("R0093", "final")
		t.expect(has(out, "pool: no rotation")).toBe(true)
		t.expect(has(out, "tier=2")).toBe(false)
		t.expect(has(out, "tier=3")).toBe(false)
		t.expect(has(out, "pick: claude claude-fable-5-2")).toBe(true)
		-- and the run keeps the order: Fable refused, then the pool member, Opus
		modes({ ["claude.zz-review"] = "script", ["claude-fable"] = "fail" })
		reviewOk("R0093", "final")
		t.expect(started()).toEqual({ "claude:claude-fable-5-2", "claude:claude-opus-5-5" })
		t.expect(filed("pickman/.tracker/rafts/R0093/final-review-001.md"))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
	end)

	it(
		"AC14: a z-raft authoring step on a role that carries pool and rotate is tried in the toml order",
		function()
			-- the same `raft` role reviews a raft (pool and rotation) and authors one (its model, then its fallbacks)
			local layers = { M.parse(MODELS, ".models.toml") }
			local authoring = M.resolve(layers, "z-raft")
			local ids = {}
			for _, s in M.tries(authoring) do
				table.insert(ids, `{s.cli}:{s.model}`)
			end
			t.expect(ids).toEqual({ "claude:claude-opus-5-5", "kimi:kimi-code-k3.1-pro" })
			t.expect(authoring.rotate).toBe(false)
			local reviewing = M.resolve(layers, "zz-review", "raft")
			t.expect(#M.tries(reviewing)).toBe(3)
			t.expect(reviewing.rotate).toBe(true)
			-- the dispatcher's plan for the z-raft step agrees: no pool member, no tiers
			local plan = znIn({ "dispatch", "z-raft", "R0093", "--dry-run" })
			t.expect(plan.ok).toBe(true)
			t.expect(has(plan.stdout, "pool: no rotation")).toBe(true)
			t.expect(has(plan.stdout, "member=")).toBe(false)
			t.expect(has(plan.stdout, "claude-fable-5-2")).toBe(false)
		end
	)

	it(
		"AC14: a raft-mode review rotates on the raft's writer and on the raft's previous coherence round",
		function()
			-- R0095: the raft was written by Fable (the members' raft-prep rows), so Opus reviews it first, unflagged
			modes({ ["claude.zz-review"] = "script" })
			local out = dry("R0095", "raft")
			t.expect(has(out, "pool: author=claude-fable-5-2 (recorded via row) previous=none")).toBe(true)
			reviewOk("R0095", "raft")
			t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
			t.expect(filed("pickman/.tracker/rafts/R0095/design-review-001.md"))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			-- R0094: the same writer, and its coherence round was Opus's, so kimi (a line that is neither) is the pick
			local second = dry("R0094", "raft")
			t.expect(has(second, "previous=claude-opus-5-5")).toBe(true)
			t.expect(has(second, "pick: kimi kimi-code-k3.1-pro")).toBe(true)
			t.expect(has(second, "tier=3 family=fable fallback=yes")).toBe(true)
		end
	)

	it("AC14: a fixture with no [families] and no rotate loads and tries in the toml order", function()
		local text = [[
[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 1000
fallbacks = ["kimi"]
]]
		local layer = M.parse(text, ".models.toml")
		t.expect(layer.families).toEqual({})
		local r = M.resolve({ layer }, "z-design")
		t.expect(r.rotate).toBe(false)
		local ids = {}
		for _, s in M.tries(r) do
			table.insert(ids, s.model)
		end
		t.expect(ids).toEqual({ "claude-opus-5-5", "kimi-code-k3.1-pro" })
		-- a closer file with no [families] beside the root's families loads, and the families stay the root's
		local closer = M.parse("[roles.design]\nmax_tokens = 5\n", "pickman/.models.toml")
		t.expect(closer.families).toEqual({})
		local both = M.resolve({ M.parse(MODELS, ".models.toml"), closer }, "z-design")
		t.expect(both.families.opus).toEqual({ "claude-opus-" })
	end)

	it(
		"AC12: the idea challenge orders through the same picker with the draft's real writer as the author, and its review records the model and the fallback",
		function()
			local f = trackerfix.new("c0251-idea-pool", { [".models.toml"] = IDEA_MODELS })
			local bin = `{f.base}/bin`
			fs.writeDir(bin)
			fs.writeFile(`{bin}/claude`, IDEA_CLAUDE)
			fs.writeFile(`{bin}/kimi`, IDEA_KIMI)
			process.exec("chmod", { "+x", `{bin}/claude`, `{bin}/kimi` })
			local ideaWt = trackerfix.trOk(f, f.main, { "worktree", "idea-pool" })
			trackerfix.trOk(f, ideaWt, { "sync" })
			local function newIdea(slug: string): string
				return string.match(
					trackerfix.trOk(f, ideaWt, { "new", "issue", "c", slug, "--project", "pickman" }),
					"(c%d+)"
				) :: string
			end
			local path = process.env.PATH or ""
			-- Fable is refused, so kimi drafts; Opus is refused too, so the challenge reaches the writer's own line last
			local id = newIdea("kimi-wrote-it")
			local ran = trackerfix.tr(
				f,
				ideaWt,
				{ "idea", id, "--text", "The board hides a finished card." },
				{
					PATH = `{bin}:{path}`,
					IDEA_FAIL_FABLE = "1",
					IDEA_FAIL_OPUS = "1",
				}
			)
			if not ran.ok then
				error(`idea failed ({ran.code}): {ran.stderr}{ran.stdout}`, 0)
			end
			local out = ran.stdout
			local opusAt = string.find(out, "idea: idea-challenge model claude-opus-5-5", 1, true)
			local kimiAt = string.find(out, "idea: idea-challenge model kimi-code-k3.1-pro", 1, true)
			t.expect(opusAt ~= nil).toBe(true)
			t.expect(kimiAt ~= nil).toBe(true)
			t.expect((opusAt :: number) < (kimiAt :: number)).toBe(true)
			local ideaReview = fs.readFile(`{ideaWt}/pickman/.tracker/issues/{id}/idea-review-001.md`)
			-- kimi challenged its own draft: the review says so
			t.expect(string.sub(ideaReview, 1, #"Model: kimi-code-k3.1-pro\nFallback: "))
				.toBe("Model: kimi-code-k3.1-pro\nFallback: ")
			t.expect(has(ideaReview, "# Idea review 001")).toBe(true)
			-- with no refusal the other line (Opus) challenges Fable's draft first, and its review records no fallback
			local other = newIdea("fable-wrote-it")
			local second = trackerfix.tr(
				f,
				ideaWt,
				{ "idea", other, "--text", "The board hides a finished card." },
				{ PATH = `{bin}:{path}` }
			)
			if not second.ok then
				error(`idea failed ({second.code}): {second.stderr}{second.stdout}`, 0)
			end
			t.expect(has(second.stdout, "idea: idea model claude-fable-5-2")).toBe(true)
			t.expect(has(second.stdout, "idea: idea-challenge model claude-opus-5-5")).toBe(true)
			t.expect(has(second.stdout, "idea: idea-challenge model kimi-code-k3.1-pro")).toBe(false)
			-- Opus is not the writer's line: the review is stamped with its model and no fallback
			local clean = fs.readFile(`{ideaWt}/pickman/.tracker/issues/{other}/idea-review-001.md`)
			t.expect(string.sub(clean, 1, #"Model: claude-opus-5-5\n# Idea review 001"))
				.toBe("Model: claude-opus-5-5\n# Idea review 001")
			t.expect(has(clean, "Fallback:")).toBe(false)
			fixture.git(f.main, { "worktree", "remove", "--force", ideaWt })
			fs.removeDir(f.base)
		end
	)

	it("cleans up", function()
		fixture.git(h.f.main, { "worktree", "remove", "--force", wt })
		fs.removeDir(h.f.base)
	end)
end)
