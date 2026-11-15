--!strict
-- c0325 AC6, AC7 and AC9: ./zn spend and ./zn commit record the model that wrote the work (typed --model, else ZN_MODEL for
-- capture, prep and build only), a marked item refuses a capture, prep or build record with no model, and the restated
-- skill and usage lines are pinned. Real git in two fixtures under .cache: `spend` (a bare origin whose path contains
-- github.com, a prep worktree and a gh stub, as c0306's commands.spec) and `commit` (an offline started raft, as c0306's
-- done.spec). Every case has its own item, because a spend or a move is consumed by the command that makes it.
--   spend  c0200 c0201 c0202 c0203 c0204 c0205 c0206 c0207 c0208 (issues), R0050 R0051 (rafts)
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local TOP = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local ROOT = "pickman/.tracker"
local PREPARING = "preparing-quiet-copper-falcon"
local NEW = "new-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

-- a terminal: no agent marker is set, and no ZN_MODEL unless a case sets it
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

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
local function say(r: fixture.Result): string
	return r.stderr .. r.stdout
end

local function issue(id: string, status: string, marked: boolean): string
	return `---\nid: {id}\ntype: chore\ntitle: title {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: ready\n{if marked
		then "reviews: judged\n"
		else ""}rank: 7\ncreated: 2026-11-10\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nThe thing is slow.\n\n## Solution\nMake it fast.\n\n## Acceptance criteria\n- AC1: it is fast\n`
end

local GH = [=[#!/bin/sh
echo "$*" >> "@LOG@"
exit 0
]=]

-- ---------------------------------------------------------------- the spend fixture
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

