--!strict
-- Measured cost: the report line, the transcript readers, and spend rows old and new. A measured row lives in its
-- own file; an old spend.md's typed minutes stay reported, apart from wall, cpu, ai and test.
local buffer = require("@znile/engine/buffer")
local costrow = require("@znile/engine/costrow")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local sessions = require("@znile/engine/sessions")
local t = require("@tests/lib/t")

local OLD = "# Spend: c0001 old\n\n"
	.. "| # | when | commit | +lines | -lines | minutes | attribution | phase | tokens |\n"
	.. "|---|---|---|---|---|---|---|---|---|\n"
	.. "| 1 | 2026-01-01 00:00 | typed | 3 | 1 | 12.5 | explicit | build | 9 |\n"

return t.spec("measured cost", function(it)
	it("reads a runner report and keeps an old ledger's minutes as reported", function()
		local wall, cpu = costrow.report("wall=1.250 cpu=0.040\n")
		t.expect(wall).toBe(1.25)
		t.expect(cpu).toBe(0.04)
		local doc = ledger.parse(OLD)
		t.expect(doc ~= nil).toBe(true)
		local rows = (doc :: any).rows
		t.expect(rows[1].minutes).toBe(12.5)
		t.expect(rows[1].tokens).toBe(9)
		local cost = ledger.cost(rows)
		t.expect(cost.reported).toBe(12.5)
		t.expect(cost.wall).toBe(0)
		t.expect(cost.n).toBe(1)
		t.expect(cost.tokensOpen).toBe(false)
	end)

	it("round-trips a measured row and does not count its minutes as reported", function()
		local text = ledger.render("c0001", "c0001", {
			{
				when = "2026-11-10 16:00",
				subject = "gate",
				added = 0,
				removed = 0,
				minutes = 0,
				how = "measured",
				phase = "test",
				tokens = nil,
				model = nil,
				wall = 1.25,
				cpu = 0.04,
				ai = nil,
				test = 1.25,
				unmeasured = "ai,tokens",
			},
		})
		local doc = ledger.parse(text)
		t.expect(doc ~= nil).toBe(true)
		local row = (doc :: any).rows[1]
		t.expect(row.phase).toBe("test")
		t.expect(row.wall).toBe(1.25)
		t.expect(row.cpu).toBe(0.04)
		t.expect(row.test).toBe(1.25)
		t.expect(row.unmeasured).toBe("tokens,ai")
		t.expect(row.tokens).toBe(nil)
		local cost = ledger.cost((doc :: ledger.Ledger).rows)
		t.expect(cost.reported).toBe(0)
		t.expect(cost.wall).toBe(1.25)
		t.expect(cost.test).toBe(1.25)
		t.expect(cost.aiOpen).toBe(true)
		t.expect(cost.tokensOpen).toBe(true)
		local both = ledger.cost({
			(ledger.parse(OLD) :: any).rows[1],
			row,
		})
		t.expect(both.reported).toBe(12.5)
		t.expect(both.n).toBe(2)
		t.expect(both.tokens).toBe(9)
	end)

	it("folds runs of one stage into one row and leaves another ticket's line", function()
		local function line(
			ms: number,
			kind: string,
			phase: string,
			subject: string,
			wall: number,
			id: string
		): buffer.Line
			return {
				ms = ms,
				kind = kind,
				phase = phase,
				subject = subject,
				wall = wall,
				cpu = wall / 10,
				test = if phase == "test" then wall else nil,
				id = id,
				branch = "capture-a",
				head = "abc",
			}
		end
		local lines = {
			line(1_000, "run", "other", "run", 1, ""),
			line(2_000, "run", "other", "run", 2, ""),
			line(3_000, "run", "other", "run", 3, ""),
			line(4_000, "test", "test", "affected", 10, ""),
			line(5_000, "test", "test", "affected", 1, "c0099"),
		}
		local folded = buffer.fold(lines, { "c0010" }, "capture-a", "abc", 6_000, false)
		local rows = folded.rows["c0010"]
		t.expect(rows ~= nil).toBe(true)
		local got = rows :: { ledger.Row }
		t.expect(#got).toBe(2)
		t.expect(got[1].phase).toBe("test")
		t.expect(got[1].subject).toBe("affected")
		t.expect(got[1].test).toBe(10)
		t.expect(got[2].phase).toBe("other")
		t.expect(got[2].subject).toBe("3 runs")
		t.expect(got[2].wall).toBe(6)
		t.expect(got[2].unmeasured).toBe("tokens,ai")
		t.expect(#folded.kept).toBe(1)
		t.expect(folded.kept[1].id).toBe("c0099")
		local detached = buffer.fold({
			{
				ms = 1_000,
				kind = "run",
				phase = "other",
				subject = "run",
				wall = 1,
				cpu = 0.1,
				id = "",
				branch = "",
				head = "deadbeef",
			},
		}, { "c0010" }, "", "deadbeef", 2_000, false)
		t.expect(detached.rows["c0010"] ~= nil).toBe(true)
		t.expect(#detached.kept).toBe(0)
		local elsewhere = buffer.fold({
			{
				ms = 1_000,
				kind = "run",
				phase = "other",
				subject = "run",
				wall = 1,
				cpu = 0.1,
				id = "",
				branch = "",
				head = "deadbeef",
			},
		}, { "c0010" }, "main", "other", 2_000, false)
		t.expect(elsewhere.rows["c0010"]).toBe(nil)
		t.expect(#elsewhere.kept).toBe(1)
		local aged = buffer.fold({
			line(1, "run", "other", "run", 1, ""),
		}, { "c0010" }, "capture-a", "abc", buffer.AGE_MS + 100, false)
		t.expect(aged.rows["c0010"]).toBe(nil)
		t.expect(#aged.kept).toBe(0)
		local a = buffer.appendTsv(nil, { got[1] })
		local b = buffer.appendTsv(nil, { got[2] })
		t.expect(string.sub(a, 1, #buffer.HEADER)).toBe(buffer.HEADER)
		t.expect(a ~= b).toBe(true)
		local parsed = buffer.parseTsv(a)
		t.expect(parsed ~= nil).toBe(true)
		t.expect(#(parsed :: { ledger.Row })).toBe(1)
	end)

	it("reads claude usage and grok turns, and leaves a cursor transcript unmeasured", function()
		t.expect(sessions.delta("2026-11-03T23:33:10.000Z", "2026-11-03T23:33:14.633Z"))
			.toBeNear(4.633, 0.001)
		local claude = sessions.claude(
			'{"type":"user","timestamp":"2026-11-03T23:33:10.000Z"}\n'
				.. '{"type":"assistant","timestamp":"2026-11-03T23:33:14.633Z","message":{"model":"claude-opus-4","usage":{"input_tokens":2,"cache_creation_input_tokens":10,"cache_read_input_tokens":99,"output_tokens":4}}}\n',
			"2026-11-03T23:33:00.000Z",
			"2026-11-03T23:34:00.000Z"
		)
		t.expect(claude ~= nil).toBe(true)
		local c = claude :: any
		t.expect(c.tokens).toBe(16) -- input + cache writes + output; cache reads left out, as the adapter does
		t.expect(c.inn).toBe(2)
		t.expect(c.out).toBe(4)
		t.expect(c.ai).toBeNear(4.633, 0.001)
		t.expect(c.model).toBe("claude-opus-4")
		local grok = sessions.grokUpdates(
			'{"timestamp":100,"update":{"_meta":{"totalTokens":10}}}\n{"timestamp":101,"update":{"_meta":{"totalTokens":25}}}\n{"timestamp":102,"update":{"_meta":{"totalTokens":4}}}\n',
			100,
			200
		)
		t.expect((grok :: any).tokens).toBe(29) -- 10, then +15, then a new turn's 4
		local turns = sessions.grokEvents(
			'{"ts":"2026-11-03T23:33:10.000Z","type":"turn_started","model_id":"grok-4"}\n{"ts":"2026-11-03T23:33:12.500Z","type":"turn_ended"}\n',
			"2026-11-03T23:33:00.000Z",
			"2026-11-03T23:34:00.000Z"
		)
		t.expect((turns :: any).ai).toBeNear(2.5, 0.001)
		t.expect(sessions.cursor('{"role":"assistant","message":{"content":[]}}\n')).toBe(nil)
		local read = sessions.combine({
			{ cli = "claude", part = c },
			{ cli = "agent", part = nil },
		})
		t.expect(read.tokens).toBe(16)
		t.expect(string.find(read.note, "agent unmeasured", 1, true) ~= nil).toBe(true)
		t.expect(read.unmeasured).toBe(nil)
		local none = sessions.combine({ { cli = "agent", part = nil } })
		t.expect(none.unmeasured).toBe("tokens,ai")
		t.expect(none.tokens).toBe(nil)
	end)

	it("the supervised runner writes wall and cpu for a command", function()
		local dir = `.cache/measure-report-{string.gsub(tostring(os.clock()), "%.", "")}`
		local report = `{dir}/report.txt`
		fs.writeDir(dir)
		local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
		local ran = process.exec("perl", {
			`{root}/z-nile/lib/bounded.pl`,
			"--report",
			report,
			"--time",
			"10",
			"--",
			"perl",
			"-e",
			"select(undef, undef, undef, 0.3)",
		})
		t.expect(ran.ok).toBe(true)
		local wall, cpu = costrow.report(fs.readFile(report))
		t.expect(wall ~= nil).toBe(true)
		t.expect((wall :: number) >= 0.2).toBe(true)
		t.expect((wall :: number) < 5).toBe(true)
		t.expect(cpu ~= nil).toBe(true)
		t.expect((cpu :: number) >= 0).toBe(true)
	end)
end)
