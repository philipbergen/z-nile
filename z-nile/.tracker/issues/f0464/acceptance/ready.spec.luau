--!strict
-- f0464 AC2, end to end: `./zn ready <issue>` on a fixture repository (real git, its own bare origin, under
-- .cache). A prepared normal ticket in no raft is readied in ONE tracker-only claim commit that adds its single raft
-- (single: true, no light: key) and moves the ticket beside it; under ZN_DISPATCH it is no longer refused as "not for
-- ./zn dispatch" (the dispatcher's approval rule applies: the fixture seals one) and --on stays refused there; outside the dispatcher
-- `ready <issue> --on <R>` builds it on the finished, unlanded raft that delivers its dependency, records `On: <R>`,
-- and `./zn work next` names that command.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local seal = require("@tests/lib/seal")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local R = "req" .. "uire"
local PREPARED = "prepared-quiet-copper-falcon"
local PROJECTS = table.concat({
	'retired = ["tracker"]',
	"",
	"[[project]]",
	'name = "pickman"',
	'root = "pickman/.tracker"',
	"",
	"[[project]]",
	'name = "z-nile"',
	'root = "z-nile/.tracker"',
	"",
}, "\n")
local ALPHA_SPEC = "--!strict\nlocal t = "
	.. R
	.. '("@tests/lib/t")\nreturn t.spec("alpha", function(it)\n\tit("computes alpha", function()\n\t\tt.expect(1).toBe(1)\n\tend)\nend)\n'
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
	.. 'check "AC2: alpha module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau" -a -f "$ZN_ROOT/pickman/tests/unit/alpha.spec.luau"\nfinish\n'
local APPROVED = "# Design review 001\n\n## Findings\n\nnone\n\n## Verdict\n\napprove\n"

local function has(text: string?, needle: string): boolean
	return string.find(text or "", needle, 1, true) ~= nil
end

local function write(dir: string, path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{dir}/{parent}`)
	end
	fs.writeFile(`{dir}/{path}`, text)
end

local function git(dir: string, args: { string }): string
	return fixture.git(dir, args)
end

local function ticket(id: string, risk: string, deps: string?): string
	return table.concat({
		"---",
		`id: {id}`,
		"type: chore",
		`title: {id} module`,
		`slug: {id}`,
		"raft: ",
		`depends_on: [{deps or ""}]`,
		"emergent: false",
		"design: ready",
		"created: 2026-11-28",
		`status: {PREPARED}`,
		`risk: {risk}`,
		"---",
		"",
		`# {id}: module`,
		"",
		"## Problem",
		"Alpha value is not computed.",
		"",
		"## Solution",
		"Add `pickman/src/alpha.luau` returning the alpha table.",
		"",
		"## Design",
		"Export `{ alpha = 1 }` from `pickman/src/alpha.luau`.",
		"",
		"### Short note",
		"- Problem: alpha is not computed",
		"- Change: export the alpha table",
		"- Files: `pickman/src/alpha.luau`",
		"- Test: `pickman/tests/unit/alpha.spec.luau`",
		"- Risk: none",
		"",
		"## Regression guard",
		"Overrides: none",
		"",
		"## Acceptance criteria",
		"- AC2: alpha module exists",
		"",
	}, "\n")
end

