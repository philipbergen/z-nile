--!strict
-- c0261 (AC5, the chain's wiring): at a prep gate whose PR still waits for its checks the chain runs the `z-wait` step
-- (a fake claude), stores the head it waited on whatever the step's outcome, then reads the PR again: it merges when the
-- PR turned green, and stops with exit 4 when it is still red; a rerun does not wait again on the same head; a z-wait
-- that failed is not a failed chain. Fake CLIs and a fake gh (@tests/lib/fakecli), fixture under .cache/c0261-wait.
local fakecli = require("@tests/lib/fakecli")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local MODELS = [[
order = ["claude"]

[dispatch]
auto_merge = ["prep"]
stall_seconds = 5
tool_seconds = 8
wait_minutes = 20

[z-design.claude]
model = "claude-opus-5-5"
rank = 3
runtime = "claude-cli"
max_tokens = 5000

[z-wait.claude]
model = "claude-haiku-5-5"
rank = 1
runtime = "claude-cli"
max_tokens = 5000
]]

local h: fakecli.Harness
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function count(text: string, needle: string): number
	local n, i = 0, 1
	while true do
		local a, b = string.find(text, needle, i, true)
		if not a then
			return n
		end
		n += 1
		i = (b :: number) + 1
	end
end
local function prJson(n: number, head: string, green: boolean): string
	local rollup = if green then '{"conclusion":"SUCCESS"}' else '{"state":"PENDING"}'
	return `\{"number":{n},"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","statusCheckRollup":[{rollup}],"headRefOid":"{head}"\}`
end
local function must(r: fixture.Result): fixture.Result
	if r.code ~= 0 and r.code ~= 1 then
		error(r.stdout .. r.stderr)
	end
	return r
end
return t.spec("c0261 the chain runs z-wait at a gate that waits for checks", function(it)
	it("sets up items with prep and rafting PRs", function()
		h = fakecli.new("c0261-wait", {
			[".models.toml"] = MODELS,
			["pickman/.tracker/issues/c0082/c0082.md"] = trackerfix.stub(
				"c0082",
				"tenth-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0090/c0090.md"] = string.gsub(
				trackerfix.stub("c0090", "rafted-thing", "prepared-quiet-copper-falcon"),
				"design: draft",
				"design: ready"
			),
			["pickman/.tracker/issues/c0090/.models.toml"] = '[dispatch]\nauto_merge = ["raft"]\n',
			["pickman/.tracker/issues/c0070/c0070.md"] = trackerfix.stub(
				"c0070",
				"seventh-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0080/c0080.md"] = trackerfix.stub(
				"c0080",
				"eighth-thing",
				"new-quiet-copper-falcon"
			),
			["pickman/.tracker/issues/c0081/c0081.md"] = trackerfix.stub(
				"c0081",
				"ninth-thing",
				"new-quiet-copper-falcon"
			),
		})
		-- the z-wait prompt is the poll alone, so the stock fake (which keys on "z-nile step <name>") cannot tell it: a
		-- wrapper logs the wait, runs <fakes>/wait.sh (what the poll would have seen change) and fails when wait.fail exists
		process.exec("mv", { `{h.bin}/claude`, `{h.bin}/claude.real` })
		fs.writeFile(
			`{h.bin}/claude`,
			table.concat({
				"#!/bin/sh",
				'case "$*" in *"gh pr "*)',
				'  { echo "claude step=z-wait"; echo "cwd=$(pwd -P)"; echo "args=$*"; } >> "$FAKE_DIR/log"',
				'  [ -f "$FAKE_DIR/wait.sh" ] && sh "$FAKE_DIR/wait.sh"',
				'  [ -f "$FAKE_DIR/wait.fail" ] && { echo boom >&2; exit 1; } ;;',
				"esac",
				'exec "$(dirname "$0")/claude.real" "$@"',
				"",
			}, "\n")
		)
		process.exec("chmod", { "+x", `{h.bin}/claude` })
		local url = "https://github.com/zn-fixture/c0261.git"
		fixture.git(h.f.main, { "config", `url.{h.f.origin}.insteadOf`, url })
		fixture.git(h.f.main, { "remote", "set-url", "origin", url })
	end)

	it("waits on z-wait, stores the head, and merges when the PR turned green (AC5)", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude.z-design", "claim") -- the claim the gate needs (preparing, the dispatcher's own)
		local head = fakecli.pullRequest(h, 7, { ["pickman/.tracker/issues/c0070/x.md"] = "notes\n" })
		fs.writeFile(`{h.fakes}/pr-prep-seventh-thing.json`, prJson(7, head, false))
		local green = prJson(7, head, true)
		fs.writeFile(`{h.fakes}/wait.sh`, `printf '%s' '{green}' > "$FAKE_DIR/pr-prep-seventh-thing.json"\n`)
		local r = must(fakecli.zn(h, { "dispatch", "c0070" }))
		local log = fakecli.log(h)
		t.expect(count(log, "claude step=z-wait")).toBe(1)
		-- the prompt is the poll alone (checks of PR 7), bounded, and asks for at most wait_minutes / 10 polls
		t.expect(has(log, "gh pr checks 7")).toBe(true)
		t.expect(has(log, "at most 2 times")).toBe(true)
		t.expect(has(log, "--model claude-haiku-5-5")).toBe(true)
		t.expect(has(log, `realgh pr merge 7 --squash --match-head-commit {head}`)).toBe(true)
		t.expect(fakecli.state(h, "c0070").waitedHead).toBe(head)
		t.expect(has(r.stdout, "next: z-wait")).toBe(true)
	end)

	it(
		"ends exit 4 after the wait when still red, and a rerun on the same head does not wait again (AC5)",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude.z-design", "claim") -- the claim the gate needs (preparing, the dispatcher's own)
			local head = fakecli.pullRequest(h, 8, { ["pickman/.tracker/issues/c0080/x.md"] = "notes\n" })
			fs.writeFile(`{h.fakes}/pr-prep-eighth-thing.json`, prJson(8, head, false))
			fs.writeFile(`{h.fakes}/script.sh`, ":\n")
			fakecli.mode(h, "claude.z-wait", "script")
			local first = fakecli.zn(h, { "dispatch", "c0080" })
			t.expect(first.code).toBe(4)
			t.expect(has(first.stdout, "waits for green CI")).toBe(true)
			t.expect(count(fakecli.log(h), "claude step=z-wait")).toBe(1)
			t.expect(has(fakecli.log(h), "realgh pr merge 8")).toBe(false)
			t.expect(fakecli.state(h, "c0080").waitedHead).toBe(head)
			local again = fakecli.zn(h, { "dispatch", "c0080" })
			t.expect(again.code).toBe(4)
			t.expect(count(fakecli.log(h), "claude step=z-wait")).toBe(1) -- once per head
		end
	)

	it(
		"a z-wait that failed is not a failed chain: the head is stored and the gate stops with exit 4 (AC5)",
		function()
			fakecli.clear(h)
			fakecli.mode(h, "claude.z-design", "claim") -- the claim the gate needs (preparing, the dispatcher's own)
			local head = fakecli.pullRequest(h, 9, { ["pickman/.tracker/issues/c0081/x.md"] = "notes\n" })
			fs.writeFile(`{h.fakes}/pr-prep-ninth-thing.json`, prJson(9, head, false))
			fs.writeFile(`{h.fakes}/wait.fail`, "1")
			local r = fakecli.zn(h, { "dispatch", "c0081" })
			t.expect(r.code).toBe(4)
			t.expect(count(fakecli.log(h), "claude step=z-wait")).toBe(1)
			t.expect(fakecli.state(h, "c0081").waitedHead).toBe(head)
		end
	)

	it("a green PR whose merge state is still UNKNOWN waits for `mergeable`, then merges (AC5)", function()
		fakecli.clear(h)
		fakecli.mode(h, "claude.z-design", "claim")
		local head = fakecli.pullRequest(h, 10, { ["pickman/.tracker/issues/c0082/x.md"] = "notes\n" })
		local function json(state: string): string
			return `\{"number":10,"state":"OPEN","isDraft":false,"mergeable":"{state}","statusCheckRollup":[\{"conclusion":"SUCCESS"\}],"headRefOid":"{head}"\}`
		end
		fs.writeFile(`{h.fakes}/pr-prep-tenth-thing.json`, json("UNKNOWN"))
		fs.writeFile(
			`{h.fakes}/wait.sh`,
			`printf '%s' '{json("MERGEABLE")}' > "$FAKE_DIR/pr-prep-tenth-thing.json"\n`
		)
		must(fakecli.zn(h, { "dispatch", "c0082" }))
		local log = fakecli.log(h)
		t.expect(count(log, "claude step=z-wait")).toBe(1)
		t.expect(has(log, "gh pr view 10 --json mergeable")).toBe(true) -- the poll is for the merge state, not the checks
		t.expect(has(log, "gh pr checks 10")).toBe(false)
		t.expect(has(log, `realgh pr merge 10 --squash --match-head-commit {head}`)).toBe(true)
	end)

	it(
		"the rafting gate waits too: z-wait runs in the raft's worktree, and the green PR merges (AC5)",
		function()
			fakecli.clear(h)
			local doc = fixture.git(h.f.origin, { "show", "main:pickman/.tracker/issues/c0090/c0090.md" })
			local files = {
				["pickman/.tracker/rafts/R0050/R0050.md"] = "---\nid: R0050\nslug: a-raft\ntitle: a raft\nissues: [c0090]\n---\n",
				["pickman/.tracker/issues/c0090/c0090.md"] = (
					string.gsub(doc, "\nraft: \n", "\nraft: R0050\n")
				),
			}
			local head = fakecli.pullRequest(h, 11, files)
			fs.writeFile(`{h.fakes}/pr-raft-c0090.json`, prJson(11, head, false))
			fs.writeFile(
				`{h.fakes}/wait.sh`,
				`printf '%s' '{prJson(11, head, true)}' > "$FAKE_DIR/pr-raft-c0090.json"\n`
			)
			must(fakecli.zn(h, { "dispatch", "c0090" }))
			local log = fakecli.log(h)
			t.expect(count(log, "claude step=z-wait")).toBe(1)
			t.expect(has(log, "/.worktree/raft-c0090\n")).toBe(true) -- the cwd of the wait
			t.expect(has(log, "gh pr checks 11")).toBe(true)
			t.expect(has(log, `realgh pr merge 11 --squash --match-head-commit {head}`)).toBe(true)
			t.expect(fakecli.state(h, "c0090").waitedHead).toBe(head)
		end
	)
end)
