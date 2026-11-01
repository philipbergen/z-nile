--!strict
-- c0178 AC5: clone.isolated clones this checkout's repository from an image of it, one packed bare clone per run and
-- HEAD (@tests/lib/clone, @tests/lib/images), and still shares no object file with the real repository. Any other
-- source is cloned directly. Folders under .cache/c0178-clone.
local clone = require("@tests/lib/clone")
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local process = require("@lune/process")
local swept = require("@tests/lib/swept")
local t = require("@tests/lib/t")
local tally = require("@tests/lib/tally")

local HOME = fixture.physical(".") :: string
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph
local BASE = `{HOME}/.cache/c0178-clone`

local function out(cmd: string, args: { string }, cwd: string?): string
	local r = process.exec(cmd, args, { cwd = cwd })
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local TOP = out("git", { "rev-parse", "--show-toplevel" })
local HEAD = out("git", { "rev-parse", "HEAD" }, TOP)

local function fresh(name: string): string
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(BASE)
	return dir
end

local function repoImages(): { string }
	local list = {}
	for _, n in fs.readDir(images.dir()) do
		if string.match(n, "^repo%-%x+$") then
			table.insert(list, n)
		end
	end
	return list
end

return t.spec("c0178 clone.isolated from the repository's image", function(it)
	it("the repository's image is a packed bare clone of this HEAD, built once", function()
		local path = clone.image()
		local before = images.builds()
		t.expect(clone.image()).toBe(path)
		t.expect(images.builds()).toBe(before)
		t.expect(string.match(path, "^(.*)/repo%-%x+/repo%.git$")).toBe(images.dir())
		t.expect(out("git", { "rev-parse", "--is-bare-repository" }, path)).toBe("true")
		t.expect(out("git", { "rev-parse", "HEAD" }, path)).toBe(HEAD)
		-- packed: a handful of files in objects/, no loose object; and nothing points back at the real repository
		t.expect(out("find", { `{path}/objects`, "-path", "*/objects/??/*", "-type", "f" })).toBe("")
		t.expect(string.match(out("git", { "count-objects", "-v" }, path), "\npacks: (%d+)")).toBe("1")
		t.expect(out("git", { "remote" }, path)).toBe("")
	end)

	it(
		"clones this checkout's repository from the image: the same HEAD, no object file shared with either",
		function()
			local dest = fresh("top")
			clone.isolated(TOP, dest)
			t.expect(out("git", { "rev-parse", "HEAD" }, dest)).toBe(HEAD)
			t.expect(out("git", { "config", "remote.origin.url" }, dest)).toBe(TOP) -- the source asked for, not the image
			t.expect(out("git", { "ls-files", "zn" }, dest)).toBe("zn")
			t.expect(fs.isFile(`{dest}/z-nile/engine/main.luau`)).toBe(true)
			-- a plain local clone hardlinks; this one shares no object file with the image or with the real repository
			t.expect(out("find", { `{dest}/.git/objects`, "-type", "f", "-links", "+1" })).toBe("")
			t.expect(out("find", { `{clone.image()}/objects`, "-type", "f", "-links", "+1" })).toBe("")
			t.expect(table.find(swept.pending(), dest) ~= nil).toBe(true)
		end
	)

	it(
		"the image follows the repository's HEAD: a commit made after the first image is a second image",
		function()
			local subject = fresh("subject")
			if fs.isDir(`{BASE}/head-images`) then
				fs.removeDir(`{BASE}/head-images`)
			end
			fs.writeDir(subject)
			out("git", { "init", "-q", "-b", "main", subject }) -- raw: init to a named path
			local function commit(message: string)
				fixture.git(subject, {
					"-c",
					"user.name=c0178",
					"-c",
					"user.email=c0178@example.invalid",
					"commit",
					"-q",
					"--allow-empty",
					"-m",
					message,
				})
			end
			commit("one")
			local first = clone.imageOf(subject, { dir = `{BASE}/head-images` })
			local firstHead = out("git", { "rev-parse", "HEAD" }, subject)
			commit("two")
			local second = clone.imageOf(subject, { dir = `{BASE}/head-images` })
			local secondHead = out("git", { "rev-parse", "HEAD" }, subject)
			t.expect(second ~= first).toBe(true)
			t.expect(out("git", { "rev-parse", "HEAD" }, first)).toBe(firstHead)
			t.expect(out("git", { "rev-parse", "HEAD" }, second)).toBe(secondHead)
			t.expect(clone.imageOf(subject, { dir = `{BASE}/head-images` })).toBe(second)
			-- and this checkout's own image, however old, is where it was: nothing here removes an image
			t.expect(fs.isDir(clone.image())).toBe(true)
		end
	)

	it(
		"paths: only the listed paths are written to the working tree, the index is complete, and nothing is lost by a commit",
		function()
			local dest = fresh("sparse")
			local files0 = tally.read()
			clone.isolated(TOP, dest, { paths = { "zn", "z-nile/lib/", "pickman/.tracker/architecture.md" } })
			local files1 = tally.read()
			t.expect(fs.isFile(`{dest}/zn`)).toBe(true)
			t.expect(fs.isFile(`{dest}/z-nile/lib/ac.sh`)).toBe(true)
			t.expect(fs.isFile(`{dest}/pickman/.tracker/architecture.md`)).toBe(true)
			t.expect(fs.isFile(`{dest}/z-nile/engine/main.luau`)).toBe(false)
			t.expect(fs.isDir(`{dest}/pickman/src`)).toBe(false)
			-- the index still lists everything, so a commit keeps it
			t.expect(out("git", { "ls-files", "z-nile/engine/main.luau" }, dest))
				.toBe("z-nile/engine/main.luau")
			fixture.git(dest, { "add", "-A" })
			t.expect(fixture.git(dest, { "status", "--porcelain" })).toBe("")
			t.expect(fixture.git(dest, { "diff", "--cached", "--name-only" })).toBe("")
			-- far fewer files than a full checkout, and the helper counts the ones it wrote
			local written = #(string.split(out("find", { dest, "-type", "f" }), "\n"))
			t.expect(files1 - files0).toBe(written)
			t.expect(written < 300).toBe(true)
		end
	)

	it(
		"a clone with paths is made with --no-checkout, so the files outside them are never written",
		function()
			local dir = fresh("child")
			fs.writeDir(`{dir}/bin`)
			local real = out("which", { "git" })
			fs.writeFile(`{dir}/bin/git`, `#!/bin/sh\necho "git $*" >> "$SHIM_LOG"\nexec {real} "$@"\n`)
			out("chmod", { "+x", `{dir}/bin/git` })
			fs.writeFile(
				`{dir}/child.luau`,
				table.concat({
					"--!strict",
					`local clone = {REQ}("@tests/lib/clone")`,
					`local engine = {REQ}("@tests/lib/engine")`,
					'clone.isolated(engine.TOP, "' .. dir .. '/dest", { paths = { "zn" } })',
					"",
				}, "\n")
			)
			local r = process.exec("lune", { "run", `{dir}/child.luau` }, {
				cwd = HOME,
				env = { PATH = `{dir}/bin:{process.env.PATH or ""}`, SHIM_LOG = `{dir}/log` },
			})
			t.expect(r.ok).toBe(true)
			local cloned = false
			for line in string.gmatch(fs.readFile(`{dir}/log`), "[^\n]+") do
				if
					string.find(line, "git clone", 1, true) and string.find(line, "--no-checkout", 1, true)
				then
					cloned = true
				end
			end
			t.expect(cloned).toBe(true)
		end
	)

	it("tooling adds the overlay set: ./zn, scripts/, z-nile/ but its tracker state", function()
		local dest = fresh("tooling")
		clone.isolated(TOP, dest, { paths = { "pickman/.tracker/architecture.md" }, tooling = true })
		t.expect(fs.isFile(`{dest}/zn`)).toBe(true)
		t.expect(fs.isFile(`{dest}/scripts/tracker.sh`)).toBe(true)
		t.expect(fs.isFile(`{dest}/z-nile/engine/main.luau`)).toBe(true)
		t.expect(fs.isFile(`{dest}/z-nile/tests/run.luau`)).toBe(true)
		t.expect(fs.isFile(`{dest}/pickman/.tracker/architecture.md`)).toBe(true)
		t.expect(fs.isDir(`{dest}/z-nile/.tracker`)).toBe(false) -- the tracker state is not tooling
		t.expect(fs.isDir(`{dest}/pickman/src`)).toBe(false)
		t.expect(out("git", { "ls-files", "pickman/src/shared" }, dest) ~= "").toBe(true) -- still in the index
	end)

	it(
		"engine.empty leaves a sparse clone with the same staged tree as a full clone: no real item is left in the index",
		function()
			local full, sparse = fresh("empty-full"), `{BASE}/empty-sparse`
			if fs.isDir(sparse) then
				fs.removeDir(sparse)
			end
			clone.isolated(TOP, full)
			clone.isolated(TOP, sparse, { paths = { "pickman/.tracker/architecture.md" }, tooling = true })
			for _, dir in { full, sparse } do
				engine.empty(dir)
				fixture.git(dir, { "add", "-A", "--sparse" })
			end
			local fullList = fixture.git(full, { "ls-files" })
			t.expect(fixture.git(sparse, { "ls-files" })).toBe(fullList)
			t.expect(string.find(fullList, ".tracker/issues/c0", 1, true) == nil).toBe(true)
			t.expect(string.find(fixture.git(sparse, { "ls-files" }), ".tracker/issues/c0", 1, true) == nil)
				.toBe(true)
		end
	)

	it("a clone with no paths is whole, and its files are counted", function()
		local dest = fresh("whole")
		local files0 = tally.read()
		clone.isolated(TOP, dest)
		local files1 = tally.read()
		t.expect(fs.isFile(`{dest}/z-nile/engine/main.luau`)).toBe(true)
		t.expect(files1 - files0).toBe(#(string.split(out("find", { dest, "-type", "f" }), "\n")))
	end)

	it(
		"a clone's origin is the source it was asked for, so nothing a fixture pushes is aimed at the image",
		function()
			local dest = fresh("origin")
			clone.isolated(TOP, dest, { paths = { "zn" } })
			t.expect(out("git", { "config", "remote.origin.url" }, dest)).toBe(TOP)
			t.expect(fixture.exec(dest, "git", { "config", "--get-all", "remote.origin.pushurl" }).ok)
				.toBe(false)
			t.expect(string.find(out("git", { "remote", "-v" }, dest), "/images/", 1, true) == nil).toBe(true)
			-- and the image itself has no remote to push to
			t.expect(out("git", { "remote" }, clone.image())).toBe("")
		end
	)

	it("a source that is not this checkout is cloned directly, and gets no image", function()
		local source = fresh("source")
		fs.writeDir(source)
		out("git", { "init", "-q", "-b", "main", source }) -- raw: init to a named path
		fixture.git(source, {
			"-c",
			"user.name=c0178",
			"-c",
			"user.email=c0178@example.invalid",
			"commit",
			"-q",
			"--allow-empty",
			"-m",
			"one",
		})
		local before = repoImages()
		local dest = `{BASE}/direct`
		if fs.isDir(dest) then
			fs.removeDir(dest)
		end
		clone.isolated(source, dest)
		t.expect(out("git", { "config", "remote.origin.url" }, dest)).toBe(source)
		t.expect(repoImages()).toEqual(before)
	end)

	it("a clone that fails raises, naming the source", function()
		local ok, err = pcall(clone.isolated, `{BASE}/does-not-exist`, `{BASE}/never`)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "does-not-exist", 1, true) ~= nil).toBe(true)
	end)
end)
