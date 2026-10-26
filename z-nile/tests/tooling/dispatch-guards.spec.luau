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
			t.expect(has(fakecli.log(h), "realgh pr merge")).toBe(false)
			-- merges: the raft's own document and its members' raft: lines, pinned to the head
			local sha = fakecli.pullRequest(h, 34, own)
			fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(34, sha))
			zn({ "dispatch", "c0096" })
			t.expect(has(fakecli.log(h), `realgh pr merge 34 --squash --match-head-commit {sha}`)).toBe(true)
		end
	)
end)
