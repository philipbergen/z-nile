--!strict
-- R0052 code review 001 (c0117): the dispatcher's guards, for real with fake CLIs (@tests/lib/fakecli). F1: the
-- rafting gate never auto-merges a PR that changes a prepared issue's sequestered files (a member's or the issue's
-- own check.sh), and still merges the raft's own document with its member's raft: line. F2: `./zn dispatch retry`
-- starts through the same guards as every run (origin's URL changed: exit 5). F6: a pending row its item may take
-- is written at the next run's start. Fixture under .cache/c0117-guards.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local raftcheck = require("@znile/engine/raftcheck")
local serde = require("@lune/serde")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

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
]]

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
local function inRaft(doc: string, rid: string): string
	return (string.gsub(doc, "\nraft: \n", `\nraft: {rid}\n`, 1))
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

return t.spec("c0117 the dispatcher's guards (R0052 code review 001)", function(it)
	it("sets up a tracker with a prepared issue, a prepared member, and the fake CLIs", function()
		h = fakecli.new("c0117-guards", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0010/c0010.md"] = trackerfix.stub(
				"c0010",
				"first-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0096/c0096.md"] = prepared("c0096", "rafted-thing"),
			["pickman/.tracker/issues/c0096/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0096/acceptance/a.spec.luau\n",
			["pickman/.tracker/issues/c0096/.models.toml"] = '[dispatch]\nauto_merge = ["raft"]\n',
			["pickman/.tracker/issues/c0091/c0091.md"] = prepared("c0091", "member-thing"),
			["pickman/.tracker/issues/c0091/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0091/acceptance/a.spec.luau\n",
			["pickman/.tracker/issues/c0012/c0012.md"] = trackerfix.stub(
				"c0012",
				"nested-beat",
				"new-quiet-copper-falcon"
			),
			-- code review 002 F1: an active raft and a backlog raft on main, each with its exit criteria
			["pickman/.tracker/rafts/active/R0040/R0040.md"] = "---\nid: R0040\nslug: a-raft\ntitle: an active raft\nissues: []\n---\n",
			["pickman/.tracker/rafts/active/R0040/check.sh"] = "bash members-check.sh\n",
			["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\nslug: a-raft\ntitle: a backlog raft\nissues: [c0094]\n---\n",
			-- code review 003 F1: an active raft's member, a backlog raft's member, a retired raft
			["pickman/.tracker/issues/active/c0093/c0093.md"] = inRaft(
				prepared("c0093", "active-member"),
				"R0040"
			),
			["pickman/.tracker/issues/active/c0093/check.sh"] = "bash acceptance.sh\n",
			["pickman/.tracker/issues/c0094/c0094.md"] = inRaft(prepared("c0094", "backlog-member"), "R0041"),
			["pickman/.tracker/rafts/retired/R0042/R0042.md"] = "---\nid: R0042\nslug: a-raft\ntitle: a retired raft\nissues: []\n---\n",
			["pickman/.tracker/rafts/R0041/check.sh"] = "bash members-check.sh\n",
			["pickman/.tracker/issues/c0092/c0092.md"] = prepared("c0092", "bystander-thing"),
			-- code review 007 F2: an issue in preparation, whose prep PR the prep gate may merge
			["pickman/.tracker/issues/c0095/c0095.md"] = (string.gsub(
				prepared("c0095", "prep-thing"),
				"prepared%-quiet%-copper%-falcon",
				"preparing-quiet-copper-falcon"
			)),
			["pickman/.tracker/issues/c0095/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0095/acceptance/a.spec.luau\n",
		})
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
	end)

	it("retry starts through the guards: origin's URL changed since the last run stops it (F2)", function()
		fakecli.clear(h)
		local first = zn({ "dispatch", "z-design", "c0010" })
		if not first.ok then
			error(first.stdout .. first.stderr)
		end
		fakecli.clear(h) -- the first run's log line is not the retry's
		local url = fixture.git(h.f.main, { "remote", "get-url", "origin" })
		local other = `{h.f.base}/other.git`
		process.exec("git", { "clone", "-q", "--bare", h.f.origin, other }) -- raw: clone to a named path
		fixture.git(h.f.main, { "remote", "set-url", "origin", other })
		local r = zn({ "dispatch", "retry", "c0010" })
		fixture.git(h.f.main, { "remote", "set-url", "origin", url })
		t.expect(r.code).toBe(5)
		t.expect(has(r.stdout, "origin's URL changed")).toBe(true)
		t.expect(has(fakecli.log(h), "claude step=z-design")).toBe(false)
	end)

	it(
		"with no pinned origin, the model walk reads only the saved origin, never origin by name (002 F3)",
		function()
			fakecli.clear(h)
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
			local ok = zn({ "dispatch", "zz-review", "c0010", "--mode", "code", "--dry-run" })
			t.expect(has(ok.stdout, "claude-opus-5-5")).toBe(true)
			local url = fixture.git(h.f.main, { "remote", "get-url", "origin" })
			local evil = `{h.f.base}/evil.git`
			process.exec("git", { "clone", "-q", "--bare", h.f.origin, evil }) -- raw: clone to a named path
			fixture.git(h.f.main, { "remote", "set-url", "origin", evil })
			local r = zn({ "dispatch", "zz-review", "c0010", "--mode", "code", "--dry-run" })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stdout .. r.stderr, ".models.toml is not read from it")).toBe(true)
		end
	)

	it("a nested step beats until its process ends, not only while its CLI runs (the stall cases)", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude.z-design", "waitreview")
		fakecli.mode(h, "claude.zz-review", "reviewer")
		local r = zn({ "dispatch", "z-design", "c0012" })
		fakecli.mode(h, "claude.z-design", nil)
		fakecli.mode(h, "claude.zz-review", nil)
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		local dir = `{h.f.main}/.cache/dispatch/c0012/zz-review-design-c0012-1`
		t.expect(fakecli.state(h, "c0012", "zz-review-design-c0012-1").outcome).toBe("ok")
		-- the last beat is the process's own, written after the review landed and its spend was recorded
		t.expect(has(fs.readFile(`{dir}/beat`), " process ")).toBe(true)
		local beat = fs.metadata(`{dir}/beat`).modifiedAt
		local saved = fs.metadata(`{dir}/state.json`).modifiedAt
		t.expect(
			beat ~= nil and saved ~= nil and (beat :: any).unixTimestamp >= (saved :: any).unixTimestamp - 1
		)
			.toBe(true)
	end)

	it("a pending row its item may take is written at the next run's start (F6)", function()
		fakecli.clear(h)
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		local path = `{h.f.main}/.cache/dispatch/c0010/state.json`
		local st = serde.decode("json", fs.readFile(path))
		st.outcome = "failed"
		st.pending = {
			{
				id = "c0010",
				phase = "prep",
				tokens = 5,
				model = "claude-opus-5-5",
				minutes = 0,
				note = "pending-row",
			},
		}
		fs.writeFile(path, serde.encode("json", st))
		local r = zn({ "dispatch", "retry", "c0010" })
		if not r.ok then
			error(r.stdout .. r.stderr)
		end
		t.expect(has(r.stdout, "pending, now written")).toBe(true)
		local rows = fakecli.rows(h, "c0010") :: { any }
		local found = false
		for _, row in rows do
			if row.subject == "pending-row" and row.tokens == 5 then
				found = true
			end
		end
		t.expect(found).toBe(true)
		t.expect(#fakecli.state(h, "c0010").pending).toBe(0)
	end)

	it(
		"the rafting gate never merges a change to a prepared issue's check.sh, the member's or its own (F1)",
		function()
			fakecli.clear(h)
			local url = "https://github.com/zn-fixture/c0117-guards.git"
			fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			local function prJson(n: number, head: string): string
				return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{head}"\}`
			end
			local doc = fixture.git(h.f.origin, { "show", "main:pickman/.tracker/issues/c0096/c0096.md" })
			local member = fixture.git(h.f.origin, { "show", "main:pickman/.tracker/issues/c0091/c0091.md" })
			local own = {
				["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096, c0091]\n---\n",
				["pickman/.tracker/issues/c0096/c0096.md"] = (
					string.gsub(doc, "\nraft: \n", "\nraft: R0050\n")
				),
				["pickman/.tracker/issues/c0091/c0091.md"] = (
					string.gsub(member, "\nraft: \n", "\nraft: R0050\n")
				),
			}
			local function with(extra: { [string]: string }): { [string]: string }
				local out = table.clone(own)
				for k, v in extra do
					out[k] = v
				end
				return out
			end
			local function gate(n: number, files: { [string]: string }): fixture.Result
				local sha = fakecli.pullRequest(h, n, files)
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(n, sha))
				return zn({ "dispatch", "c0096" })
			end
			-- the reviewer's PR #31: a raft that adds a member and rewrites that member's check.sh to `exit 0`
			local memberCheck = gate(31, with({ ["pickman/.tracker/issues/c0091/check.sh"] = "exit 0\n" }))
			t.expect(memberCheck.code).toBe(4)
			t.expect(has(memberCheck.stdout, "c0091/check.sh")).toBe(true)
			-- the issue's own reviewed check.sh is just as sequestered once prepared
			local ownCheck = gate(32, with({ ["pickman/.tracker/issues/c0096/check.sh"] = "exit 0\n" }))
			t.expect(ownCheck.code).toBe(4)
			t.expect(has(ownCheck.stdout, "c0096/check.sh")).toBe(true)
			-- a member's acceptance spec removed or rewritten: the same
			local spec =
				gate(33, with({ ["pickman/.tracker/issues/c0091/acceptance/a.spec.luau"] = "return nil\n" }))
			t.expect(spec.code).toBe(4)
			-- code review 002 F1: touching a raft's document chooses no exemption. PR #41: an active raft's title and
			-- its check.sh; PR #42: a backlog raft's
			local active = gate(
				41,
				with({
					["pickman/.tracker/rafts/active/R0040/R0040.md"] = "---\nid: R0040\nslug: a-raft\ntitle: an active raft \nissues: []\n---\n",
					["pickman/.tracker/rafts/active/R0040/check.sh"] = "exit 0\n",
				})
			)
			t.expect(active.code).toBe(4)
			t.expect(has(active.stdout, "rafts/active/R0040/check.sh")).toBe(true)
			t.expect(has(active.stdout, "raft R0040 is active")).toBe(true)
			local backlog = gate(
				42,
				with({
					["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\nslug: a-raft\ntitle: a backlog raft \nissues: [c0094]\n---\n",
					["pickman/.tracker/rafts/R0041/check.sh"] = "exit 0\n",
				})
			)
			t.expect(backlog.code).toBe(4)
			t.expect(has(backlog.stdout, "rafts/R0041/check.sh")).toBe(true)
			-- a raft's issues: line makes no issue carry-able: c0092 listed, its raft: line untouched, its design rewritten
			local listed = gate(
				43,
				with({
					["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096, c0091, c0092]\n---\n",
					["pickman/.tracker/issues/c0092/c0092.md"] = prepared("c0092", "bystander-thing")
						.. "\nrewritten\n",
				})
			)
			t.expect(listed.code).toBe(4)
			t.expect(has(listed.stdout, "c0092/c0092.md")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge")).toBe(false)
			-- code review 003 F1: an existing issue's change is judged by its shape against main
			local function onMain(path: string): string
				return process.exec("git", { "show", `main:{path}` }, { cwd = h.f.origin }).stdout
			end
			local c0096 = "pickman/.tracker/issues/c0096/c0096.md"
			local c0093 = "pickman/.tracker/issues/active/c0093/c0093.md"
			local c0092 = "pickman/.tracker/issues/c0092/c0092.md"
			local c0094 = "pickman/.tracker/issues/c0094/c0094.md"
			local refused: { { n: number, files: { [string]: string }, says: string } } = {
				-- PR #51: an active raft's member moved to the new raft, its design rewritten
				{
					n = 51,
					files = {
						[c0093] = (string.gsub(onMain(c0093), "\nraft: R0040\n", "\nraft: R0050\n"))
							.. "rewritten design\n",
					},
					says = "issues/active/c0093/c0093.md, an issue in active/",
				},
				-- a backlog member's raft: line and a design edit
				{
					n = 53,
					files = { [c0092] = inRaft(onMain(c0092), "R0050") .. "rewritten design\n" },
					says = "beyond its raft: line",
				},
				-- an issue naming the active raft
				{
					n = 54,
					files = { [c0092] = inRaft(onMain(c0092), "R0040") },
					says = "only between empty and a raft this PR carries",
				},
				-- a new raft straight into active/, outside the backlog folder
				{
					n = 61,
					files = {
						["pickman/.tracker/rafts/active/R0051/R0051.md"] = "---\nid: R0051\nslug: a-raft\ntitle: x\nissues: []\n---\n",
					},
					says = "outside the backlog folder",
				},
				-- code review 004 F2: a new raft in z-nile's root with the id of pickman's active R0040, and a pickman
				-- issue naming it
				{
					n = 70,
					files = {
						["z-nile/.tracker/rafts/R0040/R0040.md"] = "---\nid: R0040\nslug: a-raft\ntitle: x\nissues: [c0092]\n---\n",
						[c0092] = inRaft(onMain(c0092), "R0040"),
					},
					says = "raft R0040 belongs to pickman/.tracker",
				},
				-- the same new id in both roots, a pickman issue naming it
				{
					n = 74,
					files = {
						["z-nile/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: x\nissues: []\n---\n",
					},
					says = "raft R0050 in two roots",
				},
				-- code review 004 F4: a member moved out of a backlog raft the PR does not touch
				{
					n = 75,
					files = { [c0094] = (string.gsub(onMain(c0094), "\nraft: R0041\n", "\nraft: R0050\n")) },
					says = "only between empty and a raft this PR carries",
				},
				-- code review 005 F3: a new z-nile raft nothing names, and a pickman issue naming it
				{
					n = 76,
					files = {
						["z-nile/.tracker/rafts/R0091/R0091.md"] = "---\nid: R0091\nslug: a-raft\ntitle: x\nissues: []\n---\n",
						[c0092] = inRaft(onMain(c0092), "R0091"),
					},
					says = "only between empty and a raft this PR carries",
				},
				-- code review 005 F2: a new raft with no document, and one whose document names another id
				{
					n = 77,
					files = {
						["pickman/.tracker/rafts/R0090/notes.md"] = "notes\n",
						[c0092] = inRaft(onMain(c0092), "R0090"),
					},
					says = "without a valid pickman/.tracker/rafts/R0090/R0090.md",
				},
				{
					n = 78,
					files = {
						["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0099\nslug: a-raft\ntitle: x\nissues: []\n---\n",
					},
					says = "without a valid pickman/.tracker/rafts/R0050/R0050.md",
				},
				-- code review 005 F4: the counter, nonsense or a plausible bump
				{ n = 79, files = { ["z-nile/next"] = "nonsense\n" }, says = "never carries the id counter" },
				{
					n = 83,
					files = { ["z-nile/next"] = "issue 300 x\nraft 9999 x\n" },
					says = "never carries the id counter",
				},
				-- code review 006 F1: documents the tracker's own readers reject
				{
					n = 88,
					files = {
						["pickman/.tracker/rafts/R0090/R0090.md"] = "---\nid: R0090\ntitle: x\nissues: [c0092]\n---\n",
						[c0092] = inRaft(onMain(c0092), "R0090"),
					},
					says = "no-slug",
				},
				{
					n = 89,
					files = {
						["pickman/.tracker/rafts/R0090/R0090.md"] = "---\nid: R0090\nslug: a-raft\nid: R0099\ntitle: x\nissues: [c0092]\n---\n",
						[c0092] = inRaft(onMain(c0092), "R0090"),
					},
					says = "id-mismatch",
				},
				{
					n = 90,
					files = {
						["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: x\nissues: [c0096, c0091, c0094]\n---\n",
					},
					says = "lists c0094, whose raft: line does not name R0050",
				},
				{
					n = 91,
					files = {
						["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: x\nissues: [c0096]\n---\n",
					},
					says = "c0091's raft: line names R0050, which does not list it",
				},
				-- a retired raft's document
				{
					n = 55,
					files = {
						["pickman/.tracker/rafts/retired/R0042/R0042.md"] = "---\nid: R0042\nslug: a-raft\ntitle: x\nissues: []\n---\n",
					},
					says = "raft R0042 is retired",
				},
			}
			for _, case in refused do
				local r = gate(case.n, with(case.files))
				if r.code ~= 4 or not has(r.stdout, case.says) then
					error(`PR #{case.n}: exit {r.code}, wanted 4 saying "{case.says}"\n{r.stdout}{r.stderr}`)
				end
			end
			-- code review 004 F1: a backlog raft moved to active/ or done/ (its folder, with its check.sh) is not a
			-- rafting PR's to move: PR #71 to done/, PR #72 to active/ with a member added in the same PR
			for _, life in { { n = 71, to = "done" }, { n = 72, to = "active" } } do
				local from, dest = "pickman/.tracker/rafts/R0041", `pickman/.tracker/rafts/{life.to}/R0041`
				local sha = fakecli.pullRequest(
					h,
					life.n,
					life.to == "active" and { [c0092] = inRaft(onMain(c0092), "R0041") } or {},
					{ [`{from}/R0041.md`] = `{dest}/R0041.md`, [`{from}/check.sh`] = `{dest}/check.sh` }
				)
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(life.n, sha))
				local moved = zn({ "dispatch", "c0096" })
				if moved.code ~= 4 or not has(moved.stdout, "out of the backlog folder") then
					error(
						`PR #{life.n}: exit {moved.code}, wanted 4 saying "out of the backlog folder"\n{moved.stdout}{moved.stderr}`
					)
				end
				t.expect(has(fakecli.log(h), `realgh pr merge {life.n} `)).toBe(false)
			end
			-- code review 005 F2: a backlog raft's document deleted, or renamed inside its folder
			do
				local r41 = "pickman/.tracker/rafts/R0041"
				for _, case in
					{
						{ n = 84, moves = {}, deletes = { `{r41}/R0041.md` } },
						{ n = 85, moves = { [`{r41}/R0041.md`] = `{r41}/old.md` }, deletes = {} },
					}
				do
					local sha = fakecli.pullRequest(h, case.n, {}, case.moves, nil, case.deletes)
					fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(case.n, sha))
					local r = zn({ "dispatch", "c0096" })
					if
						r.code ~= 4
						or not has(r.stdout, "without a valid pickman/.tracker/rafts/R0041/R0041.md")
					then
						error(
							`PR #{case.n}: exit {r.code}, wanted 4 naming the document\n{r.stdout}{r.stderr}`
						)
					end
					t.expect(has(fakecli.log(h), `realgh pr merge {case.n} `)).toBe(false)
				end
			end
			-- code review 003 F2: a new raft's check.sh is the rendered template's RC0 lines, then only RCn checks
			local template = raftcheck.render(
				onMain("z-nile/templates/raft/check.sh"),
				{ ID = "R0050", PROJECT = "pickman" }
			)
			local check = "pickman/.tracker/rafts/R0050/check.sh"
			for _, case in
				{
					{ n = 52, text = "exit 0\n" },
					{ n = 56, text = (string.gsub(template, "%-%-full", "--quick")) },
					{ n = 57, text = (string.gsub(template, "\nfinish\n", "\nexit 0\nfinish\n")) },
				}
			do
				local r = gate(case.n, with({ [check] = case.text }))
				if r.code ~= 4 or not has(r.stdout, "rafts/R0050/check.sh") then
					error(
						`PR #{case.n}: exit {r.code}, wanted 4 naming the raft's check.sh\n{r.stdout}{r.stderr}`
					)
				end
			end
			t.expect(has(fakecli.log(h), "realgh pr merge")).toBe(false)
			-- merges, pinned to the head: the raft's own document and its members' raft: lines (PR #34); the rendered
			-- template; the template with an RC1 check; a recombine moving a backlog raft's member into the new raft
			local rc1 = (
				string.gsub(
					template,
					"\nfinish\n",
					"\ncheck \"RC1: the thing works\" bash -c 'true'\n\nfinish\n"
				)
			)
			for _, case in
				{
					{ n = 34, files = own },
					{ n = 58, files = with({ [check] = template }) },
					{ n = 59, files = with({ [check] = rc1 }) },
					{
						n = 60,
						files = with({
							["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096, c0091, c0094]\n---\n",
							["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\nslug: a-raft\ntitle: a backlog raft\nissues: []\n---\n",
							[c0094] = (string.gsub(onMain(c0094), "\nraft: R0041\n", "\nraft: R0050\n")),
						}),
					},
				}
			do
				fakecli.clear(h)
				local sha = fakecli.pullRequest(h, case.n, case.files)
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(case.n, sha))
				local r = zn({ "dispatch", "c0096" })
				if not has(fakecli.log(h), `realgh pr merge {case.n} --squash --match-head-commit {sha}`) then
					error(`PR #{case.n} did not merge\n{r.stdout}{r.stderr}`)
				end
			end
			-- code review 006 F3: a head sharing no history with main (one new raft document)
			do
				local other = h.f.other
				fixture.git(other, { "checkout", "-q", "--orphan", "orphan-92" })
				fixture.git(other, { "rm", "-rfq", "." })
				fs.writeDir(`{other}/pickman/.tracker/rafts/R0090`)
				fs.writeFile(
					`{other}/pickman/.tracker/rafts/R0090/R0090.md`,
					"---\nid: R0090\nslug: a-raft\ntitle: x\nissues: []\n---\n"
				)
				fixture.git(other, { "add", "-A" })
				fixture.git(other, { "commit", "-q", "-m", "orphan" })
				local sha = fixture.git(other, { "rev-parse", "HEAD" })
				fixture.git(other, { "push", "-q", "-f", "origin", "HEAD:refs/pull/92/head" })
				fixture.git(other, { "checkout", "-q", "-f", "main" })
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(92, sha))
				local r = zn({ "dispatch", "c0096" })
				if r.code ~= 4 or not has(r.stdout, "shares no history") then
					error(`PR #92: exit {r.code}, wanted 4 saying "shares no history"\n{r.stdout}{r.stderr}`)
				end
			end
			-- code review 007 F2: the prep gate judges by the tracker's readers too: a prep PR stripping its issue's slug,
			-- and one naming a raft that does not list it
			do
				local c0095 = "pickman/.tracker/issues/c0095/c0095.md"
				-- the dispatcher's own claim: a z-design step of its own in the item's history
				fs.writeDir(`{h.f.main}/.cache/dispatch/c0095`)
				fs.writeFile(
					`{h.f.main}/.cache/dispatch/c0095/state.json`,
					'{"id":"c0095","mode":"chain","history":[{"step":"z-design","outcome":"ok"}],"merged":[],"pushed":[],"pending":[]}'
				)
				for _, case in
					{
						{
							n = 94,
							text = (string.gsub(onMain(c0095), "\nslug: [^\n]*", "")),
							says = "no-slug",
						},
						{ n = 95, text = inRaft(onMain(c0095), "R0041"), says = "does not list it" },
					}
				do
					local sha = fakecli.pullRequest(h, case.n, { [c0095] = case.text })
					fs.writeFile(`{h.fakes}/pr-prep-prep-thing.json`, prJson(case.n, sha))
					local r = zn({ "dispatch", "c0095" })
					if has(fakecli.log(h), `realgh pr merge {case.n} `) or not has(r.stdout, case.says) then
						error(`PR #{case.n}: wanted a refusal saying "{case.says}"\n{r.stdout}{r.stderr}`)
					end
				end
			end
			-- code review 005 F1: main moves while the PRs wait. All are cut first, then main readies R0041 (with its
			-- member c0094) and adds a raft R0060 to pickman, and gets a spend row on c0092
			local r41 = "pickman/.tracker/rafts/R0041"
			local cut: { { n: number, sha: string, refused: boolean } } = {
				-- a retitle of the backlog raft main now readies
				{
					n = 80,
					sha = fakecli.pullRequest(
						h,
						80,
						with({
							[`{r41}/R0041.md`] = "---\nid: R0041\nslug: a-raft\ntitle: retitled by the rafting PR\nissues: [c0094]\n---\n",
						})
					),
					refused = true,
				},
				-- a recombine out of that raft
				{
					n = 86,
					sha = fakecli.pullRequest(
						h,
						86,
						with({
							[`{r41}/R0041.md`] = "---\nid: R0041\nslug: a-raft\ntitle: a backlog raft\nissues: []\n---\n",
							["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096, c0091, c0094]\n---\n",
							[c0094] = (string.gsub(onMain(c0094), "\nraft: R0041\n", "\nraft: R0050\n")),
						})
					),
					refused = true,
				},
				-- a new z-nile raft whose id main takes in pickman
				{
					n = 81,
					sha = fakecli.pullRequest(h, 81, {
						["z-nile/.tracker/rafts/R0060/R0060.md"] = "---\nid: R0060\nslug: a-raft\ntitle: x\nissues: []\n---\n",
					}),
					refused = true,
				},
				-- the same raft PR as #34, which main leaves alone but for an unrelated spend row
				{
					n = 87,
					sha = fakecli.pullRequest(h, 87, {
						["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0091]\n---\n",
						["pickman/.tracker/issues/c0091/c0091.md"] = own["pickman/.tracker/issues/c0091/c0091.md"],
					}),
					refused = false,
				},
				-- code review 006 F3: main touches only the carried issue itself
				{ n = 93, sha = fakecli.pullRequest(h, 93, own), refused = true },
			}
			fakecli.advanceMain(h, {
				["pickman/.tracker/rafts/R0060/R0060.md"] = "---\nid: R0060\nslug: a-raft\ntitle: y\nissues: []\n---\n",
				["pickman/.tracker/issues/c0092/spend.md"] = "| c0092 | prep | 1 |\n",
				[c0096] = onMain(c0096) .. "\nre-claimed on main\n",
			}, {
				[r41] = "pickman/.tracker/rafts/active/R0041",
				["pickman/.tracker/issues/c0094"] = "pickman/.tracker/issues/active/c0094",
			})
			for _, c in cut do
				fakecli.clear(h)
				fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(c.n, c.sha))
				local r = zn({ "dispatch", "c0096" })
				local merged =
					has(fakecli.log(h), `realgh pr merge {c.n} --squash --match-head-commit {c.sha}`)
				if c.refused and (r.code ~= 4 or merged or not has(r.stdout, "since this PR was cut")) then
					error(
						`PR #{c.n}: exit {r.code}, wanted 4 saying "since this PR was cut"\n{r.stdout}{r.stderr}`
					)
				elseif not c.refused and not merged then
					error(`PR #{c.n} did not merge\n{r.stdout}{r.stderr}`)
				end
			end
			-- code review 007 F3, 008 F1: the merge lands on a main the gate did not judge. The fake gh lands a commit over an
			-- item the PR carries on main just before it squashes, as a main that moves under the merge does
			local raftDoc = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0091]\n---\n"
			local sha96 = fakecli.pullRequest(h, 96, {
				["pickman/.tracker/rafts/R0050/R0050.md"] = raftDoc,
				["pickman/.tracker/issues/c0091/c0091.md"] = own["pickman/.tracker/issues/c0091/c0091.md"],
			})
			fakecli.clear(h)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(96, sha96))
			fs.writeFile(`{h.fakes}/race-96`, "pickman/.tracker/issues/c0091/spend.md")
			local late = zn({ "dispatch", "c0096" })
			if late.code ~= 5 or not has(late.stdout, "not the main it was judged against") then
				error(
					`PR #96: exit {late.code}, wanted 5 saying the main was not the judged one\n{late.stdout}{late.stderr}`
				)
			end
			-- the stop is recorded as an attempt of its own, so the next run holds
			local again = zn({ "dispatch", "c0096" })
			t.expect(again.code).toBe(5)
			local stateText = fs.readFile(`{h.f.main}/.cache/dispatch/c0096/state.json`)
			t.expect(has(stateText, "merge-check")).toBe(true)
			-- `vet` alone leaves the stop; `retry` clears it (the stop's own message names both)
			t.expect(has(late.stdout, "./zn dispatch retry c0096")).toBe(true)
			t.expect(has(again.stdout, "./zn dispatch retry c0096")).toBe(true)
			t.expect(has(again.stdout, "did not make")).toBe(false)
			t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
			t.expect(zn({ "dispatch", "c0096" }).code).toBe(5)
			zn({ "dispatch", "retry", "c0096" })
			t.expect(has(fs.readFile(`{h.f.main}/.cache/dispatch/c0096/state.json`), '"outcome":"tripwire"'))
				.toBe(false)
			-- a commit over a bystander while the merge lands is no reason to stop (PR #98)
			local sha98 = fakecli.pullRequest(h, 98, {
				["pickman/.tracker/rafts/R0050/R0050.md"] = raftDoc,
				["pickman/.tracker/issues/c0091/c0091.md"] = own["pickman/.tracker/issues/c0091/c0091.md"],
			})
			fakecli.clear(h)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(98, sha98))
			fs.writeFile(`{h.fakes}/race-98`, "pickman/.tracker/issues/c0092/spend.md")
			fs.removeFile(`{h.f.main}/.cache/dispatch/c0096/state.json`)
			local bystander = zn({ "dispatch", "c0096" })
			t.expect(has(fakecli.log(h), "realgh pr merge 98 ")).toBe(true)
			if bystander.code == 5 then
				error(`PR #98: a commit over a bystander stopped the run\n{bystander.stdout}`)
			end
			-- a merge whose commit GitHub cannot name is a stop too: nothing was compared
			local sha97 = fakecli.pullRequest(h, 97, {
				["pickman/.tracker/rafts/R0050/R0050.md"] = raftDoc,
				["pickman/.tracker/issues/c0091/c0091.md"] = own["pickman/.tracker/issues/c0091/c0091.md"],
			})
			fakecli.clear(h)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(97, sha97))
			fs.writeFile(`{h.fakes}/nosquash`, "1")
			fs.removeFile(`{h.f.main}/.cache/dispatch/c0096/state.json`)
			local unread = zn({ "dispatch", "c0096" })
			if
				unread.code ~= 5
				or not has(unread.stdout, "GitHub names no merge commit")
				or not has(unread.stdout, "./zn dispatch retry c0096")
			then
				error(
					`PR #97: exit {unread.code}, wanted 5 saying the merge commit was unreadable\n{unread.stdout}`
				)
			end
			-- the prep gate compares too (code review 009 F3): a prep PR's merge with a commit over its own issue
			local c0095doc = "pickman/.tracker/issues/c0095/c0095.md"
			local sha99 = fakecli.pullRequest(h, 99, {
				[c0095doc] = fixture.git(h.f.origin, { "show", `main:{c0095doc}` }) .. "\nmore design\n",
			})
			fakecli.clear(h)
			fs.writeFile(`{h.fakes}/pr-prep-prep-thing.json`, prJson(99, sha99))
			fs.writeFile(`{h.fakes}/race-99`, "pickman/.tracker/issues/c0095/spend.md")
			local prepLate = zn({ "dispatch", "c0095" })
			-- c0283: the prep gate never merges, so there is no merge to compare; it waits for the user
			if prepLate.code ~= 4 or not has(prepLate.stdout, "waits for the user's approval and merge") then
				error(`PR #99: exit {prepLate.code}, wanted 4\n{prepLate.stdout}{prepLate.stderr}`)
			end
			-- every judgement's scratch export is gone (code review 008 F5)
			local left = 0
			for _, name in fs.readDir(`{h.f.main}/.cache/dispatch`) do
				if string.sub(name, 1, 6) == "judge-" then
					left += 1
				end
			end
			t.expect(left).toBe(0)
		end
	)
end)
