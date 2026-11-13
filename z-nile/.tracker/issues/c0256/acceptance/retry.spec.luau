--!strict
-- c0256 AC3 (retry.spec), AC4 (step.spec), AC5 (capture.spec), AC6 (rounds.spec): `./zn dispatch retry <id> --answer <text> | --answer-file <path>` carries the user's answer into the
-- re-run step, for real with fake CLIs (@tests/lib/fakecli). A step that stops with questions.md leaves its question in
-- the run's exchange folder (one dated file per message); the retry adds the answer; the re-run step's prompt names the
-- folder and the step can read it; a capture (`dispatch new`) keeps its words, stops as "needs the user" (never as
-- "z-ticket made 0 issues") and its retry re-runs z-ticket with the same words. Fixture under .cache/c0256-retry.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude", "grok", "agent"]

[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[z-ticket.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000

[z-design.claude]
model = "claude-opus-5-5"
rank = 3
runtime = "claude-cli"
max_tokens = 5000
]]

local h: fakecli.Harness
local function issue(id: string, slug: string): string
	return trackerfix.stub(id, slug, "new-quiet-copper-falcon")
end
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
local function zn(args: { string }): fixture.Result
	return fakecli.zn(h, args)
end
local function mode(name: string, value: string?)
	fakecli.mode(h, name, value)
end
local function dirOf(id: string): string
	return `{h.f.main}/.cache/dispatch/{id}`
end
local function files(dir: string): { string }
	if not fs.isDir(dir) then
		return {}
	end
	local out = fs.readDir(dir)
	table.sort(out)
	return out
end
local function exchangeOf(id: string): { string }
	return files(`{dirOf(id)}/exchange`)
end
local function read(id: string, name: string): string
	return fs.readFile(`{dirOf(id)}/exchange/{name}`)
end
-- the message of an exchange file, after its date line and the blank line (asserting that shape)
local function messageOf(text: string): string
	local date, rest = string.match(text, "^date: (%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ)\n(.*)$")
	if date == nil then
		error(`not a dated message: {string.format("%q", text)}`)
	end
	local _, withStep = string.match(rest :: string, "^(step: [a-z%-]+\n)\n(.*)$")
	if withStep ~= nil then
		return withStep
	end
	local body = string.match(rest :: string, "^\n(.*)$")
	if body == nil then
		error(`not a dated message: {string.format("%q", text)}`)
	end
	return body
end
local function stepOf(text: string): string?
	return string.match(text, "^date: %S+\nstep: ([a-z%-]+)\n\n")
end
local function dateOf(text: string): string
	return string.match(text, "^date: (%S+)\n") :: string
