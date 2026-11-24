--!strict
-- f0421: a review on the model that wrote the text is allowed, and the record says so wherever the reviewer's model is
-- recorded: `./zn spend --phase design-review`, `./zn commit --phase code-review`, a dispatched review's row and `./zn idea`'s
-- challenge row. The writers' models are the spend rows of the item (reviewrec); the reviewer's is the `--model` recorded.
-- Fixtures under .cache; the rows are read back from the item's folder.
local buffer = require("@znile/engine/buffer")
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local ledger = require("@znile/engine/ledger")
local process = require("@lune/process")
local reviewrec = require("@znile/engine/reviewrec")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ROOT = "pickman/.tracker"
local RAFT = "R0010"
local A, B = "c0010", "c0020"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'

local function has(s: string, part: string): boolean
	return string.find(s, part, 1, true) ~= nil
end

local function note(writer: string): string
	return `(same-model: reviewed on {writer}'s model, which wrote the text)`
end

local function row(phase: string, model: string): ledger.Row
	return {
		when = "2026-11-21 10:00",
		subject = phase,
		added = 0,
		removed = 0,
		minutes = 0,
		how = "explicit",
		phase = phase,
		tokens = 10,
		model = model,
	}
end

local function issue(id: string, raft: string): string
	return `---\nid: {id}\ntype: chore\ntitle: {id}\nslug: {id}\nraft: {raft}\ndepends_on: []\nemergent: false\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {id}\n\n### Touched modules\n- \`notes/{id}\`\n\n### Notes\nx\n`
end

-- every spend row in a folder (the ledger and the measured rows), with its phase and subject
local function rowsIn(dir: string): { ledger.Row }
	local out: { ledger.Row } = {}
	if fs.isFile(`{dir}/spend.md`) then
		local parsed = ledger.parse(fs.readFile(`{dir}/spend.md`))
		if parsed then
			for _, r in parsed.rows do
				table.insert(out, r)
			end
		end
	end
	local folder = `{dir}/spend.d`
	if fs.isDir(folder) then
		for _, name in fs.readDir(folder) do
			if string.sub(name, -4) == ".tsv" then
				local parsed = buffer.parseTsv(fs.readFile(`{folder}/{name}`))
				if parsed then
					for _, r in parsed do
						table.insert(out, r)
					end
				end
			end
		end
	end
	return out
end

local function subjectsOf(rows: { ledger.Row }, phase: string): { string }
	local out: { string } = {}
	for _, r in rows do
		if r.phase == phase then
			table.insert(out, r.subject)
		end
	end
	return out
end

