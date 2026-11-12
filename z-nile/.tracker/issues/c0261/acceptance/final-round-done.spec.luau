--!strict
-- c0261 ("Commands refuse"): `./zn done` refuses a raft whose last final review (final-review-NNN.md) was recorded on a
-- model that is not of a final-review kind, naming the round and how to record it; a row on an Opus lets it past that
-- check. Driven for real in a throwaway clone like tests/acceptance/c0008/done-order.spec.luau (a prepared raft R0010,
-- started, one approving final review, a github.com-looking bare origin whose main holds a root .models.toml).
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
local base = `{here}/.cache/c0261-done`
local work = `{base}/work`
local bare = `{base}/github.com/fixture.git`

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

return t.spec("c0261 done refuses a final review not on a final-review model", function(it)
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
		seal.prep(work)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		-- c0120 override: pickman's items live in pickman/.tracker (the fixtures' final layout)
		write(
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Final Review 001\n\nVerdict: approve\n"
		)
		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
		-- an origin whose URL contains github.com, and a pushed branch with an upstream
		fs.writeDir(bare)
		must(process.exec("git", { "init", "-q", "--bare", bare }), "init bare")
		git({ "remote", "add", "origin", bare })
		git({ "push", "-q", "-u", "origin", "R0010/1/f0010" })
		-- the base holds a root .models.toml: the repository has final-review models to hold the round to
		write(".models.toml", 'order = ["claude"]\n[zz-review.claude]\nmodel = "claude-opus-5-5"\nrank = 4\n')
		git({ "add", ".models.toml" })
		git({ "commit", "-qm", "models" })
		git({ "push", "-q", "origin", "HEAD:refs/heads/main", "HEAD:refs/heads/R0010/1/f0010" })
	end)

	it("refuses a final review recorded on a Sonnet, and does not refuse one recorded on an Opus", function()
		local function record(model: string)
			must(
				tr({ "commit", "-m", "R0010: final-review-001", "--phase", "code-review", "--model", model }),
				"commit"
			)
			git({ "push", "-q" })
		end
		record("claude-sonnet-5-5-high")
		local refused = tr({ "done", "R0010" })
		t.expect(refused.ok).toBe(false)
		t.expect(string.find(refused.stderr, "final-review-001", 1, true) ~= nil).toBe(true)
		t.expect(string.find(refused.stderr, "model claude-sonnet-5-5-high", 1, true) ~= nil).toBe(true)
		t.expect(string.find(refused.stderr, "--mode final", 1, true) ~= nil).toBe(true)
		-- the same round re-run on an Opus: done goes past this check (a later step may still stop it)
		record("claude-opus-6-1")
		local past = tr({ "done", "R0010" })
		t.expect(string.find(past.stderr, "final-review model", 1, true)).toBe(nil)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
