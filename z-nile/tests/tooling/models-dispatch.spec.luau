--!strict
-- f0421 slice 2, step 6 (B): a dispatched step and `./zn idea` run on the ONE CLI that runs the activity, through
-- models.resolveActivity, and a call that cannot be made is an error for that activity, never a move to another CLI.
-- AC24's dispatch case (today's legacy file starts what it starts today when the first try succeeds) and AC25 (a CLI that
-- fails or reports quota ends the step and starts no other; --cli names the CLI; a CLI that cannot deliver starts nothing,
-- spends zero tokens and names the need; ./zn idea behaves the same way). Fake CLIs (@tests/lib/fakecli) in fixtures under
-- .cache; the idea cases use stub CLIs on PATH.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))

-- claude has all four aliases, grok only light, agent and kimi only heavy
local SEED = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240
[clis.claude]
xlight = { model = "claude-haiku-5-5", effort = "low" }
light = { model = "claude-sonnet-5-5", effort = "medium" }
heavy = { model = "claude-opus-5-5", effort = "high" }
ultra = { model = "claude-fable-5-2", effort = "xhigh" }
[clis.grok]
light = { model = "grok-4.7", effort = "high" }
[clis.agent]
heavy = { model = "claude-opus-5-5", effort = "high" }
max_calls = 30
max_minutes = 60
[clis.kimi]
heavy = { model = "kimi-code-k3.1-pro" }
[activities.idea]
max_tokens = 300000
all = "heavy"
[activities.idea-challenge]
max_tokens = 300000
all = "ultra"
[activities.design]
max_tokens = 5000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.design-review]
max_tokens = 5000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.raft]
max_tokens = 5000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.raft-review]
max_tokens = 5000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.code]
max_tokens = 5000
easy = "xlight"
normal = "light"
risky = "heavy"
[activities.code-review]
max_tokens = 5000
easy = "light"
normal = "heavy"
risky = "ultra"
[activities.final-review]
max_tokens = 5000
all = "ultra"
[activities.approve]
max_tokens = 5000
all = "heavy"
]]

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(text, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local function issue(id: string, slug: string, risk: string?): string
	local text = trackerfix.stub(id, slug, "new-quiet-copper-falcon")
	if risk then
		text = string.gsub(text, "\nstatus:", `\nrisk: {risk}\nstatus:`, 1)
	end
	return text
end
local function lines(out: string): { string }
	return string.split((string.gsub(out, "%s+$", "")), "\n")
end

local h: fakecli.Harness
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
local function log(): string
	return fakecli.log(h)
end

local IDEA_DRAFT = [[## Problem
- The board hides a finished card before a person can read it.

## Solution
- A finished card stays visible until the person dismisses it.

## Non-goals
- The board does not change how a card is scored.

## Open
- none
]]
-- fable (the challenger here) approves; any other model drafts
local IDEA_CLAUDE = string.gsub(
	[=[#!/bin/bash
echo "$*" >> "$IDEA_STUB_LOG"
if [[ "$*" == *fable* ]]; then
  printf '## Findings\n- none\n\n## Verdict\napprove\n'
else
  cat <<'EOF'
@DRAFT@EOF
fi
echo '{"type":"result","subtype":"success","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"output_tokens":5}}'
exit 0
]=],
	"@DRAFT@",
	function()
		return IDEA_DRAFT
	end
)

return t.spec("f0421 step 6: one CLI per activity, and no fallback to another", function(it)
	it("sets up a tracker with a new-shape .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("f0421-dispatch", {
			[".models.toml"] = SEED,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing", "risky"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
		})
	end)

	it(
		"AC25: a new-shape walk with no --cli and no ZN_CLI names no CLI: an error, and nothing starts",
		function()
			fakecli.clear(h)
			local r = zn({ "dispatch", "z-design", "c0010" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "dispatch: which CLI runs design? pass --cli <name> or set ZN_CLI"))
				.toBe(true)
			t.expect(log()).toBe("")
			local dry = zn({ "dispatch", "z-design", "c0010", "--dry-run" })
			t.expect(dry.ok).toBe(false)
			t.expect(has(dry.stderr, "dispatch: which CLI runs design? pass --cli <name> or set ZN_CLI"))
				.toBe(true)
		end
	)

	it("AC25: --cli names the CLI that runs the step, and so does ZN_CLI; --cli wins", function()
		fakecli.clear(h)
		local r = zn({ "dispatch", "z-design", "c0010", "--cli", "claude" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(count(log(), "claude step=z-design mode=ok")).toBe(1)
		t.expect(has(log(), "--model claude-sonnet-5-5")).toBe(true)
		local row = fakecli.rows(h, "c0010")
		t.expect((row :: any)[#(row :: any)].model).toBe("claude-sonnet-5-5-medium")
		fakecli.clear(h)
		local g = zn({ "dispatch", "z-design", "c0030" }, { ZN_CLI = "grok" })
		if not g.ok then
			error(g.stdout .. g.stderr)
		end
		t.expect(count(log(), "grok step=z-design mode=ok")).toBe(1)
		t.expect(count(log(), "claude step=")).toBe(0)
		local rows = fakecli.rows(h, "c0030") :: any
		t.expect(rows[#rows].model).toBe("grok-4.7-high")
		fakecli.clear(h)
		local both = zn({ "dispatch", "z-design", "c0040", "--cli", "claude" }, { ZN_CLI = "grok" })
		t.expect(both.ok).toBe(true)
		t.expect(count(log(), "claude step=z-design")).toBe(1)
		t.expect(count(log(), "grok step=")).toBe(0)
	end)

	it("AC25: a CLI that fails ends the step, and no other CLI starts", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude", "fail")
		fakecli.mode(h, "grok", "ok")
		fakecli.mode(h, "agent", "ok")
		local r = zn({ "dispatch", "z-design", "c0050", "--cli", "claude" })
		t.expect(r.code).toBe(1)
		t.expect(count(log(), "claude step=")).toBe(1)
		t.expect(count(log(), "grok step=")).toBe(0)
		t.expect(count(log(), "agent step=")).toBe(0)
		t.expect(fakecli.state(h, "c0050").outcome).toBe("failed")
	end)

	it("AC25: a CLI on quota ends the step with the reason, and no other CLI starts", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude", "quota")
		local r = zn({ "dispatch", "z-design", "c0060", "--cli", "claude" })
		t.expect(r.ok).toBe(false)
		t.expect(count(log(), "claude step=")).toBe(1)
		t.expect(count(log(), "grok step=")).toBe(0)
		local s = fakecli.state(h, "c0060")
		t.expect(s.outcome).toBe("quota")
		t.expect(s.history[#s.history].detail).toBe("claude is out of quota")
		t.expect(has(r.stderr, "dispatch: claude is out of quota")).toBe(true)
	end)

	it(
		"AC25: a CLI that is not installed ends the step naming the activity, the CLI and the model",
		function()
			fakecli.clear(h)
			fs.move(`{h.bin}/claude`, `{h.bin}/claude.off`)
			local r = zn(
				{ "dispatch", "z-design", "c0010", "--cli", "claude" },
				{ PATH = `{h.bin}:/usr/bin:/bin` }
			)
			fs.move(`{h.bin}/claude.off`, `{h.bin}/claude`)
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stderr,
					"claude is not installed (the claude CLI), so design/normal on claude-sonnet-5-5-medium cannot run"
				)
			).toBe(true)
			t.expect(log()).toBe("")
			local s = fakecli.state(h, "c0010")
			t.expect(s.outcome).toBe("failed")
			t.expect(s.history[#s.history].outcome).toBe("missing")
		end
	)

	it(
		"AC25: a CLI that cannot deliver the step starts nothing, spends zero tokens and names the need",
		function()
			fakecli.clear(h)
			-- c0020 is risky: design needs heavy, which grok does not define
			local r = zn({ "dispatch", "z-design", "c0020", "--cli", "grok" })
			t.expect(r.code).toBe(1)
			t.expect(
				has(
					r.stderr,
					"grok cannot deliver design/risky (heavy): grok does not define heavy; start a worker whose CLI has heavy (claude, agent, kimi), or set --cli"
				)
			).toBe(true)
			t.expect(log()).toBe("")
			local s = fakecli.state(h, "c0020")
			t.expect(s.outcome).toBe("undeliverable")
			t.expect(s.tokens).toBe(0)
			t.expect(s.history[#s.history].tokens).toBe(0)
			t.expect(fakecli.rows(h, "c0020")).toBe(nil)
		end
	)

	it(
		"AC25: --dry-run prints the one line the step would start, or the refusal, and starts nothing",
		function()
			fakecli.clear(h)
			local claude = zn({ "dispatch", "z-design", "c0010", "--dry-run", "--cli", "claude" })
			t.expect(lines(claude.stdout)).toEqual({
				"step=z-design id=c0010 kind=model",
				"cli=claude runtime=claude-cli model=claude-sonnet-5-5-medium max_tokens=5000",
			})
			local grok = zn({ "dispatch", "z-design", "c0010", "--dry-run", "--cli", "grok" })
			t.expect(lines(grok.stdout)[2])
				.toBe("cli=grok runtime=grok-cli model=grok-4.7-high max_tokens=5000")
			local refused = zn({ "dispatch", "z-design", "c0020", "--dry-run", "--cli", "grok" })
			t.expect(refused.ok).toBe(true)
			t.expect(lines(refused.stdout)[2]).toBe(
				"refused: grok cannot deliver design/risky (heavy): grok does not define heavy; start a worker whose CLI has heavy (claude, agent, kimi), or set --cli"
			)
			local bogus = zn({ "dispatch", "z-design", "c0010", "--dry-run", "--cli", "opencode" })
			t.expect(bogus.ok).toBe(false)
			t.expect(has(bogus.stderr, "--cli opencode is not a supported CLI (claude, grok, agent, kimi)"))
				.toBe(true)
			t.expect(log()).toBe("")
			t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/c0010/state.json`)).toBe(true) -- the earlier cases' runs; no new one
		end
	)

	it(
		"AC25: a reviewer is refused on the model the item's latest writer row names, and a missing row is said",
		function()
			fakecli.clear(h)
			-- c0010's prep rows say the design was written by claude-opus-5-5-high; design-review normal is heavy: the same model
			local dir = `{h.f.main}/pickman/.tracker/issues/c0010`
			local row: ledger.Row = {
				when = "2026-11-21 10:00",
				subject = "design",
				added = 0,
				removed = 0,
				minutes = 0,
				how = "explicit",
				phase = "prep",
				tokens = 10,
				model = "claude-opus-5-5-high",
			}
			fs.writeFile(`{dir}/spend.md`, ledger.append(nil, "c0010", "first-thing", row))
			local same =
				zn({ "dispatch", "zz-review", "c0010", "--mode", "design", "--dry-run", "--cli", "claude" })
			fs.removeFile(`{dir}/spend.md`)
			t.expect(same.ok).toBe(true)
			t.expect(
				has(
					same.stdout,
					"refused: design-review: the only model left is the author's (claude-opus-5-5)"
				)
			).toBe(true)
			t.expect(has(same.stdout, "note:")).toBe(false)
			-- no row: it proceeds, and says it could not read the writer's model
			local none =
				zn({ "dispatch", "zz-review", "c0030", "--mode", "design", "--dry-run", "--cli", "claude" })
			t.expect(none.ok).toBe(true)
			t.expect(has(none.stdout, "cli=claude runtime=claude-cli model=claude-opus-5-5-high")).toBe(true)
			t.expect(
				has(
					none.stdout,
					"note: the writer's model could not be read (c0030 has no prep spend row with a model)"
				)
			).toBe(true)
			t.expect(log()).toBe("")
		end
	)

	it(
		"AC24: today's legacy file starts what it starts today on the role's own CLI, and --cli names another",
		function()
			local legacy = fakecli.new("f0421-dispatch-legacy", {
				[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
				["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			})
			local function dry(args: { string }): { string }
				local argv = { "dispatch" }
				for _, a in args do
					table.insert(argv, a)
				end
				table.insert(argv, "--dry-run")
				return lines(fakecli.zn(legacy, argv).stdout)
			end
			t.expect(dry({ "z-design", "c0010" })[2])
				.toBe("cli=claude runtime=claude-cli model=claude-opus-5-5-high max_tokens=3000000")
			t.expect(dry({ "z-run", "c0010" })[2])
				.toBe("cli=claude runtime=claude-cli model=claude-sonnet-5-5-high max_tokens=12000000")
			t.expect(dry({ "zz-review", "c0010", "--mode", "code" })[2])
				.toBe("cli=claude runtime=claude-cli model=claude-opus-5-5-xhigh max_tokens=2000000")
			t.expect(dry({ "zz-review", "c0010", "--mode", "final" })[2])
				.toBe("cli=claude runtime=claude-cli model=claude-fable-5-2-xhigh max_tokens=2000000")
			-- a fallback of the role names a CLI that can deliver it
			t.expect(dry({ "z-design", "c0010", "--cli", "grok" })[2])
				.toBe("cli=grok runtime=grok-cli model=grok-4.7-high max_tokens=3000000")
			t.expect(dry({ "z-design", "c0010", "--cli", "kimi" })[2])
				.toBe("cli=kimi runtime=kimi-cli model=kimi-code-k3.1-pro-high max_tokens=3000000")
			fakecli.clear(legacy)
		end
	)

	it(
		"AC25: ./zn idea runs on one CLI: a new-shape walk needs --cli, and a CLI that cannot deliver starts nothing",
		function()
			local f = trackerfix.new("f0421-idea", { [".models.toml"] = SEED })
			local bin = `{f.base}/bin`
			fs.writeDir(bin)
			fs.writeFile(`{bin}/claude`, IDEA_CLAUDE)
			process.exec("chmod", { "+x", `{bin}/claude` })
			local logPath = `{f.base}/idea-stub.log`
			local wt = trackerfix.trOk(f, f.main, { "worktree", "idea-run" })
			trackerfix.trOk(f, wt, { "sync" })
			local id = string.match(
				trackerfix.trOk(f, wt, { "new", "issue", "c", "one-cli-idea", "--project", "pickman" }),
				"(c%d+)"
			) :: string
			local env = { PATH = `{bin}:{process.env.PATH or ""}`, IDEA_STUB_LOG = logPath, ZN_CLI = "" }
			local none = trackerfix.tr(f, wt, { "idea", id, "--text", "The board hides a card." }, env)
			t.expect(none.ok).toBe(false)
			t.expect(has(none.stderr, "idea: which CLI runs idea? pass --cli <name> or set ZN_CLI"))
				.toBe(true)
			t.expect(fs.isFile(logPath)).toBe(false)
			-- grok defines light only: idea needs heavy, so grok starts nothing, before the draft spends a token
			local grok = trackerfix.tr(
				f,
				wt,
				{ "idea", id, "--text", "The board hides a card.", "--cli", "grok" },
				env
			)
			t.expect(grok.ok).toBe(false)
			t.expect(
				has(
					grok.stderr,
					"grok cannot deliver idea/normal (heavy): grok does not define heavy; start a worker whose CLI has heavy (claude, agent, kimi), or set --cli"
				)
			).toBe(true)
			t.expect(fs.isFile(logPath)).toBe(false)
			-- claude delivers both: the draft on heavy, the challenge on ultra
			local ran = trackerfix.tr(
				f,
				wt,
				{ "idea", id, "--text", "The board hides a card.", "--cli", "claude" },
				env
			)
			if not ran.ok then
				error(`idea failed ({ran.code}): {ran.stderr}{ran.stdout}`, 0)
			end
			t.expect(has(ran.stdout, "idea: idea model claude-opus-5-5-high")).toBe(true)
			t.expect(has(ran.stdout, "idea: idea-challenge model claude-fable-5-2-xhigh")).toBe(true)
			t.expect(count(fs.readFile(logPath), "--model claude-opus-5-5")).toBe(1)
			t.expect(count(fs.readFile(logPath), "--model claude-fable-5-2")).toBe(1)
		end
	)
end)
