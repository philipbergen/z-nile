--!strict
-- c0115 AC12's freeze (decided with the user, 2026-10-24, G14: "Yes, same rule"; scoped and its own raft added
-- 2026-10-25, design review 013 F2, F5): while origin/main still holds the old testing skill's file (c0115's mark) and
-- every path `./zn busy` is given lies in the skill folders, busy ignores c0115's own prep and implementation, the
-- items listed as stacked on them (prep-c0116 … impl-c0121), any branch whose history holds c0115's move commit (the
-- one on origin/impl-c0115 whose subject starts "c0115: move the skills"), the prototypes approved by exact name
-- (proto-c0116, proto-c0117, proto-c0118, proto-c0121) and an active raft that lists c0115. Each is named on stderr,
-- uncounted. A branch sharing only commits main took as a squash (013 F1), a look-alike name, a local branch named
-- origin/…, an unrelated branch, another raft and a detached worktree still block; nothing is exempt without paths,
-- for a path outside the skill folders, or once the move lands. The same rule as c0120's freeze
-- (z-nile/engine/main.luau's FREEZES). Fixture under .cache/c0115-busy (tests/lib/trackerfix).
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local REGISTRY = 'retired = ["tracker"]\n\n[[project]]\nname = "pickman"\nroot = "pickman/.tracker"\n\n'
	.. '[[project]]\nname = "z-nile"\nroot = "z-nile/.tracker"\n'
local PATHS = { ".claude/skills", "z-nile/skills", "pickman/skills" }
local MARK = ".claude/skills/testing/SKILL.md"
local f: trackerfix.Fixture

local function busy(args: { string }): fixture.Result
	local argv = { "busy" }
	for _, a in args do
		table.insert(argv, a)
	end
	return trackerfix.tr(f, f.main, argv)
end
local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function branchOff(name: string, from: string, file: string, subject: string?)
	fixture.git(f.main, { "checkout", "-q", "-b", name, from })
	local parent = string.match(file, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{f.main}/{parent}`)
	end
	fs.writeFile(`{f.main}/{file}`, `{name}\n`)
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-qm", subject or name })
	fixture.git(f.main, { "checkout", "-q", "main" })
end
-- a raft document on origin/main listing `issues`, as `./zn ready` would have pushed it
local function raftDoc(id: string, issues: string): string
	return `---\nid: {id}\ntype: chore\ntitle: demo\nslug: demo\nissues: [{issues}]\ncreated: 2026-01-01\nstatus: active-a-b-c\n---\n\n# {id}\n`
end
local function push(name: string)
	fixture.git(f.main, { "push", "-q", "origin", name })
	fixture.git(f.main, { "fetch", "-q", "origin" })
end
local function drop(names: { string }, remote: { string })
	local args = { "branch", "-q", "-D" }
	for _, n in names do
		table.insert(args, n)
	end
	fixture.git(f.main, args)
	for _, n in remote do
		fixture.git(f.main, { "push", "-q", "origin", "--delete", n })
	end
	fixture.git(f.main, { "fetch", "-q", "--prune", "origin" })
end

return t.spec("c0115 the freeze ignores the items stacked on c0115", function(it)
	it("sets up a fixture whose origin/main still holds the old testing skill", function()
		f = trackerfix.new("c0115-busy", {
			["z-nile/projects.toml"] = REGISTRY,
			[MARK] = "---\nname: testing\n---\n",
			["pickman/.tracker/issues/active/.gitkeep"] = "",
			["pickman/.tracker/rafts/active/.gitkeep"] = "",
		})
		t.expect(busy(PATHS).stdout).toBe("")
	end)

	it(
		"c0115's prep and implementation, the stacked items, branches holding its move and the approved prototypes are ignored",
		function()
			branchOff("prep-c0115", "main", "z-nile/.tracker/issues/NOTES-c0115.md")
			push("prep-c0115")
			-- main takes the prep's change as a squash: the prep's own commit never reaches main (013 F1)
			trackerfix.elsewhere(
				f,
				{ ["z-nile/.tracker/issues/NOTES-c0115.md"] = "prep-c0115\n" },
				"prep (#1)"
			)
			-- the base the implementation is built on, landed on main as a squash too: its commits sit under the move,
			-- as c0120's do on the real branch (014 F1)
			branchOff("base-work", "main", "pickman/.tracker/issues/active/base.md")
			push("base-work")
			trackerfix.elsewhere(
				f,
				{ ["pickman/.tracker/issues/active/base.md"] = "base-work\n" },
				"base (#2)"
			)
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			branchOff(
				"impl-c0115",
				"origin/base-work",
				"z-nile/skills/zz-x/SKILL.md",
				"c0115: move the skills (renames only)"
			)
			fixture.git(f.main, { "checkout", "-q", "impl-c0115" })
			fs.writeFile(`{f.main}/z-nile/skills/zz-x/after.md`, "after\n")
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "c0115: the edits" })
			fixture.git(f.main, { "checkout", "-q", "main" })
			push("impl-c0115")
			branchOff("on-the-impl", "origin/impl-c0115", "z-nile/skills/zz-y/SKILL.md")
			-- cut at the move commit, below the branch's tip: it holds the move (a pin on the tip would miss it)
			branchOff("at-the-move", "origin/impl-c0115~1", "z-nile/skills/zz-m/SKILL.md")
			-- cut from the squashed base under the move: it doesn't hold the move, so it blocks
			branchOff("below-the-move", "origin/base-work", "z-nile/skills/zz-u/SKILL.md")
			branchOff("on-the-prep", "origin/prep-c0115", "pickman/skills/pickman-x/SKILL.md")
			branchOff("impl-c0121", "main", "z-nile/skills/zz-z/SKILL.md")
			branchOff("proto-c0121", "main", ".claude/skills/zz-w")
			-- look-alikes and an unrelated branch block
			branchOff("impl-c0115-x", "main", "z-nile/skills/zz-a/SKILL.md")
			branchOff("proto-c0121-copy", "main", "z-nile/skills/zz-b/SKILL.md")
			branchOff("origin/proto-c0121", "main", "z-nile/skills/zz-c/SKILL.md")
			branchOff("unrelated-work", "main", "pickman/skills/pickman-y/SKILL.md")
			local r = busy(PATHS)
			for _, n in { "on-the-impl", "branch impl-c0121 ", "branch proto-c0121 " } do
				t.expect(has(r.stdout, n)).toBe(false)
			end
			t.expect(has(r.stdout, "branch impl-c0115 ")).toBe(false)
			t.expect(has(r.stdout, "branch origin/impl-c0115 ")).toBe(false)
			t.expect(has(r.stdout, "branch prep-c0115 ")).toBe(false)
			t.expect(has(r.stderr, "ignored for c0115's freeze: on-the-impl (holds its move)")).toBe(true)
			t.expect(has(r.stderr, "ignored for c0115's freeze: at-the-move (holds its move)")).toBe(true)
			t.expect(has(r.stdout, "branch below-the-move changes")).toBe(true)
			-- built on the prep, whose commit main took as a squash: no history rule for c0115, so it blocks
			t.expect(has(r.stdout, "branch on-the-prep changes")).toBe(true)
			t.expect(has(r.stderr, "on-the-prep")).toBe(false)
			t.expect(has(r.stderr, "ignored for c0115's freeze: impl-c0121 (stacked on its prep)")).toBe(true)
			t.expect(has(r.stderr, "ignored for c0115's freeze: proto-c0121 (approved by name)")).toBe(true)
			t.expect(has(r.stdout, "branch impl-c0115-x changes")).toBe(true)
			t.expect(has(r.stdout, "branch proto-c0121-copy changes")).toBe(true)
			t.expect(has(r.stdout, "branch origin/proto-c0121 changes")).toBe(true)
			t.expect(has(r.stdout, "branch unrelated-work changes")).toBe(true)
			t.expect(r.code).toBe(1)
			drop({
				"on-the-prep",
				"below-the-move",
				"impl-c0115-x",
				"proto-c0121-copy",
				"origin/proto-c0121",
				"unrelated-work",
			}, {})
			local clear = busy(PATHS)
			t.expect(clear.stdout).toBe("")
			t.expect(clear.code).toBe(0)
		end
	)

	it("a worktree on an ignored branch is ignored; a detached one is listed", function()
		local on = `{f.base}/wt-approved`
		local detached = `{f.base}/wt-detached`
		fixture.git(f.main, { "worktree", "add", "-q", on, "proto-c0121" })
		fixture.git(f.main, { "worktree", "add", "-q", "--detach", detached, "main" })
		fs.writeDir(`{on}/z-nile/skills`)
		fs.writeFile(`{on}/z-nile/skills/dirty.md`, "x\n")
		fs.writeDir(`{detached}/z-nile/skills`)
		fs.writeFile(`{detached}/z-nile/skills/dirty.md`, "x\n")
		local r = busy(PATHS)
		local onP, detP = fixture.physical(on) :: string, fixture.physical(detached) :: string
		t.expect(has(r.stdout, `worktree {onP} has`)).toBe(false)
		t.expect(
			has(r.stderr, `ignored for c0115's freeze: worktree {onP} on proto-c0121 (approved by name)`)
		)
			.toBe(true)
		t.expect(has(r.stdout, `worktree {detP} has uncommitted changes`)).toBe(true)
		fixture.git(f.main, { "worktree", "remove", "--force", on })
		fixture.git(f.main, { "worktree", "remove", "--force", detached })
	end)

	it("an active raft that lists c0115 is ignored; any other raft is listed", function()
		trackerfix.elsewhere(f, {
			["z-nile/.tracker/rafts/active/R0099/R0099.md"] = raftDoc("R0099", "c0115, c0113"),
			["z-nile/.tracker/rafts/active/R0098/R0098.md"] = raftDoc("R0098", "c0116"),
		}, "tracker: ready R0098 and R0099")
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local r = busy(PATHS)
		t.expect(has(r.stderr, "ignored for c0115's freeze: raft R0099 (c0115's own)")).toBe(true)
		t.expect(has(r.stdout, "raft R0099")).toBe(false)
		t.expect(has(r.stdout, "raft R0098 is active")).toBe(true)
		t.expect(r.code).toBe(1)
		local all = busy({})
		t.expect(has(all.stdout, "raft R0099 is active")).toBe(true)
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(
			f.other,
			{ "rm", "-q", "-r", "z-nile/.tracker/rafts/active/R0098", "z-nile/.tracker/rafts/active/R0099" }
		)
		fixture.git(f.other, { "commit", "-qm", "tracker: stop R0098 and R0099" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		t.expect(busy(PATHS).stdout).toBe("")
	end)

	it("the freeze covers only the skill folders: any other path given turns it off", function()
		branchOff("prep-c0116", "main", "z-nile/skills/zz-q/SKILL.md")
		local inside = busy({ "z-nile/skills/" })
		t.expect(inside.stdout).toBe("")
		t.expect(has(inside.stderr, "ignored for c0115's freeze: prep-c0116 (stacked on its prep)"))
			.toBe(true)
		local mixed = busy({ "z-nile/skills", "z-nile/.tracker" })
		t.expect(mixed.code).toBe(1)
		t.expect(has(mixed.stdout, "branch prep-c0116 changes")).toBe(true)
		t.expect(has(mixed.stdout, "branch impl-c0121 changes")).toBe(true)
		t.expect(has(mixed.stderr, "ignored")).toBe(false)
		-- whole segments only: a sibling that shares the prefix is outside; "./" is the same path; ".." is never inside
		branchOff("prep-c0117", "main", "z-nile/skillsX/a.md")
		local sibling = busy({ "z-nile/skillsX" })
		t.expect(has(sibling.stdout, "branch prep-c0117 changes")).toBe(true)
		t.expect(has(sibling.stderr, "ignored")).toBe(false)
		local dotted = busy({ "./z-nile/skills" })
		t.expect(has(dotted.stdout, "prep-c0116")).toBe(false)
		t.expect(has(dotted.stderr, "ignored for c0115's freeze: prep-c0116 (stacked on its prep)"))
			.toBe(true)
		local up = busy({ "z-nile/skills/../skillsX" })
		t.expect(has(up.stderr, "ignored")).toBe(false)
		drop({ "prep-c0116", "prep-c0117" }, {})
	end)

	it(
		"the move commit is read by subject, from the branch's own commits, and only when it is the one",
		function()
			local before = (
				string.gsub(fixture.git(f.main, { "rev-parse", "origin/impl-c0115" }), "%s+$", "")
			)
			-- a main commit whose body carries the subject's words, and one whose subject does, merged into the
			-- implementation: neither is the branch's own, so the move commit stays the one pinned
			trackerfix.elsewhere(
				f,
				{ ["pickman/.tracker/issues/active/body.md"] = "x\n" },
				"chore\n\nc0115: move the skills, later"
			)
			trackerfix.elsewhere(
				f,
				{ ["pickman/.tracker/issues/active/subject.md"] = "x\n" },
				"c0115: move the skills (a look-alike on main)"
			)
			fixture.git(f.main, { "pull", "-q", "origin", "main" })
			fixture.git(f.main, { "checkout", "-q", "impl-c0115" })
			fixture.git(f.main, { "merge", "-q", "--no-edit", "main" })
			-- a subject that only contains the words is not the move commit (015 F1, mutant T)
			fs.writeFile(`{f.main}/z-nile/skills/zz-x/note.md`, "note\n")
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "note: not c0115: move the skills" })
			fixture.git(f.main, { "checkout", "-q", "main" })
			push("impl-c0115")
			branchOff("rogue-on-main", "main", "z-nile/skills/zz-r/SKILL.md")
			local r = busy(PATHS)
			t.expect(has(r.stdout, "branch rogue-on-main changes")).toBe(true)
			t.expect(has(r.stderr, "ignored for c0115's freeze: on-the-impl (holds its move)")).toBe(true)
			-- a local branch named origin/impl-c0115 with its own "move" is not the remote branch (015 F1, mutant U)
			branchOff(
				"origin/impl-c0115",
				"main",
				"z-nile/skills/zz-f/SKILL.md",
				"c0115: move the skills (a local look-alike)"
			)
			branchOff("on-the-fake", "refs/heads/origin/impl-c0115", "z-nile/skills/zz-g/SKILL.md")
			local fake = busy(PATHS)
			t.expect(has(fake.stdout, "branch on-the-fake changes")).toBe(true)
			t.expect(has(fake.stderr, "ignored for c0115's freeze: on-the-impl (holds its move)")).toBe(true)
			drop({ "on-the-fake", "origin/impl-c0115" }, {})
			-- a second commit with the subject: no single move commit, so nothing is pinned
			fixture.git(f.main, { "checkout", "-q", "impl-c0115" })
			fs.writeFile(`{f.main}/z-nile/skills/zz-x/again.md`, "again\n")
			fixture.git(f.main, { "add", "-A" })
			fixture.git(f.main, { "commit", "-qm", "c0115: move the skills, again" })
			fixture.git(f.main, { "checkout", "-q", "main" })
			push("impl-c0115")
			-- cut above both: it holds either one, yet neither is the move commit
			branchOff("above-both", "origin/impl-c0115", "z-nile/skills/zz-v/SKILL.md")
			local two = busy(PATHS)
			t.expect(has(two.stdout, "branch on-the-impl changes")).toBe(true)
			t.expect(has(two.stdout, "branch above-both changes")).toBe(true)
			t.expect(has(two.stderr, "holds its move")).toBe(false)
			-- back as before
			fixture.git(f.main, { "branch", "-q", "-f", "impl-c0115", before })
			fixture.git(f.main, { "push", "-q", "-f", "origin", "impl-c0115" })
			fixture.git(f.main, { "fetch", "-q", "origin" })
			drop({ "rogue-on-main", "above-both" }, {})
		end
	)

	it("nothing is exempt without paths, nor once origin/main loses the mark", function()
		local all = busy({})
		t.expect(has(all.stderr, "ignored")).toBe(false)
		fixture.git(f.other, { "pull", "-q", "origin", "main" })
		fixture.git(f.other, { "rm", "-q", MARK })
		fixture.git(f.other, { "commit", "-qm", "the move" })
		fixture.git(f.other, { "push", "-q", "origin", "HEAD:main" })
		fixture.git(f.main, { "pull", "-q", "origin", "main" })
		local landed = busy(PATHS)
		t.expect(landed.code).toBe(1)
		t.expect(has(landed.stdout, "branch on-the-impl changes")).toBe(true)
		t.expect(has(landed.stdout, "branch proto-c0121 changes")).toBe(true)
		t.expect(has(landed.stderr, "ignored")).toBe(false)
		drop({
			"prep-c0115",
			"impl-c0115",
			"on-the-impl",
			"at-the-move",
			"base-work",
			"impl-c0121",
			"proto-c0121",
		}, {
			"base-work",
			"prep-c0115",
			"impl-c0115",
		})
	end)
end)
