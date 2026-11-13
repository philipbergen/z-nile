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

return t.spec("c0256 AC6: every round of the conversation is kept", function(it)
	it("sets up a tracker with .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("c0256-rounds", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
		})
		t.expect(fs.isDir(h.f.main)).toBe(true)
	end)

	it("AC6: a step that stops with questions leaves its question, dated, in the run's exchange", function()
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
		"AC6: the answer is stored after the question, and the re-run step reads both in its folder",
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
		"AC6: a second round appends, the earlier messages stay byte for byte, and the third run sees all five",
		function()
			local before: { [string]: string } = {}
			for _, name in exchangeOf("c0010") do
				before[name] = read("c0010", name)
			end
			fakecli.clear(h)
			mode("claude", "script")
			fs.writeFile(`{h.fakes}/script.sh`, READ_THEN_NOTHING)
			local answerFile = `{h.f.base}/second.txt`
			fs.writeFile(answerFile, "second reply\r\nwith a CRLF and a final newline\n  ")
			zn({ "dispatch", "retry", "c0010", "--answer-file", answerFile })
			t.expect(table.concat(exchangeOf("c0010"), ","))
				.toBe("001-question.md,002-answer.md,003-question.md,004-answer.md")
			for name, text in before do
				t.expect(read("c0010", name)).toBe(text)
			end
			t.expect(messageOf(read("c0010", "004-answer.md")))
				.toBe("second reply\r\nwith a CRLF and a final newline\n  ")
			t.expect(has(fakecli.log(h), "001-question.md, 002-answer.md, 003-question.md, 004-answer.md"))
				.toBe(true)
			t.expect(fs.isFile(`{dirOf("c0010")}/answered-2.md`)).toBe(true)
		end
	)
end)
