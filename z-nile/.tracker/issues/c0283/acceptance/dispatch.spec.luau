--!strict
-- c0283 AC4: the dispatcher's prep gate never merges, whatever auto_merge says, every prep stop keeps its reason and gains
-- the approve suffix, a gate that no condition fails says the PR waits for the user, and a dispatched worker cannot
-- approve. Fake CLIs and a fixture under .cache (tests/lib/fakecli), as c0117's guards.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
[dispatch]
auto_merge = ["prep"]
stall_seconds = 3

[fallback.grok]
model = "grok-4.7"
runtime = "grok-cli"

[fallback.agent]
model = "claude-opus-5-5"
runtime = "cursor-cli"
max_calls = 2
max_minutes = 60

[roles.idea]
model = "claude-sonnet-5"
cli = "claude"
runtime = "claude-cli"
rank = 2
max_tokens = 5000
fallbacks = []

[roles.design]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 3
max_tokens = 5000
effort = "high"
fallbacks = ["grok", "agent"]

[roles.design-challenge]
model = "claude-opus-5-5"
cli = "claude"
runtime = "claude-cli"
rank = 4
max_tokens = 5000
effort = "xhigh"
fallbacks = ["grok"]
]]

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(args: { string }, extra: { [string]: string }?): fixture.Result
	return fakecli.zn(h, args, extra)
end
return t.spec("c0283 the dispatcher's prep gate", function(it)
	it("sets up a tracker and the fake CLIs", function()
		h = fakecli.new("c0283-dispatch", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0020/c0020.md"] = trackerfix.stub(
				"c0020",
				"second-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0021/c0021.md"] = trackerfix.stub(
				"c0021",
				"third-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0021/.models.toml"] = "[dispatch]\nauto_merge = []\n",
			["pickman/.tracker/issues/c0022/c0022.md"] = trackerfix.stub(
				"c0022",
				"fourth-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0023/c0023.md"] = trackerfix.stub(
				"c0023",
				"fifth-thing",
				"new-quiet-copper-falcon"
			),
		})
		t.expect(zn({ "dispatch", "vet" }).ok).toBe(true)
	end)

	it("the prep gate never merges, whatever auto_merge says, and a worker cannot approve", function()
		fakecli.clear(h)
		local url = "https://github.com/zn-fixture/c0283-dispatch.git"
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
		if r.code ~= 4 then
			error(`exit {r.code}: {r.stdout}{r.stderr}{fakecli.log(h)}`)
		end
		t.expect(has(r.stdout, "the prep PR #7 waits for the user's approval and merge")).toBe(true)
		t.expect(has(r.stdout, "./zn approve c0020")).toBe(true)
		t.expect(has(r.stdout, "./zn dispatch c0020 again")).toBe(true)
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
		local approve = zn({ "approve", "c0020" }, { ZN_DISPATCH = "1" })
		t.expect(approve.ok).toBe(false)
		t.expect(has(approve.stderr, "ZN_DISPATCH is set")).toBe(true)
	end)

	it(
		"the suffix follows the reason: a carrying PR is not told to merge, a red one is told to resolve first",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude", "claim")
			local function pr(n: number, files: { [string]: string }, ci: string): string
				local sha = fakecli.pullRequest(h, n, files)
				return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"{ci}"\}],"headRefOid":"{sha}"\}`
			end
			-- a prep PR whose head carries code waits for a human's judgement: its reason is kept, and nothing says merge it
			fs.writeFile(
				`{h.fakes}/pr-prep-fourth-thing.json`,
				pr(
					9,
					{ ["pickman/.tracker/issues/c0022/x.md"] = "x\n", ["src/x.lua"] = "return 1\n" },
					"SUCCESS"
				)
			)
			local carries = zn({ "dispatch", "c0022" })
			t.expect(carries.code).toBe(4)
			t.expect(has(carries.stdout, "src/x.lua")).toBe(true)
			t.expect(has(carries.stdout, "merge it yourself")).toBe(false)
			-- red CI: the user is told to resolve that first
			fs.writeFile(
				`{h.fakes}/pr-prep-fifth-thing.json`,
				pr(10, { ["pickman/.tracker/issues/c0023/x.md"] = "x\n" }, "FAILURE")
			)
			local red = zn({ "dispatch", "c0023" })
			t.expect(red.code).toBe(4)
			t.expect(has(red.stdout, "waits for green CI")).toBe(true)
			t.expect(has(red.stdout, "when that is resolved, approve the design with ./zn approve c0023"))
				.toBe(true)
			t.expect(has(fakecli.log(h), "realgh pr merge 9")).toBe(false)
			t.expect(has(fakecli.log(h), "realgh pr merge 10")).toBe(false)
		end
	)
end)
