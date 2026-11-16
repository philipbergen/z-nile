--!strict
-- c0175 AC12: the shared fake CLIs (@tests/lib/fakecli) fake `kimi`, `agy` and `opencode` too, so a dispatcher spec can start them
-- without a real binary. Each fake prints the stream its real CLI prints (as the E1 to E5 probes recorded it), the adapter of its
-- runtime counts it, and its quota mode ends in a quota failure. Fixture under .cache/c0175-fakes. No real CLI starts.
local adapters = require("@znile/engine/adapters")
local fakecli = require("@tests/lib/fakecli")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local F: any = fakecli

local here = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local base = `{here}/.cache/c0175-fakes`

local RUNTIME = { kimi = "kimi-cli", agy = "agy-cli", opencode = "opencode-cli" }

-- Runs the fake `cli` in mode `mode` (the mode file the script reads) and feeds its stdout to the CLI's adapter.
local function run(cli: string, mode: string?): (any, boolean, string)
	process.exec("mkdir", { "-p", `{base}/fakes` })
	local script = `{base}/{cli}`
	fs.writeFile(script, F.script(cli))
	process.exec("chmod", { "+x", script })
	local modeFile = `{base}/fakes/{cli}`
	if fs.isFile(modeFile) then
		fs.removeFile(modeFile)
	end
	if mode then
		fs.writeFile(modeFile, mode)
	end
	local r = process.exec(
		"sh",
		{ script, "-p", "a prompt" },
		{ env = { FAKE_DIR = `{base}/fakes`, PATH = process.env.PATH :: string } }
	)
	local adapter = adapters.get(RUNTIME[cli])
	local acc = adapters.newAcc()
	for line in string.gmatch(r.stdout, "[^\n]+") do
		adapter.feed(acc, line)
	end
	return acc, r.ok, r.stderr
end

return t.spec("c0175 the shared fake CLIs", function(it)
	it(
		"AC12: the fake agy prints a stream its adapter counts: input + output of the step, cache reads out",
		function()
			local acc, ok = run("agy", nil)
			t.expect(ok).toBe(true)
			t.expect(adapters.tokens(acc)).toBe(411)
			t.expect(acc.session).toBe("fake-conversation")
			local outcome = adapters.finish(acc, ok, "", "agy-cli")
			t.expect(outcome).toBe("ok")
		end
	)

	it("AC12: the fake opencode prints a step_finish its adapter counts, and names its session", function()
		local acc, ok = run("opencode", nil)
		t.expect(ok).toBe(true)
		t.expect(adapters.tokens(acc)).toBe(513)
		t.expect(acc.session).toBe("ses_fake")
	end)

	it(
		"AC12: the fake kimi names its session and prints no usage: ok and unmeasured, as the real one is before its wire is read",
		function()
			local acc, ok = run("kimi", nil)
			t.expect(ok).toBe(true)
			t.expect(acc.session).toBe("session_fake")
			local outcome, why = adapters.finish(acc, ok, "", "kimi-cli")
			t.expect(outcome).toBe("ok")
			t.expect(why).toBe("no token count (kimi-cli)")
		end
	)

	it("AC12: each fake's quota mode ends in a quota failure", function()
		for _, cli in { "kimi", "agy", "opencode" } do
			local acc, ok, stderr = run(cli, "quota")
			t.expect(ok).toBe(false)
			local outcome = adapters.finish(acc, ok, stderr, RUNTIME[cli])
			t.expect(outcome).toBe("quota")
		end
	end)

	it("AC12: the fake that fails prints no usage and fails, for each of them", function()
		for _, cli in { "kimi", "agy", "opencode" } do
			local acc, ok, stderr = run(cli, "fail")
			t.expect(ok).toBe(false)
			local outcome = adapters.finish(acc, ok, stderr, RUNTIME[cli])
			t.expect(outcome).toBe("failed")
		end
	end)

	it("AC12: the cap mode of each fake prints lines its adapter counts at 1001 each", function()
		for _, cli in { "agy", "opencode" } do
			local script = F.script(cli)
			local acc = adapters.newAcc()
			-- the mode's echo line, run once with $i = 1, as the shell would
			local line = string.match(script, "cap%) .-; do (echo [^;]+); i=")
			t.expect(line ~= nil).toBe(true)
			local r = process.exec("sh", { "-c", `i=1; {line}` })
			for l in string.gmatch(r.stdout, "[^\n]+") do
				adapters.get(RUNTIME[cli]).feed(acc, l)
			end
			t.expect(adapters.tokens(acc)).toBe(1001)
		end
	end)
	it("AC12: the harness writes an executable fake for each of the six CLIs, and a gh and a git", function()
		local h = F.new("c0175-fakes-new", {})
		for _, name in { "claude", "grok", "agent", "kimi", "agy", "opencode", "gh", "git" } do
			t.expect(process.exec("test", { "-x", `{h.bin}/{name}` }).ok).toBe(true)
		end
		-- the fake it wrote is the library's script, not a stub
		t.expect(fs.readFile(`{h.bin}/agy`)).toBe(F.script("agy"))
		t.expect(fs.readFile(`{h.bin}/opencode`)).toBe(F.script("opencode"))
	end)
end)
