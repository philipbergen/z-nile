--!strict
-- R0093 code review 001 F1 and F2, for real with fake CLIs (@tests/lib/fakecli). F1: `./zn dispatch retry new` (or a
-- z-ticket step that ends well) adopts the issue its capture made; the issue may already be a run of its own, so the
-- adoption takes the issue's run lock, joins its state (never replaces it) and sets a question left in the slot aside.
-- F2: a relative --answer-file is the file where ./zn was run, not at the checkout's root.
-- Fixture under .cache/r0093-adopt.
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
local function madeAndAsked(words: string, slug: string): string
	fakecli.clear(h)
	mode("claude.z-ticket", "script")
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`./zn new issue c {slug} --project pickman --desc x; printf '## Q1\\nShould I capture the follow-up?\\n' > "$ZN_DISPATCH_DIR/questions.md"`
	)
	local r = zn({ "dispatch", "new", words })
	t.expect(r.ok).toBe(false)
	return askedIssue(r.stdout .. r.stderr)
end

return t.spec(
	"R0093 F1 F2: adopting the issue a capture made, and a caller-relative --answer-file",
	function(it)
		it("sets up a tracker with .models.toml, an issue and the fake CLIs", function()
			h = fakecli.new("r0093-adopt", {
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
			"F1a: the issue keeps its own run (z-design's attempt), gains the capture's exchange and seal",
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

		it("F1b: an issue whose run is live is not adopted; nothing moves", function()
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
			"F1c: a capture that died holding a question has it set aside, and the slot takes new words",
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
				task.wait(4) -- the step the killed dispatcher left behind ends by itself; its run is held until then
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
			"F2: a relative --answer-file is read from where ./zn was run, not from the checkout's root",
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
				t.expect(has(fs.readFile(`{dirOf("c0010")}/exchange/004-answer.md`), "absolute words"))
					.toBe(true)
			end
		)
	end
)
