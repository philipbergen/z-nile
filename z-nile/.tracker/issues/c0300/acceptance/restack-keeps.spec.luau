--!strict
-- c0300: `./zn restack` on an unfinished layer (several worker commits on its `tracker: start`, each titled
-- "c0010: ...", the shape R0093 truncated) keeps every commit, or refuses the layer unchanged; a red or killed
-- check leaves no ref on a truncated layer, and the restack after a killed one finishes the layer with no hand
-- repair; `finish` on a layer only behind main is moved on by the restack it names. One raft, one layer, cases in
-- order. Fixture: .cache/c0300-restack-github.com.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local LAYER = "R0010/1/c0010"
-- red.txt on main turns the check red; kill.txt on main, or .cache/c0300-kill in the worktree (ignored, so main need
-- not move again), kills the restack (check.sh's parent) mid-check
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'top="$(git rev-parse --show-toplevel)"\n'
	.. 'if [[ -f "$top/pickman/src/kill.txt" || -f "$top/.cache/c0300-kill" ]]; then kill -9 "$PPID"; exit 1; fi\n'
	.. 'check "AC1: not red" test ! -f "$top/pickman/src/red.txt"\nfinish\n'

local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local f: trackerfix.Fixture
local wt = ""
local env: { [string]: string } = {}

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function tr(args: { string }): fixture.Result
	return trackerfix.tr(f, wt, args, env)
end

local function zn(args: { string }): string
	local r = tr(args)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return r.stdout
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

-- A seeded file the layer edits at line 10 (a conflict and a rename on main use it).
local function shared(line10: string): string
	local lines = {}
	for i = 1, 20 do
		table.insert(lines, if i == 10 then line10 else `local line{i} = {i}`)
	end
	return table.concat(lines, "\n") .. "\n"
end

-- One commit in the worktree, titled the way a worker titles its commits on a layer.
local function work(name: string)
	write(wt, `pickman/src/{name}.luau`, `return "{name}"\n`)
	git(wt, { "add", "-A" })
	git(wt, { "commit", "-qm", `c0010: {name}` })
end

-- Another terminal moves origin's main: renames each `moves` key to its value, writes `add`, deletes `drop`.
local function mainMoves(
	add: { [string]: string },
	drop: { string },
	message: string,
	moves: { [string]: string }?
)
	git(f.other, { "switch", "-q", "main" })
	git(f.other, { "pull", "-q", "origin", "main" })
	local renames: { [string]: string } = moves or {}
	for from, to in renames do
		git(f.other, { "mv", from, to })
	end
	for path, text in add do
		write(f.other, path, text)
	end
	for _, path in drop do
		git(f.other, { "rm", "-q", path })
	end
	git(f.other, { "add", "-A" })
	git(f.other, { "commit", "-qm", message })
	git(f.other, { "push", "-q", "origin", "HEAD:main" })
end

-- The layer's own commits on `ref`, oldest first: each subject with the lines its change adds and removes.
-- Independent of the tool's own change key: it reads the -U0 patch's +/- lines (not its paths).
local function held(ref: string): string
	local out: { string } = {}
	local shas = git(wt, { "rev-list", "--reverse", `origin/main..{ref}` })
	for sha in string.gmatch(shas .. "\n", "(%x+)\n") do
		local subject = git(wt, { "log", "-1", "--format=%s", sha })
		local patch = git(wt, { "diff-tree", "-p", "-U0", "--no-commit-id", "-r", sha })
		local lines: { string } = { subject }
		for line in string.gmatch(patch .. "\n", "([^\n]*)\n") do
			local c = string.sub(line, 1, 1)
			if
				(c == "+" or c == "-")
				and string.sub(line, 1, 3) ~= "+++"
				and string.sub(line, 1, 3) ~= "---"
			then
				table.insert(lines, "  " .. line)
			end
		end
		table.insert(out, table.concat(lines, "\n"))
	end
	return table.concat(out, "\n")
end

local function sha(ref: string): string
	return git(wt, { "rev-parse", ref })
end

local function remote(): string
	return git(f.main, { "ls-remote", "origin", `refs/heads/{LAYER}` })
end

return t.spec("c0300: restack keeps every commit of an unfinished layer", function(it)
	it("sets up a readied raft whose layer holds four worker commits", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: stack\nslug: stack\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# R0010\n\n## Order & dependencies\nc0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/c0010.md"] = `---\nid: c0010\ntype: chore\ntitle: alpha\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# c0010\n\n{CAPTURED}`,
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = "",
			["pickman/src/shared.luau"] = shared("local line10 = 10"),
		}
		f = trackerfix.new("c0300-restack-github.com", seed)
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			'#!/bin/sh\ncase "$1 $2" in\n  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
				.. '  "pr view") echo body; exit 0 ;;\nesac\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn({ "start", "R0010" })
		t.expect(git(wt, { "branch", "--show-current" })).toBe(LAYER)
		work("one")
		work("two")
		work("three")
		write(wt, "pickman/src/shared.luau", shared("local line10 = 'layer'"))
		git(wt, { "commit", "-qam", "c0010: edit shared" })
		git(wt, { "push", "-q", "origin", LAYER })
		t.expect(git(wt, { "rev-list", "--count", `origin/main..{LAYER}` })).toBe("5")
	end)

	it(
		"AC3: a restack whose rebuilt layer fails its check leaves the branch and its remote where they were",
		function()
			local before, layer, ref = held(LAYER), sha(LAYER), remote()
			mainMoves({ ["pickman/src/red.txt"] = "red\n" }, {}, "main turns c0010's check red")
			local r = tr({ "restack", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, `restack stopped at {LAYER}: c0010 check.sh failed`)).toBe(true)
			t.expect(sha(LAYER)).toBe(layer)
			t.expect(remote()).toBe(ref)
			t.expect(held(LAYER)).toBe(before)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(LAYER)
		end
	)

	it("AC3: a restack killed during its check leaves no ref on a layer missing a commit", function()
		local before, ref = held(LAYER), remote()
		mainMoves(
			{ ["pickman/src/kill.txt"] = "kill\n" },
			{ "pickman/src/red.txt" },
			"main kills the next restack"
		)
		local r = tr({ "restack", "R0010" })
		t.expect(r.ok).toBe(false)
		-- origin is pushed only after a green check
		t.expect(remote()).toBe(ref)
		-- the local branch is either where it was or the whole rebuilt layer, never a truncated one
		git(wt, { "fetch", "-q", "origin" })
		t.expect(held(LAYER)).toBe(before)
	end)

	it("AC3: the restack after a killed one finishes the layer, with no hand repair", function()
		-- the layer as origin still holds it: a killed restack never pushed, so this is every commit
		git(wt, { "fetch", "-q", "origin" })
		local before = held(`origin/{LAYER}`)
		mainMoves({}, { "pickman/src/kill.txt" }, "main stops killing restacks")
		local r = tr({ "restack", "R0010" })
		t.expect(r.ok).toBe(true)
		git(wt, { "fetch", "-q", "origin" })
		t.expect(sha(`origin/{LAYER}`)).toBe(sha(LAYER))
		t.expect(held(LAYER)).toBe(before)
		t.expect(held(`origin/{LAYER}`)).toBe(before)
		t.expect(fixture.exec(wt, "git", { "merge-base", "--is-ancestor", "origin/main", LAYER }).ok)
			.toBe(true)
	end)

	it(
		"AC3: a restack killed when main does not move again is finished by the next one, which pushes it",
		function()
			git(wt, { "fetch", "-q", "origin" })
			local before, ref = held(`origin/{LAYER}`), remote()
			mainMoves({ ["pickman/src/main2.txt"] = "moved\n" }, {}, "main moves once")
			fs.writeDir(`{wt}/.cache`)
			fs.writeFile(`{wt}/.cache/c0300-kill`, "")
			local killed = tr({ "restack", "R0010" })
			t.expect(killed.ok).toBe(false)
			t.expect(remote()).toBe(ref)
			git(wt, { "fetch", "-q", "origin" })
			t.expect(held(LAYER)).toBe(before)
			t.expect(has(before, "c0010: edit shared")).toBe(true)
			fs.removeFile(`{wt}/.cache/c0300-kill`)
			local r = tr({ "restack", "R0010" })
			t.expect(r.ok).toBe(true)
			git(wt, { "fetch", "-q", "origin" })
			t.expect(remote() ~= ref).toBe(true)
			t.expect(sha(`origin/{LAYER}`)).toBe(sha(LAYER))
			t.expect(held(`origin/{LAYER}`)).toBe(before)
		end
	)

	it(
		"AC2: a conflict refuses the layer with its branch, its remote and the worktree as they were",
		function()
			local layer, ref = sha(LAYER), remote()
			mainMoves(
				{ ["pickman/src/shared.luau"] = shared("local line10 = 'main'") },
				{},
				"main edits line 10 too"
			)
			local r = tr({ "restack", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, `restack stopped at {LAYER}: conflict`)).toBe(true)
			t.expect(sha(LAYER)).toBe(layer)
			t.expect(remote()).toBe(ref)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(LAYER)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
			mainMoves(
				{ ["pickman/src/shared.luau"] = shared("local line10 = 10") },
				{},
				"main takes line 10 back"
			)
		end
	)

	it(
		"AC2: a commit whose change is already on main refuses the layer unchanged and says what to do",
		function()
			local layer, ref = sha(LAYER), remote()
			mainMoves(
				{ ["pickman/src/two.luau"] = 'return "two"\n' },
				{},
				"main carries the change of c0010: two"
			)
			local r = tr({ "restack", "R0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, `restack stopped at {LAYER}`)).toBe(true)
			t.expect(has(r.stderr, '"c0010: two" is empty on the new base')).toBe(true)
			t.expect(has(r.stderr, "nothing was changed")).toBe(true)
			t.expect(has(r.stderr, "./zn restack R0010")).toBe(true)
			t.expect(sha(LAYER)).toBe(layer)
			t.expect(remote()).toBe(ref)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(LAYER)
			t.expect(git(wt, { "status", "--porcelain" })).toBe("")
		end
	)

	it("AC2: a local branch and origin copy that have diverged refuse the layer unchanged", function()
		mainMoves({}, { "pickman/src/two.luau" }, "main drops two.luau again")
		git(f.other, { "fetch", "-q", "origin" })
		git(f.other, { "switch", "-q", "-c", "elsewhere", `origin/{LAYER}` })
		write(f.other, "pickman/src/other.luau", 'return "other"\n')
		git(f.other, { "add", "-A" })
		git(f.other, { "commit", "-qm", "c0010: other" })
		git(f.other, { "push", "-q", "origin", `elsewhere:{LAYER}` })
		work("four")
		local layer, ref = sha(LAYER), remote()
		local r = tr({ "restack", "R0010" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, `restack stopped at {LAYER}`)).toBe(true)
		t.expect(has(r.stderr, "diverged")).toBe(true)
		t.expect(has(r.stderr, "nothing was changed")).toBe(true)
		t.expect(has(r.stderr, `git pull --rebase origin {LAYER}`)).toBe(true)
		t.expect(sha(LAYER)).toBe(layer)
		t.expect(remote()).toBe(ref)
		-- bring them together as the refusal says
		git(wt, { "pull", "-q", "--rebase", "origin", LAYER })
		git(wt, { "push", "-q", "origin", LAYER })
	end)

	it(
		"AC1, AC4: finish names restack, restack keeps every commit (an unpushed one too), and finish then succeeds",
		function()
			work("five") -- local only: the local branch is ahead of origin
			-- a rename on main of a file the layer edits: a clean rebase, the same change under another path
			mainMoves(
				{},
				{},
				"main renames shared.luau",
				{ ["pickman/src/shared.luau"] = "pickman/src/common.luau" }
			)
			git(wt, { "fetch", "-q", "origin" })
			local before = held(LAYER)
			t.expect(has(before, "c0010: one")).toBe(true)
			t.expect(has(before, "c0010: five")).toBe(true)
			local refused = tr({ "finish", "c0010" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "./zn restack R0010")).toBe(true)
			local restacked = tr({ "restack", "R0010" })
			t.expect(restacked.ok).toBe(true)
			t.expect(has(restacked.stdout, "restacked R0010")).toBe(true)
			git(wt, { "fetch", "-q", "origin" })
			-- one commit for each commit it held, same subject and change, same order, on the new main
			t.expect(held(LAYER)).toBe(before)
			t.expect(held(`origin/{LAYER}`)).toBe(before)
			t.expect(sha(`origin/{LAYER}`)).toBe(sha(LAYER))
			t.expect(fixture.exec(wt, "git", { "merge-base", "--is-ancestor", "origin/main", LAYER }).ok)
				.toBe(true)
			t.expect(git(wt, { "branch", "--show-current" })).toBe(LAYER)
			zn({ "finish", "c0010" })
			t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0010: alpha")
			t.expect(git(wt, { "rev-list", "--count", "origin/main..HEAD" })).toBe("1")
			for _, name in { "one", "two", "three", "four", "five", "other" } do
				t.expect(fs.isFile(`{wt}/pickman/src/{name}.luau`)).toBe(true)
			end
			t.expect(has(fs.readFile(`{wt}/pickman/src/common.luau`), "local line10 = 'layer'")).toBe(true)
			t.expect(fs.isFile(`{wt}/pickman/src/shared.luau`)).toBe(false)
		end
	)
end)
