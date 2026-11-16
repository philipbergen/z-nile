--!strict
-- c0253 AC1, AC6, AC9: the real `./zn work --once --cli claude` over the fake CLIs, end to end on a fixture under
-- .cache/c0253-session whose R0010 is prepared. The pick is run by the dispatcher's chain (not by a launcher of the
-- supervisor's own): the session gets the dispatcher's wrapper first on its PATH, a publish broker, the agent's token, and none of
-- the markers or session ids of the person's CLI the supervisor was started from. Fake CLIs only: no model, no network.
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

[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []
]]

local h: fakecli.Harness
local out = ""

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

return t.spec("c0253 the supervisor runs a pick through the dispatcher", function(it)
	it("sets up a prepared raft and fake CLIs, the claude one logging the markers it sees", function()
		h = fakecli.new("c0253-session", {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[".models.toml"] = MODELS,
			["pickman/.tracker/architecture.md"] = fs.readFile(`{TOP}/pickman/.tracker/architecture.md`),
			["pickman/.tracker/rafts/R0010/R0010.md"] = `---\nid: R0010\ntype: chore\ntitle: Carry\nslug: carry\nsingle: false\nissues: [c0010]\ndesign: ready\ncreated: 2026-11-10\nstatus: {PREPARED}\n---\n\n# R0010\n`,
			["pickman/.tracker/rafts/R0010/check.sh"] = CHECK,
			["pickman/.tracker/issues/c0010/c0010.md"] = `---\nid: c0010\ntype: chore\ntitle: c0010\nslug: c0010\nraft: R0010\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: {PREPARED}\n---\n\n# c0010\n`,
			["pickman/.tracker/issues/c0010/check.sh"] = CHECK,
		})
		-- the claude fake, wrapped to log what its environment holds of the person's CLI session
		local real = `{h.bin}/claude.real`
		fs.writeFile(real, fakecli.script("claude"))
		fs.writeFile(
			`{h.bin}/claude`,
			'#!/bin/sh\necho "env claudecode=[${CLAUDECODE:-}] session=[${CLAUDE_CODE_SESSION_ID:-}] kimi=[${KIMI_SESSION_ID:-}] headless=[${ZN_HEADLESS:-}] model=[${ZN_MODEL:-}]" >> "$FAKE_DIR/log"\n'
				.. `exec sh "{real}" "$@"\n`
		)
		process.exec("chmod", { "+x", `{h.bin}/claude`, real })
		fixture.git(h.f.main, { "add", "-A" })
		fixture.git(h.f.main, { "commit", "-q", "-m", "models", "--allow-empty" })
		fixture.git(h.f.main, { "push", "-q", "origin", "HEAD:main" })
	end)

	it(
		"AC1: takes the raft next prints and runs it through the dispatcher's chain with the person's CLI",
		function()
			local r = fakecli.zn(h, { "work", "--once", "--cli", "claude" }, {
				CLAUDECODE = "1",
				CLAUDE_CODE_SESSION_ID = "the-persons-session",
				KIMI_SESSION_ID = "the-persons-kimi",
				ZN_WORK_QUOTA_WAIT = "1",
			})
			out = r.stdout .. r.stderr
			t.expect(has(out, "dispatch: z-ready R0010")).toBe(true)
			t.expect(has(out, "dispatch: z-run R0010 on claude")).toBe(true)
			t.expect(has(out, "worker stopped")).toBe(true)
		end
	)

	it(
		"AC6: the session has the dispatcher's wrapper, broker and the agent's token, and not the person's markers",
		function()
			local log = fakecli.log(h)
			t.expect(has(log, "z-run mode=")).toBe(true)
			local path0 = string.match(log, "path0=([^\n]*)") or ""
			t.expect(string.sub(path0, -#"/z-nile/bin") == "/z-nile/bin").toBe(true)
			local broker = string.match(log, "broker=([^\n]*)") or ""
			t.expect(broker ~= "").toBe(true)
			t.expect(has(log, "fake-agent-token")).toBe(true)
			t.expect(has(log, "the-users-token")).toBe(false)
			t.expect(has(log, "env claudecode=[] session=[] kimi=[] headless=[1]")).toBe(true)
			t.expect(has(log, "the-persons-session")).toBe(false)
		end
	)

	it("AC6: the session is told the model it runs on, so its spend and commits record the author", function()
		local log = fakecli.log(h)
		t.expect(has(log, "model=[claude-opus-5-5]")).toBe(true)
	end)
end)
