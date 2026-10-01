--!strict
-- c0060 AC1-AC2: the changed-file list behind `scripts/affected`, now in scripts/lib/changed, is
-- specced against a throwaway git repository: every kind of change appears, a moved file appears at
-- both paths (no rename detection), changes made on the base after the fork do not, and the default
-- base is origin/main when it exists, main otherwise.
local changed = require("@scripts/lib/changed")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0060-changed`
local repo = `{base}/repo`
local origin = `{base}/origin.git`

local function git(args: { string }, cwd: string?): string
	local r = process.exec("git", args, { cwd = cwd or repo })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}{r.stdout}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(`{repo}/{parent}`)
	end
	fs.writeFile(`{repo}/{path}`, text)
end

local function commit(message: string)
	git({ "add", "-A" })
	git({ "commit", "-qm", message })
end

local function sorted(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)
	return copy
end

local function listed(list: { string }, path: string): boolean
	return table.find(list, path) ~= nil
end

return t.spec("c0060 changed files", function(it)
	it("sets up a repository with main and a feature branch forked from it", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		fs.writeDir(repo)
		git({ "init", "-q", "-b", "main" })
		git({ "config", "user.name", "e2e" })
		git({ "config", "user.email", "e2e@example.invalid" })
		git({ "config", "gc.auto", "0" })
		write("src/a.luau", "return 'a'\n")
		write("src/b.luau", "return 'b'\n")
		write("tests/x.luau", "return 'x'\n")
		commit("base")
		git({ "checkout", "-q", "-b", "feature" })
	end)

	it("lists committed, staged, unstaged and untracked changes, and nothing else", function()
		write("src/b.luau", "return 'b2'\n")
		commit("edit b on the branch")
		write("tests/x.luau", "return 'x2'\n") -- unstaged
		write("src/staged.luau", "return 's'\n")
		git({ "add", "src/staged.luau" }) -- staged
		write("src/new.luau", "return 'n'\n") -- untracked
		local files = changed.files("main", repo)
		t.expect(sorted(files)).toEqual({ "src/b.luau", "src/new.luau", "src/staged.luau", "tests/x.luau" })
	end)

	it("lists a moved file at both its old and its new path", function()
		git({ "add", "-A" })
		git({ "commit", "-qm", "wip" })
		fs.writeDir(`{repo}/place`)
		git({ "mv", "src/a.luau", "place/a.luau" })
		commit("move a out of src")
		local files = changed.files("main", repo)
		t.expect(listed(files, "src/a.luau")).toBe(true)
		t.expect(listed(files, "place/a.luau")).toBe(true)
	end)

	it("does not list what changed on the base after the branch forked", function()
		git({ "checkout", "-q", "main" })
		write("src/only-main.luau", "return 'm'\n")
		commit("main moves on")
		git({ "checkout", "-q", "feature" })
		local files = changed.files("main", repo)
		t.expect(listed(files, "src/only-main.luau")).toBe(false)
		t.expect(listed(files, "src/b.luau")).toBe(true)
	end)

	it("defaults to main when there is no origin", function()
		t.expect(sorted(changed.files(nil, repo))).toEqual(sorted(changed.files("main", repo)))
	end)

	it("defaults to origin/main when it exists, even if the local main is elsewhere", function()
		-- origin/main = the commit the feature branch was cut from, plus one more on main; then the
		-- local main is moved back, so the two bases give different merge-bases for the feature branch
		git({ "checkout", "-q", "main" })
		write("src/f1.luau", "return 'f1'\n")
		commit("f1")
		local f1 = git({ "rev-parse", "HEAD" })
		git({ "checkout", "-q", "-B", "feature2" })
		write("src/feature2.luau", "return 'f2'\n")
		commit("feature2 work")
		git({ "init", "-q", "--bare", origin }, base)
		git({ "remote", "add", "origin", origin })
		git({ "push", "-q", "origin", `{f1}:refs/heads/main` })
		git({ "fetch", "-q", "origin" })
		git({ "branch", "-f", "main", "main~1" }) -- the local main goes back to before f1
		t.expect(listed(changed.files("main", repo), "src/f1.luau")).toBe(true)
		local byDefault = changed.files(nil, repo)
		t.expect(listed(byDefault, "src/f1.luau")).toBe(false)
		t.expect(listed(byDefault, "src/feature2.luau")).toBe(true)
	end)

	it("with no usable base, still lists uncommitted and untracked files", function()
		git({ "checkout", "-q", "feature" })
		write("src/late.luau", "return 'late'\n") -- untracked
		write("src/b.luau", "return 'b3'\n") -- unstaged
		local files = changed.files("no-such-ref", repo)
		t.expect(listed(files, "src/late.luau")).toBe(true)
		t.expect(listed(files, "src/b.luau")).toBe(true)
		t.expect(listed(files, "place/a.luau")).toBe(false) -- committed changes need a base to compare with
		git({ "checkout", "-q", "--", "src/b.luau" })
		fs.removeFile(`{repo}/src/late.luau`)
	end)

	it("scripts/affected takes its changed files from the module", function()
		local text = fs.readFile(`{root}/scripts/affected.luau`)
		local call = "req" .. "uire" -- keeps literal require text out of this file (graph scanner)
		t.expect(string.find(text, call .. '("./lib/changed")', 1, true) ~= nil).toBe(true)
		t.expect((string.find(text, "local function changedFiles", 1, true))).toBe(nil)
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
