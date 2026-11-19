--!strict
-- c0253 AC1, AC4, AC5, AC6, AC9, AC10: the supervisor's pure rules (supervise.luau): what `./zn next` printed and what a
-- dispatch run's exit code asks of the loop, the environment the dispatcher child starts in, the refusals at start, the
-- state file, the detached start, and the dispatcher's worker mode (the CLI order, the session record, the prompts, the quota
-- cap and its note). No process, no file, no clock.
local escalation = require("@znile/engine/escalation")
local models = require("@znile/engine/models")
local supervise = require("@znile/engine/supervise")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local NOTHING = "next: nothing to take: no claimable raft"
local TRACE = "error: tracker next: main.luau:7790: attempt to index nil\nstack traceback:"

return t.spec("c0253 the supervisor's pure rules", function(it)
	it("AC1: reads the one line next prints as a pick, for each of the four kinds", function()
		for _, kind in { "lost", "raft", "rafting", "draft" } do
			local r = supervise.parseNext(`c0301 {kind} its heartbeat is stale\n`, "", 0)
			t.expect(r.kind).toBe("pick")
			t.expect((r.pick :: supervise.Pick).kind).toBe(kind)
			t.expect((r.pick :: supervise.Pick).id).toBe("c0301")
			t.expect((r.pick :: supervise.Pick).why).toBe("its heartbeat is stale")
		end
		t.expect((supervise.parseNext("R0010 raft rank 3", "", 0).pick :: supervise.Pick).id).toBe("R0010")
	end)

	it("AC1: nothing claimable is exit 1 with c0249's own stderr line, and nothing else", function()
		local none = supervise.parseNext("", NOTHING, 1)
		t.expect(none.kind).toBe("none")
		t.expect(has(none.why, "no claimable raft")).toBe(true)
	end)

	it("AC9: every other outcome of next is a failed read, never a pick and never nothing", function()
		local cases: { { string | number } } = {
			{ "", "", 1 }, -- exit 1 with no c0249 line: a crash or a refusal
			{ "", TRACE, 1 }, -- Lune's own exit 1
			{ "", "fatal: unable to access origin: could not resolve host", 128 },
			{ "", "", 0 },
			{ "R0010 raft rank 1\nR0020 raft rank 2", "", 0 },
			{ "R0010 maybe because", "", 0 },
			{ "R0010", "", 0 },
			{ "something went wrong", "", 0 },
			{ "R0010 raft rank 1", NOTHING, 1 },
		}
		for _, c in cases do
			local r = supervise.parseNext(c[1] :: string, c[2] :: string, c[3] :: number)
			if c[1] == "R0010 raft rank 1" and c[3] == 1 then
				t.expect(r.kind).toBe("none") -- c0249's line decides, whatever is on stdout
			else
				t.expect(r.kind).toBe("failed")
				t.expect(r.pick).toBe(nil)
				t.expect(r.why ~= "").toBe(true)
			end
		end
		local named = supervise.parseNext("R0010 maybe because", "", 0)
		t.expect(has(named.why, "maybe")).toBe(true)
	end)

	it("AC1: a pick is run by one dispatcher call, in the documented argument order", function()
		local pick: supervise.Pick = { id = "R0010", kind = "raft", why = "" }
		t.expect(supervise.dispatchArgs(pick, { cli = nil, noRun = false, retry = false }))
			.toEqual({ "dispatch", "R0010", "--worker" })
		t.expect(supervise.dispatchArgs(pick, { cli = "kimi", noRun = true, retry = false }))
			.toEqual({ "dispatch", "R0010", "--worker", "--cli", "kimi", "--no-run" })
		t.expect(supervise.dispatchArgs(pick, { cli = "kimi", noRun = false, retry = true }))
			.toEqual({ "dispatch", "retry", "R0010", "--worker", "--cli", "kimi" })
	end)

	it("AC4: what a dispatch run's exit code asks of the loop", function()
		local E = supervise.EXIT
		t.expect(supervise.afterDispatch("raft", E.done, 0).kind).toBe("done")
		t.expect(supervise.afterDispatch("raft", E.user, 0).kind).toBe("blocked")
		t.expect(supervise.afterDispatch("raft", E.gate, 0).kind).toBe("wait")
		t.expect(supervise.afterDispatch("rafting", E.gate, 0).kind).toBe("wait")
		t.expect(supervise.afterDispatch("draft", E.gate, 0).kind).toBe("park")
		t.expect(supervise.afterDispatch("raft", E.tripwire, 0).kind).toBe("stop")
		t.expect(supervise.afterDispatch("raft", E.failure, 0).kind).toBe("retry")
		t.expect(supervise.afterDispatch("raft", E.failure, 1).kind).toBe("stop")
		t.expect(supervise.afterDispatch("raft", 2, 0).kind).toBe("stop")
		t.expect(supervise.afterDispatch("raft", 137, 0).kind).toBe("stop")
	end)

	it("AC6: the dispatcher child starts without the starter's markers and session ids", function()
		local base: { [string]: string? } = {
			PATH = "/bin",
			CLAUDECODE = "1",
			AI_AGENT = "claude",
			CLAUDE_CODE_SESSION_ID = "person-session",
			KIMI_SESSION_ID = "k1",
			KIMI_CODE_SESSION_ID = "k2",
			ZN_DISPATCH = "1",
			ZN_DISPATCH_DIR = "/x",
			ZN_HEADLESS = "1",
			ZN_MODEL = "m",
			ZN_PUBLISH_BROKER = "/b",
		}
		local argv = supervise.cleanArgv(base, "/top/zn", { "dispatch", "R0010" })
		t.expect(argv[1]).toBe("env")
		for _, name in
			{
				"CLAUDECODE",
				"AI_AGENT",
				"CLAUDE_CODE_SESSION_ID",
				"KIMI_SESSION_ID",
				"KIMI_CODE_SESSION_ID",
				"ZN_DISPATCH",
				"ZN_DISPATCH_DIR",
				"ZN_HEADLESS",
				"ZN_MODEL",
				"ZN_PUBLISH_BROKER",
			}
		do
			local at = table.find(argv, name)
			t.expect(at ~= nil and argv[(at :: number) - 1] == "-u").toBe(true)
		end
		t.expect(table.find(argv, "PATH")).toBe(nil)
		t.expect({ table.unpack(argv, #argv - 2) }).toEqual({ "/top/zn", "dispatch", "R0010" })
		-- only what the starter holds is listed
		t.expect(supervise.cleanArgv({ PATH = "/bin" }, "/top/zn", { "next" }))
			.toEqual({ "env", "/top/zn", "next" })
	end)

	it(
		"AC9: the CLI the person started is the one the supervisor runs, and it must be one every role has",
		function()
			t.expect(supervise.starterCli({ CLAUDECODE = "1" })).toBe("claude")
			t.expect(supervise.starterCli({ CLAUDE_CODE_SESSION_ID = "abc" })).toBe("claude")
			t.expect(supervise.starterCli({ KIMI_SESSION_ID = "abc" })).toBe("kimi")
			t.expect(supervise.starterCli({ PATH = "/bin" })).toBe(nil)
			local roles =
				{ implementation = { "claude", "kimi" }, design = { "claude" }, raft = { "claude", "grok" } }
			t.expect(supervise.cliProblem("claude", roles)).toBe(nil)
			local bad = supervise.cliProblem("kimi", roles) :: string
			t.expect(has(bad, "kimi") and has(bad, "design")).toBe(true)
			t.expect(supervise.cliProblem("agy", roles) ~= nil).toBe(true)
		end
	)

	it(
		"AC9: the supervisor starts only in the main checkout and never inside a session or (detached) a check",
		function()
			local ok: supervise.Start =
				{ headless = nil, dispatch = nil, checking = false, detach = false, here = "/m", main = "/m" }
			t.expect(supervise.refusal(ok)).toBe(nil)
			t.expect(has(
				supervise.refusal({
					headless = "1",
					dispatch = nil,
					checking = false,
					detach = false,
					here = "/m",
					main = "/m",
				}) :: string,
				"headless"
			)).toBe(true)
			t.expect(has(
				supervise.refusal({
					headless = nil,
					dispatch = "1",
					checking = false,
					detach = true,
					here = "/m",
					main = "/m",
				}) :: string,
				"dispatched"
			)).toBe(true)
			t.expect(has(
				supervise.refusal({
					headless = nil,
					dispatch = nil,
					checking = true,
					detach = true,
					here = "/m",
					main = "/m",
				}) :: string,
				"check"
			)).toBe(true)
			t.expect(supervise.refusal({
				headless = nil,
				dispatch = nil,
				checking = true,
				detach = false,
				here = "/m",
				main = "/m",
			})).toBe(nil)
			local elsewhere = supervise.refusal({
				headless = nil,
				dispatch = nil,
				checking = false,
				detach = false,
				here = "/m/.worktree/R1",
				main = "/m",
			}) :: string
			t.expect(has(elsewhere, "main checkout: /m")).toBe(true)
		end
	)

	it(
		"AC8: a host the person marked as one that does not land keeps the run gate off; anything unreadable fails closed",
		function()
			t.expect(supervise.hostLand(nil)).toBe(true)
			t.expect(supervise.hostLand("[work]\nland = true\n")).toBe(true)
			t.expect(supervise.hostLand("[work]\nland = false\n")).toBe(false)
			t.expect(supervise.hostLand("[work]\nland = maybe\n")).toBe(false)
			t.expect(supervise.hostLand("[work]\n")).toBe(true)
		end
	)

	it("AC8: the run gate (the landing) is the only gate a host that does not land drops", function()
		t.expect(supervise.gates({ "prep", "raft", "run" }, false)).toEqual({ "prep", "raft", "run" })
		t.expect(supervise.gates({ "prep", "raft", "run" }, true)).toEqual({ "prep", "raft" })
		t.expect(supervise.gates({}, true)).toEqual({})
	end)

	it("AC5: the person's CLI is tried first, and the first is waited for once before the next", function()
		local specs = { { cli = "claude" }, { cli = "kimi" }, { cli = "grok" } }
		local function cliOf(s: { cli: string }): string
			return s.cli
		end
		local plain = supervise.order(specs, cliOf, nil, {})
		t.expect(#plain).toBe(3)
		t.expect(plain[1].spec.cli).toBe("claude")
		local first = supervise.order(specs, cliOf, "kimi", {})
		t.expect(first[1].spec.cli).toBe("kimi")
		t.expect(first[2].spec.cli).toBe("claude")
		local waited = supervise.order(specs, cliOf, "kimi", { kimi = 600 })
		t.expect(#waited).toBe(4)
		t.expect(waited[2].spec.cli).toBe("kimi")
		t.expect(waited[2].afterWait).toBe(true)
		t.expect(waited[1].afterWait).toBe(false)
		-- a wait set for a CLI that is not first adds nothing
		t.expect(#supervise.order(specs, cliOf, "kimi", { grok = 600 })).toBe(3)
	end)

	it(
		"AC5: an outage is one unbroken stretch, and only past the cap is it a block; the note it files parses",
		function()
			t.expect(supervise.allOut(nil, 1000, 3600).kind).toBe("wait")
			t.expect(supervise.allOut(nil, 1000, 3600).since).toBe(1000)
			t.expect(supervise.allOut(1000, 4599, 3600).kind).toBe("wait")
			t.expect(supervise.allOut(1000, 4600, 3600).kind).toBe("block")
			t.expect(supervise.allOut(1000, 999999, nil).kind).toBe("wait")
			local text = supervise.quotaEscalation("R0010", { "claude", "kimi" }, 90000)
			local note, why = escalation.parse(text)
			t.expect(why).toBe(nil)
			t.expect(escalation.check(note :: escalation.Note)).toBe(nil)
			t.expect(has(text, "25 hours")).toBe(true)
		end
	)

	it(
		"AC2: one CLI session per raft: the same CLI resumes it, another CLI starts a new one that reads the notes",
		function()
			t.expect(supervise.sessionMode(nil, "claude")).toBe("new")
			t.expect(supervise.sessionMode({ cli = "claude", id = "" }, "claude")).toBe("new")
			t.expect(supervise.sessionMode({ cli = "claude", id = "s1" }, "claude")).toBe("resume")
			t.expect(supervise.sessionMode({ cli = "claude", id = "s1" }, "kimi")).toBe("switched")
			t.expect(supervise.notesPath("z-nile/.tracker/rafts/active/R0010"))
				.toBe("z-nile/.tracker/rafts/active/R0010/notes.md")
		end
	)

	it(
		"AC5: every prompt of a worker session names its skill and the notes, a resumed one says it has read it",
		function()
			local skill, notes = "z-nile/skills/z-run/SKILL.md", "z-nile/.tracker/rafts/active/R0010/notes.md"
			for _, mode in { "new", "resume", "switched" } do
				local p = supervise.sessionPrompt(mode, "R0010", skill, notes, "claude")
				t.expect(has(p, skill) or mode == "new").toBe(true)
				t.expect(has(p, notes)).toBe(true)
				t.expect(has(p, "R0010") or mode == "new").toBe(true)
			end
			t.expect(has(supervise.sessionPrompt("resume", "R0010", skill, notes, ""), "you have read"))
				.toBe(true)
			local switched = supervise.sessionPrompt("switched", "R0010", skill, notes, "claude")
			t.expect(has(switched, "taken over from a session on claude")).toBe(true)
			t.expect(has(switched, "read it now")).toBe(true)
		end
	)

	it(
		"AC6: every supported CLI has a resume row, and a resumed session swaps or appends the flag",
		function()
			for _, cli in models.CLIS do
				t.expect(supervise.RESUME[cli] ~= nil).toBe(true)
			end
			t.expect(supervise.RESUME.agy ~= nil and supervise.RESUME.opencode ~= nil).toBe(true)
			local claude = { "claude", "-p", "prompt", "--session-id", "S1", "--model", "m" }
			t.expect((supervise.withSession(claude, "claude", "S1", false))).toEqual(claude)
			local resumed = supervise.withSession(claude, "claude", "S1", true) :: { string }
			t.expect(table.find(resumed, "--session-id")).toBe(nil)
			t.expect(resumed[table.find(resumed, "--resume") :: number + 1]).toBe("S1")
			t.expect(#resumed).toBe(#claude)
			local agent =
				supervise.withSession({ "agent", "-p", "prompt" }, "agent", "chat-7", true) :: { string }
			t.expect(agent[#agent - 1]).toBe("--resume")
			t.expect(agent[#agent]).toBe("chat-7")
			local kimi = supervise.withSession({ "kimi", "-p", "x" }, "kimi", "k1", true) :: { string }
			t.expect(kimi[#kimi - 1]).toBe("-S")
			local none, why = supervise.withSession({ "zed" }, "zed", "x", true)
			t.expect(none).toBe(nil)
			t.expect(has(why :: string, "zed")).toBe(true)
		end
	)

	it("AC10: the state file reads back what was written, and a stale one is called ended", function()
		local s: supervise.State = {
			pid = 4242,
			state = "working",
			item = "R0010",
			cli = "claude",
			since = "2026-11-16 09:00:00",
			moved = 2,
			blocked = 1,
			held = "R0010",
		}
		t.expect(supervise.parseState(supervise.stateText(s))).toEqual(s)
		t.expect(supervise.parseState("pid: x\nstate: idle\n")).toBe(nil)
		local live = supervise.statusLine(s, true, false)
		t.expect(
			has(
				live,
				"pid 4242: working on R0010 using claude since 2026-11-16 09:00:00; moved 2, blocked 1; holds R0010"
			)
		).toBe(true)
		t.expect(has(supervise.statusLine(s, false, false), "ended without a summary")).toBe(true)
		t.expect(has(supervise.statusLine(s, false, true), "ended (see the log)")).toBe(true)
		local stopped: supervise.State = {
			pid = 4242,
			state = "stopped",
			item = "",
			cli = "",
			since = "t",
			moved = 1,
			blocked = 0,
			held = "R0010",
		}
		t.expect(has(supervise.statusLine(stopped, false, true), "pid 4242: stopped")).toBe(true)
		t.expect(
			has(supervise.statusLine(stopped, false, true), "R0010 stays held: ./zn work run resumes it")
		)
			.toBe(true)
	end)

	it(
		"AC10: the detached start leaves its own session, clears the markers and keeps the flags in the order typed",
		function()
			local argv = supervise.detachArgv(
				"/top/zn",
				{ "work", "--max-items", "3", "--detach", "--cli", "claude" },
				"/top/.cache/work/log",
				{ CLAUDECODE = "1" }
			)
			t.expect(argv[1]).toBe("perl")
			t.expect(has(argv[3], "setsid") and has(argv[3], "fork")).toBe(true)
			t.expect(argv[4]).toBe("/top/.cache/work/log")
			t.expect({ table.unpack(argv, 5) }).toEqual({
				"env",
				"-u",
				"CLAUDECODE",
				"/top/zn",
				"work",
				"run",
				"--max-items",
				"3",
				"--cli",
				"claude",
			})
			t.expect(table.find(argv, "--detach")).toBe(nil)
		end
	)

	it("AC10: the summary names what moved and what blocked", function()
		local text =
			supervise.summary({ moved = { "R0010", "R0020" }, blocked = { "R0030" }, stopped = "stop asked" })
		t.expect(has(text, "worker stopped: stop asked")).toBe(true)
		t.expect(has(text, "moved: R0010, R0020")).toBe(true)
		t.expect(has(text, "blocked: R0030")).toBe(true)
		t.expect(has(supervise.summary({ moved = {}, blocked = {}, stopped = "x" }), "moved: nothing"))
			.toBe(true)
	end)
end)
