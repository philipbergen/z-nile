--!strict
-- d0415 AC1 to AC5: `./zn dispatch zz-review` files, refuses and keeps reviews, and records their spend, against fake CLIs
-- (@tests/lib/fakecli) in a fixture under .cache/d0415-dispatch, from a worktree of it. One raft (R0095, on the fixture's
-- origin, members c0030 and c0040) goes through a refold, a second review of the same record, a review lost to a race
-- and later runs of the same item; a raft that is only local (R0090) shows the unrecorded spend. The cases build on each
-- other, round after round of the same raft. Nothing here touches the real repository.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
stall_seconds = 120
tool_seconds = 240

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = []

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []

[roles.code-review]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []
]]

-- the raft's records: what z-raft grouped first, after the refold, and after a second refold
local FIRST = "[c0030@111111111111]"
local FOLD = "[c0030@111111111111, c0040@222222222222]"
local FOLD2 = "[c0030@111111111111, c0040@333333333333]"
local RAFT = "pickman/.tracker/rafts/R0095"

local h: fakecli.Harness
local wt: string

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function znIn(args: { string }): fixture.Result
	local argv = { "scripts/tracker.sh" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(wt, "bash", argv, {
		env = {
			FAKE_DIR = h.fakes,
			PATH = `{h.bin}:{process.env.PATH}`,
			ZN_AGENT_TOKEN_FILE = h.token,
			GH_TOKEN = "the-users-token",
		},
	})
end
local function names(dir: string, prefix: string): { string }
	local out = {}
	if fs.isDir(dir) then
		for _, name in fs.readDir(dir) do
			if string.sub(name, 1, #prefix) == prefix then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end
local function raftDoc(id: string, members: string, grouped: string): string
	return `---\nid: {id}\ntype: chore\ntitle: demo\nslug: demo\nissues: [{members}]\ngrouped: {grouped}\ncreated: 2026-01-01\nstatus: backlog-a-b-c\n---\n\n# {id}\n`
end
local function review(grouped: string, marker: string): string
	return `# Review\\n\\nInputs:\\nGrouped: {grouped}\\n\\n{marker}\\n\\nVerdict: approve\\n`
end
-- a reviewer that writes its review in its state folder, and, when `race` is a file name, also files one of its own in
-- the raft's folder while it runs (a second reviewer, or the author, filing first)
local function reviewer(grouped: string, marker: string, race: string?)
	fakecli.clear(h) -- clears the modes and the script too
	fakecli.mode(h, "claude.zz-review", "script")
	local extra = ""
	if race then
		extra = `; d=$(./zn find R0095); printf '# Racing\\n\\nGrouped: {grouped}\\n' > "$d/{race}"`
	end
	fs.writeFile(
		`{h.fakes}/script.sh`,
		`sleep 1; printf '{review(grouped, marker)}' > "$ZN_DISPATCH_DIR/review.md"{extra}\n`
	)
end
local function setGrouped(value: string, members: string?)
	local doc = `{wt}/{RAFT}/R0095.md`
	fs.writeFile(doc, raftDoc("R0095", members or "c0030, c0040", value))
end
local function dispatchRaft(id: string): fixture.Result
	return znIn({ "dispatch", "zz-review", id, "--mode", "raft" })
end

local first: fixture.Result
local refused: fixture.Result
local rowsBefore = 0

return t.spec("d0415 dispatched reviews: filing, refusing, keeping and recording", function(it)
	it(
		"sets up a fixture with a raft R0095 of two members on origin, and an author's worktree of it",
		function()
			h = fakecli.new("d0415-dispatch", {
				[".models.toml"] = MODELS,
				["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
					"c0010",
					"one",
					"new-quiet-copper-falcon"
				),
				["pickman/.tracker/issues/c0020/c0020.md"] = trackerfix.stub(
					"c0020",
					"two",
					"prepared-quiet-copper-falcon"
				),
				["pickman/.tracker/issues/c0030/c0030.md"] = trackerfix.stub(
					"c0030",
					"three",
					"prepared-quiet-copper-falcon"
				),
				["pickman/.tracker/issues/c0040/c0040.md"] = trackerfix.stub(
					"c0040",
					"four",
					"prepared-quiet-copper-falcon"
				),
			})
			fakecli.advanceMain(h, {
				[`{RAFT}/R0095.md`] = raftDoc("R0095", "c0030", FIRST), -- origin/main: before the refold
				[`{RAFT}/design-review-001.md`] = `# Review\n\nInputs:\nGrouped: {FIRST}\n\nVerdict: approve\n`,
			})
			fixture.git(h.f.main, { "fetch", "-q", "origin", "main" })
			wt = `{h.f.main}/.worktree/author`
			fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "author", wt, "origin/main" })
			wt = fixture.physical(wt) :: string
			setGrouped(FOLD) -- the refold: a second member joined, the record changed, the one review quotes the older one
			t.expect(names(`{wt}/{RAFT}`, "design-review-")).toEqual({ "design-review-001.md" })
		end
	)

	it(
		"AC1: a refolded raft's review is filed as the next design-review-NNN.md and the older one is left as it was",
		function()
			reviewer(FOLD, "run one")
			first = dispatchRaft("R0095")
			if not first.ok then
				error(first.stdout .. first.stderr)
			end
			t.expect(names(`{wt}/{RAFT}`, "design-review-"))
				.toEqual({ "design-review-001.md", "design-review-002.md" })
			t.expect(has(fs.readFile(`{wt}/{RAFT}/design-review-002.md`), `Grouped: {FOLD}`)).toBe(true)
			t.expect(has(fs.readFile(`{wt}/{RAFT}/design-review-001.md`), `Grouped: {FIRST}`)).toBe(true)
		end
	)

	-- origin/main's R0095 lists c0030 only; the author's worktree (the refold) lists c0030 and c0040: the row is shared
	-- among the members the worktree gives the raft, as ./zn spend run there would
	it("AC5: a raft's review row is written to its members the way ./zn spend shares it", function()
		local one = fakecli.rows(h, "c0030")
		local two = fakecli.rows(h, "c0040")
		t.expect(one ~= nil and two ~= nil).toBe(true)
		local a = (one :: any)[#(one :: any)]
		local b = (two :: any)[#(two :: any)]
		t.expect(a.phase).toBe("design-review")
		t.expect(a.subject).toBe("design-review-002")
		t.expect(a.tokens).toBe(123)
		t.expect(b.subject).toBe("design-review-002")
		t.expect(b.tokens == nil or b.tokens == 0).toBe(true)
		t.expect(#(fakecli.state(h, "R0095").pending or {})).toBe(0)
		rowsBefore = #(one :: any) + #(two :: any)
	end)

	it("AC2: the same record again is refused and no second review is filed", function()
		reviewer(FOLD, "run two")
		refused = dispatchRaft("R0095")
		t.expect(refused.ok).toBe(false)
		t.expect(has(refused.stdout .. refused.stderr, "design-review-002.md")).toBe(true)
		t.expect(has(refused.stdout .. refused.stderr, "there is no second round")).toBe(true)
		t.expect(names(`{wt}/{RAFT}`, "design-review-"))
			.toEqual({ "design-review-001.md", "design-review-002.md" })
		t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/R0095/review.md`)).toBe(false)
	end)

	it("AC3: a raft refusal starts no CLI and spends zero tokens", function()
		t.expect(fakecli.log(h)).toBe("") -- fakecli.clear ran before the refused run, and no CLI wrote to it
		local s = fakecli.state(h, "R0095")
		t.expect(s.outcome).toBe("failed")
		t.expect(s.tokens).toBe(0)
		t.expect(has(s.detail, "there is no second round")).toBe(true)
		t.expect(#(s.pending or {})).toBe(0)
		local one = fakecli.rows(h, "c0030") :: any
		local two = fakecli.rows(h, "c0040") :: any
		t.expect(#one + #two).toBe(rowsBefore)
	end)

	it(
		"AC3: a design-mode second review is refused before any CLI starts, as is every refusal the folder decides",
		function()
			local dir = `{wt}/pickman/.tracker/issues/c0010`
			fs.writeFile(`{dir}/design-review-001.md`, "# Review\n\nVerdict: approve\n")
			fs.writeFile(`{dir}/review-001.md`, "# Review\n\nVerdict: approve\n")
			for _, mode in { "design", "code" } do
				reviewer(FOLD, "never")
				local r = znIn({ "dispatch", "zz-review", "c0010", "--mode", mode })
				t.expect(r.ok).toBe(false)
				t.expect(has(r.stdout .. r.stderr, "there is no further round")).toBe(true)
				t.expect(fakecli.log(h)).toBe("")
				t.expect(fakecli.state(h, "c0010").tokens).toBe(0)
			end
			t.expect(names(dir, "design-review-")).toEqual({ "design-review-001.md" })
		end
	)

	it(
		"AC4: a review that cannot be filed after the run is kept as review-unfiled-N.md, and the failure names it",
		function()
			setGrouped(FOLD2, "c0020, c0030, c0040") -- a second refold, a lower member joins: not covered by 001 or 002
			reviewer(FOLD2, "run three", "design-review-003.md") -- a rival review of the same record lands first
			local r = dispatchRaft("R0095")
			t.expect(r.ok).toBe(false)
			local kept = `{h.f.main}/.cache/dispatch/R0095/review-unfiled-1.md`
			t.expect(fs.isFile(kept)).toBe(true)
			t.expect(has(fs.readFile(kept), "run three")).toBe(true)
			t.expect(fs.isFile(`{h.f.main}/.cache/dispatch/R0095/review.md`)).toBe(false)
			local said = r.stdout .. r.stderr
			t.expect(has(said, "review-unfiled-1.md")).toBe(true)
			t.expect(has(fakecli.state(h, "R0095").detail, "review-unfiled-1.md")).toBe(true)
			t.expect(names(`{wt}/{RAFT}`, "design-review-")).toEqual({
				"design-review-001.md",
				"design-review-002.md",
				"design-review-003.md",
			})
			t.expect(has(fs.readFile(`{wt}/{RAFT}/design-review-003.md`), "Racing")).toBe(true) -- the rival is not overwritten
			-- the failed run's tokens are on the lowest member of the worktree's list, c0020, which origin's list lacks
			local lowest = fakecli.rows(h, "c0020") :: any
			t.expect(lowest ~= nil).toBe(true)
			t.expect(lowest[#lowest].tokens).toBe(123)
			t.expect(lowest[#lowest].subject).toBe("dispatch zz-review")
		end
	)

	it("AC4: a later run of the same item neither deletes nor overwrites a kept review", function()
		fs.removeFile(`{wt}/{RAFT}/design-review-003.md`)
		reviewer(FOLD2, "run four", "design-review-003.md")
		local r = dispatchRaft("R0095")
		t.expect(r.ok).toBe(false)
		local dir = `{h.f.main}/.cache/dispatch/R0095`
		t.expect(has(fs.readFile(`{dir}/review-unfiled-1.md`), "run three")).toBe(true)
		t.expect(has(fs.readFile(`{dir}/review-unfiled-2.md`), "run four")).toBe(true)
		-- a person removed review-unfiled-1.md: the next number is one past the highest (3), never the count (2)
		fs.removeFile(`{dir}/review-unfiled-1.md`)
		fs.removeFile(`{wt}/{RAFT}/design-review-003.md`)
		reviewer(FOLD2, "run five", "design-review-003.md")
		local r5 = dispatchRaft("R0095")
		t.expect(r5.ok).toBe(false)
		t.expect(has(fs.readFile(`{dir}/review-unfiled-3.md`), "run five")).toBe(true)
		t.expect(has(fs.readFile(`{dir}/review-unfiled-2.md`), "run four")).toBe(true)
		-- a third run whose reviewer writes nothing: the start of a run clears review.md only
		fs.removeFile(`{wt}/{RAFT}/design-review-003.md`)
		fs.writeFile(`{h.fakes}/script.sh`, "sleep 1\n")
		fakecli.mode(h, "claude.zz-review", "script")
		local r3 = znIn({ "dispatch", "zz-review", "R0095", "--mode", "raft" })
		t.expect(r3.ok).toBe(false)
		t.expect(has(fakecli.state(h, "R0095").detail, "the reviewer wrote no review")).toBe(true)
		t.expect(names(dir, "review-unfiled-")).toEqual({ "review-unfiled-2.md", "review-unfiled-3.md" })
		t.expect(has(fs.readFile(`{dir}/review-unfiled-2.md`), "run four")).toBe(true)
	end)

	it(
		"AC5: a row that cannot be recorded stays pending, is printed as unrecorded spend, and is listed by dispatch status",
		function()
			-- R0090 is only in this worktree: origin has no folder for it, so its row cannot be written anywhere
			local dir = `{wt}/pickman/.tracker/rafts/R0090`
			fs.writeDir(dir)
			fs.writeFile(`{dir}/R0090.md`, raftDoc("R0090", "c0030, c0040", "[]"))
			reviewer(FOLD, "run five")
			fs.writeFile(
				`{dir}/R0090.md`,
				(string.gsub(fs.readFile(`{dir}/R0090.md`), "grouped: %[%]\n", ""))
			)
			local r = dispatchRaft("R0090")
			fs.removeDir(dir)
			t.expect(r.ok).toBe(true) -- the review was filed; only its spend row is not on a ledger
			local said = r.stdout .. r.stderr
			t.expect(has(said, "UNRECORDED spend")).toBe(true)
			t.expect(has(said, "123 tokens")).toBe(true)
			local s = fakecli.state(h, "R0090")
			t.expect(#s.pending).toBe(1)
			t.expect(s.pending[1].tokens).toBe(123)
			t.expect(s.pending[1].phase).toBe("design-review")
			local status = fakecli.zn(h, { "dispatch", "status", "R0090" })
			t.expect(
				has(status.stdout, "unrecorded spend (never written while origin/main does not list R0090)")
			)
				.toBe(true)
			t.expect(has(status.stdout, "123 tokens")).toBe(true)
		end
	)

	-- a review its author started (a nested run) keeps its state in a folder of its own under the author's
	it(
		"AC5: a nested run's unrecorded row is listed by dispatch status and ./zn metrics, and a later run of the item writes it once",
		function()
			local parent = `{h.f.main}/.cache/dispatch/c0099`
			fs.writeDir(parent)
			local dir = `{wt}/pickman/.tracker/rafts/R0091`
			fs.writeDir(dir)
			fs.writeFile(
				`{dir}/R0091.md`,
				(string.gsub(raftDoc("R0091", "c0030", "[]"), "grouped: %[%]\n", ""))
			)
			reviewer(FIRST, "run six")
			local r = fixture.exec(
				wt,
				"bash",
				{ "scripts/tracker.sh", "dispatch", "zz-review", "R0091", "--mode", "raft" },
				{
					env = {
						FAKE_DIR = h.fakes,
						PATH = `{h.bin}:{process.env.PATH}`,
						ZN_AGENT_TOKEN_FILE = h.token,
						GH_TOKEN = "the-users-token",
						ZN_DISPATCH_DIR = parent,
					},
				}
			)
			t.expect(r.ok).toBe(true)
			local nested = `{parent}/zz-review-raft-R0091-1`
			t.expect(fs.isFile(`{nested}/state.json`)).toBe(true)
			t.expect(#fakecli.state(h, "c0099", "zz-review-raft-R0091-1").pending).toBe(1)
			t.expect(#(fakecli.state(h, "c0099", "zz-review-raft-R0091-1").pending[1].members or {})).toBe(1)
			local status = fakecli.zn(h, { "dispatch", "status", "R0091" })
			t.expect(
				has(status.stdout, "unrecorded spend (never written while origin/main does not list R0091)")
			)
				.toBe(true)
			t.expect(has(status.stdout, "zz-review-raft-R0091-1/state.json")).toBe(true)
			local metrics = fakecli.zn(h, { "metrics" })
			t.expect(has(metrics.stdout, "Unrecorded dispatcher spend")).toBe(true)
			t.expect(has(metrics.stdout, "R0091 design-review 123 tokens")).toBe(true)
			-- the raft reaches origin/main: its next run writes the row on its member, once, and the nested file lets go of it
			fakecli.advanceMain(
				h,
				{ ["pickman/.tracker/rafts/R0091/R0091.md"] = raftDoc("R0091", "c0030", "[]") }
			)
			local before = #(fakecli.rows(h, "c0030") :: any)
			local again = fakecli.zn(h, { "dispatch", "status", "R0091" })
			t.expect(has(again.stdout, "unrecorded spend (written by the next run of R0091)")).toBe(true)
			local second = znIn({ "dispatch", "zz-review", "R0091", "--mode", "raft" }) -- refused before any CLI, but the run flushes first
			t.expect(second.ok).toBe(false)
			local rows = fakecli.rows(h, "c0030") :: any
			t.expect(#rows).toBe(before + 1)
			t.expect(rows[#rows].subject).toBe("design-review-001")
			t.expect(rows[#rows].tokens).toBe(123)
			t.expect(#fakecli.state(h, "c0099", "zz-review-raft-R0091-1").pending).toBe(0)
			local third = znIn({ "dispatch", "zz-review", "R0091", "--mode", "raft" })
			t.expect(third.ok).toBe(false)
			t.expect(#(fakecli.rows(h, "c0030") :: any)).toBe(before + 1)
			fs.removeDir(dir)
		end
	)

	it("AC5: a pending raft row recorded before this change is never written, and says so", function()
		-- R0070's rows of 2026-11-17: a raft id, a backlog raft on origin, no members stored on the row
		local old = `{h.f.main}/.cache/dispatch/c0098`
		fs.writeDir(old)
		fs.writeFile(
			`{old}/state.json`,
			'{"id":"c0098","dir":"'
				.. old
				.. '","mode":"step","history":[],"merged":{},"pushed":{},"pending":[{"id":"R0095","phase":"design-review","tokens":77,"minutes":1,"model":"claude-opus-5-5-xhigh","note":"dispatch zz-review"}]}\n'
		)
		local status = fakecli.zn(h, { "dispatch", "status", "R0095" })
		t.expect(
			has(status.stdout, "never written: R0095's row was recorded before d0415 and names no members")
		)
			.toBe(true)
		t.expect(has(status.stdout, "77 tokens")).toBe(true)
		local before = #(fakecli.rows(h, "c0030") :: any) + #(fakecli.rows(h, "c0040") :: any)
		setGrouped(FOLD) -- the record design-review-002 quotes: this run is refused
		reviewer(FOLD, "run seven")
		local r = dispatchRaft("R0095") -- refused before any CLI, but the run flushes first
		t.expect(r.ok).toBe(false)
		t.expect(#(fakecli.rows(h, "c0030") :: any) + #(fakecli.rows(h, "c0040") :: any)).toBe(before)
		t.expect(#fakecli.state(h, "c0098").pending).toBe(1)
	end)
end)
