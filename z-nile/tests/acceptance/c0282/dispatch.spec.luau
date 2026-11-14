--!strict
-- c0282 AC6, AC7 (through the dispatcher): a dispatched step gets ZN_ACTOR from the spec of the attempt that runs it
-- (a fallthrough's second attempt its own, a dotted model id normalised); the rafting gate merges a rafting PR whose
-- member folders carry `rafted` rows in provenance.md appended to what main holds, and refuses any other row, an edited
-- old row or another file, each for its own reason; and a script step records the user who started the pipeline and
-- the step it ran under. Fake CLIs and a fixture under .cache (tests/lib/fakecli), as c0117's guards.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep", "raft"]
stall_seconds = 3

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = ["grok"]

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
]]

local function HEADER(id: string): string
	return `# Provenance: {id}\n\n| when | event | actor | detail |\n|---|---|---|---|\n`
end

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
local function prepared(id: string, slug: string): string
	return (
		string.gsub(
			trackerfix.stub(id, slug, "prepared-quiet-copper-falcon"),
			"design: draft",
			"design: ready"
		)
	)
end

return t.spec("c0282 provenance through the dispatcher", function(it)
	it("sets up a tracker, a prepared pair for the rafting gate, and the fake CLIs", function()
		h = fakecli.new("c0282-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0020/c0020.md"] = trackerfix.stub(
				"c0020",
				"second-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0096/c0096.md"] = prepared("c0096", "rafted-thing"),
			["pickman/.tracker/issues/c0096/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0096/acceptance/a.spec.luau\n",
			["pickman/.tracker/issues/c0096/.models.toml"] = '[dispatch]\nauto_merge = ["raft"]\n',
			-- the prep PR's approval is already on main when the rafting PR appends its row
			["pickman/.tracker/issues/c0096/provenance.md"] = HEADER("c0096")
				.. "| 2026-11-08 09:00 | approved | human:Ann | design=aaaaaaaaaaaa |\n",
			["pickman/.tracker/issues/c0022/c0022.md"] = (
				string.gsub(prepared("c0022", "scripted-thing"), "created: ", "size: 300\ncreated: ", 1)
			),
			["pickman/.tracker/issues/c0021/c0021.md"] = trackerfix.stub(
				"c0021",
				"third-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0021/.models.toml"] = "[dispatch]\nauto_merge = []\n",
			["pickman/.tracker/issues/c0091/c0091.md"] = prepared("c0091", "member-thing"),
			["pickman/.tracker/issues/c0091/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0091/acceptance/a.spec.luau\n",
			-- an active raft with its active member, and a backlog raft: a rafting PR writes neither one's record
			["pickman/.tracker/rafts/active/R0040/R0040.md"] = "---\nid: R0040\nslug: a-raft\ntitle: an active raft\nissues: [c0093]\n---\n",
			["pickman/.tracker/rafts/active/R0040/check.sh"] = "bash members-check.sh\n",
			["pickman/.tracker/issues/active/c0093/c0093.md"] = (
				string.gsub(prepared("c0093", "active-member"), "\nraft: \n", "\nraft: R0040\n", 1)
			),
			["pickman/.tracker/issues/active/c0093/check.sh"] = "bash acceptance.sh\n",
			["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\nslug: a-raft\ntitle: a backlog raft\nissues: []\n---\n",
			["pickman/.tracker/rafts/R0041/check.sh"] = "bash members-check.sh\n",
		})
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
	end)

	it("each attempt's ZN_ACTOR is its own spec: model, version and effort, one spelling", function()
		fakecli.clear(h)
		fs.writeFile(`{h.fakes}/script.sh`, 'echo "actor=$ZN_ACTOR" >> "$FAKE_DIR/log"\n')
		fakecli.mode(h, "claude.z-design", "scriptquota")
		fakecli.mode(h, "grok.z-design", "script")
		local r = zn({ "dispatch", "z-design", "c0010" })
		if not r.ok then
			error(r.stdout .. r.stderr .. fakecli.log(h))
		end
		local l = fakecli.log(h)
		t.expect(has(l, "actor=agent:claude-opus-5-5 effort high\n")).toBe(true)
		t.expect(has(l, "actor=agent:grok-4-7 effort high\n")).toBe(true)
	end)

	it(
		"the rafting gate merges a rafted row in provenance.md beside raft:, and refuses any other row or file",
		function()
			fakecli.clear(h)
			local url = "https://github.com/zn-fixture/c0282-dispatch.git"
			fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			local function prJson(n: number, head: string): string
				return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{head}"\}`
			end
			local function onMain(path: string): string
				return fixture.git(h.f.origin, { "show", `main:{path}` })
			end
			local c96, c91 =
				"pickman/.tracker/issues/c0096/c0096.md", "pickman/.tracker/issues/c0091/c0091.md"
			local function rafted(doc: string): string
				return (string.gsub(doc, "\nraft: \n", "\nraft: R0050\n", 1))
			end
			local ACTOR = "agent:claude-sonnet-5-5 effort high"
			-- a plain replacement (the actor holds pattern characters)
			local function swap(text: string, from: string, to: string): string
				local at = string.find(text, from, 1, true) :: number
				return string.sub(text, 1, at - 1) .. to .. string.sub(text, at + #from)
			end
			local p96, p91 =
				"pickman/.tracker/issues/c0096/provenance.md", "pickman/.tracker/issues/c0091/provenance.md"
			-- the rows a rafting PR may add: its own, appended to what main already holds
			local function appended(path: string, id: string, event: string): string
				local old = fixture.exec(h.f.origin, "git", { "show", `main:{path}` })
				local row = `| 2026-11-08 10:00 | {event} | {ACTOR} | raft=R0050 |\n`
				return (if old.ok then old.stdout else HEADER(id)) .. row
			end
			local raftDocText = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096, c0091]\n---\n"
			local function gate(
				n: number,
				rec96: string,
				rec91: string,
				more: { [string]: string }?
			): fixture.Result
				local files: { [string]: string } = {
					["pickman/.tracker/rafts/R0050/R0050.md"] = raftDocText,
					[c96] = rafted(onMain(c96)),
					[c91] = rafted(onMain(c91)),
					["pickman/.tracker/issues/c0096/provenance.md"] = rec96,
					["pickman/.tracker/issues/c0091/provenance.md"] = rec91,
				}
				local extra: { [string]: string } = more or {}
				for k, v in extra do
					files[k] = v
				end
				local sha = fakecli.pullRequest(h, n, files)
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(n, sha))
				return zn({ "dispatch", "c0096" })
			end
			-- refused, each for its own reason: a delivered row (not a rafting PR's), an approval, the prep PR's approved
			-- row (already on main) edited, a second file beside the record
			local cases: { { r96: string, r91: string, more: { [string]: string }?, why: string } } = {
				{
					r96 = appended(p96, "c0096", "delivered"),
					r91 = appended(p91, "c0091", "rafted"),
					why = "delivered row is not published here",
				},
				{
					r96 = appended(p96, "c0096", "rafted"),
					r91 = appended(p91, "c0091", "approved"),
					why = "approved row is not published here",
				},
				{
					r96 = (string.gsub(appended(p96, "c0096", "rafted"), "human:Ann", "human:Eve", 1)),
					r91 = appended(p91, "c0091", "rafted"),
					why = "row 1 differs from origin/main",
				},
				{
					r96 = appended(p96, "c0096", "rafted"),
					r91 = appended(p91, "c0091", "rafted"),
					more = { ["pickman/.tracker/issues/c0091/notes.md"] = "x\n" },
					why = "notes.md: a rafting PR changes only a backlog issue's raft: line",
				},
				-- a record of an issue that is no longer in the backlog, and a raft's record
				{
					r96 = appended(p96, "c0096", "rafted"),
					r91 = appended(p91, "c0091", "rafted"),
					more = {
						["pickman/.tracker/issues/active/c0093/provenance.md"] = HEADER("c0093")
							.. "| 2026-11-08 10:00 | rafted | "
							.. ACTOR
							.. " | raft=R0050 |\n",
					},
					why = "an issue in active/",
				},
				{
					r96 = appended(p96, "c0096", "rafted"),
					r91 = appended(p91, "c0091", "rafted"),
					more = {
						["pickman/.tracker/rafts/R0041/provenance.md"] = HEADER("R0041")
							.. "| 2026-11-08 10:00 | rafted | "
							.. ACTOR
							.. " | raft=R0050 |\n",
					},
					why = "does not write a raft's record",
				},
				-- a row on an issue whose raft: line the PR does not move
				{
					r96 = appended(p96, "c0096", "rafted"),
					r91 = appended(p91, "c0091", "rafted"),
					more = {
						["pickman/.tracker/issues/c0022/provenance.md"] = HEADER("c0022")
							.. "| 2026-11-08 10:00 | rafted | "
							.. ACTOR
							.. " | raft=R0050 |\n",
					},
					why = "but not c0022's raft: line",
				},
				-- a row naming a raft the PR does not carry, and one naming another raft than the issue's
				{
					r96 = (string.gsub(appended(p96, "c0096", "rafted"), "raft=R0050 |", "raft=R0999 |")),
					r91 = appended(p91, "c0091", "rafted"),
					why = "detail is not raft=R0050",
				},
				-- an actor no command writes: unknown, or a git-derived form
				{
					r96 = swap(appended(p96, "c0096", "rafted"), ACTOR, "unknown"),
					r91 = appended(p91, "c0091", "rafted"),
					why = "not a live form",
				},
				{
					r96 = swap(appended(p96, "c0096", "rafted"), ACTOR, "human:Ann (from git)"),
					r91 = appended(p91, "c0091", "rafted"),
					why = "not a live form",
				},
				{
					r96 = (string.gsub(
						appended(p96, "c0096", "rafted"),
						"raft=R0050 |",
						"raft=R0050; via=bogus |"
					)),
					r91 = appended(p91, "c0091", "rafted"),
					why = "detail is not raft=R0050",
				},
			}
			for i, case in cases do
				fakecli.clear(h)
				local r = gate(40 + i, case.r96, case.r91, case.more)
				if r.code ~= 4 or not has(r.stdout, case.why) then
					error(`case {i} expected exit 4 and "{case.why}"\n{r.stdout}{r.stderr}`)
				end
				t.expect(has(fakecli.log(h), `realgh pr merge {40 + i} `)).toBe(false)
			end
			local function cut(n: number): string
				return fakecli.pullRequest(h, n, {
					["pickman/.tracker/rafts/R0050/R0050.md"] = raftDocText,
					[c96] = rafted(onMain(c96)),
					[c91] = rafted(onMain(c91)),
					[p96] = appended(p96, "c0096", "rafted"),
					[p91] = appended(p91, "c0091", "rafted"),
				})
			end
			-- PR #50 is cut, then main gains a row on c0096 (a rank, a confirmation): the PR is stale and the gate refuses it
			fakecli.clear(h)
			local early = cut(50)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(50, early))
			trackerfix.elsewhere(h.f, {
				[p96] = fixture.git(h.f.origin, { "show", `main:{p96}` })
					.. "\n| 2026-11-08 09:30 | ranked | human:Ann | rank=3 |\n",
			}, "a rank on c0096")
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
			local stale = zn({ "dispatch", "c0096" })
			t.expect(stale.code).toBe(4)
			t.expect(has(stale.stdout, "run ./zn sync")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge 50 ")).toBe(false)
			-- the synced PR #51 carries what the engine's union yields: main's rows (approved, ranked) first, then ours; the gate merges it
			fakecli.clear(h)
			local sha = cut(51)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(51, sha))
			local r = zn({ "dispatch", "c0096" })
			if not has(fakecli.log(h), `realgh pr merge 51 --squash --match-head-commit {sha}`) then
				error(`PR #51 did not merge\n{r.stdout}{r.stderr}`)
			end
		end
	)
	it("a script step records the user who started the pipeline and the step it ran under", function()
		fakecli.clear(h)
		-- the chain meets a prepared, raftless issue: raft-plan --apply (a script step) rafts it in raft-c0022
		fakecli.mode(h, "claude", "ok")
		-- the pipeline is started from an agent session: the row still names the user, not agent:unknown
		zn({ "dispatch", "c0022" }, { CLAUDECODE = "1", CLAUDE_EFFORT = "high" })
		local path = `{h.f.main}/.worktree/raft-c0022/pickman/.tracker/issues/c0022/provenance.md`
		t.expect(fs.isFile(path)).toBe(true)
		local rec = fs.readFile(path)
		t.expect(
			string.match(rec, "| rafted | human:c0282%-dispatch | raft=R%d+; via=dispatch:raft%-plan |")
				~= nil
		)
			.toBe(true)
	end)
end)
