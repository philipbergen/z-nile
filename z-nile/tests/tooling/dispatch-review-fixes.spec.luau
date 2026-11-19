--!strict
-- d0415 code review 001 F3 and F4: a raft row naming a member with no folder buffers nothing (so a retry writes the
-- row once), and `dispatch status` and a run's flush survive a gate judgement's scratch tree and a link loop under the
-- dispatcher's home. A fixture under .cache/d0415-fixes; nothing here touches the real repository.
local dispatch = require("@znile/engine/dispatch")
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

[roles.raft]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = []
]]
local GROUPED = "[c0030@111111111111]"
local RAFT = "pickman/.tracker/rafts/R0095"

local function raftDoc(members: string): string
	return `---\nid: R0095\ntype: chore\ntitle: demo\nslug: demo\nissues: [{members}]\ngrouped: {GROUPED}\ncreated: 2026-01-01\nstatus: backlog-a-b-c\n---\n\n# R0095\n`
end

local h: fakecli.Harness
local wt: string

local function run(): fixture.Result
	return fixture.exec(
		wt,
		"bash",
		{ "scripts/tracker.sh", "dispatch", "zz-review", "R0095", "--mode", "raft" },
		{
			env = {
				FAKE_DIR = h.fakes,
				PATH = `{h.bin}:{process.env.PATH}`,
				ZN_AGENT_TOKEN_FILE = h.token,
				GH_TOKEN = "the-users-token",
			},
		}
	)
end

