--!strict
-- c0359 AC5: the dispatcher's prep and raft gates refuse a pull request whose merge with today's main fails the gate's
-- format and lint stages (`z-nile/check.sh --lint` on that merge), and say which file; a clean one still merges, pinned to
-- its head; a PR that changes no path the stages read is not linted (a failing file already on main does not hold it);
-- a red static check stops it at green CI with the files still named; a format setting in a PR's folder holds it;
-- the stages read the merge, not the head alone; they run after the shape judgement, so a PR's own gate script never
-- runs; and the judgement's scratch tree is removed. For real with fake CLIs
-- and a fake gh (@tests/lib/fakecli), every PR a real head on the fixture's origin. Fixture under .cache/c0359-gate.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
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
]]
-- unformatted for the root's stylua.toml; formatted with one selene warning only; clean
local UNFORMATTED = "local x = {1,2}\nreturn x\n"
local SHADOWED = "local a = 1\nlocal function f()\n\tlocal a = 2\n\treturn a\nend\nreturn { a, f }\n"
local CLEAN = "local x = { 1, 2 }\nreturn x\n"

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function zn(args: { string }): fixture.Result
	return fakecli.zn(h, args)
end
local function preparing(id: string, slug: string): string
	return trackerfix.stub(id, slug, "preparing-quiet-copper-falcon")
