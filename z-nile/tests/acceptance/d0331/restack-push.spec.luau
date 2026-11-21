--!strict
-- d0331: a restack whose push of one layer is rejected (seen on R0072: layer 1 pushed, layer 2 "remote rejected")
-- exits non-zero naming each layer it did not push, goes back to the branch it started on, and the next
-- restack of the raft puts the remote stack back in one piece.
-- Fixture: .cache/d0331-restack-push-github.com (its own origin and clones; origin's update hook rejects on demand).
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

local function isAncestor(dir: string, a: string, b: string): boolean
	return fixture.exec(dir, "git", { "merge-base", "--is-ancestor", a, b }).ok
end

return t.spec("d0331 a restack survives a rejected push", function(it)
	it("sets up a three-layer raft, all finished, and an origin that can reject pushes of layer 2", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = raftDoc(
				"R0010",
				"stack",
				"c0010, c0020, c0030",
				"c0010\nc0020\nc0030"
			),
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "alpha", "R0010"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "beta", "R0010"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "gamma", "R0010"),
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
		seed["pickman/.tracker/issues/c0030/acceptance/.gitkeep"] = ""
		seed["pickman/.tracker/issues/c0030/check.sh"] = CHECK
		f = trackerfix.new("d0331-restack-push-github.com", seed)
		local bin = `{f.base}/bin`
		fs.writeDir(bin)
		fs.writeFile(
			`{bin}/gh`,
			'#!/bin/sh\ncase "$1 $2" in\n  "pr list") case "$*" in *number*) echo 1 ;; esac; exit 0 ;;\n'
				.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n  "pr view") echo body; exit 0 ;;\nesac\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{bin}/gh` })
		env = { PATH = `{bin}:{process.env.PATH or ""}` }
		fs.writeFile(
			`{f.origin}/hooks/update`,
			'#!/bin/sh\ncase "$1" in refs/heads/R0010/2/*)\n  if [ -f "'
				.. f.base
				.. '/reject" ]; then echo "rejected on purpose" >&2; exit 1; fi ;;\nesac\nexit 0\n'
		)
		process.exec("chmod", { "+x", `{f.origin}/hooks/update` })
		trackerfix.trOk(f, f.main, { "ready", "R0010" })
		wt = trackerfix.trOk(f, f.main, { "worktree", "R0010" })
		zn(wt, { "start", "R0010" })
		write(wt, "pickman/src/alpha.luau", "alpha\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0010 work" })
		zn(wt, { "finish", "c0010" })
		seal.layerReview(wt, "c0010") -- c0248: a layer is reviewed before the next starts
		zn(wt, { "start", "R0010" })
		write(wt, "pickman/src/beta.luau", "beta\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0020 work" })
		zn(wt, { "finish", "c0020" })
		seal.layerReview(wt, "c0020")
		zn(wt, { "start", "R0010" })
		write(wt, "pickman/src/gamma.luau", "gamma\n")
		git(wt, { "add", "-A" })
		git(wt, { "commit", "-qm", "c0030 work" })
		zn(wt, { "finish", "c0030" })
	end)

	it(
		"AC9: the rejected layer is named as not pushed, the command fails, and the worktree is back on its branch",
		function()
			trackerfix.elsewhere(f, { ["pickman/src/moved.luau"] = "moved\n" }, "elsewhere: moved")
			git(wt, { "fetch", "-q", "origin" })
			local tip = git(wt, { "rev-parse", "origin/main" })
			local oldTwo = git(wt, { "rev-parse", "origin/R0010/2/c0020" })
			local oldThree = git(wt, { "rev-parse", "origin/R0010/3/c0030" })
			git(wt, { "switch", "-q", "R0010/1/c0010" })
			fs.writeFile(`{f.base}/reject`, "")
			local r = trackerfix.tr(f, wt, { "restack", "R0010" }, env)
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stderr,
					"the push of R0010/2/c0020 was rejected; not pushed: R0010/2/c0020, R0010/3/c0030. Run ./zn restack R0010 again"
				)
			).toBe(true)
			t.expect(has(r.stderr, "rejected on purpose")).toBe(true)
			t.expect(has(r.stdout, "restacked R0010")).toBe(false)
			t.expect(git(wt, { "branch", "--show-current" })).toBe("R0010/1/c0010")
			git(f.main, { "fetch", "-q", "origin" })
			-- the half-moved remote stack: layer 1 is on main's tip, layer 2 is where it was
			t.expect(isAncestor(f.main, tip, "origin/R0010/1/c0010")).toBe(true)
			t.expect(git(f.main, { "rev-parse", "origin/R0010/2/c0020" })).toBe(oldTwo)
			t.expect(isAncestor(f.main, "origin/R0010/1/c0010", "origin/R0010/2/c0020")).toBe(false)
			t.expect(git(f.main, { "rev-parse", "origin/R0010/3/c0030" })).toBe(oldThree)
			-- the local layer is what origin has, so nothing reads the stack as moved
			t.expect(git(wt, { "rev-parse", "R0010/2/c0020" })).toBe(oldTwo)
		end
	)

	it(
		"AC9: the next restack puts layer 3 on layer 2 on layer 1 on origin, each still one finish commit",
		function()
			fs.removeFile(`{f.base}/reject`)
			local again = zn(wt, { "restack", "R0010" })
			t.expect(has(again, "restacked R0010")).toBe(true)
			git(f.main, { "fetch", "-q", "origin" })
			-- c0248: layer 2 ends in its review commit, above its finish commit, above layer 1
			t.expect(git(f.main, { "rev-parse", "origin/R0010/2/c0020~2" }))
				.toBe(git(f.main, { "rev-parse", "origin/R0010/1/c0010" }))
			t.expect(git(f.main, { "log", "-4", "--format=%s", "origin/R0010/2/c0020" }))
				.toBe("tracker: review c0020\nc0020: beta\ntracker: review c0010\nc0010: alpha")
			t.expect(git(f.main, { "show", "origin/R0010/2/c0020:pickman/src/beta.luau" })).toBe("beta")
			t.expect(git(f.main, { "rev-parse", "origin/R0010/3/c0030^" }))
				.toBe(git(f.main, { "rev-parse", "origin/R0010/2/c0020" }))
			t.expect(git(f.main, { "log", "-5", "--format=%s", "origin/R0010/3/c0030" }))
				.toBe("c0030: gamma\ntracker: review c0020\nc0020: beta\ntracker: review c0010\nc0010: alpha")
			local seen = zn(wt, { "stack", "R0010" })
			t.expect(has(seen, "3 R0010/3/c0030 c0030 finished")).toBe(true)
			t.expect(has(seen, "1 R0010/1/c0010 c0010 complete")).toBe(true)
			t.expect(has(seen, "2 R0010/2/c0020 c0020 complete")).toBe(true)
			local third = zn(wt, { "restack", "R0010" })
			t.expect(has(third, "already stacked")).toBe(true)
		end
	)
end)