return t.spec("f0421: a review on the writer's own model is recorded as such", function(it)
	it("reviewrec names the writer a review's model matches, and none for another model", function()
		local writers = { "claude-sonnet-5-5-medium", "claude-opus-5-5-high" }
		t.expect(reviewrec.matched("claude-opus-5-5-xhigh", writers)).toBe("claude-opus-5-5-high")
		t.expect(reviewrec.matched("claude-haiku-5-5-low", writers)).toBe(nil)
		t.expect(reviewrec.matched("claude-opus-5-5-high", {})).toBe(nil)
		t.expect(reviewrec.note("claude-opus-5-5-high")).toBe(note("claude-opus-5-5-high"))
	end)

	it(
		"./zn commit --phase code-review on a writer's model records the note on the row, and on another model does not",
		function()
			local seed: { [string]: string } = {
				[`{ROOT}/rafts/active/{RAFT}/{RAFT}.md`] = `---\nid: {RAFT}\ntype: chore\ntitle: Rec\nslug: rec\nsingle: false\nissues: [{A}, {B}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n`,
				[`{ROOT}/rafts/active/{RAFT}/check.sh`] = CHECK,
				[`{ROOT}/issues/active/{A}/{A}.md`] = issue(A, RAFT),
				[`{ROOT}/issues/active/{A}/check.sh`] = CHECK,
				[`{ROOT}/issues/active/{A}/spend.md`] = ledger.append(
					nil,
					A,
					A,
					row("build", "claude-opus-5-5-high")
				),
				[`{ROOT}/issues/active/{B}/{B}.md`] = issue(B, RAFT),
				[`{ROOT}/issues/active/{B}/check.sh`] = CHECK,
			}
			local f = trackerfix.new("review-record-commit", seed)
			fixture.git(f.main, { "checkout", "-q", "-b", `{RAFT}/1/{B}` })
			local function review(model: string, n: number): { string }
				fs.writeDir(`{f.main}/notes/{B}`)
				fs.writeFile(`{f.main}/notes/{B}/r{n}.txt`, "1\n2\n3\n")
				local r = fixture.exec(
					f.main,
					"./zn",
					{ "commit", "-m", `review {n}`, "--phase", "code-review", "--model", model }
				)
				if not r.ok then
					error(`commit failed ({r.code}): {r.stderr}{r.stdout}`)
				end
				local all = rowsIn(`{f.main}/{ROOT}/issues/active/{A}`)
				for _, x in rowsIn(`{f.main}/{ROOT}/issues/active/{B}`) do
					table.insert(all, x)
				end
				local out: { string } = {}
				for _, s in subjectsOf(all, "code-review") do
					if has(s, `review {n}`) then
						table.insert(out, s)
					end
				end
				return out
			end
			local same = review("claude-opus-5-5-xhigh", 1) -- the writer's model at another effort: the same model
			t.expect(#same > 0).toBe(true)
			t.expect(has(same[1], note("claude-opus-5-5-high"))).toBe(true)
			local other = review("claude-sonnet-5-5-medium", 2)
			t.expect(#other > 0).toBe(true)
			t.expect(has(other[1], "same-model")).toBe(false)
		end
	)

	it(
		"f0421 slice 3: ./zn commit on the session's declared model (ZN_MODEL) marks the row (declared)",
		function()
			local seed: { [string]: string } = {
				[`{ROOT}/rafts/active/{RAFT}/{RAFT}.md`] = `---\nid: {RAFT}\ntype: chore\ntitle: Rec\nslug: rec\nsingle: false\nissues: [{A}]\ndesign: ready\ncreated: 2026-11-10\nstatus: prepared-quiet-copper-falcon\n---\n\n# {RAFT}\n`,
				[`{ROOT}/rafts/active/{RAFT}/check.sh`] = CHECK,
				[`{ROOT}/issues/active/{A}/{A}.md`] = issue(A, RAFT),
				[`{ROOT}/issues/active/{A}/check.sh`] = CHECK,
			}
			local f = trackerfix.new("review-record-declared", seed)
			fixture.git(f.main, { "checkout", "-q", "-b", `{RAFT}/1/{A}` })
			local function commit(n: number, model: string, env: { [string]: string }): string
				fs.writeDir(`{f.main}/notes/{A}`)
				fs.writeFile(`{f.main}/notes/{A}/d{n}.txt`, "1\n2\n")
				local r = fixture.exec(
					f.main,
					"./zn",
					{ "commit", "-m", `layer {n}`, "--phase", "build", "--model", model },
					{ env = env }
				)
				if not r.ok then
					error(`commit failed ({r.code}): {r.stderr}{r.stdout}`)
				end
				for _, s in subjectsOf(rowsIn(`{f.main}/{ROOT}/issues/active/{A}`), "build") do
					if has(s, `layer {n}`) then
						return s
					end
				end
				return ""
			end
			local declared =
				commit(1, "gemini-4-neon-high", { ZN_CLI = "agy", ZN_MODEL = "gemini-4-neon-high" })
			t.expect(has(declared, "(declared)")).toBe(true)
			-- review-005 F4: a row on another model than the declared one is recorded and says so
			local other =
				commit(2, "gemini-4-neon-high", { ZN_CLI = "agy", ZN_MODEL = "gemini-4-argon-high" })
			t.expect(has(other, "(declared; the session declared ZN_MODEL=gemini-4-argon-high)")).toBe(true)
			-- an agent session names no model, and the engine reads none: its row is declared
			local agent = commit(3, "claude-opus-5-5-high", { ZN_CLI = "agent" })
			t.expect(has(agent, "(declared)")).toBe(true)
			-- a claude row is never marked
			local claude = commit(4, "claude-opus-5-5-high", { ZN_CLI = "claude" })
			t.expect(has(claude, "declared")).toBe(false)
		end
	)

	it("review-005 F4: ./zn spend on an agy session marks its row (declared)", function()
		local seed: { [string]: string } = {
			[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
			[`{ROOT}/issues/c0030/c0030.md`] = trackerfix.stub(
				"c0030",
				"thirty",
				"prepared-quiet-copper-falcon"
			),
		}
		local f = trackerfix.new("review-record-spend-declared", seed)
		local wt = trackerfix.trOk(f, f.main, { "worktree", "spend-declared" })
		trackerfix.trOk(f, wt, { "sync" })
		local function spent(n: number, env: { [string]: string }): string
			local r = trackerfix.tr(f, wt, {
				"spend",
				"c0030",
				"--phase",
				"prep",
				"--model",
				"gemini-4-neon-high",
				"--note",
				`round {n}`,
			}, env)
			if not r.ok then
				error(`spend failed ({r.code}): {r.stderr}{r.stdout}`)
			end
			for _, s in subjectsOf(rowsIn(`{wt}/{ROOT}/issues/c0030`), "prep") do
				if has(s, `round {n}`) then
					return s
				end
			end
			return ""
		end
		t.expect(has(spent(1, { ZN_CLI = "agy", ZN_MODEL = "gemini-4-neon-high" }), "(declared)")).toBe(true)
		t.expect(has(spent(2, { ZN_CLI = "claude" }), "declared")).toBe(false)
	end)

	it(
		"./zn spend --phase design-review records the note on the row when the reviewer's model wrote the design",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = fs.readFile(`{TOP}/.gitignore`),
				[`{ROOT}/issues/c0030/c0030.md`] = trackerfix.stub(
					"c0030",
					"thirty",
					"prepared-quiet-copper-falcon"
				),
				[`{ROOT}/issues/c0030/spend.md`] = ledger.append(
					nil,
					"c0030",
					"c0030",
					row("prep", "claude-opus-5-5-high")
				),
			}
			local f = trackerfix.new("review-record-spend", seed)
			local wt = trackerfix.trOk(f, f.main, { "worktree", "spend-run" })
			trackerfix.trOk(f, wt, { "sync" })
			local function spent(model: string, n: number): { string }
				local r = trackerfix.tr(
					f,
					wt,
					{ "spend", "c0030", "--phase", "design-review", "--model", model, "--note", `round {n}` },
					nil
				)
				if not r.ok then
					error(`spend failed ({r.code}): {r.stderr}{r.stdout}`)
				end
				local out: { string } = {}
				for _, s in subjectsOf(rowsIn(`{wt}/{ROOT}/issues/c0030`), "design-review") do
					if has(s, `round {n}`) then
						table.insert(out, s)
					end
				end
				return out
			end
			local same = spent("claude-opus-5-5-high", 1)
			t.expect(#same > 0).toBe(true)
			t.expect(has(same[1], note("claude-opus-5-5-high"))).toBe(true)
			local other = spent("claude-sonnet-5-5-medium", 2)
			t.expect(#other > 0).toBe(true)
			t.expect(has(other[1], "same-model")).toBe(false)
		end
	)

	it(
		"a dispatched review (a real run, not --dry-run) on the writer's model records the note with the writer that matched",
		function()
			local h = fakecli.new("review-record-dispatch", {
				[".models.toml"] = fs.readFile(`{TOP}/.models.toml`),
				[`{ROOT}/issues/c0030/c0030.md`] = trackerfix.stub(
					"c0030",
					"thirty",
					"prepared-quiet-copper-falcon"
				),
			})
			local twice = ledger.append(nil, "c0030", "c0030", row("prep", "claude-sonnet-5-5-medium"))
			twice = ledger.append(twice, "c0030", "c0030", row("prep", "claude-opus-5-5-high"))
			fakecli.advanceMain(h, { [`{ROOT}/issues/c0030/spend.md`] = twice })
			local wt = `{h.f.main}/.worktree/author`
			fixture.git(h.f.main, { "fetch", "-q", "origin", "main" })
			fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "author", wt, "origin/main" })
			local phys = fixture.physical(wt) :: string
			fakecli.mode(h, "claude.zz-review", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				"printf '# Review\\n\\nInputs: x\\n\\nVerdict: approve\\n' > \"$ZN_DISPATCH_DIR/review.md\"\n"
			)
			local r = fixture.exec(phys, "bash", {
				"scripts/tracker.sh",
				"dispatch",
				"zz-review",
				"c0030",
				"--mode",
				"design",
				"--cli",
				"claude",
			}, {
				env = {
					FAKE_DIR = h.fakes,
					PATH = `{h.bin}:{process.env.PATH}`,
					ZN_AGENT_TOKEN_FILE = h.token,
					GH_TOKEN = "the-users-token",
				},
			})
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			-- the design review resolves to claude-opus-5-5-high at normal: the writer that matched is the opus row, not the first
			local notes: { string } = {}
			for _, p in fakecli.state(h, "c0030").pending do
				table.insert(notes, p.note)
			end
			for _, x in (fakecli.rows(h, "c0030") or {}) :: { ledger.Row } do
				table.insert(notes, x.subject)
			end
			t.expect(#notes > 0).toBe(true)
			local named = false
			for _, n in notes do
				named = named or has(n, note("claude-opus-5-5-high"))
				t.expect(has(n, "claude-sonnet-5-5-medium's model")).toBe(false)
			end
			t.expect(named).toBe(true)
		end
	)
end)
