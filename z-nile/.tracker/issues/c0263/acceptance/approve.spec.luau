--!strict
-- c0263 AC4, AC5: `./zn approve <id>` and the refusal of `./zn status <id> prepared` without a current approval, driven
-- for real in worktrees of a trackerfix fixture (a bare origin, the way c0116's claims spec drives the carried move).
-- The approval is a row of the issue's provenance.md, its human is the git author of the `tracker: approve` commit, an
-- agent session needs the user's words, a dispatched worker cannot approve, a redesign makes the approval stale, and a
-- raft's move needs each issue it moves approved.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local NAME = "c0263-approve"
local ME = `human:{NAME}` -- trackerfix's git identity
local OPUS = "agent:claude-opus-5-5 effort high"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local ISSUES = "pickman/.tracker/issues"
-- an agent session's hints must not leak into the human cases
local HUMAN: { [string]: string } =
	{ CLAUDECODE = "", AI_AGENT = "", CLAUDE_EFFORT = "", ZN_ACTOR = "", ZN_DISPATCH = "" }

local function draft(id: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-10-20\nstatus: new-amber-otter-lynx\n---\n\n# {id}\n\n## Design\nOne.\n`
end

local f: trackerfix.Fixture
local W1, W2 = "", ""

local function env(extra: { [string]: string }?): { [string]: string }
	local out: { [string]: string } = {}
	for k, v in HUMAN do
		out[k] = v
	end
	local more: { [string]: string } = extra or {}
	for k, v in more do
		out[k] = v
	end
	return out
end
local function tr(cwd: string, args: { string }, extra: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, cwd, args, env(extra))
end
local function trOk(cwd: string, args: { string }, extra: { [string]: string }?): string
	local r = tr(cwd, args, extra)
	if not r.ok then
		error(`{table.concat(args, " ")} failed ({r.code}): {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end
local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function setLine(path: string, key: string, value: string)
	local text = fs.readFile(path)
	local s, e = string.find(text, `\n{key}:[^\n]*\n`)
	assert(s and e, `{path} has no {key}:`)
	fs.writeFile(path, string.sub(text, 1, s) .. `{key}: {value}\n` .. string.sub(text, e + 1))
end
local function record(wt: string, id: string): string
	local p = `{wt}/{ISSUES}/{id}/provenance.md`
	return if fs.isFile(p) then fs.readFile(p) else ""
end
-- claims `id` for design here and marks its design ready, as z-design does before its last review
local function ready(wt: string, id: string)
	trOk(wt, { "status", id, "preparing" })
	setLine(`{wt}/{ISSUES}/{id}/{id}.md`, "design", "ready")
end

return t.spec("c0263 approve and the refusal of prepared", function(it)
	it("sets up a fixture with an origin and four drafts", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
		}
		for _, id in { "c0010", "c0011", "c0012", "c0013" } do
			seed[`{ISSUES}/{id}/{id}.md`] = draft(id)
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		f = trackerfix.new(NAME, seed)
		W1 = trackerfix.trOk(f, f.main, { "worktree", "prep-a" })
		W2 = trackerfix.trOk(f, f.main, { "worktree", "prep-b" })
	end)

	it(
		"prepared is refused until a human has approved, and the approval is a row with the human and the design hash",
		function()
			ready(W1, "c0010")
			local refused = tr(W1, { "status", "c0010", "prepared" })
			t.expect(refused.ok).toBe(false)
			t.expect(has(refused.stderr, "no current approval")).toBe(true)
			t.expect(has(refused.stderr, "./zn approve c0010")).toBe(true)
			trOk(W1, { "approve", "c0010" })
			local rec = record(W1, "c0010")
			t.expect(has(rec, `| approved | {ME} | design=`)).toBe(true)
			t.expect(
				string.match(rec, "design=(%x+)") ~= nil
					and #(string.match(rec, "design=(%x+)") :: string) == 12
			).toBe(true)
			-- the approve commit is the human's: its author is the git identity, its subject names the issue
			t.expect(fixture.git(W1, { "log", "-1", "--format=%an|%s" }))
				.toBe(`{NAME}|tracker: approve c0010`)
			t.expect(fixture.git(W1, { "status", "--porcelain" })).toBe("")
			-- now the carried move goes through, and it is carried: nothing is published
			local before = fixture.git(f.origin, { "rev-parse", "main" })
			trOk(W1, { "status", "c0010", "prepared" })
			t.expect(fixture.git(f.origin, { "rev-parse", "main" })).toBe(before)
			t.expect(
				string.match(fs.readFile(`{W1}/{ISSUES}/c0010/c0010.md`), "\nstatus: (prepared)%-") ~= nil
			)
				.toBe(true)
		end
	)

	it(
		"approve refuses what a worker, the main checkout, an undesigned issue or an agent without the user's words would pass",
		function()
			ready(W1, "c0011")
			local mark = fixture.git(W1, { "rev-parse", "HEAD" })
			local function refused(args: { string }, extra: { [string]: string }?, cwd: string?)
				local r = tr(cwd or W1, args, extra)
				t.expect(r.ok).toBe(false)
				t.expect(fixture.git(W1, { "rev-parse", "HEAD" })).toBe(mark)
				t.expect(has(record(W1, "c0011"), "approved")).toBe(false)
				return r
			end
			-- a dispatched worker cannot approve
			t.expect(has(refused({ "approve", "c0011" }, { ZN_DISPATCH = "1" }).stderr, "dispatch"))
				.toBe(true)
			-- the main checkout is read-only
			refused({ "approve", "c0011" }, nil, f.main)
			-- an issue that is not being designed (a draft design, then nothing claimed)
			trOk(W2, { "status", "c0012", "preparing" })
			local undesigned = tr(W2, { "approve", "c0012" })
			t.expect(undesigned.ok).toBe(false)
			t.expect(has(undesigned.stderr, "design: ready")).toBe(true)
			local unclaimed = tr(W2, { "approve", "c0013" })
			t.expect(unclaimed.ok).toBe(false)
			-- an agent session carries the user's git identity, so the user's words are required
			local noWords = refused({ "approve", "c0011" }, { CLAUDECODE = "1", CLAUDE_EFFORT = "high" })
			t.expect(has(noWords.stderr, "--said")).toBe(true)
			refused({ "approve", "c0011", "--said", "" }, { CLAUDECODE = "1" })
			-- with the words it records the human, the agent that ran it, and the words
			trOk(
				W1,
				{ "approve", "c0011", "--said", "yes, approved | go ahead" },
				{ CLAUDECODE = "1", CLAUDE_EFFORT = "high", ZN_ACTOR = OPUS }
			)
			local rec = record(W1, "c0011")
			t.expect(has(rec, `| approved | {ME} |`)).toBe(true)
			t.expect(has(rec, `via={OPUS}`)).toBe(true)
			t.expect(has(rec, 'said="yes, approved / go ahead"')).toBe(true)
		end
	)

	it("a redesign makes the approval stale, and a fresh approval makes it current again", function()
		local doc = `{W1}/{ISSUES}/c0011/c0011.md`
		fs.writeFile(doc, fs.readFile(doc) .. "\nA changed rule.\n")
		fixture.git(W1, { "add", "-A" })
		fixture.git(W1, { "commit", "-q", "-m", "redesign" })
		local stale = tr(W1, { "status", "c0011", "prepared" })
		t.expect(stale.ok).toBe(false)
		t.expect(has(stale.stderr, "redesigned since its approval")).toBe(true)
		t.expect(has(stale.stderr, "./zn approve c0011")).toBe(true)
		trOk(W1, { "approve", "c0011", "--said", "still fine" }, { CLAUDECODE = "1" })
		trOk(W1, { "status", "c0011", "prepared" })
		-- two approval rows now; the newest is the one that counts
		local _, n = string.gsub(record(W1, "c0011"), "| approved |", "")
		t.expect(n).toBe(2)
		-- an edit to the sequestered check.sh is a redesign too
		trOk(W2, { "status", "c0012", "new" })
		ready(W2, "c0012")
		trOk(W2, { "approve", "c0012" })
		fs.writeFile(`{W2}/{ISSUES}/c0012/check.sh`, CHECK .. "# edited\n")
		t.expect(tr(W2, { "status", "c0012", "prepared" }).ok).toBe(false)
	end)

	it("a raft's move refuses each issue it moves that has no current approval", function()
		-- new raft merges origin/main after its claim, so the worktree must be clean
		fixture.git(W2, { "add", "-A" })
		fixture.git(W2, { "commit", "-q", "-m", "wip" })
		local out = trOk(W2, { "new", "raft", "chore", "pair", "c0013", "--project", "pickman" })
		local rid = string.match(out, "(R%d+)") :: string
		for _, id in { "c0013" } do
			setLine(`{W2}/{ISSUES}/{id}/{id}.md`, "design", "ready")
		end
		setLine(`{W2}/pickman/.tracker/rafts/{rid}/{rid}.md`, "design", "ready")
		local refused = tr(W2, { "status", rid, "prepared" })
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stderr, "c0013")).toBe(true)
		t.expect(has(refused.stderr, "no current approval")).toBe(true)
		trOk(W2, { "approve", "c0013" })
		local again = tr(W2, { "status", rid, "prepared" })
		-- the approval no longer blocks it; any other refusal (the raft's own Theme) is the raft's rule
		t.expect(has(again.stderr, "no current approval")).toBe(false)
	end)
end)
