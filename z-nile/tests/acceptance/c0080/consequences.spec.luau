--!strict
-- c0860: `tracker.sh done` refuses a latest refute file whose "fixed" answer doesn't say what the fix could break
-- ("; consequences: ..."), naming the finding; refuted answers need none. Driven in a throwaway clone (no origin,
-- so no gh), inside this spec run (so done skips the full gate, c0800); each case starts from the same commit,
-- a started raft with a two-finding review.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0860-consequences`
local work = `{base}/work`

local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'
-- the fixture's identity rides in the environment: a nested runner refuses a fixture identity in git config
local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "e2e",
	GIT_AUTHOR_EMAIL = "e2e@example.invalid",
	GIT_COMMITTER_NAME = "e2e",
	GIT_COMMITTER_EMAIL = "e2e@example.invalid",
}

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(args: { string }): string
	return must(fixture.exec(work, "git", args, { env = ID }), "git " .. table.concat(args, " "))
end

local function tr(args: { string }, env: { [string]: string }?): Result
	local merged = table.clone(ID)
	if env then
		for k, v in env do
			merged[k] = v
		end
	end
	return fixture.exec(work, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = merged })
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{work}/{parent}`)
	end
	fs.writeFile(`{work}/{path}`, text)
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(fs.readFile(`{work}/{path}`), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local reviewed = ""

-- every case starts from the reviewed commit, then answers the review with `lines` and runs done
local function answer(lines: { string }): Result
	git({ "reset", "-q", "--hard", reviewed })
	write("tracker/rafts/active/R0010/refute-001.md", table.concat(lines, "\n") .. "\n")
	must(tr({ "commit", "-m", "refute 001", "--time", "1" }), "commit refute")
	return tr({ "done", "R0010" })
end

return t.spec("c0860 fixed answers carry their consequences", function(it)
	it("sets up a clone with a started raft and a review with two findings", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		must(process.exec("git", { "clone", "-q", "--no-hardlinks", root, work }), "clone")
		git({ "remote", "remove", "origin" })
		local listed = process.exec("git", {
			"ls-files",
			"-co",
			"--exclude-standard",
			"zn",
			"scripts",
			"z-nile",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				write(path, fs.readFile(`{root}/{path}`))
			end
		end
		git({ "config", "gc.auto", "0" })
		-- c0114 override: every project root is emptied, and the counter moved to z-nile/next
		engine.empty(work)
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		must(tr({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new issue")
		must(
			tr({ "new", "raft", "feature", "demo", "f0010", "--single", "--project", "pickman" }),
			"new raft"
		)
		for _, doc in { "tracker/issues/f0010/f0010.md", "tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		edit(
			"tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		write("tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		write(
			"tracker/rafts/active/R0010/review-001.md",
			"# Review 001\n\n### F1 [low] a small thing\nEvidence: x\n\n### F2 [high] a big thing\nEvidence: y\n\nVerdict: changes\n"
		)
		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
		reviewed = git({ "rev-parse", "HEAD" })
	end)

	it("a fixed answer without consequences is refused, naming the finding", function()
		local r =
			answer({ "- F1: fixed abc: tidied; consequences: none", "- F2: fixed abc: rewrote the loop" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "F2")).toBe(true)
		t.expect(has(r.stderr, "consequences")).toBe(true)
		t.expect(has(r.stderr, "F1:")).toBe(false) -- F1 is answered properly
		t.expect(fs.isDir(`{work}/tracker/rafts/active/R0010`)).toBe(true)
	end)

	it("a fixed answer with empty consequences is refused", function()
		local r =
			answer({ "- F1: fixed abc: tidied; consequences:   ", "- F2: refuted: the spec shows otherwise" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "F1")).toBe(true)
		t.expect(has(r.stderr, "consequences")).toBe(true)
	end)

	it("fixed answers with consequences, and refuted answers without, get past the review check", function()
		local r = answer({
			"- F1: fixed abc: tidied; consequences: none",
			"- F2: refuted: the design text says so",
		})
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
