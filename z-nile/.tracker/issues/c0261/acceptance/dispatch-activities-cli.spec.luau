--!strict
-- c0261: `./zn dispatch zz-review --mode design [--final]` starts the CLI with the model of the activity it runs (the
-- round on the way cheap, the final round expensive through the zz-review fallback), writes the row with that model,
-- refuses a final stream review, and `--dry-run` names the activity. Fake CLIs (@tests/lib/fakecli), fixture under
-- .cache/c0261-dispatch.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local dispatch = require("@znile/engine/dispatch")
local dispatcher = require("@znile/engine/dispatcher")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude"]

[dispatch]
stall_seconds = 5
tool_seconds = 8

[z-design.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000

[zz-review-design.claude]
model = "claude-sonnet-5"
rank = 2
runtime = "claude-cli"
max_tokens = 5000
]]

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function znIn(dir: string, args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			ZN_WATERMARK_DIR = `{h.f.base}/watermark`,
			GH_TOKEN = "the-users-token",
		},
	})
end
local function reviewer()
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`sleep 1; printf '# Review\\n\\nVerdict: approve\\n' > "$ZN_DISPATCH_DIR/review.md"\n`
	)
end
local function lastRow(id: string): any
	local rows = fakecli.rows(h, id)
	return rows and rows[#rows]
end

return t.spec("c0261 ./zn dispatch picks the model of the activity", function(it)
	it("sets up a tracker with the activity tables and a worktree for the issue", function()
		h = fakecli.new("c0261-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub("c0010", "first-thing", "new-quiet-copper-falcon"),
		})
		local r = fakecli.zn(h, { "dispatch", "z-design", "c0010" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
	end)

	it("a round on the way starts the cheap model and records it; --final starts the expensive one (AC10)", function()
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		reviewer()
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(fakecli.log(h), "--model claude-sonnet-5")).toBe(true)
		t.expect(has(fakecli.log(h), "--model claude-opus-5-5")).toBe(false)
		t.expect(lastRow("c0010").model).toBe("claude-sonnet-5")
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/design-review-001.md`)
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		reviewer()
		local f = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design", "--final" })
		if not f.ok then
			error(f.stdout .. f.stderr)
		end
		t.expect(has(fakecli.log(h), "--model claude-opus-5-5")).toBe(true)
		t.expect(lastRow("c0010").model).toBe("claude-opus-5-5")
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/design-review-001.md`)
	end)

	it("a code review with no table of its own takes the expensive model (AC10)", function()
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		fakecli.clear(h)
		fakecli.mode(h, "claude.zz-review", "script")
		reviewer()
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "code" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(fakecli.log(h), "--model claude-opus-5-5")).toBe(true)
		fs.removeFile(`{wt}/pickman/.tracker/issues/c0010/review-001.md`)
	end)

	it("a final stream review is refused and starts no CLI; --dry-run names the activity (AC10)", function()
		local wt = fixture.physical(`{h.f.main}/.worktree/prep-first-thing`) :: string
		fakecli.clear(h)
		local r = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "stream", "--final" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "stream")).toBe(true)
		t.expect(has(fakecli.log(h), "step=zz-review")).toBe(false)
		local d = znIn(wt, { "dispatch", "zz-review", "c0010", "--mode", "design", "--final", "--dry-run" })
		t.expect(has(d.stdout, "activity=zz-review-design-final")).toBe(true)
		t.expect(has(d.stdout, "model=claude-opus-5-5")).toBe(true)
	end)

	-- the poll itself, run for real against a fake gh that counts its calls and answers a sequence of exit codes (the
	-- runner's `./zn run --time` wrapper is cut off: it only bounds). every = 0 and a deadline of 2 to 4 seconds keep it quick.
	it("the wait command re-polls while checks are pending, ends 0 when they pass, 2 when one fails, 3 when time runs out (AC4)", function()
		fs.writeFile(
			`{h.bin}/gh`,
			'#!/bin/bash\ncase "$*" in\n "pr view"*) echo "$FAKE_STATE";;\n "pr checks"*)\n n=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$FAKE_COUNT"\n seq=($FAKE_SEQ); rc=${seq[$((n-1))]:-${seq[${#seq[@]}-1]}}\n echo "$FAKE_OUT"; exit $rc;;\nesac\n'
		)
		process.exec("chmod", { "+x", `{h.bin}/gh` })
		local count = `{h.f.base}/gh-count`
		local function run(what: string, env: { [string]: string }, seconds: number?): (number, number)
			fs.writeFile(count, "0")
			-- a deadline of a few seconds, so a loaded machine cannot end a poll before its second call
			local command: string = (dispatch :: any).waitCommand(what, 42, seconds or 4, 0)
			local inner = string.match(command, "%-%- (bash %-c .*)$") :: string
			local e = { PATH = `{h.bin}:{process.env.PATH}`, FAKE_COUNT = count }
			for k, v in env do
				e[k] = v
			end
			local code = fixture.exec(h.f.main, "bash", { "-c", inner }, { env = e }).code
			return code, tonumber(fs.readFile(count)) :: number
		end
		local code, calls = run("checks", { FAKE_SEQ = "8", FAKE_OUT = "pending" }, 2)
		t.expect(code).toBe(3) -- pending until the deadline is "ran out", not "failed"
		t.expect(calls > 1).toBe(true) -- and it polled more than once
		code, calls = run("checks", { FAKE_SEQ = "8 0", FAKE_OUT = "x" })
		t.expect(code).toBe(0)
		t.expect(calls).toBe(2)
		code = run("checks", { FAKE_SEQ = "1 0", FAKE_OUT = "no checks reported on the branch" })
		t.expect(code).toBe(0)
		code = run("checks", { FAKE_SEQ = "1", FAKE_OUT = "build failed" })
		t.expect(code).toBe(2) -- the same unexplained failure three times in a row
		code = run("checks", { FAKE_SEQ = "1 8 1 0", FAKE_OUT = "gh: network error" })
		t.expect(code).toBe(0) -- a transient error between good polls is not a failed check
		code = run("checks", { FAKE_SEQ = "1 1 0", FAKE_OUT = "gh: network error" })
		t.expect(code).toBe(0)
		t.expect((run("merged", { FAKE_STATE = "MERGED" }))).toBe(0)
		t.expect((run("merged", { FAKE_STATE = "CLOSED" }))).toBe(2)
		t.expect((run("merged", { FAKE_STATE = "OPEN" }))).toBe(3)
	end)

	it("parsePr reads GitHub's mergeable state: CONFLICTING conflicts, UNKNOWN (still computing) does not, missing does not (AC5)", function()
		local function pr(mergeable: string?): any
			local field = if mergeable then `,"mergeable":"{mergeable}"` else ""
			return dispatcher.parsePr(`\{"number":7,"state":"OPEN","isDraft":false,"headRefOid":"abc","statusCheckRollup":[]{field}\}`)
		end
		t.expect(pr("MERGEABLE").mergeable).toBe(true)
		t.expect(pr("MERGEABLE").conflicting).toBe(false)
		t.expect(pr("CONFLICTING").mergeable).toBe(false)
		t.expect(pr("CONFLICTING").conflicting).toBe(true)
		t.expect(pr("UNKNOWN").mergeable).toBe(false)
		t.expect(pr("UNKNOWN").conflicting).toBe(false)
		t.expect(pr(nil).conflicting).toBe(false)
		t.expect(pr("UNKNOWN").mergeState).toBe("UNKNOWN")
		t.expect(pr("MERGEABLE").mergeState).toBe("MERGEABLE")
		local function rollup(entries: string): any
			return dispatcher.parsePr(`\{"number":7,"state":"OPEN","isDraft":false,"headRefOid":"abc","mergeable":"MERGEABLE","statusCheckRollup":[{entries}]\}`)
		end
		t.expect(rollup('\{"conclusion":"FAILURE"\}').failed).toBe(true)
		t.expect(rollup('\{"conclusion":"SUCCESS"\},\{"state":"PENDING"\}').failed).toBe(false)
		t.expect(rollup('\{"conclusion":"SUCCESS"\},\{"state":"PENDING"\}').green).toBe(false)
	end)
end)
