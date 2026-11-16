--!strict
-- c0278 AC2, AC6 to AC9: what every reader does with an issue closed as won't do. list, the bare status listing, the
-- board and raft-plan leave it out (list closed shows it with its reason); no status move, idea, fold or new raft takes
-- it; the dispatcher stops it as finished; watch-net's open-defect test ignores it; audit reports a close that ./zn
-- close did not make; and the publish guard never publishes a closed document again. Fixture under .cache/c0278-readers
-- (tests/lib/trackerfix), the closes made by ./zn close itself.
local dispatch = require("@znile/engine/dispatch")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local publish = require("@znile/engine/publish")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")
local watchcmd = require("@znile/engine/watchcmd")

local ISSUES = "pickman/.tracker/issues"
local RAFTS = "pickman/.tracker/rafts"
local CHECK = 'source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"\n'
	.. 'check "AC1: ok" true\nfinish\n'
local REASON = "moot: superseded"

local function issue(
	id: string,
	status: string,
	design: string,
	raft: string?,
	deps: string?,
	extra: string?
): string
	return `---\nid: {id}\ntype: chore\ntitle: {id} title\nslug: slug-{id}\nraft: {raft or ""}\ndepends_on: [{deps or ""}]\nemergent: false\ndesign: {design}\ncreated: 2026-11-15\nsize: 50\nstatus: {status}\n{extra or ""}---\n\n# {id}\n`
end
local function raftDoc(id: string, issues: string, status: string, extra: string?): string
	return `---\nid: {id}\ntype: chore\ntitle: Raft\nslug: raft-{id}\nsingle: false\nissues: [{issues}]\ndesign: ready\ncreated: 2026-11-15\nstatus: {status}\n{extra or ""}---\n\n# {id}\n\n## Theme\nT.\n\n## Order & dependencies\nBy id.\n`
end

local f: trackerfix.Fixture
local W, R = "", ""
local listBefore = ""

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
local function tip(): string
	return fixture.git(f.origin, { "rev-parse", "main" })
end
local function tr(cwd: string, args: { string }): fixture.Result
	return trackerfix.tr(f, cwd, args)
end
local function trOk(cwd: string, args: { string }): string
	return trackerfix.trOk(f, cwd, args)
end
local function refused(cwd: string, args: { string }, ...: string)
	local before = tip()
	local r = tr(cwd, args)
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
local function lines(text: string): { string }
	local out: { string } = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(out, line)
	end
	return out
