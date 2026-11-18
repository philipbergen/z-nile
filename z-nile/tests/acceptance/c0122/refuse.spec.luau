--!strict
-- c0122 AC2: the ref guard, driven by real git end to end. c0131 pinned the hook by feeding it an empty
-- transaction by hand; this spec lets git itself send what a fetch sends. A fixture clone of a fixture origin, both
-- under this home's .cache, is fenced by z-nile/lib/fence.sh exactly as a check.sh flow (PICKMAN_FENCE_SPECS unset, as ac.sh leaves it;
-- once also exported empty) or a spec run (PICKMAN_FENCE_SPECS=1) fences its checkout, and git then runs in it. Here: what stays refused. What a
-- check.sh flow may do is fetch.spec.luau's (AC1). The fixture is the protected
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
local base = `{(string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))}/.cache/c0122-refuse`
local origin = `{base}/origin`
local work = `{base}/clone`
local runner = `{base}/fenced.sh`
local FENCE = `{root}/z-nile/lib/fence.sh`
local ZERO = string.rep("0", 40)

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

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
-- for a fetch with nothing new), so every refusal here is of the whole fetch on every git.
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

return t.spec("c0122 the ref guard still refuses the rest, end to end", function(it)
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

	it("AC2: a spec run's fetch is refused whether or not anything is new, and moves nothing", function()
		local before = tip(work, "refs/remotes/origin/main")
		local nothing = fetch("specs", { "-q", "origin" })
		commitInOrigin("fourth")
		local brings = fetch("specs", { "-q", "origin" })
		t.expect(line({
			nothing = has(nothing.stderr, "fence: a check tried to change refs in the real repository"),
			nothingOk = nothing.ok,
			brings = has(brings.stderr, "fence: a check tried to change refs in the real repository"),
			bringsOk = brings.ok,
			unmoved = tip(work, "refs/remotes/origin/main") == before,
		})).toBe(
			line({ nothing = true, nothingOk = false, brings = true, bringsOk = false, unmoved = true })
		)
	end)

	it("AC2: a check.sh flow's pruning fetch is refused whole, and moves nothing", function()
		fixture.git(origin, { "branch", "gone" })
		local first = fetch("checks", { "--no-prune", "-q", "origin" }) -- creates origin/gone
		fixture.git(origin, { "branch", "-D", "gone" })
		commitInOrigin("fifth")
		local main = tip(work, "refs/remotes/origin/main")
		local r = fetch("checks", { "--prune", "-q", "origin" })
		t.expect(line({
			first = first.ok,
			ok = r.ok,
			said = has(r.stderr, "fence: a check tried to change refs in the real repository"),
			mainKept = tip(work, "refs/remotes/origin/main") == main,
			goneKept = tip(work, "refs/remotes/origin/gone") ~= ZERO,
		})).toBe(line({ first = true, ok = false, said = true, mainKept = true, goneKept = true }))
	end)

	it("AC2: a check.sh flow's fetch that writes a new tag is refused whole, and moves nothing", function()
		local sync = fetch("checks", { "--no-prune", "--no-tags", "-q", "origin" })
		commitInOrigin("sixth")
		fixture.git(origin, { "tag", "v1" })
		local main = tip(work, "refs/remotes/origin/main")
		local r = fetch("checks", { "-q", "origin" })
		t.expect(line({
			sync = sync.ok,
			ok = r.ok,
			said = has(r.stderr, "fence: a check tried to change refs in the real repository"),
			mainKept = tip(work, "refs/remotes/origin/main") == main,
			noTag = tip(work, "refs/tags/v1") == ZERO,
		})).toBe(line({ sync = true, ok = false, said = true, mainKept = true, noTag = true }))
	end)

	-- the tagOpt pin above makes the tag part of the fetch's own refspecs; a fetch by the origin's path ignores every
	-- remote.origin.* key and follows the tag the way a default fetch does (backfill), the path most sensitive to the git version
	it(
		"AC2: a check.sh flow's fetch that follows a new tag by default is refused whole, and moves nothing",
		function()
			local main = tip(work, "refs/remotes/origin/main")
			local r = fetch("checks", { "-q", origin, "+refs/heads/*:refs/remotes/origin/*" })
			t.expect(line({
				ok = r.ok,
				said = has(r.stderr, "fence: a check tried to change refs in the real repository"),
				mainKept = tip(work, "refs/remotes/origin/main") == main,
				noTag = tip(work, "refs/tags/v1") == ZERO,
			})).toBe(line({ ok = false, said = true, mainKept = true, noTag = true }))
		end
	)

	it("AC2: a check.sh flow still can't update a branch or remove the remote", function()
		local head = tip(work, "HEAD")
		local branch = fenced("checks", { "update-ref", "refs/heads/evil", "HEAD" })
		local before = tip(work, "refs/remotes/origin/main")
		local removed = fenced("checks", { "remote", "remove", "origin" })
		t.expect(line({
			branchOk = branch.ok,
			branchSaid = has(branch.stderr, "fence: a check tried to change refs in the real repository"),
			branchMade = tip(work, "refs/heads/evil") ~= ZERO,
			removedOk = removed.ok,
			removedSaid = has(removed.stderr, "fence: a check tried to change refs in the real repository"),
			trackingKept = tip(work, "refs/remotes/origin/main") == before and before ~= ZERO,
			headKept = tip(work, "HEAD") == head,
		})).toBe(line({
			branchOk = false,
			branchSaid = true,
			branchMade = false,
			removedOk = false,
			removedSaid = true,
			trackingKept = true,
			headKept = true,
		}))
	end)

	-- last before cleanup: it leaves a refspec in the clone's configuration
	it(
		"AC2: a remote whose own refspec writes outside refs/remotes/ is refused whole, flags or not",
		function()
			fixture.git(work, { "config", "--add", "remote.origin.fetch", "+refs/heads/*:refs/heads/up/*" })
			commitInOrigin("seventh")
			local main = tip(work, "refs/remotes/origin/main")
			local r = fenced(
				"checks",
				{ "fetch", "--atomic", "--no-prune", "--no-prune-tags", "--no-tags", "-q", "origin" }
			)
			t.expect(line({
				ok = r.ok,
				said = has(r.stderr, "fence: a check tried to change refs in the real repository"),
				mainKept = tip(work, "refs/remotes/origin/main") == main,
				noUp = tip(work, "refs/heads/up/main") == ZERO,
			})).toBe(line({ ok = false, said = true, mainKept = true, noUp = true }))
		end
	)

	it("cleans up", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		t.expect(fs.isDir(base)).toBe(false)
	end)
end)
