--!strict
-- c0189 AC3: `./zn hooks` installs the repository hook, and `./zn hooks --check` reports what is wrong with it, in
-- fixture checkouts (a clone of a fixture origin, each with its own repository under this home's .cache). The command
-- runs in the main checkout of a repository that has an origin, where other writers refuse; the hook it writes is
-- origin/main's copy of the source (the tree's own when there is no origin/main), executable, in the git directory
-- every worktree shares, never a checkout's unmerged edit; it never overwrites a hook it does not know.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local FX = "fixture@example.invalid"
local SOURCE = "z-nile/lib/repo-hooks/reference-transaction"

local f: trackerfix.Fixture
local main = ""
local dest = ""

local function zn(dir: string, args: { string }): fixture.Result
	local argv = { "zn" }
	for _, a in args do
		table.insert(argv, a)
	end
	return fixture.exec(dir, "bash", argv)
end

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function git(dir: string, args: { string }): fixture.Result
	return fixture.exec(dir, "git", args)
end

-- Runs `fn` with the installed hook moved aside: the fixture made its commits under its fixture identity, and the
-- installed hook would refuse a fetch (or an update-ref) that brings them in.
local function withoutHook(fn: () -> ())
	local aside = `{dest}.off`
	local hadHook = fs.isFile(dest)
	if hadHook then
		t.expect(fixture.exec(main, "mv", { dest, aside }).ok).toBe(true)
	end
	fn()
	if hadHook then
		t.expect(fixture.exec(main, "mv", { aside, dest }).ok).toBe(true)
	end
end

local function fetchOrigin()
	withoutHook(function()
		t.expect(git(main, { "fetch", "-q", "origin" }).ok).toBe(true)
	end)
end

-- origin/main's copy of the hook source, byte for byte, as ./zn hooks installs it (nothing trimmed)
local function originText(): string
	return fixture.exec(main, "git", { "cat-file", "blob", `origin/main:{SOURCE}` }).stdout
end

-- the hook files left in the hooks folder besides the hook itself (a temporary file of an install)
local function leftovers(): { string }
	local out = {}
	local hooksDir = string.gsub(dest, "[^/]+$", "")
	for _, name in fs.readDir(hooksDir) do
		if string.sub(name, 1, 24) == ".reference-transaction.n" then
			table.insert(out, name)
		end
	end
	return out
end

local function isExecutable(path: string): boolean
	return fixture.exec(main, "test", { "-x", path }).ok
end

local function isLink(path: string): boolean
	return fixture.exec(main, "test", { "-L", path }).ok
end

