--!strict
-- c0256 AC1 and AC2: the exchange of a dispatched run, pure. `exchange.luau` names, renders, parses and orders the
-- messages between the user and a run's steps (one file each, dated, the message exactly as written), and
-- `dispatch.prompt` names those files, in order, in the prompt of a re-run step (and adds nothing to a first run's).
local dispatch = require("@znile/engine/dispatch")
local exchange = require("@znile/engine/exchange")
local t = require("@tests/lib/t")

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local DATE = "2026-11-09T10:11:12Z"

local function order(names: { string }): ({ string }?, string?)
	return exchange.order(names)
end

-- the first message of every legal exchange, then the legal continuations
local function failsWith(names: { string }, needle: string)
	local got, why = order(names)
	t.expect(got).toBe(nil)
	if not has(why or "", needle) then
		error(`order {table.concat(names, ",")} should say "{needle}", said "{why}"`)
	end
end

return t.spec("c0256 the exchange of a dispatched run", function(it)
	it("AC1: a file name says its number and kind, and nothing else is a name", function()
		t.expect(exchange.name(1, "ask")).toBe("001-ask.md")
		t.expect(exchange.name(12, "question")).toBe("012-question.md")
		t.expect(exchange.name(999, "answer")).toBe("999-answer.md")
		local n, kind = exchange.parseName("012-question.md")
		t.expect(n).toBe(12)
		t.expect(kind).toBe("question")
		for _, bad in
			{
				"1-ask.md",
				"0001-ask.md",
				"001-reply.md",
				"001-ask.txt",
				"001-ask.md.tmp",
				"001-Ask.md",
				"a01-ask.md",
				"001-ask",
				"questions.md",
				"",
			}
		do
			local bn, bk = exchange.parseName(bad)
			if bn ~= nil or bk ~= nil then
				error(`{bad} should not be an exchange file name`)
			end
		end
	end)

	it("AC1: a message is kept exactly as written, behind a date line and one blank line", function()
		for _, body in
			{
				"",
				"a\n",
				"no newline at the end",
				"two\n\nblank lines\n\n",
				"date: 2020-01-01T00:00:00Z\n\nlooks like a header",
				"```\na fence\n```\n",
				"windows\r\nlines\r\n",
				"## Q1\nWhich scope?\n",
				"  leading spaces and a tab\t",
			}
		do
			local text = exchange.render(DATE, body)
			t.expect(string.sub(text, 1, 28)).toBe(`date: {DATE}\n\n`)
			local entry, why = exchange.parse("002-answer.md", text)
			if entry == nil then
				error(`render then parse failed for {string.format("%q", body)}: {why}`)
			end
			t.expect((entry :: exchange.Entry).body).toBe(body)
			t.expect((entry :: exchange.Entry).date).toBe(DATE)
			t.expect((entry :: exchange.Entry).n).toBe(2)
			t.expect((entry :: exchange.Entry).kind).toBe("answer")
		end
	end)

	it("AC1: a file without a date line, or with a loose one, is refused with its name", function()
		for _, bad in
			{
				"",
				"no header\n",
				"date: yesterday\n\nbody",
				"date: 2026-11-09 10:11:12Z\n\nbody",
				"date: 2026-11-09T10:11:12\n\nbody",
				"date: 2026-11-09T10:11:12Z\nbody",
				" date: 2026-11-09T10:11:12Z\n\nbody",
				"Date: 2026-11-09T10:11:12Z\n\nbody",
			}
		do
			local entry, why = exchange.parse("001-ask.md", bad)
			t.expect(entry).toBe(nil)
			if not has(why or "", "001-ask.md") then
				error(`the refusal of {string.format("%q", bad)} should name the file, said "{why}"`)
			end
		end
		local entry, why = exchange.parse("notes.md", exchange.render(DATE, "x"))
		t.expect(entry).toBe(nil)
		t.expect(has(why or "", "notes.md")).toBe(true)
	end)

	it(
		"AC1: the order is the number, however the folder listed it, and every legal shape is accepted",
		function()
			local got = order({ "003-answer.md", "001-ask.md", "002-question.md" })
			t.expect(table.concat(got :: { string }, ",")).toBe("001-ask.md,002-question.md,003-answer.md")
			got = order({ "001-question.md" })
			t.expect(table.concat(got :: { string }, ",")).toBe("001-question.md")
			got = order({})
			t.expect(#(got :: { string })).toBe(0)
			got = order({ "002-question.md", "001-question.md" })
			-- (two questions in a row: refused below) so only the legal continuation is checked here
			t.expect(got).toBe(nil)
			got = order({
				"001-ask.md",
				"002-question.md",
				"003-answer.md",
				"004-question.md",
				"005-answer.md",
			})
			t.expect(#(got :: { string })).toBe(5)
			-- a file being written (a dot name) is not part of the exchange
			got = order({ ".002-question.md", "001-ask.md" })
			t.expect(table.concat(got :: { string }, ",")).toBe("001-ask.md")
		end
	)

	it(
		"AC1: a gap, a repeat, a stray name and a broken alternation are each refused, naming the file",
		function()
			failsWith({ "001-ask.md", "003-question.md" }, "number 2")
			failsWith({ "002-question.md" }, "number 1")
			failsWith({ "001-ask.md", "001-question.md" }, "001-question.md")
			failsWith({ "001-ask.md", "notes.txt" }, "notes.txt")
			failsWith({ "001-ask.md", "002-ask.md" }, "002-ask.md")
			failsWith({ "001-question.md", "002-ask.md" }, "002-ask.md")
			failsWith({ "001-ask.md", "002-question.md", "003-question.md" }, "003-question.md")
			failsWith({ "001-answer.md" }, "001-answer.md")
			failsWith({ "001-ask.md", "002-answer.md" }, "002-answer.md")
			failsWith({ "001-ask.md", "002-question.md", "003-answer.md", "004-answer.md" }, "004-answer.md")
			failsWith({ "001-ask.md", "002-question.md", "003-answer.md", "005-question.md" }, "number 4")
		end
	)

	it("AC1: the next message is numbered after the last, and only a legal kind may follow", function()
		local function nextOf(names: { string }, kind: exchange.Kind): (number?, string?)
			return exchange.next(names, kind)
		end
		t.expect((nextOf({}, "ask"))).toBe(1)
		t.expect((nextOf({}, "question"))).toBe(1)
		t.expect((nextOf({}, "answer"))).toBe(nil)
		t.expect((nextOf({ "001-ask.md" }, "question"))).toBe(2)
		t.expect((nextOf({ "001-ask.md" }, "answer"))).toBe(nil)
		t.expect((nextOf({ "001-ask.md" }, "ask"))).toBe(nil)
		t.expect((nextOf({ "001-ask.md", "002-question.md" }, "answer"))).toBe(3)
		t.expect((nextOf({ "001-ask.md", "002-question.md" }, "question"))).toBe(nil)
		t.expect((nextOf({ "001-ask.md", "002-question.md", "003-answer.md" }, "question"))).toBe(4)
		t.expect((nextOf({ "003-answer.md", "001-ask.md", "002-question.md" }, "question"))).toBe(4)
		local n, why = nextOf({ "001-ask.md", "003-question.md" }, "answer")
		t.expect(n).toBe(nil)
		t.expect(has(why or "", "number 2")).toBe(true)
	end)

	it("AC1: the exchange holds 999 messages and says so when it is full", function()
		local names: { string } = { "001-ask.md" }
		for n = 2, 999 do
			table.insert(names, exchange.name(n, if n % 2 == 0 then "question" else "answer"))
		end
		t.expect(#(order(names) :: { string })).toBe(999)
		local n, why = exchange.next(names, "question")
		t.expect(n).toBe(nil)
		t.expect(has(why or "", "full")).toBe(true)
	end)

	it(
		"AC2: a re-run's prompt names every file of the exchange, in order, and says what each kind is",
		function()
			local base: dispatch.PromptInput = {
				step = "z-ticket",
				id = "",
				skillPath = "z-nile/skills/z-ticket/SKILL.md",
				worktree = "/w",
				stateDir = "/w/.cache/dispatch/new",
				description = "make a thing",
			}
			local first = dispatch.prompt(base)
			local none = table.clone(base)
			none.exchange = {}
			t.expect(dispatch.prompt(none)).toBe(first) -- nothing exchanged yet: the prompt is the first run's, byte for byte
			local rerun = table.clone(base)
			rerun.exchange = { "001-ask.md", "002-question.md", "003-answer.md" }
			rerun.exchangeAsker = "z-ticket"
			rerun.exchangeLastStep = "z-ticket"
			local p = dispatch.prompt(rerun)
			t.expect(has(p, "`/w/.cache/dispatch/new/exchange/`")).toBe(true)
			t.expect(has(p, "001-ask.md, 002-question.md, 003-answer.md")).toBe(true)
			t.expect(has(p, "-ask")).toBe(true)
			t.expect(has(p, "-question")).toBe(true)
			t.expect(has(p, "-answer")).toBe(true)
			t.expect(has(p, "a restatement is a question")).toBe(true)
			t.expect(has(p, "do not ask again what it settles")).toBe(true)
			t.expect(has(p, "it replies to your latest question")).toBe(true)
			-- everything the first prompt said, it still says: the re-run text is added, nothing is replaced
			for line in string.gmatch(first, "[^\n]+") do
				if not has(p, line) then
					error(`the re-run prompt lost: {line}`)
				end
			end
			t.expect(has(p, "follow it to capture this as one issue")).toBe(true)
			t.expect(has(p, '"make a thing"')).toBe(true)
			-- it comes before the work the step does, after who the step is
			local at = string.find(p, "This is a re-run", 1, true) :: number
			t.expect(at > (string.find(p, "You are running the z-nile step", 1, true) :: number)).toBe(true)
			t.expect(at < (string.find(p, "Nobody will answer a question", 1, true) :: number)).toBe(true)
		end
	)
	it("AC1: a question names the step that asked, and only a question does", function()
		local text = exchange.render(DATE, "## Q1\nWhich scope?\n", "z-design")
		t.expect(text).toBe(`date: {DATE}\nstep: z-design\n\n## Q1\nWhich scope?\n`)
		local entry, why = exchange.parse("002-question.md", text)
		if entry == nil then
			error(`a question with its step should parse: {why}`)
		end
		t.expect((entry :: exchange.Entry).step).toBe("z-design")
		t.expect((entry :: exchange.Entry).body).toBe("## Q1\nWhich scope?\n")
		for _, case in
			{
				{ name = "002-question.md", text = exchange.render(DATE, "x"), says = "step" },
				{ name = "002-question.md", text = `date: {DATE}\nstep: Z Design\n\nx`, says = "step" },
				{ name = "002-question.md", text = `date: {DATE}\nstep: z-design\nx`, says = "blank line" },
				{ name = "001-ask.md", text = exchange.render(DATE, "x", "z-ticket"), says = "001-ask.md" },
				{
					name = "003-answer.md",
					text = exchange.render(DATE, "x", "z-ticket"),
					says = "003-answer.md",
				},
			}
		do
			local got, bad = exchange.parse(case.name, case.text)
			t.expect(got).toBe(nil)
			if not has(bad or "", case.says) then
				error(`parse of {case.name} should say "{case.says}", said "{bad}"`)
			end
		end
	end)

	it(
		"AC1: the seal notices a file added, changed or removed, and no seal means nothing was written",
		function()
			local texts = { ["001-ask.md"] = "one", ["002-question.md"] = "two" }
			local sealed = exchange.seal(texts)
			t.expect(exchange.changed(sealed, texts)).toBe(nil)
			t.expect(
				has(
					exchange.changed(
						sealed,
						{ ["001-ask.md"] = "one", ["002-question.md"] = "two", ["003-answer.md"] = "x" }
					) or "",
					"added 003-answer.md"
				)
			).toBe(true)
			t.expect(
				has(
					exchange.changed(sealed, { ["001-ask.md"] = "forged", ["002-question.md"] = "two" }) or "",
					"changed 001-ask.md"
				)
			).toBe(true)
			t.expect(
				has(exchange.changed(sealed, { ["001-ask.md"] = "one" }) or "", "removed 002-question.md")
			)
				.toBe(true)
			t.expect(exchange.changed(nil, {})).toBe(nil)
			t.expect(has(exchange.changed(nil, { ["001-ask.md"] = "x" }) or "", "added 001-ask.md"))
				.toBe(true)
			-- the seal is of the bytes: one byte more is a change
			t.expect(
				has(
					exchange.changed(sealed, { ["001-ask.md"] = "one\n", ["002-question.md"] = "two" }) or "",
					"changed 001-ask.md"
				)
			).toBe(true)
		end
	)

	it(
		"AC1: an answer is refused when it is blank, over 64 KiB or binary, and accepted at the limit",
		function()
			t.expect(exchange.LIMIT).toBe(65536)
			for _, bad in { "", "  \n\t", string.rep("a", 65537), "text\0text" } do
				t.expect(exchange.answerRefusal(bad) ~= nil).toBe(true)
			end
			t.expect(has(exchange.answerRefusal(string.rep("a", 65537)) or "", "65537")).toBe(true)
			t.expect(has(exchange.answerRefusal("a\0b") or "", "NUL")).toBe(true)
			t.expect(exchange.answerRefusal(string.rep("a", 65536))).toBe(nil)
			t.expect(exchange.answerRefusal("ok")).toBe(nil)
			t.expect(exchange.answerRefusal(" a ")).toBe(nil)
		end
	)

	it(
		"AC2: a step that did not ask is told the history settles other steps' questions, not its own",
		function()
			local base: dispatch.PromptInput = {
				step = "z-design",
				id = "c0040",
				skillPath = "z-nile/skills/z-design/SKILL.md",
				worktree = "/w",
				stateDir = "/w/.cache/dispatch/c0040",
				exchange = { "001-ask.md", "002-question.md", "003-answer.md" },
				exchangeAsker = "z-ticket",
			}
			local p = dispatch.prompt(base)
			t.expect(has(p, "001-ask.md, 002-question.md, 003-answer.md")).toBe(true)
			t.expect(has(p, "Earlier steps of this run have already exchanged messages")).toBe(true)
			t.expect(has(p, "They settle those steps' questions, not yours")).toBe(true)
			t.expect(has(p, "This is a re-run")).toBe(false)
			t.expect(has(p, "do not ask again what it settles")).toBe(false)
			-- the same history read by the step that asked is a re-run
			local own = table.clone(base)
			own.step = "z-ticket"
			own.id = ""
			own.exchangeLastStep = "z-ticket"
			local q = dispatch.prompt(own)
			t.expect(has(q, "This is a re-run")).toBe(true)
			t.expect(has(q, "do not ask again what it settles")).toBe(true)
			t.expect(has(q, "Earlier steps of this run")).toBe(false)
			-- no step line to compare: nobody asked, so nobody is told it is a re-run
			local none = table.clone(base)
			none.exchangeAsker = nil
			t.expect(has(dispatch.prompt(none), "This is a re-run")).toBe(false)
		end
	)

	it("AC2: a re-run whose latest answer says no reply was given is told its question stands", function()
		local base: dispatch.PromptInput = {
			step = "z-ticket",
			id = "",
			skillPath = "z-nile/skills/z-ticket/SKILL.md",
			worktree = "/w",
			stateDir = "/w/.cache/dispatch/new",
			description = "make a thing",
			exchange = { "001-ask.md", "002-question.md", "003-answer.md" },
			exchangeAsker = "z-ticket",
			exchangeLastStep = "z-ticket",
			exchangeNoReply = true,
		}
		local p = dispatch.prompt(base)
		t.expect(has(p, "This is a re-run")).toBe(true)
		t.expect(has(p, "your question stands unanswered")).toBe(true)
		t.expect(has(p, "do not ask again what it settles")).toBe(false)
	end)

	it(
		"AC2: a step that asked long ago, with something else run since, is not told it is a re-run",
		function()
			local base: dispatch.PromptInput = {
				step = "z-design",
				id = "c0040",
				skillPath = "z-nile/skills/z-design/SKILL.md",
				worktree = "/w",
				stateDir = "/w/.cache/dispatch/c0040",
				exchange = { "001-question.md", "002-answer.md" },
				exchangeAsker = "z-design",
				exchangeLastStep = "z-raft",
			}
			local p = dispatch.prompt(base)
			t.expect(has(p, "This is a re-run")).toBe(false)
			t.expect(has(p, "Earlier steps of this run have already exchanged messages")).toBe(true)
			-- the same history with z-design the step that ran last is the re-run
			local again = table.clone(base)
			again.exchangeLastStep = "z-design"
			t.expect(has(dispatch.prompt(again), "This is a re-run")).toBe(true)
		end
	)

	it(
		"AC2: a re-run whose last file is a question is told it has no reply, and an answer copied at the retry is read in the question",
		function()
			local base: dispatch.PromptInput = {
				step = "z-design",
				id = "c0040",
				skillPath = "z-nile/skills/z-design/SKILL.md",
				worktree = "/w",
				stateDir = "/w/.cache/dispatch/c0040",
				exchange = { "001-question.md" },
				exchangeAsker = "z-design",
				exchangeLastStep = "z-design",
			}
			local p = dispatch.prompt(base)
			t.expect(has(p, "The last file is a question: it has no reply")).toBe(true)
			t.expect(has(p, "do not ask again what it settles")).toBe(false)
			local unknown = table.clone(base)
			unknown.exchange = { "001-question.md", "002-answer.md" }
			unknown.exchangeUnknownReply = true
			local q = dispatch.prompt(unknown)
			-- text the user added is their answer; a question alone is no reply, and is never read as an approval
			t.expect(has(q, "Text the user added to your question is their answer")).toBe(true)
			t.expect(
				has(q, "If it holds only your question, the user gave no reply and your question stands")
			)
				.toBe(true)
			t.expect(has(q, "treat what you find as their answer")).toBe(false)
		end
	)

	it(
		"AC2: a nested step is also told to read the exchange of the run that started it, read only",
		function()
			local base: dispatch.PromptInput = {
				step = "zz-review",
				id = "c0060",
				mode = "design",
				skillPath = "z-nile/skills/zz-review/SKILL.md",
				worktree = "/w",
				stateDir = "/w/.cache/dispatch/c0060/zz-review-design-c0060-2",
				parentExchange = { "001-question.md", "002-answer.md" },
				parentStateDir = "/w/.cache/dispatch/c0060",
			}
			local p = dispatch.prompt(base)
			t.expect(has(p, "The run that started you has exchanged messages with the user too")).toBe(true)
			t.expect(has(p, "`/w/.cache/dispatch/c0060/exchange/`")).toBe(true)
			t.expect(has(p, "001-question.md, 002-answer.md")).toBe(true)
			t.expect(has(p, "You only read them")).toBe(true)
			local none = table.clone(base)
			none.parentExchange = {}
			t.expect(has(dispatch.prompt(none), "The run that started you")).toBe(false)
		end
	)

	it("AC1: a text is compared as an editor leaves it, and the refusal names what it is about", function()
		t.expect(exchange.normal("## Q1\r\nWhich scope?  \r\n")).toBe("## Q1\nWhich scope?")
		t.expect(exchange.normal("a\n\n\n")).toBe("a")
		t.expect(exchange.normal("a \n b")).toBe("a\n b") -- leading spaces are kept
		t.expect(exchange.normal("")).toBe("")
		t.expect(exchange.normal("  \n")).toBe("")
		t.expect(exchange.normal("a b") ~= "ab").toBe(true)
		t.expect(has(exchange.answerRefusal("", "the question") or "", "the question is empty")).toBe(true)
		t.expect(
			has(
				exchange.answerRefusal(string.rep("q", 70000), "the question") or "",
				"the question is 70000 bytes"
			)
		).toBe(true)
		t.expect(
			has(exchange.answerRefusal("", "questions.md as edited") or "", "questions.md as edited is empty")
		)
			.toBe(true)
		t.expect(has(exchange.answerRefusal("") or "", "the answer is empty")).toBe(true)
	end)
end)
