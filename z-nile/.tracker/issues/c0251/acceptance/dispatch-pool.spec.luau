--!strict
-- c0251 AC3 (final), AC5, AC6, AC7, AC8, AC11, AC12, AC14, AC17 and AC21: the real dispatcher runs reviews against fake CLIs
-- (@tests/lib/fakecli, with a model-aware `claude` and a `kimi`) in a fixture under .cache/c0251-dispatch-pool, from a worktree of
-- it. A review goes to the first runnable pick of the picker (a model line other than the writer's and the previous round's), falls
-- to the next on quota, runs on any model (no refused tries), stamps `Fallback:` only when the attempt that wrote it was the
-- writer's own line, allows no second round of a kind (a `Fallback:` round included) except the extra round of the frontier floor,
-- reads a design's or a raft's writer from its `designed-by` line, and keeps the toml order for a role without `rotate`. Each case
-- has its own item: a round is consumed by the review that files it.
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
composer = ["composer-"]

[review]
frontier = ["claude-opus-5-5", "claude-fable-5-2", "kimi-code-k3.1-pro", "grok-4.7@xhigh"]

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

[member.sonnet]
cli = "claude"
model = "claude-sonnet-5-5"
runtime = "claude-cli"

[member.grok46]
cli = "grok"
model = "grok-4.6"
runtime = "grok-cli"

[member.composer]
cli = "agent"
model = "composer-2.5"
runtime = "cursor-cli"
max_calls = 30
max_minutes = 60

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
fallbacks = ["kimi", "grok"]

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = ["kimi"]

[roles.raft-review]
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
pool = ["sonnet", "grok46", "composer"]
fallbacks = []
]]

-- the design-challenge role without its Fable member
local NO_POOL = "[roles.design-challenge]\npool = []\n"
-- the code-review role at effort high: any model may run a review, so a grok try at high runs there
-- the frontier list a closer file narrows to kimi alone, or to a model no role has
local KIMI_ONLY = '[review]\nfrontier = ["kimi-code-k3.1-pro"]\n'
local NO_ROLE_FRONTIER = '[review]\nfrontier = ["gemini-4-argon"]\n'
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

-- the design's writer is the document's designed-by line (user, 2026-11-16): `designer` is its value, nil for no line
local function designedLine(designer: string?): string
	return if designer then `designed-by: {designer}\n` else ""
end

local function marked(id: string, designer: string?): string
	return (
		string.gsub(
			trackerfix.stub(id, id, "new-quiet-copper-falcon"),
			"design: draft\n",
			`design: draft\nreviews: judged\n{designedLine(designer)}`,
			1
		)
	)
end

local function raftDoc(id: string, issues: string, designer: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: demo\nslug: demo\nissues: [{issues}]\nreviews: judged\n{designedLine(
		designer
	)}created: 2026-01-01\nstatus: active-a-b-c\n---\n\n# {id}\n`
end

local OPUS = "claude-opus-5-5"
local FABLE = "claude-fable-5-2"
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
	unmarked: boolean?,
	designer: string?
)
	ITEMS[`pickman/.tracker/issues/{id}/{id}.md`] = if unmarked
		then trackerfix.stub(id, id, "new-quiet-copper-falcon")
		else marked(id, designer)
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

local function review(id: string, mode: string, env: { [string]: string }?, flag: string?): fixture.Result
	local args = { "dispatch", "zz-review", id, "--mode", mode }
	if flag then
		table.insert(args, flag)
	end
	return znIn(args, env)
end
local function reviewOk(id: string, mode: string, env: { [string]: string }?, flag: string?): fixture.Result
	local r = review(id, mode, env, flag)
	if not r.ok then
		error(`dispatch zz-review {id} --mode {mode} failed: {r.stdout}{r.stderr}`, 2)
	end
	return r
