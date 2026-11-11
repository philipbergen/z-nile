--!strict
-- Measured cost: the report line, the transcript readers, and spend rows old and new. A measured row lives in its
-- own file; an old spend.md's typed minutes stay reported, apart from wall, cpu, ai and test.
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

	it("keeps two row files for one ticket, the way a merge of two checkouts does", function()
		local dir = `.cache/measure-spec-{string.gsub(tostring(os.clock()), "%.", "")}`
		fs.writeDir(dir)
		local first = costrow.write({
			root = ".",
			id = "branch-a",
			phase = "test",
			subject = "one",
			dir = dir,
			wall = 1,
			cpu = 0.1,
			test = 1,
		})
		local second = costrow.write({
			root = ".",
			id = "branch-a",
			phase = "build",
			subject = "two",
			dir = dir,
			wall = 2,
			cpu = 0.2,
		})
		t.expect(first ~= nil).toBe(true)
		t.expect(second ~= nil).toBe(true)
		t.expect(first ~= second).toBe(true)
		local rows: { ledger.Row } = {}
		for _, name in fs.readDir(`{dir}/spend.d`) do
			local doc = ledger.parse(fs.readFile(`{dir}/spend.d/{name}`))
			t.expect(doc ~= nil).toBe(true)
			for _, row in (doc :: any).rows do
				table.insert(rows, row)
			end
		end
		t.expect(#rows).toBe(2)
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
