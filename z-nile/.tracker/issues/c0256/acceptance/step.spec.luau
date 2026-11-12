--!strict
-- c0256 AC3 (retry.spec), AC4 (step.spec), AC5 (capture.spec), AC6 (rounds.spec): `./zn dispatch retry <id> --answer <text> | --answer-file <path>` carries the user's answer into the
-- re-run step, for real with fake CLIs (@tests/lib/fakecli). A step that stops with questions.md leaves its question in
-- the run's exchange folder (one dated file per message); the retry adds the answer; the re-run step's prompt names the
-- folder and the step can read it; a capture (`dispatch new`) keeps its words, stops as "needs the user" (never as
-- "z-ticket made 0 issues") and its retry re-runs z-ticket with the same words. Fixture under .cache/c0256-retry.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
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

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000

[z-raft.claude]
model = "claude-opus-5-5"
rank = 3
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
local function dateOf(text: string): string
	return string.match(text, "^date: (%S+)\n") :: string
end
-- the step reads its exchange folder: logged, file by file, the way a real step would `cat` them
local READ_THEN_NOTHING =
	[[echo "reads:"; for f in "$ZN_DISPATCH_DIR"/exchange/*; do echo "file=$(basename "$f")"; cat "$f"; echo; done]]
local READ_THEN_ASK_AGAIN = READ_THEN_NOTHING
	.. [[; printf '## Q1\nsecond question\n' > "$ZN_DISPATCH_DIR/questions.md"]]

return t.spec("c0256 AC4: any step is retried the same way", function(it)
	it("sets up a tracker with .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("c0256-step", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
			["pickman/.tracker/issues/c0030/c0030.md"] = issue("c0030", "third-thing"),
			["pickman/.tracker/issues/c0050/c0050.md"] = issue("c0050", "fifth-thing"),
			["pickman/.tracker/issues/c0070/c0070.md"] = issue("c0070", "seventh-thing"),
		})
		t.expect(fs.isDir(h.f.main)).toBe(true)
	end)

	it("AC4: a step that stops with questions leaves its question, dated, in the run's exchange", function()
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

	it(
		"AC4: the answer is stored after the question, and the re-run step reads both in its folder",
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

	it("AC4: a one-step run that stops with questions is retried the same way", function()
		fakecli.clear(h)
		mode("claude", "questions")
		local r = zn({ "dispatch", "z-design", "c0030" })
		t.expect(r.code).toBe(3)
		t.expect(table.concat(exchangeOf("c0030"), ",")).toBe("001-question.md")
		mode("claude", "script")
		fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_NOTHING)
		zn({ "dispatch", "retry", "c0030", "--answer", "go" })
		t.expect(table.concat(exchangeOf("c0030"), ",")).toBe("001-question.md,002-answer.md")
		t.expect(has(fakecli.log(h), "file=002-answer.md")).toBe(true)
		t.expect(has(fakecli.log(h), "go")).toBe(true)
	end)

	it("AC4: a step started by hand while a question waits starts nothing", function()
		fakecli.clear(h)
		mode("claude", "script")
		fs.writeFile(`{h.fakes}/script.sh`, "echo SHOULD-NOT-RUN")
		local before = table.concat(exchangeOf("c0010"), ",")
		local r = zn({ "dispatch", "z-design", "c0010" })
		t.expect(r.code).toBe(3)
		t.expect(has(r.stdout .. r.stderr, "a question waits")).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
		t.expect(table.concat(exchangeOf("c0010"), ",")).toBe(before)
	end)

	it(
		"AC4: a review the author started that needs the user tells the author to ask, and sees the answer when it is dispatched again",
		function()
			fakecli.clear(h)
			mode("claude.z-design", "script")
			mode("claude.zz-review", "questions")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[./zn dispatch zz-review "$id" --mode design; printf '## Q1\nthe reviewer asks: which scope?\n' > "$ZN_DISPATCH_DIR/questions.md"]]
			)
			local r = zn({ "dispatch", "z-design", "c0050" })
			local log = fakecli.log(h)
			t.expect(has(log, "only the step that started it can ask")).toBe(true)
			t.expect(has(log, "retry c0050 --answer")).toBe(false) -- no command that would refuse is named
			t.expect(r.code).toBe(3) -- the author, not the reviewer, asks the user
			t.expect(table.concat(exchangeOf("c0050"), ",")).toBe("001-question.md")
			-- the user answers the author; the author dispatches its review again, and that reviewer is told to read the answer
			fakecli.clear(h)
			mode("claude.z-design", "script")
			mode("claude.zz-review", "questions")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[./zn dispatch zz-review "$id" --mode design; printf '## Q1\nasked again\n' > "$ZN_DISPATCH_DIR/questions.md"]]
			)
			zn({ "dispatch", "retry", "c0050", "--answer", "USER-DECISION small scope" })
			local second = fakecli.log(h)
			-- the reviewer's own part of the log (the second claude step=zz-review), not the re-run author's
			local first = string.find(second, "claude step=zz-review", 1, true)
			t.expect(first ~= nil).toBe(true)
			local rest = string.sub(second, (first :: number) + 1)
			local at = string.find(rest, "claude step=", 1, true)
			local reviewer = if at then string.sub(rest, 1, at - 1) else rest
			local told = string.find(
				reviewer,
				"The run that started you has exchanged messages with the user too",
				1,
				true
			)
			t.expect(told ~= nil).toBe(true)
			local after = string.sub(reviewer, told :: number)
			t.expect(has(after, ".cache/dispatch/c0050/exchange/")).toBe(true) -- the parent's folder, not its own
			t.expect(has(after, "001-question.md, 002-answer.md")).toBe(true)
		end
	)

	it(
		"AC4: a step that ran after the asker is told the exchange settles earlier steps' questions, not its own",
		function()
			fakecli.clear(h)
			mode("claude.z-design", "questions")
			zn({ "dispatch", "z-design", "c0070" })
			t.expect(table.concat(exchangeOf("c0070"), ",")).toBe("001-question.md")
			-- the asker is answered and finishes; the next step runs after it and fails, so it is retried
			fakecli.clear(h)
			mode("claude.z-design", "ok")
			zn({ "dispatch", "retry", "c0070", "--answer", "go on" })
			mode("claude.z-raft", "fail")
			zn({ "dispatch", "z-raft", "c0070" })
			fakecli.clear(h)
			mode("claude.z-raft", "script")
			fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_NOTHING)
			zn({ "dispatch", "retry", "c0070" })
			local log = fakecli.log(h)
			t.expect(has(log, "step=z-raft")).toBe(true)
			t.expect(has(log, "Earlier steps of this run have already exchanged messages")).toBe(true)
			t.expect(has(log, "This is a re-run")).toBe(false)
		end
	)
end)
