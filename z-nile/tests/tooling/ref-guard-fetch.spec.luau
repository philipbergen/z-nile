--!strict
-- R0068 review-001 F1 (c0122): the ref guard's `--affected` selector. c0122's end-to-end specs (`fetch`, `refuse`)
-- watch only the files their layer changed, so a change to the hook itself selected neither of them. This spec has
-- its own watch (`ref-guard-fetch.watch.txt`) naming the hook and fence.sh, so a change to either runs it before a
-- merge. It drives the guard through real git, as c0122's specs do: a fixture origin and its clone under this
-- home's .cache, the clone fenced by z-nile/lib/fence.sh in one bash process with PICKMAN_FENCE_SPECS unset (a
-- check.sh flow, as ac.sh leaves it) or 1 (a spec run), set for that process only. Nothing outside .cache is
-- touched. The full pair (c0122's `fetch` and `refuse`) still runs in the full gate.
local clone = require("@tests/lib/clone")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

local root = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
local base = `{trim(process.exec("pwd", { "-P" }).stdout)}/.cache/ref-guard-fetch`
local origin = `{base}/origin`
local work = `{base}/clone`
local runner = `{base}/fenced.sh`
local FENCE = `{root}/z-nile/lib/fence.sh`
local ZERO = string.rep("0", 40)
local REFUSED = "fence: a check tried to change refs in the real repository"

local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

-- `mode` sets the marker inside the script whatever this run has set: `checks` unsets it, `specs` exports 1.
local function fenced(mode: string, args: { string }): fixture.Result
	local argv = { runner, FENCE, work, mode }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(work, "bash", argv)
end

-- The host's git configuration never decides a case: the fetch settings the result depends on are set with -c.
local function fetch(mode: string): fixture.Result
	return fenced(mode, {
		"-c",
		"fetch.prune=false",
		"-c",
		"fetch.pruneTags=false",
		"-c",
		"remote.origin.prune=false",
		"-c",
		"remote.origin.pruneTags=false",
		"-c",
		"remote.origin.tagOpt=--no-tags",
		"fetch",
		"--atomic",
		"-q",
		"origin",
	})
end

local function tip(dir: string, ref: string): string
	local r = fixture.exec(dir, "git", { "rev-parse", "--verify", "-q", ref })
	return if r.ok then trim(r.stdout) else ZERO
end

return t.spec(
	"the ref guard's selector: a change to the hook or fence.sh runs a real fetch through it",
	function(it)
		it("sets up a fixture origin and a fenced clone of it", function()
			if fs.isDir(base) then
				fs.removeDir(base)
			end
			fs.writeDir(base)
			t.expect(process.exec("git", { "init", "-q", "-b", "main", origin }).ok).toBe(true)
			fixture.git(origin, {
				"-c",
				"user.name=ref-guard-fetch",
				"-c",
				"user.email=ref-guard-fetch@example.invalid",
				"commit",
				"-q",
				"--allow-empty",
				"-m",
				"first",
			})
			clone.isolated(origin, work)
			fs.writeFile(
				runner,
				table.concat({
					"#!/usr/bin/env bash",
					'source "$1" || exit 90',
					'case "$3" in',
					"checks) unset PICKMAN_FENCE_SPECS ;;",
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

		it("a check.sh flow's fetch with nothing new succeeds", function()
			local before = tip(work, "refs/remotes/origin/main")
			local r = fetch("checks")
			t.expect(`ok={tostring(r.ok)} refused={tostring(has(r.stderr, REFUSED))}`)
				.toBe("ok=true refused=false")
			t.expect(tip(work, "refs/remotes/origin/main")).toBe(before)
		end)

		it("a spec run's fetch with nothing new is refused with the guard's message", function()
			local before = tip(work, "refs/remotes/origin/main")
			local r = fetch("specs")
			t.expect(`ok={tostring(r.ok)} refused={tostring(has(r.stderr, REFUSED))}`)
				.toBe("ok=false refused=true")
			t.expect(tip(work, "refs/remotes/origin/main")).toBe(before)
		end)

		it("a check.sh flow still can't create a branch", function()
			local r = fenced("checks", { "update-ref", "refs/heads/evil", "HEAD" })
			t.expect(`ok={tostring(r.ok)} refused={tostring(has(r.stderr, REFUSED))}`)
				.toBe("ok=false refused=true")
			t.expect(tip(work, "refs/heads/evil")).toBe(ZERO)
		end)
	end
)
