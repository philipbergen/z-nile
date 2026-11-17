--!strict
-- c0251 AC20: `./zn done` refuses a landing with no code or final review of the landed code by a model on the `[review] frontier`
-- list, naming `no-frontier-review` and the extra round that clears it, in a marked raft and an unmarked one alike; one listed
-- review anywhere in the raft's folder or a member's meets it; a design, stream or idea review does not; and any other model may
-- run any review (a Sonnet round is not refused). Two fixtures under .cache, each a repository with this tree's tooling and no
-- remote (as c0306's done.spec): `a` a marked raft, `b` an unmarked one.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache`

local TERMINAL: { [string]: string } = {
	GIT_AUTHOR_NAME = "floor",
	GIT_AUTHOR_EMAIL = "floor@example.invalid",
	GIT_COMMITTER_NAME = "floor",
	GIT_COMMITTER_EMAIL = "floor@example.invalid",
	CLAUDECODE = "",
	AI_AGENT = "",
	CLAUDE_EFFORT = "",
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

-- the frontier list of the fixture's own .models.toml (the root file's, as it is seeded)
local MODELS =
	'[review]\nfrontier = ["claude-opus-5-5", "claude-fable-5-2", "kimi-code-k3.1-pro", "grok-4.7@xhigh", "gemini-4-argon"]\n'
local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
local TR = "pickman/.tracker"

local dir = ""
local raft, issue = "", ""

local function run(cmd: string, args: { string }, extra: { [string]: string }?): Result
	local env: { [string]: string } = table.clone(TERMINAL)
	local more: { [string]: string } = extra or {}
	for k, v in more do
		env[k] = v
	end
	return fixture.exec(dir, cmd, args, { env = env })
end
local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return trim(r.stdout)
end
local function zn(args: { string }): Result
	return run("./zn", args)
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
local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end
local function say(r: Result): string
	return r.stderr .. r.stdout
end
local function raftDir(): string
	return `{TR}/rafts/active/{raft}`
end
local function issueDir(): string
	return `{TR}/issues/active/{issue}`
end
local function commitAll(message: string)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", message })
end

local function review(model: string?, effort: string?): string
	local head = if model then `Model: {model}\n{if effort then `Effort: {effort}\n` else ""}` else ""
	return `{head}# Review 001: {raft} (code mode)\nInputs: the diff\n\nVerdict: approve\n`
end

-- a started raft of one issue, offline, with its layer built, finished, and a final review on `model`
local function setup(name: string, marked: boolean, model: string, effort: string)
	dir = `{base}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	process.exec("git", { "init", "-q", "-b", "main", dir })
	for _, p in { ".claude", ".luaurc", ".gitignore", "rokit.toml" } do
		process.exec("cp", { "-R", `{root}/{p}`, `{dir}/{p}` })
	end
	fs.writeDir(`{dir}/pickman/.tracker`)
	engine.copy(root, dir)
	for _, d in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
		write(`{TR}/{d}/.gitkeep`, "")
	end
	write(".models.toml", MODELS)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "seed" })
	issue = string.match(
		must(zn({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new"),
		"(f%d%d%d%d)"
	) :: string
	raft = string.match(
		must(zn({ "new", "raft", "feature", "demo", issue, "--project", "pickman" }), "new raft"),
		"(R%d%d%d%d)"
	) :: string
	local issueDoc, raftDocPath = `{TR}/issues/{issue}/{issue}.md`, `{TR}/rafts/{raft}/{raft}.md`
	for _, doc in { issueDoc, raftDocPath } do
		write(doc, (string.gsub(read(doc), "design: draft", "design: ready", 1)))
	end
	if not marked then
		write(raftDocPath, (string.gsub(read(raftDocPath), "reviews: judged\n", "", 1)))
	end
	write(
		issueDoc,
		(string.gsub(read(issueDoc), "### Touched modules\n", "### Touched modules\n- `notes/alpha`\n", 1))
	)
	for _, p in { `{TR}/issues/{issue}/check.sh`, `{TR}/rafts/{raft}/check.sh` } do
		write(p, TRIVIAL_CHECK)
	end
	seal.prep(dir)
	git({ "add", "-A" })
	git({ "commit", "-q", "-m", "prep ready" })
	must(zn({ "start", raft }), "start")
	write("notes/alpha/a.txt", "1\n2\n")
	write(`{raftDir()}/stream-review-{issue}-001.md`, review("claude-fable-5-2", "xhigh"))
	must(zn({ "commit", "-m", "work", "--issue", issue, "--model", "claude-sonnet-5-5" }), "commit")
	must(zn({ "finish", issue }), "finish")
	write(`{raftDir()}/final-review-001.md`, review(model, effort))
	commitAll("final review")
end

return t.spec("c0251 done needs a review of the landed code by a frontier model", function(it)
	it(
		"sets up a marked started raft of one issue, finished, whose final review ran on claude-sonnet-5-5",
		function()
			setup("c0251-floor-a", true, "claude-sonnet-5-5", "high")
		end
	)

	it(
		"AC20: done refuses a landing whose only code review is on a model off the list, naming the code, the file, the model and the extra round",
		function()
			local r = zn({ "done", raft })
			t.expect(r.ok).toBe(false)
			local said = say(r)
			t.expect(has(said, "no-frontier-review")).toBe(true)
			t.expect(has(said, "final-review-001.md on claude-sonnet-5-5 at high")).toBe(true)
			t.expect(has(said, "claude-fable-5-2")).toBe(true)
			t.expect(has(said, `./zn dispatch zz-review {raft} --mode final --frontier`)).toBe(true)
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(false)
		end
	)

	it(
		"AC20: a stream review on Fable, a design review on Fable and a grok review at high do not meet the floor",
		function()
			-- the fixture already holds a stream review on Fable in the raft's folder
			write(`{raftDir()}/design-review-001.md`, review("claude-fable-5-2", "xhigh"))
			write(`{raftDir()}/final-review-002.md`, review("grok-4.7", "high"))
			commitAll("reviews that do not count")
			local r = zn({ "done", raft })
			t.expect(r.ok).toBe(false)
			t.expect(has(say(r), "no-frontier-review")).toBe(true)
			t.expect(has(say(r), "final-review-002.md on grok-4.7 at high")).toBe(true)
			t.expect(has(say(r), "design-review-001.md")).toBe(false)
			t.expect(has(say(r), "stream-review")).toBe(false)
		end
	)

	it(
		"AC20: a later round on a listed model meets it, the Sonnet round is no refusal, and done lands the raft",
		function()
			write(`{raftDir()}/final-review-003.md`, review("grok-4.7", "xhigh"))
			commitAll("final review on grok at xhigh")
			must(zn({ "finish", issue }), "finish")
			seal.trace(dir, raft)
			local r = zn({ "done", raft })
			if not r.ok then
				error(`done refused with a frontier review: {say(r)}`)
			end
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(true)
		end
	)

	it("sets up an unmarked started raft of one issue whose final review ran on claude-haiku-5-5", function()
		setup("c0251-floor-b", false, "claude-haiku-5-5", "medium")
	end)

	it("AC20: the floor holds for an unmarked raft too: every landing", function()
		seal.trace(dir, raft)
		local r = zn({ "done", raft })
		t.expect(r.ok).toBe(false)
		t.expect(has(say(r), "no-frontier-review")).toBe(true)
		t.expect(has(say(r), "claude-haiku-5-5")).toBe(true)
		t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(false)
	end)

	it(
		"AC20: one frontier review in a member's folder meets it for the whole raft, though the final review is off the list",
		function()
			write(`{issueDir()}/review-001.md`, review("kimi-code-k3.1-pro", "high"))
			commitAll("layer review on kimi")
			must(zn({ "finish", issue }), "finish")
			seal.trace(dir, raft)
			local r = zn({ "done", raft })
			if not r.ok then
				error(`done refused with a frontier review in a member's folder: {say(r)}`)
			end
			t.expect(fs.isDir(`{dir}/{TR}/rafts/done/{raft}`)).toBe(true)
		end
	)

	it("cleans up", function()
		fs.removeDir(`{base}/c0251-floor-a`)
		fs.removeDir(`{base}/c0251-floor-b`)
	end)
end)
