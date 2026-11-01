--!strict
-- c0178 AC3: engine.copy takes this checkout's tooling from its image (@tests/lib/engine, @tests/lib/images): the same
-- tree engine.build lays out, in one cp, with no image for a tree that is not this checkout's own; and when the
-- destination already holds a repository the seed image's packed objects come along, so the caller's `git add -A`
-- writes next to no loose object. Folders of its own under .cache/c0178-tooling; the image is the real one in
-- images.dir() (the harness's own, built by the first spec that needs it).
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local images = require("@tests/lib/images")
local process = require("@lune/process")
local swept = require("@tests/lib/swept")
local t = require("@tests/lib/t")

local HOME = fixture.physical(".") :: string
local BASE = `{HOME}/.cache/c0178-tooling`
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end

local function fresh(name: string): string
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
	return dir
end

local function out(cmd: string, args: { string }, cwd: string?): string
	local r = process.exec(cmd, args, { cwd = cwd })
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function entries(dir: string): { string }
	local list = {}
	if fs.isDir(dir) then
		for _, n in fs.readDir(dir) do
			table.insert(list, n)
		end
	end
	table.sort(list)
	return list
end

local function toolingImages(): { string }
	local list = {}
	for _, n in entries(images.dir()) do
		if string.match(n, "^tooling%-%x+$") then
			table.insert(list, n)
		end
	end
	return list
end

-- The checkout's top, the way the older specs name it
local TOP = out("git", { "rev-parse", "--show-toplevel" })

-- Shims that log every call of git, cp, pwd and perl, then run the real one; `rejectClone` makes `cp -cR` fail the
-- way a cp without copy-on-write does. Returns the PATH a child runs with.
local function shims(dir: string, rejectClone: boolean): string
	fs.writeDir(dir)
	for _, cmd in { "git", "cp", "pwd", "perl", "mkdir", "mktemp" } do
		local real = out("which", { cmd })
		local body = `#!/bin/sh\necho "{cmd} $1 $2 $3" >> "$SHIM_LOG"\n`
		if rejectClone and cmd == "cp" then
			body ..= 'if [ "$1" = "-cR" ]; then echo "cp: unknown option -c" >&2; exit 64; fi\n'
		end
		write(`{dir}/{cmd}`, `{body}exec {real} "$@"\n`)
		out("chmod", { "+x", `{dir}/{cmd}` })
	end
	return `{dir}:{process.env.PATH or ""}`
end

-- Runs `engine.copy(".", dest)` in a child with the shims first on PATH; returns its stdout and the shim log's lines.
local function copyInChild(name: string, rejectClone: boolean): (string, { string })
	local dir = fresh(name)
	local path = shims(`{dir}/bin`, rejectClone)
	fs.writeDir(`{dir}/dest`)
	write(
		`{dir}/child.luau`,
		table.concat({
			"--!strict",
			`local engine = {REQ}("@tests/lib/engine")`,
			`local process = {REQ}("@lune/process")`,
			'engine.copy(".", process.args[#process.args])',
			`local tally = {REQ}("@tests/lib/tally")`,
			"local files, procs = tally.read()",
			'print("copied " .. files .. " " .. procs)',
			"",
		}, "\n")
	)
	local r = process.exec("lune", { "run", `{dir}/child.luau`, "--", `{dir}/dest` }, {
		cwd = HOME,
		env = { PATH = path, SHIM_LOG = `{dir}/log` },
	})
	if not r.ok then
		error(`child failed: {r.stderr}{r.stdout}`, 2)
	end
	local lines = {}
	if fs.isFile(`{dir}/log`) then
		for line in string.gmatch(fs.readFile(`{dir}/log`), "[^\n]+") do
			table.insert(lines, line)
		end
	end
	return r.stdout, lines
end

local function lines(text: string): { string }
	local list = {}
	for line in string.gmatch(text, "[^\n]+") do
		table.insert(list, line)
	end
	return list
end

local function count(rows: { string }, prefix: string): number
	local n = 0
	for _, l in rows do
		if string.sub(l, 1, #prefix) == prefix then
			n += 1
		end
	end
	return n
end

local function looseObjects(repo: string): number
	local n = 0
	for _, d in fs.readDir(`{repo}/.git/objects`) do
		if d ~= "pack" and d ~= "info" then
			n += #fs.readDir(`{repo}/.git/objects/{d}`)
		end
	end
	return n
end

return t.spec("c0178 engine.copy from the tooling image", function(it)
	it("lays out exactly what engine.build lays out: every file, every executable bit", function()
		local dir = fresh("parity")
		fs.writeDir(`{dir}/copy`)
		fs.writeDir(`{dir}/built`)
		engine.copy(TOP, `{dir}/copy`)
		engine.build(engine.TOP, `{dir}/built`)
		t.expect(out("diff", { "-r", `{dir}/copy`, `{dir}/built` })).toBe("")
		local function executables(root: string): string
			return out("find", { ".", "-type", "f", "-perm", "-u+x" }, root)
		end
		local want = executables(`{dir}/built`)
		t.expect(string.find(want, "./zn", 1, true) ~= nil).toBe(true) -- there are some, so the comparison means something
		t.expect(executables(`{dir}/copy`)).toBe(want)
		-- the registry the fixtures run under, not the checkout's
		t.expect(fs.readFile(`{dir}/copy/z-nile/projects.toml`)).toBe(engine.REGISTRY)
	end)

	it(
		"the tooling image is built once: engine.image() twice is one folder in images.dir() and builds nothing the second time",
		function()
			local first = engine.image()
			local before = images.builds()
			t.expect(engine.image()).toBe(first)
			t.expect(images.builds()).toBe(before)
			t.expect(string.sub(first, 1, #images.dir() + 1)).toBe(`{images.dir()}/`)
			t.expect(table.find(toolingImages(), string.match(first, "([^/]+)$") :: string) ~= nil).toBe(true)
			t.expect(fs.isFile(`{first}/zn`)).toBe(true)
		end
	)

	it("a tree that is not this checkout's own is copied as it is and gets no image", function()
		local dir = fresh("mutated")
		fs.writeDir(`{dir}/mutant`)
		engine.build(engine.TOP, `{dir}/mutant`)
		write(`{dir}/mutant/z-nile/README.md`, "a tree the spec changed\n")
		write(`{dir}/mutant/scripts/added-by-the-spec.sh`, "echo added\n")
		local before = toolingImages()
		fs.writeDir(`{dir}/copy`)
		engine.copy(`{dir}/mutant`, `{dir}/copy`)
		t.expect(fs.readFile(`{dir}/copy/z-nile/README.md`)).toBe("a tree the spec changed\n")
		t.expect(fs.isFile(`{dir}/copy/scripts/added-by-the-spec.sh`)).toBe(true)
		t.expect(toolingImages()).toEqual(before)
	end)

	it(
		"a destination that holds a repository gets the seed image's packs, and the next commit writes almost no loose object",
		function()
			local dir = fresh("packs")
			local repo = `{dir}/repo`
			out("git", { "init", "-q", "-b", "main", repo }) -- raw: init to a named path
			engine.copy(TOP, repo)
			local packs = 0
			for _, n in fs.readDir(`{repo}/.git/objects/pack`) do
				if string.match(n, "%.pack$") then
					packs += 1
				end
			end
			t.expect(packs >= 1).toBe(true)
			fixture.git(repo, { "add", "-A" })
			fixture.git(repo, {
				"-c",
				"user.name=c0178",
				"-c",
				"user.email=c0178@example.invalid",
				"commit",
				"-q",
				"-m",
				"seed",
			})
			-- the tooling is some 260 files; with its objects in the packs the commit writes the few that are new
			t.expect(looseObjects(repo) <= 25).toBe(true)
			t.expect(fixture.git(repo, { "ls-files", "zn" })).toBe("zn")
		end
	)

	it("the destination's fixture folder is registered to be swept when the spec file passes", function()
		local dir = fresh("registered")
		fs.writeDir(`{dir}/dest`)
		engine.copy(TOP, `{dir}/dest`)
		t.expect(table.find(swept.pending(), BASE) ~= nil).toBe(true) -- the spec file's own .cache/<name>
	end)

	it("a destination with no repository gets no repository", function()
		local dir = fresh("plain")
		fs.writeDir(`{dir}/dest`)
		engine.copy(TOP, `{dir}/dest`)
		t.expect(fs.isDir(`{dir}/dest/.git`)).toBe(false)
		t.expect(fs.isFile(`{dir}/dest/zn`)).toBe(true)
	end)

	it("a warm copy is one cp", function()
		engine.image() -- warm
		local stdout, log = copyInChild("warm", false)
		t.expect(string.match(stdout, "^copied") ~= nil).toBe(true)
		t.expect(count(log, "cp ")).toBe(1)
		t.expect(count(log, "cp -cR")).toBe(1)
		-- the helper counts what it starts and what it writes: the shim log and the files on disk
		local files, procs = string.match(stdout, "^copied (%d+) (%d+)")
		t.expect(tonumber(procs)).toBe(#log)
		t.expect(tonumber(files)).toBe(#lines(out("find", { `{BASE}/warm/dest`, "-type", "f" })))
	end)

	it("falls back to a plain cp where copy-on-write is refused", function()
		local stdout, log = copyInChild("fallback", true)
		t.expect(string.match(stdout, "^copied") ~= nil).toBe(true)
		t.expect(count(log, "cp -cR")).toBe(1)
		t.expect(count(log, "cp -R")).toBe(1)
		t.expect(fs.isFile(`{BASE}/fallback/dest/zn`)).toBe(true)
		t.expect(fs.isFile(`{BASE}/fallback/dest/z-nile/engine/main.luau`)).toBe(true)
	end)
end)
