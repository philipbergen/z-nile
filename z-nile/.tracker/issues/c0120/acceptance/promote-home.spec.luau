--!strict
-- c0120 AC7: `./zn done` promotes a pickman member's acceptance specs into pickman/tests/acceptance/<id> (its project's
-- home), never the root's tests/acceptance, and checks them there: the type check reads pickman/tests and the meta spec
-- and the promoted specs run from pickman/, so a promoted spec's @logic and relative paths are pickman's.
-- `promote-check` does the same with copies it removes. A deliver's spend counts no promoted spec of any project, and a
-- compaction renames pickman's promoted folders and rewrites the paths that name them. Fixture under
-- .cache/c0120-promote: a clone of the repository with its tooling, pickman's items in pickman/.tracker, a stub gate.
local audit = require("@znile/engine/audit")
local compact = require("@znile/engine/compact")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

-- a promoted-spec path in two parts, so a compaction never rewrites this spec's own test data
local ACC = "tests/" .. "acceptance/"

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

-- the checkout's top (cloned from) and this home's .cache (these specs run from z-nile/, c0120)
local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0120-promote`
local work = `{base}/work`

local REQ = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local TRIVIAL_CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC1: fixture" true\nfinish\n'
-- a promoted spec that only passes from pickman/: pickman's @logic, and a path relative to the home
local ALPHA = table.concat({
	"--!strict",
	`local fs = {REQ}("@lune/fs")`,
	`local Maze = {REQ}("@logic/Maze")`,
	`local t = {REQ}("@tests/lib/t")`,
	'return t.spec("alpha", function(it)',
	'\tit("runs from pickman/", function()',
	'\t\tt.expect(type(Maze.parse)).toBe("function")',
	'\t\tt.expect(fs.isFile("src/shared/Logic/Maze/init.luau")).toBe(true)',
	"\tend)",
	"end)",
	"",
}, "\n")
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
local function tr(args: { string }): Result
	return fixture.exec(work, "bash", { "scripts/tracker.sh", table.unpack(args) }, { env = ID })
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

return t.spec("c0120 done promotes into the item's home", function(it)
	it("sets up a clone with a started, reviewed pickman raft whose member has an acceptance spec", function()
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
			"pickman/scripts",
			"pickman/tests/run.luau",
			"pickman/tests/lib",
			"pickman/tests/meta",
			"pickman/.luaurc",
			".luaurc",
			":(exclude)z-nile/.tracker",
			":(exclude)z-nile/tests/acceptance",
			":(exclude)z-nile/tests/tooling",
			":(exclude)z-nile/next",
			":(exclude)z-nile/compaction.txt",
		}, { cwd = root })
		for path in string.gmatch(listed.stdout, "[^\n]+") do
			if fs.isFile(`{root}/{path}`) then
				write(path, fs.readFile(`{root}/{path}`))
			end
		end
		write("z-nile/check.sh", "#!/usr/bin/env bash\nexit 0\n") -- a stub gate: done's spec-run path never calls it
		git({ "config", "gc.auto", "0" })
		engine.empty(work)
		write("z-nile/projects.toml", REGISTRY)
		for _, state in { "issues/active", "issues/done", "rafts/active", "rafts/done" } do
			write(`pickman/.tracker/{state}/.gitkeep`, "")
		end
		git({ "add", "-A" })
		git({ "commit", "-qm", "empty tracker, pickman's home", "--allow-empty" })
		t.expect(must(tr({ "new", "issue", "f", "alpha" }), "new issue"))
			.toBe("pickman/.tracker/issues/f0010/f0010.md")
		must(tr({ "new", "raft", "feature", "demo", "f0010", "--single" }), "new raft")
		for _, doc in { "pickman/.tracker/issues/f0010/f0010.md", "pickman/.tracker/rafts/R0010/R0010.md" } do
			edit(doc, "design: draft", "design: ready")
		end
		edit(
			"pickman/.tracker/issues/f0010/f0010.md",
			"### Touched modules\n",
			"### Touched modules\n- `notes/alpha`\n"
		)
		write("pickman/.tracker/issues/f0010/acceptance/alpha.spec.luau", ALPHA)
		write("pickman/.tracker/issues/f0010/check.sh", TRIVIAL_CHECK)
		write("pickman/.tracker/rafts/R0010/check.sh", TRIVIAL_CHECK)
		git({ "add", "-A" })
		git({ "commit", "-qm", "prep ready" })
		must(tr({ "start", "R0010" }), "start")
		write("pickman/.tracker/rafts/active/R0010/review-001.md", "# Review 001\n\nVerdict: approve\n")
		must(tr({ "commit", "-m", "review 001", "--time", "1" }), "commit")
	end)

	it("spend's lines leave out every project's promoted specs", function()
		write("pickman/" .. ACC .. "f0099/x.spec.luau", "--!strict\nreturn nil\n")
		write("z-nile/" .. ACC .. "c0099/y.spec.luau", "--!strict\nreturn nil\n")
		write("pickman/src/counted.luau", "--!strict\nreturn 1\n")
		write(
			"probe-spend.luau",
			`local spend = {REQ}("./z-nile/engine/spend")\nfor _, s in spend.stagedStats(true) do print(s.path) end\n`
		)
		git({ "add", "pickman/" .. ACC .. "f0099", "z-nile/" .. ACC .. "c0099", "pickman/src/counted.luau" })
		local r = fixture.exec(work, "lune", { "run", "probe-spend.luau" })
		git({ "reset", "-q", "HEAD", "--", "." })
		for _, rel in { "pickman/" .. ACC .. "f0099", "z-nile/" .. ACC .. "c0099" } do
			fs.removeDir(`{work}/{rel}`)
		end
		fs.removeFile(`{work}/pickman/src/counted.luau`)
		fs.removeFile(`{work}/probe-spend.luau`)
		t.expect(r.ok).toBe(true)
		t.expect(r.stdout).toBe("pickman/src/counted.luau\n")
	end)

	it("promote-check checks copies in pickman/tests/acceptance from pickman/, then removes them", function()
		local r = tr({ "promote-check", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(fs.isDir(`{work}/pickman/{ACC}f0010`)).toBe(false)
		t.expect(fs.isDir(`{work}/{ACC}f0010`)).toBe(false)
		t.expect(git({ "status", "--porcelain" })).toBe("")
	end)

	it("done moves the specs into pickman/tests/acceptance/<id> and runs them from pickman/", function()
		local r = tr({ "done", "R0010" })
		if not r.ok then
			error(r.stderr .. r.stdout)
		end
		t.expect(fs.isFile(`{work}/pickman/{ACC}f0010/alpha.spec.luau`)).toBe(true)
		t.expect(fs.isDir(`{work}/{ACC}f0010`)).toBe(false)
		t.expect(fs.isDir(`{work}/pickman/.tracker/issues/done/f0010`)).toBe(true)
		t.expect(fs.isDir(`{work}/pickman/.tracker/rafts/done/R0010`)).toBe(true)
		-- the promoted spec ran (it only passes from pickman/)
		t.expect(string.find(r.stdout, "passed, 0 failed", 1, true) ~= nil).toBe(true)
		t.expect(git({ "log", "-1", "--format=%s" })).toBe("tracker: done R0010")
		local promoted =
			git({ "show", "--name-status", "--format=", "HEAD", "--", "pickman/tests/acceptance" })
		t.expect(string.find(promoted, "pickman/" .. ACC .. "f0010/alpha.spec.luau", 1, true) ~= nil)
			.toBe(true)
	end)

	it("the done check.sh still finds its promoted specs from pickman/", function()
		write(
			"pickman/.tracker/issues/done/f0010/check.sh",
			'HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"\n'
				.. 'source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
				.. 'A="$HERE/acceptance"\n[[ -d $A ]] || A="$PWD/tests/acceptance/f0010"\n'
				.. 'check "AC1: alpha" lune run tests/run -- "$A/alpha.spec.luau"\nfinish\n'
		)
		local r = fixture.exec(work, "bash", { "pickman/.tracker/issues/done/f0010/check.sh" })
		git({ "checkout", "--", "pickman/.tracker/issues/done/f0010/check.sh" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(string.find(r.stdout, "PASS  AC1: alpha", 1, true) ~= nil).toBe(true)
	end)

	it("a compaction renames pickman's promoted folders and rewrites the paths that name them", function()
		write("notes.md", "see pickman/" .. ACC .. "f0010/alpha.spec.luau\n")
		write("pickman/notes.md", "see " .. ACC .. "f0010/alpha.spec.luau\n")
		git({ "add", "-A" })
		git({ "commit", "-qm", "notes" })
		compact.apply({ f0010 = "f0001", R0010 = "R0001" }, audit.scan(work), work)
		t.expect(fs.isFile(`{work}/pickman/{ACC}f0001/alpha.spec.luau`)).toBe(true)
		t.expect(fs.isDir(`{work}/pickman/{ACC}f0010`)).toBe(false)
		t.expect(fs.isDir(`{work}/pickman/.tracker/issues/done/f0001`)).toBe(true)
		t.expect(fs.readFile(`{work}/notes.md`)).toBe("see pickman/" .. ACC .. "f0001/alpha.spec.luau\n")
		t.expect(fs.readFile(`{work}/pickman/notes.md`)).toBe("see " .. ACC .. "f0001/alpha.spec.luau\n")
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
