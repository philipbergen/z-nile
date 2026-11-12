--!strict
-- The branches a spec run used to skip: finish's real spec run, the four watch-file cases, done's
-- checkout check, a missing verdict, a failed push that puts pull-request bases back, and a raft
-- worktree that never grows an R####-<slug> branch. Fixtures: .cache/stack-fix-github.com and
-- .cache/stack-fix-run-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire"
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function issue(id: string, title: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\none\n`
end

local function raftDoc(id: string, slug: string, issues: string, order: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{order}\n`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

return t.spec("stack corrections", function(it)
	local f: trackerfix.Fixture
	local wt = ""
	local env: { [string]: string } = {}

	local function zn(dir: string, args: { string }, extra: { [string]: string }?): string
		local child = extra or env
		local r = trackerfix.tr(f, dir, args, child)
		if not r.ok then
			error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
		end
		return r.stdout
	end

	it("sets up a two-layer raft whose watches already name one source", function()
		local seed: { [string]: string } = {
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha", "R0010"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "beta", "R0010"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "gamma", "R0020"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "delta", "R0030"),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc(
				"R0010",
				"alpha",
				"c0010, c0020",
				"c0010\nc0020"
			),
			["pickman/.tracker/rafts/R0020/R0020.md"] = raftDoc("R0020", "gamma", "c0030", "c0030"),
			["pickman/.tracker/rafts/R0030/R0030.md"] = raftDoc("R0030", "delta", "c0040", "c0040"),
			["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = "",
			["pickman/.tracker/issues/c0020/acceptance/.gitkeep"] = "",
			["pickman/.tracker/issues/c0030/acceptance/foo.spec.luau"] = "--!strict\nreturn nil\n",
			["pickman/.tracker/issues/c0040/acceptance/.gitkeep"] = "",
			["pickman/src/earlier.luau"] = "return {}\n",
			["pickman/src/needed.luau"] = "return {}\n",
			["pickman/tests/unit/union.spec.luau"] = "--!strict\nreturn nil\n",
			["pickman/tests/unit/union.watch.txt"] = "pickman/src/earlier.luau\n",
			["pickman/tests/unit/suite.spec.luau"] = "--!strict\nreturn nil\n",
			["pickman/tests/unit/req.spec.luau"] = `--!strict\n{R}("../../src/needed")\nreturn nil\n`,
		}
		for _, id in { "c0010", "c0020", "c0030", "c0040" } do
			seed[`pickman/.tracker/issues/{id}/check.sh`] = CHECK
		end
		for _, id in { "R0010", "R0020", "R0030" } do
			seed[`pickman/.tracker/rafts/{id}/check.sh`] = CHECK
		end
		seed[".gitignore"] = fs.readFile(`{TOP}/.gitignore`)
		f = trackerfix.new("stack-fix-github.com", seed)
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			'#!/bin/sh\necho "$*" >> "$GH_LOG"\ncase "$1 $2" in\n'
				.. '  "pr list") echo 1; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
				.. '  "pr view") echo main; exit 0 ;;\n'
				.. '  "pr edit") exit 0 ;;\n'
				.. "esac\nexit 0\n"
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}`, GH_LOG = `{f.base}/gh.log` }
		for _, raft in { "R0010", "R0020", "R0030" } do
			trackerfix.trOk(f, f.main, { "ready", raft })
		end
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
	end)

	it("worktree then start leaves no R####-<slug> branch", function()
		zn(wt, { "start", "R0010" })
		local branches = git(f.main, { "branch", "-a" })
		t.expect(has(branches, "R0010-")).toBe(false)
		t.expect(has(branches, "R0010/1/c0010")).toBe(true)
		t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
	end)

	it("finish unions an existing watch, filters by suite, and writes one acceptance watch", function()
		write(wt, "pickman/src/later.luau", "return {}\n")
		write(wt, "pickman/src/game.luau", "return {}\n")
		write(wt, "z-nile/engine/other.luau", "return {}\n")
		write(wt, "z-nile/tests/tooling/tool.spec.luau", "--!strict\nreturn nil\n")
		write(wt, "pickman/tests/unit/union.spec.luau", "--!strict\n-- edited\nreturn nil\n")
		write(wt, "pickman/tests/unit/suite.spec.luau", "--!strict\n-- edited\nreturn nil\n")
		write(wt, "pickman/.tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 work" })
		local out = zn(wt, { "finish", "c0010" })
		t.expect(has(out, "affected specs are skipped")).toBe(true)
		local acc = fs.readFile(`{wt}/pickman/.tracker/issues/active/c0010/acceptance/watch.txt`)
		t.expect(has(acc, "pickman/src/later.luau")).toBe(true)
		t.expect(has(acc, "pickman/src/game.luau")).toBe(true)
		t.expect(has(acc, "z-nile/engine/other.luau")).toBe(false)
		local union = fs.readFile(`{wt}/pickman/tests/unit/union.watch.txt`)
		t.expect(has(union, "pickman/src/earlier.luau")).toBe(true)
		t.expect(has(union, "pickman/src/later.luau")).toBe(true)
		t.expect(has(union, "z-nile/engine/other.luau")).toBe(false)
		local suite = fs.readFile(`{wt}/pickman/tests/unit/suite.watch.txt`)
		t.expect(has(suite, "pickman/src/game.luau")).toBe(true)
		t.expect(has(suite, "z-nile/engine/other.luau")).toBe(false)
		local tool = fs.readFile(`{wt}/z-nile/tests/tooling/tool.watch.txt`)
		t.expect(has(tool, "z-nile/engine/other.luau")).toBe(true)
		t.expect(has(tool, "pickman/src/later.luau")).toBe(false)
	end)

	it("a layer that changes no source file watches what the spec requires", function()
		zn(wt, { "start", "R0010" })
		write(
			wt,
			"pickman/tests/unit/req.spec.luau",
			`--!strict\n-- edited\n{R}("../../src/needed")\nreturn nil\n`
		)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0020 work" })
		zn(wt, { "finish", "c0020" })
		local watch = fs.readFile(`{wt}/pickman/tests/unit/req.watch.txt`)
		t.expect(has(watch, "pickman/src/needed.luau")).toBe(true)
		t.expect(has(watch, "pickman/src/later.luau")).toBe(false)
	end)

	it("done from a lower layer names that layer and both shas", function()
		git(wt, { "switch", "-q", "R0010/1/c0010" })
		local here = git(wt, { "rev-parse", "HEAD" })
		local land = git(f.main, { "rev-parse", "origin/R0010/2/c0020" })
		local refused = trackerfix.tr(f, wt, { "done", "R0010" }, env)
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, `R0010/1/c0010 is {here} and R0010/2/c0020 is {land}`)).toBe(true)
		t.expect(has(git(f.main, { "log", "--format=%s", "origin/main" }), "bind")).toBe(false)
	end)

	it("a failed push puts the pull request bases back", function()
		git(wt, { "switch", "-q", "R0010/2/c0020" })
		seal.trace(wt, "R0010")
		local bin, log = `{f.base}/bin`, `{f.base}/gh.log`
		fs.writeFile(
			`{bin}/gh`,
			`#!/bin/sh\necho "$*" >> "{log}"\n`
				.. 'case "$1 $2" in\n'
				.. '  "pr list") case "$*" in *R0010/2*) echo 2 ;; *) echo 1 ;; esac; exit 0 ;;\n'
				.. '  "pr view") case "$3" in 2) echo R0010/1/c0010 ;; *) echo main ;; esac; exit 0 ;;\n'
				.. '  "pr edit") exit 0 ;;\n'
				.. "esac\nexit 0\n"
		)
		local hook = `{f.origin}/hooks/pre-receive`
		fs.writeFile(
			hook,
			"#!/bin/sh\nwhile read old new ref; do\n"
				.. '  case "$ref" in refs/heads/main) echo deny main >&2; exit 1 ;; esac\n'
				.. "done\nexit 0\n"
		)
		process.exec("chmod", { "+x", hook })
		local before = git(f.main, { "rev-parse", "origin/main" })
		local pushed = trackerfix.tr(f, wt, { "done", "R0010" }, { PATH = `{bin}:{process.env.PATH or ""}` })
		t.expect(pushed.ok).toBe(false)
		t.expect(has(pushed.stderr, "could not push")).toBe(true)
		local calls = fs.readFile(log)
		t.expect(has(calls, "pr edit 2 --base main")).toBe(true)
		t.expect(has(calls, "pr edit 2 --base R0010/1/c0010")).toBe(true)
		t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
		fs.removeFile(hook)
	end)

	it("done from a top layer behind origin names that layer and both shas", function()
		git(wt, { "switch", "-q", "R0010/2/c0020" })
		local land = git(wt, { "rev-parse", "HEAD" })
		git(wt, { "reset", "--hard", "HEAD~1" })
		local here = git(wt, { "rev-parse", "HEAD" })
		local refused = trackerfix.tr(f, wt, { "done", "R0010" }, env)
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, `R0010/2/c0020 is {here} and R0010/2/c0020 is {land}`)).toBe(true)
	end)

	it("done with no review file records no verdict", function()
		local bare = trackerfix.trOk(f, f.main, { "worktree", "R0020" })
		zn(bare, { "start", "R0020" })
		write(bare, "pickman/src/gamma.luau", "return {}\n")
		git(bare, { "add", "-A" })
		git(bare, { "commit", "-qm", "c0030 work" })
		zn(bare, { "finish", "c0030" })
		t.expect(fs.isFile(`{bare}/pickman/.tracker/issues/active/c0030/acceptance/watch.txt`)).toBe(true)
		t.expect(fs.isFile(`{bare}/pickman/.tracker/issues/active/c0030/acceptance/foo.spec.luau`)).toBe(true)
		t.expect(fs.isFile(`{bare}/pickman/.tracker/issues/active/c0030/acceptance/foo.watch.txt`))
			.toBe(false)
		local refused = trackerfix.tr(f, bare, { "done", "R0020" }, env)
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "no review-NNN.md")).toBe(true)
		t.expect(has(git(bare, { "log", "--format=%s" }), "bind")).toBe(false)
	end)

	it("a review with no Verdict line is not recorded as approve", function()
		local bare = trackerfix.trOk(f, f.main, { "worktree", "R0030" })
		zn(bare, { "start", "R0030" })
		write(bare, "pickman/.tracker/rafts/active/R0030/review-001.md", "# Review 001\n\nNo ruling.\n")
		write(bare, "pickman/src/delta.luau", "return {}\n")
		git(bare, { "add", "-A" })
		git(bare, { "commit", "-qm", "c0040 work" })
		zn(bare, { "finish", "c0040" })
		local refused = trackerfix.tr(f, bare, { "done", "R0030" }, env)
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "no Verdict")).toBe(true)
		t.expect(has(git(bare, { "log", "--format=%s" }), "Verdict: approve")).toBe(false)
	end)

	it("finish outside a spec run goes green, and red when the selected spec fails", function()
		local passing = "--!strict\nlocal t = "
			.. R
			.. '("@tests/lib/t")\nreturn t.spec("ok", function(it)\n\tit("passes", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
		local seed: { [string]: string } = {
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha", "R0010"),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc("R0010", "alpha", "c0010", "c0010"),
			["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = "",
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/src/ok.luau"] = "return { value = 1 }\n",
			["pickman/tests/unit/ok.spec.luau"] = passing,
			["pickman/tests/unit/ok.watch.txt"] = "pickman/src/ok.luau\n",
			["pickman/.tracker/rafts/R0010/review-001.md"] = "# Review 001\n\nVerdict: approve\n",
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		}
		local run = trackerfix.new("stack-fix-run-github.com", seed)
		local function copy(rel: string)
			local parent = string.match(rel, "^(.*)/[^/]+$")
			if parent then
				fs.writeDir(`{run.main}/{parent}`)
			end
			local copied = process.exec("cp", { "-R", `{TOP}/{rel}`, `{run.main}/{rel}` })
			if not copied.ok then
				error(`cp {rel}: {copied.stderr}`)
			end
		end
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
			copy(rel)
		end
		git(run.main, { "add", "-A" })
		git(run.main, { "commit", "-qm", "runner" })
		git(run.main, { "push", "-q", "origin", "HEAD:main" })
		local bin = `{run.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(`{bin}/gh`, "#!/bin/sh\necho https://github.com/x/y/pull/1\nexit 0\n")
		process.exec("chmod", { "+x", `{bin}/gh` })
		local runEnv = { PATH = `{bin}:{process.env.PATH or ""}` }
		trackerfix.trOk(run, run.main, { "ready", "R0010" })
		local work = trackerfix.trOk(run, run.main, { "worktree", "R0010" })
		local function runZn(args: { string }, extra: { [string]: string }?): fixture.Result
			local child = table.clone(runEnv)
			if extra then
				for k, v in extra do
					child[k] = v
				end
			end
			return trackerfix.tr(run, work, args, child)
		end
		local started = runZn({ "start", "R0010" })
		if not started.ok then
			error(started.stderr .. started.stdout)
		end
		write(work, "pickman/src/ok.luau", "return { value = 2 }\n")
		git(work, { "add", "-A" })
		git(work, { "commit", "-qm", "change ok" })
		local gate = {
			PATH = process.env.PATH or "",
			PICKMAN_DONE_GATE = "1",
			ZN_MEASURED = "1",
		}
		local green = runZn({ "finish", "c0010" }, gate)
		if not green.ok then
			error(green.stderr .. green.stdout)
		end
		t.expect(has(green.stdout, "affected specs are skipped")).toBe(false)
		t.expect(has(green.stdout .. green.stderr, "passed")).toBe(true)
		write(
			work,
			"pickman/tests/unit/ok.spec.luau",
			"--!strict\nlocal t = "
				.. R
				.. '("@tests/lib/t")\nreturn t.spec("ok", function(it)\n\tit("passes", function()\n\t\tt.expect(1).toBe(2)\n\tend)\nend)\n'
		)
		git(work, { "add", "-A" })
		git(work, { "commit", "-qm", "break the spec" })
		local red = runZn({ "finish", "c0010" }, gate)
		t.expect(red.ok).toBe(false)
		t.expect(has(red.stderr, "a spec the watch map selects is red")).toBe(true)
	end)
end)
