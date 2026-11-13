--!strict
-- c0261 (AC2, the dispatcher's wiring of models.available): the dispatcher reads a CLI's model list once per run
-- (`agent --list-models`), through the CLI's own binary under .cache; an agent whose list lacks Opus starts the next try
-- (kimi) and records the first as an attempt `missing`; a failed or unreadable list fails open (Opus starts, one stderr
-- line). A fake agent that answers the list and counts its calls; fixture under .cache/c0261-list.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["agent"]

[dispatch]
stall_seconds = 5
tool_seconds = 8

[zz-review.agent]
model = "claude-opus-5-5-high"
fallback = ["kimi-k3-high", "grok-4.7-xhigh"]
rank = 4
runtime = "cursor-cli"
max_tokens = 5000
max_calls = 9
max_minutes = 9
]]

local h: fakecli.Harness
local wt: string
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function znIn(args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(wt, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
			GH_TOKEN = "the-users-token",
		},
	})
end
-- one design review under the given list answer (nil: the CLI prints the stock JSON, as c0117's fakes do)
local function review(list: string?, fail: boolean): (fixture.Result, string, number)
	fakecli.clear(h)
	fakecli.mode(h, "agent.zz-review", "script")
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`sleep 1; printf '# Review\n\nVerdict: approve\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
	if list then
		fs.writeFile(`{h.fakes}/models.txt`, list)
	end
	if fail then
		fs.writeFile(`{h.fakes}/models.fail`, "1")
	end
	fs.writeFile(`{h.fakes}/listcalls`, "")
	local r = znIn({ "dispatch", "zz-review", "c0010", "--mode", "design" })
	local _, calls = string.gsub(fs.readFile(`{h.fakes}/listcalls`), "\n", "")
	local path = `{wt}/pickman/.tracker/issues/c0010/design-review-001.md`
	if fs.isFile(path) then
		fs.removeFile(path)
	end
	return r, fakecli.log(h), calls
end

return t.spec("c0261 the dispatcher reads the model list once and skips an unlisted model", function(it)
	it("sets up a tracker, a fake agent that lists models, and a prep worktree", function()
		h = fakecli.new("c0261-list", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
		})
		process.exec("mv", { `{h.bin}/agent`, `{h.bin}/agent.real` })
		fs.writeFile(
			`{h.bin}/agent`,
			table.concat({
				"#!/bin/sh",
				'if [ "$1" = --list-models ]; then',
				'  echo x >> "$FAKE_DIR/listcalls"',
				'  [ -f "$FAKE_DIR/models.fail" ] && { echo "not signed in" >&2; exit 1; }',
				'  [ -f "$FAKE_DIR/models.txt" ] && cat "$FAKE_DIR/models.txt"',
				"  exit 0",
				"fi",
				'exec "$(dirname "$0")/agent.real" "$@"',
				"",
			}, "\n")
		)
		process.exec("chmod", { "+x", `{h.bin}/agent` })
		wt = trackerfix.trOk(h.f, h.f.main, { "worktree", "prep-first-thing" })
	end)

	it(
		"an agent whose list lacks Opus starts kimi, records the Opus try as missing, and lists once (D7)",
		function()
			local r, log, calls = review("kimi-k3-high - Kimi K3\ngrok-4.7-xhigh - Grok 4.7\n", false)
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(has(log, "--model kimi-k3-high")).toBe(true)
			t.expect(has(log, "--model claude-opus-5-5-high")).toBe(false)
			t.expect(has(r.stderr, "model claude-opus-5-5-high not listed by agent")).toBe(true)
			t.expect(calls).toBe(1) -- three tries ask the list, which is read once
			local state = fakecli.state(h, "c0010")
			t.expect(state.history[1].outcome).toBe("missing")
			t.expect(state.history[1].detail).toBe("model claude-opus-5-5-high not listed by agent")
		end
	)

	it("an agent whose list names Opus starts Opus (D7)", function()
		local r, log, calls = review("claude-opus-5-5-high - Opus 5.5 High\nkimi-k3-high - Kimi K3\n", false)
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(log, "--model claude-opus-5-5-high")).toBe(true)
		t.expect(has(log, "--model kimi-k3-high")).toBe(false)
		t.expect(calls).toBe(1)
	end)

	it(
		"a failed list fails open with one stderr line, and so does an answer with no model ids in it (D7)",
		function()
			local r, log = review(nil, true)
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(has(log, "--model claude-opus-5-5-high")).toBe(true)
			local lines = 0
			for line in string.gmatch(r.stderr, "[^\n]+") do
				if has(line, "model list could not be read") then
					lines += 1
				end
			end
			t.expect(lines).toBe(1)
			-- the stock fake answers every call with a JSON result line: not a list
			local r2, log2 = review(nil, false)
			if not r2.ok then
				error(r2.stdout .. r2.stderr)
			end
			t.expect(has(log2, "--model claude-opus-5-5-high")).toBe(true)
		end
	)
end)
