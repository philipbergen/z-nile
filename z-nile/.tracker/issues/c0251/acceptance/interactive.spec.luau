--!strict
-- c0251 AC9 and AC10: an interactive lead gets the pick from `./zn dispatch zz-review <id> --mode <m> --dry-run` (the pool line,
-- each try's tier, family and fallback, and the pick, in the order the run would try them; a design's or a raft's writer is the
-- `designed-by` line of its document, a layer's the build rows, and the tool assumes none), and
-- `./zn spend --phase design-review --model` and `./zn commit --phase code-review --model` stamp `Fallback:` themselves: when the
-- typed model is the writer's line, or the pick was not a `claude-` id and another model ran; none when the typed model is the pick.
-- Fixtures under .cache: fake CLIs for the dry-run and the run it must agree with, a github-shaped origin and prep worktree for `spend`,
-- and an offline started raft for `commit`.
local engine = require("@tests/lib/engine")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local pool: any = require("@znile/engine/reviewpool")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local TOP = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local ROOT = "pickman/.tracker"

local MODELS = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240

[families]
opus = ["claude-opus-"]
fable = ["claude-fable-"]
sonnet = ["claude-sonnet-"]
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
fallbacks = ["kimi", "grok"]

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

[roles.final-review]
model = "claude-fable-5-2"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
rotate = true
pool = ["opus"]
fallbacks = ["kimi"]
]]

local NO_POOL = "[roles.design-challenge]\npool = []\n"
local NO_ROTATE = "[roles.design-challenge]\nrotate = false\n"

local HEADER = "when\tsubject\tadded\tremoved\tphase\ttokens\tmodel\twall\tcpu\tai\ttest\tunmeasured\n"
local function rowsFor(phase: string, model: string, subject: string?): string
	return HEADER .. `2026-11-15 08:00\t{subject or phase}\t0\t0\t{phase}\t\t{model}\t\t\t\t\t\n`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

-- a terminal: no agent marker is set, and no ZN_MODEL
local TERMINAL: { [string]: string } = {
	CLAUDECODE = "",
	AI_AGENT = "",
	CLAUDE_EFFORT = "",
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	ZN_MODEL = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
	GIT_AUTHOR_NAME = "author",
	GIT_AUTHOR_EMAIL = "author@example.invalid",
	GIT_COMMITTER_NAME = "author",
	GIT_COMMITTER_EMAIL = "author@example.invalid",
}

local function issue(id: string, status: string, designer: string?): string
	local line = if designer then `designed-by: {designer}\n` else ""
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\nreviews: judged\n{line}rank: 7\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nThe thing is slow.\n\n## Solution\nMake it fast.\n\n## Acceptance criteria\n- AC1: it is fast\n`
end
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local PREPARING = "preparing-quiet-copper-falcon"
local REVIEW = "# Review\n\nVerdict: approve\n"

local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
exit 0
]=]

-- ---------------------------------------------------------------- the dry-run fixture (AC9)
local h: fakecli.Harness
local wt = ""

local KIMI = table.concat({
	"#!/bin/sh",
	'{ echo "kimi step=zz-review mode=fail cwd=$(pwd -P)"; echo "args=$*"; } >> "$FAKE_DIR/log"',
	"echo boom >&2; exit 1",
	"",
}, "\n")

