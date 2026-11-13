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
local function dateOf(text: string): string
	return string.match(text, "^date: (%S+)\n") :: string
end

-- how many issues origin's main holds
local function originIssues(): number
	local r = process.exec("git", { `--git-dir={h.f.origin}`, "ls-tree", "-r", "--name-only", "main" })
	local n = 0
	for _, path in string.split(r.stdout, "\n") do
		if string.match(path, "/issues/c%d+/c%d+%.md$") then
			n += 1
		end
	end
	return n
end

-- another session's issue lands on origin: a one-step run of c0010 whose step makes it (the case fails if it did not land)
local function landOther(slug: string)
	local before = originIssues()
	fakecli.clear(h)
	mode("claude.z-design", "script")
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`./zn new issue c {slug} --project pickman --desc "another session's issue"`
	)
	zn({ "dispatch", "z-design", "c0010" })
	t.expect(originIssues()).toBe(before + 1)
end

return t.spec("c0256 AC5: a dispatched capture keeps its words and is retried by name", function(it)
	it("sets up a tracker with .models.toml, issues and the fake CLIs", function()
		h = fakecli.new("c0256-capture", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = issue("c0010", "first-thing"),
		})
		t.expect(fs.isDir(h.f.main)).toBe(true)
	end)

	it("AC5: a dry run of a new capture records nothing", function()
		local r = zn({ "dispatch", "new", "a dry thing", "--dry-run" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isDir(`{dirOf("new")}/exchange`)).toBe(false)
	end)

	it(
		"AC5: a capture that stops with questions is 'needs the user', keeps its words dated, and names its retry",
		function()
			fakecli.clear(h)
			mode("claude.z-ticket", "questions")
			local r = zn({ "dispatch", "new", "make a thing, then another" })
			t.expect(r.code).toBe(3)
			t.expect(has(r.stdout, "needs the user")).toBe(true)
			t.expect(has(r.stdout, "./zn dispatch retry new")).toBe(true)
			t.expect(has(r.stdout .. r.stderr, "made 0 issues")).toBe(false)
			t.expect(table.concat(exchangeOf("new"), ",")).toBe("001-ask.md,002-question.md")
			t.expect(messageOf(read("new", "001-ask.md"))).toBe("make a thing, then another")
			t.expect(messageOf(read("new", "002-question.md"))).toBe("## Q1\nWhich scope?\n")
			local st = fakecli.state(h, "new")
			t.expect(st.outcome ~= "failed").toBe(true)
			for _, a in st.history do
				t.expect(a.outcome ~= "failed").toBe(true)
			end
		end
	)

	it("AC5: new words are not taken while a capture waits for its answer", function()
		fakecli.clear(h)
		local r = zn({ "dispatch", "new", "something else entirely" })
		t.expect(r.code).toBe(3)
		t.expect(has(r.stdout, "were not taken")).toBe(true)
		t.expect(table.concat(exchangeOf("new"), ",")).toBe("001-ask.md,002-question.md")
		t.expect(messageOf(read("new", "001-ask.md"))).toBe("make a thing, then another")
		t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(0)
	end)

	it(
		"AC5: retrying the capture re-runs z-ticket with the same words, and its exchange moves to the new issue",
		function()
			local askedAt = dateOf(read("new", "001-ask.md"))
			task.wait(1.2) -- so a date taken at the retry could not equal the ask's
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			mode("claude.z-design", "ok")
			local r = zn({ "dispatch", "retry", "new", "--answer", "Approved as restated." })
			local log = fakecli.log(h)
			t.expect(count(log, "claude step=z-ticket mode=ticket")).toBe(1)
			t.expect(has(log, '"make a thing, then another"')).toBe(true) -- the first message, not the answer
			t.expect(has(log, "001-ask.md, 002-question.md, 003-answer.md")).toBe(true)
			local id = string.match(log, "issues/(c%d%d%d%d)/") :: string
			t.expect(id ~= nil).toBe(true)
			t.expect(table.concat(exchangeOf(id), ",")).toBe("001-ask.md,002-question.md,003-answer.md")
			t.expect(#exchangeOf("new")).toBe(0) -- it moved, it was not copied
			t.expect(messageOf(read(id, "003-answer.md"))).toBe("Approved as restated.")
			t.expect(dateOf(read(id, "001-ask.md"))).toBe(askedAt) -- dated from the first message
			t.expect(dateOf(read(id, "003-answer.md")) > askedAt).toBe(true)
			t.expect(r.code ~= 3).toBe(true) -- the capture went on; nothing waits for the user
			-- z-design, the next step, is told the capture's messages are other steps', not its own re-run
			local at = string.find(log, "claude step=z-design", 1, true)
			t.expect(at ~= nil).toBe(true)
			local designChunk = string.sub(log, at :: number)
			t.expect(has(designChunk, "Earlier steps of this run have already exchanged messages")).toBe(true)
			t.expect(has(designChunk, "This is a re-run")).toBe(false)
			t.expect(has(designChunk, "001-ask.md, 002-question.md, 003-answer.md")).toBe(true)
		end
	)

	it("AC5: a retry of a capture that is not waiting says so and starts nothing", function()
		fakecli.clear(h)
		local r = zn({ "dispatch", "retry", "new" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout .. r.stderr, "no capture waits")).toBe(true)
		t.expect(fakecli.log(h)).toBe("")
		local withAnswer = zn({ "dispatch", "retry", "new", "--answer", "x" })
		t.expect(withAnswer.ok).toBe(false)
		t.expect(fakecli.log(h)).toBe("")
	end)

	it("AC5: a second capture in a row runs, and keeps its own words", function()
		fakecli.clear(h)
		mode("claude.z-ticket", "ticket")
		mode("claude.z-design", "ok")
		local r = zn({ "dispatch", "new", "a second thing" })
		t.expect(has(r.stdout .. r.stderr, "lost")).toBe(false)
		local log = fakecli.log(h)
		t.expect(count(log, "claude step=z-ticket mode=ticket")).toBe(1)
		local id = string.match(log, "issues/(c%d%d%d%d)/") :: string
		t.expect(id ~= nil).toBe(true)
		t.expect(table.concat(exchangeOf(id), ",")).toBe("001-ask.md")
		t.expect(messageOf(read(id, "001-ask.md"))).toBe("a second thing")
	end)

	it("AC5: a capture that failed is retried by name, with its first words", function()
		fakecli.clear(h)
		mode("claude.z-ticket", "fail")
		local r = zn({ "dispatch", "new", "a failing thing" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout, "./zn dispatch retry new")).toBe(true)
		fakecli.clear(h)
		mode("claude.z-ticket", "ticket")
		mode("claude.z-design", "ok")
		zn({ "dispatch", "retry", "new" })
		local log = fakecli.log(h)
		t.expect(count(log, "claude step=z-ticket mode=ticket")).toBe(1)
		t.expect(has(log, '"a failing thing"')).toBe(true)
		local id = string.match(log, "issues/(c%d%d%d%d)/") :: string
		t.expect(messageOf(read(id, "001-ask.md"))).toBe("a failing thing")
	end)

	it(
		"AC5: a capture waiting from before the exchange (questions.md, no ask) is cleared by a retry",
		function()
			fakecli.clear(h)
			fs.writeDir(dirOf("new"))
			fs.writeFile(`{dirOf("new")}/questions.md`, "## Q1\nold\n")
			local r = zn({ "dispatch", "retry", "new" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout .. r.stderr, "no capture waits")).toBe(true)
			t.expect(fs.isFile(`{dirOf("new")}/questions.md`)).toBe(false)
			mode("claude.z-ticket", "ticket")
			mode("claude.z-design", "ok")
			zn({ "dispatch", "new", "after the old one" })
			t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1)
		end
	)

	it("AC5: a new capture sets an abandoned earlier exchange aside and never deletes it", function()
		fakecli.clear(h)
		mode("claude.z-ticket", "questions")
		t.expect(zn({ "dispatch", "new", "first words" }).code).toBe(3)
		t.expect(table.concat(exchangeOf("new"), ",")).toBe("001-ask.md,002-question.md")
		-- the user gives up on that capture: the question is removed by hand, no answer is given
		fs.removeFile(`{dirOf("new")}/questions.md`)
		t.expect(zn({ "dispatch", "new", "second words" }).code).toBe(3)
		local aside: { string } = {}
		for _, name in files(dirOf("new")) do
			if string.sub(name, 1, 9) == "exchange-" then
				table.insert(aside, name)
			end
		end
		t.expect(#aside).toBe(1)
		t.expect(table.concat(files(`{dirOf("new")}/{aside[1]}`), ",")).toBe("001-ask.md,002-question.md")
		t.expect(messageOf(read("new", "001-ask.md"))).toBe("second words")
		t.expect(table.concat(exchangeOf("new"), ",")).toBe("001-ask.md,002-question.md")
	end)

	it(
		"AC5: a capture whose z-ticket landed its issue and died is not captured twice by the retry",
		function()
			fakecli.clear(h)
			fs.removeFile(`{dirOf("new")}/questions.md`) -- the user abandoned the capture left waiting by the case before
			mode("claude.z-ticket", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[./zn new issue c landed-thing --project pickman --desc landed; kill -9 "$ZN_DISPATCHER_PID"]]
			)
			zn({ "dispatch", "new", "words whose capture dies" })
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(1)
			landOther("another-sessions-issue") -- lands after the capture's own, on origin beside it
			-- a check that cannot tell what the capture made refuses: a git whose fetch fails (a network blip)
			local realGit = string.gsub(process.exec("sh", { "-c", "command -v git" }).stdout, "%s+$", "")
			local marker = `{h.f.base}/fetch-fails`
			fs.writeFile(
				`{h.bin}/git`,
				`#!/bin/sh\nif [ -e "{marker}" ] && [ "$1" = fetch ]; then echo "fetch failed" >&2; exit 128; fi\nexec {realGit} "$@"\n`
			)
			process.exec("chmod", { "+x", `{h.bin}/git` })
			fs.writeFile(marker, "")
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local blind = zn({ "dispatch", "retry", "new" })
			t.expect(blind.ok).toBe(false)
			t.expect(has(blind.stdout .. blind.stderr, "cannot tell whether this capture made an issue"))
				.toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(0) -- the retry started nothing
			fs.removeFile(marker)
			fs.removeFile(`{h.bin}/git`)
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local r = zn({ "dispatch", "retry", "new" })
			local out = r.stdout .. r.stderr
			t.expect(r.ok).toBe(true)
			-- it adopts this capture's issue alone: one id, not the other session's
			local id = string.match(out, "(c%d%d%d%d) was made by this capture")
			t.expect(id ~= nil).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(0) -- the retry started nothing
			t.expect(table.concat(exchangeOf(id :: string), ",")).toBe("001-ask.md") -- the conversation moved to it
			t.expect(#exchangeOf("new")).toBe(0)
			-- and the slot is free again
			local again = zn({ "dispatch", "retry", "new" })
			t.expect(again.ok).toBe(true)
		end
	)

	it("AC5: new words are not taken over a failed capture, which keeps its words for the retry", function()
		fakecli.clear(h)
		task.wait(4) -- the step the killed dispatcher left behind ends by itself; its run is held until then
		mode("claude.z-ticket", "fail")
		t.expect(zn({ "dispatch", "new", "words A" }).ok).toBe(false)
		local b = zn({ "dispatch", "new", "words B" })
		t.expect(b.ok).toBe(false)
		t.expect(has(b.stdout .. b.stderr, "still has its words")).toBe(true)
		t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(1)
		t.expect(messageOf(read("new", "001-ask.md"))).toBe("words A")
	end)

	it(
		"AC5: a capture waiting for its answer is retried although another session made an issue meanwhile",
		function()
			zn({ "dispatch", "retry", "new", "--forget-exchange" })
			fakecli.clear(h)
			mode("claude.z-ticket", "questions")
			t.expect(zn({ "dispatch", "new", "words kept for the answer" }).code).toBe(3)
			landOther("someone-elses-thing")
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			mode("claude.z-design", "ok")
			local r = zn({ "dispatch", "retry", "new", "--answer", "Approved." })
			t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1) -- it ran
			t.expect(has(r.stdout .. r.stderr, "was made since this capture began")).toBe(false)
			t.expect(#exchangeOf("new")).toBe(0) -- the exchange moved to the issue the capture made
		end
	)

	it("AC5: a failed capture beside an issue another session made is retried, with no flag", function()
		fakecli.clear(h)
		mode("claude.z-ticket", "fail")
		zn({ "dispatch", "new", "words of a capture that fails" })
		landOther("an-issue-landed-meanwhile")
		fakecli.clear(h)
		mode("claude.z-ticket", "ticket")
		mode("claude.z-design", "ok")
		local r = zn({ "dispatch", "retry", "new" })
		t.expect(has(r.stdout .. r.stderr, "was made by this capture")).toBe(false)
		t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1)
	end)

	it(
		"AC5: a z-ticket that made an issue and then asked a question fails, naming the issue, and is not captured twice",
		function()
			zn({ "dispatch", "retry", "new", "--forget-exchange" })
			fakecli.clear(h)
			mode("claude.z-ticket", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[./zn new issue c made-then-asked --project pickman --desc x; printf '## Q1\nShould I also capture the follow-up?\n' > "$ZN_DISPATCH_DIR/questions.md"]]
			)
			local r = zn({ "dispatch", "new", "make one thing" })
			local out = r.stdout .. r.stderr
			t.expect(r.code ~= 3).toBe(true) -- a failure, not a question that waits
			t.expect(has(out, "made")).toBe(true)
			t.expect(has(out, "and asked a question")).toBe(true)
			t.expect(fs.isFile(`{dirOf("new")}/questions.md`)).toBe(false) -- set aside, not waiting
			t.expect(table.concat(exchangeOf("new"), ",")).toBe("001-ask.md") -- the question did not enter the exchange
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local again = zn({ "dispatch", "retry", "new", "--answer", "No, just the one." })
			local out2 = again.stdout .. again.stderr
			t.expect(again.ok).toBe(true)
			t.expect(has(out2, "was made by this capture")).toBe(true)
			t.expect(has(out2, "your --answer was not taken")).toBe(true)
			local id2 = string.match(out2, "(c%d%d%d%d) was made by this capture")
			t.expect(id2 ~= nil).toBe(true)
			t.expect(table.concat(exchangeOf(id2 :: string), ",")).toBe("001-ask.md") -- the ask moved to the issue it made
			t.expect(#exchangeOf("new")).toBe(0)
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(0) -- the retry started nothing
		end
	)

	it(
		"AC5: a retry that --forget-exchange cannot serve is refused before the capture's words are set aside",
		function()
			zn({ "dispatch", "retry", "new", "--forget-exchange" })
			fakecli.clear(h)
			mode("claude.z-ticket", "questions")
			t.expect(zn({ "dispatch", "new", "precious words" }).code).toBe(3)
			local before = table.concat(exchangeOf("new"), ",")
			local folder = table.concat(files(dirOf("new")), ",")
			local r = zn({ "dispatch", "retry", "new", "--forget-exchange", "--answer", "x" })
			t.expect(r.ok).toBe(false)
			t.expect(
				has(
					r.stdout .. r.stderr,
					"--forget-exchange drops the capture, so --answer has nothing to answer"
				)
			).toBe(true)
			t.expect(table.concat(exchangeOf("new"), ",")).toBe(before) -- nothing moved
			t.expect(table.concat(files(dirOf("new")), ",")).toBe(folder) -- no exchange-forgotten folder appeared
		end
	)
end)
