--!strict
-- c0070 AC1: `tracker.sh done` marks the PR ready before its final push, so that CI (which skips
-- drafts) runs on the final head. Driven for real in a throwaway clone whose origin is a local bare
-- repository under a `github.com` path (so `done` takes its GitHub branch), with a fake `gh` that
-- records the branch head on origin at the moment `gh pr ready` is called.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0070-done`
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

local function git(args: { string }): string
	return must(process.exec("git", args, { cwd = work }), "git " .. table.concat(args, " "))
end

local function tr(args: { string }, env: { [string]: string }?): Result
	return process.exec("bash", { "scripts/tracker.sh", table.unpack(args) }, { cwd = work, env = env })
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
		local listed = process.exec(
			"git",
			{ "ls-files", "-co", "--exclude-standard", "scripts", "tracker/templates" },
			{ cwd = root }
		)
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				local parent = string.match(path, "^(.*)/[^/]+$")
				if parent then
					fs.writeDir(`{work}/{parent}`)
				end
				fs.writeFile(`{work}/{path}`, fs.readFile(`{root}/{path}`))
			end
		end
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		git({ "config", "gc.auto", "0" })
		for _, kind in { "issues", "rafts" } do
			for _, state in { "", "active/", "done/" } do
				local dir = `{work}/tracker/{kind}/{state}`
				for _, name in fs.readDir(dir) do
					if string.match(name, "^[fdcR]%d%d%d%d$") then
						fs.removeDir(dir .. name)
					end
				end
			end
		end
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker", "--allow-empty" })
		must(tr({ "new", "issue", "f", "alpha" }), "new issue")
		must(tr({ "new", "raft", "feature", "demo", "f0010", "--single" }), "new raft")
		for _, doc in { "tracker/issues/f0010/f0010.md", "tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		edit(
			"tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		-- an acceptance spec, so that done has something to promote (and to roll back)
		fs.writeDir(`{work}/tracker/issues/f0010/acceptance`)
		write(
			"tracker/issues/f0010/acceptance/alpha.spec.luau",
			"--!strict\nlocal t = "
				.. REQ
				.. '("@tests/lib/t")\n\nreturn t.spec("alpha", function(it)\n\tit("holds", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		)
		write("tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		write("tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
		-- an origin whose URL contains github.com, and a pushed branch with an upstream
		fs.writeDir(bare)
		must(process.exec("git", { "init", "-q", "--bare", bare }), "init bare")
		git({ "remote", "add", "origin", bare })
		git({ "push", "-q", "-u", "origin", "R0010-demo" })
		t.expect(git({ "rev-parse", "HEAD" })).toBe(git({ "rev-parse", "origin/R0010-demo" }))
	end)

	local function installGh()
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			table.concat({
				"#!/bin/sh",
				'echo "$*" >> "$GH_LOG"',
				'case "$1 $2" in',
				'  "pr ready")',
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
			GH_BRANCH = "R0010-demo",
			GH_READY_HEAD = `{base}/ready-head`,
			GH_FAIL_READY = if failReady then "1" else "",
		})
	end

	it("does not mark the PR ready when done refuses", function()
		installGh()
		-- an unresolved review: one open finding and no answer to it
		write(
			"tracker/rafts/active/R0010/review-001.md",
			"# Review 001\n\n### F1 [low] an open finding\nEvidence: x\n\nVerdict: changes requested\n"
		)
		must(tr({ "commit", "-m", "unresolved review", "--time", "1" }), "commit")
		local r = done(false)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "F1", 1, true) ~= nil).toBe(true)
		local log = if fs.isFile(`{base}/gh.log`) then fs.readFile(`{base}/gh.log`) else ""
		t.expect((string.find(log, "pr ready", 1, true))).toBe(nil)
		-- restore the approving review for the cases that follow
		write("tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		must(tr({ "commit", "-m", "review approved", "--time", "1" }), "commit")
		-- a promotion that fails is the last refusal before the ready call: done must refuse there too,
		-- leave the tree as it was, and still not have called gh pr ready
		write(
			"tracker/issues/f0010/acceptance/bad.spec.luau",
			"--!strict\nlocal t = "
				.. REQ
				.. '("@tests/lib/t")\n\nreturn t.spec("bad", function(it)\n\tit("fails", function()\n\t\tt.expect(1).toBe(2)\n\tend)\nend)\n'
		)
		must(tr({ "commit", "-m", "failing spec", "--time", "1" }), "commit")
		local promoted = done(false)
		t.expect(promoted.ok).toBe(false)
		t.expect(string.find(promoted.stderr, "promoted acceptance specs fail", 1, true) ~= nil).toBe(true)
		local after = if fs.isFile(`{base}/gh.log`) then fs.readFile(`{base}/gh.log`) else ""
		t.expect((string.find(after, "pr ready", 1, true))).toBe(nil)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		t.expect(fs.isFile(`{work}/tracker/issues/active/f0010/acceptance/bad.spec.luau`)).toBe(true)
		fs.removeFile(`{work}/tracker/issues/active/f0010/acceptance/bad.spec.luau`)
		must(tr({ "commit", "-m", "drop the failing spec", "--time", "1" }), "commit")
	end)

	it("rolls back and stays active when gh cannot mark the PR ready", function()
		installGh()
		local before = git({ "rev-parse", "HEAD" })
		local r = done(true)
		t.expect(r.ok).toBe(false)
		t.expect(string.find(r.stderr, "ready", 1, true) ~= nil).toBe(true)
		t.expect(git({ "rev-parse", "HEAD" })).toBe(before)
		t.expect(git({ "status", "--porcelain" })).toBe("")
		t.expect(fs.isDir(`{work}/tracker/rafts/active/R0010`)).toBe(true)
		t.expect(fs.isDir(`{work}/tracker/issues/active/f0010`)).toBe(true)
		t.expect(fs.isFile(`{work}/tracker/issues/active/f0010/acceptance/alpha.spec.luau`)).toBe(true)
		t.expect(fs.isDir(`{work}/tests/acceptance/f0010`)).toBe(false) -- the promotion was undone
		t.expect(git({ "rev-parse", "origin/R0010-demo" })).toBe(before) -- nothing was pushed
	end)

	it("marks the PR ready while origin still has the previous head, then pushes the done commit", function()
		local before = git({ "rev-parse", "HEAD" })
		local r = done(false)
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		local after = git({ "rev-parse", "HEAD" })
		t.expect(after ~= before).toBe(true)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
		-- gh was asked to mark the PR ready, and to edit its body with the spend summary
		local log = fs.readFile(`{base}/gh.log`)
		t.expect(string.find(log, "pr ready", 1, true) ~= nil).toBe(true)
		t.expect(string.find(log, "pr edit", 1, true) ~= nil).toBe(true)
		-- at that moment origin had the previous head: the done commit was not pushed yet
		local atReady = (string.gsub(fs.readFile(`{base}/ready-head`), "%s+$", ""))
		t.expect(atReady).toBe(before)
		-- and afterwards origin has the final head, which is what CI must test
		t.expect(
			must(
				process.exec("git", { "--git-dir", bare, "rev-parse", "refs/heads/R0010-demo" }),
				"origin head"
			)
		).toBe(after)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