local function znIn(args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(wt, "bash", argv, {
		env = {
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
		},
	})
end

local function dryRun(id: string, mode: string, extra: { string }?): fixture.Result
	local args = { "dispatch", "zz-review", id, "--mode", mode, "--dry-run" }
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(args, a)
	end
	return znIn(args)
end

local function lines(text: string): { string }
	local out = {}
	for l in string.gmatch(text, "[^\n]+") do
		table.insert(out, l)
	end
	return out
end

-- "cli:model" of each try line of a dry run, effort cut off
local function tryList(out: string): { string }
	local list = {}
	for _, l in lines(out) do
		local cli, model = string.match(l, "^try=%d+ cli=(%S+) runtime=%S+ model=(%S+)")
		if cli then
			table.insert(list, `{cli}:{(string.gsub(model :: string, "%-(%a+)$", ""))}`)
		end
	end
	return list
end

-- "cli:model" of each fake started, in order
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
		model = string.gsub(model, "%[.*$", "")
		model = string.gsub(model, "^kimi%-code/", "kimi-code-")
		table.insert(out, `{p.cli}:{model}`)
	end
	return out
end

-- ---------------------------------------------------------------- the spend fixture (AC10)
local f: trackerfix.Fixture
local prep = ""
local env: { [string]: string } = {}

local function zn(dir: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local out: { [string]: string } = table.clone(env)
	for k, v in TERMINAL do
		out[k] = v
	end
	local more: { [string]: string } = extra or {}
	for k, v in more do
		out[k] = v
	end
	return fixture.exec(dir, "./zn", args, { env = out })
end

local function spendArgs(id: string, note: string, model: string, effort: string?): { string }
	local args = { "spend", id, "--phase", "design-review", "--note", note, "--model", model }
	if effort then
		table.insert(args, "--effort")
		table.insert(args, effort)
	end
	return args
end

local function spendWith(
	id: string,
	note: string,
	model: string,
	effort: string?,
	extra: { [string]: string }?
): fixture.Result
	local args = spendArgs(id, note, model, effort)
	local r = zn(prep, args, extra)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return r
end

local function spendReview(id: string, model: string, effort: string?, extra: { [string]: string }?): string
	spendWith(id, "design-review-001", model, effort, extra)
	return fs.readFile(`{prep}/{ROOT}/issues/{id}/design-review-001.md`)
end

local function spendRaftReview(id: string, model: string, effort: string?, note: string?): string
	local name = note or "design-review-001"
	spendWith(id, name, model, effort, nil)
	return fs.readFile(`{prep}/{ROOT}/rafts/{id}/{name}.md`)
end

-- ---------------------------------------------------------------- the commit fixture (AC10)
local dir = ""
local raft, member = "", ""
local function run(cmd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local e: { [string]: string } = table.clone(TERMINAL)
	local more: { [string]: string } = extra or {}
	for k, v in more do
		e[k] = v
	end
	return fixture.exec(dir, cmd, args, { env = e })
end
local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function git(args: { string }): string
	return must(run("git", args), "git " .. table.concat(args, " "))
end
local function write(path: string, text: string)
	local full = `{dir}/{path}`
	fs.writeDir(string.match(full, "^(.*)/[^/]+$") :: string)
	fs.writeFile(full, text)
end
local function read(path: string): string
	return fs.readFile(`{dir}/{path}`)
end

-- a started raft of one issue, offline, whose layer was built by Sonnet
local function setup(name: string)
	local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache`
	dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	process.exec("git", { "init", "-q", "-b", "main", dir }) -- raw: init to a named path
	for _, p in { ".claude", ".luaurc", ".gitignore", "rokit.toml" } do
		process.exec("cp", { "-R", `{TOP}/{p}`, `{dir}/{p}` })
	end
	fs.writeDir(`{dir}/pickman/.tracker`)
	engine.copy(TOP, dir)
	for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
		write(`{ROOT}/{d}/.gitkeep`, "")
	end
	write(".models.toml", MODELS)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "seed" })
	member = string.match(
		must(run("./zn", { "new", "issue", "f", "alpha", "--project", "pickman" }), "new"),
		"(f%d%d%d%d)"
	) :: string
	raft = string.match(
		must(run("./zn", { "new", "raft", "feature", "demo", member, "--project", "pickman" }), "new raft"),
		"(R%d%d%d%d)"
	) :: string
	local issueDoc, raftDocPath = `{ROOT}/issues/{member}/{member}.md`, `{ROOT}/rafts/{raft}/{raft}.md`
	for _, doc in { issueDoc, raftDocPath } do
		write(doc, (string.gsub(read(doc), "design: draft", "design: ready", 1)))
	end
	write(
		issueDoc,
		(string.gsub(read(issueDoc), "### Touched modules\n", "### Touched modules\n- `notes/alpha`\n", 1))
	)
	for _, p in { `{ROOT}/issues/{member}/check.sh`, `{ROOT}/rafts/{raft}/check.sh` } do
		write(
			p,
			'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\ncheck "RC1: fixture" true\nfinish\n'
		)
	end
	seal.prep(dir)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "prep ready" })
	must(run("./zn", { "start", raft }), "start")
	-- the layer, written by Sonnet
	write("notes/alpha/a.txt", "line\nline\n")
	must(run("./zn", { "commit", "-m", `{member}: step 1`, "--model", "claude-sonnet-5-5" }), "build commit")
end

local n = 0
-- a review file in the raft's folder, committed with --phase code-review and the typed model (and the lead's own, when given)
local function commitFile(name: string, model: string, more: { string }?): string
	n += 1
	local path = `{ROOT}/rafts/active/{raft}/{name}-{string.format("%03d", n)}.md`
	write(path, REVIEW)
	local args = {
		"commit",
		"-m",
		`{raft}: {name}-{string.format("%03d", n)}`,
		"--phase",
		"code-review",
		"--model",
		model,
		"--effort",
		"xhigh",
	}
	local added: { string } = more or {}
	for _, a in added do
		table.insert(args, a)
	end
	must(run("./zn", args), "commit")
	return read(path)
end
local function commitReview(model: string, more: { string }?): string
	return commitFile("review", model, more)
end
local function commitFinal(model: string, more: { string }?): string
	return commitFile("final-review", model, more)
end

return t.spec("c0251 the interactive pick and its derived Fallback: stamp", function(it)
	it(
		"sets up the dry-run fixture: marked designs whose designed-by lines say Opus and Fable, and the fake CLIs",
		function()
			local seed: { [string]: string } = { [".models.toml"] = MODELS }
			-- the spend rows say the opposite of each line: the line is the writer
			local writers: { [string]: string } = { c0030 = "claude-opus-5-5", c0031 = "claude-fable-5-2" }
			local rows: { [string]: string } =
				{ c0030 = "claude-fable-5-2-high", c0031 = "claude-opus-5-5-high" }
			for id, model in writers do
				seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, "new-quiet-copper-falcon", model)
				seed[`{ROOT}/issues/{id}/spend.d/m.local-1.tsv`] = rowsFor("prep", rows[id])
			end
			seed[`{ROOT}/issues/c0029/c0029.md`] = issue("c0029", "new-quiet-copper-falcon")
			h = fakecli.new("c0251-interactive-pool", seed)
			fs.writeFile(`{h.bin}/kimi`, KIMI)
			process.exec("chmod", { "+x", `{h.bin}/kimi` })
			wt = fixture.physical(`{h.f.base}/wt-pick`) or `{h.f.base}/wt-pick`
			fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "prep-pick", wt, "origin/main" })
			wt = fixture.physical(wt) :: string
		end
	)

	it("AC9: --dry-run prints the pool line, each try's tier, family and fallback, and the pick", function()
		local r = dryRun("c0030", "design")
		t.expect(r.ok).toBe(true)
		local out = r.stdout
		t.expect(has(out, "pool: author=claude-opus-5-5 (recorded via designed-by) previous=none\n"))
			.toBe(true)
		local tries = {}
		for _, l in lines(out) do
			if string.sub(l, 1, 4) == "try=" then
				table.insert(tries, l)
			end
		end
		t.expect(#tries).toBe(5)
		t.expect(has(tries[1], "cli=claude runtime=claude-cli model=claude-fable-5-2-xhigh")).toBe(true)
		t.expect(has(tries[1], "tier=1 family=fable fallback=no")).toBe(true)
		-- a try from a [member.*] table names it; the role's own model and its CLI fallbacks do not
		t.expect(has(tries[1], " member=fable ")).toBe(true)
		t.expect(has(tries[4], "member=")).toBe(false)
		t.expect(has(tries[2], "member=")).toBe(false)
		t.expect(has(tries[2], "tier=1 family=kimi fallback=no")).toBe(true)
		t.expect(has(tries[3], "tier=1 family=grok fallback=no")).toBe(true)
		t.expect(has(tries[4], "model=claude-opus-5-5-xhigh")).toBe(true)
		t.expect(has(tries[4], "tier=3 family=opus fallback=yes")).toBe(true)
		t.expect(has(tries[5], "cli=agent")).toBe(true)
		t.expect(has(tries[5], "tier=3 family=opus fallback=yes")).toBe(true)
		t.expect(has(out, "pick: claude claude-fable-5-2\n")).toBe(true)
		-- the pick is the last line, after every try
		local all = lines(out)
		t.expect(all[#all]).toBe("pick: claude claude-fable-5-2")
		-- and it starts nothing
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"AC9: the lead's own model is no input: a typed --author changes nothing, and the line decides",
		function()
			local plain = dryRun("c0030", "design")
			local typed = dryRun("c0030", "design", { "--author", "claude-fable-5-2" })
			t.expect(typed.ok).toBe(true)
			t.expect(typed.stdout).toBe(plain.stdout)
			t.expect(has(typed.stdout, "pool: author=claude-opus-5-5 (recorded via designed-by)")).toBe(true)
			-- c0031's line says Fable: Opus is tier 1 and goes first, Fable is the recorded fallback
			local fable = dryRun("c0031", "design")
			t.expect(has(fable.stdout, "pool: author=claude-fable-5-2 (recorded via designed-by)")).toBe(true)
			t.expect(has(fable.stdout, "pick: claude claude-opus-5-5\n")).toBe(true)
			t.expect(tryList(fable.stdout)[5]).toBe("claude:claude-fable-5-2")
			-- a document with no line is refused, not assumed
			local none = dryRun("c0029", "design")
			t.expect(none.ok).toBe(false)
			t.expect(has(say(none), "designed-by")).toBe(true)
			t.expect(has(say(none), "c0029.md")).toBe(true)
		end
	)

	it("AC9: the printed order equals the order the run tries", function()
		local dry = dryRun("c0030", "design")
		local printed = tryList(dry.stdout)
		fakecli.clear(h)
		for _, cli in { "claude", "grok", "agent" } do
			fakecli.mode(h, cli, "fail")
		end
		local ran = znIn({ "dispatch", "zz-review", "c0030", "--mode", "design" })
		t.expect(ran.ok).toBe(false) -- every try was refused, so the step fails
		t.expect(started()).toEqual(printed)
		t.expect(#printed).toBe(5)
	end)

	it("AC9: the run uses the designed-by line too: c0031's run starts Opus first", function()
		fakecli.clear(h)
		for _, cli in { "claude", "grok", "agent" } do
			fakecli.mode(h, cli, "fail")
		end
		znIn({ "dispatch", "zz-review", "c0031", "--mode", "design" })
		t.expect(started()[1]).toBe("claude:claude-opus-5-5")
	end)

	it(
		"sets up the spend fixture: a github-shaped origin, designs whose rows differ from the role's first choice, a raft, and a gh stub",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["z-nile/next"] = "issue 400 quiet-copper-falcon\nraft 70 quiet-copper-falcon\n",
				[".models.toml"] = MODELS,
			}
			-- a design under review: its review file, its designed-by line (none when `designer` is nil), the spend row of a prep
			-- that disagrees with it (none when `row` is nil) and a closer file
			local function design(id: string, designer: string?, row: string?, closer: string?)
				seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, PREPARING, designer)
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
				seed[`{ROOT}/issues/{id}/design-review-001.md`] = REVIEW
				if row then
					seed[`{ROOT}/issues/{id}/spend.d/m.local-1.tsv`] = rowsFor("prep", row)
				end
				if closer then
					seed[`{ROOT}/issues/{id}/.models.toml`] = closer
				end
			end
			-- the design role's first choice is Opus: the lines, not the role and not the rows, say who wrote each
			design("c0300", "claude-fable-5-2") -- Fable wrote it
			design("c0301", "claude-fable-5-2")
			design("c0302", "claude-fable-5-2", "claude-opus-5-5-high") -- the line says Fable, the row says Opus
			design("c0303", "[claude-opus-5-5, claude-fable-5-2]") -- two models wrote it
			design("c0304", nil, "claude-opus-5-5-high") -- no line: refused, whatever the row says
			design("c0306", "claude-opus-5-5") -- ZN_MODEL says Fable, the line says Opus
			design("c0307", "claude-opus-5-5", nil, NO_ROTATE)
			design("c0308", "claude-opus-5-5", nil, NO_POOL) -- the pick is kimi
			design("c0309", "claude-opus-5-5", nil, NO_POOL)
			design("c0310", "claude-opus-5-5", nil, NO_POOL)
			-- a raft written by Fable (its document's line; its members' raft-prep rows say Opus), with a coherence review file in its folder
			seed[`{ROOT}/rafts/R0300/R0300.md`] =
				"---\nid: R0300\ntype: chore\ntitle: R0300\nslug: r0300\nsingle: false\nissues: [c0312, c0313]\ndesign: ready\nreviews: judged\ndesigned-by: claude-fable-5-2\nrank: 3\ncreated: 2026-11-10\nstatus: preparing-quiet-copper-falcon\n---\n\n# R0300\n\n## Theme\nT.\n\n## Order & dependencies\nc0312\nc0313\n"
			seed[`{ROOT}/rafts/R0300/check.sh`] = CHECK
			seed[`{ROOT}/rafts/R0300/design-review-001.md`] = REVIEW
			for _, id in { "c0312", "c0313" } do
				seed[`{ROOT}/issues/{id}/{id}.md`] = (
					string.gsub(issue(id, "prepared-quiet-copper-falcon"), "raft: \n", "raft: R0300\n", 1)
				)
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
			end
			-- a second raft, written by Fable too, whose own .models.toml makes kimi the raft-review role's only model
			seed[`{ROOT}/rafts/R0301/R0301.md`] = (
				string.gsub(
					string.gsub(seed[`{ROOT}/rafts/R0300/R0300.md`], "R0300", "R0301"),
					"c0312, c0313",
					"c0314"
				)
			)
			seed[`{ROOT}/issues/c0314/c0314.md`] = (
				string.gsub(issue("c0314", "prepared-quiet-copper-falcon"), "raft: \n", "raft: R0301\n", 1)
			)
			seed[`{ROOT}/issues/c0314/check.sh`] = CHECK
			seed[`{ROOT}/rafts/R0301/check.sh`] = CHECK
			seed[`{ROOT}/rafts/R0301/design-review-001.md`] = REVIEW
			seed[`{ROOT}/rafts/R0301/.models.toml`] =
				'[roles.raft-review]\nmodel = "kimi-code-k3.1-pro"\ncli = "kimi"\nruntime = "kimi-cli"\npool = []\nfallbacks = []\n'
			seed[`{ROOT}/issues/c0312/spend.d/m.local-1.tsv`] =
				rowsFor("prep", "claude-opus-5-5-high", "raft-prep")
			f = trackerfix.new("c0251-interactive-github.com", seed)
			local bin = `{f.base}/bin`
			fs.writeDir(bin)
			fs.writeFile(`{bin}/gh`, (string.gsub(GH, "@LOG@", `{f.base}/gh.log`)))
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			prep = `{f.base}/wt-prep`
			fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-c0251", prep, "origin/main" })
		end
	)

	it(
		"AC10: a spend stamps Fallback: when the typed model is the writer's line, the writer read from the designed-by line",
		function()
			-- the line says Fable wrote c0300, though the design role's first choice is Opus
			local text = spendReview("c0300", "claude-fable-5-2", "xhigh")
			t.expect(string.sub(text, 1, #"Model: claude-fable-5-2\nEffort: xhigh\nFallback: "))
				.toBe("Model: claude-fable-5-2\nEffort: xhigh\nFallback: ")
			t.expect(has(string.match(text, "\nFallback: ([^\n]*)\n") :: string, "claude-fable-5-2"))
				.toBe(true)
			t.expect(has(string.match(text, "\nFallback: ([^\n]*)\n") :: string, "assumed")).toBe(false)
			-- and an Opus reviewer of that Fable design is not flagged
			t.expect(spendReview("c0301", "claude-opus-5-5", "xhigh"))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. REVIEW)
		end
	)

	it("AC10: the designed-by line beats the spend rows, and a list names every writer", function()
		-- c0302's row says Opus wrote it, its line says Fable: Opus reviewing is not the writer's line, Fable is
		t.expect(spendReview("c0302", "claude-opus-5-5", "xhigh"))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. REVIEW)
		-- c0303's line lists Opus and Fable: a Fable review is the writers' line
		local both = spendReview("c0303", "claude-fable-5-2", "xhigh")
		t.expect(has(both, "\nFallback: ")).toBe(true)
	end)

	it(
		"AC10: a spend of a design review on a document with no designed-by line is refused, stamps nothing and names the document",
		function()
			local r = zn(prep, spendArgs("c0304", "design-review-001", "claude-opus-5-5", "xhigh"))
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "designed-by")).toBe(true)
			t.expect(has(say(r), "c0304.md")).toBe(true)
			t.expect(fs.readFile(`{prep}/{ROOT}/issues/c0304/design-review-001.md`)).toBe(REVIEW)
		end
	)

	it("AC10: ZN_MODEL is not the writer of a design: the line is", function()
		-- c0306's line says Opus; a Fable lead's env is no writer, so a Fable review is not flagged
		local text = spendReview("c0306", "claude-fable-5-2", "xhigh", { ZN_MODEL = "claude-fable-5-2" })
		t.expect(text).toBe("Model: claude-fable-5-2\nEffort: xhigh\n" .. REVIEW)
	end)

	it(
		"AC10: it stamps Fallback: when the pick was not a claude- id and a different model was typed",
		function()
			-- without the Fable member the Opus-written design's pick is kimi
			local viaFable = spendReview("c0308", "claude-fable-5-2", "xhigh")
			t.expect(has(viaFable, "\nFallback: ")).toBe(true)
			t.expect(has(string.match(viaFable, "\nFallback: ([^\n]*)\n") :: string, "kimi-code-k3.1-pro"))
				.toBe(true)
			t.expect(spendReview("c0309", "kimi-code-k3.1-pro", "high"))
				.toBe("Model: kimi-code-k3.1-pro\nEffort: high\n" .. REVIEW)
			-- a typed model that is the writer's line is a fallback even when the pick was not Claude
			t.expect(has(spendReview("c0310", "claude-opus-5-5", "xhigh"), "\nFallback: ")).toBe(true)
		end
	)

	it("AC10: a typed id whose role does not rotate stamps no Fallback:", function()
		t.expect(spendReview("c0307", "claude-opus-5-5", "xhigh"))
			.toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. REVIEW)
	end)

	it(
		"AC10: a spend on a raft's folder is a raft-mode review, read against the raft document's designed-by line",
		function()
			-- Fable wrote the raft (its document's line; the members' raft-prep rows say Opus); Opus is not its writer
			t.expect(spendRaftReview("R0300", "claude-opus-5-5", "xhigh"))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\n" .. REVIEW)
		end
	)

	it("AC10: the same raft reviewed by the writer's own line is flagged", function()
		-- a second review file: the first was stamped
		fs.writeFile(`{prep}/{ROOT}/rafts/R0300/design-review-002.md`, REVIEW)
		local text = spendRaftReview("R0300", "claude-fable-5-2", "xhigh", "design-review-002")
		t.expect(has(text, "\nFallback: ")).toBe(true)
	end)

	it(
		"AC10: a raft folder is read in raft mode, whose role is raft-review: its own .models.toml decides the pick",
		function()
			-- R0301's raft-review role has kimi alone, so the pick is not a claude- id: an Opus review of it is the fallback
			local text = spendRaftReview("R0301", "claude-opus-5-5", "xhigh")
			t.expect(has(text, "\nFallback: ")).toBe(true)
			t.expect(has(string.match(text, "\nFallback: ([^\n]*)\n") :: string, "kimi-code-k3.1-pro"))
				.toBe(true)
		end
	)

	it(
		"AC10: commit --phase code-review --model stamps Fallback: when the typed model is the layer writer's line",
		function()
			setup("c0251-interactive-commit")
			-- Sonnet wrote the layer; Opus is the pick and needs no flag
			local opus = commitReview("claude-opus-5-5")
			t.expect(string.sub(opus, 1, #"Model: claude-opus-5-5\nEffort: xhigh\n"))
				.toBe("Model: claude-opus-5-5\nEffort: xhigh\n")
			t.expect(has(opus, "Fallback:")).toBe(false)
			-- a Sonnet subagent reviewing Sonnet's code is the writer's line
			local sonnet = commitReview("claude-sonnet-5-5")
			t.expect(has(sonnet, "\nFallback: ")).toBe(true)
			t.expect(has(string.match(sonnet, "\nFallback: ([^\n]*)\n") :: string, "sonnet")).toBe(true)
			-- Fable is not the writer's line and the pick was a Claude id
			t.expect(has(commitReview("claude-fable-5-2"), "Fallback:")).toBe(false)
		end
	)

	it(
		"AC10: commit takes no --author: the layer's writer is the build row, whatever the lead types",
		function()
			-- the build row says Sonnet; an Opus review is the pick, and a typed --author claude-opus-5-5 makes it no fallback or flag
			local typed = commitReview("claude-opus-5-5", { "--author", "claude-opus-5-5" })
			t.expect(has(typed, "Fallback:")).toBe(false)
			local sonnet = commitReview("claude-sonnet-5-5", { "--author", "claude-fable-5-2" })
			t.expect(has(sonnet, "\nFallback: ")).toBe(true)
		end
	)

	it("AC10: a final review file is read in final mode, whose role is final-review", function()
		-- the raft's own .models.toml makes kimi the final-review role's only model; the code-review role is untouched (Opus)
		write(
			`{ROOT}/rafts/active/{raft}/.models.toml`,
			'[roles.final-review]\nmodel = "kimi-code-k3.1-pro"\ncli = "kimi"\nruntime = "kimi-cli"\npool = []\nfallbacks = []\n'
		)
		local final = commitFinal("claude-opus-5-5")
		t.expect(has(final, "\nFallback: ")).toBe(true)
		t.expect(has(string.match(final, "\nFallback: ([^\n]*)\n") :: string, "kimi-code-k3.1-pro"))
			.toBe(true)
		-- the same Opus as a code review of that layer is not flagged: that role's pick is Opus
		t.expect(has(commitReview("claude-opus-5-5"), "Fallback:")).toBe(false)
		fs.removeFile(`{dir}/{ROOT}/rafts/active/{raft}/.models.toml`)
	end)

	it("AC10: a non-Claude pick that was not the model that ran is flagged on a commit too", function()
		-- the raft's own .models.toml makes kimi the code-review role's only model, so the pick is not a claude- id
		write(
			`{ROOT}/rafts/active/{raft}/.models.toml`,
			'[roles.code-review]\nmodel = "kimi-code-k3.1-pro"\ncli = "kimi"\nruntime = "kimi-cli"\npool = []\nfallbacks = []\n'
		)
		local flagged = commitReview("claude-opus-5-5")
		t.expect(has(flagged, "\nFallback: ")).toBe(true)
		t.expect(has(string.match(flagged, "\nFallback: ([^\n]*)\n") :: string, "kimi-code-k3.1-pro"))
			.toBe(true)
		local onPick = commitReview("kimi-code-k3.1-pro")
		t.expect(has(onPick, "Fallback:")).toBe(false)
	end)

	it(
		"AC10: pool.interactiveReason is the pure rule: the writer's line, or a non-Claude pick that was not the model that ran",
		function()
			local families = { opus = { "claude-opus-" }, fable = { "claude-fable-" }, kimi = { "kimi-" } }
			local function spec(cli: string, model: string)
				return {
					cli = cli,
					model = model,
					effort = "high",
					rank = 4,
					runtime = `{cli}-rt`,
					maxTokens = 1,
				}
			end
			local tries = {
				spec("claude", "claude-fable-5-2"),
				spec("kimi", "kimi-code-k3.1-pro"),
				spec("claude", "claude-opus-5-5"),
			}
			local function plan(authors: { string }): any
				return {
					picks = pool.order(tries, families, authors, {}),
					authors = authors,
					authorFamilies = { "opus" },
					priors = {},
					priorFamilies = {},
					provenance = "recorded",
					via = "designed-by",
					families = families,
					rotate = true,
				}
			end
			local opusPlan = plan({ "claude-opus-5-5" })
			t.expect(pool.interactiveReason(opusPlan, "claude-fable-5-2")).toBe(nil)
			t.expect(pool.interactiveReason(opusPlan, "kimi-code-k3.1-pro")).toBe(nil)
			t.expect(pool.interactiveReason(opusPlan, "claude-sonnet-5-5")).toBe(nil)
			t.expect(has(pool.interactiveReason(opusPlan, "claude-opus-5-5") :: string, "claude-opus-5-5"))
				.toBe(true)
			t.expect(
				has(pool.interactiveReason(opusPlan, "claude-opus-5-5[1m]") :: string, "claude-opus-5-5")
			)
				.toBe(true)
			-- the first pick is kimi: any other model that ran is flagged, the pick itself is not
			local kimiFirst = {
				picks = pool.order(
					{ spec("kimi", "kimi-code-k3.1-pro"), spec("claude", "claude-opus-5-5") },
					families,
					{ "claude-opus-5-5" },
					{}
				),
				authors = { "claude-opus-5-5" },
				authorFamilies = { "opus" },
				priors = {},
				priorFamilies = {},
				provenance = "recorded",
				via = "designed-by",
				families = families,
				rotate = true,
			}
			t.expect(pool.interactiveReason(kimiFirst, "kimi-code-k3.1-pro")).toBe(nil)
			local flagged = pool.interactiveReason(kimiFirst, "claude-fable-5-2") :: string
			t.expect(has(flagged, "kimi-code-k3.1-pro")).toBe(true)
			t.expect(has(flagged, "claude-fable-5-2")).toBe(true)
			-- a plan made from the checkout's own .models.toml says so
			local walked: any = table.clone(kimiFirst)
			walked.walk = "checkout"
			t.expect(has(pool.interactiveReason(walked, "claude-fable-5-2") :: string, "checkout")).toBe(true)
			t.expect(has(pool.interactiveReason(kimiFirst, "claude-fable-5-2") :: string, "checkout"))
				.toBe(false)
			-- the tool assumes no author, so no reason says so
			t.expect(has(pool.interactiveReason(kimiFirst, "claude-opus-5-5") :: string, "assumed"))
				.toBe(false)
			t.expect(#(pool.interactiveReason(kimiFirst, "claude-opus-5-5") :: string) <= 120).toBe(true)
		end
	)

	it("cleans up", function()
		fixture.git(h.f.main, { "worktree", "remove", "--force", wt })
		fs.removeDir(h.f.base)
		fixture.git(f.main, { "worktree", "remove", "--force", prep })
		fs.removeDir(f.base)
		fs.removeDir(dir)
	end)
end)
