--!strict
-- c0283 AC7: the dispatcher's prep gate never merges, whatever auto_merge says, every prep stop keeps its reason and gains
-- the approve suffix, a gate that no condition fails says the PR waits for the user, and a dispatched worker cannot
-- approve. Fake CLIs and a fixture under .cache (tests/lib/fakecli), as c0117's guards.
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
		t.expect(r.code).toBe(4)
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
		t.expect(has(approve.stderr, "dispatch")).toBe(true)
	end)
end)
