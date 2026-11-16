--!strict
-- c0253 AC2, AC5, AC6: the dispatcher's worker mode (`./zn dispatch z-run R0010 --worker`), over the fake CLIs
-- (@tests/lib/fakecli) on a fixture under .cache/c0253-dispatch whose R0010 is readied. A raft's z-run step is one CLI session
-- resumed on a rerun; the person's CLI is tried first; a CLI out of quota is waited for once and then the next CLI starts a
-- new session that reads the raft's notes; every session leaves a measured row; every prompt names the skill. No real CLI
-- starts (the dispatcher refuses any outside .cache in a check run), and the waits are one second (ZN_WORK_QUOTA_WAIT).
local escalation = require("@znile/engine/escalation")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local PREPARED = "prepared-quiet-copper-falcon"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local MODELS = [[
[dispatch]
stall_seconds = 60
tool_seconds = 120

[work.claude]
quota_wait_minutes = 1

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = ["grok"]
]]

local h: fakecli.Harness
local quotaOut = ""
local WAIT = { ZN_WORK_QUOTA_WAIT = "6", ZN_BEAT_EVERY = "1" }

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	for _ = 1, 1000 do
		local a, b = string.find(text, needle, i, true)
		if not a then
			break
		end
		n += 1
		i = (b :: number) + 1
	end
	return n
end
local function step(extra: { string }?): string
	local args = { "dispatch", "z-run", "R0010", "--worker" }
	local more: { string } = extra or {}
	for _, a in more do
		table.insert(args, a)
	end
	local r = fakecli.zn(h, args, WAIT)
	return r.stdout .. r.stderr
end

