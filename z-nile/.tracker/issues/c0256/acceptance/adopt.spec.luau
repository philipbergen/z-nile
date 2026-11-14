--!strict
-- c0256 AC9 and AC10 (found by R0093 code review 001, F1 and F2), for real with fake CLIs (@tests/lib/fakecli). F1: `./zn dispatch retry new` (or a
-- z-ticket step that ends well) adopts the issue its capture made; the issue may already be a run of its own, so the
-- adoption takes the issue's run lock, joins its state (never replaces it) and sets a question left in the slot aside.
-- F2: a relative --answer-file is the file where ./zn was run, not at the checkout's root.
-- Fixture under .cache/c0256-adopt.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local runner = require("@znile/engine/runner")
local t = require("@tests/lib/t")
local task = require("@lune/task")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[roles.idea]
model = "claude-sonnet-5"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 5000
fallbacks = []

[roles.idea-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
fallbacks = []

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
fallbacks = []

[roles.implementation]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
fallbacks = []

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []

[roles.final-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
fallbacks = []
]]

local h: fakecli.Harness

-- Waits (up to 60 s of wall clock, measured with os.time) until no run left behind by a killed dispatcher still holds
-- its lock: the step it left ends by itself, and its run lock and the dispatcher's own are free then. A failing expect
-- names the wait when it runs out. The lock test is the engine's own (runner.held).
local function waitForLeftOverRuns()
	local root = `{h.f.main}/.cache/dispatch`
	local function anyHeld(): string?
		if not fs.isDir(root) then
			return nil
		end
		for _, name in fs.readDir(root) do
			for _, lockName in { "run.lock", "lock" } do
				if runner.held(`{root}/{name}/{lockName}`) then
					return `{name}/{lockName}`
				end
			end
		end
		return nil
	end
	local start = os.time()
	local held = anyHeld()
	while held ~= nil and os.time() - start < 60 do
		task.wait(0.2)
		held = anyHeld()
	end
	t.expect(held == nil or `the step the killed dispatcher left behind still holds {held} after 60 s`)
		.toBe(true)
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
local function exchangeOf(id: string): string
	return table.concat(files(`{dirOf(id)}/exchange`), ",")
end
local function steps(id: string): string
	local out: { string } = {}
	for _, a in fakecli.state(h, id).history do
		table.insert(out, `{a.step}:{a.outcome}`)
	end
	return table.concat(out, ",")
end
local function refusedQuestions(dir: string): number
	local n = 0
	for _, name in files(dir) do
		if string.match(name, "^questions%-refused%-%d+%.md$") then
			n += 1
		end
	end
	return n
end
local function askedIssue(out: string): string
	local id = string.match(out, "made (c%d%d%d%d) and asked a question")
	if id == nil then
		error(`the capture did not fail naming its issue: {out}`)
	end
	return id
end

-- z-ticket makes an issue, then writes questions.md: the capture fails naming the issue
local function madeAndAsked(words: string, slug: string): (string, string)
	fakecli.clear(h)
	mode("claude.z-ticket", "script")
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`./zn new issue c {slug} --project pickman --desc x; printf '## Q1\\nShould I capture the follow-up?\\n' > "$ZN_DISPATCH_DIR/questions.md"`
	)
	local r = zn({ "dispatch", "new", words })
	t.expect(r.ok).toBe(false)
	return askedIssue(r.stdout .. r.stderr), r.stdout .. r.stderr
end

