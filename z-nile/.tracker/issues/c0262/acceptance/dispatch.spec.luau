--!strict
-- c0262: the dispatcher runs a ticket's final review in the limited view folder, lands the review in the ticket's
-- folder, and starts a second one only after the layer changed. Real git, fake CLIs. Fixture under
-- .cache/final-dispatch-github.com.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local FAST_PROJECTS = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local DOC = table.concat({
	"---",
	"id: c0010",
	"type: chore",
	"title: alpha module",
	"slug: c0010",
	"raft: R0010",
	"depends_on: []",
	"emergent: false",
	"design: ready",
	"created: 2026-11-13",
	`status: {PREPARED}`,
	"---",
	"",
	"# c0010: alpha module",
	"",
	"## Problem",
	"User: the alpha value is not computed.",
	"",
	"## Solution",
	"Add `pickman/src/alpha.luau` returning the alpha table.",
	"",
	"## Design",
	"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
	"",
	"## Unknowns & experiments",
	"A compromise: design-review-001 F4 was refuted.",
	"",
	"## Acceptance criteria",
	"- AC1: alpha module exists",
	"",
}, "\n")

local MODELS = [[
[dispatch]
stall_seconds = 30

[roles.final-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []
]]

local SCRIPT = [[
v=$(sed -n 's/^View: \([0-9a-f]*\)$/\1/p' README.md | head -1)
printf '### F1\nGap: implementation\nMeasured against: "x"\nmissing\n\nView: %s\nVerdict: off-course\n' "$v" > "$ZN_DISPATCH_DIR/review.md"
]]

return t.spec("c0262 dispatching a ticket's final review", function(it)
	it(
		"AC11: runs in the view folder, lands in the ticket's folder, and runs again only after the layer changed",
		function()
			local check = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
				.. 'check "AC1: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n'
			local h = fakecli.new("final-dispatch-github.com", {
				[".models.toml"] = MODELS,
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				["z-nile/projects.toml"] = FAST_PROJECTS,
				["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["pickman/.tracker/issues/c0010/c0010.md"] = DOC,
				["pickman/.tracker/issues/c0010/check.sh"] = check,
				["pickman/.tracker/rafts/R0010/R0010.md"] = table.concat({
					"---",
					"id: R0010",
					"type: chore",
					"title: one ticket",
					"slug: one-ticket",
					"single: false",
					"issues: [c0010]",
					"design: ready",
					"created: 2026-11-13",
					`status: {PREPARED}`,
					"---",
					"",
					"# R0010: one ticket",
					"",
					"## Order & dependencies",
					"c0010",
					"",
				}, "\n"),
				["pickman/.tracker/rafts/R0010/check.sh"] = check,
			})
			local f = h.f
			for _, rel in
				{
					".luaurc",
					"pickman/.luaurc",
					"pickman/tests/run.luau",
					"pickman/tests/lib",
					"z-nile/tests/run.luau",
					"z-nile/tests/lib",
				}
			do
				local parent = string.match(rel, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{f.main}/{parent}`)
				end
				process.exec("cp", { "-R", `{TOP}/{rel}`, `{f.main}/{rel}` })
			end
			require("@tests/lib/seal").stamp(f.main, "final-dispatch")
			git(f.main, { "add", "-A" })
			git(f.main, { "commit", "-qm", "prep R0010" })
			git(f.main, { "push", "-q", "origin", "HEAD:main" })
			fakecli.clear(h)
			trackerfix.trOk(f, f.main, { "ready", "R0010" })
			local wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
			local env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_AGENT_TOKEN_FILE = h.token,
				GH_TOKEN = "the-users-token",
				ZN_FINAL_VIEW_ROOT = `{f.base}/views`,
			}
			local function zn(args: { string }): fixture.Result
				return trackerfix.tr(f, wt, args, env)
			end
			local r = zn({ "start", "R0010" })
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0010 implementation" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			-- a review the ticket's state cannot read (the usual `Verdict: approve`) is not placed, and the step fails
			fakecli.mode(h, "claude.zz-review", "reviewer")
			local unreadable = zn({ "dispatch", "zz-review", "c0010", "--mode", "final" })
			t.expect(unreadable.ok).toBe(false)
			t.expect(fs.isFile(`{wt}/pickman/.tracker/issues/active/c0010/final-review-001.md`)).toBe(false)
			fakecli.mode(h, "claude.zz-review", "script")
			fs.writeFile(`{h.fakes}/script.sh`, SCRIPT)
			local dir = "pickman/.tracker/issues/active/c0010"

			local first = zn({ "dispatch", "zz-review", "c0010", "--mode", "final" })
			if not first.ok then
				error(first.stdout .. first.stderr)
			end
			local log = fakecli.log(h)
			t.expect(has(log, `cwd={fixture.physical(f.base .. "/views/c0010")}`)).toBe(true)
			-- not under any checkout of the fixture (no CLAUDE.md or AGENTS.md above it)
			t.expect(has(log, `cwd={fixture.physical(wt)}`)).toBe(false)
			t.expect(has(log, "Open to the human")).toBe(false)
			t.expect(has(log, "README.md")).toBe(true)
			t.expect(has(log, "z-nile/skills/zz-review/SKILL.md")).toBe(false)
			t.expect(fs.isFile(`{wt}/{dir}/final-review-001.md`)).toBe(true)
			t.expect(has(fs.readFile(`{wt}/{dir}/final-review-001.md`), "Verdict: off-course")).toBe(true)

			-- committed and unchanged: the view is the one it judged, so a second review is refused
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "final review 1" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			local again = zn({ "dispatch", "zz-review", "c0010", "--mode", "final" })
			t.expect(again.ok).toBe(false)
			t.expect(fs.isFile(`{wt}/{dir}/final-review-002.md`)).toBe(false)

			-- rebuilt: the view changed, the review runs again and lands as 002
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 2 }\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "rebuilt" })
			git(wt, { "push", "-q", "origin", "HEAD:refs/heads/R0010/1/c0010" })
			local second = zn({ "dispatch", "zz-review", "c0010", "--mode", "final" })
			if not second.ok then
				error(second.stdout .. second.stderr)
			end
			t.expect(fs.isFile(`{wt}/{dir}/final-review-002.md`)).toBe(true)
		end
	)

	it("AC11: with no override the view folder is outside every checkout", function()
		local dir = require("@znile/engine/finalread").viewDir("c0010")
		t.expect(string.sub(dir, 1, #TOP) == TOP).toBe(false)
		t.expect(string.find(dir, "/.cache/", 1, true) == nil).toBe(true)
		t.expect(string.match(dir, "/zn%-final/c0010$") ~= nil).toBe(true)
	end)
end)