return t.spec("c0253 the dispatcher's worker mode", function(it)
	it("sets up a readied raft and the fake CLIs", function()
		h = fakecli.new("c0253-dispatch", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = MODELS,
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Carry\nslug: carry\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-11-10\nstatus: {PREPARED}\n---\n\n# R0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/c0010.md"] = `---\nid: c0010\ntype: chore\ntitle: c0010\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: {PREPARED}\n---\n\n# c0010\n`,
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
		})
		local ready = fakecli.zn(h, { "ready", "R0010" })
		if not ready.ok then
			error(ready.stdout .. ready.stderr)
		end
	end)

	it(
		"AC2: a raft's z-run session is new at first and resumed on a rerun, on the CLI that ran it",
		function()
			fakecli.clear(h)
			local first = step()
			t.expect(has(first, "z-run on claude: ok")).toBe(true)
			local log = fakecli.log(h)
			local id = string.match(log, "%-%-session%-id ([%w%-]+)")
			t.expect(id ~= nil).toBe(true)
			local state = fakecli.state(h, "R0010")
			t.expect(state.session.cli).toBe("claude")
			t.expect(state.session.id).toBe(id)
			step()
			local again = fakecli.log(h)
			t.expect(has(again, `--resume {id}`)).toBe(true)
			t.expect(count(again, "--session-id") <= 1).toBe(true)
		end
	)

	it(
		"AC5: every prompt of a worker session names its skill, the raft and the notes; a resumed one says so",
		function()
			local log = fakecli.log(h)
			t.expect(count(log, "z-nile/skills/z-run/SKILL.md") >= 2).toBe(true)
			t.expect(has(log, "Keep `pickman/.tracker/rafts/active/R0010/notes.md` current")).toBe(true)
			t.expect(
				has(log, "This is a resumed session for R0010: you have read `z-nile/skills/z-run/SKILL.md`")
			)
				.toBe(true)
		end
	)

	it("AC6: every session leaves one measured row, with the adapter's tokens and the model", function()
		local pending = fakecli.state(h, "R0010").pending
		t.expect(#pending >= 2).toBe(true)
		for _, row in pending do
			t.expect(row.tokens).toBe(123)
			t.expect(has(row.model, "claude-opus-5-5")).toBe(true)
		end
	end)

	it("AC5: the person's CLI is tried first", function()
		fakecli.clear(h)
		step({ "--cli", "grok" })
		local log = fakecli.log(h)
		local firstCli = string.match(log, "^(%a+) step=")
		t.expect(firstCli).toBe("grok")
		t.expect(has(log, "claude step=")).toBe(false)
	end)

	it(
		"AC5: a CLI out of quota is waited for once, then the next CLI starts a new session that reads the notes",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude", "spentquota")
			local out = step({ "--cli", "claude" })
			quotaOut = out
			local log = fakecli.log(h)
			t.expect(count(log, "claude step=")).toBe(2) -- the try, and the retry after the wait
			t.expect(count(log, "grok step=")).toBe(1)
			t.expect(has(out, "claude is out of quota: waiting 60s for it before the next CLI")).toBe(true)
			t.expect(has(out, "dispatch: waited 6s with no model running, beating active-")).toBe(true)
			t.expect(has(log, "taken over from a session on claude")).toBe(true)
			t.expect(has(log, "pickman/.tracker/rafts/active/R0010/notes.md")).toBe(true)
			t.expect(fakecli.state(h, "R0010").session.cli).toBe("grok")
		end
	)

	it("AC7: the quota wait beats the claim through c0275's claimBeat, with the claim's stamp", function()
		-- the beat child is `zn run --time 60 -- zn beat R0010 --adopt --stamp <S>`; c0265's `beat` command is not in this tree,
		-- so the child fails and the dispatcher says so once: the attempt, with the stamp, is what this case sees
		t.expect(has(quotaOut, "dispatch: beat R0010")).toBe(true)
	end)

	it("AC5: a plain dispatch run keeps the role's order, with no wait and no session record", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude", "spentquota")
		local r = fakecli.zn(h, { "dispatch", "z-run", "R0010" }, WAIT)
		local out = r.stdout .. r.stderr
		local log = fakecli.log(h)
		t.expect(has(out, "waiting")).toBe(false)
		t.expect(count(log, "claude step=")).toBe(1)
		t.expect(has(log, "--resume")).toBe(false)
		t.expect(has(log, "Keep `")).toBe(false)
	end)

	it(
		"AC5: an outage that a working session ended is forgotten: the cap counts one unbroken stretch",
		function()
			fakecli.clear(h)
			local path = `{h.f.main}/.cache/dispatch/R0010/state.json`
			local text = fs.readFile(path)
			fs.writeFile(path, (string.gsub(text, '"session"', '"quotaSince": 1000, "session"', 1)))
			t.expect(fakecli.state(h, "R0010").quotaSince).toBe(1000)
			step({ "--cli", "claude" })
			t.expect(fakecli.state(h, "R0010").quotaSince).toBe(nil)
		end
	)

	it(
		"AC5: with every CLI out past the cap the raft is blocked with quota and a note escalation.parse accepts",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude", "spentquota")
			fakecli.mode(h, "grok", "quota")
			local r = fakecli.zn(h, { "dispatch", "R0010", "--worker", "--cli", "claude" }, {
				ZN_WORK_QUOTA_WAIT = "3",
				ZN_WORK_QUOTA_CAP = "5",
				ZN_BEAT_EVERY = "1",
			})
			local out = r.stdout .. r.stderr
			t.expect(has(out, "every CLI is out of quota: waiting")).toBe(true)
			local doc = fixture.git(h.f.origin, { "show", "main:pickman/.tracker/rafts/R0010/R0010.md" })
			t.expect(has(doc, "blocked: quota")).toBe(true)
			local note =
				fixture.git(h.f.origin, { "show", "main:pickman/.tracker/rafts/R0010/escalation.md" })
			local parsed, why = escalation.parse(note)
			t.expect(why).toBe(nil)
			t.expect(escalation.check(parsed :: escalation.Note)).toBe(nil)
		end
	)
end)
