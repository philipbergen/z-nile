--!strict
-- c0251 prep experiments E1, E2, E5, E6 and E9, run on the prototype (proto-c0251-rulings, after the user's rulings of 2026-11-16) with
-- `lune run tests/run`. Not an acceptance spec: it is the record of the probes, and is never promoted. Fixture under .cache/c0251-probes (fake CLIs, a worktree of it).
local authorread = require("@znile/engine/authorread")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local reviewmodel = require("@znile/engine/reviewmodel")
local t = require("@tests/lib/t")

local RM: any = reviewmodel

local MODELS = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240

[families]
opus = ["claude-opus-"]
fable = ["claude-fable-"]
kimi = ["kimi-"]
grok = ["grok-"]

[fallback.kimi]
model = "kimi-code-k3.1-pro"
runtime = "kimi-cli"

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[member.fable]
cli = "claude"
model = "claude-fable-5-2"
runtime = "claude-cli"

[roles.raft-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
rotate = true
fallbacks = ["kimi", "grok"]

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
rotate = true
pool = ["fable"]
fallbacks = ["kimi", "grok"]
]]

local HEADER = "when\tsubject\tadded\tremoved\tphase\ttokens\tmodel\twall\tcpu\tai\ttest\tunmeasured\n"
local function marked(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: R0100\ndepends_on: []\nemergent: false\ndesign: draft\nreviews: judged\ncreated: 2026-01-01\nstatus: new-quiet-copper-falcon\n---\n\n# {id}\n`
end
local RAFT =
	"---\nid: R0100\ntype: chore\ntitle: demo\nslug: demo\nissues: [c0040]\nreviews: judged\ndesigned-by: claude-opus-5-5\ncreated: 2026-01-01\nstatus: active-a-b-c\n---\n\n# R0100\n"
local DESIGN =
	"---\nid: c0041\ntype: chore\ntitle: c0041\nslug: c0041\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\nreviews: judged\ndesigned-by: claude-opus-5-5\ncreated: 2026-01-01\nstatus: new-quiet-copper-falcon\n---\n\n# c0041\n"

local KIMI = table.concat({
	"#!/bin/sh",
	'mode=ok; [ -f "$FAKE_DIR/kimi" ] && mode=$(cat "$FAKE_DIR/kimi")',
	'{ echo "kimi step=zz-review mode=$mode cwd=$(pwd -P)"; echo "args=$*"; } >> "$FAKE_DIR/log"',
	'case "$mode" in',
	-- the session id only, as the real kimi prints: the usage is in the session's wire file (E5)
	'wire) echo \'{"session_id":"s-e5"}\'; sh "$FAKE_DIR/script.sh" >> "$FAKE_DIR/log" 2>&1 ;;',
	'ok) sh "$FAKE_DIR/script.sh" >> "$FAKE_DIR/log" 2>&1; echo \'{"type":"usage.record","usage":{"inputOther":10,"output":5}}\' ;;',
	"fail) echo boom >&2; exit 1 ;;",
	"esac",
	"",
}, "\n")

local h: fakecli.Harness
local wt = ""
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
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
	for k, v in extra or {} do
		env[k] = v
	end
	return fixture.exec(wt, "bash", argv, { env = env })
end

return t.spec("c0251 prep experiments", function(it)
	it("sets up the fixture", function()
		h = fakecli.new("c0251-probes", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0040/c0040.md"] = marked("c0040"),
			["pickman/.tracker/issues/c0040/spend.d/m.local-1.tsv"] = HEADER
				.. "2026-11-15 08:00\traft-prep\t0\t0\tprep\t\tclaude-opus-5-5-high\t\t\t\t\t\n",
			["pickman/.tracker/issues/c0041/c0041.md"] = DESIGN,
			["pickman/.tracker/issues/c0041/spend.d/m.local-1.tsv"] = HEADER
				.. "2026-11-15 08:00\tprep\t0\t0\tprep\t\tclaude-opus-5-5-high\t\t\t\t\t\n",
			["pickman/.tracker/rafts/R0100/R0100.md"] = RAFT,
		})
		fs.writeFile(`{h.bin}/kimi`, KIMI)
		process.exec("chmod", { "+x", `{h.bin}/kimi` })
		wt = fixture.physical(`{h.f.base}/wt-probes`) or `{h.f.base}/wt-probes`
		fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "prep-probes", wt, "origin/main" })
		wt = fixture.physical(wt) :: string
		fakecli.mode(h, "claude.zz-review", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			`printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
		)
	end)

	it(
		"E1: the tiers compose with any model running: kimi first, grok at high next, Opus last, flagged only then",
		function()
			-- raft-review role at effort high, an Opus author (the raft document's designed-by line), a marked raft: kimi is
			-- tier 1, grok at high is tier 1 too (any model may run any review), Opus is the writer's own model. kimi runs.
			fakecli.mode(h, "kimi", "ok")
			local r = znIn({ "dispatch", "zz-review", "R0100", "--mode", "raft" })
			t.expect(r.ok).toBe(true)
			local clean = fs.readFile(`{wt}/pickman/.tracker/rafts/R0100/design-review-001.md`)
			t.expect(has(clean, "Model: kimi-code-k3.1-pro\nEffort: high\n")).toBe(true)
			t.expect(has(clean, "Fallback:")).toBe(false)
			fs.removeFile(`{wt}/pickman/.tracker/rafts/R0100/design-review-001.md`)
			-- kimi failing: grok at high runs (no list of review models), and its file is clean
			fakecli.mode(h, "kimi", "fail")
			fakecli.mode(h, "grok.zz-review", "script")
			local second = znIn({ "dispatch", "zz-review", "R0100", "--mode", "raft" })
			t.expect(second.ok).toBe(true)
			local grok = fs.readFile(`{wt}/pickman/.tracker/rafts/R0100/design-review-001.md`)
			t.expect(has(grok, "Model: grok-4.7\nEffort: high\n")).toBe(true)
			t.expect(has(grok, "Fallback:")).toBe(false)
			fs.removeFile(`{wt}/pickman/.tracker/rafts/R0100/design-review-001.md`)
			-- kimi and grok failing: Opus runs last and the file carries Fallback:
			fakecli.mode(h, "grok.zz-review", "fail")
			local third = znIn({ "dispatch", "zz-review", "R0100", "--mode", "raft" })
			t.expect(third.ok).toBe(true)
			local text = fs.readFile(`{wt}/pickman/.tracker/rafts/R0100/design-review-001.md`)
			t.expect(has(text, "Model: claude-opus-5-5\nEffort: high\nFallback: ")).toBe(true)
			fs.removeFile(`{wt}/pickman/.tracker/rafts/R0100/design-review-001.md`)
		end
	)

	it(
		"E2: Model, Effort, Fallback, Commit and Patch all fit the 12-line window ahead of the reviewer's own header",
		function()
			local head =
				"Model: claude-opus-5-5\nEffort: xhigh\nFallback: exact\nCommit: 0123456789ab\nPatch: abcdef012345\n# Review 001: c0041 (code mode)\n"
			local model, effort = RM.read(head)
			t.expect(model).toBe("claude-opus-5-5")
			t.expect(effort).toBe("xhigh")
			t.expect(RM.fallbackOf(head)).toBe("exact")
			t.expect(string.match(head, "\nCommit: (%x+)\n")).toBe("0123456789ab")
			t.expect(string.match(head, "\nPatch: (%x+)\n")).toBe("abcdef012345")
		end
	)

	it(
		"E5: a kimi step's tokens are measured from its session wire when the stream prints no usage",
		function()
			local sessions = `{h.f.base}/kimi-sessions`
			fs.writeDir(`{sessions}/ws/s-e5/agents/main`)
			fs.writeFile(
				`{sessions}/ws/s-e5/agents/main/wire.jsonl`,
				'{"type":"usage.record","usage":{"inputOther":100,"inputCacheCreation":10,"output":20,"inputCacheRead":9000}}\n'
			)
			fakecli.mode(h, "kimi", "wire")
			-- a design review of c0041 with kimi as the only runnable try: claude fails
			fakecli.mode(h, "claude.zz-review", "fail")
			local r = znIn(
				{ "dispatch", "zz-review", "c0041", "--mode", "design" },
				{ PICKMAN_KIMI_SESSIONS = sessions }
			)
			fakecli.mode(h, "claude.zz-review", "script")
			t.expect(r.ok).toBe(true)
			-- 100 + 10 + 20: the cache read is left out
			t.expect(has(r.stdout, "on kimi: ok (done), 130 tokens")).toBe(true)
			fs.removeFile(`{wt}/pickman/.tracker/issues/c0041/design-review-001.md`)
		end
	)

	it(
		"E9: a [member.*] on claude under the design-challenge's xhigh shows in --dry-run, passes the judge and runs headless",
		function()
			fakecli.mode(h, "kimi", nil)
			local dry = znIn({ "dispatch", "zz-review", "c0041", "--mode", "design", "--dry-run" })
			t.expect(dry.ok).toBe(true)
			t.expect(
				has(
					dry.stdout,
					"cli=claude runtime=claude-cli model=claude-fable-5-2-xhigh rank=4 max_tokens=5000 member=fable tier=1"
				)
			).toBe(true)
			t.expect(reviewmodel.ok("claude-fable-5-2", "xhigh")).toBe(true)
			local r = znIn({ "dispatch", "zz-review", "c0041", "--mode", "design" })
			t.expect(r.ok).toBe(true)
			local text = fs.readFile(`{wt}/pickman/.tracker/issues/c0041/design-review-001.md`)
			t.expect(has(text, "Model: claude-fable-5-2\nEffort: xhigh\n")).toBe(true)
			t.expect(has(text, "Fallback:")).toBe(false)
			t.expect(has(fakecli.log(h), "--model claude-fable-5-2")).toBe(true)
			fs.removeFile(`{wt}/pickman/.tracker/issues/c0041/design-review-001.md`)
		end
	)

	it(
		"E6: authorread reads a stream's issue and a raft of 10 members from spend.d alone (no git)",
		function()
			local base = `{h.f.base}/e6`
			local dirs = {}
			for i = 1, 10 do
				local dir = `{base}/m{i}`
				fs.writeDir(`{dir}/spend.d`)
				fs.writeFile(
					`{dir}/spend.d/m.local-1.tsv`,
					HEADER .. "2026-11-15 08:00\traft-prep\t0\t0\tprep\t\tclaude-opus-5-5-high\t\t\t\t\t\n"
				)
				table.insert(dirs, dir)
			end
			-- a folder that is no repository: a git read would fail
			local layers = { models.parse(MODELS, ".models.toml") }
			local a = authorread.read("raft", dirs, layers, nil, nil)
			t.expect(a.provenance).toBe("recorded")
			t.expect(#a.writers).toBe(1)
			t.expect(a.writers[1].model).toBe("claude-opus-5-5")
			local s = authorread.read("stream", { dirs[1] }, layers, nil, nil)
			t.expect(s.via).toBe("none") -- the probe's toml names no implementation role, so there is no first choice to assume
		end
	)

	it("cleans up", function()
		fixture.git(h.f.main, { "worktree", "remove", "--force", wt })
		fs.removeDir(h.f.base)
	end)
end)