end
local function prJson(n: number, head: string, conclusion: string?): string
	local c = conclusion or "SUCCESS"
	return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[\{"conclusion":"{c}"\}],"headRefOid":"{head}"\}`
end
-- the dispatcher's own claim of `id`: a z-design step of its own in the item's history
local function claimed(id: string)
	fs.writeDir(`{h.f.main}/.cache/dispatch/{id}`)
	fs.writeFile(
		`{h.f.main}/.cache/dispatch/{id}/state.json`,
		`\{"id":"{id}","mode":"chain","history":[\{"step":"z-design","outcome":"ok"\}],"merged":[],"pushed":[],"pending":[]\}`
	)
end
local function merged(n: number): boolean
	return has(fakecli.log(h), `realgh pr merge {n} `)
end
local function issueDir(id: string): string
	return `pickman/.tracker/issues/{id}`
end

return t.spec("c0359 the gates run the format and lint stages", function(it)
	local headLate = ""

	it(
		"sets up a tracker with six issues in preparation, a prepared one, the root's settings and the fakes",
		function()
			h = fakecli.new("c0359-gate", {
				[".models.toml"] = MODELS,
				["stylua.toml"] = fs.readFile(`{TOP}/stylua.toml`),
				["selene.toml"] = fs.readFile(`{TOP}/selene.toml`),
				[`{issueDir("c0010")}/c0010.md`] = preparing("c0010", "lint-thing"),
				[`{issueDir("c0020")}/c0020.md`] = preparing("c0020", "doc-thing"),
				[`{issueDir("c0030")}/c0030.md`] = preparing("c0030", "late-thing"),
				[`{issueDir("c0040")}/c0040.md`] = preparing("c0040", "script-thing"),
				[`{issueDir("c0050")}/c0050.md`] = preparing("c0050", "red-thing"),
				[`{issueDir("c0060")}/c0060.md`] = preparing("c0060", "ignore-thing"),
				[`{issueDir("c0096")}/c0096.md`] = (string.gsub(
					trackerfix.stub("c0096", "rafted-thing", "prepared-quiet-copper-falcon"),
					"design: draft",
					"design: ready"
				)),
				[`{issueDir("c0096")}/.models.toml`] = '[dispatch]\nauto_merge = ["raft"]\n',
			})
			-- a GitHub-looking origin, rewritten to the fixture's own (the chain asks the fake gh about PRs)
			local url = "https://github.com/zn-fixture/c0359.git"
			fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
			fixture.git(h.f.main, { "remote", "set-url", "origin", url })
			for _, id in { "c0010", "c0020", "c0030", "c0040", "c0050", "c0060" } do
				claimed(id)
			end
			-- cut now, before main gains a failing file: its head is clean, its merge is not (the last case)
			headLate = fakecli.pullRequest(h, 61, { [`{issueDir("c0030")}/acceptance/a.spec.luau`] = CLEAN })
		end
	)

	it(
		"a prep PR whose merge fails the format stage waits for a human, naming the file, and is not merged",
		function()
			fakecli.clear(h)
			local sha =
				fakecli.pullRequest(h, 31, { [`{issueDir("c0010")}/acceptance/a.spec.luau`] = UNFORMATTED })
			fs.writeFile(`{h.fakes}/pr-prep-lint-thing.json`, prJson(31, sha))
			local r = zn({ "dispatch", "c0010" })
			t.expect(r.code).toBe(4)
			t.expect(has(r.stdout, "fails the static stages")).toBe(true)
			t.expect(has(r.stdout, "a.spec.luau")).toBe(true)
			t.expect(merged(31)).toBe(false)
		end
	)

	it("a lint warning alone in a prep PR's experiment holds it too", function()
		fakecli.clear(h)
		local sha = fakecli.pullRequest(h, 32, { [`{issueDir("c0010")}/experiments/w.luau`] = SHADOWED })
		fs.writeFile(`{h.fakes}/pr-prep-lint-thing.json`, prJson(32, sha))
		local r = zn({ "dispatch", "c0010" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "fails the static stages")).toBe(true)
		t.expect(has(r.stdout, "w.luau")).toBe(true)
		t.expect(merged(32)).toBe(false)
	end)

	it("a rafting PR whose merge fails the stages waits too", function()
		fakecli.clear(h)
		local doc = fixture.git(h.f.origin, { "show", `main:{issueDir("c0096")}/c0096.md` })
		local sha = fakecli.pullRequest(h, 41, {
			["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0096]\n---\n",
			["pickman/.tracker/rafts/R0050/notes.luau"] = UNFORMATTED,
			[`{issueDir("c0096")}/c0096.md`] = (string.gsub(doc, "\nraft: \n", "\nraft: R0050\n")),
		})
		fs.writeFile(`{h.fakes}/pr-raft-c0096.json`, prJson(41, sha))
		local r = zn({ "dispatch", "c0096" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "fails the static stages")).toBe(true)
		t.expect(has(r.stdout, "notes.luau")).toBe(true)
		t.expect(merged(41)).toBe(false)
	end)

	it("a clean prep PR merges, pinned to its head", function()
		fakecli.clear(h)
		local sha = fakecli.pullRequest(h, 33, { [`{issueDir("c0010")}/acceptance/a.spec.luau`] = CLEAN })
		fs.writeFile(`{h.fakes}/pr-prep-lint-thing.json`, prJson(33, sha))
		zn({ "dispatch", "c0010" })
		t.expect(has(fakecli.log(h), `realgh pr merge 33 --squash --match-head-commit {sha}`)).toBe(true)
	end)

	it("a red static check stops the gate at green CI, and the stop still names the failing files", function()
		fakecli.clear(h)
		local sha =
			fakecli.pullRequest(h, 81, { [`{issueDir("c0050")}/acceptance/a.spec.luau`] = UNFORMATTED })
		fs.writeFile(`{h.fakes}/pr-prep-red-thing.json`, prJson(81, sha, "FAILURE"))
		local r = zn({ "dispatch", "c0050" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "waits for green CI, and for a human: its merge fails the static stages"))
			.toBe(true)
		t.expect(has(r.stdout, "a.spec.luau")).toBe(true)
		t.expect(merged(81)).toBe(false)
	end)

	it("a format setting in a prep PR's folder holds it, even where it hides an unformatted spec", function()
		fakecli.clear(h)
		local sha = fakecli.pullRequest(h, 91, {
			[`{issueDir("c0060")}/acceptance/.styluaignore`] = "*\n",
			[`{issueDir("c0060")}/acceptance/a.spec.luau`] = UNFORMATTED,
		})
		fs.writeFile(`{h.fakes}/pr-prep-ignore-thing.json`, prJson(91, sha))
		local r = zn({ "dispatch", "c0060" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "format or lint settings under a .tracker/ folder")).toBe(true)
		t.expect(has(r.stdout, ".styluaignore")).toBe(true)
		t.expect(merged(91)).toBe(false)
	end)

	it(
		"a PR that changes no path the stages read is not linted, so a failing file on main does not hold it",
		function()
			fakecli.clear(h)
			fakecli.advanceMain(
				h,
				{ [`{issueDir("c0020")}/experiments/old.luau`] = UNFORMATTED },
				nil,
				"a failing file"
			)
			local sha = fakecli.pullRequest(h, 51, { [`{issueDir("c0020")}/notes.md`] = "notes\n" })
			fs.writeFile(`{h.fakes}/pr-prep-doc-thing.json`, prJson(51, sha))
			zn({ "dispatch", "c0020" })
			t.expect(has(fakecli.log(h), `realgh pr merge 51 --squash --match-head-commit {sha}`)).toBe(true)
		end
	)

	it("the stages read the merge with today's main, not the head alone", function()
		fakecli.clear(h)
		-- PR #61 was cut before main gained old.luau: its head passes, its merge carries main's failing file
		fs.writeFile(`{h.fakes}/pr-prep-late-thing.json`, prJson(61, headLate))
		local r = zn({ "dispatch", "c0030" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "fails the static stages")).toBe(true)
		t.expect(has(r.stdout, "old.luau")).toBe(true)
		t.expect(merged(61)).toBe(false)
	end)

	it("the stages run only after the shape judgement, so a PR's own z-nile/check.sh never runs", function()
		fakecli.clear(h)
		-- a prep PR that replaces the gate script with one that leaves a mark, beside a clean spec of its own
		local sha = fakecli.pullRequest(h, 71, {
			[`{issueDir("c0040")}/acceptance/a.spec.luau`] = CLEAN,
			["z-nile/check.sh"] = '#!/usr/bin/env bash\ntouch "$FAKE_DIR/ran-pr-script"\nexit 0\n',
		})
		fs.writeFile(`{h.fakes}/pr-prep-script-thing.json`, prJson(71, sha))
		local r = zn({ "dispatch", "c0040" })
		t.expect(r.code).toBe(4)
		t.expect(has(r.stdout, "z-nile/check.sh")).toBe(true)
		t.expect(fs.isFile(`{h.fakes}/ran-pr-script`)).toBe(false)
		t.expect(merged(71)).toBe(false)
	end)

	it("no judgement leaves its scratch tree behind", function()
		local left: { string } = {}
		for _, name in fs.readDir(`{h.f.main}/.cache/dispatch`) do
			if string.sub(name, 1, 5) == "lint-" or string.sub(name, 1, 6) == "judge-" then
				table.insert(left, name)
			end
		end
		t.expect(left).toEqual({})
	end)
end)