local function znOk(dir: string, args: { string }, extra: { [string]: string }?): string
	local r = zn(dir, args, extra)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {say(r)}`, 2)
	end
	return r.stdout
end

local function tsv(id: string): string
	local folder = `{prep}/{ROOT}/issues/{id}/spend.d`
	local out = ""
	if fs.isDir(folder) then
		for _, name in fs.readDir(folder) do
			out ..= fs.readFile(`{folder}/{name}`)
		end
	end
	return out
end

-- the model cell of the rows of one phase in an item's spend.d (nil when the row has none)
local function modelOfRow(id: string, phase: string): string?
	local found: string? = nil
	for line in string.gmatch(tsv(id), "[^\n]+") do
		local cells = string.split(line, "\t")
		if cells[5] == phase then
			found = cells[7] or ""
		end
	end
	return found
end

local function spendIn(
	id: string,
	phase: string,
	extra: { string }?,
	e: { [string]: string }?
): fixture.Result
	local args = { "spend", id, "--phase", phase }
	for _, a in extra or {} do
		table.insert(args, a)
	end
	return zn(prep, args, e)
end

-- ---------------------------------------------------------------- the commit fixture
local dir = ""
local raft, member = "", ""
local TR = "pickman/.tracker"

local function run(cmd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	local e: { [string]: string } = table.clone(TERMINAL)
	for k, v in extra or {} do
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

-- a started raft of one issue, offline, with its layer built and nothing finished; `marked` keeps the raft's mark
local function setup(name: string, marked: boolean)
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
		write(`{TR}/{d}/.gitkeep`, "")
	end
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
	local issueDoc, raftDocPath = `{TR}/issues/{member}/{member}.md`, `{TR}/rafts/{raft}/{raft}.md`
	for _, doc in { issueDoc, raftDocPath } do
		write(doc, (string.gsub(read(doc), "design: draft", "design: ready", 1)))
	end
	-- the local `new raft` marks the raft; an unmarked fixture stands for a raft made before c0306 landed
	if not marked then
		write(raftDocPath, (string.gsub(read(raftDocPath), "reviews: judged\n", "", 1)))
	end
	write(
		issueDoc,
		(string.gsub(read(issueDoc), "### Touched modules\n", "### Touched modules\n- `notes/alpha`\n", 1))
	)
	for _, p in { `{TR}/issues/{member}/check.sh`, `{TR}/rafts/{raft}/check.sh` } do
		write(
			p,
			'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\ncheck "RC1: fixture" true\nfinish\n'
		)
	end
	seal.prep(dir)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "prep ready" })
	must(run("./zn", { "start", raft }), "start")
end

local n = 0
-- a build commit with a few lines of its own, so the layer's row is written
local function buildCommit(args: { string }, extra: { [string]: string }?): fixture.Result
	n += 1
	write("notes/alpha/a.txt", string.rep("line\n", n + 1))
	local argv = { "commit", "-m", `{member}: step {n}` }
	for _, a in args do
		table.insert(argv, a)
	end
	return run("./zn", argv, extra)
end

local function memberDir(): string
	return `{TR}/issues/active/{member}`
end
local function rows(): string
	local folder = `{dir}/{memberDir()}/spend.d`
	local out = ""
	if fs.isDir(folder) then
		for _, name in fs.readDir(folder) do
			out ..= fs.readFile(`{folder}/{name}`)
		end
	end
	return out
end
local function lastBuildModel(): string?
	local found: string? = nil
	for line in string.gmatch(rows(), "[^\n]+") do
		local cells = string.split(line, "\t")
		if cells[5] == "build" then
			found = cells[7] or ""
		end
	end
	return found
end
local function lastCommitMessage(): string
	return git({ "log", "-1", "--format=%B" })
end

local function skillText(name: string): string
	return fs.readFile(`{TOP}/z-nile/skills/{name}/SKILL.md`)
end

return t.spec("c0325 spend and commit record the model that wrote the work", function(it)
	it(
		"sets up the spend fixture: a github-shaped origin, marked and unmarked items, a prep worktree and a gh stub",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[`{ROOT}/architecture.md`] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
				["z-nile/next"] = "issue 400 quiet-copper-falcon\nraft 70 quiet-copper-falcon\n",
			}
			local function item(id: string, status: string, marked: boolean)
				seed[`{ROOT}/issues/{id}/{id}.md`] = issue(id, status, marked)
				seed[`{ROOT}/issues/{id}/check.sh`] = CHECK
			end
			item("c0200", PREPARING, true) -- AC7 marked prep, no model
			item("c0201", PREPARING, false) -- unmarked prep, no model
			item("c0202", NEW, true) -- AC7 marked capture, no model
			item("c0203", NEW, false) -- unmarked capture
			item("c0204", PREPARING, true) -- typed model
			item("c0205", PREPARING, true) -- env model
			item("c0206", PREPARING, true) -- typed model beats the env
			item("c0207", PREPARING, false) -- a reviewer's row takes no env default
			item("c0208", PREPARING, true) -- a marked item's reviewer row
			f = trackerfix.new("c0325-authorcmd-github.com", seed)
			local bin = `{f.base}/bin`
			fs.writeDir(bin)
			fs.writeFile(`{bin}/gh`, (string.gsub(GH, "@LOG@", `{f.base}/gh.log`)))
			process.exec("chmod", { "+x", `{bin}/gh` })
			env = { PATH = `{bin}:{process.env.PATH or ""}` }
			prep = `{f.base}/wt-prep`
			fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-c0325", prep, "origin/main" })
		end
	)

	it(
		"AC6: `spend --phase prep|capture` and `commit` take `ZN_MODEL` only for `capture`/`prep`/`build`; a typed `--model` wins; `code-review`/`design-review` rows take none",
		function()
			-- spend: the env fills a prep and a capture row
			znOk(prep, { "spend", "c0205", "--phase", "prep" }, { ZN_MODEL = "claude-sonnet-5-5" })
			t.expect(modelOfRow("c0205", "prep")).toBe("claude-sonnet-5-5")
			znOk(prep, { "spend", "c0203", "--phase", "capture" }, { ZN_MODEL = "kimi-code-k3.1-pro" })
			t.expect(modelOfRow("c0203", "capture")).toBe("kimi-code-k3.1-pro")
			-- a typed --model wins over the env
			znOk(
				prep,
				{ "spend", "c0206", "--phase", "prep", "--model", "claude-opus-5-5" },
				{ ZN_MODEL = "claude-sonnet-5-5" }
			)
			t.expect(modelOfRow("c0206", "prep")).toBe("claude-opus-5-5")
			-- a reviewer's row takes no env default: no model, in an unmarked item and in a marked one
			znOk(prep, { "spend", "c0207", "--phase", "design-review" }, { ZN_MODEL = "claude-sonnet-5-5" })
			t.expect(modelOfRow("c0207", "design-review")).toBe("")
			-- a ZN_MODEL that is no model id is an error
			local bad = spendIn("c0201", "prep", {}, { ZN_MODEL = "not a model" })
			t.expect(bad.ok).toBe(false)
			t.expect(has(say(bad), "ZN_MODEL")).toBe(true)
			t.expect(tsv("c0201")).toBe("")
			-- commit: the env fills a build row; a typed --model wins; code-review and deliver take none
			setup("c0325-authorcmd-commit-a", false)
			must(buildCommit({}, { ZN_MODEL = "claude-sonnet-5-5" }), "commit")
			t.expect(lastBuildModel()).toBe("claude-sonnet-5-5")
			must(buildCommit({ "--model", "claude-opus-5-5" }, { ZN_MODEL = "claude-sonnet-5-5" }), "commit")
			t.expect(lastBuildModel()).toBe("claude-opus-5-5")
			write(`{memberDir()}/notes.md`, "x\n")
			must(
				run(
					"./zn",
					{ "commit", "-m", `{member}: review`, "--phase", "code-review" },
					{ ZN_MODEL = "claude-sonnet-5-5" }
				),
				"commit"
			)
			local last: string? = nil
			for line in string.gmatch(rows(), "[^\n]+") do
				local cells = string.split(line, "\t")
				if cells[5] == "code-review" then
					last = cells[7] or ""
				end
			end
			t.expect(last ~= "claude-sonnet-5-5").toBe(true)
			write(`{memberDir()}/notes.md`, "y\n")
			must(
				run(
					"./zn",
					{ "commit", "-m", `{member}: deliver`, "--phase", "deliver" },
					{ ZN_MODEL = "claude-sonnet-5-5" }
				),
				"commit"
			)
			t.expect(has(rows(), "deliver\t\t")).toBe(true) -- the deliver row's tokens and model cells are empty
		end
	)

	it(
		"AC7: a marked item refuses prep/capture/build with no model; an unmarked item, other phases and a given `--model` are unchanged; the row and trailer hold the model",
		function()
			-- marked: refused, naming the flag, and nothing is written
			for _, case in { { "c0200", "prep" }, { "c0202", "capture" } } do
				local r = spendIn(case[1], case[2], {})
				t.expect(r.ok).toBe(false)
				t.expect(has(say(r), "--model")).toBe(true)
				t.expect(has(say(r), case[2])).toBe(true)
				t.expect(tsv(case[1])).toBe("")
			end
			-- unmarked, with no model: records as today
			znOk(prep, { "spend", "c0201", "--phase", "prep" })
			t.expect(tsv("c0201") ~= "").toBe(true)
			t.expect(modelOfRow("c0201", "prep")).toBe("")
			-- marked, other phase: a design-review row with no model and no note records as today
			znOk(prep, { "spend", "c0208", "--phase", "design-review" })
			t.expect(tsv("c0208") ~= "").toBe(true)
			-- marked, with a typed model: the row holds it
			znOk(prep, { "spend", "c0204", "--phase", "prep", "--model", "claude-opus-5-5[1m]" })
			t.expect(modelOfRow("c0204", "prep")).toBe("claude-opus-5-5[1m]")
			-- commit: a marked raft refuses a build commit with no model, naming the flag, and commits nothing
			setup("c0325-authorcmd-commit-b", true)
			local before = git({ "rev-parse", "HEAD" })
			local refused = buildCommit({})
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "--model")).toBe(true)
			t.expect(git({ "rev-parse", "HEAD" })).toBe(before)
			-- a given model records: the row and the Issue: trailer hold it
			must(buildCommit({ "--model", "claude-sonnet-5-5" }), "commit")
			t.expect(lastBuildModel()).toBe("claude-sonnet-5-5")
			t.expect(has(lastCommitMessage(), `Issue: {member}`)).toBe(true)
			t.expect(string.find(lastCommitMessage(), "Issue: [^\n]* claude%-sonnet%-5%-5") ~= nil).toBe(true)
			-- the dispatcher's env satisfies the marked refusal too
			must(buildCommit({}, { ZN_MODEL = "kimi-code-k3.1-pro" }), "commit")
			t.expect(lastBuildModel()).toBe("kimi-code-k3.1-pro")
			-- another phase in a marked raft is not refused for want of a model (a deliver commit)
			write(`{memberDir()}/notes.md`, "z\n")
			must(run("./zn", { "commit", "-m", `{member}: deliver`, "--phase", "deliver" }), "commit")
			-- an unmarked raft commits a build with no model, as today
			setup("c0325-authorcmd-commit-c", false)
			must(buildCommit({}), "commit")
			t.expect(lastBuildModel()).toBe("")
		end
	)

	it("AC9: the restated skill and usage lines are pinned", function()
		for _, name in { "z-design", "z-raft", "zz-review", "zz-rules", "zz-execute" } do
			local text = skillText(name)
			local a = string.find(text, "**Author record.**", 1, true)
			if not a then
				error(`{name} has no "**Author record.**" paragraph`)
			end
			local b = string.find(text, "\n", a :: number, true)
			local p = string.sub(text, a :: number, (b or #text + 1) - 1)
			for _, needle in
				{
					"`./zn spend <id> --phase capture|prep`",
					"`./zn commit`",
					"`--model <your model id>`",
					"`ZN_MODEL`",
					"reviews: judged",
					"refuses",
					"idea, design, raft or build",
				}
			do
				if not has(p, needle) then
					error(`{name} Author record does not say: {needle}`)
				end
			end
		end
		local rules = skillText("zz-rules")
		t.expect(has(rules, "`--phase build` records the model that wrote the layer")).toBe(true)
		t.expect(has(rules, "`--phase capture|prep` records the model that wrote the work")).toBe(true)
		t.expect(
			has(skillText("z-design"), "add `--model <your model id>`, which records who wrote the design")
		)
			.toBe(true)
		t.expect(has(skillText("z-raft"), "--phase prep --model <your model id>")).toBe(true)
		t.expect(has(skillText("z-ticket"), "--phase capture --model <your model id>")).toBe(true)
		t.expect(has(skillText("zz-execute"), "--model <your model id>` (the model that wrote the layer)"))
			.toBe(true)
		-- the usage lines of commit and spend name the record
		local usage = say(run("./zn", { "help" })) -- the usage text, which exits 1
		t.expect(has(usage, "--phase build records the model that wrote the layer")).toBe(true)
		t.expect(has(usage, "--phase capture|prep records the model that wrote the work")).toBe(true)
	end)
end)