-- A fixture with its own bare origin: the tooling copied, tickets (each with its check.sh and an approved design
-- review) seeded and pushed, and a `gh` stub.
local function build(name: string, tickets: { [string]: string }): (trackerfix.Fixture, { [string]: string })
	local f = trackerfix.new(name, {
		[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
		["z-nile/projects.toml"] = PROJECTS,
		["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
		["pickman/src/untouched.luau"] = "--!strict\nreturn { untouched = true }\n",
		["pickman/tests/unit/unrun.spec.luau"] = ALPHA_SPEC,
		["pickman/tests/unit/unrun.watch.txt"] = "pickman/src/untouched.luau\n",
	})
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
		local parent = string.match(rel, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{f.main}/{parent}`)
		end
		process.exec("cp", { "-R", `{TOP}/{rel}`, `{f.main}/{rel}` })
	end
	for id, text in tickets do
		write(f.main, `pickman/.tracker/issues/{id}/{id}.md`, text)
		write(f.main, `pickman/.tracker/issues/{id}/check.sh`, CHECK)
		write(f.main, `pickman/.tracker/issues/{id}/design-review-001.md`, APPROVED)
	end
	seal.stamp(f.main, name)
	git(f.main, { "add", "-A" })
	git(f.main, { "commit", "-qm", "prep tickets" })
	git(f.main, { "push", "-q", "origin", "HEAD:main" })
	local bin = `{f.base}/bin`
	fs.writeDir(bin)
	fs.writeFile(
		`{bin}/gh`,
		'#!/bin/sh\ncase "$1 $2" in\n'
			.. '  "pr list") echo 1; exit 0 ;;\n'
			.. '  "pr create") echo https://github.com/x/y/pull/1; exit 0 ;;\n'
			.. '  "pr view") echo main; exit 0 ;;\n'
			.. '  "pr edit") exit 0 ;;\n'
			.. "esac\nexit 0\n"
	)
	process.exec("chmod", { "+x", `{bin}/gh` })
	return f, { PATH = `{bin}:{process.env.PATH or ""}`, PICKMAN_DONE_GATE = "1" }
end

local function zn(
	f: trackerfix.Fixture,
	dir: string,
	env: { [string]: string },
	args: { string }
): fixture.Result
	local use = if args[1] == "finish" then env else { PATH = env.PATH }
	return trackerfix.tr(f, dir, args, use)
end

local function ok(f: trackerfix.Fixture, dir: string, env: { [string]: string }, args: { string }): string
	local r = zn(f, dir, env, args)
	if not r.ok then
		error(`./zn {table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- the newest ready commit for `id` on origin/main: its sha and message
local function readyCommit(f: trackerfix.Fixture, id: string): (string, string, string)
	git(f.main, { "fetch", "-q", "origin" })
	local log = git(f.main, { "log", "--format=%H %s", "origin/main" })
	local sha, rid = string.match(log, `(%x+) tracker: ready (R%d+) {id}`)
	assert(sha and rid, `no ready commit for {id}:\n{log}`)
	return sha :: string, rid :: string, git(f.main, { "log", "-1", "--format=%B", sha :: string })
end

return t.spec("f0464 ready <issue> readies a ticket alone, end to end", function(it)
	it(
		"AC2: a normal ticket in no raft is readied in one claim commit with a single raft that is not light",
		function()
			local f, env = build("f0464-ready-normal-github.com", { c0010 = ticket("c0010", "normal") })
			local said = ok(f, f.main, env, { "ready", "c0010" })
			t.expect(has(said, "readied R")).toBe(true)
			local sha, rid, body = readyCommit(f, "c0010")
			local files = git(f.main, { "show", "--name-status", "--format=", sha })
			t.expect(has(files, `A\tpickman/.tracker/rafts/active/{rid}/{rid}.md`)).toBe(true)
			t.expect(has(files, `A\tpickman/.tracker/rafts/active/{rid}/check.sh`)).toBe(true)
			t.expect(has(files, "pickman/.tracker/issues/active/c0010/c0010.md")).toBe(true)
			for line in string.gmatch(files, "[^\n]+") do
				t.expect(has(line, ".tracker/") or has(line, "z-nile/next")).toBe(true)
			end
			t.expect(has(body, "Lands: approved")).toBe(true)
			t.expect(has(body, "Light: true")).toBe(false)
			t.expect(has(body, "On: ")).toBe(false)
			local raftDoc = git(f.main, { "show", `{sha}:pickman/.tracker/rafts/active/{rid}/{rid}.md` })
			t.expect(has(raftDoc, "single: true")).toBe(true)
			t.expect(has(raftDoc, "issues: [c0010]")).toBe(true)
			t.expect(has(raftDoc, "\nlight:")).toBe(false)
			-- the Theme of a raft that is not light: words only that text has, and not the light text's
			t.expect(has(raftDoc, "built and reviewed as any raft")).toBe(true)
			t.expect(has(raftDoc, "no separate code review")).toBe(false)
			local issueDoc = git(f.main, { "show", `{sha}:pickman/.tracker/issues/active/c0010/c0010.md` })
			t.expect(has(issueDoc, `raft: {rid}`)).toBe(true)
			-- asking again regenerates the prompt and publishes nothing
			local tip = git(f.main, { "rev-parse", "origin/main" })
			t.expect(has(ok(f, f.main, env, { "ready", rid }), "regenerated")).toBe(true)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(tip)
		end
	)

	it(
		"AC2: under ./zn dispatch ready <issue> readies a ticket whose approval holds, and --on stays refused",
		function()
			-- the fixture seals an approval for every item (tests/lib/seal), so the dispatcher's approval rule holds
			local f, env = build("f0464-ready-dispatch-github.com", { c0020 = ticket("c0020", "risky") })
			local denv = { PATH = env.PATH, ZN_DISPATCH = "1" }
			local before = git(f.main, { "rev-parse", "origin/main" })
			local on = trackerfix.tr(f, f.main, { "ready", "c0020", "--on", "R0001" }, denv)
			t.expect(on.ok).toBe(false)
			t.expect(has(on.stderr, "--on is not for ./zn dispatch")).toBe(true)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
			local r = trackerfix.tr(f, f.main, { "ready", "c0020" }, denv)
			t.expect(has(r.stderr, "not for ./zn dispatch")).toBe(false)
			t.expect(has(r.stderr, "takes no --on")).toBe(false)
			t.expect(r.ok).toBe(true)
			local sha, rid, body = readyCommit(f, "c0020")
			-- readied by the dispatcher: no Lands: approved (approval was asked at ready), not light
			t.expect(has(body, "Lands: approved")).toBe(false)
			t.expect(has(body, "Light: true")).toBe(false)
			local raftDoc = git(f.main, { "show", `{sha}:pickman/.tracker/rafts/active/{rid}/{rid}.md` })
			t.expect(has(raftDoc, "single: true")).toBe(true)
			t.expect(has(raftDoc, "\nlight:")).toBe(false)
		end
	)

	it(
		"AC2: ready <issue> --on <R> builds a ticket on the finished raft that delivers its dependency",
		function()
			local f, env = build("f0464-ready-on-github.com", {
				c0030 = ticket("c0030", "easy"),
				c0031 = ticket("c0031", "normal", "c0030"),
				c0032 = ticket("c0032", "easy"),
			})
			-- c0032 is readied alone and never started: an active raft that holds nothing c0031 depends on
			local other = string.match(ok(f, f.main, env, { "ready", "c0032" }), "readied (R%d+)") :: string
			-- c0030 is readied, started and its layer finished (it has not landed)
			local said = ok(f, f.main, env, { "ready", "c0030" })
			local base = string.match(said, "readied (R%d+)") :: string
			local wt = ok(f, f.main, env, { "worktree", base })
			ok(f, wt, env, { "start", base })
			write(
				wt,
				`pickman/.tracker/rafts/active/{base}/check.sh`,
				'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"\n'
					.. `check "RC0: the module exists" test -f "$ZN_ROOT/pickman/src/alpha.luau"\nfinish\n`
			)
			-- started, its layer not finished: --on it is refused, and so is --on a raft that delivers nothing it
			-- depends on; nothing is published
			local early = git(f.main, { "rev-parse", "origin/main" })
			local unfinished = zn(f, f.main, env, { "ready", "c0031", "--on", base })
			t.expect(unfinished.ok).toBe(false)
			t.expect(has(unfinished.stderr, "layer for c0030 is not finished")).toBe(true)
			local unrelated = zn(f, f.main, env, { "ready", "c0031", "--on", other })
			t.expect(unrelated.ok).toBe(false)
			t.expect(has(unrelated.stderr, "nothing in c0031 depends on " .. other)).toBe(true)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(early)
			write(wt, "pickman/src/alpha.luau", "--!strict\nreturn { alpha = 1 }\n")
			write(wt, "pickman/tests/unit/alpha.spec.luau", ALPHA_SPEC)
			git(wt, { "add", "-A" })
			git(wt, { "commit", "-qm", "c0030 implementation" })
			ok(f, wt, env, { "finish", "c0030" })
			-- without --on it is refused, naming the dependency; nothing is published
			local before = git(f.main, { "rev-parse", "origin/main" })
			local plain = zn(f, f.main, env, { "ready", "c0031" })
			t.expect(plain.ok).toBe(false)
			t.expect(has(plain.stderr, "c0031 depends on c0030")).toBe(true)
			-- --on a raft that delivers nothing it depends on is still refused once c0030 is finished
			local stray = zn(f, f.main, env, { "ready", "c0031", "--on", other })
			t.expect(stray.ok).toBe(false)
			t.expect(has(stray.stderr, "nothing in c0031 depends on " .. other)).toBe(true)
			git(f.main, { "fetch", "-q", "origin" })
			t.expect(git(f.main, { "rev-parse", "origin/main" })).toBe(before)
			-- work next names the command
			local asked = ok(f, f.main, env, { "work", "next", "c0031", "--one" })
			t.expect(has(asked, `./zn ready c0031 --on {base}`)).toBe(true)
			-- and it readies it, recording On: <base>; the single raft is not light
			ok(f, f.main, env, { "ready", "c0031", "--on", base })
			local sha, rid, body = readyCommit(f, "c0031")
			t.expect(rid ~= base).toBe(true)
			t.expect(has(body, `On: {base}`)).toBe(true)
			t.expect(has(body, "Light: true")).toBe(false)
			local raftDoc = git(f.main, { "show", `{sha}:pickman/.tracker/rafts/active/{rid}/{rid}.md` })
			t.expect(has(raftDoc, "\nlight:")).toBe(false)
			t.expect(has(raftDoc, "issues: [c0031]")).toBe(true)
		end
	)
end)
