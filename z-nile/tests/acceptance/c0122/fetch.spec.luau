--!strict
-- c0122 AC1: the ref guard, driven by real git end to end. c0131 pinned the hook by feeding it an empty
-- transaction by hand; this spec lets git itself send what a fetch sends. A fixture clone of a fixture origin, both
-- under this home's .cache, is fenced by z-nile/lib/fence.sh exactly as a check.sh flow (PICKMAN_FENCE_SPECS unset, as ac.sh leaves it;
-- once also exported empty) or a spec run (PICKMAN_FENCE_SPECS=1) fences its checkout, and git then runs in it. Here: a check.sh flow fetches
-- whether or not anything is new. What stays refused is refuse.spec.luau's (AC2). The fixture is the protected
-- repository: the fence adds its git directory to PICKMAN_FENCE_REAL_GIT. Nothing outside .cache is touched.
local clone = require("@tests/lib/clone")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- fixtures under this home's .cache (the working directory, c0120); root is for reading the tooling
local base = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/c0122-fetch`
local origin = `{base}/origin`
local work = `{base}/clone`
local runner = `{base}/fenced.sh`
local FENCE = `{root}/z-nile/lib/fence.sh`
local ZERO = string.rep("0", 40)

-- Fences the clone as ac.sh or the runner would, then runs git with `args` in it. `mode` sets the marker inside the
-- script, whatever the run this spec is in has set (zz-test/specs-set-host-markers-explicitly): `checks` unsets
-- PICKMAN_FENCE_SPECS, as a real check.sh flow has it (a hook that fails on an unset variable must show here),
-- `empty` exports it empty, `specs` exports 1 (a spec run).
local function fenced(mode: string, args: { string }): fixture.Result
	local argv = { runner, FENCE, work, mode }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(work, "bash", argv)
end

-- The host's git configuration never decides a case: every fetch names, with -c, the fetch settings its result
-- depends on (they outrank the global and system config), and the cases that need others set them themselves.
-- --atomic makes every git put the whole fetch in one transaction (git 2.50.1 gives each ref its own and starts none
-- for a fetch with nothing new); `plain` is the same without it, for the cases whose outcome holds on every git.
local PINS = {
	"-c",
	"fetch.prune=false",
	"-c",
	"fetch.pruneTags=false",
	"-c",
	"remote.origin.prune=false",
	"-c",
	"remote.origin.pruneTags=false",
	"-c",
	"remote.origin.tagOpt=--tags",
}

local function fetchWith(mode: string, atomic: boolean, args: { string }): fixture.Result
	local argv = table.clone(PINS)
	table.insert(argv, "fetch")
	if atomic then
		table.insert(argv, "--atomic")
	end
	for _, a in args do
		table.insert(argv, a)
	end
	return fenced(mode, argv)
end

local function fetch(mode: string, args: { string }): fixture.Result
	return fetchWith(mode, true, args)
end

local function plain(mode: string, args: { string }): fixture.Result
	return fetchWith(mode, false, args)
end

local function commitInOrigin(label: string)
	fixture.git(origin, {
		"-c",
		"user.name=c0122",
		"-c",
		"user.email=c0122@example.invalid",
		"commit",
		"-q",
		"--allow-empty",
		"-m",
		label,
	})
end

local function tip(dir: string, ref: string): string
	local r = fixture.exec(dir, "git", { "rev-parse", "--verify", "-q", ref })
	return if r.ok then trim(r.stdout) else ZERO
end

-- One line per case, so a failure shows every field: { a = 1, b = "x" } is "a=1 b=x", keys sorted
local function line(fields: { [string]: any }): string
	local keys = {}
	for k in fields do
		table.insert(keys, k)
	end
	table.sort(keys)
	local out = {}
	for _, k in keys do
		table.insert(out, `{k}={tostring(fields[k])}`)
	end
	return table.concat(out, " ")
end

local function outcome(r: fixture.Result): string
	return if r.ok then "ok" else `refused: {trim(r.stderr)}`
end

return t.spec("c0122 a check.sh flow can fetch whether or not anything is new", function(it)
	it("sets up a fixture origin and a clone of it", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(base)
		local init = process.exec("git", { "init", "-q", "-b", "main", origin }) -- creating a fixture needs no check
		t.expect(init.ok).toBe(true)
		commitInOrigin("first")
		clone.isolated(origin, work)
		-- fence.sh is sourced and the checkout fenced before git runs; a failing fence stops the script before git
		fs.writeFile(
			runner,
			table.concat({
				"#!/usr/bin/env bash",
				'source "$1" || exit 90',
				'case "$3" in',
				"checks) unset PICKMAN_FENCE_SPECS ;;",
				"empty) export PICKMAN_FENCE_SPECS= ;;",
				"specs) export PICKMAN_FENCE_SPECS=1 ;;",
				"*) exit 92 ;;",
				"esac",
				'pickman_fence "$2" || exit 91',
				'cd "$2" && shift 3 && git "$@"',
				"",
			}, "\n")
		)
		t.expect(tip(work, "refs/remotes/origin/main")).toBe(tip(origin, "HEAD"))
	end)

	it("AC1: a check.sh flow's fetch succeeds when it brings something and when nothing is new", function()
		commitInOrigin("second")
		local brings = plain("checks", { "-q", "origin" })
		local moved = tip(work, "refs/remotes/origin/main") == tip(origin, "HEAD")
		local nothing = plain("checks", { "-q", "origin" })
		local again = fetch("checks", { "-q", "origin" })
		local empty = fetch("empty", { "-q", "origin" }) -- the marker exported empty: also nothing new
		-- one more commit, and a branch the clone has no ref for: the fetch must create a remote-tracking ref too
		commitInOrigin("third")
		fixture.git(origin, { "branch", "extra" })
		local after = fetch("checks", { "-q", "origin" }) -- atomic: main moves and `extra` is created in one transaction
		t.expect(line({
			brings = outcome(brings),
			moved = moved,
			nothing = outcome(nothing),
			again = outcome(again),
			empty = outcome(empty),
			after = outcome(after),
			followed = tip(work, "refs/remotes/origin/main") == tip(origin, "HEAD"),
			created = tip(work, "refs/remotes/origin/extra") == tip(origin, "extra"),
		})).toBe(line({
			brings = "ok",
			moved = true,
			nothing = "ok",
			again = "ok",
			empty = "ok",
			after = "ok",
			followed = true,
			created = true,
		}))
	end)

	it(
		"AC1: the safe form succeeds with a tag and a deleted branch upstream, whatever prune and tag settings are on",
		function()
			fixture.git(origin, { "branch", "-D", "extra" })
			commitInOrigin("fourth")
			fixture.git(origin, { "tag", "v1" })
			-- every setting that makes a fetch prune or follow tags is on, on the command line; the flags must win
			local r = fenced("checks", {
				"-c",
				"fetch.prune=true",
				"-c",
				"fetch.pruneTags=true",
				"-c",
				"remote.origin.prune=true",
				"-c",
				"remote.origin.pruneTags=true",
				"-c",
				"remote.origin.tagOpt=--tags",
				"fetch",
				"--atomic",
				"--no-prune",
				"--no-prune-tags",
				"--no-tags",
				"-q",
				"origin",
			})
			t.expect(line({
				result = outcome(r),
				followed = tip(work, "refs/remotes/origin/main") == tip(origin, "HEAD"),
				staleKept = tip(work, "refs/remotes/origin/extra") ~= ZERO,
				noTag = tip(work, "refs/tags/v1") == ZERO,
			})).toBe(line({ result = "ok", followed = true, staleKept = true, noTag = true }))
		end
	)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