end
local function rowOf(text: string, id: string): string?
	for _, line in lines(text) do
		if string.sub(line, 1, #id + 1) == id .. " " then
			return line
		end
	end
	return nil
end

return t.spec("c0278 readers of a closed issue", function(it)
	it("sets up issues, a raft, a rafting and a design worktree, and closes two issues", function()
		local seed: { [string]: string } = {
			[".gitignore"] = ".cache/\n.worktree/\n.DS_Store\n/*/.tracker/rafts/active/*/prompt.md\n",
			["pickman/.tracker/architecture.md"] = "# Architecture\n",
			[`{ISSUES}/c0510/c0510.md`] = issue("c0510", "new-amber-otter-lynx", "draft"),
			[`{ISSUES}/c0520/c0520.md`] = issue("c0520", "prepared-amber-otter-lynx", "ready"),
			[`{ISSUES}/c0525/c0525.md`] = issue("c0525", "prepared-amber-otter-lynx", "ready"),
			[`{ISSUES}/c0530/c0530.md`] = issue("c0530", "new-amber-otter-lynx", "draft"),
			[`{ISSUES}/c0540/c0540.md`] = issue("c0540", "prepared-brisk-heron-lynx", "ready", "R0510"),
			[`{RAFTS}/R0510/R0510.md`] = raftDoc("R0510", "c0540", "prepared-brisk-heron-lynx"),
		}
		for _, id in { "c0510", "c0520", "c0525", "c0530", "c0540" } do
			seed[`{ISSUES}/{id}/check.sh`] = CHECK
		end
		seed[`{RAFTS}/R0510/check.sh`] = CHECK
		f = trackerfix.new("c0278-readers", seed)
		W = trOk(f.main, { "worktree", "prep-readers" })
		R = trOk(f.main, { "worktree", "raft-readers" })
		listBefore = trOk(W, { "list" })
		t.expect(has(trOk(W, { "raft-plan" }), "c0520")).toBe(true)
		trOk(W, { "close", "c0510", "--reason", REASON })
		trOk(W, { "close", "c0520", "--reason", REASON })
		trOk(W, { "sync" })
		trOk(R, { "sync" })
	end)

	it(
		"list leaves a closed issue out, list backlog too, and list closed shows it with its reason",
		function()
			local all = trOk(W, { "list" })
			t.expect(rowOf(all, "c0510")).toBe(nil)
			t.expect(rowOf(all, "c0520")).toBe(nil)
			t.expect(rowOf(all, "c0530") ~= nil).toBe(true)
			local backlog = trOk(W, { "list", "backlog" })
			t.expect(rowOf(backlog, "c0510")).toBe(nil)
			t.expect(rowOf(backlog, "c0530") ~= nil).toBe(true)
			local closed = trOk(W, { "list", "closed" })
			local row = rowOf(closed, "c0510") :: string
			t.expect(row ~= nil).toBe(true)
			t.expect(string.match(row, "^c0510  closed   chore ") ~= nil).toBe(true)
			t.expect(has(row, `  (won't do: {REASON})`)).toBe(true)
			t.expect(rowOf(closed, "c0520") ~= nil).toBe(true)
			t.expect(rowOf(closed, "c0530")).toBe(nil)
			t.expect(rowOf(closed, "R0510")).toBe(nil)
		end
	)

	it("list's other rows are unchanged by a close", function()
		local want: { string } = {}
		for _, line in lines(listBefore) do
			if not (string.sub(line, 1, 6) == "c0510 " or string.sub(line, 1, 6) == "c0520 ") then
				table.insert(want, line)
			end
		end
		t.expect(trOk(W, { "list" })).toBe(table.concat(want, "\n"))
	end)

	it("the bare status listing leaves it out and status <id> prints closed", function()
		local listing = trOk(W, { "status" })
		t.expect(has(listing, "c0510 ")).toBe(false)
		t.expect(has(listing, "c0530 new")).toBe(true)
		t.expect(trOk(W, { "status", "c0510" })).toBe("closed")
		t.expect(trOk(W, { "status", "c0520" })).toBe("closed")
	end)

	it("the board's data has no card for it and raft-plan does not offer it", function()
		local out = `{f.base}/board.html`
		trOk(W, { "board", "-O", "--out", out })
		local html = fs.readFile(out)
		t.expect(has(html, '"c0510"')).toBe(false)
		t.expect(has(html, '"c0520"')).toBe(false)
		t.expect(has(html, '"c0530"')).toBe(true)
		local plan = trOk(W, { "raft-plan" })
		t.expect(has(plan, "c0520")).toBe(false)
		t.expect(has(plan, "c0525")).toBe(true)
	end)

	it("status moves refuse a closed issue, and status <id> closed names ./zn close", function()
		refused(
			W,
			{ "status", "c0510", "preparing" },
			"c0510 is closed (won't do): nothing moves a closed issue"
		)
		refused(W, { "status", "c0510", "new" }, "c0510 is closed (won't do)")
		refused(W, { "status", "c0520", "prepared" }, "c0520 is closed (won't do)")
		refused(
			W,
			{ "status", "c0530", "closed" },
			"only ./zn close closes an issue",
			"./zn close c0530 --reason"
		)
	end)

	it("idea, fold and new raft refuse a closed issue", function()
		refused(W, { "idea", "c0510" }, "idea: c0510 is closed (won't do): nothing to write")
		refused(R, { "fold", "R0510", "c0520" }, "c0520 is closed (won't do): nothing moves a closed issue")
		refused(R, { "new", "raft", "chore", "gone", "c0520", "--project", "pickman" }, "c0520 is closed")
	end)

	it("dispatch.next stops a closed issue as finished", function()
		local facts: dispatch.Facts = {
			id = "c0510",
			folder = `{ISSUES}/c0510`,
			root = "pickman/.tracker",
			kind = "issue",
			where = "backlog",
			status = "closed",
			design = "draft",
			raft = "",
			ownClaim = false,
			localRaft = "",
			pr = nil,
			questions = false,
			openHuman = {},
			last = nil,
			uncovered = {},
			autoMerge = {},
			description = nil,
		}
		local action = dispatch.next(facts)
		t.expect(action.kind).toBe("stop")
		t.expect(action.code).toBe(dispatch.EXIT.done)
		t.expect(action.why).toBe("c0510 is closed (won't do): nothing to run")
	end)

	it("watch-net's open-defect test ignores a closed defect and keeps done/ and retired/ closed", function()
		local open = "---\nid: d0510\nslug: slow-tier-red\nstatus: new-amber-otter-lynx\n---\n"
		local closed =
			"---\nid: d0510\nslug: slow-tier-red\nstatus: closed-amber-otter-lynx\nwont_do: moot\n---\n"
		t.expect(watchcmd.isOpenDefect("z-nile/.tracker/issues/d0510/d0510.md", open)).toBe(true)
		t.expect(watchcmd.isOpenDefect("z-nile/.tracker/issues/d0510/d0510.md", closed)).toBe(false)
		t.expect(watchcmd.isOpenDefect("z-nile/.tracker/issues/done/d0510/d0510.md", open)).toBe(false)
		t.expect(watchcmd.isOpenDefect("z-nile/.tracker/rafts/retired/R0510/R0510.md", open)).toBe(false)
	end)

	it(
		"watch-net files a new slow-tier-red defect when the open one is closed, and says already open when it is not",
		function()
			local NEXT = "issue 1 fixture\nraft 1 fixture\n"
			local DEFECT = "z-nile/.tracker/issues/d0500/d0500.md"
			local w = trackerfix.new("c0278-watch", {
				["z-nile/next"] = NEXT,
				[DEFECT] = "---\nid: d0500\ntype: defect\ntitle: Slow tier red\nslug: slow-tier-red\nraft: \ndepends_on: []\nemergent: false\ndesign: draft\ncreated: 2026-11-15\nsize: 50\nstatus: closed-amber-otter-lynx\nwont_do: moot\n---\n\n# d0500\n",
			})
			local function commit(path: string, text: string, msg: string)
				fs.writeFile(`{w.main}/{path}`, text)
				fixture.git(w.main, { "add", "-A" })
				fixture.git(w.main, { "commit", "-qm", msg })
			end
			-- as tooling/watch-map: a stub gate failing on --slow (the copied gate keeps its mode), a pass marker, and a
			-- source commit after it
			commit(
				"z-nile/check.sh",
				'#!/usr/bin/env bash\ncase " $* " in\n*" --slow "*) echo "FAIL pickman/tests/unit/miss.spec.luau :: holds"; exit 1 ;;\nesac\nexit 0\n',
				"stub the suite"
			)
			commit("z-nile/watch-passed", fixture.git(w.main, { "rev-parse", "HEAD" }) .. "\n", "passed here")
			fs.writeDir(`{w.main}/pickman/src`)
			commit("pickman/src/More.luau", "return {}\n", "a source since the last pass")
			fixture.git(w.main, { "push", "-q", "origin", "HEAD:main" })
			local function documents(): number
				local listed = process.exec(
					"git",
					{ "grep", "-l", "slug: slow-tier-red", "origin/main", "--", "*.md" },
					{ cwd = w.main }
				)
				local n = 0
				for _ in string.gmatch(listed.stdout, "[^\n]+") do
					n += 1
				end
				return n
			end
			t.expect(documents()).toBe(1)
			local first = trackerfix.trOk(w, w.main, { "watch-net" })
			t.expect(has(first, "pushed a defect")).toBe(true)
			t.expect(documents()).toBe(2)
			-- the control: the defect it filed is open, so a second red slow tier files nothing
			fixture.git(w.main, { "pull", "-q", "--rebase", "origin", "main" })
			commit("pickman/src/Second.luau", "return {}\n", "another source")
			fixture.git(w.main, { "push", "-q", "origin", "HEAD:main" })
			local again = trackerfix.trOk(w, w.main, { "watch-net" })
			t.expect(has(again, "already open")).toBe(true)
			t.expect(has(again, "pushed a defect")).toBe(false)
			t.expect(documents()).toBe(2)
			fs.removeDir(w.base)
		end
	)

	it(
		"audit reports closed-mismatch, closed-not-backlog, closed-in-raft and closed-dependency, each with its fix, and nothing for a proper close",
		function()
			local clean = tr(W, { "audit" })
			t.expect(has(clean.stdout .. clean.stderr, "closed-")).toBe(false)
			local writes: { [string]: string } = {
				[`{ISSUES}/c0610/c0610.md`] = issue(
					"c0610",
					"new-amber-otter-lynx",
					"draft",
					nil,
					nil,
					"wont_do: stray\n"
				),
				[`{ISSUES}/c0620/c0620.md`] = issue("c0620", "closed-amber-otter-lynx", "draft"),
				[`{ISSUES}/done/c0630/c0630.md`] = issue(
					"c0630",
					"closed-amber-otter-lynx",
					"ready",
					nil,
					nil,
					"wont_do: x\n"
				),
				[`{ISSUES}/c0640/c0640.md`] = issue(
					"c0640",
					"closed-amber-otter-lynx",
					"ready",
					"R0510",
					nil,
					"wont_do: x\n"
				),
				[`{ISSUES}/c0650/c0650.md`] = issue("c0650", "new-amber-otter-lynx", "draft", nil, "c0510"),
				-- a closed issue under active/, a closed raft, a raft that holds a closed issue the issue
				-- does not know, an active dependent of a closed issue, and a closed status with an empty reason
				[`{ISSUES}/active/c0660/c0660.md`] = issue(
					"c0660",
					"closed-amber-otter-lynx",
					"ready",
					nil,
					nil,
					"wont_do: x\n"
				),
				[`{RAFTS}/R0520/R0520.md`] = raftDoc("R0520", "", "closed-amber-otter-lynx", "wont_do: x\n"),
				[`{ISSUES}/c0670/c0670.md`] = issue(
					"c0670",
					"closed-amber-otter-lynx",
					"ready",
					nil,
					nil,
					"wont_do: x\n"
				),
				[`{RAFTS}/R0540/R0540.md`] = raftDoc("R0540", "c0670", "prepared-brisk-heron-lynx"),
				[`{ISSUES}/active/c0680/c0680.md`] = issue(
					"c0680",
					"active-amber-otter-lynx",
					"ready",
					nil,
					"c0510"
				),
				[`{ISSUES}/c0690/c0690.md`] = issue(
					"c0690",
					"closed-amber-otter-lynx",
					"ready",
					nil,
					nil,
					"wont_do:\n"
				),
			}
			for path, text in writes do
				fs.writeDir(`{W}/{string.match(path, "^(.*)/[^/]+$")}`)
				fs.writeFile(`{W}/{path}`, text)
			end
			local r = tr(W, { "audit" })
			local out = r.stdout .. r.stderr
			t.expect(r.ok).toBe(false)
			local function line(code: string, id: string): string
				for _, l in lines(out) do
					if has(l, `error {code} `) and has(l, id) then
						return l
					end
				end
				error(`no {code} for {id} in:\n{out}`, 2)
			end
			t.expect(has(line("closed-mismatch", "c0610"), "only ./zn close writes them")).toBe(true)
			t.expect(has(line("closed-mismatch", "c0620"), "only ./zn close writes them")).toBe(true)
			t.expect(has(line("closed-not-backlog", "c0630"), "only a backlog issue is closed")).toBe(true)
			t.expect(has(line("closed-in-raft", "c0640"), "empty its raft: line")).toBe(true)
			t.expect(has(line("closed-dependency", "c0650"), "drop c0510 from c0650's depends_on")).toBe(true)
			t.expect(has(line("closed-not-backlog", "c0660"), "only a backlog issue is closed")).toBe(true)
			t.expect(has(line("closed-not-backlog", "R0520"), "only a backlog issue is closed")).toBe(true)
			t.expect(has(line("closed-in-raft", "c0670"), "drop it from R0540's issues:")).toBe(true)
			t.expect(has(line("closed-dependency", "c0680"), "drop c0510 from c0680's depends_on")).toBe(true)
			t.expect(has(line("closed-mismatch", "c0690"), "only ./zn close writes them")).toBe(true)
			-- the proper closes are named by nothing but c0650's dependency
			for _, l in lines(out) do
				if has(l, " closed-") and (has(l, "c0520")) then
					error(`a proper close is reported: {l}`)
				end
			end
			for path in writes do
				fs.removeDir(`{W}/{string.match(path, "^(.*)/[^/]+$")}`)
			end
		end
	)

	it(
		"the publish guard refuses a status-only edit of a closed document and a wont_do line without the closed status",
		function()
			local closedDoc = `{ISSUES}/c0510/c0510.md`
			local before = tip()
			local r1 = publish.commit(W, function(_paths, read)
				local text = read(closedDoc) :: string
				return {
					{
						path = closedDoc,
						content = (
							string.gsub(text, "\nstatus: [^\n]*\n", "\nstatus: new-brisk-amber-otter\n", 1)
						),
					},
				}
			end, "tracker: c0510 new")
			t.expect(r1.ok).toBe(false)
			t.expect(
				has(
					r1.reason,
					"c0510 is closed on origin/main: a closed issue's document is never published again"
				)
			).toBe(true)
			local liveDoc = `{ISSUES}/c0525/c0525.md`
			local r2 = publish.commit(W, function(_paths, read)
				local text = read(liveDoc) :: string
				return {
					{
						path = liveDoc,
						content = (string.gsub(text, "\n%-%-%-\n", "\nwont_do: sneaky\n---\n", 1)),
					},
				}
			end, "tracker: c0525 sneaky")
			t.expect(r2.ok).toBe(false)
			t.expect(has(r2.reason, "may only edit its status: line (or be one close: ./zn close)"))
				.toBe(true)
			t.expect(tip()).toBe(before)
		end
	)

	it("publish.commit refuses to move a closed issue's folder, as never published again", function()
		local from, to = `{ISSUES}/c0510`, `{ISSUES}/active/c0510`
		local before = tip()
		local r = publish.commit(W, function(_paths, read)
			local out: { publish.Change } = {}
			for _, rel in { "c0510.md", "check.sh" } do
				local text = read(`{from}/{rel}`) :: string
				if rel == "c0510.md" then
					text = (
						string.gsub(text, "\nstatus: [^\n]*\n", "\nstatus: active-brisk-amber-otter\n", 1)
					)
				end
				table.insert(out, { path = `{to}/{rel}`, from = `{from}/{rel}`, content = text })
			end
			return out
		end, "tracker: ready c0510")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.reason, "never published again")).toBe(true)
		t.expect(tip()).toBe(before)
	end)

	it("cleans up", function()
		fs.removeDir(f.base)
	end)
end)