return t.spec("d0415 review 001: no partial buffer, a safe walk of the dispatcher's home", function(it)
	it(
		"sets up a raft R0095 whose review already quotes its record, and a pending row naming c0060",
		function()
			h = fakecli.new("d0415-fixes", {
				[".models.toml"] = MODELS,
				["pickman/.tracker/issues/c0030/c0030.md"] = trackerfix.stub(
					"c0030",
					"three",
					"prepared-quiet-copper-falcon"
				),
			})
			fakecli.advanceMain(h, {
				[`{RAFT}/R0095.md`] = raftDoc("c0030"),
				[`{RAFT}/design-review-001.md`] = `# Review\n\nInputs:\nGrouped: {GROUPED}\n\nVerdict: approve\n`,
			})
			fixture.git(h.f.main, { "fetch", "-q", "origin", "main" })
			wt = `{h.f.main}/.worktree/author`
			fixture.git(h.f.main, { "worktree", "add", "-q", "-b", "author", wt, "origin/main" })
			wt = fixture.physical(wt) :: string
			local old = `{h.f.main}/.cache/dispatch/c0098/zz-review-raft-R0095-1`
			fs.writeDir(old)
			fs.writeFile(
				`{old}/state.json`,
				'{"id":"R0095","dir":"'
					.. old
					.. '","mode":"step","history":[],"merged":{},"pushed":{},"pending":[{"id":"R0095","phase":"design-review","tokens":123,"minutes":1,"model":"claude-opus-5-5","note":"dispatch zz-review","members":["c0030","c0060"]}]}\n'
			)
			t.expect(#fakecli.state(h, "c0098", "zz-review-raft-R0095-1").pending).toBe(1)
		end
	)

	it("F3: a member with no folder leaves nothing buffered, and the retry writes the row once", function()
		for _ = 1, 2 do
			local r = run() -- refused before any CLI (the record is covered), but the run flushes first
			t.expect(r.ok).toBe(false)
		end
		t.expect(#((fakecli.rows(h, "c0030") or {}) :: any)).toBe(0)
		t.expect(#fakecli.state(h, "c0098", "zz-review-raft-R0095-1").pending).toBe(1)
		fakecli.advanceMain(h, {
			["pickman/.tracker/issues/c0060/c0060.md"] = trackerfix.stub(
				"c0060",
				"five",
				"prepared-quiet-copper-falcon"
			),
		})
		run()
		local rows = fakecli.rows(h, "c0030") :: any
		t.expect(#rows).toBe(1)
		t.expect(rows[1].tokens).toBe(123)
	end)

	it("F4: a judge-* scratch tree and a link loop under the home leave dispatch status working", function()
		local home = `{h.f.main}/.cache/dispatch`
		fs.writeDir(`{home}/judge-1-2-3/c0077`)
		fs.writeFile(`{home}/judge-1-2-3/c0077/state.json`, "not json")
		local loop = fixture.exec(h.f.main, "ln", { "-s", home, `{home}/c0098/zz-review-raft-R0095-1/loop` })
		t.expect(loop.ok).toBe(true)
		local status = fakecli.zn(h, { "dispatch", "status", "R0095" })
		t.expect(status.ok).toBe(true)
		t.expect(run().ok).toBe(false)
	end)

	-- final review 001 F1: a design review of an item that has left the backlog says its row will not be written
	it(
		"F1: a review of an active item prints UNRECORDED spend with the fate, and keeps one pending row",
		function()
			local doc = (
				string.gsub(
					trackerfix.stub("c0070", "five", "active-quiet-copper-falcon"),
					"design: draft",
					"design: ready"
				)
			)
			fakecli.advanceMain(h, { ["pickman/.tracker/issues/active/c0070/c0070.md"] = doc })
			fixture.git(wt, { "fetch", "-q", "origin", "main" })
			fixture.git(wt, { "merge", "-q", "--no-edit", "FETCH_HEAD" })
			fakecli.clear(h)
			fakecli.mode(h, "claude.zz-review", "script")
			fs.writeFile(
				`{h.fakes}/script.sh`,
				"printf '# Review\\n\\nInputs: x\\n\\nVerdict: approve\\n' > \"$ZN_DISPATCH_DIR/review.md\"\n"
			)
			local r = fixture.exec(
				wt,
				"bash",
				{ "scripts/tracker.sh", "dispatch", "zz-review", "c0070", "--mode", "design" },
				{
					env = {
						FAKE_DIR = h.fakes,
						PATH = `{h.bin}:{process.env.PATH}`,
						ZN_AGENT_TOKEN_FILE = h.token,
						GH_TOKEN = "the-users-token",
					},
				}
			)
			if not r.ok then
				error(r.stdout .. r.stderr)
			end
			t.expect(string.find(r.stderr, "UNRECORDED spend", 1, true) ~= nil).toBe(true)
			t.expect(string.find(r.stderr, "never written: c0070 is active", 1, true) ~= nil).toBe(true)
			t.expect(#fakecli.state(h, "c0070").pending).toBe(1)
		end
	)

	-- code review 001 F1: the chain writes a raft's kept row on its members before z-ready moves the raft
	it("the follow writes a nested raft row on the member, once", function()
		local doc = (
			string.gsub(
				trackerfix.stub("c0030", "three", "prepared-quiet-copper-falcon"),
				"raft: \n",
				"raft: R0095\n"
			)
		)
		fakecli.advanceMain(h, {
			["pickman/.tracker/issues/c0030/c0030.md"] = (string.gsub(doc, "design: draft", "design: ready")),
		})
		local nested = `{h.f.main}/.cache/dispatch/c0030/zz-review-raft-R0095-1`
		fs.writeDir(nested)
		fs.writeFile(
			`{nested}/state.json`,
			'{"id":"R0095","dir":"'
				.. nested
				.. '","mode":"step","history":[],"merged":{},"pushed":{},"pending":[{"id":"R0095","phase":"design-review","tokens":321,"minutes":1,"model":"claude-opus-5-5","note":"follow","members":["c0030"]}]}\n'
		)
		local before = #((fakecli.rows(h, "c0030") or {}) :: any)
		fakecli.zn(h, { "dispatch", "c0030" })
		t.expect(#((fakecli.rows(h, "c0030") or {}) :: any)).toBe(before + 1)
		t.expect(#fakecli.state(h, "c0030", "zz-review-raft-R0095-1").pending).toBe(0)
		fakecli.zn(h, { "dispatch", "c0030" })
		t.expect(#((fakecli.rows(h, "c0030") or {}) :: any)).toBe(before + 1)
	end)

	it("F5: a deliver row that waits for its raft is not reported as never written", function()
		local fate = dispatch.pendingFate("R0099", "deliver", "active", true)
		t.expect(string.find(fate, "written once R0099 is done", 1, true) ~= nil).toBe(true)
		t.expect(string.find(fate, "never written", 1, true) == nil).toBe(true)
		local old = dispatch.pendingFate("R0070", "design-review", "backlog", false)
		t.expect(string.find(old, "document was not in the step", 1, true) ~= nil).toBe(true)
	end)
end)
