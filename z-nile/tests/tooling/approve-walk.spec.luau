--!strict
-- f0423 AC3 to AC7 and the safety property of amendment 4, through the real `./zn` in a fixture (the fixture approve-walk):
-- the queue of a raft and of the stack under it, the rulings a session may write, the y/N that alone records, the
-- refusals (no terminal, ZN_DISPATCH, ZN_APPROVE_SESSION, a changed design), and the launch of the CLI with a stub
-- `claude` first on PATH. `script` is the person's terminal; the spec process itself has none. What is not exercised
-- here: a real CLI taking the terminal.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local models = require("@znile/engine/models")
local process = require("@lune/process")
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

local function checkText(id: string): string
	return HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{id}/check.sh\n` .. "finish\n"
end

local function doc(id: string, design: string, raft: string, depends: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: Title of {id}\nslug: slug-{id}\nraft: {raft}\ndepends_on: {depends}\nemergent: false\ndesign: {design}\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Problem\nThe gate cannot see {id}.\n\n## Solution\nRecord a hash for {id}.\n\n## Design\nHash the contract of {id}.{extra or ""}\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover it.\n`
end

local function raftDoc(id: string, members: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Raft {id}\nslug: raft-{id}\nsingle: false\nissues: [{members}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n## Theme\nThe contract stays put.\n`
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

	local function zn(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
		return fixture.exec(cwd, "./zn", args, if env then { env = env } else nil)
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
		issue("c0001", "draft", "R0001", "[]")
		issue("c0002", "draft", "R0001", "[c0001]")
		issue("c0003", "draft", "R0002", "[c0002]")
		issue("c0004", "draft", "", "[]")
		issue("c0005", "draft", "", "[]")
		seed[`{ROOT}/rafts/R0001/R0001.md`] = raftDoc("R0001", "c0001, c0002")
		seed[`{ROOT}/rafts/R0001/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n'
		seed[`{ROOT}/rafts/R0002/R0002.md`] = raftDoc("R0002", "c0003")
		seed[`{ROOT}/rafts/R0002/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n'
		-- the role the walk form starts (the repository's own .models.toml is checked in the last case)
		seed[".models.toml"] =
			'[roles.approve]\nmodel = "claude-opus-5-5"\ncli = "claude"\nruntime = "claude-cli"\nrank = 4\nmax_tokens = 3000000\n'
		f = trackerfix.new("approve-walk", seed)
		-- c0001 to c0003 hold guesses and are ready; c0004 is ready with none; c0005 stays a draft
		for _, id in { "c0001", "c0002", "c0003", "c0004" } do
			local raft = if id == "c0003" then "R0002" elseif id == "c0004" then "" else "R0001"
			local depends = if id == "c0002" then "[c0001]" elseif id == "c0003" then "[c0002]" else "[]"
			fs.writeFile(
				`{f.main}/{ROOT}/issues/{id}/{id}.md`,
				doc(id, "ready", raft, depends, if id == "c0004" then nil else " Guess (prep) G1: a choice.")
			)
			if id ~= "c0004" then
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
				string.find(r.stdout, "1. c0001", 1, true),
				string.find(r.stdout, "2. c0002", 1, true),
				string.find(r.stdout, "3. c0003", 1, true)
			t.expect(a ~= nil and b ~= nil and c ~= nil).toBe(true)
			t.expect(has(r.stdout, "no approval (1 guesses)")).toBe(true)
			-- queue.tsv: id, place, hash and verdict of each; brief.md: the guesses verbatim and the doc path
			local queue = fs.readFile(`{runDir(run)}/queue.tsv`)
			t.expect(has(queue, "c0001\torigin/main\t")).toBe(true)
			t.expect(has(queue, "c0004")).toBe(false)
			t.expect(has(queue, "c0005")).toBe(false)
			local brief = fs.readFile(`{runDir(run)}/brief.md`)
			t.expect(has(brief, GUESS)).toBe(true)
			t.expect(has(brief, `{ROOT}/issues/c0003/c0003.md`)).toBe(true)
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
		"a raft alone lists its own tickets; --walk lists one; no scope lists the project, with the draft still being worked",
		function()
			local own = zn(f.main, { "approve", "R0001", "--queue" })
			t.expect(own.ok).toBe(true)
			t.expect(has(own.stdout, "2 waiting for the owner, 0 still being worked")).toBe(true)
			t.expect(has(own.stdout, "c0003")).toBe(false)
			local one = zn(f.main, { "approve", "--walk", "c0002", "--queue" })
			t.expect(has(one.stdout, "1 waiting for the owner")).toBe(true)
			t.expect(has(one.stdout, "c0001")).toBe(false)
			local all = zn(f.main, { "approve", "--queue" })
			t.expect(all.ok).toBe(true)
			t.expect(has(all.stdout, "3 waiting for the owner, 1 still being worked")).toBe(true)
			local brief = fs.readFile(`{runDir(runOf(all))}/brief.md`)
			t.expect(has(brief, "c0005: Title of c0005 (its design is not ready)")).toBe(true)
			-- a ticket that does not wait is no run
			local clear = zn(f.main, { "approve", "--walk", "c0004", "--queue" })
			t.expect(has(clear.stdout, "nothing waits for approval in c0004")).toBe(true)
			-- the other forms are refused with the way out
			local tributary = zn(f.main, { "approve", "north", "--queue" })
			t.expect(tributary.ok).toBe(false)
			t.expect(has(say(tributary), "north is not a raft or a ticket")).toBe(true)
			local bare = zn(f.main, { "approve", "c0001", "--queue" })
			t.expect(bare.ok).toBe(false)
		end
	)

	it("--ruling writes one row with no terminal, only into the run's rulings.tsv", function()
		local before = tracked()
		local r = zn(f.main, { "approve", "--ruling", run, "c0001", "approve" })
		t.expect(r.ok).toBe(true)
		t.expect(
			has(
				r.stdout,
				`ruling written for c0001 in {run}: approve. Nothing is recorded until the person runs ./zn approve --apply {run}.`
			)
		).toBe(true)
		t.expect(has(fs.readFile(`{runDir(run)}/rulings.tsv`), "c0001\t-\tapprove")).toBe(true)
		t.expect(tracked()).toEqual(before)
		local again = zn(f.main, { "approve", "--ruling", run, "c0001", "approve" })
		t.expect(again.ok).toBe(false)
		t.expect(has(say(again), "c0001 already has a ruling in this run")).toBe(true)
		local outside = zn(f.main, { "approve", "--ruling", run, "c0004", "approve" })
		t.expect(has(say(outside), "c0004 is not in this run's queue")).toBe(true)
		local noAsk = zn(f.main, {
			"approve",
			"--ruling",
			run,
			"c0002",
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
			{ "approve", "--ruling", run, "c0002", "approve" },
			{ ZN_DISPATCH = "1", PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
		)
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(say(dispatched), `{run}: --ruling is refused while ZN_DISPATCH is set`)).toBe(true)
		-- the session itself may write it
		local session = zn(f.main, {
			"approve",
			"--ruling",
			run,
			"c0002",
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
			local refused = zn(f.main, { "approve", "--ruling", bad, "c0003", "approve" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "is not a run id")).toBe(true)
		end
		local ticket = zn(f.main, { "approve", "--ruling", run, "../../c0003", "approve" })
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
			local walk = zn(f.main, { "approve", "R0001" }, clean)
			t.expect(say(walk)).toBe(
				"R0001: approve is refused without a terminal on stdin. Run ./zn approve R0001 yourself, in a terminal.\n"
			)
			local apply = zn(f.main, { "approve", "--apply", run }, clean)
			t.expect(say(apply)).toBe(
				`approve: approve is refused without a terminal on stdin. Run ./zn approve --apply {run} yourself, in a terminal.\n`
			)
			local bare = zn(f.main, { "approve", "c0001" }, clean)
			t.expect(has(say(bare), "c0001: approve is refused without a terminal on stdin")).toBe(true)
			local republish = zn(f.main, { "approve", "c0001", "--publish" }, clean)
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
			}, { env = { ZN_TOP = f.main, ZN_CWD = "", ZN_DISPATCH = "", ZN_APPROVE_SESSION = "" } })
			t.expect(detached.ok).toBe(false)
			t.expect(say(detached)).toBe(
				`{run}: approve is refused without a terminal on stdin. Run ./zn approve --apply {run} yourself, in a terminal.\n`
			)
			-- ZN_DISPATCH, on a terminal
			for _, line in
				{
					"approve R0001",
					`approve --apply {run}`,
					"approve --walk c0001",
					"approve c0001",
					"approve c0001 --publish",
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
					"approve R0001",
					`approve --apply {run}`,
					"approve --walk c0001",
					"approve c0001",
					"approve c0001 --publish",
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
			-- the engine repeats the session refusal when the wrapper is bypassed
			local direct = onTerminal(
				f.main,
				"run z-nile/engine/main -- approve c0001",
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
			t.expect(fs.isFile(`{f.main}/{ROOT}/issues/c0001/approval.md`)).toBe(false)
			fixture.git(f.main, { "fetch", "-q", "origin" })
			t.expect(
				fixture.exec(
					f.main,
					"git",
					{ "cat-file", "-e", `origin/main:{ROOT}/issues/c0001/approval.md` }
				).ok
			).toBe(false)
			-- the reads still work inside a session
			local reads = zn(
				f.main,
				{ "approve", "R0001", "--queue" },
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
		local run1 = runWith("c0001", { "approve" })
		local r = onTerminal(f.main, `approve --apply {run1}`, "y")
		local out = r.stdout .. r.stderr
		t.expect(`{r.ok} {out}`).toBe(`true {out}`)
		t.expect(has(out, `Approve c0001 (Title of c0001) on the design walked in {run1}? [y/N]`)).toBe(true)
		t.expect(has(out, `{run1}: 1 approved, 0 changes confirmed, 0 left waiting, 0 refused`)).toBe(true)
		t.expect(
			has(
				fixture.git(f.main, { "show", `origin/main:{ROOT}/issues/c0001/approval.md` }),
				`(walkthrough {run1})`
			)
		).toBe(true)
		-- the ticket no longer waits
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		local gone = zn(f.main, { "approve", "--walk", "c0001", "--queue" })
		t.expect(has(gone.stdout, "nothing waits for approval in c0001")).toBe(true)
		-- a second --apply of the same run has nothing left to ask
		t.expect(
			has(onTerminal(f.main, `approve --apply {run1}`, "y").stdout, "no rulings waiting to be applied")
		)
			.toBe(true)
	end)

	it("any answer but y records nothing, and the ruling waits for a later --apply", function()
		local run2 = runWith("c0002", { "approve" })
		for _, answer in { "n", "yes", "", "x" } do
			local no = onTerminal(f.main, `approve --apply {run2}`, answer)
			t.expect(
				has(no.stdout, "c0002: nothing recorded; the ruling waits for a later ./zn approve --apply")
			)
				.toBe(true)
			t.expect(has(no.stdout, "0 approved, 0 changes confirmed, 1 left waiting")).toBe(true)
			t.expect(onMain("c0002/approval.md")).toBe(false)
		end
	end)

	it(
		"a change ruling is confirmed with y and prints the ./zn rework line (step 3 runs it); nothing is recorded",
		function()
			local run3 = runWith(
				"c0002",
				{ "change", "--stage", "design", "--guess", "G1", "--note", "keep the old way" }
			)
			local r = onTerminal(f.main, `approve --apply {run3}`, "y")
			local out = r.stdout .. r.stderr
			t.expect(
				has(
					out,
					`Change c0002 (Title of c0002) G1 at the design stage: "keep the old way". c0002 goes back to the design stage.`
				)
			).toBe(true)
			t.expect(
				has(
					out,
					"c0002: confirmed. To carry the change out, run: ./zn rework c0002 --stage design --guess G1 --note 'keep the old way'"
				)
			).toBe(true)
			t.expect(onMain("c0002/approval.md")).toBe(false)
		end
	)

	it("an approval is refused when the design changed since it was walked, naming the part", function()
		local run4 = runWith("c0003", { "approve" })
		local text = fs.readFile(`{f.main}/{ROOT}/issues/c0003/c0003.md`)
		fs.writeFile(
			`{f.main}/{ROOT}/issues/c0003/c0003.md`,
			(string.gsub(text, "Hash the contract of c0003.", "Hash the contract of c0003, differently.", 1))
		)
		publish("c0003's design changes")
		local r = onTerminal(f.main, `approve --apply {run4}`, "y")
		local out = r.stdout .. r.stderr
		t.expect(r.ok).toBe(false)
		t.expect(
			has(
				out,
				`c0003: not recorded: its contract changed since the walkthrough {run4} (design). Walk it again: ./zn approve --walk c0003`
			)
		).toBe(true)
		t.expect(onMain("c0003/approval.md")).toBe(false)
		-- and the state of the run: nothing was marked applied, so it is asked again
		t.expect(has(fs.readFile(`{runDir(run4)}/applied.tsv`), "c0003")).toBe(false)
	end)

	it(
		"the walk form starts the CLI that [roles.approve] names, with the session variable, then applies",
		function()
			local log = `{f.base}/stub.log`
			local stub = table.concat({
				"#!/bin/sh",
				'{ echo "argv=$*"; echo "session=$ZN_APPROVE_SESSION"; echo "cwd=$(pwd -P)"; } > "'
					.. log
					.. '"',
				'./zn approve --ruling "$ZN_APPROVE_SESSION" c0002 approve >> "' .. log .. '" 2>&1',
				'./zn approve c0002 >> "' .. log .. '" 2>&1',
				'echo "bare-exit=$?" >> "' .. log .. '"',
				'./zn approve --apply "$ZN_APPROVE_SESSION" >> "' .. log .. '" 2>&1',
				'echo "apply-exit=$?" >> "' .. log .. '"',
				"",
			}, "\n")
			fs.writeFile(`{f.base}/stubs/claude`, stub)
			fixture.exec(f.main, "chmod", { "+x", `{f.base}/stubs/claude` })
			fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
			local r = onTerminal(f.main, "approve --walk c0002", "y")
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
			t.expect(has(text, "ruling written for c0002")).toBe(true)
			t.expect(has(text, "bare-exit=1")).toBe(true)
			t.expect(has(text, "apply-exit=1")).toBe(true)
			t.expect(has(text, "inside a walkthrough session")).toBe(true)
			-- when the CLI exited the command applied: the person's y recorded c0002
			t.expect(`{r.ok} {r.stdout}`).toBe(`true {r.stdout}`)
			t.expect(has(r.stdout, "1 approved")).toBe(true)
			fixture.git(f.main, { "fetch", "-q", "origin" })
			t.expect(
				has(
					fixture.git(f.main, { "show", `origin/main:{ROOT}/issues/c0002/approval.md` }),
					`(walkthrough {session})`
				)
			).toBe(true)
		end
	)

	it("refuses a CLI it cannot start interactively and names the --queue path", function()
		fs.removeFile(`{f.base}/stubs/claude`)
		local pathless = onTerminal(
			f.main,
			"approve R0002",
			"y",
			{ PATH = "/usr/bin:/bin:" .. (process.env.HOME or "") .. "/.rokit/bin" }
		)
		t.expect(pathless.ok).toBe(false)
		t.expect(
			has(
				pathless.stdout .. pathless.stderr,
				"claude is not on PATH. The run is written: ./zn approve R0002 --queue prints it"
			)
		).toBe(true)
	end)

	it("the repository's .models.toml names [roles.approve] as claude on claude-opus-5-5", function()
		local top = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local resolved = models.resolveRole(models.walk(top, "."), "approve")
		local spec = resolved.specs[resolved.order[1]]
		t.expect(spec.cli).toBe("claude")
		t.expect(spec.model).toBe("claude-opus-5-5")
	end)
end)
