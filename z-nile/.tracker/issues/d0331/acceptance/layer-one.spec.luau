--!strict
-- d0331: layer 1 of a raft is judged against the commit where it left main, not against main's newest commit.
-- finish, start, stack, work next, trace and done all accept a stack that main moved past, with no restack;
-- layers 2 and up keep the rule that each contains the tip of the layer below.
-- Fixture: .cache/d0331-layer-one-github.com (its own origin and clones).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local CAPTURED =
	"## Problem\nThe marker is missing.\n\n## Solution\nStore the marker.\n\n## Acceptance criteria\n- AC1: the marker is stored\n"

local function issue(id: string, title: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {title}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n{CAPTURED}`
end

local function raftDoc(id: string, slug: string, issues: string, order: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {slug}\nslug: {slug}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-10-06\nstatus: {PREPARED}\n---\n\n# {id}\n\n## Order & dependencies\n{order}\n`
end

local f: trackerfix.Fixture
local wt = ""
local env: { [string]: string } = {}
local finish1 = ""

local function must(r: fixture.Result, what: string): string
	if not r.ok then
		error(`{what} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function zn(dir: string, args: { string }): string
	return must(trackerfix.tr(f, dir, args, env), "./zn " .. table.concat(args, " "))
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

-- Another terminal lands a source file on origin's main; returns main's new tip.
local function mainMoves(n: number): string
	trackerfix.elsewhere(f, { [`pickman/src/moved{n}.luau`] = `moved {n}\n` }, `elsewhere: moved {n}`)
	git(wt, { "fetch", "-q", "origin" })
	return git(wt, { "rev-parse", "origin/main" })
end

local function isAncestor(dir: string, a: string, b: string): boolean
	return fixture.exec(dir, "git", { "merge-base", "--is-ancestor", a, b }).ok
end

return t.spec("d0331 layer 1 is judged against where it left main", function(it)
	it("sets up a two-ticket raft, started, behind a local github-shaped origin", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc(
				"R0010",
				"stack",
				"c0010, c0020",
				"c0010\nc0020"
			),
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha", "R0010"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "beta", "R0010"),
		}
		for _, dir in
			{
				"pickman/.tracker/rafts/R0010",
				"pickman/.tracker/issues/c0010",
				"pickman/.tracker/issues/c0020",
			}
		do
			seed[`{dir}/check.sh`] = CHECK
		end
		seed["pickman/.tracker/issues/c0010/acceptance/.gitkeep"] = ""
		seed["pickman/.tracker/issues/c0020/acceptance/.gitkeep"] = ""
		f = trackerfix.new("d0331-layer-one-github.com", seed)
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			'#!/bin/sh\ncase "$1 $2" in\n  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n  "pr view") echo body; exit 0 ;;\nesac\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		write(wt, "pickman/src/alpha.luau", "alpha\n")
		write(
			wt,
			"pickman/.tracker/rafts/active/R0010/final-review-001.md",
			"# Final Review 001\n\nVerdict: approve\n"
		)
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 work" })
	end)

	it(
		"AC1: finish accepts layer 1 after main gained a commit, as one commit on the fork, with only its own files",
		function()
			local fork = git(wt, { "rev-parse", "origin/main" })
			local moved = mainMoves(1)
			t.expect(moved ~= fork).toBe(true)
			zn(wt, { "finish", "c0010" })
			finish1 = git(wt, { "rev-parse", "HEAD" })
			t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0010: alpha")
			t.expect(git(wt, { "rev-parse", "HEAD^" })).toBe(fork)
			-- finish did not rebase the layer: main's new commit is still not in it
			t.expect(isAncestor(wt, moved, "HEAD")).toBe(false)
			local files = git(wt, { "diff", "--name-only", "HEAD^", "HEAD" })
			t.expect(has(files, "pickman/src/alpha.luau")).toBe(true)
			t.expect(has(files, "moved1.luau")).toBe(false)
			local watch = fs.readFile(`{wt}/pickman/.tracker/issues/active/c0010/acceptance/watch.txt`)
			t.expect(has(watch, "pickman/src/alpha.luau")).toBe(true)
			t.expect(has(watch, "moved1.luau")).toBe(false)
			t.expect(git(f.main, { "ls-remote", "origin", "refs/heads/R0010/1/c0010" }) ~= "").toBe(true)
		end
	)

	it(
		"AC2: stack and work next call the layer finished after main moved, and start opens layer 2",
		function()
			mainMoves(2)
			git(f.other, { "fetch", "-q", "origin" })
			local seen = zn(f.other, { "stack", "R0010" })
			t.expect(has(seen, "1 R0010/1/c0010 c0010 finished")).toBe(true)
			local nextUp = zn(wt, { "work", "next", "R0010" })
			t.expect(has(nextUp, "restack")).toBe(false)
			t.expect(has(nextUp, "./zn finish c0010")).toBe(false)
			t.expect(has(nextUp, "./zn start R0010")).toBe(true)
			zn(wt, { "start", "R0010" })
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/2/c0020")
			t.expect(git(wt, { "rev-parse", "HEAD^" })).toBe(finish1)
		end
	)

	it(
		"AC3: a layer above still has to contain the tip of the layer below, and restack still moves the stack onto main's tip",
		function()
			write(wt, "pickman/src/beta.luau", "beta\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0020 work" })
			git(wt, { "push", "-q", "origin", "R0010/2/c0020" })
			git(wt, { "switch", "-q", "R0010/1/c0010" })
			write(wt, "pickman/src/fix.luau", "fix\n")
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "fix layer 1" })
			git(wt, { "push", "-q", "origin", "R0010/1/c0010" })
			zn(wt, { "finish", "c0010" })
			git(wt, { "switch", "-q", "R0010/2/c0020" })
			local refused = trackerfix.tr(f, wt, { "finish", "c0020" }, env)
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "R0010/2/c0020 is not based on the layer below: ./zn restack R0010"))
				.toBe(true)
			local tip = git(wt, { "rev-parse", "origin/main" })
			zn(wt, { "restack", "R0010" })
			git(wt, { "fetch", "-q", "origin" })
			t.expect(isAncestor(wt, tip, "origin/R0010/1/c0010")).toBe(true)
			t.expect(isAncestor(wt, "origin/R0010/1/c0010", "origin/R0010/2/c0020")).toBe(true)
			git(wt, { "switch", "-q", "R0010/2/c0020" })
			zn(wt, { "finish", "c0020" })
			t.expect(git(wt, { "log", "-1", "--format=%s" })).toBe("c0020: beta")
		end
	)

	it(
		"AC4: with every layer finished, work next goes on to the review after main moved, never to a restack or a finish",
		function()
			mainMoves(3)
			local moved = zn(wt, { "work", "next", "R0010" })
			if has(moved, "restack") or has(moved, "./zn finish") or not has(moved, "code review") then
				error(`work next after main moved: {moved}`)
			end
			git(f.other, { "fetch", "-q", "origin" })
			local seen = zn(f.other, { "stack", "R0010" })
			t.expect(has(seen, "1 R0010/1/c0010 c0010 finished")).toBe(true)
			t.expect(has(seen, "2 R0010/2/c0020 c0020 finished")).toBe(true)
		end
	)

	it(
		"AC5: trace and done accept the stack after main moved again, and done lands it on main's tip with no restack",
		function()
			local one = git(wt, { "rev-parse", "origin/R0010/1/c0010" })
			mainMoves(4)
			seal.trace(wt, "R0010")
			local top = git(wt, { "rev-parse", "HEAD" })
			local tip = mainMoves(5)
			t.expect(isAncestor(wt, tip, top)).toBe(false)
			local landed = zn(wt, { "done", "R0010" })
			t.expect(has(landed, "landed R0010")).toBe(true)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "log", "-1", "--format=%s", "origin/main" }))
				.toBe("R0010: bind c0010, c0020")
			t.expect(git(f.main, { "rev-parse", "origin/main^1" })).toBe(tip)
			t.expect(git(f.main, { "rev-parse", "origin/main^2" })).toBe(top)
			t.expect(isAncestor(f.main, one, "origin/main")).toBe(true)
			t.expect(git(f.main, { "show", "origin/main:pickman/src/moved5.luau" })).toBe("moved 5")
			t.expect(git(f.main, { "show", "origin/main:pickman/src/beta.luau" })).toBe("beta")
		end
	)
end)