end
local function dry(id: string, mode: string): string
	local args = { "dispatch", "zz-review", id, "--mode", mode, "--dry-run" }
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
		"sets up a tracker with .models.toml, marked items with the writers' designed-by lines and spend rows, and the fake CLIs",
		function()
			-- AC17, AC5: an Opus-designed document (c0010; c0011 has no Fable member; c0012 sees Fable out of quota; c0014 sees everything but Opus fail)
			item("c0010", nil, nil, nil, false, OPUS)
			item("c0011", nil, nil, NO_POOL, false, OPUS)
			item("c0012", nil, nil, nil, false, OPUS)
			item("c0014", nil, nil, nil, false, OPUS)
			-- AC8: a design with no designed-by line, whatever its spend rows say, is refused; a design by a list of two models
			item("c0015", { { "prep", "claude-opus-5-5-high" } })
			item("c0031", { { "prep", "claude-sonnet-5-5-high" } }, nil, nil, false, FABLE)
			item("c0032", nil, nil, nil, false, `[{OPUS}, {FABLE}]`)
			-- AC8 under dispatch: the document has no line, and the dispatcher's own environment names the model
			item("c0035", nil)
			-- AC5: a Sonnet-written code review goes to Opus first; Opus out of quota, the other Claude model on the same CLI runs
			item("c0013", SONNET_BUILD)
			item("c0022", SONNET_BUILD)
			-- AC5 (any model may run any review): the code-review role at effort high reaches grok-4.7 at high, and it runs
			item("c0025", SONNET_BUILD, nil, AT_HIGH)
			-- AC7: a round that records a Fallback: allows no second round, marked or not, and an unflagged one allows none either
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
			-- AC11: a Sonnet-written layer (c0019, with a stamped earlier review that a stream review must not read), a Haiku one (c0020)
			-- and an Opus one (c0036, for the whole stream list)
			item("c0019", SONNET_BUILD, { ["review-001.md"] = stamped("claude-haiku-5-5", "medium") })
			item("c0020", { { "build", "claude-haiku-5-5-medium" } })
			item("c0036", { { "build", "claude-opus-5-5-high" } })
			-- AC11: a Haiku-written layer whose cheap Sonnet is out of quota is reviewed by Haiku itself, with a Fallback: line (c0027)
			item("c0027", { { "build", "claude-haiku-5-5-medium" } })
			-- AC4, AC7 in an unmarked item: stamped rounds are priors, and a flagged round allows no second round (c0029)
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
			-- AC17: no designed-by line is read for a code review: the build rows are (Opus built c0037, so Fable is first)
			item("c0037", { { "build", "claude-opus-5-5-high" } })
			-- AC21: the extra round of the frontier floor. c0040: the only code review ran on Sonnet; c0041: on Fable (met);
			-- c0042: on Sonnet, and the frontier list is kimi alone; c0043: every frontier model is out of quota; c0044: a list
			-- that names no model of the role; c0045: grok at high does not meet grok-4.7@xhigh, c0046: grok at xhigh does
			item("c0040", SONNET_BUILD, { ["review-001.md"] = stamped("claude-sonnet-5-5", "high") })
			item("c0041", SONNET_BUILD, { ["review-001.md"] = stamped("claude-fable-5-2", "xhigh") })
			item(
				"c0042",
				SONNET_BUILD,
				{ ["review-001.md"] = stamped("claude-sonnet-5-5", "high") },
				KIMI_ONLY
			)
			item("c0043", SONNET_BUILD, { ["review-001.md"] = stamped("claude-sonnet-5-5", "high") })
			item(
				"c0044",
				SONNET_BUILD,
				{ ["review-001.md"] = stamped("claude-sonnet-5-5", "high") },
				NO_ROLE_FRONTIER
			)
			item("c0045", SONNET_BUILD, { ["review-001.md"] = stamped("grok-4.7", "high") })
			item("c0046", SONNET_BUILD, { ["review-001.md"] = stamped("grok-4.7", "xhigh") })
			-- AC3 final: idea by Fable, design by Opus, build by Sonnet; the final review's author is the build's only
			item("c0023", {
				{ "idea", "claude-fable-5-2-medium", "c0023 ok" },
				{ "prep", "claude-opus-5-5-high" },
				{ "build", "claude-sonnet-5-5-high" },
			})
			-- AC14: the final review of R0093 (built by Fable) runs on a role with no rotate
			item("c0024", { { "build", "claude-fable-5-2-high" } })
			-- raft-mode review with rotate: the rafts' writers are the raft documents' designed-by lines, whatever the members' raft-prep
			-- rows say (they say Opus, the documents say Fable); R0094's coherence round was Opus's, R0095's has none, R0096 has no line
			item("c0033", { { "prep", "claude-opus-5-5-high", "raft-prep" } })
			item("c0034", { { "prep", "claude-opus-5-5-high", "raft-prep" } })
			item("c0038", { { "prep", "claude-opus-5-5-high", "raft-prep" } })
			ITEMS["pickman/.tracker/rafts/R0092/R0092.md"] = raftDoc("R0092", "c0023")
			ITEMS["pickman/.tracker/rafts/R0093/R0093.md"] = raftDoc("R0093", "c0024")
			ITEMS["pickman/.tracker/rafts/R0093/.models.toml"] = PLAIN_FINAL
			ITEMS["pickman/.tracker/rafts/R0094/R0094.md"] = raftDoc("R0094", "c0033", FABLE)
			ITEMS["pickman/.tracker/rafts/R0094/design-review-001.md"] = stamped("claude-opus-5-5", "xhigh")
			ITEMS["pickman/.tracker/rafts/R0095/R0095.md"] = raftDoc("R0095", "c0034", FABLE)
			ITEMS["pickman/.tracker/rafts/R0096/R0096.md"] = raftDoc("R0096", "c0038")
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
			for _, id in { "c0019", "c0020", "c0027", "c0036" } do
				toRaft(id, "R0091")
			end
			toRaft("c0033", "R0094")
			toRaft("c0034", "R0095")
			toRaft("c0038", "R0096")
			toRaft("c0023", "R0092")
			toRaft("c0024", "R0093")
			fs.writeDir(`{wt}/pickman/.tracker/rafts/R0091`)
			fs.writeFile(
				`{wt}/pickman/.tracker/rafts/R0091/R0091.md`,
				raftDoc("R0091", "c0019, c0020, c0027, c0036")
			)
			-- the model-aware claude is the one on PATH; the kimi is new
			t.expect(fs.isFile(`{h.bin}/kimi`)).toBe(true)
		end
	)

	it(
		"AC17: an Opus-designed document picks Fable first, on the claude fake, and the file records it with no Fallback:",
		function()
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0010", "design")
			t.expect(filed(`{folder("c0010")}/design-review-001.md`))
				.toBe("Model: claude-fable-5-2\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(started()).toEqual({ "claude:claude-fable-5-2" })
		end
	)

	it(
		"AC5: without the Fable member an Opus-designed document goes to kimi first, and claude is never started",
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
		"AC17: with Fable out of quota kimi runs next, and AC6: the fall-through to a tier 1 pick stamps no Fallback:",
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
		"AC17: with every other line failing, Opus runs last and the file carries Fallback: with the exact-model reason, and AC6: only the attempt that wrote it counts",
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
		"AC8: a design review of a document with no designed-by line is refused, naming the document, whatever the spend rows say, and no CLI starts",
		function()
			modes({ ["claude.zz-review"] = "script" })
			local r = review("c0015", "design")
			t.expect(r.ok).toBe(false)
			local said = r.stdout .. r.stderr
			t.expect(has(said, "designed-by")).toBe(true)
			t.expect(has(said, "c0015.md")).toBe(true)
			t.expect(started()).toEqual({})
			t.expect(exists(`{folder("c0015")}/design-review-001.md`)).toBe(false)
			-- the dry-run refuses too, so a lead learns before it starts a subagent
			local d = znIn({ "dispatch", "zz-review", "c0015", "--mode", "design", "--dry-run" })
			t.expect(d.ok).toBe(false)
			t.expect(has(d.stdout .. d.stderr, "designed-by")).toBe(true)
			-- a raft review of a raft document with no line is refused the same way
			local raft = review("R0096", "raft")
			t.expect(raft.ok).toBe(false)
			t.expect(has(raft.stdout .. raft.stderr, "R0096.md")).toBe(true)
			t.expect(started()).toEqual({})
			-- and there is no --author to get past it
			local author = znIn({
				"dispatch",
				"zz-review",
				"c0015",
				"--mode",
				"design",
				"--author",
				"claude-opus-5-5",
			})
			t.expect(author.ok).toBe(false)
			t.expect(started()).toEqual({})
		end
	)

	it(
		"AC8: the writer of a design is its designed-by line, not the spend rows, and a list names every model that wrote it",
		function()
			-- c0031's rows say Sonnet wrote the design; its line says Fable, so Opus is the first pick, unflagged
			local out = dry("c0031", "design")
			t.expect(has(out, "pool: author=claude-fable-5-2 (recorded via designed-by) previous=none"))
				.toBe(true)
			t.expect(has(out, "pick: claude claude-opus-5-5")).toBe(true)
			-- c0032's line is a list of two: Opus and Fable are both the writers, so the first pick is kimi
			local two = dry("c0032", "design")
			t.expect(has(two, "author=claude-opus-5-5,claude-fable-5-2 (recorded via designed-by)"))
				.toBe(true)
			t.expect(has(two, "pick: kimi kimi-code-k3.1-pro")).toBe(true)
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0031", "design")
			t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
			t.expect(filed(`{folder("c0031")}/design-review-001.md`))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
		end
	)

	it(
		"AC8: under dispatch the tool writes the line from the attempt's own model, and adds a second model that revises",
		function()
			modes({ ["claude.zz-review"] = "script" })
			local env =
				{ ZN_DISPATCH = "1", ZN_MODEL = "claude-opus-5-5", ZN_DISPATCH_DIR = `{h.f.base}/state-pool` }
			fs.writeDir(`{h.f.base}/state-pool`)
			reviewOk("c0035", "design", env)
			t.expect(has(filed(`{folder("c0035")}/c0035.md`), "designed-by: claude-opus-5-5\n")).toBe(true)
			-- the review ran away from Opus: Fable
			t.expect(started()).toEqual({ "claude:claude-fable-5-2" })
		end
	)

	it(
		"AC5: a role whose only try is the author's exact model still runs it, with a Fallback: line",
		function()
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0018", "code")
			local text = filed(`{folder("c0018")}/review-001.md`)
			t.expect(string.sub(text, 1, #"Model: claude-opus-5-5\nEffort: xhigh\nFallback: "))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\nFallback: ")
			t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
		end
	)

	it(
		"AC5: any model may run any review: grok-4.7 at effort high is started when the Claude models and kimi fail, and its review is filed",
		function()
			modes({
				["claude"] = "fail",
				["kimi"] = "fail",
				["grok.zz-review"] = "script",
			})
			local r = reviewOk("c0025", "code")
			t.expect(started()).toEqual({
				"claude:claude-opus-5-5",
				"claude:claude-fable-5-2",
				"kimi:kimi-code/k3.1-pro",
				"grok:grok-4.7",
			})
			t.expect(has(r.stderr .. r.stdout, "not a review model")).toBe(false)
			t.expect(filed(`{folder("c0025")}/review-001.md`))
				.toBe("Model: grok-4.7\nEffort: high\n# Review\n\nVerdict: approve\n")
		end
	)

	it(
		"AC7: a round that carries Fallback: allows no second round, in a marked item or not (no re-review)",
		function()
			modes({ ["claude.zz-review"] = "script" })
			for _, id in { "c0016", "c0029" } do
				local r = review(id, "code")
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stdout .. r.stderr, "there is no second round")).toBe(true)
				t.expect(exists(`{folder(id)}/review-002.md`)).toBe(false)
			end
			-- an unflagged one allows none either, and the earlier round stays as it was
			for _, id in { "c0017", "c0030" } do
				local plain = review(id, "code")
				t.expect(plain.ok).toBe(false)
				t.expect(has(plain.stdout .. plain.stderr, "there is no second round")).toBe(true)
				t.expect(exists(`{folder(id)}/review-002.md`)).toBe(false)
			end
			t.expect(has(filed(`{folder("c0016")}/review-001.md`), "Fallback:")).toBe(true)
		end
	)

	it("AC4: an unmarked item's stamped round is a previous reviewer", function()
		local out = dry("c0029", "code")
		t.expect(has(out, "previous=claude-opus-5-5")).toBe(true)
		t.expect(has(out, "pick: claude claude-fable-5-2")).toBe(true)
		t.expect(has(dry("c0016", "code"), "previous=claude-opus-5-5")).toBe(true)
	end)

	it("AC17: a code review reads the build rows, and no designed-by line", function()
		local out = dry("c0037", "code")
		t.expect(has(out, "pool: author=claude-opus-5-5 (recorded via row) previous=none")).toBe(true)
		t.expect(has(out, "pick: claude claude-fable-5-2")).toBe(true)
		-- no row at all: the tool assumes nothing, every try is tier 1 and the role's order stands
		local unrecorded = dry("c0017", "code")
		t.expect(has(unrecorded, "author=claude-sonnet-5-5")).toBe(true)
		local none = dry("c0033", "code")
		t.expect(has(none, "author=unknown")).toBe(true)
		t.expect(has(none, "tier=3")).toBe(false)
		t.expect(has(none, "pick: claude claude-opus-5-5")).toBe(true)
	end)

	it(
		"AC21: the extra round of the frontier floor runs only a frontier model and is allowed over the newest round when the floor is unmet",
		function()
			modes({ ["claude.zz-review"] = "script" })
			local r = reviewOk("c0040", "code", nil, "--frontier")
			t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
			-- the Sonnet round stays as history, the new round takes the next number and rotates away from Sonnet's line
			t.expect(has(filed(`{folder("c0040")}/review-001.md`), "claude-sonnet-5-5")).toBe(true)
			t.expect(filed(`{folder("c0040")}/review-002.md`))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
			t.expect(has(r.stdout .. r.stderr, "the review is")).toBe(true)
		end
	)

	it(
		"AC21: with the floor met an extra round is refused before any CLI starts, and an ordinary second round still is",
		function()
			modes({ ["claude.zz-review"] = "script" })
			local r = review("c0041", "code", nil, "--frontier")
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "frontier floor is met")).toBe(true)
			t.expect(started()).toEqual({})
			t.expect(exists(`{folder("c0041")}/review-002.md`)).toBe(false)
			local plain = review("c0041", "code")
			t.expect(plain.ok).toBe(false)
			t.expect(has(plain.stdout .. plain.stderr, "there is no second round")).toBe(true)
		end
	)

	it("AC21: a frontier round starts no try that is off the frontier list", function()
		modes({ ["claude"] = "fail", ["kimi.zz-review"] = "script" })
		reviewOk("c0042", "code", nil, "--frontier")
		-- the list is kimi alone: neither Opus nor Fable (both on the role) is started
		t.expect(started()).toEqual({ "kimi:kimi-code/k3.1-pro" })
		t.expect(filed(`{folder("c0042")}/review-002.md`))
			.toBe("Model: kimi-code-k3.1-pro\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
		-- a list that names no model of the role is an error, not a quiet pass
		local none = review("c0044", "code", nil, "--frontier")
		t.expect(none.ok).toBe(false)
		t.expect(has(none.stdout .. none.stderr, "frontier list")).toBe(true)
	end)

	it(
		"AC21: a list entry with @effort needs that effort: grok-4.7 at high leaves the floor unmet, at xhigh meets it",
		function()
			modes({ ["claude.zz-review"] = "script" })
			reviewOk("c0045", "code", nil, "--frontier")
			t.expect(started()).toEqual({ "claude:claude-opus-5-5" })
			local met = review("c0046", "code", nil, "--frontier")
			t.expect(met.ok).toBe(false)
			t.expect(has(met.stdout .. met.stderr, "frontier floor is met")).toBe(true)
		end
	)

	it(
		"AC21: when every frontier model is out of quota the run waits: exit 6, a waiting line, and no review is filed",
		function()
			modes({ ["claude"] = "quota", ["kimi"] = "quota", ["grok"] = "quota", ["agent"] = "quota" })
			local r = review("c0043", "code", nil, "--frontier")
			t.expect(r.code).toBe(6)
			t.expect(has(r.stdout .. r.stderr, "waiting")).toBe(true)
			t.expect(exists(`{folder("c0043")}/review-002.md`)).toBe(false)
			-- a failure that is not quota is a failure (exit 1), not a wait
			modes({ ["claude"] = "fail", ["kimi"] = "fail", ["grok"] = "fail", ["agent"] = "fail" })
			local failed = review("c0043", "code", nil, "--frontier")
			t.expect(failed.code).toBe(1)
		end
	)

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
		"AC11: the stream list is Haiku, Sonnet, grok-4.6, then composer: with the first three failing composer runs",
		function()
			modes({ ["claude"] = "fail", ["grok"] = "fail", ["agent.zz-review"] = "script" })
			reviewOk("c0036", "stream")
			t.expect(started()).toEqual({
				"claude:claude-haiku-5-5",
				"claude:claude-sonnet-5-5",
				"grok:grok-4.6",
				"agent:composer-2.5",
			})
			local text = filed("pickman/.tracker/rafts/R0091/stream-review-c0036-001.md")
			t.expect(string.sub(text, 1, #"Model: composer-2.5\n")).toBe("Model: composer-2.5\n")
			t.expect(has(text, "Fallback:")).toBe(false)
		end
	)

	it(
		"AC11: a stream review run by the layer writer's own line records Fallback:, and allows no second round",
		function()
			modes({
				["claude.zz-review"] = "script",
				["claude-sonnet"] = "fail",
				["grok"] = "fail",
				["agent"] = "fail",
			})
			local r = reviewOk("c0027", "stream")
			t.expect(started()).toEqual({
				"claude:claude-sonnet-5-5",
				"grok:grok-4.6",
				"agent:composer-2.5",
				"claude:claude-haiku-5-5",
			})
			local text = filed("pickman/.tracker/rafts/R0091/stream-review-c0027-001.md")
			t.expect(string.sub(text, 1, #"Model: claude-haiku-5-5\nEffort: medium\nFallback: "))
				.toBe("Model: claude-haiku-5-5\nEffort: medium\nFallback: ")
			t.expect(has(r.stderr .. r.stdout, "fallback review: ")).toBe(true)
			-- no cross-model re-review (user, 2026-11-16): the next stream round is refused
			modes({ ["claude.zz-review"] = "script" })
			local again = review("c0027", "stream")
			t.expect(again.ok).toBe(false)
			t.expect(has(again.stdout .. again.stderr, "there is no second round")).toBe(true)
			t.expect(exists("pickman/.tracker/rafts/R0091/stream-review-c0027-002.md")).toBe(false)
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
		-- and the run keeps the order: Fable failing, then the CLI fallbacks in the order listed, kimi first
		modes({ ["claude.zz-review"] = "script", ["claude-fable"] = "fail", ["kimi.zz-review"] = "script" })
		reviewOk("R0093", "final")
		t.expect(started()).toEqual({ "claude:claude-fable-5-2", "kimi:kimi-code/k3.1-pro" })
		t.expect(filed("pickman/.tracker/rafts/R0093/final-review-001.md"))
			.toBe("Model: kimi-code-k3.1-pro\nEffort: xhigh\n# Review\n\nVerdict: approve\n")
	end)

	it(
		"AC14: z-raft writes on the raft role, which has neither a pool nor a rotation; the raft review has both on its own role",
		function()
			local layers = { M.parse(MODELS, ".models.toml") }
			local authoring = M.resolve(layers, "z-raft")
			local ids = {}
			for _, s in M.tries(authoring) do
				table.insert(ids, `{s.cli}:{s.model}`)
			end
			t.expect(ids).toEqual({ "claude:claude-opus-5-5", "kimi:kimi-code-k3.1-pro" })
			t.expect(authoring.rotate).toBe(false)
			local reviewing = M.resolve(layers, "zz-review", "raft")
			t.expect(reviewing.skill).toBe("raft-review")
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
		"AC14: a raft-mode review rotates on the raft document's designed-by line and on the raft's previous coherence round",
		function()
			-- R0095: the raft document says Fable wrote it (its members' raft-prep rows say Opus), so Opus reviews it first, unflagged
			modes({ ["claude.zz-review"] = "script" })
			local out = dry("R0095", "raft")
			t.expect(has(out, "pool: author=claude-fable-5-2 (recorded via designed-by) previous=none"))
				.toBe(true)
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
