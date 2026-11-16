--!strict
-- c0248 AC10: reviews can be produced headless. `./zn dispatch zz-review <issue> --mode code` files the reviewer's
-- review into the issue's folder as the next review-NNN.md, stamped by the tool with the layer's finish commit and its
-- patch id, and refuses a layer that is not finished; `--mode final [--through <issue>]` files the next
-- final-review-NNN.md and trace-NNN.md, and its one-round rule counts only the reviews not yet on origin/main, so each
-- landing has exactly one. Fake CLIs under .cache (the c0117 dispatch-cli harness); no model, no network.
-- Fixture: .cache/c0248-dispatch-review.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local MODELS = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = ["grok"]

[roles.final-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = ["grok"]
]]

local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local RAFT =
	`---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010, c0020]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Theme\nThe stack theme.\n\n## Order & dependencies\nc0010\nc0020\n`

local h: fakecli.Harness
local wt = ""

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- `./zn` from the raft's worktree, the fakes first on PATH (a review runs in its author's worktree, never the main one)
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

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(args: { string }): string
	return fixture.git(wt, args)
end

-- the fake reviewer: its review in its state folder, and with `trace` a filled trace beside it
local function reviewer(trace: boolean)
	local script = `sleep 1; printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	local more = if trace then `printf '# Trace: R0010\\n' > "$ZN_DISPATCH_DIR/trace.md"\n` else ""
	fs.writeFile(`{h.fakes}/script.sh`, script .. more)
	fakecli.mode(h, "claude.zz-review", "script")
end

local function finishSha(issueId: string): string
	for line in string.gmatch(git({ "log", "--format=%H%x09%s", "-80" }) .. "\n", "([^\n]*)\n") do
		local sha, subject = string.match(line, "^(%x+)\t(.*)$")
		if sha and subject and string.sub(subject, 1, #issueId + 2) == `{issueId}: ` then
			return sha
		end
	end
	error(`no finish commit for {issueId}`, 2)
end

local function patchOf(sha: string): string
	local r =
		fixture.exec(wt, "bash", { "-c", `git show --format= --no-color {sha} | git patch-id --stable` })
	return string.match(r.stdout, "^(%x+)") :: string
end

local function folder(id: string): string
	return `{wt}/{must(znIn(wt, { "find", id }), "find")}`
end

local function build(issueId: string, file: string)
	must(znIn(wt, { "start", "R0010" }), "start")
	fs.writeDir(`{wt}/pickman/src`)
	fs.writeFile(`{wt}/pickman/src/{file}.luau`, `return "{file}"\n`)
	git({ "add", "-A" })
	git({ "commit", "-qm", `{issueId} work` })
end

local function names(dir: string, prefix: string): { string }
	local out = {}
	for _, name in fs.readDir(dir) do
		if string.sub(name, 1, #prefix) == prefix then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

return t.spec(
	"c0248 headless reviews: a stamped code review per issue and a final review per landing",
	function(it)
		it("sets up a readied raft behind a local origin, the fake CLIs and a models file", function()
			h = fakecli.new("c0248-dispatch-review", {
				[".models.toml"] = MODELS,
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/.tracker/rafts/R0010/R0010.md"] = RAFT,
				["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010"),
				["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
				["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020"),
				["pickman/.tracker/issues/c0020/check.sh"] = CHECK,
			})
			must(fakecli.zn(h, { "ready", "R0010" }), "ready")
			wt = must(fakecli.zn(h, { "worktree", "R0010" }), "worktree")
		end)

		it(
			"AC10: a dispatched code review for an issue lands in its folder as the next review-NNN.md, stamped, and a layer that is not finished is refused",
			function()
				build("c0010", "alpha")
				-- the layer is built but not finished: a code review reviews a finished layer
				reviewer(false)
				local early = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
				t.expect(early.ok).toBe(false)
				t.expect(has(early.stdout .. early.stderr, "c0010 is not finished")).toBe(true)
				t.expect(names(folder("c0010"), "review-")).toEqual({})
				t.expect(has(fakecli.log(h), "step=zz-review")).toBe(false) -- no model was started
				-- finished: the review lands in the issue's folder, not the raft's, stamped with what it was given
				must(znIn(wt, { "finish", "c0010" }), "finish")
				local sha = finishSha("c0010")
				local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
				if not r.ok then
					error(r.stdout .. r.stderr)
				end
				t.expect(names(folder("c0010"), "review-")).toEqual({ "review-001.md" })
				t.expect(names(folder("R0010"), "review-")).toEqual({})
				local text = fs.readFile(`{folder("c0010")}/review-001.md`)
				local head = ""
				local n = 0
				for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
					n += 1
					if n <= 12 then
						head ..= line .. "\n"
					end
				end
				t.expect(has(head, `Commit: {sha}\n`)).toBe(true)
				t.expect(has(head, `Patch: {patchOf(sha)}\n`)).toBe(true)
				t.expect(has(text, "Verdict: approve")).toBe(true)
				-- the prompt sends the layer's open list to the issue's document
				t.expect(has(fakecli.log(h), "c0010.md")).toBe(true)
				-- the file is committed and the layer is complete: the stamp is the tool's, so ./zn stack says so
				git({ "add", "-A" })
				git({ "commit", "-qm", "tracker: review c0010" })
				git({ "push", "-q", "origin", "HEAD" })
				t.expect(has(must(znIn(wt, { "stack", "R0010" }), "stack"), "c0010 complete")).toBe(true)
				-- one round per issue folder
				local again = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
				t.expect(again.ok).toBe(false)
				t.expect(has(again.stdout .. again.stderr, "one round")).toBe(true)
				t.expect(names(folder("c0010"), "review-")).toEqual({ "review-001.md" })
			end
		)

		it(
			"AC10: a dispatched final review with --through files the next final-review-NNN.md and trace-NNN.md, and a second landing's final review is not refused",
			function()
				build("c0020", "beta")
				must(znIn(wt, { "finish", "c0020" }), "finish")
				-- the first landing is layer 1 alone: its own final review and trace
				reviewer(true)
				fakecli.mode(h, "claude.zz-review", "script")
				local r =
					znIn(wt, { "dispatch", "zz-review", "R0010", "--mode", "final", "--through", "c0010" })
				if not r.ok then
					error(r.stdout .. r.stderr)
				end
				local raftDir = folder("R0010")
				t.expect(names(raftDir, "final-review-")).toEqual({ "final-review-001.md" })
				t.expect(names(raftDir, "trace-")).toEqual({ "trace-001.md" })
				t.expect(fs.isFile(`{raftDir}/trace.md`)).toBe(false)
				-- the prompt carried --through into ./zn trace
				t.expect(has(fakecli.log(h), "./zn trace R0010 --through c0010")).toBe(true)
				-- the one round of this landing is spent
				local again =
					znIn(wt, { "dispatch", "zz-review", "R0010", "--mode", "final", "--through", "c0010" })
				t.expect(again.ok).toBe(false)
				if not has(again.stdout .. again.stderr, "one round") then
					error(again.stdout .. again.stderr)
				end
				t.expect(names(raftDir, "final-review-")).toEqual({ "final-review-001.md" })
				-- the first landing reaches origin/main (a tracker-only commit, as a bind's tracker files are): its review and
				-- trace are history, and the next landing has its own
				local rel = must(znIn(wt, { "find", "R0010" }), "find")
				trackerfix.elsewhere(h.f, {
					[`{rel}/final-review-001.md`] = fs.readFile(`{raftDir}/final-review-001.md`),
					[`{rel}/trace-001.md`] = fs.readFile(`{raftDir}/trace-001.md`),
				}, "R0010: bind c0010 (its final review and trace)")
				reviewer(true)
				local second = znIn(wt, { "dispatch", "zz-review", "R0010", "--mode", "final" })
				if not second.ok then
					error(second.stdout .. second.stderr)
				end
				t.expect(names(raftDir, "final-review-"))
					.toEqual({ "final-review-001.md", "final-review-002.md" })
				t.expect(names(raftDir, "trace-")).toEqual({ "trace-001.md", "trace-002.md" })
				-- a reviewer that wrote no trace fails the step: a landing's review and trace come together
				fs.removeFile(`{raftDir}/final-review-002.md`)
				fs.removeFile(`{raftDir}/trace-002.md`)
				reviewer(false)
				local bare = znIn(wt, { "dispatch", "zz-review", "R0010", "--mode", "final" })
				t.expect(bare.ok).toBe(false)
				t.expect(has(bare.stdout .. bare.stderr, "wrote no trace")).toBe(true)
				t.expect(names(raftDir, "final-review-")).toEqual({ "final-review-001.md" })
			end
		)
	end
)
