--!strict
-- c0263 AC6, AC7 (through the dispatcher): a dispatched step gets ZN_ACTOR from the spec of the attempt that runs it
-- (a fallthrough's second attempt its own, a dotted model id normalised); the prep gate never merges, whatever
-- auto_merge says, and waits for the user's approval; a worker cannot approve; and the rafting gate merges a rafting PR
-- whose member folders carry a `rafted` row in provenance.md but refuses any other row or file. Fake CLIs and a fixture
-- under .cache (tests/lib/fakecli), as c0117's guards.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude", "grok"]

[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[z-design.claude]
model = "claude-opus-5-5"
effort = "high"
rank = 3
runtime = "claude-cli"
max_tokens = 5000

[z-design.grok]
model = "grok-4.7"
effort = "medium"
rank = 3
runtime = "grok-cli"
max_tokens = 5000

[zz-review.claude]
model = "claude-opus-5-5"
effort = "high"
rank = 4
runtime = "claude-cli"
max_tokens = 5000
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

return t.spec("c0263 provenance through the dispatcher", function(it)
	it("sets up a tracker, a prepared pair for the rafting gate, and the fake CLIs", function()
		h = fakecli.new("c0263-dispatch", {
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
			["pickman/.tracker/issues/c0096/provenance.md"] = HEADER("c0096") .. "| 2026-11-08 09:00 | approved | human:Ann | design=aaaaaaaaaaaa |\n",
			["pickman/.tracker/issues/c0022/c0022.md"] = (string.gsub(
				prepared("c0022", "scripted-thing"),
				"created: ",
				"size: 300\ncreated: ",
				1
			)),
			["pickman/.tracker/issues/c0021/c0021.md"] = trackerfix.stub("c0021", "third-thing", "new-quiet-copper-falcon"),
			["pickman/.tracker/issues/c0021/.models.toml"] = "[dispatch]\nauto_merge = []\n",
			["pickman/.tracker/issues/c0091/c0091.md"] = prepared("c0091", "member-thing"),
			["pickman/.tracker/issues/c0091/check.sh"] = "lune run tests/run -- pickman/.tracker/issues/c0091/acceptance/a.spec.luau\n",
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
		t.expect(has(l, "actor=agent:grok-4-7 effort medium\n")).toBe(true)
	end)

	it("the prep gate never merges, whatever auto_merge says, and a worker cannot approve", function()
		fakecli.clear(h)
		local url = "https://github.com/zn-fixture/c0263-dispatch.git"
		fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
		fixture.git(h.f.main, { "remote", "set-url", "origin", url })
		local sha = fakecli.pullRequest(h, 7, { ["pickman/.tracker/issues/c0020/x.md"] = "notes\n" })
		fs.writeFile(
			`{h.fakes}/pr-prep-second-thing.json`,
			`\{"number":7,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{sha}"\}`
		)
		-- the fake design step claims the issue (as z-design does), then the chain meets the PR at the prep gate; the
		-- root .models.toml says auto_merge = ["prep"] and the chain still stops there
		fakecli.mode(h, "claude", "claim")
		local r = zn({ "dispatch", "c0020" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "./zn approve c0020")).toBe(true)
		t.expect(has(fakecli.log(h), "realgh pr merge 7")).toBe(false)
		-- with prep absent from auto_merge (an item-level []) the reason is the old one, and the suffix is still there
		local sha21 = fakecli.pullRequest(h, 8, { ["pickman/.tracker/issues/c0021/x.md"] = "notes\n" })
		fs.writeFile(
			`{h.fakes}/pr-prep-third-thing.json`,
			`\{"number":8,"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{sha21}"\}`
		)
		local r21 = zn({ "dispatch", "c0021" })
		t.expect(r21.code).toBe(4)
		t.expect(has(r21.stdout, "#8 waits for a merge")).toBe(true)
		t.expect(has(r21.stdout, "./zn approve c0021")).toBe(true)
		t.expect(has(fakecli.log(h), "realgh pr merge 8")).toBe(false)
		-- a step that runs `./zn approve` is refused: the dispatched worker has no human behind it
		local approve = zn({ "approve", "c0020", "--said", "go" }, { ZN_DISPATCH = "1" })
		t.expect(approve.ok).toBe(false)
		t.expect(has(approve.stderr, "dispatch")).toBe(true)
	end)

	it("the rafting gate merges a rafted row in provenance.md beside raft:, and refuses any other row or file", function()
		fakecli.clear(h)
		local function prJson(n: number, head: string): string
			return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{head}"\}`
		end
		local function onMain(path: string): string
			return fixture.git(h.f.origin, { "show", `main:{path}` })
		end
		local c96, c91 = "pickman/.tracker/issues/c0096/c0096.md", "pickman/.tracker/issues/c0091/c0091.md"
		local function rafted(doc: string): string
			return (string.gsub(doc, "\nraft: \n", "\nraft: R0050\n", 1))
		end
		local ACTOR = "agent:claude-sonnet-5-5 effort high"
		local p96, p91 = "pickman/.tracker/issues/c0096/provenance.md", "pickman/.tracker/issues/c0091/provenance.md"
		-- the rows a rafting PR may add: its own, appended to what main already holds
		local function appended(path: string, id: string, event: string): string
			local old = fixture.exec(h.f.origin, "git", { "show", `main:{path}` })
			local row = `| 2026-11-08 10:00 | {event} | {ACTOR} | raft=R0050 |\n`
			return (if old.ok then old.stdout else HEADER(id)) .. row
		end
		local raftDocText = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096, c0091]\n---\n"
		local function gate(n: number, rec96: string, rec91: string, more: { [string]: string }?): fixture.Result
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
		-- refused: a delivered row (not a rafting PR's), an approval, a second file beside the record
		local cases: { { r96: string, r91: string, more: { [string]: string }? } } = {
			-- a delivered row is not a rafting PR's
			{ r96 = appended(p96, "c0096", "delivered"), r91 = appended(p91, "c0091", "rafted") },
			-- nor is an approval
			{ r96 = appended(p96, "c0096", "rafted"), r91 = appended(p91, "c0091", "approved") },
			-- the prep PR's approved row, already on main, edited
			{
				r96 = (string.gsub(appended(p96, "c0096", "rafted"), "human:Ann", "human:Eve", 1)),
				r91 = appended(p91, "c0091", "rafted"),
			},
			-- a second file beside the record
			{
				r96 = appended(p96, "c0096", "rafted"),
				r91 = appended(p91, "c0091", "rafted"),
				more = { ["pickman/.tracker/issues/c0091/notes.md"] = "x\n" },
			},
		}
		for i, case in cases do
			fakecli.clear(h)
			local r = gate(40 + i, case.r96, case.r91, case.more)
			t.expect(r.code).toBe(4)
			t.expect(has(r.stdout, "provenance.md") or has(r.stdout, "beyond its raft: line") or has(r.stdout, "notes.md")).toBe(true)
			t.expect(has(fakecli.log(h), `realgh pr merge {40 + i} `)).toBe(false)
		end
		-- main gains a row on c0096 after the PR is cut (a rank, a confirmation): the sync unions it before ours, so main's
		-- record stays a prefix of the PR's and the gate still merges it
		trackerfix.elsewhere(
			h.f,
			{ [p96] = fixture.git(h.f.origin, { "show", `main:{p96}` }) .. "\n| 2026-11-08 09:30 | ranked | human:Ann | rank=3 |\n" },
			"a rank on c0096"
		)
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
		-- merged, pinned to the head: one rafted row per ticket
		fakecli.clear(h)
		local sha = fakecli.pullRequest(h, 50, {
			["pickman/.tracker/rafts/R0050/R0050.md"] = raftDocText,
			[c96] = rafted(onMain(c96)),
			[c91] = rafted(onMain(c91)),
			[p96] = appended(p96, "c0096", "rafted"),
			[p91] = appended(p91, "c0091", "rafted"),
		})
		fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(50, sha))
		local r = zn({ "dispatch", "c0096" })
		if not has(fakecli.log(h), `realgh pr merge 50 --squash --match-head-commit {sha}`) then
			error(`PR #50 did not merge\n{r.stdout}{r.stderr}`)
		end
	end)
	it("a script step records the user who started the pipeline and the step it ran under", function()
		fakecli.clear(h)
		-- the chain meets a prepared, raftless issue: raft-plan --apply (a script step) rafts it in raft-c0022
		fakecli.mode(h, "claude", "ok")
		zn({ "dispatch", "c0022" })
		local path = `{h.f.main}/.worktree/raft-c0022/pickman/.tracker/issues/c0022/provenance.md`
		t.expect(fs.isFile(path)).toBe(true)
		local rec = fs.readFile(path)
		t.expect(string.match(rec, "| rafted | human:c0263%-dispatch | raft=R%d+; via=dispatch:raft%-plan |") ~= nil).toBe(true)
	end)
end)
