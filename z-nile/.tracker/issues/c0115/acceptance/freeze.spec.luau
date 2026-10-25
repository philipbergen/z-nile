--!strict
-- c0115 AC12's freeze (decided with the user, 2026-10-24, G14: "Yes, same rule"): while origin/main still
-- holds the old testing skill's file (c0115's mark), `./zn busy` with paths ignores c0115's own prep and
-- implementation, the items listed as stacked on them (prep-c0116 … impl-c0121), any branch whose history holds a
-- commit of origin/prep-c0115 or origin/impl-c0115 that main doesn't, and the prototypes approved by exact name
-- (proto-c0116, proto-c0117, proto-c0118, proto-c0121). Each is named on stderr, uncounted. A look-alike name, a local
-- branch named origin/…, an unrelated branch and a detached worktree still block, and nothing is exempt without paths
-- or once the move lands. The same rule as c0120's freeze (z-nile/engine/main.luau's FREEZES). Fixture under
-- .cache/c0115-busy (tests/lib/trackerfix).
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
local function branchOff(name: string, from: string, file: string)
	fixture.git(f.main, { "checkout", "-q", "-b", name, from })
	local parent = string.match(file, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{f.main}/{parent}`)
	end
	fs.writeFile(`{f.main}/{file}`, `{name}\n`)
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-qm", name })
	fixture.git(f.main, { "checkout", "-q", "main" })
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
		"c0115's prep and implementation, the stacked items, branches built on them and the approved prototypes are ignored",
		function()
			branchOff("prep-c0115", "main", "z-nile/.tracker/issues/NOTES-c0115.md")
			push("prep-c0115")
			branchOff("impl-c0115", "main", "z-nile/skills/zz-x/SKILL.md")
			push("impl-c0115")
			branchOff("on-the-impl", "origin/impl-c0115", "z-nile/skills/zz-y/SKILL.md")
			branchOff("on-the-prep", "origin/prep-c0115", "pickman/skills/pickman-x/SKILL.md")
			branchOff("impl-c0121", "main", "z-nile/skills/zz-z/SKILL.md")
			branchOff("proto-c0121", "main", ".claude/skills/zz-w")
			-- look-alikes and an unrelated branch block
			branchOff("impl-c0115-x", "main", "z-nile/skills/zz-a/SKILL.md")
			branchOff("proto-c0121-copy", "main", "z-nile/skills/zz-b/SKILL.md")
			branchOff("origin/proto-c0121", "main", "z-nile/skills/zz-c/SKILL.md")
			branchOff("unrelated-work", "main", "pickman/skills/pickman-y/SKILL.md")
			local r = busy(PATHS)
			for _, n in { "on-the-impl", "on-the-prep", "branch impl-c0121 ", "branch proto-c0121 " } do
				t.expect(has(r.stdout, n)).toBe(false)
			end
			t.expect(has(r.stdout, "branch impl-c0115 ")).toBe(false)
			t.expect(has(r.stdout, "branch origin/impl-c0115 ")).toBe(false)
			t.expect(has(r.stdout, "branch prep-c0115 ")).toBe(false)
			t.expect(has(r.stderr, "ignored for c0115's freeze: on-the-impl (stacked on its implementation)"))
				.toBe(true)
			t.expect(has(r.stderr, "ignored for c0115's freeze: on-the-prep (stacked on its prep)"))
				.toBe(true)
			t.expect(has(r.stderr, "ignored for c0115's freeze: impl-c0121 (stacked on its prep)")).toBe(true)
			t.expect(has(r.stderr, "ignored for c0115's freeze: proto-c0121 (approved by name)")).toBe(true)
			t.expect(has(r.stdout, "branch impl-c0115-x changes")).toBe(true)
			t.expect(has(r.stdout, "branch proto-c0121-copy changes")).toBe(true)
			t.expect(has(r.stdout, "branch origin/proto-c0121 changes")).toBe(true)
			t.expect(has(r.stdout, "branch unrelated-work changes")).toBe(true)
			t.expect(r.code).toBe(1)
			drop({
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
		drop({ "prep-c0115", "impl-c0115", "on-the-impl", "on-the-prep", "impl-c0121", "proto-c0121" }, {
			"prep-c0115",
			"impl-c0115",
		})
	end)
end)