end
-- the step reads its exchange folder: logged, file by file, the way a real step would `cat` them
local READ_THEN_NOTHING =
	[[echo "reads:"; for f in "$ZN_DISPATCH_DIR"/exchange/*; do echo "file=$(basename "$f")"; cat "$f"; echo; done]]
local READ_THEN_ASK_AGAIN = READ_THEN_NOTHING
	.. [[; printf '## Q1\nsecond question\n' > "$ZN_DISPATCH_DIR/questions.md"]]

return t.spec("c0256 AC3: retry takes the user's answer", function(it)
	it("sets up a tracker with .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("c0256-retry", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0020/c0020.md"] = issue("c0020", "second-thing"),
			["pickman/.tracker/issues/c0040/c0040.md"] = issue("c0040", "fourth-thing"),
			["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["pickman/.tracker/issues/c0060/c0060.md"] = issue("c0060", "sixth-thing"),
			["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "seventh-thing"),
			["pickman/.tracker/issues/c0080/c0080.md"] = issue("c0080", "eighth-thing"),
			["pickman/.tracker/issues/c0090/c0090.md"] = issue("c0090", "ninth-thing"),
			["pickman/.tracker/issues/c0100/c0100.md"] = issue("c0100", "tenth-thing"),
			["pickman/.tracker/issues/c0110/c0110.md"] = issue("c0110", "eleventh-thing"),
			["pickman/.tracker/issues/c0130/c0130.md"] = issue("c0130", "thirteenth-thing"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["pickman/.tracker/issues/c0120/c0120.md"] = issue("c0120", "twelfth-thing"),
			["pickman/.tracker/issues/c0140/c0140.md"] = issue("c0140", "fourteenth-thing"),
			["pickman/.tracker/issues/c0150/c0150.md"] = issue("c0150", "fifteenth-thing"),
			["pickman/.tracker/issues/c0160/c0160.md"] = issue("c0160", "sixteenth-thing"),
			["pickman/.tracker/issues/c0170/c0170.md"] = issue("c0170", "seventeenth-thing"),
			["pickman/.tracker/issues/c0180/c0180.md"] = issue("c0180", "eighteenth-thing"),
			["pickman/.tracker/issues/c0190/c0190.md"] = issue("c0190", "nineteenth-thing"),
			["pickman/.tracker/issues/c0200/c0200.md"] = issue("c0200", "twentieth-thing"),
			["pickman/.tracker/issues/c0210/c0210.md"] = issue("c0210", "twentyfirst-thing"),
			["pickman/.tracker/issues/c0220/c0220.md"] = issue("c0220", "twentysecond-thing"),
		})
		t.expect(fs.isDir(h.f.main)).toBe(true)
	end)

	it("AC3: a step that stops with questions leaves its question, dated, in the run's exchange", function()
		fakecli.clear(h)
		mode("claude", "questions")
		local r = zn({ "dispatch", "c0010" })
		t.expect(r.code).toBe(3)
		t.expect(has(r.stdout, "needs the user")).toBe(true)
		t.expect(has(r.stdout, "--answer")).toBe(true) -- the stop names how to answer
		t.expect(table.concat(exchangeOf("c0010"), ",")).toBe("001-question.md")
		local text = read("c0010", "001-question.md")
		t.expect(messageOf(text)).toBe("## Q1\nWhich scope?\n") -- the step's questions.md, exactly
		t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(true)
	end)

	it("AC3: a retry that cannot take its answer refuses it and changes nothing", function()
		local before = table.concat(exchangeOf("c0010"), ",")
		local answerFile = `{h.f.base}/answer.txt`
		fs.writeFile(answerFile, "from a file")
		process.exec("ln", { "-s", answerFile, `{h.f.base}/linked.txt` })
		local emptyFile = `{h.f.base}/empty.txt`
		fs.writeFile(emptyFile, "  \n")
		for _, case in
			{
				{ args = { "--answer", "a", "--answer-file", answerFile }, says = "not both" },
				{ args = { "--answer", "a", "--answer", "b" }, says = "one answer" },
				{ args = { "--answer", "" }, says = "empty" },
				{ args = { "--answer", "  " }, says = "empty" },
				{ args = { "--answer-file", `{h.f.base}/missing.txt` }, says = "not a regular file" },
				{ args = { "--answer-file", emptyFile }, says = "empty" },
				{ args = { "--answer-file", h.f.base }, says = "not a regular file" },
				{ args = { "--answer-file", `{h.f.base}/linked.txt` }, says = "not a regular file" },
			}
		do
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, "echo SHOULD-NOT-RUN")
			local argv = { "dispatch", "retry", "c0010" }
			for _, a in case.args do
				table.insert(argv, a)
			end
			local r = zn(argv)
			if r.ok then
				error(`retry {table.concat(case.args, " ")} should be refused`)
			end
			if not has(r.stdout .. r.stderr, case.says) then
				error(
					`retry {table.concat(case.args, " ")} should say "{case.says}", said: {r.stdout}{r.stderr}`
				)
			end
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(true) -- still waiting
			t.expect(fs.isFile(`{dirOf("c0010")}/answered-1.md`)).toBe(false)
			t.expect(table.concat(exchangeOf("c0010"), ",")).toBe(before)
			t.expect(has(fakecli.log(h), "SHOULD-NOT-RUN")).toBe(false) -- no step started
		end
	end)

	it("AC3: an answer where no question waits is refused, not stored for later", function()
		fakecli.clear(h)
		mode("claude", "ok")
		local r = zn({ "dispatch", "retry", "c0020", "--answer", "nobody asked" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "no question waits")).toBe(true)
		t.expect(#exchangeOf("c0020")).toBe(0)
		t.expect(fs.isDir(`{dirOf("c0020")}/exchange`)).toBe(false)
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"AC3: the answer is stored after the question, and the re-run step reads both in its folder",
		function()
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_ASK_AGAIN)
			local r =
				zn({ "dispatch", "retry", "c0010", "--answer", "Use the small scope.\nNot the large one." })
			t.expect(r.code).toBe(3) -- it asked again, so the chain stopped for the user again
			t.expect(table.concat(exchangeOf("c0010"), ","))
				.toBe("001-question.md,002-answer.md,003-question.md")
			t.expect(messageOf(read("c0010", "002-answer.md")))
				.toBe("Use the small scope.\nNot the large one.")
			t.expect(messageOf(read("c0010", "003-question.md"))).toBe("## Q1\nsecond question\n")
			-- the dated order: the question is not older than the answer, which is not older than the first question
			t.expect(dateOf(read("c0010", "001-question.md")) <= dateOf(read("c0010", "002-answer.md")))
				.toBe(true)
			t.expect(dateOf(read("c0010", "002-answer.md")) <= dateOf(read("c0010", "003-question.md")))
				.toBe(true)
			-- c0117's behaviour is kept: the answered questions.md is set aside, the new one waits
			t.expect(fs.isFile(`{dirOf("c0010")}/answered-1.md`)).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0010")}/questions.md`)).toBe(true)
			-- the re-run step was told where to look, and could read the question and the reply
			local log = fakecli.log(h)
			t.expect(count(log, "claude step=z-design mode=script")).toBe(1)
			t.expect(has(log, ".cache/dispatch/c0010/exchange/")).toBe(true)
			t.expect(has(log, "001-question.md, 002-answer.md")).toBe(true)
			t.expect(has(log, "file=001-question.md")).toBe(true)
			t.expect(has(log, "file=002-answer.md")).toBe(true)
			t.expect(has(log, "Which scope?")).toBe(true)
			t.expect(has(log, "Use the small scope.")).toBe(true)
		end
	)

	it(
		"AC3: a retry with no answer still reruns (c0117), and the exchange says no reply was given",
		function()
			fakecli.clear(h)
			mode("claude", "questions")
			t.expect(zn({ "dispatch", "c0020" }).code).toBe(3)
			mode("claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_NOTHING)
			zn({ "dispatch", "retry", "c0020" })
			t.expect(table.concat(exchangeOf("c0020"), ",")).toBe("001-question.md,002-answer.md")
			t.expect(messageOf(read("c0020", "002-answer.md")))
				.toBe("(no reply: the user ran retry without an answer)")
			t.expect(fs.isFile(`{dirOf("c0020")}/answered-1.md`)).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0020")}/questions.md`)).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-design mode=script")).toBe(1)
		end
	)

	it("AC3: an exchange folder that cannot be read stops the retry before anything is moved", function()
		fakecli.clear(h)
		mode("claude", "questions")
		t.expect(zn({ "dispatch", "c0040" }).code).toBe(3)
		fs.writeFile(`{dirOf("c0040")}/exchange/notes.txt`, "a stray file")
		mode("claude", "script")
		fs.writeFile(`{h.fakes}/script.sh`, "echo SHOULD-NOT-RUN")
		local r = zn({ "dispatch", "retry", "c0040", "--answer", "x" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "notes.txt")).toBe(true)
		t.expect(fs.isFile(`{dirOf("c0040")}/questions.md`)).toBe(true)
		t.expect(fs.isFile(`{dirOf("c0040")}/answered-1.md`)).toBe(false)
		t.expect(has(fakecli.log(h), "SHOULD-NOT-RUN")).toBe(false)
	end)

	local function editState(id: string, fn: (any) -> ())
		local path = `{dirOf(id)}/state.json`
		local st = serde.decode("json", fs.readFile(path))
		fn(st)
		fs.writeFile(path, serde.encode("json", st))
	end
	local function stopAt(id: string)
		fakecli.clear(h)
		mode("claude", "questions")
		t.expect(zn({ "dispatch", id }).code).toBe(3)
	end
	local function readThenNothing()
		fakecli.clear(h)
		mode("claude", "script")
		fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_NOTHING)
	end

	it("AC3: a question carries the step that asked it", function()
		t.expect(stepOf(read("c0010", "001-question.md"))).toBe("z-design")
	end)

	it("AC3: what the user writes into questions.md is their answer, stored whole", function()
		stopAt("c0050")
		local qpath = `{dirOf("c0050")}/questions.md`
		local edited = fs.readFile(qpath) .. "ANSWER: the small scope\n"
		fs.writeFile(qpath, edited)
		readThenNothing()
		zn({ "dispatch", "retry", "c0050" })
		t.expect(table.concat(exchangeOf("c0050"), ",")).toBe("001-question.md,002-answer.md")
		t.expect(messageOf(read("c0050", "002-answer.md"))).toBe(edited)
		t.expect(has(fakecli.log(h), "ANSWER: the small scope")).toBe(true) -- the re-run step read it
		t.expect(fs.readFile(`{dirOf("c0050")}/answered-1.md`)).toBe(edited)
	end)

	it("AC3: an edited questions.md together with --answer is refused, and the edit stays", function()
		stopAt("c0060")
		local qpath = `{dirOf("c0060")}/questions.md`
		local edited = fs.readFile(qpath) .. "ANSWER: edited\n"
		fs.writeFile(qpath, edited)
		local r = zn({ "dispatch", "retry", "c0060", "--answer", "and a flag" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "edited and --answer")).toBe(true)
		t.expect(fs.readFile(qpath)).toBe(edited)
		t.expect(table.concat(exchangeOf("c0060"), ",")).toBe("001-question.md")
	end)

	it(
		"AC3: a link in the exchange (a file, the folder, questions.md) is refused and nothing is written through it",
		function()
			stopAt("c0070")
			local dir = dirOf("c0070")
			local decoy = `{h.f.base}/decoy.txt`
			fs.writeFile(decoy, "DECOY")
			local function sh(cmd: string)
				local r = process.exec("sh", { "-c", cmd })
				if not r.ok then
					error(`{cmd}: {r.stderr}`)
				end
			end
			-- a link where the answer would be written
			sh(`ln -s '{decoy}' '{dir}/exchange/002-answer.md'`)
			local r = zn({ "dispatch", "retry", "c0070", "--answer", "x" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "002-answer.md is not a regular file")).toBe(true)
			t.expect(fs.readFile(decoy)).toBe("DECOY")
			sh(`rm '{dir}/exchange/002-answer.md'`)
			-- the folder itself a link
			sh(`mv '{dir}/exchange' '{dir}/exchange.real' && ln -s exchange.real '{dir}/exchange'`)
			r = zn({ "dispatch", "retry", "c0070", "--answer", "x" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "is a link")).toBe(true)
			t.expect(#files(`{dir}/exchange.real`)).toBe(1)
			sh(`rm '{dir}/exchange' && mv '{dir}/exchange.real' '{dir}/exchange'`)
			-- questions.md a link
			sh(`mv '{dir}/questions.md' '{dir}/questions.real' && ln -s questions.real '{dir}/questions.md'`)
			r = zn({ "dispatch", "retry", "c0070", "--answer", "x" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "questions.md is a link")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, "cannot take the question")).toBe(false) -- refused at the retry, not later in the copy
			t.expect(table.concat(exchangeOf("c0070"), ",")).toBe("001-question.md")
		end
	)

	it(
		"AC3: a step that rewrites the exchange fails with its spend recorded, and its question is set aside",
		function()
			stopAt("c0080")
			local before = #(fakecli.rows(h, "c0080") or {})
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[printf 'FORGED' >> "$ZN_DISPATCH_DIR/exchange/001-question.md"; printf '## Q1\nagain\n' > "$ZN_DISPATCH_DIR/questions.md"]]
			)
			local r = zn({ "dispatch", "retry", "c0080", "--answer", "the real answer" })
			t.expect(r.ok).toBe(false)
			local st = fakecli.state(h, "c0080")
			t.expect(st.outcome).toBe("failed")
			t.expect(has(st.detail, "changed 001-question.md")).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0080")}/questions.md`)).toBe(false)
			t.expect(fs.isFile(`{dirOf("c0080")}/questions-refused-1.md`)).toBe(true)
			t.expect(#(fakecli.rows(h, "c0080") or {}) > before).toBe(true)
			-- the next run says what happened: it is neither "lost" nor a question for the user
			local again = zn({ "dispatch", "c0080" })
			t.expect(has(again.stdout .. again.stderr, "lost")).toBe(false)
			t.expect(again.code ~= 3).toBe(true)
			-- the record is damaged: a retry refuses it, says how to go on, and --forget-exchange sets it aside
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_NOTHING)
			local damaged = zn({ "dispatch", "retry", "c0080" })
			t.expect(damaged.ok).toBe(false)
			t.expect(has(damaged.stdout .. damaged.stderr, "--forget-exchange")).toBe(true)
			t.expect(fakecli.log(h)).toBe("")
			zn({ "dispatch", "retry", "c0080", "--forget-exchange" })
			t.expect(has(fakecli.log(h), "reads:")).toBe(true) -- the step ran
			local forgotten: { string } = {}
			for _, name in files(dirOf("c0080")) do
				if string.sub(name, 1, 18) == "exchange-forgotten" then
					table.insert(forgotten, name)
				end
			end
			t.expect(#forgotten).toBe(1)
			t.expect(table.concat(files(`{dirOf("c0080")}/{forgotten[1]}`), ","))
				.toBe("001-question.md,002-answer.md")
			t.expect(#exchangeOf("c0080")).toBe(0)
		end
	)

	it(
		"AC3: a step that leaves a stray file and a question fails with its spend recorded, not 'lost'",
		function()
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[mkdir -p "$ZN_DISPATCH_DIR/exchange"; echo x > "$ZN_DISPATCH_DIR/exchange/notes.md"; printf '## Q1\nq\n' > "$ZN_DISPATCH_DIR/questions.md"]]
			)
			local before = #(fakecli.rows(h, "c0090") or {})
			local r = zn({ "dispatch", "c0090" })
			t.expect(r.ok).toBe(false)
			local st = fakecli.state(h, "c0090")
			t.expect(st.outcome).toBe("failed")
			t.expect(has(st.detail, "notes.md")).toBe(true)
			t.expect(#(fakecli.rows(h, "c0090") or {}) > before).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0090")}/questions-refused-1.md`)).toBe(true)
			local again = zn({ "dispatch", "c0090" })
			t.expect(has(again.stdout .. again.stderr, "lost")).toBe(false)
		end
	)

	it(
		"AC3: a retry that died after storing the answer is finished by the next one, which adds nothing",
		function()
			stopAt("c0100")
			readThenNothing()
			zn({ "dispatch", "retry", "c0100", "--answer", "first" })
			-- the state a retry killed after writing the answer leaves, as the dispatcher records it: the answer is in the
			-- exchange, questions.md still waits, and the state names the questions.md the answer was written for
			local dir = dirOf("c0100")
			local text = fs.readFile(`{dir}/answered-1.md`)
			fs.writeFile(`{dir}/questions.md`, text)
			editState("c0100", function(st)
				st.answering = serde.hash("sha256", text)
			end)
			local names = table.concat(exchangeOf("c0100"), ",")
			t.expect(names).toBe("001-question.md,002-answer.md")
			local r = zn({ "dispatch", "retry", "c0100", "--answer", "second" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, "already recorded")).toBe(true)
			t.expect(fs.isFile(`{dir}/questions.md`)).toBe(true)
			zn({ "dispatch", "retry", "c0100" })
			t.expect(table.concat(exchangeOf("c0100"), ",")).toBe(names)
			t.expect(fs.isFile(`{dir}/questions.md`)).toBe(false)
			t.expect(fs.isFile(`{dir}/answered-2.md`)).toBe(true)
			t.expect(fakecli.state(h, "c0100").answering).toBe(nil)
		end
	)

	it("AC3: an answer over 64 KiB or binary is refused, and one at the limit is stored", function()
		stopAt("c0110")
		local big = `{h.f.base}/big.txt`
		fs.writeFile(big, string.rep("a", 65537))
		local nul = `{h.f.base}/nul.txt`
		fs.writeFile(nul, "text\0text")
		for _, case in { { file = big, says = "65537" }, { file = nul, says = "NUL" } } do
			local r = zn({ "dispatch", "retry", "c0110", "--answer-file", case.file })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, case.says)).toBe(true)
			t.expect(fs.isFile(`{dirOf("c0110")}/questions.md`)).toBe(true)
			t.expect(table.concat(exchangeOf("c0110"), ",")).toBe("001-question.md")
		end
		local limit = `{h.f.base}/limit.txt`
		fs.writeFile(limit, string.rep("a", 65536))
		readThenNothing()
		zn({ "dispatch", "retry", "c0110", "--answer-file", limit })
		t.expect(#messageOf(read("c0110", "002-answer.md"))).toBe(65536)
	end)

	it("AC3: a step started by hand does not start on an exchange it cannot read", function()
		fakecli.clear(h)
		fs.writeDir(`{dirOf("c0130")}/exchange`)
		fs.writeFile(`{dirOf("c0130")}/exchange/notes.txt`, "a stray file")
		mode("claude", "script")
		fs.writeFile(`{h.fakes}/script.sh`, "echo SHOULD-NOT-RUN")
		local one = zn({ "dispatch", "z-design", "c0130" })
		t.expect(one.ok).toBe(false)
		t.expect(has(one.stdout .. one.stderr, "notes.txt")).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
	end)

	it(
		"AC3: a re-run that asked again and then lost its dispatcher gets the new question recorded and answered",
		function()
			stopAt("c0120")
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[printf '## Q1\nsecond question\n' > "$ZN_DISPATCH_DIR/questions.md"; kill -9 "$ZN_DISPATCHER_PID"]]
			)
			zn({ "dispatch", "retry", "c0120", "--answer", "first answer" }) -- the dispatcher dies in the step
			task.wait(4) -- the step the killed dispatcher left behind ends by itself; its run is held until then
			t.expect(table.concat(exchangeOf("c0120"), ",")).toBe("001-question.md,002-answer.md")
			readThenNothing()
			zn({ "dispatch", "retry", "c0120", "--answer", "answer to the second question" })
			t.expect(table.concat(exchangeOf("c0120"), ","))
				.toBe("001-question.md,002-answer.md,003-question.md,004-answer.md")
			t.expect(messageOf(read("c0120", "003-question.md"))).toBe("## Q1\nsecond question\n")
			t.expect(messageOf(read("c0120", "004-answer.md"))).toBe("answer to the second question")
			t.expect(has(fakecli.log(h), "This is a re-run")).toBe(true)
		end
	)

	it(
		"AC3: a question the retry copies itself may hold the user's answer, and is not recorded as 'no reply'",
		function()
			-- a question waiting from before the exchange existed (c0117's way: the user answers inside the file)
			stopAt("c0030")
			local dir = dirOf("c0030")
			fs.removeDir(`{dir}/exchange`)
			editState("c0030", function(st)
				st.sealed = nil
			end)
			fs.writeFile(
				`{dir}/questions.md`,
				fs.readFile(`{dir}/questions.md`) .. "ANSWER (as c0117 documents): the small scope\n"
			)
			readThenNothing()
			zn({ "dispatch", "retry", "c0030" })
			t.expect(table.concat(exchangeOf("c0030"), ",")).toBe("001-question.md,002-answer.md")
			t.expect(has(messageOf(read("c0030", "001-question.md")), "the small scope")).toBe(true)
			t.expect(messageOf(read("c0030", "002-answer.md")))
				.toBe("(the question was copied when the user retried, so any answer they wrote is inside it)")
			t.expect(has(fakecli.log(h), "Text the user added to your question is their answer")).toBe(true)
			t.expect(has(fakecli.log(h), "treat what you find as their answer")).toBe(false)
			-- and a flag still gives the answer
			stopAt("c0140")
			fs.removeDir(`{dirOf("c0140")}/exchange`)
			editState("c0140", function(st)
				st.sealed = nil
			end)
			readThenNothing()
			zn({ "dispatch", "retry", "c0140", "--answer", "by the flag" })
			t.expect(messageOf(read("c0140", "002-answer.md"))).toBe("by the flag")
		end
	)

	it(
		"AC3: line ends and trailing space an editor adds are not an edit, and a blank or deleted file has a way on",
		function()
			stopAt("c0150")
			local q150 = `{dirOf("c0150")}/questions.md`
			fs.writeFile(q150, fs.readFile(q150) .. "\r\n  \n")
			zn({ "dispatch", "retry", "c0150", "--answer", "by the flag" })
			t.expect(messageOf(read("c0150", "002-answer.md"))).toBe("by the flag") -- an editor's final newline did not count as an edit
			stopAt("c0160")
			local q160 = `{dirOf("c0160")}/questions.md`
			fs.writeFile(q160, fs.readFile(q160) .. "  \n")
			readThenNothing()
			zn({ "dispatch", "retry", "c0160" })
			t.expect(messageOf(read("c0160", "002-answer.md")))
				.toBe("(no reply: the user ran retry without an answer)")
			-- a blank file: a plain retry is refused with the way on, a flag takes the flag
			stopAt("c0170")
			fs.writeFile(`{dirOf("c0170")}/questions.md`, "")
			local plain = zn({ "dispatch", "retry", "c0170" })
			t.expect(plain.ok).toBe(false)
			t.expect(has(plain.stdout .. plain.stderr, "restore it from")).toBe(true)
			t.expect(table.concat(exchangeOf("c0170"), ",")).toBe("001-question.md")
			readThenNothing()
			zn({ "dispatch", "retry", "c0170", "--answer", "after a blanked file" })
			t.expect(messageOf(read("c0170", "002-answer.md"))).toBe("after a blanked file")
			-- a deleted file: the flag answers the exchange's last unanswered question, and nothing is moved
			stopAt("c0180")
			fs.removeFile(`{dirOf("c0180")}/questions.md`)
			readThenNothing()
			zn({ "dispatch", "retry", "c0180", "--answer", "after a deleted file" })
			t.expect(table.concat(exchangeOf("c0180"), ",")).toBe("001-question.md,002-answer.md")
			t.expect(messageOf(read("c0180", "002-answer.md"))).toBe("after a deleted file")
			t.expect(fs.isFile(`{dirOf("c0180")}/answered-1.md`)).toBe(false)
		end
	)

	it(
		"AC3: a name the dispatcher picks is free of links too: a planted link is skipped, never written through",
		function()
			local decoy = `{h.f.base}/decoy-dir`
			fs.writeDir(decoy)
			-- answered-N.md
			stopAt("c0190")
			process.exec("ln", { "-s", decoy, `{dirOf("c0190")}/answered-1.md` })
			readThenNothing()
			zn({ "dispatch", "retry", "c0190", "--answer", "x" })
			t.expect(#files(decoy)).toBe(0)
			t.expect(fs.isFile(`{dirOf("c0190")}/answered-2.md`)).toBe(true)
			-- questions-refused-N.md, from a step that leaves a link there and a stray file
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				`mkdir -p "$ZN_DISPATCH_DIR/exchange"; echo x > "$ZN_DISPATCH_DIR/exchange/notes.md"; printf '## Q1\nq\n' > "$ZN_DISPATCH_DIR/questions.md"; ln -s '{decoy}' "$ZN_DISPATCH_DIR/questions-refused-1.md"`
			)
			zn({ "dispatch", "c0200" })
			t.expect(#files(decoy)).toBe(0)
			t.expect(fs.isFile(`{dirOf("c0200")}/questions-refused-2.md`)).toBe(true)
		end
	)

	it("AC3: a question over 64 KiB fails the step with its spend recorded", function()
		fakecli.clear(h)
		mode("claude", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			[[head -c 70000 /dev/zero | tr '\0' 'a' > "$ZN_DISPATCH_DIR/questions.md"]]
		)
		local before = #(fakecli.rows(h, "c0210") or {})
		local r = zn({ "dispatch", "c0210" })
		t.expect(r.ok).toBe(false)
		local st = fakecli.state(h, "c0210")
		t.expect(st.outcome).toBe("failed")
		t.expect(has(st.detail, "the question is 70000 bytes")).toBe(true)
		t.expect(#(fakecli.rows(h, "c0210") or {}) > before).toBe(true)
	end)

	it("AC3: a refused retry leaves the exchange where it was, --forget-exchange included", function()
		-- c0020 has a finished round and no question waiting
		local before = table.concat(exchangeOf("c0020"), ",")
		local r = zn({ "dispatch", "retry", "c0020", "--forget-exchange", "--answer", "x" })
		t.expect(r.ok).toBe(false)
		t.expect(table.concat(exchangeOf("c0020"), ",")).toBe(before)
		for _, name in files(dirOf("c0020")) do
			t.expect(string.sub(name, 1, 18) ~= "exchange-forgotten").toBe(true)
		end
	end)

	local function asksAgain()
		fakecli.clear(h)
		mode("claude", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			[[printf '## Q2\nA DIFFERENT question\n' > "$ZN_DISPATCH_DIR/questions.md"]]
		)
	end

	it(
		"AC3: a question left open when questions.md was deleted is closed as withdrawn, so the step's next question is recorded, and a flag answers that one",
		function()
			stopAt("c0220")
			fs.removeFile(`{dirOf("c0220")}/questions.md`)
			asksAgain()
			local r = zn({ "dispatch", "retry", "c0220" })
			t.expect(r.code).toBe(3)
			t.expect(table.concat(exchangeOf("c0220"), ","))
				.toBe("001-question.md,002-answer.md,003-question.md")
			t.expect(messageOf(read("c0220", "002-answer.md")))
				.toBe("(no reply: questions.md was removed without an answer)")
			t.expect(messageOf(read("c0220", "003-question.md"))).toBe("## Q2\nA DIFFERENT question\n")
			-- the step that was re-run was told its question stands (a withdrawn question is no reply)
			local told = fakecli.log(h)
			t.expect(has(told, "your question stands unanswered")).toBe(true)
			t.expect(has(told, "do not ask again what it settles")).toBe(false)
			-- the flag answers the step's new question, not an "edit" of the old one
			readThenNothing()
			zn({ "dispatch", "retry", "c0220", "--answer", "answer to Q2" })
			t.expect(table.concat(exchangeOf("c0220"), ","))
				.toBe("001-question.md,002-answer.md,003-question.md,004-answer.md")
			t.expect(messageOf(read("c0220", "004-answer.md"))).toBe("answer to Q2")
			t.expect(has(fakecli.log(h), "do not ask again what it settles")).toBe(true)
		end
	)
end)
