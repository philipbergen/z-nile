--!strict
-- f0423 AC3 to AC7 and the safety property of amendment 4, through the real `./zn` in a fixture (the fixture approve-walk):
-- the queue of a raft and of the stack under it, the rulings a session may write, the y/N that alone records, the
-- refusals (no terminal, ZN_DISPATCH, ZN_APPROVE_SESSION, a changed design), and the launch of the CLI with a stub
-- `claude` first on PATH. `script` is the person's terminal; the spec process itself has none. What is not exercised
-- here: a real CLI taking the terminal.
local agentenv = require("@znile/engine/agentenv")
local approverun = require("@znile/engine/approverun")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = "z-nile/.tracker"
local CACHE = ".cache" -- joined to a folder name below, so this file names no fixture directory of its own
local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local GUESS = "G1 (design, 2026-11-16): which way. Chose: the first. Why: it is simpler."

-- a person's terminal: the agent markers and session ids cleared (zz-test lesson terminal-fixtures-clear-the-agent-session)
local TERMINAL: { [string]: string } = {
	ZN_DISPATCH = "",
	ZN_APPROVE_SESSION = "",
	ZN_APPROVE_RUN = "",
	ZN_HEADLESS = "",
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

-- the environment of a person's shell: every agent marker cleared, then `extra`
local function cleared(extra: { [string]: string }): { [string]: string }
	local env: { [string]: string } = {}
	for _, name in agentenv.MARKERS do
		env[name] = ""
	end
	for k, v in extra do
		env[k] = v
	end
	return env
end

local function checkText(id: string): string
	return HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{id}/check.sh\n` .. "finish\n"
end

local function doc(id: string, design: string, raft: string, depends: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: Title of {id}\nslug: slug-{id}\nraft: {raft}\ndepends_on: {depends}\nemergent: false\ndesign: {design}\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Problem\nThe gate cannot see {id}.\n\n## Solution\nRecord a hash for {id}.\n\n## Design\nHash the contract of {id}.{extra or ""}\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover it.\n`
end

local function raftDoc(id: string, members: string, order: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: Raft {id}\nslug: raft-{id}\nsingle: false\nissues: [{members}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Theme\nThe contract stays put.\n{if order
		then "\n## Order & dependencies\n" .. order .. "\n"
		else ""}`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("approve: the walkthrough forms", function(it)
	local f: trackerfix.Fixture
	local run = "" -- the run of the stack R0002

	local function say(r: fixture.Result): string
		return r.stderr .. r.stdout
	end

	-- the facts the app reads go to a throwaway state folder of the fixture, as the fence requires (f0437 review 4)
	local function stateDir(): string
		return `{f.base}/livestate`
	end
	local function zn(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
		local merged: { [string]: string } = if env then table.clone(env) else {}
		if merged.ZN_LIVE_DIR == nil then
			merged.ZN_LIVE_DIR = stateDir()
		end
		return fixture.exec(cwd, "./zn", args, { env = merged })
	end

	-- `./zn <line>` on a terminal (script), with `answer` typed again and again as every answer the person gives (an
	-- endless `yes`, as approve.spec does: a short script's first keys are lost to the terminal's own mode changes);
	-- PATH has the stubs first
	local function onTerminal(
		cwd: string,
		line: string,
		answer: string,
		env: { [string]: string }?
	): fixture.Result
		local merged = table.clone(TERMINAL)
		merged.PATH = `{f.base}/stubs:{process.env.PATH or ""}`
		merged.HOME = process.env.HOME or ""
		if env then
			for k, v in env do
				merged[k] = v
			end
		end
		local cmd = `yes '{answer}' | script -q /dev/null sh -c './zn {line}; echo "zn-exit=$?"'`
		local r = fixture.exec(cwd, "sh", { "-c", cmd }, { env = merged })
		local code = string.match(r.stdout, "zn%-exit=(%d+)")
		return { ok = code == "0", code = tonumber(code or "1") or 1, stdout = r.stdout, stderr = r.stderr }
	end

	local function publish(message: string)
		fixture.git(f.main, { "add", "-A" })
		fixture.git(f.main, { "commit", "-q", "-m", message })
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
	end

	-- every file of the checkout that is not git's or the ignored .cache, with its text
	local function tracked(): { string }
		local out: { string } = {}
		local function walk(path: string, rel: string)
			for _, name in fs.readDir(path) do
				if name ~= ".git" and name ~= ".cache" and name ~= ".worktree" then
					local full = `{path}/{name}`
					if fs.isDir(full) then
						walk(full, `{rel}{name}/`)
					else
						table.insert(out, `{rel}{name}={fs.readFile(full)}`)
					end
				end
			end
		end
		walk(f.main, "")
		table.sort(out)
		return out
	end

	local function runDir(id: string): string
		return `{f.main}/{CACHE}/approve/{id}`
	end

	local function runOf(r: fixture.Result): string
		return string.match(r.stdout, "approval run (%S+):") or ""
	end

	it("sets up two stacked rafts, a raftless ticket and a draft", function()
		local seed: { [string]: string } = {}
		local function issue(id: string, design: string, raft: string, depends: string)
			seed[`{ROOT}/issues/{id}/{id}.md`] = doc(id, design, raft, depends)
			seed[`{ROOT}/issues/{id}/check.sh`] = checkText(id)
		end
		issue("c0004", "draft", "R0003", "[]")
		issue("c0005", "draft", "R0003", "[c0004]")
		issue("c0001", "draft", "R0002", "[c0005]")
		issue("c0006", "draft", "", "[]")
		issue("c0007", "draft", "", "[]")
		issue("c0008", "draft", "R0001", "[]")
		seed[`{ROOT}/rafts/R0003/R0003.md`] = raftDoc("R0003", "c0004, c0005")
		seed[`{ROOT}/rafts/R0003/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n'
		seed[`{ROOT}/rafts/R0002/R0002.md`] = raftDoc("R0002", "c0001")
		seed[`{ROOT}/rafts/R0002/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n'
		-- a raft whose Order section names a ticket that is not a member (the real tracker has such a raft)
		seed[`{ROOT}/rafts/R0001/R0001.md`] = raftDoc("R0001", "c0008", "1. c0099 first")
		seed[`{ROOT}/rafts/R0001/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n'
		-- the role the walk form starts (the repository's own .models.toml is checked in the last case)
		seed[".models.toml"] =
			'[roles.approve]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 4\nmax_tokens = 3000000\n'
		f = trackerfix.new("approve-walk", seed)
		-- c0004 to c0001 hold guesses and are ready; c0006 is ready with none; c0007 stays a draft
		for _, id in { "c0004", "c0005", "c0001", "c0006", "c0008" } do
			local raft = if id == "c0001"
				then "R0002"
				elseif id == "c0006" then ""
				elseif id == "c0008" then "R0001"
				else "R0003"
			local depends = if id == "c0005" then "[c0004]" elseif id == "c0001" then "[c0005]" else "[]"
			fs.writeFile(
				`{f.main}/{ROOT}/issues/{id}/{id}.md`,
				doc(id, "ready", raft, depends, if id == "c0006" then nil else " Guess (prep) G1: a choice.")
			)
			if id ~= "c0006" then
				fs.writeFile(`{f.main}/{ROOT}/issues/{id}/guesses.md`, `# guesses\n- {GUESS}\n`)
			end
		end
		publish("designs ready")
		fs.writeDir(`{f.base}/stubs`)
	end)

	it(
		"--queue writes the run for a raft and the stack under it, bottom first, and nothing outside the run folder",
		function()
			local before = tracked()
			local heads = fixture.git(f.main, { "ls-remote", "origin" })
			local trees = fixture.git(f.main, { "worktree", "list" })
			local r = zn(f.main, { "approve", "R0002", "--queue" })
			t.expect(r.ok).toBe(true)
			run = runOf(r)
			t.expect(string.match(run, "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%x%x%x%x$") ~= nil).toBe(true)
			t.expect(has(r.stdout, "3 waiting for the owner, 0 still being worked")).toBe(true)
			local a, b, c =
				string.find(r.stdout, "1. c0004", 1, true),
				string.find(r.stdout, "2. c0005", 1, true),
				string.find(r.stdout, "3. c0001", 1, true)
			t.expect(a ~= nil and b ~= nil and c ~= nil).toBe(true)
			t.expect(has(r.stdout, "no approval (1 guesses)")).toBe(true)
			-- queue.tsv: id, place, hash and verdict of each; brief.md: the guesses verbatim and the doc path
			local queue = fs.readFile(`{runDir(run)}/queue.tsv`)
			t.expect(has(queue, "c0004\torigin/main\t")).toBe(true)
			t.expect(has(queue, "c0006")).toBe(false)
			t.expect(has(queue, "c0007")).toBe(false)
			local brief = fs.readFile(`{runDir(run)}/brief.md`)
			t.expect(has(brief, GUESS)).toBe(true)
			t.expect(has(brief, `{ROOT}/issues/c0001/c0001.md`)).toBe(true)
			t.expect(has(brief, "Guess (prep) G1: a choice.")).toBe(true)
			t.expect(select("#", string.find(queue, "[%x]+", 1))).toBe(2)
			-- nothing outside the run's folder changed: no tracked file, no ref, no worktree
			t.expect(tracked()).toEqual(before)
			t.expect(fixture.git(f.main, { "ls-remote", "origin" })).toBe(heads)
			t.expect(fixture.git(f.main, { "worktree", "list" })).toBe(trees)
			t.expect(fixture.git(f.main, { "status", "--porcelain" })).toBe("")
		end
	)

	it(
		"--queue also writes the facts the app's Approvals view reads, bottom of the stack first (f0437)",
		function()
			local facts = fs.readFile(`{stateDir()}/approvals.json`)
			local decoded = serde.decode("json" :: "json", facts)
			t.expect(decoded.version).toBe(1)
			t.expect(decoded.run).toBe(run)
			local order: { string } = {}
			for _, th in decoded.themes do
				for _, raft in th.rafts do
					for _, tk in raft.tickets do
						table.insert(order, tk.id)
					end
				end
			end
			t.expect(order).toEqual({ "c0004", "c0005", "c0001" })
			local first = decoded.themes[1].rafts[1].tickets[1]
			t.expect(first.idea.problem).toBe("The gate cannot see c0004.")
			t.expect(first.guesses[1].chose).toBe("the first.")
			t.expect(first.design[1].heading).toBe("Design")
			t.expect(decoded.themes[1].id).toBe("unsorted")
			-- the scope of the queue, and the contract hash of the queue row the ruling and --apply are bound to
			t.expect(decoded.scope).toBe("R0002")
			local queueRows = fs.readFile(`{runDir(run)}/queue.tsv`)
			t.expect(has(queueRows, `c0004\torigin/main\t{first.hash}\t`)).toBe(true)
			t.expect(#first.hash >= 32).toBe(true)
			-- nothing in the facts is a path of this machine
			t.expect(has(facts, f.main)).toBe(false)
		end
	)

	it(
		"a fenced run (the live layer off) without ZN_LIVE_DIR writes no facts, and a scoped queue says its scope (f0437 review 3, 4)",
		function()
			local fenced = { ZN_LIVE = "off", ZN_LIVE_DIR = "" }
			fs.removeFile(`{stateDir()}/approvals.json`)
			local r = zn(f.main, { "approve", "R0002", "--queue" }, fenced)
			t.expect(r.ok).toBe(true)
			t.expect(fs.isFile(`{f.main}/{CACHE}/live/approvals.json`)).toBe(false)
			t.expect(fs.isFile(`{stateDir()}/approvals.json`)).toBe(false)
			-- a cleared ticket's scoped queue is an empty facts file that names its scope
			local clear = zn(f.main, { "approve", "--walk", "c0006", "--queue" })
			t.expect(clear.ok).toBe(true)
			local decoded = serde.decode("json" :: "json", fs.readFile(`{stateDir()}/approvals.json`))
			t.expect(decoded.scope).toBe("c0006")
			t.expect(#decoded.themes).toBe(0)
		end
	)

	it(
		"a checkout behind origin/main is refused, and after a sync the brief carries the new guess",
		function()
			-- a guess is added on origin/main by another clone; this checkout has not pulled it
			local other = f.other
			fixture.git(other, { "pull", "-q", "--ff-only", "origin", "main" })
			fs.writeFile(
				`{other}/{ROOT}/issues/c0001/guesses.md`,
				`# guesses\n- {GUESS}\n- G2 (design, 2026-11-17): a later question. Chose: the second way. Why: it was newer.\n`
			)
			fixture.git(other, { "add", "-A" })
			fixture.git(other, { "commit", "-q", "-m", "a guess the owner never saw" })
			fixture.git(other, { "push", "-q", "origin", "HEAD:main" })
			local refused = zn(f.main, { "approve", "R0002", "--queue" })
			t.expect(refused.ok).toBe(false)
			t.expect(
				has(
					say(refused),
					"c0001: this checkout's copy differs from origin/main: run ./zn sync, or walk from origin/main"
				)
			).toBe(true)
			fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			local synced = zn(f.main, { "approve", "R0002", "--queue" })
			t.expect(synced.ok).toBe(true)
			local brief = fs.readFile(`{runDir(runOf(synced))}/brief.md`)
			t.expect(has(brief, "G2 (design, 2026-11-17): a later question. Chose: the second way."))
				.toBe(true)
			-- the brief is self-contained: the text and the revision it was read from
			t.expect(has(brief, "The gate cannot see c0001.")).toBe(true)
			t.expect(has(brief, "Record a hash for c0001.")).toBe(true)
			t.expect(string.match(brief, "read from: origin/main at %x+;") ~= nil).toBe(true)
		end
	)

	it(
		"a local contract that cannot be built is named; a prep worktree's place gets only 'walk from'",
		function()
			local guessesFile = `{f.main}/{ROOT}/issues/c0005/guesses.md`
			local good = fs.readFile(guessesFile)
			fs.writeFile(guessesFile, "this is not a guesses file\n")
			local broken = zn(f.main, { "approve", "R0003", "--queue" })
			fs.writeFile(guessesFile, good)
			t.expect(broken.ok).toBe(false)
			t.expect(has(say(broken), "c0005: this checkout's copy of the contract cannot be built: "))
				.toBe(true)
			t.expect(has(say(broken), "differs from")).toBe(false)
			-- a design of its own in a prep worktree: the way out is that worktree, not a sync
			local prep = `{f.main}/.worktree/p5`
			fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-slug-c0005", prep, "HEAD" })
			local doc5 = fs.readFile(`{prep}/{ROOT}/issues/c0005/c0005.md`)
			fs.writeFile(
				`{prep}/{ROOT}/issues/c0005/c0005.md`,
				(
					string.gsub(
						doc5,
						"Hash the contract of c0005.",
						"Hash the contract of c0005, in a prep branch.",
						1
					)
				)
			)
			fixture.git(prep, { "add", "-A" })
			fixture.git(prep, { "commit", "-q", "-m", "a design of its own" })
			local viaPrep = zn(f.main, { "approve", "R0003", "--queue" })
			fixture.git(f.main, { "worktree", "remove", "--force", prep })
			fixture.git(f.main, { "branch", "-q", "-D", "prep-slug-c0005" })
			t.expect(viaPrep.ok).toBe(false)
			t.expect(
				has(
					say(viaPrep),
					"c0005: this checkout's copy differs from .worktree/p5: walk from .worktree/p5"
				)
			).toBe(true)
			t.expect(has(say(viaPrep), "./zn sync")).toBe(false)
		end
	)

	it(
		"a raft alone lists its own tickets; --walk lists one; no scope lists the project, with the draft still being worked",
		function()
			local own = zn(f.main, { "approve", "R0003", "--queue" })
			t.expect(own.ok).toBe(true)
			t.expect(has(own.stdout, "2 waiting for the owner, 0 still being worked")).toBe(true)
			t.expect(has(own.stdout, "c0001")).toBe(false)
			local one = zn(f.main, { "approve", "--walk", "c0005", "--queue" })
			t.expect(has(one.stdout, "1 waiting for the owner")).toBe(true)
			t.expect(has(one.stdout, "c0004")).toBe(false)
			local all = zn(f.main, { "approve", "--queue" })
			t.expect(all.ok).toBe(true)
			t.expect(has(all.stdout, "4 waiting for the owner, 1 still being worked")).toBe(true)
			local brief = fs.readFile(`{runDir(runOf(all))}/brief.md`)
			-- an undesigned capture is one line, not listed by itself
			t.expect(has(brief, "1 tickets are still being designed")).toBe(true)
			t.expect(has(brief, "c0007")).toBe(false)
			-- a raft whose Order is inconsistent does not stop the command: it is named in the brief
			t.expect(
				has(
					brief,
					"Note: R0001's Order section is inconsistent (c0099 is in R0001's Order and is not a member)"
				)
			).toBe(true)
			t.expect(has(brief, "c0008: Title of c0008")).toBe(true)
			t.expect(has(brief, "rework history")).toBe(false)
			-- a ticket that does not wait is no run
			local clear = zn(f.main, { "approve", "--walk", "c0006", "--queue" })
			t.expect(has(clear.stdout, "nothing waits for approval in c0006")).toBe(true)
			-- the other forms are refused with the way out
			local tributary = zn(f.main, { "approve", "north", "--queue" })
			t.expect(tributary.ok).toBe(false)
			t.expect(has(say(tributary), "north is not a raft or a ticket")).toBe(true)
			local bare = zn(f.main, { "approve", "c0004", "--queue" })
			t.expect(bare.ok).toBe(false)
			t.expect(has(say(bare), "c0004 is a ticket: use ./zn approve --walk c0004 [--queue]")).toBe(true)
		end
	)

	it("--ruling writes one row with no terminal, only into the run's rulings.tsv", function()
		local before = tracked()
		local r = zn(f.main, { "approve", "--ruling", run, "c0004", "approve" })
		t.expect(r.ok).toBe(true)
		t.expect(
			has(
				r.stdout,
				`ruling written for c0004 in {run}: approve. Nothing is recorded until the person runs ./zn approve --apply {run}.`
			)
		).toBe(true)
		t.expect(has(fs.readFile(`{runDir(run)}/rulings.tsv`), "c0004\t-\tapprove")).toBe(true)
		t.expect(tracked()).toEqual(before)
		local again = zn(f.main, { "approve", "--ruling", run, "c0004", "approve" })
		t.expect(again.ok).toBe(false)
		t.expect(has(say(again), "c0004 already has a ruling in this run")).toBe(true)
		local outside = zn(f.main, { "approve", "--ruling", run, "c0006", "approve" })
		t.expect(has(say(outside), "c0006 is not in this run's queue")).toBe(true)
		local noAsk = zn(f.main, {
			"approve",
			"--ruling",
			run,
			"c0005",
			"change",
			"--stage",
			"design",
			"--note",
			"no",
			"--lesson",
			"rule",
			"--ask",
			"no question",
		})
		t.expect(has(say(noAsk), "must be a question")).toBe(true)
		-- under the dispatcher a ruling is refused
		local dispatched = zn(
			f.main,
			{ "approve", "--ruling", run, "c0005", "approve" },
			{ ZN_DISPATCH = "1", PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
		)
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(say(dispatched), `{run}: --ruling is refused while ZN_DISPATCH is set`)).toBe(true)
		-- the session itself may write it
		local session = zn(f.main, {
			"approve",
			"--ruling",
			run,
			"c0005",
			"change",
			"--stage",
			"design",
			"--guess",
			"G1",
			"--note",
			"keep the old way",
		}, { ZN_APPROVE_SESSION = run, PATH = process.env.PATH or "", HOME = process.env.HOME or "" })
		t.expect(session.ok).toBe(true)
		-- a traversing run or ticket id writes nothing anywhere
		local settled = tracked()
		for _, bad in { "../../x", `{run}/..`, "/etc/passwd" } do
			local refused = zn(f.main, { "approve", "--ruling", bad, "c0001", "approve" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "is not a run id")).toBe(true)
		end
		local ticket = zn(f.main, { "approve", "--ruling", run, "../../c0001", "approve" })
		t.expect(ticket.ok).toBe(false)
		t.expect(has(say(ticket), "is not a ticket id")).toBe(true)
		t.expect(tracked()).toEqual(settled)
		t.expect(fs.isDir(`{f.main}/{CACHE}/x`)).toBe(false)
	end)

	it(
		"every recording form is refused without a terminal, under ZN_DISPATCH and inside a session, with the way out",
		function()
			local clean = { PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
			-- no terminal (a pipe): the wrapper's stdin test
			local walk = zn(f.main, { "approve", "R0003" }, clean)
			t.expect(say(walk)).toBe(
				"R0003: approve is refused without a terminal on stdin. Run ./zn approve R0003 yourself, in a terminal.\n"
			)
			local apply = zn(f.main, { "approve", "--apply", run }, clean)
			t.expect(say(apply)).toBe(
				`approve is refused without a terminal on stdin. Run ./zn approve --apply {run} yourself, in a terminal.\n`
			)
			t.expect(say(zn(f.main, { "approve" }, clean)))
				.toBe(
					"approve is refused without a terminal on stdin. Run ./zn approve yourself, in a terminal.\n"
				)
			local bare = zn(f.main, { "approve", "c0004" }, clean)
			t.expect(has(say(bare), "c0004: approve is refused without a terminal on stdin")).toBe(true)
			local republish = zn(f.main, { "approve", "c0004", "--publish" }, clean)
			t.expect(has(say(republish), "approve is refused without a terminal on stdin")).toBe(true)
			-- no terminal, past the wrapper: the engine's own /dev/tty test (setsid drops the controlling terminal)
			local detached = fixture.exec(f.main, "perl", {
				"-e",
				"use POSIX; POSIX::setsid(); exec @ARGV",
				"lune",
				"run",
				"z-nile/engine/main",
				"--",
				"approve",
				"--apply",
				run,
			}, {
				env = cleared({ ZN_TOP = f.main, ZN_CWD = "", ZN_DISPATCH = "", ZN_APPROVE_SESSION = "" }),
			})
			t.expect(say(detached)).toBe(
				`{run}: approve is refused without a terminal on stdin. Run ./zn approve --apply {run} yourself, in a terminal.\n`
			)
			t.expect(detached.ok).toBe(false)
			-- ZN_DISPATCH, on a terminal
			for _, line in
				{
					"approve R0003",
					`approve --apply {run}`,
					"approve --walk c0004",
					"approve c0004",
					"approve c0004 --publish",
				}
			do
				local r = onTerminal(f.main, line, "y", { ZN_DISPATCH = "1" })
				t.expect(r.ok).toBe(false)
				t.expect(
					has(r.stdout .. r.stderr, "approve is refused while ZN_DISPATCH is set. Run ./zn approve")
				)
					.toBe(true)
			end
			-- a walkthrough session, on a terminal (an agent's shell that has a terminal): no form records or walks
			for _, line in
				{
					"approve R0003",
					`approve --apply {run}`,
					"approve --walk c0004",
					"approve c0004",
					"approve c0004 --publish",
				}
			do
				local r = onTerminal(f.main, line, "y", { ZN_APPROVE_SESSION = run })
				t.expect(r.ok).toBe(false)
				t.expect(
					has(
						r.stdout .. r.stderr,
						`approve is refused inside a walkthrough session (ZN_APPROVE_SESSION is set): an agent never records an approval. Write rulings with ./zn approve --ruling, then ask the person to run ./zn approve --apply {run} in a terminal.`
					)
				).toBe(true)
			end
			-- an agent marker in the environment refuses every recording form, on a terminal, whatever the wrapper does
			for _, marker in agentenv.MARKERS do
				for _, line in { "approve R0003", "approve c0004", "approve --walk c0004" } do
					local r = onTerminal(f.main, line, "y", { [marker] = "1" })
					t.expect(r.ok).toBe(false)
					t.expect(
						has(
							r.stdout .. r.stderr,
							`approve is refused inside an agent session ({marker} is set): only the person records an approval, in their own terminal. If this is your own terminal, open a new one that no agent CLI started.`
						)
					).toBe(true)
				end
			end
			local markedApply =
				onTerminal(f.main, `approve --apply {run}`, "y", { CLAUDE_CODE_SESSION_ID = "abc" })
			t.expect(markedApply.ok).toBe(false)
			t.expect(
				has(
					markedApply.stdout .. markedApply.stderr,
					"inside an agent session (CLAUDE_CODE_SESSION_ID is set)"
				)
			).toBe(true)
			local markedPublish = onTerminal(f.main, "approve c0004 --publish", "y", { AI_AGENT = "x" })
			t.expect(
				has(markedPublish.stdout .. markedPublish.stderr, "inside an agent session (AI_AGENT is set)")
			)
				.toBe(true)
			-- the engine repeats the session refusal when the wrapper is bypassed
			local direct = onTerminal(
				f.main,
				"run z-nile/engine/main -- approve c0004",
				"y",
				{ ZN_APPROVE_SESSION = run }
			)
			t.expect(direct.ok).toBe(false)
			local engineOnly = fixture.exec(f.main, "sh", {
				"-c",
				`printf 'y\\ny\\n' | script -q /dev/null lune run z-nile/engine/main -- approve --apply {run}; echo zn-exit=$?`,
			}, {
				env = {
					ZN_TOP = f.main,
					ZN_CWD = "",
					ZN_APPROVE_SESSION = run,
					ZN_DISPATCH = "",
					PATH = process.env.PATH or "",
					HOME = process.env.HOME or "",
				},
			})
			t.expect(has(engineOnly.stdout, "approve is refused inside a walkthrough session")).toBe(true)
			-- nothing was recorded by any of them
			t.expect(fs.isFile(`{f.main}/{ROOT}/issues/c0004/approval.md`)).toBe(false)
			fixture.git(f.main, { "fetch", "-q", "origin" })
			t.expect(
				fixture.exec(
					f.main,
					"git",
					{ "cat-file", "-e", `origin/main:{ROOT}/issues/c0004/approval.md` }
				).ok
			).toBe(false)
			-- the reads still work inside a session
			local reads = zn(
				f.main,
				{ "approve", "R0003", "--queue" },
				{ ZN_APPROVE_SESSION = run, PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
			)
			t.expect(reads.ok).toBe(true)
		end
	)

	-- a run of one ticket: queue it, write the ruling, return the run
	local function runWith(id: string, ruling: { string }): string
		local made = zn(f.main, { "approve", "--walk", id, "--queue" })
		local id2 = runOf(made)
		local args = { "approve", "--ruling", id2, id }
		for _, a in ruling do
			table.insert(args, a)
		end
		local wrote = zn(f.main, args)
		if not wrote.ok then
			error(say(wrote))
		end
		return id2
	end

	local function onMain(path: string): boolean
		fixture.git(f.main, { "fetch", "-q", "origin" })
		return fixture.exec(f.main, "git", { "cat-file", "-e", `origin/main:{ROOT}/issues/{path}` }).ok
	end

	it("--apply records only for a y at the terminal, with the owner's walkthrough in the row", function()
		local run1 = runWith("c0004", { "approve" })
		local r = onTerminal(f.main, `approve --apply {run1}`, "y")
		local out = r.stdout .. r.stderr
		t.expect(`{r.ok} {out}`).toBe(`true {out}`)
		-- the prompt shows what --apply worked out itself, in a few lines before the question
		t.expect(has(out, "c0004: Title of c0004")).toBe(true)
		t.expect(
			has(
				out,
				"c0004: Title of c0004; waits because: no approval (1 guesses); 1 guess(es); will be recorded in origin/main, unchanged since the walkthrough 20"
			)
		).toBe(true)
		t.expect(has(out, "  G1 chose: the first")).toBe(true)
		t.expect(has(out, "Approve c0004 (Title of c0004)? [y/N]")).toBe(true)
		t.expect(
			has(out, `{run1}: 1 approved, 0 already approved, 0 changes pending, 0 left waiting, 0 refused`)
		)
			.toBe(true)
		t.expect(
			has(
				fixture.git(f.main, { "show", `origin/main:{ROOT}/issues/c0004/approval.md` }),
				`(walkthrough {run1})`
			)
		).toBe(true)
		-- the ticket no longer waits
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		local gone = zn(f.main, { "approve", "--walk", "c0004", "--queue" })
		t.expect(has(gone.stdout, "nothing waits for approval in c0004")).toBe(true)
		-- a second --apply of the same run has nothing left to ask
		t.expect(
			has(onTerminal(f.main, `approve --apply {run1}`, "y").stdout, "no rulings waiting to be applied")
		)
			.toBe(true)
	end)

	it("any answer but y records nothing, and the ruling waits for a later --apply", function()
		local run2 = runWith("c0005", { "approve" })
		for _, answer in { "n", "yes", "", "x" } do
			local no = onTerminal(f.main, `approve --apply {run2}`, answer)
			t.expect(
				has(no.stdout, "c0005: nothing recorded; the ruling waits for a later ./zn approve --apply")
			)
				.toBe(true)
			t.expect(has(no.stdout, "0 approved, 0 already approved, 0 changes pending, 1 left waiting"))
				.toBe(true)
			t.expect(onMain("c0005/approval.md")).toBe(false)
		end
	end)

	it("the prompt is one line, at most 5 guesses cut to 80 characters, and a pointer to the rest", function()
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		-- c0009: twelve guesses, the first with a 300-character Chose; c0010: none, approved and then redesigned
		local lines = { "# guesses" }
		for n = 1, 12 do
			local chose = if n == 1 then string.rep("x", 300) else `choice number {n}`
			table.insert(lines, `- G{n} (design, 2026-11-16): question {n}. Chose: {chose}. Why: because.`)
		end
		fs.writeDir(`{f.main}/{ROOT}/issues/c0009`)
		fs.writeFile(`{f.main}/{ROOT}/issues/c0009/c0009.md`, doc("c0009", "ready", "", "[]"))
		fs.writeFile(`{f.main}/{ROOT}/issues/c0009/check.sh`, checkText("c0009"))
		fs.writeFile(`{f.main}/{ROOT}/issues/c0009/guesses.md`, table.concat(lines, "\n") .. "\n")
		fs.writeDir(`{f.main}/{ROOT}/issues/c0010`)
		fs.writeFile(`{f.main}/{ROOT}/issues/c0010/c0010.md`, doc("c0010", "ready", "", "[]"))
		fs.writeFile(`{f.main}/{ROOT}/issues/c0010/check.sh`, checkText("c0010"))
		publish("two more tickets")
		t.expect(onTerminal(f.main, "approve c0010", "y").ok).toBe(true)
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		local text = fs.readFile(`{f.main}/{ROOT}/issues/c0010/c0010.md`)
		fs.writeFile(
			`{f.main}/{ROOT}/issues/c0010/c0010.md`,
			(string.gsub(text, "Hash the contract of c0010.", "Hash the contract of c0010, again.", 1))
		)
		publish("c0010 is redesigned")

		-- twelve guesses
		local twelve = runWith("c0009", { "approve" })
		local out = onTerminal(f.main, `approve --apply {twelve}`, "n").stdout
		t.expect(
			has(
				out,
				"c0009: Title of c0009; waits because: no approval (12 guesses); 12 guess(es); will be recorded in origin/main, unchanged since the walkthrough 20"
			)
		).toBe(true)
		local _, shown = string.gsub(out, " chose: ", "")
		t.expect(shown).toBe(5)
		t.expect(has(out, `  G1 chose: {string.rep("x", 80)}…`)).toBe(true)
		t.expect(has(out, string.rep("x", 81))).toBe(false)
		t.expect(has(out, "  and 7 more: see ")).toBe(true)
		t.expect(has(out, `{runDir(twelve)}/brief.md`)).toBe(true)
		t.expect(has(out, "G6 chose")).toBe(false)
		-- no guess: no list at all, and no pointer
		local none = runWith("c0010", { "approve" })
		local bare = onTerminal(f.main, `approve --apply {none}`, "n").stdout
		t.expect(
			has(
				bare,
				"c0010: Title of c0010; waits because: changed: design; 0 guess(es); will be recorded in origin/main"
			)
		).toBe(true)
		t.expect(has(bare, " chose: ")).toBe(false)
		t.expect(has(bare, "more: see")).toBe(false)
	end)

	it("a change ruling is shown, plainly not applied, and shown again by the next --apply", function()
		local run3 =
			runWith("c0005", { "change", "--stage", "design", "--guess", "G1", "--note", "keep the old way" })
		for _ = 1, 2 do
			local r = onTerminal(f.main, `approve --apply {run3}`, "y")
			local out = r.stdout .. r.stderr
			t.expect(r.ok).toBe(true)
			t.expect(
				has(
					out,
					`c0005 (Title of c0005): the owner ruled a change to G1 at the design stage: "keep the old way". Nothing changes yet: ./zn rework is not built`
				)
			).toBe(true)
			t.expect(has(out, "1 changes pending")).toBe(true)
			-- no question is asked about it and no command that does not exist is offered
			t.expect(has(out, "[y/N]")).toBe(false)
			t.expect(has(out, "To carry the change out")).toBe(false)
			t.expect(has(fs.readFile(`{runDir(run3)}/applied.tsv`), "c0005")).toBe(false)
		end
		t.expect(onMain("c0005/approval.md")).toBe(false)
	end)

	it("a hand-made run is refused: no queue.tsv, or a ticket that does not wait now", function()
		-- a run folder with no queue.tsv
		local bare = "20261121T000000Z-aaaa"
		fs.writeDir(`{runDir(bare)}`)
		local nothing = onTerminal(f.main, `approve --apply {bare}`, "y")
		t.expect(nothing.ok).toBe(false)
		t.expect(
			has(
				nothing.stdout .. nothing.stderr,
				`{bare} has no queue.tsv: a run is made by ./zn approve <scope> --queue`
			)
		).toBe(true)
		-- a queue and a ruling for a ticket that never waited (c0006 has no guesses): refused, never asked
		local forged = "20261121T000001Z-bbbb"
		local row: approverun.QueueRow = {
			id = "c0006",
			place = "origin/main",
			hash = "0000",
			state = "waits",
			parts = "-",
			why = "forged",
		}
		t.expect(approverun.write(f.main, forged, { row }, "brief")).toBe(nil)
		t.expect(approverun.addRuling(f.main, forged, {
			ticket = "c0006",
			guess = "-",
			action = "approve",
			stage = "-",
			note = "-",
			lesson = "-",
			ask = "-",
			into = "-",
		})).toBe(nil)
		local refused = onTerminal(f.main, `approve --apply {forged}`, "y")
		t.expect(refused.ok).toBe(false)
		t.expect(
			has(
				refused.stdout .. refused.stderr,
				"c0006: not recorded: it does not wait for approval now (nothing to approve)"
			)
		).toBe(true)
		t.expect(has(refused.stdout .. refused.stderr, "[y/N]")).toBe(false)
		t.expect(onMain("c0006/approval.md")).toBe(false)
		-- a duplicate ruling row is asked once
		local twice = runWith("c0005", { "approve" })
		local file = `{runDir(twice)}/rulings.tsv`
		local text = fs.readFile(file)
		local rowText = string.match(text, "\n(c0005[^\n]*)\n") :: string
		fs.writeFile(file, text .. rowText .. "\n")
		local asked = onTerminal(f.main, `approve --apply {twice}`, "n")
		local _, count = string.gsub(asked.stdout, "Approve c0005 %(Title of c0005%)%? %[y/N%]", "")
		t.expect(count).toBe(1)
	end)

	it("an approval that is already there is counted as already approved, not as approved", function()
		local early = runWith("c0008", { "approve" })
		local recorded = onTerminal(f.main, "approve c0008", "y")
		t.expect(recorded.ok).toBe(true)
		local r = onTerminal(f.main, `approve --apply {early}`, "y")
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, "c0008 (Title of c0008): already approved; nothing to record")).toBe(true)
		t.expect(
			has(
				r.stdout,
				`{early}: 0 approved, 1 already approved, 0 changes pending, 0 left waiting, 0 refused`
			)
		).toBe(true)
	end)

	it("an approval is refused when the design changed since it was walked, naming the part", function()
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		local run4 = runWith("c0001", { "approve" })
		local text = fs.readFile(`{f.main}/{ROOT}/issues/c0001/c0001.md`)
		fs.writeFile(
			`{f.main}/{ROOT}/issues/c0001/c0001.md`,
			(string.gsub(text, "Hash the contract of c0001.", "Hash the contract of c0001, differently.", 1))
		)
		publish("c0001's design changes")
		local r = onTerminal(f.main, `approve --apply {run4}`, "y")
		local out = r.stdout .. r.stderr
		t.expect(r.ok).toBe(false)
		t.expect(
			has(
				out,
				`c0001: not recorded: its contract changed since the walkthrough {run4} (design). Walk it again: ./zn approve --walk c0001`
			)
		).toBe(true)
		t.expect(onMain("c0001/approval.md")).toBe(false)
		-- and the state of the run: nothing was marked applied, so it is asked again
		t.expect(has(fs.readFile(`{runDir(run4)}/applied.tsv`), "c0001")).toBe(false)
	end)

	it("refuses a CLI it cannot start interactively and names the --queue path", function()
		local pathless = onTerminal(
			f.main,
			"approve --walk c0005",
			"y",
			{ PATH = "/usr/bin:/bin:" .. (process.env.HOME or "") .. "/.rokit/bin" }
		)
		t.expect(pathless.ok).toBe(false)
		t.expect(
			has(
				pathless.stdout .. pathless.stderr,
				"claude is not on PATH. The run is written: ./zn approve --walk c0005 --queue prints it"
			)
		).toBe(true)
	end)

	it(
		"the walk form refuses a missing [roles.approve] and a CLI it cannot start interactively, naming the role",
		function()
			local file = `{f.main}/.models.toml`
			local original = fs.readFile(file)
			fs.writeFile(file, "[dispatch]\nstall_seconds = 300\n")
			local missing = onTerminal(f.main, "approve --walk c0005", "y")
			t.expect(missing.ok).toBe(false)
			t.expect(
				has(
					missing.stdout .. missing.stderr,
					"approve: .models.toml names no usable [roles.approve] (no .models.toml on the walk names role approve"
				)
			).toBe(true)
			local grok = string.gsub(original, 'cli = "claude"', 'cli = "grok"')
			grok = string.gsub(grok, 'runtime = "claude%-cli"', 'runtime = "grok-cli"')
			grok = string.gsub(grok, 'model = "claude%-opus%-5%-5"', 'model = "grok-4.7"')
			fs.writeFile(file, grok)
			local other = onTerminal(f.main, "approve --walk c0005", "y")
			t.expect(other.ok).toBe(false)
			t.expect(has(other.stdout .. other.stderr, "[roles.approve] names grok. The run is written:"))
				.toBe(true)
			fs.writeFile(file, original)
		end
	)

	it(
		"a CLI that exits with an error still offers --apply for the rulings it wrote, asking first",
		function()
			local log = `{f.base}/stub.log`
			fs.writeFile(
				`{f.base}/stubs/claude`,
				table.concat({
					"#!/bin/sh",
					'./zn approve --ruling "$ZN_APPROVE_SESSION" c0005 approve > "' .. log .. '" 2>&1',
					"exit 3",
					"",
				}, "\n")
			)
			fixture.exec(f.main, "chmod", { "+x", `{f.base}/stubs/claude` })
			local declined = onTerminal(f.main, "approve --walk c0005", "n")
			local out = declined.stdout .. declined.stderr
			t.expect(has(out, "claude exited with code 3")).toBe(true)
			t.expect(has(out, "the session ended with an error; apply the 1 rulings it wrote? [y/N]"))
				.toBe(true)
			t.expect(has(out, "not applied: ./zn approve --apply")).toBe(true)
			t.expect(onMain("c0005/approval.md")).toBe(false)
			local accepted = onTerminal(f.main, "approve --walk c0005", "y")
			t.expect(has(accepted.stdout, "claude exited with code 3")).toBe(true)
			t.expect(has(accepted.stdout, "1 approved")).toBe(true)
			t.expect(onMain("c0005/approval.md")).toBe(true)
			-- c0005 is approved now: put its approval back for the next case by walking c0001 instead
		end
	)

	it(
		"the walk form starts the CLI that [roles.approve] names, with the session variable, then applies",
		function()
			local log = `{f.base}/stub.log`
			local stub = table.concat({
				"#!/bin/sh",
				-- a child that carries an agent marker; the parent, which records, must be unaffected
				"export CLAUDECODE=1",
				'{ echo "argv=$*"; echo "marker=$CLAUDECODE"; echo "session=$ZN_APPROVE_SESSION"; echo "cwd=$(pwd -P)"; } > "'
					.. log
					.. '"',
				'./zn approve --ruling "$ZN_APPROVE_SESSION" c0001 approve >> "' .. log .. '" 2>&1',
				'./zn approve c0001 >> "' .. log .. '" 2>&1',
				'echo "bare-exit=$?" >> "' .. log .. '"',
				'./zn approve --apply "$ZN_APPROVE_SESSION" >> "' .. log .. '" 2>&1',
				'echo "apply-exit=$?" >> "' .. log .. '"',
				"",
			}, "\n")
			fs.writeFile(`{f.base}/stubs/claude`, stub)
			fixture.exec(f.main, "chmod", { "+x", `{f.base}/stubs/claude` })
			fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			local r = onTerminal(f.main, "approve --walk c0001", "y")
			t.expect(fs.isFile(log)).toBe(true)
			local text = fs.readFile(log)
			local session = string.match(text, "session=(%S+)") or ""
			t.expect(string.match(session, "^%d%d%d%d%d%d%d%dT%d%d%d%d%d%dZ%-%x%x%x%x$") ~= nil).toBe(true)
			t.expect(
				has(text, "argv=--model claude-opus-5-5 Use the z-approve skill for approval run " .. session)
			)
				.toBe(true)
			t.expect(has(text, `{session}/brief.md`)).toBe(true)
			t.expect(has(text, `cwd={f.main}`)).toBe(true)
			-- the session wrote its ruling, and could neither record nor apply
			t.expect(has(text, "ruling written for c0001")).toBe(true)
			t.expect(has(text, "marker=1")).toBe(true)
			t.expect(has(text, "bare-exit=1")).toBe(true)
			t.expect(has(text, "apply-exit=1")).toBe(true)
			t.expect(has(text, "inside a walkthrough session")).toBe(true)
			-- when the CLI exited the command applied: the person's y recorded c0001
			t.expect(`{r.ok} {r.stdout}`).toBe(`true {r.stdout}`)
			t.expect(has(r.stdout, "1 approved")).toBe(true)
			fixture.git(f.main, { "fetch", "-q", "origin" })
			t.expect(
				has(
					fixture.git(f.main, { "show", `origin/main:{ROOT}/issues/c0001/approval.md` }),
					`(walkthrough {session})`
				)
			).toBe(true)
		end
	)

	it("the repository's .models.toml names [roles.approve] as claude on claude-opus-5-5", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local resolved = models.resolveRole(models.walk(top, "."), "approve")
		local spec = resolved.specs[resolved.order[1]]
		t.expect(spec.cli).toBe("claude")
		t.expect(spec.model).toBe("claude-opus-5-5")
	end)

	it("a facts file that cannot be written removes the old one and says so (f0437 review 2)", function()
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		local ok = zn(f.main, { "approve", "--walk", "c0009", "--queue" })
		t.expect(ok.ok).toBe(true)
		t.expect(fs.isFile(`{stateDir()}/approvals.json`)).toBe(true)
		-- a title with a stray byte cannot be encoded
		local file = `{f.main}/{ROOT}/issues/c0009/c0009.md`
		fs.writeFile(file, (string.gsub(fs.readFile(file), "Title of c0009", "Title of c0009 \255", 1)))
		publish("a title with a stray byte")
		local r = zn(f.main, { "approve", "--walk", "c0009", "--queue" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stderr, "approval facts not written")).toBe(true)
		t.expect(fs.isFile(`{stateDir()}/approvals.json`)).toBe(false)
	end)
end)
