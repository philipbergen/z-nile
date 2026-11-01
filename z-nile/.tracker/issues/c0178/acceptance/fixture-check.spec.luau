--!strict
-- c0178 AC7: fixture.git checks that its directory is a fixture repository once per call, right before it runs git (it
-- used to check twice: once itself, once again inside fixture.exec), and the check still refuses what is not a fixture
-- repository, before anything runs. Fixture under .cache/c0178-check.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local HOME = fixture.physical(".") :: string
local BASE = `{HOME}/.cache/c0178-check`
local REQ = "require" -- built by concatenation: a literal require in a string would join the graph

local function out(cmd: string, args: { string }): string
	local r = process.exec(cmd, args)
	if not r.ok then
		error(`{cmd} {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
	return (string.gsub(r.stdout, "%s+$", ""))
end

local function write(path: string, text: string)
	local parent = string.match(path, "^(.*)/[^/]+$")
	if parent then
		fs.writeDir(parent)
	end
	fs.writeFile(path, text)
end

-- The git calls a child makes while it runs `body` (Luau statements), one "git <1> <2> <3>" line each.
local function gitCalls(name: string, target: string, body: string, shimmed: { string }?): { string }
	local dir = `{BASE}/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/bin`)
	local commands: { string } = shimmed or { "git" }
	for _, cmd in commands do
		write(
			`{dir}/bin/{cmd}`,
			`#!/bin/sh\necho "{cmd} $1 $2 $3" >> "$SHIM_LOG"\nexec {out("which", { cmd })} "$@"\n`
		)
		out("chmod", { "+x", `{dir}/bin/{cmd}` })
	end
	write(
		`{dir}/child.luau`,
		table.concat({
			"--!strict",
			`local fixture = {REQ}("@tests/lib/fixture")`,
			`local target = "{target}"`,
			body,
			"",
		}, "\n")
	)
	local r = process.exec("lune", { "run", `{dir}/child.luau` }, {
		cwd = HOME,
		env = { PATH = `{dir}/bin:{process.env.PATH or ""}`, SHIM_LOG = `{dir}/log` },
	})
	if not r.ok then
		error(`child failed: {r.stderr}{r.stdout}`, 2)
	end
	local list = {}
	if fs.isFile(`{dir}/log`) then
		for line in string.gmatch(fs.readFile(`{dir}/log`), "[^\n]+") do
			table.insert(list, (string.gsub(line, "%s+$", "")))
		end
	end
	return list
end

local function count(list: { string }, line: string): number
	local n = 0
	for _, l in list do
		if l == line then
			n += 1
		end
	end
	return n
end

local f: trackerfix.Fixture

return t.spec("c0178 fixture.git checks once", function(it)
	it("sets up a fixture", function()
		f = trackerfix.new("c0178-check")
	end)

	it("fixture.git in a worktree fixture checks its directory once and then runs the command", function()
		local calls = gitCalls("git", f.main, 'fixture.git(target, { "rev-parse", "HEAD" })')
		t.expect(count(calls, "git rev-parse --show-toplevel")).toBe(1)
		t.expect(count(calls, "git rev-parse HEAD")).toBe(1)
		t.expect(#calls).toBe(2)
	end)

	it("fixture.exec checks once too", function()
		local calls = gitCalls("exec", f.main, 'fixture.exec(target, "git", { "rev-parse", "HEAD" })')
		t.expect(count(calls, "git rev-parse --show-toplevel")).toBe(1)
		t.expect(#calls).toBe(2)
	end)

	it("a bare fixture is checked once as well: its own folder is the git directory", function()
		local calls = gitCalls("bare", f.origin, 'fixture.git(target, { "rev-parse", "HEAD" })')
		t.expect(count(calls, "git rev-parse --show-toplevel")).toBe(1)
		t.expect(count(calls, "git rev-parse --is-bare-repository --absolute-git-dir")).toBe(1)
		t.expect(count(calls, "git rev-parse HEAD")).toBe(1)
	end)

	it(
		"the home's physical path is read once per process; the directory's own path and repository are read on every call",
		function()
			local calls = gitCalls(
				"home",
				f.main,
				'fixture.git(target, { "rev-parse", "HEAD" })\nfixture.git(target, { "rev-parse", "HEAD" })\nfixture.git(target, { "rev-parse", "HEAD" })',
				{ "git", "pwd" }
			)
			-- three calls: the directory's pwd -P each time, the home's once; the repository read each time
			t.expect(count(calls, "pwd -P")).toBe(4)
			t.expect(count(calls, "git rev-parse --show-toplevel")).toBe(3)
			t.expect(count(calls, "git rev-parse HEAD")).toBe(3)
		end
	)

	it("still refuses a folder that is not a fixture repository, before any git runs", function()
		-- the home itself: inside this checkout, outside every fixture
		local calls = gitCalls(
			"refuse",
			HOME,
			table.concat({
				'local ok, err = pcall(fixture.git, target, { "rev-parse", "HEAD" })',
				'assert(not ok and string.find(tostring(err), "not a fixture repository", 1, true), tostring(err))',
				'local ok2, err2 = pcall(fixture.exec, target, "git", { "rev-parse", "HEAD" })',
				'assert(not ok2 and string.find(tostring(err2), "not a fixture repository", 1, true), tostring(err2))',
			}, "\n")
		)
		t.expect(count(calls, "git rev-parse HEAD")).toBe(0) -- the command never ran
	end)

	it("still refuses a folder under .cache that is not a repository of its own", function()
		fs.writeDir(`{BASE}/plain-folder`)
		local calls = gitCalls(
			"plain",
			`{BASE}/plain-folder`,
			table.concat({
				'local ok, err = pcall(fixture.git, target, { "status" })',
				'assert(not ok and string.find(tostring(err), "not a fixture repository", 1, true), tostring(err))',
			}, "\n")
		)
		t.expect(count(calls, "git status")).toBe(0)
	end)
end)
