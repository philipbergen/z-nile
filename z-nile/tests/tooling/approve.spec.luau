--!strict
-- ./zn approve records the contract, and ready, done and --check refuse when it changes.
-- The fixture is .cache/approve-gate. Approving goes through `script`, which allocates a terminal;
-- the spec process itself has none.
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

	local function approve(env: { [string]: string }?): fixture.Result
		local merged: { [string]: string } = { PATH = process.env.PATH or "", HOME = process.env.HOME or "" }
		if env then
			for k, v in env do
				merged[k] = v
			end
		end
		return fixture.exec(wt, "script", { "-q", "/dev/null", "./zn", "approve", ID }, { env = merged })
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

	it("refuses an agent, a pipe, a draft and an unruled bullet", function()
		local piped = zn(wt, { "approve", ID })
		t.expect(piped.ok).toBe(false)
		t.expect(has(say(piped), "without a terminal on stdin")).toBe(true)

		local dispatched = approve({ ZN_DISPATCH = "1" })
		t.expect(dispatched.ok).toBe(false)
		t.expect(has(say(dispatched), "ZN_DISPATCH is set")).toBe(true)

		local draft = approve(nil)
		t.expect(draft.ok).toBe(false)
		t.expect(has(say(draft), "is not design: ready")).toBe(true)

		fs.writeFile(
			`{wt}/{ISSUE}/{ID}.md`,
			doc("ready") .. "\n## Open to the human\n- F1: a finding. Decision: rule it.\n"
		)
		commit(wt, "an unruled bullet")
		local open = approve(nil)
		t.expect(open.ok).toBe(false)
		t.expect(has(say(open), "unruled open-list bullet (F1)")).toBe(true)
	end)

	it("records the hash, and ready and done refuse the part that changed", function()
		fs.writeFile(`{wt}/{ISSUE}/{ID}.md`, doc("ready"))
		publish("design ready, no approval yet")
		local early = zn(f.main, { "ready", RAFT })
		t.expect(early.ok).toBe(false)
		t.expect(has(say(early), "one-time step for an item prepared before approval")).toBe(true)
		t.expect(has(say(early), ID)).toBe(true)

		local recorded = approve(nil)
		t.expect(recorded.ok).toBe(true)
		t.expect(has(recorded.stdout, `approved {ID} `)).toBe(true)
		local hash = string.match(recorded.stdout, "approved c0001 (%x+)")
		t.expect(hash ~= nil and #hash == 64).toBe(true)
		local file = fs.readFile(`{wt}/{ISSUE}/approval.md`)
		t.expect(has(file, "approve-gate")).toBe(true)
		t.expect(string.match(file, "%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ") ~= nil).toBe(true)

		publish("approved")
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
		fs.writeFile(`{f.main}/{HOLD}`, (string.gsub(spec, "toBe%(true%)", "toBe(false)", 1)))
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
		fs.writeFile(
			`{f.main}/{ISSUE}/{ID}.md`,
			(string.gsub(body, "Hash the contract.", "Hash the contract!", 1))
		)
		commit(f.main, "the design section")
		fixture.git(f.main, { "push", "-q", "origin", "HEAD:main" })
		local design = zn(f.main, { "approve", ID, "--check" })
		t.expect(design.ok).toBe(false)
		t.expect(has(say(design), "contract changed since approval: design")).toBe(true)
		t.expect(has(say(design), "hold.spec.luau")).toBe(false)

		-- The worktree is where a terminal can approve. Bring it up to the design change first.
		fixture.git(wt, { "pull", "-q", "--ff-only", "origin", "main" })
		local again = approve(nil)
		t.expect(again.ok).toBe(true)
		publish("approved again")
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
		fs.writeFile(`{layer}/{ROOT}/rafts/active/{RAFT}/review-001.md`, "Verdict: approve\n")
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
		t.expect(has(say(dropped), `{ID} has no approval`)).toBe(true)

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
