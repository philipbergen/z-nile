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
order = ["claude", "grok", "agent"]

[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[z-design.claude]
model = "claude-opus-5-5"
rank = 3
runtime = "claude-cli"
max_tokens = 5000

[zz-review.claude]
model = "claude-opus-5-5"
rank = 4
runtime = "claude-cli"
max_tokens = 5000
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
			["pickman/.tracker/rafts/active/R0040/R0040.md"] = "---\nid: R0040\ntitle: an active raft\nissues: []\n---\n",
			["pickman/.tracker/rafts/active/R0040/check.sh"] = "bash members-check.sh\n",
			["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\ntitle: a backlog raft\nissues: [c0094]\n---\n",
			-- code review 003 F1: an active raft's member, a backlog raft's member, a retired raft
			["pickman/.tracker/issues/active/c0093/c0093.md"] = inRaft(
				prepared("c0093", "active-member"),
				"R0040"
			),
			["pickman/.tracker/issues/active/c0093/check.sh"] = "bash acceptance.sh\n",
			["pickman/.tracker/issues/c0094/c0094.md"] = inRaft(prepared("c0094", "backlog-member"), "R0041"),
			["pickman/.tracker/rafts/retired/R0042/R0042.md"] = "---\nid: R0042\ntitle: a retired raft\nissues: []\n---\n",
			["pickman/.tracker/rafts/R0041/check.sh"] = "bash members-check.sh\n",
			["pickman/.tracker/issues/c0092/c0092.md"] = prepared("c0092", "bystander-thing"),
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
				["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\ntitle: a raft\nissues: [c0096, c0091]\n---\n",
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
					["pickman/.tracker/rafts/active/R0040/R0040.md"] = "---\nid: R0040\ntitle: an active raft \nissues: []\n---\n",
					["pickman/.tracker/rafts/active/R0040/check.sh"] = "exit 0\n",
				})
			)
			t.expect(active.code).toBe(4)
			t.expect(has(active.stdout, "rafts/active/R0040/check.sh")).toBe(true)
			t.expect(has(active.stdout, "raft R0040 is active")).toBe(true)
			local backlog = gate(
				42,
				with({
					["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\ntitle: a backlog raft \nissues: [c0094]\n---\n",
					["pickman/.tracker/rafts/R0041/check.sh"] = "exit 0\n",
				})
			)
			t.expect(backlog.code).toBe(4)
			t.expect(has(backlog.stdout, "rafts/R0041/check.sh")).toBe(true)
			-- a raft's issues: line makes no issue carry-able: c0092 listed, its raft: line untouched, its design rewritten
			local listed = gate(
				43,
				with({
					["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\ntitle: a raft\nissues: [c0096, c0091, c0092]\n---\n",
					["pickman/.tracker/issues/c0092/c0092.md"] = prepared("c0092", "bystander-thing")
						.. "\nrewritten\n",
				})
			)
			t.expect(listed.code).toBe(4)
			t.expect(has(listed.stdout, "c0092/c0092.md")).toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge")).toBe(false)
			-- code review 003 F1: an existing issue's change is judged by its shape against main
			local function doc(path: string): string
				return process.exec("git", { "show", `main:{path}` }, { cwd = h.f.origin }).stdout
			end
			local c0093 = "pickman/.tracker/issues/active/c0093/c0093.md"
			local c0092 = "pickman/.tracker/issues/c0092/c0092.md"
			local c0094 = "pickman/.tracker/issues/c0094/c0094.md"
			local refused: { { n: number, files: { [string]: string }, says: string } } = {
				-- PR #51: an active raft's member moved to the new raft, its design rewritten
				{
					n = 51,
					files = {
						[c0093] = (string.gsub(doc(c0093), "\nraft: R0040\n", "\nraft: R0050\n"))
							.. "rewritten design\n",
					},
					says = "issues/active/c0093/c0093.md, an issue in active/",
				},
				-- a backlog member's raft: line and a design edit
				{
					n = 53,
					files = { [c0092] = inRaft(doc(c0092), "R0050") .. "rewritten design\n" },
					says = "beyond its raft: line",
				},
				-- an issue naming the active raft
				{
					n = 54,
					files = { [c0092] = inRaft(doc(c0092), "R0040") },
					says = "only between empty and a raft this PR carries",
				},
				-- a retired raft's document
				{
					n = 55,
					files = {
						["pickman/.tracker/rafts/retired/R0042/R0042.md"] = "---\nid: R0042\ntitle: x\nissues: []\n---\n",
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
			-- code review 003 F2: a new raft's check.sh is the rendered template's RC0 lines, then only RCn checks
			local template =
				raftcheck.render(doc("z-nile/templates/raft/check.sh"), { ID = "R0050", PROJECT = "pickman" })
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
							["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\ntitle: a raft\nissues: [c0096, c0091, c0094]\n---\n",
							["pickman/.tracker/rafts/R0041/R0041.md"] = "---\nid: R0041\ntitle: a backlog raft\nissues: []\n---\n",
							[c0094] = (string.gsub(doc(c0094), "\nraft: R0041\n", "\nraft: R0050\n")),
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
		end
	)
end)