return t.spec("c0189 ./zn hooks and ./zn hooks --check", function(it)
	it("sets up a fixture checkout with an origin, the tooling and no hook", function()
		f = trackerfix.new("c0189-hooks")
		main = f.main
		dest = fixture.git(main, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
			.. "/hooks/reference-transaction"
		t.expect(fs.isFile(`{main}/{SOURCE}`)).toBe(true)
		t.expect(fs.isFile(dest)).toBe(false)
	end)

	it("--check reports a missing hook, names the path and the fix, and writes nothing", function()
		local r = zn(main, { "hooks", "--check" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, `hooks: {dest} is missing; run ./zn hooks`)).toBe(true)
		t.expect(fs.isFile(dest)).toBe(false)
	end)

	it("installs the tree's file, executable, in the main checkout of a repository with an origin", function()
		t.expect(git(main, { "remote" }).stdout).toBe("origin\n")
		local r = zn(main, { "hooks" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, `hooks: installed {dest}`)).toBe(true)
		t.expect(fs.readFile(dest)).toBe(originText())
		t.expect(isExecutable(dest)).toBe(true)
		local check = zn(main, { "hooks", "--check" })
		t.expect(check.ok).toBe(true)
		t.expect(has(check.stdout, "hooks: reference-transaction installed in")).toBe(true)
	end)

	it("the installed hook refuses a commit under a fixture identity in that repository", function()
		local before = git(main, { "rev-parse", "HEAD" }).stdout
		local r = fixture.exec(main, "git", { "commit", "-q", "--allow-empty", "-m", "x" }, {
			env = {
				GIT_AUTHOR_NAME = "a",
				GIT_AUTHOR_EMAIL = FX,
				GIT_COMMITTER_NAME = "a",
				GIT_COMMITTER_EMAIL = FX,
			},
		})
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "cannot become a ref of this repository")).toBe(true)
		t.expect(git(main, { "rev-parse", "HEAD" }).stdout).toBe(before)
	end)

	it("a second run says it is up to date and leaves the file as it is", function()
		local text = fs.readFile(dest)
		local r = zn(main, { "hooks" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, `hooks: {dest} is up to date`)).toBe(true)
		t.expect(fs.readFile(dest)).toBe(text)
	end)

	it(
		"a stale copy of our own file is reported by --check, left alone by it, and replaced by the command",
		function()
			fs.writeFile(dest, fs.readFile(dest) .. "# an older line\n")
			local stale = fs.readFile(dest)
			local check = zn(main, { "hooks", "--check" })
			t.expect(check.ok).toBe(false)
			t.expect(has(check.stderr, `hooks: {dest} differs from origin/main's {SOURCE}; run ./zn hooks`))
				.toBe(true)
			t.expect(fs.readFile(dest)).toBe(stale)
			local r = zn(main, { "hooks" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, `hooks: updated {dest}`)).toBe(true)
			t.expect(fs.readFile(dest)).toBe(originText())
			t.expect(isExecutable(dest)).toBe(true)
		end
	)

	it("a copy that is not executable is reported, and the command makes it executable", function()
		t.expect(fixture.exec(main, "chmod", { "644", dest }).ok).toBe(true)
		local check = zn(main, { "hooks", "--check" })
		t.expect(check.ok).toBe(false)
		t.expect(has(check.stderr, "is not executable, so git skips it; run ./zn hooks")).toBe(true)
		t.expect(zn(main, { "hooks" }).ok).toBe(true)
		t.expect(isExecutable(dest)).toBe(true)
	end)

	it("a hook it does not recognise is reported, never overwritten, and its bytes stay", function()
		local mine = "#!/bin/sh\necho mine\n"
		fs.writeFile(dest, mine)
		t.expect(fixture.exec(main, "chmod", { "755", dest }).ok).toBe(true)
		local check = zn(main, { "hooks", "--check" })
		t.expect(check.ok).toBe(false)
		t.expect(has(check.stderr, "does not recognise")).toBe(true)
		local r = zn(main, { "hooks" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "it never overwrites one")).toBe(true)
		t.expect(fs.readFile(dest)).toBe(mine)
	end)

	it("a symbolic link at the place is refused, and the link and its target stay", function()
		local target = `{main}/.git/hooks/elsewhere`
		fs.writeFile(target, "#!/bin/sh\nexit 0\n")
		t.expect(fixture.exec(main, "rm", { "-f", dest }).ok).toBe(true)
		t.expect(fixture.exec(main, "ln", { "-s", target, dest }).ok).toBe(true)
		local r = zn(main, { "hooks" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "is a symbolic link")).toBe(true)
		t.expect(isLink(dest)).toBe(true)
		t.expect(fs.readFile(target)).toBe("#!/bin/sh\nexit 0\n")
		t.expect(zn(main, { "hooks", "--check" }).ok).toBe(false)
		t.expect(fixture.exec(main, "rm", { "-f", dest, target }).ok).toBe(true)
	end)

	it(
		"a git configuration that moves the hooks folder is refused by both modes, naming the setting's scope",
		function()
			t.expect(zn(main, { "hooks" }).ok).toBe(true)
			t.expect(git(main, { "config", "core.hooksPath", "/elsewhere" }).ok).toBe(true)
			local check = zn(main, { "hooks", "--check" })
			t.expect(check.ok).toBe(false)
			t.expect(has(check.stderr, "git reads hooks from /elsewhere (local configuration)")).toBe(true)
			local r = zn(main, { "hooks" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, "git reads hooks from /elsewhere (local configuration)")).toBe(true)
			t.expect(git(main, { "config", "--unset", "core.hooksPath" }).ok).toBe(true)
			t.expect(zn(main, { "hooks", "--check" }).ok).toBe(true)
		end
	)

	it(
		"run in a linked worktree it installs into the git directory every worktree shares, and never its unmerged edit",
		function()
			t.expect(fixture.exec(main, "rm", { "-f", dest }).ok).toBe(true)
			local linked = `{f.base}/linked`
			t.expect(git(main, { "worktree", "add", "-q", "-b", "c0189-linked", linked }).ok).toBe(true)
			-- this worktree's tree carries an edit that is not on origin/main: another checkout must not be turned red by it
			local edited = fs.readFile(`{linked}/{SOURCE}`) .. "# an unmerged edit\n"
			fs.writeFile(`{linked}/{SOURCE}`, edited)
			local r = zn(linked, { "hooks" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, `hooks: installed {dest}`)).toBe(true)
			t.expect(fs.readFile(dest)).toBe(originText())
			t.expect(fs.readFile(dest) == edited).toBe(false)
			-- and both checkouts agree that it is installed
			t.expect(zn(main, { "hooks", "--check" }).ok).toBe(true)
			t.expect(zn(linked, { "hooks", "--check" }).ok).toBe(true)
			t.expect(fs.readFile(`{linked}/{SOURCE}`)).toBe(edited)
		end
	)

	it("an install that cannot write fails, naming the path, and leaves no partial file", function()
		t.expect(fixture.exec(main, "rm", { "-f", dest }).ok).toBe(true)
		local hooksDir = string.gsub(dest, "/[^/]+$", "")
		t.expect(fixture.exec(main, "chmod", { "555", hooksDir }).ok).toBe(true)
		local ok, err = pcall(function()
			local r = zn(main, { "hooks" })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.stderr, `hooks: could not install {dest}`)).toBe(true)
			t.expect(fs.isFile(dest)).toBe(false)
		end)
		t.expect(fixture.exec(main, "chmod", { "755", hooksDir }).ok).toBe(true)
		if not ok then
			error(err, 0)
		end
		t.expect(zn(main, { "hooks" }).ok).toBe(true)
	end)

	it(
		"when origin/main moves to a new hook text, --check accepts the older reviewed copy with a note until ./zn hooks updates it",
		function()
			local newer = originText() .. "# a newer line\n"
			local before = fs.readFile(dest)
			trackerfix.elsewhere(f, { [SOURCE] = newer }, "a newer hook")
			fetchOrigin()
			t.expect(originText()).toBe(newer)
			-- the installed text is one origin/main has held: no gate goes red for a legitimate fetch
			local check = zn(main, { "hooks", "--check" })
			t.expect(check.ok).toBe(true)
			t.expect(
				has(
					check.stdout,
					`is an older reviewed copy of origin/main's {SOURCE}; run ./zn hooks to update`
				)
			).toBe(true)
			t.expect(fs.readFile(dest)).toBe(before)
			t.expect(zn(main, { "hooks" }).ok).toBe(true)
			t.expect(fs.readFile(dest)).toBe(newer)
			local after = zn(main, { "hooks", "--check" })
			t.expect(after.ok).toBe(true)
			t.expect(has(after.stdout, "installed in")).toBe(true)
			-- a text origin/main never held is still red, even when it begins like a held one
			fs.writeFile(dest, newer .. "# never reviewed\n")
			t.expect(zn(main, { "hooks", "--check" }).ok).toBe(false)
			t.expect(zn(main, { "hooks" }).ok).toBe(true)
			t.expect(fs.readFile(dest)).toBe(newer)
		end
	)

	it(
		"only a text main itself held counts as reviewed: a merged branch's work-in-progress text is red",
		function()
			local base = originText()
			local wip = base .. "# wip weak\n"
			local final = base .. "# final\n"
			t.expect(git(f.other, { "pull", "-q", "origin", "main" }).ok).toBe(true)
			t.expect(git(f.other, { "switch", "-q", "-c", "wip-branch" }).ok).toBe(true)
			fs.writeFile(`{f.other}/{SOURCE}`, wip)
			t.expect(git(f.other, { "commit", "-q", "-am", "wip" }).ok).toBe(true)
			fs.writeFile(`{f.other}/{SOURCE}`, final)
			t.expect(git(f.other, { "commit", "-q", "-am", "final" }).ok).toBe(true)
			t.expect(git(f.other, { "switch", "-q", "main" }).ok).toBe(true)
			t.expect(git(f.other, { "merge", "-q", "--no-ff", "-m", "Merge pull request", "wip-branch" }).ok)
				.toBe(true)
			t.expect(git(f.other, { "push", "-q", "origin", "HEAD:main" }).ok).toBe(true)
			fetchOrigin()
			t.expect(originText()).toBe(final)
			-- the intermediate text, installed by hand, is not a text main held: red
			fs.writeFile(dest, wip)
			t.expect(fixture.exec(main, "chmod", { "755", dest }).ok).toBe(true)
			local check = zn(main, { "hooks", "--check" })
			t.expect(check.ok).toBe(false)
			t.expect(has(check.stderr, "differs from origin/main's")).toBe(true)
			-- the final text is what main held: after one more change on main it is an older reviewed copy
			t.expect(zn(main, { "hooks" }).ok).toBe(true)
			t.expect(fs.readFile(dest)).toBe(final)
			trackerfix.elsewhere(f, { [SOURCE] = final .. "# later\n" }, "later hook")
			fetchOrigin()
			local older = zn(main, { "hooks", "--check" })
			t.expect(older.ok).toBe(true)
			t.expect(has(older.stdout, "is an older reviewed copy")).toBe(true)
			t.expect(zn(main, { "hooks" }).ok).toBe(true)
		end
	)

	it(
		"the installed bytes are the blob's, whatever the source's last line looks like, so a later change is still an older reviewed copy",
		function()
			for _, ending in { "", "\n\n" } do
				local text = string.gsub(originText(), "\n+$", "") .. ending
				trackerfix.elsewhere(f, { [SOURCE] = text }, "an ending")
				fetchOrigin()
				t.expect(originText()).toBe(text)
				t.expect(zn(main, { "hooks" }).ok).toBe(true)
				t.expect(fs.readFile(dest)).toBe(text)
				t.expect(zn(main, { "hooks", "--check" }).ok).toBe(true)
				trackerfix.elsewhere(f, { [SOURCE] = text .. "\n# one more\n" }, "one more")
				fetchOrigin()
				local check = zn(main, { "hooks", "--check" })
				t.expect(check.ok).toBe(true)
				t.expect(has(check.stdout, "is an older reviewed copy")).toBe(true)
				t.expect(zn(main, { "hooks" }).ok).toBe(true)
			end
		end
	)

	it(
		"when origin/main has no hook file there is nothing to install or check, and nothing changes",
		function()
			t.expect(git(f.other, { "pull", "-q", "origin", "main" }).ok).toBe(true)
			t.expect(git(f.other, { "rm", "-q", SOURCE }).ok).toBe(true)
			t.expect(git(f.other, { "commit", "-q", "-m", "no hook" }).ok).toBe(true)
			t.expect(git(f.other, { "push", "-q", "origin", "HEAD:main" }).ok).toBe(true)
			fetchOrigin()
			local before = fs.readFile(dest)
			local check = zn(main, { "hooks", "--check" })
			t.expect(check.ok).toBe(true)
			t.expect(
				has(
					check.stdout,
					`hooks: origin/main has no {SOURCE} yet, so there is nothing to install or check`
				)
			).toBe(true)
			local r = zn(main, { "hooks" })
			t.expect(r.ok).toBe(true)
			t.expect(has(r.stdout, "nothing to install or check")).toBe(true)
			t.expect(fs.readFile(dest)).toBe(before)
			-- the tree still has its copy: it is not installed in place of origin/main's
			t.expect(fs.isFile(`{main}/{SOURCE}`)).toBe(true)
		end
	)

	it(
		"a read of origin/main that fails, or an origin whose main was never fetched, is an error in both modes",
		function()
			local before = fs.readFile(dest)
			local mainRef = fixture.git(main, { "rev-parse", "refs/remotes/origin/main" })
			local blob = fixture.git(main, { "hash-object", "-w", `{main}/zn` })
			local function bothFail(expected: string)
				for _, args in { { "hooks", "--check" }, { "hooks" } } do
					local r = zn(main, args)
					t.expect(`{args[#args]} {r.ok}`).toBe(`{args[#args]} false`)
					t.expect(has(r.stderr, expected)).toBe(true)
				end
				t.expect(fs.readFile(dest)).toBe(before)
				t.expect(#leftovers()).toBe(0)
			end
			local ok, err = pcall(function()
				t.expect(git(main, { "update-ref", "refs/remotes/origin/main", blob }).ok).toBe(true)
				bothFail("hooks: cannot read origin/main:")
				withoutHook(function()
					t.expect(git(main, { "update-ref", "refs/remotes/origin/main", mainRef }).ok).toBe(true)
				end)
				t.expect(git(main, { "update-ref", "-d", "refs/remotes/origin/main" }).ok).toBe(true)
				bothFail("hooks: origin has no main fetched; run git fetch origin main")
			end)
			fetchOrigin()
			if not ok then
				error(err, 0)
			end
			t.expect(fixture.git(main, { "rev-parse", "refs/remotes/origin/main" })).toBe(mainRef)
		end
	)

	it("a clone with no origin/main uses its own tree's copy, and refuses a tree that has none", function()
		local solo = `{f.base}/solo`
		local cloned = process.exec("git", { "clone", "-q", f.origin, solo })
		t.expect(cloned.ok).toBe(true)
		t.expect(git(solo, { "remote", "remove", "origin" }).ok).toBe(true)
		-- the clone checked out main as it is now: origin/main (the hook-less commit) is gone with the remote
		t.expect(fs.isFile(`{solo}/{SOURCE}`)).toBe(false)
		local without = zn(solo, { "hooks" })
		t.expect(without.ok).toBe(false)
		t.expect(has(without.stderr, `this tree's {SOURCE} is missing or has no`)).toBe(true)
		-- its tree gets the hook back (the commit before the removal), and the clone installs that copy
		t.expect(git(solo, { "checkout", "-q", "HEAD~1", "--", SOURCE }).ok).toBe(true)
		local soloDest = fixture.git(solo, { "rev-parse", "--path-format=absolute", "--git-common-dir" })
			.. "/hooks/reference-transaction"
		local r = zn(solo, { "hooks" })
		t.expect(r.ok).toBe(true)
		t.expect(has(r.stdout, `hooks: installed {soloDest}`)).toBe(true)
		t.expect(fs.readFile(soloDest)).toBe(fs.readFile(`{solo}/{SOURCE}`))
		t.expect(zn(solo, { "hooks", "--check" }).ok).toBe(true)
	end)

	it("an unknown option or an argument is a usage error", function()
		local r = zn(main, { "hooks", "--bogus" })
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "usage: ./zn hooks [--check] (unknown option --bogus)")).toBe(true)
		local p = zn(main, { "hooks", "extra" })
		t.expect(p.ok).toBe(false)
		t.expect(has(p.stderr, "usage: ./zn hooks [--check]")).toBe(true)
	end)

	it("cleans up", function()
		if fs.isDir(f.base) then
			fs.removeDir(f.base)
		end
		t.expect(fs.isDir(f.base)).toBe(false)
	end)
end)