return t.spec("c0256 adopting the issue a capture made, and a caller-relative --answer-file", function(it)
	it("sets up a tracker with .models.toml, an issue and the fake CLIs", function()
		h = fakecli.new("c0256-adopt", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
		})
		t.expect(fs.isDir(h.f.main)).toBe(true)
	end)

	it(
		"AC9: the issue keeps its own run (z-design's attempt), gains the capture's exchange and seal",
		function()
			local id = madeAndAsked("make one thing", "made-then-asked")
			fakecli.clear(h)
			mode("claude.z-design", "ok")
			local d = zn({ "dispatch", "z-design", id })
			t.expect(d.ok).toBe(true)
			t.expect(steps(id)).toBe("z-design:ok")
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local r = zn({ "dispatch", "retry", "new", "--answer", "No, just the one." })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout .. r.stderr, `{id} was made by this capture`)).toBe(true)
			t.expect(steps(id)).toBe("z-design:ok") -- not replaced by the slot's z-ticket attempts
			local st = fakecli.state(h, id)
			t.expect(st.step).toBe("z-design")
			t.expect(st.mode).toBe("step")
			t.expect(exchangeOf(id)).toBe("001-ask.md")
			t.expect(exchangeOf("new")).toBe("")
			t.expect(st.sealed ~= nil and st.sealed["001-ask.md"] ~= nil).toBe(true)
			-- the next step on the issue starts: its exchange is sealed, not "changed" or "cannot be used"
			fakecli.clear(h)
			mode("claude.z-design", "ok")
			local again = zn({ "dispatch", "z-design", id })
			local out = again.stdout .. again.stderr
			t.expect(has(out, "cannot be used")).toBe(false)
			t.expect(has(out, "changed")).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1)
			t.expect(again.ok).toBe(true)
		end
	)

	it(
		"AC9: an issue whose own step asked has its exchange joined to the capture's by retry new, in order",
		function()
			local id, stop = madeAndAsked("make a joined thing", "made-asked-then-designed")
			-- the stop names the adoption first and going on with the issue second
			t.expect(has(stop, `./zn dispatch retry new gives {id} its conversation`)).toBe(true)
			t.expect(has(stop, `./zn dispatch {id} goes on with the issue`)).toBe(true)
			fakecli.clear(h)
			mode("claude.z-design", "questions") -- the user goes on with the issue, and its z-design asks
			local d = zn({ "dispatch", id })
			t.expect(d.code).toBe(3)
			t.expect(exchangeOf(id)).toBe("001-question.md")
			local ownState = fakecli.state(h, id)
			t.expect(ownState.step).toBe("z-design")
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local r = zn({ "dispatch", "retry", "new", "--answer", "No, keep it separate." })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout .. r.stderr, `{id} was made by this capture`)).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(0) -- the retry started nothing
			-- the capture's message first, the issue's own question after it: only the number changed
			t.expect(exchangeOf(id)).toBe("001-ask.md,002-question.md")
			t.expect(exchangeOf("new")).toBe("")
			local question = fs.readFile(`{dirOf(id)}/exchange/002-question.md`)
			t.expect(has(question, "step: z-design")).toBe(true)
			t.expect(has(question, "Which scope?")).toBe(true)
			t.expect(has(fs.readFile(`{dirOf(id)}/exchange/001-ask.md`), "make a joined thing")).toBe(true)
			-- the old folder is set aside, never deleted
			local aside = 0
			for _, name in files(dirOf(id)) do
				if string.find(name, "exchange-before-adoption", 1, true) == 1 then
					aside += 1
					t.expect(table.concat(files(`{dirOf(id)}/{name}`), ",")).toBe("001-question.md")
				end
			end
			t.expect(aside).toBe(1)
			-- the issue keeps its own run
			local st = fakecli.state(h, id)
			t.expect(st.step).toBe("z-design")
			t.expect(steps(id)).toBe("z-design:ok")
			t.expect(
				st.sealed ~= nil and st.sealed["001-ask.md"] ~= nil and st.sealed["002-question.md"] ~= nil
			)
				.toBe(true)
			t.expect(st.sealed["001-question.md"]).toBe(nil)
			-- its waiting question is still the user's to answer, and the answer lands after the joined messages
			fakecli.clear(h)
			mode("claude.z-design", "ok")
			zn({ "dispatch", "retry", id, "--answer", "x" }) -- the fake z-design claims nothing, so the chain stops after it
			t.expect(count(fakecli.log(h), "claude step=z-design")).toBe(1) -- the step was re-run
			t.expect(exchangeOf(id)).toBe("001-ask.md,002-question.md,003-answer.md")
			t.expect(has(fakecli.log(h), "This is a re-run")).toBe(true)
			-- the slot is free for new words, which run z-ticket
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local next = zn({ "dispatch", "new", "other words" })
			t.expect(has(next.stdout .. next.stderr, "retry new re-runs")).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1)
			t.expect(has(fakecli.log(h), '"other words"')).toBe(true)
		end
	)

	it("AC9: an issue whose run is live is not adopted; nothing moves", function()
		local id = madeAndAsked("make another thing", "held-by-a-live-run")
		fakecli.clear(h)
		mode("claude.z-design", "script")
		fs.writeFile(
			`{h.fakes}/script.sh`,
			`touch "$FAKE_DIR/running"; n=0; while [ ! -e "$FAKE_DIR/release" ] && [ $n -lt 600 ]; do sleep 0.1; n=$((n+1)); done`
		)
		local live: fixture.Result? = nil
		task.spawn(function()
			live = zn({ "dispatch", "z-design", id })
		end)
		local waited = 0
		while not fs.isFile(`{h.fakes}/running`) and waited < 120 do
			waited += task.wait(0.2)
		end
		t.expect(fs.isFile(`{h.fakes}/running`)).toBe(true)
		local slot = table.concat(files(dirOf("new")), ",")
		local issueFolder = table.concat(files(dirOf(id)), ",")
		local slotState = fs.readFile(`{dirOf("new")}/state.json`)
		local r = zn({ "dispatch", "retry", "new" })
		fs.writeFile(`{h.fakes}/release`, "")
		local out = r.stdout .. r.stderr
		t.expect(r.ok).toBe(false)
		t.expect(has(out, id)).toBe(true)
		t.expect(has(out, "being dispatched")).toBe(true)
		t.expect(exchangeOf("new")).toBe("001-ask.md") -- still the slot's
		t.expect(slot).toBe(table.concat(files(dirOf("new")), ","))
		t.expect(fs.readFile(`{dirOf("new")}/state.json`)).toBe(slotState)
		t.expect(table.concat(files(dirOf(id)), ",")).toBe(issueFolder)
		t.expect(fs.isDir(`{dirOf(id)}/exchange`)).toBe(false) -- no exchange appeared in the issue's folder
		local waitedEnd = 0
		while live == nil and waitedEnd < 120 do
			waitedEnd += task.wait(0.2)
		end
		t.expect(live ~= nil).toBe(true)
		-- once its run ends, the same retry adopts the issue
		fakecli.clear(h)
		mode("claude.z-ticket", "ticket")
		local after = zn({ "dispatch", "retry", "new" })
		t.expect(after.ok).toBe(true)
		t.expect(has(after.stdout .. after.stderr, `{id} was made by this capture`)).toBe(true)
		t.expect(exchangeOf(id)).toBe("001-ask.md")
	end)

	it(
		"AC9: a capture that died holding a question has it set aside, and the slot takes new words",
		function()
			fakecli.clear(h)
			mode("claude.z-ticket", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				[[./zn new issue c died-with-a-question --project pickman --desc x; printf '## Q1\nAnything else?\n' > "$ZN_DISPATCH_DIR/questions.md"; kill -9 "$ZN_DISPATCHER_PID"]]
			)
			zn({ "dispatch", "new", "words whose capture dies" })
			t.expect(count(fakecli.log(h), "claude step=z-ticket")).toBe(1)
			local asideBefore = refusedQuestions(dirOf("new")) -- earlier cases set theirs aside too
			waitForLeftOverRuns()
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			local r = zn({ "dispatch", "retry", "new" })
			local out = r.stdout .. r.stderr
			t.expect(r.ok).toBe(true)
			t.expect(has(out, "was made by this capture")).toBe(true)
			t.expect(has(out, "the question z-ticket left was set aside as")).toBe(true)
			t.expect(fs.isFile(`{dirOf("new")}/questions.md`)).toBe(false)
			t.expect(refusedQuestions(dirOf("new"))).toBe(asideBefore + 1)
			fakecli.clear(h)
			mode("claude.z-ticket", "ticket")
			mode("claude.z-design", "ok")
			local next = zn({ "dispatch", "new", "other words" })
			t.expect(has(next.stdout .. next.stderr, "waits for your answer")).toBe(false)
			t.expect(has(next.stdout .. next.stderr, "retry new re-runs")).toBe(false)
			t.expect(count(fakecli.log(h), "claude step=z-ticket mode=ticket")).toBe(1)
			t.expect(has(fakecli.log(h), '"other words"')).toBe(true)
		end
	)

	it(
		"AC10: a relative --answer-file is read from where ./zn was run, not from the checkout's root",
		function()
			fakecli.clear(h)
			mode("claude.z-design", "questions")
			local first = zn({ "dispatch", "z-design", "c0010" })
			t.expect(first.code).toBe(3)
			local sub = `{h.f.main}/.cache/askhere`
			fs.writeDir(sub)
			fs.writeFile(`{sub}/answer.md`, "the answer beside the caller")
			fs.writeFile(`{h.f.main}/answer.md`, "the answer at the root")
			fakecli.clear(h)
			mode("claude.z-design", "ok")
			local env: { [string]: string } = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_AGENT_TOKEN_FILE = h.token,
				ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
				GH_TOKEN = "the-users-token",
			}
			local r = fixture.exec(
				h.f.main,
				"bash",
				{ "-c", "cd .cache/askhere && ../../zn dispatch retry c0010 --answer-file answer.md" },
				{ env = env }
			)
			t.expect(r.ok).toBe(true)
			local stored = fs.readFile(`{dirOf("c0010")}/exchange/002-answer.md`)
			t.expect(has(stored, "the answer beside the caller")).toBe(true)
			t.expect(has(stored, "the answer at the root")).toBe(false)
			-- an absolute path is read as it is
			local abs = `{h.f.base}/abs-answer.md`
			fs.writeFile(abs, "absolute words")
			fakecli.clear(h)
			mode("claude.z-design", "questions")
			t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(3)
			mode("claude.z-design", "ok")
			local a = fixture.exec(
				h.f.main,
				"bash",
				{ "-c", `cd .cache/askhere && ../../zn dispatch retry c0010 --answer-file {abs}` },
				{ env = env }
			)
			t.expect(a.ok).toBe(true)
			t.expect(has(fs.readFile(`{dirOf("c0010")}/exchange/004-answer.md`), "absolute words")).toBe(true)
			-- run from a folder outside the checkout: the file beside the caller, not the one of the same name at the root
			fs.writeFile(`{h.f.base}/outside.md`, "the answer outside the checkout")
			fs.writeFile(`{h.f.main}/outside.md`, "the answer at the root, not outside")
			fakecli.clear(h)
			mode("claude.z-design", "questions")
			t.expect(zn({ "dispatch", "z-design", "c0010" }).code).toBe(3)
			mode("claude.z-design", "ok")
			local outside = fixture.exec(
				h.f.main, -- the shell leaves the checkout at once (fixture.exec runs only inside one)
				"bash",
				{ "-c", `cd {h.f.base} && {h.f.main}/zn dispatch retry c0010 --answer-file outside.md` },
				{ env = env }
			)
			t.expect(outside.ok).toBe(true)
			local outsideStored = fs.readFile(`{dirOf("c0010")}/exchange/006-answer.md`)
			t.expect(has(outsideStored, "the answer outside the checkout")).toBe(true)
			t.expect(has(outsideStored, "the answer at the root")).toBe(false)
		end
	)
end)
