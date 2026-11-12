--!strict
-- c0070 AC1: `tracker.sh done` retargets each layer pull request onto main before it pushes the
-- binding commit, so GitHub can mark the layers merged. Driven for real in a throwaway clone whose
-- origin is a local bare repository under a `github.com` path, with a fake `gh` that records the
-- layer head on origin at the moment `gh pr edit --base main` is called.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- c0120 override: fixtures live under the home's .cache (the jail refuses the checkout top's)
local here = fixture.physical(".") or "."
local base = `{here}/.cache/c0070-done`
local work = `{base}/work`
local bare = `{base}/github.com/fixture.git`
local bin = `{base}/bin`

local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "RC1: fixture" true\nfinish\n'

local function must(r: Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- The fixture's identity rides in the environment, not in its git config: a run of the spec runner nested in
-- the fixture (tracker.sh done runs one) refuses a repository whose own identity is a fixture's (c0640).
local ID: { [string]: string } = {
	GIT_AUTHOR_NAME = "e2e",
	GIT_AUTHOR_EMAIL = "e2e@example.invalid",
	GIT_COMMITTER_NAME = "e2e",
	GIT_COMMITTER_EMAIL = "e2e@example.invalid",
}

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

local function read(path: string): string
	return fs.readFile(`{work}/{path}`)
end

local function write(path: string, text: string)
	fs.writeFile(`{work}/{path}`, text)
end

local function edit(path: string, from: string, to: string)
	local text, n = string.gsub(read(path), from, to)
	assert(n > 0, `pattern {from} not found in {path}`)
	write(path, text)
end

return t.spec("c0070 done marks the PR ready before the final push", function(it)
	it("sets up a clone with a prepared raft, started and reviewed, and a GitHub-looking origin", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		must(process.exec("git", { "clone", "-q", "--no-hardlinks", root, work }), "clone")
		git({ "remote", "remove", "origin" })
		-- overlay the working tree's tooling so uncommitted tracker changes are what gets tested
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
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{work}/{parent}`)
				end
				fs.writeFile(`{work}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		git({ "config", "gc.auto", "0" })
		-- c0114 override: every project root is emptied, and the counter moved to z-nile/next
		-- c0120 override: engine.empty lays the clone out on the final layout (pickman's items in pickman/.tracker, so done
		-- checks the promoted specs from pickman/, their home, with the clone's own pickman/tests/run.luau)
		engine.empty(work)
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		must(tr({ "new", "issue", "f", "alpha", "--project", "pickman" }), "new issue")
		must(
			tr({ "new", "raft", "feature", "demo", "f0010", "--single", "--project", "pickman" }),
			"new raft"
		)
		-- c0120 override: the items are pickman's, in pickman/.tracker; its promoted specs in pickman/tests/acceptance
		for _, doc in { "pickman/.tracker/issues/f0010/f0010.md", "pickman/.tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		edit(
			"pickman/.tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		-- an acceptance spec, so that done has something to promote (and to roll back)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		fs.writeDir(`{work}/pickman/.tracker/issues/f0010/acceptance`)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/issues/f0010/acceptance/alpha.spec.luau",
			"--!strict\nlocal t = "
				.. REQ
				.. '("@tests/lib/t")\n\nreturn t.spec("alpha", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write("pickman/.tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("pickman/.tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write("pickman/.tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
		-- an origin whose URL contains github.com, and a pushed branch with an upstream
		fs.writeDir(bare)
		must(process.exec("git", { "init", "-q", "--bare", bare }), "init bare")
		git({ "remote", "add", "origin", bare })
		git({ "push", "-q", "-u", "origin", "R0010/1/f0010" })
		t.expect(git({ "rev-parse", "HEAD" })).toBe(git({ "rev-parse", "origin/R0010/1/f0010" }))
	end)

	local function installGh()
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			table.concat({
				"#!/bin/sh",
				'echo "$*" >> "$GH_LOG"',
				'case "$1 $2" in',
				'  "pr list") echo 1 ;;',
				'  "pr edit")',
				'    if [ -n "$GH_FAIL_READY" ]; then echo "gh: boom" >&2; exit 1; fi',
				'    git --git-dir="$GH_BARE" rev-parse "refs/heads/$GH_BRANCH" > "$GH_READY_HEAD" ;;',
				'  "pr view") echo "body" ;;',
				"esac",
				"exit 0",
				"",
			}, "\n")
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
	end

	local function done(failReady: boolean): Result
		return tr({ "done", "R0010" }, {
			PATH = `{bin}:{process.env.PATH or ""}`,
			GH_LOG = `{base}/gh.log`,
			GH_BARE = bare,
			GH_BRANCH = "R0010/1/f0010",
			GH_READY_HEAD = `{base}/ready-head`,
			GH_FAIL_READY = if failReady then "1" else "",
		})
	end

	it("does not mark the PR ready when done refuses", function()
		installGh()
		-- c0120 override: the items are pickman's, in pickman/.tracker; its promoted specs in pickman/tests/acceptance
		-- an unresolved review: one open finding and no answer to it
		write(
			"pickman/.tracker/rafts/active/R0010/review-001.md",
			"# Review 001\n\n### F1 [low] an open finding\nEvidence: x\n\nVerdict: changes requested\n"
		)
		must(tr({ "commit", "-m", "unresolved review", "--time", "1" }), "commit")
		git({ "push", "-q" })
		local r = done(false)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "F1", 1, true) ~= nil).toBe(true)
		local log = if fs.isFile(`{base}/gh.log`) then fs.readFile(`{base}/gh.log`) else ""
		t.expect((string.find(log, "pr ready", 1, true))).toBe(nil)
		-- restore the approving review for the cases that follow
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write("pickman/.tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		must(tr({ "commit", "-m", "review approved", "--time", "1" }), "commit")
		-- a promotion that fails is the last refusal before the ready call: done must refuse there too,
		-- leave the tree as it was, and still not have called gh pr ready
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/issues/active/f0010/acceptance/bad.spec.luau",
			"--!strict\nlocal t = "
				.. REQ
				.. '("@tests/lib/t")\n\nreturn t.spec("bad", function(it)\n\tit("fails", function()\n\t\tt.expect(1).toBe(2)\n\tend)\nend)\n'
		)
		must(tr({ "commit", "-m", "failing spec", "--time", "1" }), "commit")
		must(tr({ "finish", "f0010" }), "finish")
		seal.trace(work, "R0010")
		local promoted = done(false)
		t.expect(promoted.ok).toBe(false)
		t.expect(string.find(promoted.stderr, "promoted acceptance specs fail", 1, true) ~= nil).toBe(true)
		local after = if fs.isFile(`{base}/gh.log`) then fs.readFile(`{base}/gh.log`) else ""
		t.expect((string.find(after, "pr ready", 1, true))).toBe(nil)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		t.expect(fs.isFile(`{work}/pickman/.tracker/issues/active/f0010/acceptance/bad.spec.luau`)).toBe(true)
		fs.removeFile(`{work}/pickman/.tracker/issues/active/f0010/acceptance/bad.spec.luau`)
		must(tr({ "commit", "-m", "drop the failing spec", "--time", "1" }), "commit")
	end)

	it("rolls back and stays active when the layer pull request cannot be retargeted", function()
		installGh()
		must(tr({ "finish", "f0010" }), "finish")
		seal.trace(work, "R0010")
		local before = git({ "rev-parse", "HEAD" })
		local r = done(true)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "retarget", 1, true) ~= nil).toBe(true)
		t.expect(git({ "rev-parse", "HEAD" })).toBe(before)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		-- c0120 override: the items are pickman's, in pickman/.tracker; its promoted specs in pickman/tests/acceptance
		t.expect(fs.isDir(`{work}/pickman/.tracker/rafts/active/R0010`)).toBe(true)
		t.expect(fs.isDir(`{work}/pickman/.tracker/issues/active/f0010`)).toBe(true)
		t.expect(fs.isFile(`{work}/pickman/.tracker/issues/active/f0010/acceptance/alpha.spec.luau`))
			.toBe(true)
		t.expect(fs.isDir(`{work}/pickman/tests/acceptance/f0010`)).toBe(false) -- the promotion was undone
		t.expect(git({ "rev-parse", "origin/R0010/1/f0010" })).toBe(before) -- nothing was pushed
	end)

	it("marks the PR ready while origin still has the previous head, then pushes the done commit", function()
		-- this raft has nothing to promote: the ready call must not depend on a promotion happening
		-- c0120 override: the items are pickman's, in pickman/.tracker; its promoted specs in pickman/tests/acceptance
		fs.removeFile(`{work}/pickman/.tracker/issues/active/f0010/acceptance/alpha.spec.luau`)
		must(tr({ "commit", "-m", "no acceptance spec", "--time", "1" }), "commit")
		must(tr({ "finish", "f0010" }), "finish")
		seal.trace(work, "R0010")
		local before = git({ "rev-parse", "HEAD" })
		local r = done(false)
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		local after = git({ "rev-parse", "HEAD" })
		t.expect(after ~= before).toBe(true)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("R0010: bind f0010")
		-- c0120 override: pickman's files live in pickman/ (its home)
		t.expect(fs.isFile(`{work}/pickman/tests/acceptance/f0010/alpha.spec.luau`)).toBe(false)
		-- gh was asked to retarget the layer onto main before the binding commit was pushed
		local log = fs.readFile(`{base}/gh.log`)
		t.expect(string.find(log, "pr edit 1 --base main", 1, true) ~= nil).toBe(true)
		local atEdit = (string.gsub(fs.readFile(`{base}/ready-head`), "%s+$", ""))
		t.expect(atEdit).toBe(before)
		t.expect(must(fixture.exec(bare, "git", { "rev-parse", "refs/heads/main" }), "origin main"))
			.toBe(after)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
