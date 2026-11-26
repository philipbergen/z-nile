--!strict
-- ./zn approve records the contract and publishes it in one command (c0369), and ready, done and --check refuse when
-- it changes. The fixture is .cache/approve-gate. Approving goes through `script`, which allocates a terminal; the
-- spec process itself has none. Every ready design carries an explainer page that names its contract, the opener is
-- a stub first on PATH and `yes y |` answers at the terminal, so the cases pass with or without a page check and a
-- y/n question in approve (c0368's outcome, carried by c0369); the exit code is echoed inside `script`.
local contract = require("@znile/engine/contract")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ID = "c0001"
local RAFT = "R0001"
local ROOT = "z-nile/.tracker"
local ISSUE = `{ROOT}/issues/{ID}`
local HOLD = `{ISSUE}/acceptance/hold.spec.luau`

local HEAD =
	'#!/usr/bin/env bash\nsource "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
local CHECK = HEAD .. 'check "AC1: holds" true\n' .. `# {ROOT}/issues/{ID}/check.sh\n` .. "finish\n"
local SPEC = "--!strict\n"
	.. 'local t = require("@tests/lib/t")\n'
	.. 'return t.spec("holds", function(it)\n'
	.. '\tit("holds", function()\n'
	.. "\t\tt.expect(true).toBe(true)\n"
	.. "\tend)\n"
	.. "end)\n"

-- a person's terminal: the agent markers and session ids cleared (zz-test lesson terminal-fixtures-clear-the-agent-session)
local TERMINAL: { [string]: string } = {
	ZN_DISPATCH = "",
	ZN_HEADLESS = "",
	CLAUDECODE = "",
	AI_AGENT = "",
	CURSOR_AGENT = "",
	GROK_SESSION_ID = "",
	CLAUDE_CODE_SESSION_ID = "",
	KIMI_SESSION_ID = "",
	KIMI_CODE_SESSION_ID = "",
}

-- an explainer page of f0339's shape that names the contract of the document `text` and the spec `spec`
local function page(text: string, spec: string?): string
	local parts = contract.build(text, CHECK, { ["hold.spec.luau"] = spec or SPEC })
	local hash = contract.hash(parts :: contract.Parts)
	return `<!doctype html><html><head><meta charset="utf-8"><meta name="zn-contract" content="{hash}"><title>c0001</title></head><body>`
		.. '<section id="idea"><p>Show the person a page before they say yes.</p></section>'
		.. '<section id="before"><svg viewBox="0 0 10 10"><rect width="4" height="4"/></svg></section>'
		.. '<section id="changes"><ul><li><code>z-nile/engine/hold.luau</code>: hold()</li></ul></section>'
		.. '<section id="after"><svg viewBox="0 0 10 10"><circle r="3"/></svg></section>'
		.. '<section id="choices"><div class="choice"><ul class="pros"><li>plain</li></ul><ul class="cons"><li>one more file</li></ul></div></section>'
		.. "</body></html>\n"
end
local PAGE = `{ISSUE}/explainer.html`

local function doc(design: string): string
	return `---\nid: {ID}\ntype: chore\ntitle: Hold\nslug: hold\nraft: {RAFT}\ndepends_on: []\nemergent: false\ndesign: {design}\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {ID}\n\n## Problem\nThe gate cannot see an approval.\n\n## Solution\nRecord a hash.\n\n## Design\nHash the contract.\n\n## Acceptance criteria\nThe hash is checked.\n\n## Test plan\nSpecs cover the gates.\n`
end

local function raftDoc(): string
	return `---\nid: {RAFT}\ntype: chore\ntitle: Hold\nslug: hold\nsingle: true\nissues: [{ID}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n\n## Theme\nThe contract stays put.\n`
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("human approval freezes the contract", function(it)
	local f: trackerfix.Fixture
	local wt = ""

	local function zn(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
		return fixture.exec(cwd, "./zn", args, if env then { env = env } else nil)
	end

	local function say(result: fixture.Result): string
		return result.stderr .. result.stdout
	end

	local function commit(cwd: string, message: string)
		fixture.git(cwd, { "add", "-A" })
		local stale = fixture.git(cwd, { "status", "--porcelain" })
		if stale ~= "" then
			fixture.git(cwd, { "commit", "-q", "-m", message })
		end
	end

	local function publish(message: string)
		commit(wt, message)
		fixture.git(wt, { "push", "-q", "origin", "HEAD:main" })
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
	end

	-- `./zn approve c0001` in the worktree (or `./zn approve <id>` in `cwd`), with a terminal that answers y and a stub
	-- opener first on PATH
	local function approve(env: { [string]: string }?, cwd: string?, id: string?): fixture.Result
		local stubs = `{f.base}/stubs`
		if not fs.isDir(stubs) then
			fs.writeDir(stubs)
			for _, name in { "open", "xdg-open" } do
				fs.writeFile(`{stubs}/{name}`, "#!/bin/sh\nexit 0\n")
				fixture.exec(f.main, "chmod", { "+x", `{stubs}/{name}` })
			end
		end
		local merged = table.clone(TERMINAL)
		merged.PATH = `{stubs}:{process.env.PATH or ""}`
		merged.HOME = process.env.HOME or ""
		if env then
			for k, v in env do
				merged[k] = v
			end
		end
		local target = id or ID
		local line = `yes y | script -q /dev/null sh -c './zn approve {target}; echo "zn-exit=$?"'`
		local r = fixture.exec(cwd or wt, "sh", { "-c", line }, { env = merged })
		local code = string.match(r.stdout, "zn%-exit=(%d+)")
		return { ok = code == "0", code = tonumber(code or "1") or 1, stdout = r.stdout, stderr = r.stderr }
	end
	-- origin/main as it is now, in the main checkout and the worktree
	local function catchUp()
		fixture.git(f.main, { "pull", "-q", "--ff-only", "origin", "main" })
		fixture.git(wt, { "pull", "-q", "--ff-only", "origin", "main" })
	end

	it("sets up a prepared issue with no approval", function()
		f = trackerfix.new("approve-gate", {
			[`{ROOT}/rafts/{RAFT}/{RAFT}.md`] = raftDoc(),
			[`{ROOT}/rafts/{RAFT}/check.sh`] = HEAD .. 'check "RC0: holds" true\nfinish\n',
			[`{ISSUE}/{ID}.md`] = doc("draft"),
			[`{ISSUE}/check.sh`] = CHECK,
			[HOLD] = SPEC,
		})
		wt = `{f.base}/wt`
		fixture.git(f.main, { "worktree", "add", "-q", "-b", "prep-c0001", wt, "HEAD" })
	end)

	it("refuses a pipe, the dispatcher, a draft and an unruled bullet", function()
		local piped = zn(wt, { "approve", ID })
		t.expect(piped.ok).toBe(false)
		t.expect(has(say(piped), "without a terminal on stdin")).toBe(true)

		local dispatched = approve({ ZN_DISPATCH = "1" })
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(say(dispatched), "ZN_DISPATCH is set")).toBe(true)

		local draft = approve(nil)
		t.expect(draft.ok).toBe(false)
		t.expect(has(say(draft), "is not design: ready")).toBe(true)

		-- f0423 (was c0369 review 001 F3, which refused a raft id as "not an issue"): a raft id is now a scope to walk, and a
		-- raft whose only ticket is a draft has nothing waiting; it is never refused as a wrong kind of id
		local walked = zn(wt, { "approve", RAFT, "--queue" })
		t.expect(walked.ok).toBe(true)
		t.expect(has(say(walked), `approve takes an issue ({RAFT} is a raft)`)).toBe(false)
		t.expect(has(say(walked), `nothing waits for approval in {RAFT} (1 still being worked)`)).toBe(true)

		fs.writeFile(
			`{wt}/{ISSUE}/{ID}.md`,
			doc("ready") .. "\n## Open to the human\n- F1: a finding. Decision: rule it.\n"
		)
		commit(wt, "an unruled bullet")
		local open = approve(nil)
		t.expect(open.ok).toBe(false)
		t.expect(has(say(open), "unruled open-list bullet (F1)")).toBe(true)
	end)

	-- c0369 review 001 F1: zz-rules says a worktree on no branch is refused before anything is recorded; run inside a
	-- detached worktree that holds a design of its own, the command acts there in its own process and must refuse too
	it(
		"refuses to record inside a detached worktree with a design of its own, and records nothing",
		function()
			local detached = `{f.base}/detached`
			fixture.git(f.main, { "worktree", "add", "-q", "--detach", detached, "prep-c0001" })
			local ready = (string.gsub(doc("ready"), "Hash the contract.", "Hash the contract, detached.", 1))
			fs.writeFile(`{detached}/{ISSUE}/{ID}.md`, ready)
			fs.writeFile(`{detached}/{PAGE}`, page(ready))
			commit(detached, "a design of its own, on no branch")
			local tip = fixture.git(detached, { "rev-parse", "HEAD" })
			local mainTip = fixture.git(f.main, { "ls-remote", "origin", "refs/heads/main" })
			local heads = fixture.git(f.main, { "ls-remote", "--heads", "origin" })

			local refused = approve(nil, detached, nil)
			t.expect(refused.ok).toBe(false)
			t.expect(has(say(refused), "is on no branch")).toBe(true)
			t.expect(has(say(refused), "nothing recorded")).toBe(true)
			t.expect(has(say(refused), `approved {ID} `)).toBe(false)
			t.expect(fixture.git(detached, { "rev-parse", "HEAD" })).toBe(tip)
			t.expect(fs.isFile(`{detached}/{ISSUE}/approval.md`)).toBe(false)
			t.expect(fixture.git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(mainTip)
			t.expect(fixture.git(f.main, { "ls-remote", "--heads", "origin" })).toBe(heads)
			fixture.git(f.main, { "worktree", "remove", "--force", detached })
		end
	)

	-- f0421 escape (2026-11-24): an agy session marks itself with ANTIGRAVITY_AGENT alone; on a terminal, with every other
	-- marker cleared and a design ready to approve, that one variable is what refuses
	it("an agy session (ANTIGRAVITY_AGENT alone) on a terminal is refused and records nothing", function()
		fs.writeFile(`{wt}/{ISSUE}/{ID}.md`, doc("ready"))
		fs.writeFile(`{wt}/{PAGE}`, page(doc("ready")))
		publish("design ready, no approval yet")
		local mainTip = fixture.git(f.main, { "ls-remote", "origin", "refs/heads/main" })
		local tip = fixture.git(wt, { "rev-parse", "HEAD" })
		local agy = approve({ ANTIGRAVITY_AGENT = "1" })
		t.expect(agy.ok).toBe(false)
		t.expect(
			has(
				say(agy),
				`{ID}: approve is refused inside an agent session (ANTIGRAVITY_AGENT is set): only the person records an approval, in their own terminal.`
			)
		).toBe(true)
		t.expect(has(say(agy), `approved {ID} `)).toBe(false)
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)
		t.expect(fixture.git(wt, { "rev-parse", "HEAD" })).toBe(tip)
		t.expect(fixture.git(f.main, { "ls-remote", "origin", "refs/heads/main" })).toBe(mainTip)
	end)

	it("records the hash, and ready and done refuse the part that changed", function()
		fs.writeFile(`{wt}/{ISSUE}/{ID}.md`, doc("ready"))
		fs.writeFile(`{wt}/{PAGE}`, page(doc("ready")))
		publish("design ready, no approval yet")
		-- f0399: a missing approval stops ready only under ./zn dispatch; outside it done asks (readycheck.spec)
		local early = zn(
			f.main,
			{ "ready", RAFT },
			{ ZN_DISPATCH = "1", PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
		)
		t.expect(early.ok).toBe(false)
		t.expect(has(say(early), "one-time step for an item prepared before approval")).toBe(true)
		t.expect(has(say(early), ID)).toBe(true)

		local recorded = approve(nil)
		t.expect(recorded.ok).toBe(true)
		t.expect(has(recorded.stdout, `approved {ID} `)).toBe(true)
		t.expect(has(recorded.stdout, `published {ID} to origin/main: it counts now`)).toBe(true)
		t.expect(has(recorded.stdout, "--publish")).toBe(false)
		local hash = string.match(recorded.stdout, "approved c0001 (%x+)")
		t.expect(hash ~= nil and #hash == 64).toBe(true)
		-- one command: nothing is committed in the worktree it ran in, and main has the approval
		t.expect(fs.isFile(`{wt}/{ISSUE}/approval.md`)).toBe(false)
		catchUp()
		local file = fs.readFile(`{f.main}/{ISSUE}/approval.md`)
		t.expect(has(file, "approve-gate")).toBe(true)
		t.expect(string.match(file, "%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ") ~= nil).toBe(true)

		local held = zn(f.main, { "approve", ID, "--check" })
		t.expect(held.ok).toBe(true)
		t.expect(has(held.stdout, `approved {hash} `)).toBe(true)

		local lived = fs.readFile(`{f.main}/{ISSUE}/{ID}.md`)
		fs.writeFile(
			`{f.main}/{ISSUE}/{ID}.md`,
			(
				string.gsub(
					lived,
					"status: prepared%-quiet%-copper%-falcon",
					"status: prepared-other-other-other"
				)
			)
		)
		fs.writeDir(`{f.main}/{ISSUE}/spend.d`)
		fs.writeFile(`{f.main}/{ISSUE}/spend.d/proof.tsv`, "when\tphase\n2026-11-11\tprep\n")
		fs.writeFile(`{f.main}/{ISSUE}/acceptance/hold.watch.txt`, "z-nile/engine/contract.luau\n")
		local sidecars = zn(f.main, { "approve", ID, "--check" })
		t.expect(sidecars.ok).toBe(true)
		fixture.git(f.main, { "checkout", "-q", "--", ISSUE })
		fs.removeDir(`{f.main}/{ISSUE}/spend.d`)

		local spec = fs.readFile(`{f.main}/{HOLD}`)
		local flippedSpec = (string.gsub(spec, "toBe%(true%)", "toBe(false)", 1))
		fs.writeFile(`{f.main}/{HOLD}`, flippedSpec)
		fs.writeFile(`{f.main}/{PAGE}`, page(fs.readFile(`{f.main}/{ISSUE}/{ID}.md`), flippedSpec))
		commit(f.main, "one byte in the spec")
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local named = zn(f.main, { "approve", ID, "--check" })
		t.expect(named.ok).toBe(false)
		t.expect(has(say(named), "hold.spec.luau")).toBe(true)
		local refused = zn(f.main, { "ready", RAFT })
		t.expect(refused.ok).toBe(false)
		t.expect(has(say(refused), "hold.spec.luau")).toBe(true)

		fs.writeFile(`{f.main}/{HOLD}`, spec)
		local body = fs.readFile(`{f.main}/{ISSUE}/{ID}.md`)
		local changed = (string.gsub(body, "Hash the contract.", "Hash the contract!", 1))
		fs.writeFile(`{f.main}/{ISSUE}/{ID}.md`, changed)
		fs.writeFile(`{f.main}/{PAGE}`, page(changed))
		commit(f.main, "the design section")
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local design = zn(f.main, { "approve", ID, "--check" })
		t.expect(design.ok).toBe(false)
		t.expect(has(say(design), "contract changed since approval: design")).toBe(true)
		t.expect(has(say(design), "hold.spec.luau")).toBe(false)

		-- one command again, from the worktree, which is only behind main: it approves main's design
		local again = approve(nil)
		t.expect(again.ok).toBe(true)
		t.expect(has(again.stdout, `published {ID} to origin/main: it counts now`)).toBe(true)
		catchUp()
		local metrics = zn(f.main, { "metrics", ID })
		t.expect(metrics.ok).toBe(true)
		t.expect(has(metrics.stdout, `Approvals for {ID}: 2 (re-approvals 1).`)).toBe(true)
		local history = fs.readFile(`{f.main}/{ISSUE}/approval.md`)
		local rows = 0
		for _ in string.gmatch(history, "\n%d%d%d%d%-%d%d%-%d%dT") do
			rows += 1
		end
		t.expect(rows).toBe(2)

		local readied = zn(f.main, { "ready", RAFT })
		t.expect(readied.ok).toBe(true)
		t.expect(has(readied.stdout, `readied {RAFT}`)).toBe(true)
		local active = `{ROOT}/issues/active/{ID}`
		t.expect(fs.isFile(`{f.main}/{active}/approval.md`)).toBe(true)
		local rewritten = fs.readFile(`{f.main}/{active}/check.sh`)
		t.expect(has(rewritten, `{ROOT}/issues/active/{ID}/check.sh`)).toBe(true)

		-- done checks the published layer tip, so the contract change has to be that commit
		local layer = (string.gsub(zn(f.main, { "worktree", RAFT }).stdout, "%s+$", ""))
		local started = zn(layer, { "start", RAFT })
		if not started.ok then
			error(say(started))
		end
		fs.writeFile(`{layer}/{ROOT}/rafts/active/{RAFT}/final-review-001.md`, "Verdict: approve\n")
		local flipped = fs.readFile(`{layer}/{active}/acceptance/hold.spec.luau`)
		fs.writeFile(
			`{layer}/{active}/acceptance/hold.spec.luau`,
			(string.gsub(flipped, "toBe%(true%)", "toBe(false)", 1))
		)
		commit(layer, "review, then one byte")
		fixture.git(layer, { "push", "-q" })
		local done = zn(layer, { "done", RAFT })
		t.expect(done.ok).toBe(false)
		t.expect(has(say(done), "hold.spec.luau")).toBe(true)
		t.expect(has(say(done), "rolled back")).toBe(false)

		-- deleting the approval is not a way past it: ready published one, so done still asks for it
		fs.removeFile(`{layer}/{active}/approval.md`)
		commit(layer, "the approval deleted")
		fixture.git(layer, { "push", "-q" })
		local dropped = zn(layer, { "done", RAFT })
		t.expect(dropped.ok).toBe(false)
		-- f0399: done names every member that waits, with why
		t.expect(has(say(dropped), `waits for approval: {ID} (no approval)`)).toBe(true)

		fs.writeFile(`{f.main}/{active}/acceptance/hold.spec.luau`, flipped)
		fs.writeFile(
			`{f.main}/{active}/check.sh`,
			(string.gsub(rewritten, "/issues/active/", "/issues/done/"))
		)
		fs.writeDir(`{f.main}/z-nile/tests/acceptance`)
		fixture.git(f.main, { "mv", `{active}/acceptance`, `z-nile/tests/acceptance/{ID}` })
		local promoted = zn(f.main, { "approve", ID, "--check" })
		t.expect(promoted.ok).toBe(true)
		t.expect(has(promoted.stdout, "approved")).toBe(true)
	end)
end)
