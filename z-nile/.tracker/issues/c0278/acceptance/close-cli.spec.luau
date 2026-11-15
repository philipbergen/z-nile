--!strict
-- c0278 AC3, AC4, AC5: `./zn close <issue> --reason "<why>" [--carry]`. The published close is one tracker-only commit
-- on origin/main that stamps the document's status: closed-… and adds wont_do: <why>, and nothing else: the folder,
-- its reviews, spend.md and check.sh stay where they are. Every refusal publishes nothing and names its way out.
-- `--carry` writes the same document in this tree, publishes nothing, and is judged on this tree. Driven through
-- scripts/tracker.sh in worktrees of a fixture under .cache/c0278-close (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ISSUES = "pickman/.tracker/issues"
local RAFTS = "pickman/.tracker/rafts"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local REASON = "moot: superseded by c0520"

local function issue(id: string, status: string, design: string, raft: string?, deps: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: slug-{id}\nraft: {raft or ""}\ndepends_on: [{deps or ""}]\nemergent: false\ndesign: {design}\ncreated: 2026-11-15\nsize: 50\nstatus: {status}\n---\n\n# {id}\n\n## Problem\nSomething.\n`
end
local function raftDoc(id: string, issues: string, status: string): string
	return `---\nid: {id}\ntype: chore\ntitle: Raft\nslug: raft-{id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-15\nstatus: {status}\n---\n\n# {id}\n`
end

local f: trackerfix.Fixture
local W, W2, W3 = "", "", ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function onOrigin(path: string): string?
	local r = fixture.exec(f.origin, "git", { "show", `main:{path}` })
	return if r.ok then r.stdout else nil
end
local function tr(cwd: string, args: { string }, env: { [string]: string }?): fixture.Result
	return trackerfix.tr(f, cwd, args, env)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function refused(cwd: string, args: { string }, env: { [string]: string }?, ...: string)
	local before = tip()
	local r = tr(cwd, args, env)
	if r.ok then
		error(`{table.concat(args, " ")} was accepted: {r.stdout}`, 2)
	end
	for _, needle in { ... } do
		if not has(r.stderr .. r.stdout, needle) then
			error(`{table.concat(args, " ")}: output lacks {needle}: {r.stderr}{r.stdout}`, 2)
		end
	end
	t.expect(tip()).toBe(before)
end
-- the document as a close must leave it: the status: line replaced by `stamp`, then wont_do: <reason> appended as the
-- frontmatter's last line, every other byte kept (an oracle of its own, not closing.edit)
local function closedAs(text: string, stamp: string, reason: string): string
	local head, block, rest = string.match(text, "^(%-%-%-\n)(.-\n)(%-%-%-\n.*)$")
	assert(head and block and rest, "no frontmatter")
	local s, e = string.find(block, "status: [^\n]*\n")
	assert(s and e, "no status line")
	block = string.sub(block, 1, s - 1) .. `status: {stamp}\n` .. string.sub(block, e + 1)
	return head .. block .. `wont_do: {reason}\n` .. rest
end
local function statusOf(text: string?): string
	return string.match(text or "", "\nstatus: (%S+)\n") or ""
end

return t.spec("c0278 ./zn close", function(it)
	it(
		"sets up new, prepared, preparing, rafted, depended-on, done and active issues, a raft and a worktree",
		function()
			local seed: { [string]: string } = {
				[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
				["pickman/.tracker/architecture.md"] = "# Architecture\n",
				[`{ISSUES}/c0510/c0510.md`] = issue("c0510", "new-amber-otter-lynx", "draft"),
				[`{ISSUES}/c0510/design-review-001.md`] = "# Design review 001\n\nVerdict: approve\n",
				[`{ISSUES}/c0510/spend.md`] = "# Spend: c0510\n",
				[`{ISSUES}/c0520/c0520.md`] = issue("c0520", "prepared-amber-otter-lynx", "ready"),
				[`{ISSUES}/c0530/c0530.md`] = issue("c0530", "preparing-amber-otter-lynx", "draft"),
				[`{ISSUES}/c0540/c0540.md`] = issue("c0540", "prepared-brisk-heron-lynx", "ready", "R0510"),
				[`{RAFTS}/R0510/R0510.md`] = raftDoc("R0510", "c0540", "prepared-brisk-heron-lynx"),
				[`{ISSUES}/c0550/c0550.md`] = issue("c0550", "new-amber-otter-lynx", "draft"),
				[`{ISSUES}/c0560/c0560.md`] = issue("c0560", "new-amber-otter-lynx", "draft", nil, "c0550"),
				-- only a done item depends on c0565: a done dependent never holds an issue open
				[`{ISSUES}/c0565/c0565.md`] = issue("c0565", "new-amber-otter-lynx", "draft"),
				[`{ISSUES}/done/c0570/c0570.md`] = issue("c0570", "done", "ready", "R0590", "c0565"),
				[`{ISSUES}/active/c0580/c0580.md`] = issue(
					"c0580",
					"active-jolly-lynx-heron",
					"ready",
					"R0520"
				),
				[`{RAFTS}/active/R0520/R0520.md`] = raftDoc("R0520", "c0580", "active-jolly-lynx-heron"),
				[`{ISSUES}/c0590/c0590.md`] = issue("c0590", "new-amber-otter-lynx", "draft"),
				[`{ISSUES}/c0600/c0600.md`] = issue("c0600", "prepared-amber-otter-lynx", "ready"),
			}
			for _, p in
				{
					"c0510",
					"c0520",
					"c0530",
					"c0540",
					"c0550",
					"c0560",
					"c0565",
					"done/c0570",
					"active/c0580",
					"c0590",
					"c0600",
				}
			do
				seed[`{ISSUES}/{p}/check.sh`] = CHECK
			end
			seed[`{RAFTS}/R0510/check.sh`] = CHECK
			seed[`{RAFTS}/active/R0520/check.sh`] = CHECK
			f = trackerfix.new("c0278-close", seed)
			W = trOk(f.main, { "worktree", "prep-close-a" })
			W2 = trOk(f.main, { "worktree", "prep-close-b" })
			W3 = trOk(f.main, { "worktree", "prep-close-c" })
		end
	)

	it(
		"close publishes one tracker-only commit that changes only the document's status and adds wont_do",
		function()
			local doc = `{ISSUES}/c0510/c0510.md`
			local before, oldTip = onOrigin(doc) :: string, tip()
			local out = trOk(W, { "close", "c0510", "--reason", REASON })
			t.expect(has(out, "closed c0510 on origin/main")).toBe(true)
			local newTip = tip()
			t.expect(newTip ~= oldTip).toBe(true)
			t.expect(fixture.git(f.origin, { "rev-parse", "main^" })).toBe(oldTip)
			t.expect(
				fixture.git(f.origin, { "diff-tree", "-r", "--no-renames", "--name-status", "main^", "main" })
			)
				.toBe(`M\t{doc}`)
			local after = onOrigin(doc) :: string
			local stamp = statusOf(after)
			t.expect(string.match(stamp, "^closed%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
			t.expect(after).toBe(closedAs(before, stamp, REASON))
			-- the worktree is not touched: it sees the close on its next sync
			t.expect(statusOf(fs.readFile(`{W}/{doc}`))).toBe("new-amber-otter-lynx")
		end
	)

	it(
		"the closed issue keeps its folder: find, capture, status, spend.md and its review files are where they were",
		function()
			trOk(W, { "sync" })
			t.expect(trOk(W, { "find", "c0510" })).toBe(`{ISSUES}/c0510`)
			t.expect(trOk(W, { "status", "c0510" })).toBe("closed")
			t.expect(has(trOk(W, { "capture", "c0510" }), `{ISSUES}/c0510/c0510.md`)).toBe(true)
			for _, rel in { "check.sh", "spend.md", "design-review-001.md" } do
				t.expect(onOrigin(`{ISSUES}/c0510/{rel}`) ~= nil).toBe(true)
				t.expect(fs.isFile(`{W}/{ISSUES}/c0510/{rel}`)).toBe(true)
			end
		end
	)

	it("the commit's subject and Reason line carry the id and the reason", function()
		t.expect(fixture.git(f.origin, { "log", "-1", "--format=%s", "main" }))
			.toBe("tracker: close c0510 won't do")
		t.expect(has(fixture.git(f.origin, { "log", "-1", "--format=%b", "main" }), `Reason: {REASON}`))
			.toBe(true)
	end)

	it("a prepared raftless issue is closed too", function()
		trOk(W, { "close", "c0520", "--reason", "moot: folded into c0510" })
		local text = onOrigin(`{ISSUES}/c0520/c0520.md`)
		t.expect(string.match(statusOf(text), "^closed%-") ~= nil).toBe(true)
		t.expect(has(text, "\nwont_do: moot: folded into c0510\n")).toBe(true)
	end)

	it(
		"close refuses without a reason, with a blank or multi-line reason, a raft id, an unknown id, a done, an active, a closed, a preparing, a rafted and a depended-on issue, each naming its way out, and publishes nothing",
		function()
			refused(W, { "close", "c0550" }, nil, "--reason")
			refused(W, { "close", "c0550", "--reason", "   " }, nil, "--reason")
			refused(W, { "close", "c0550", "--reason", "two\nlines" }, nil, "one line")
			refused(W, { "close" }, nil, "usage: ./zn close <issue> --reason")
			refused(W, { "close", "R0510", "--reason", REASON }, nil, "R0510 is a raft: close takes an issue")
			refused(W, { "close", "c0999", "--reason", REASON }, nil, "c0999 is not on origin/main")
			refused(W, { "close", "c0570", "--reason", REASON }, nil, "c0570 is done")
			refused(
				W,
				{ "close", "c0580", "--reason", REASON },
				nil,
				"readied (in active/)",
				"./zn stop R0520"
			)
			refused(W, { "close", "c0510", "--reason", REASON }, nil, "c0510 is already closed")
			refused(
				W,
				{ "close", "c0530", "--reason", REASON },
				nil,
				"being prepared",
				"./zn status c0530 new"
			)
			refused(
				W,
				{ "close", "c0540", "--reason", REASON },
				nil,
				"c0540 is in R0510",
				"./zn unfold R0510 c0540"
			)
			refused(W, { "close", "c0550", "--reason", REASON }, nil, "named in the depends_on of c0560")
			-- a dependent in done/ never holds it
			trOk(W, { "close", "c0565", "--reason", REASON })
			t.expect(has(onOrigin(`{ISSUES}/c0565/c0565.md`), "\nwont_do: ")).toBe(true)
		end
	)

	it("close refuses in the main checkout and, without --carry, without an origin", function()
		refused(f.main, { "close", "c0590", "--reason", REASON }, nil, "must run inside a worktree")
		refused(
			W,
			{ "close", "c0590", "--reason", REASON },
			{ PICKMAN_PUBLISH = "0" },
			"needs an origin remote",
			"--carry"
		)
	end)

	it(
		"close --carry edits only this tree's document, the same bytes but the stamp, and publishes nothing",
		function()
			local doc = `{ISSUES}/c0600/c0600.md`
			trOk(W2, { "sync" })
			local before, oldTip = fs.readFile(`{W2}/{doc}`), tip()
			local out = trOk(W2, { "close", "c0600", "--carry", "--reason", REASON })
			t.expect(has(out, "closed c0600 in this tree (carried)")).toBe(true)
			t.expect(tip()).toBe(oldTip)
			t.expect(statusOf(onOrigin(doc))).toBe("prepared-amber-otter-lynx")
			local after = fs.readFile(`{W2}/{doc}`)
			local stamp = statusOf(after)
			t.expect(string.match(stamp, "^closed%-%a+%-%a+%-%a+$") ~= nil).toBe(true)
			t.expect(after).toBe(closedAs(before, stamp, REASON))
			-- nothing staged or committed: only the document changed
			t.expect(fixture.git(W2, { "status", "--porcelain" })).toBe(` M {doc}`)
			t.expect(trOk(W2, { "list", "closed" }) ~= "").toBe(true)
			-- offline works for --carry
			local r = tr(W3, { "close", "c0590", "--carry", "--reason", REASON }, { PICKMAN_PUBLISH = "0" })
			t.expect(r.ok).toBe(true)
			fixture.git(W3, { "checkout", "--", `{ISSUES}/c0590/c0590.md` })
		end
	)

	it("close --carry refuses as the published close does, judged on this tree", function()
		trOk(W3, { "sync" })
		-- in this tree only, c0550 names c0590 in its depends_on: a live dependent nobody published
		local dep = `{W3}/{ISSUES}/c0550/c0550.md`
		local text = fs.readFile(dep)
		fs.writeFile(dep, (string.gsub(text, "depends_on: %[%]", "depends_on: [c0590]", 1)))
		refused(
			W3,
			{ "close", "c0590", "--carry", "--reason", REASON },
			nil,
			"named in the depends_on of c0550"
		)
		t.expect(statusOf(fs.readFile(`{W3}/{ISSUES}/c0590/c0590.md`))).toBe("new-amber-otter-lynx")
		refused(W3, { "close", "c0540", "--carry", "--reason", REASON }, nil, "c0540 is in R0510")
		refused(
			W3,
			{ "close", "c0530", "--carry", "--reason", REASON },
			nil,
			"being prepared (preparing on this tree)"
		)
		refused(W3, { "close", "c0999", "--carry", "--reason", REASON }, nil, "c0999 is not on this tree")
		refused(W3, { "close", "c0510", "--carry", "--reason", REASON }, nil, "c0510 is already closed")
		-- the published close judges origin/main, where c0590 has no dependent
		trOk(W3, { "close", "c0590", "--reason", REASON })
		t.expect(has(onOrigin(`{ISSUES}/c0590/c0590.md`), `\nwont_do: {REASON}\n`)).toBe(true)
		fixture.git(W3, { "checkout", "--", `{ISSUES}/c0550/c0550.md` })
	end)

	it("cleans up", function()
		fs.removeDir(f.base)
	end)
end)
