--!strict
-- f0424 follow-up: the shared spec runner builds the live daemon (<root>/.cache/bin/znlive) before a z-nile run when it is
-- missing or older than the Go sources, by the same z-nile/lib/gobuild.sh, so `./zn finish` and a by-name run need not
-- go through the gate. Its decision is pure (livebuild.wanted); the build runs in a fixture checkout under .cache.
local fence = require("@tests/lib/fence")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local livebuild = require("@tests/lib/livebuild")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local hasGo = process.exec("sh", { "-c", "command -v go" }).ok

-- A fixture checkout with the Go sources and the build scripts copied from this one; nothing else of the repository.
local function checkout(name: string): string
	local home = fixture.physical(".") :: string
	local dir = `{home}/.cache/{name}`
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(`{dir}/z-nile/lib`)
	for _, f in { "gobuild.sh", "goenv.sh" } do
		fs.writeFile(`{dir}/z-nile/lib/{f}`, fs.readFile(`{root}/z-nile/lib/{f}`))
	end
	local cp = process.exec("cp", { "-R", `{root}/z-nile/go`, `{dir}/z-nile/go` })
	if not cp.ok then
		error(`cp of z-nile/go failed: {cp.stderr}`, 2)
	end
	return dir
end

local function read(path: string): string
	return fs.readFile(path)
end

return t.spec("f0424 the spec runner builds the live daemon", function(it)
	it("wanted: only an unguarded z-nile run with Go sources", function()
		t.expect(livebuild.wanted("z-nile", true, false)).toBe(true)
		t.expect(livebuild.wanted("pickman", true, false)).toBe(false)
		t.expect(livebuild.wanted("z-nile", false, false)).toBe(false)
		-- a guarded process (a worker, a nested run) is inside the jail and never builds
		t.expect(livebuild.wanted("z-nile", true, true)).toBe(false)
	end)

	it("guardedRun: a spec process is inside a guarded run", function()
		t.expect(fence.guardedRun()).toBe(true)
	end)

	it(
		"builds when the binary is missing, leaves a current one alone, rebuilds after a source changes",
		function()
			if not hasGo then
				return -- with no Go there is nothing to build: the next case covers it
			end
			local dir = checkout("f0424-runner-build")
			local bin = `{dir}/.cache/bin/znlive`
			t.expect(fs.isFile(bin)).toBe(false)
			t.expect(livebuild.ensure(dir)).toBe("built")
			t.expect(fs.isFile(bin)).toBe(true)
			local id = read(`{bin}.id`)
			t.expect(livebuild.ensure(dir)).toBe("current")
			t.expect(read(`{bin}.id`)).toBe(id)
			-- a changed Go source makes the binary stale
			fs.writeFile(`{dir}/z-nile/go/cmd/znlive/zz_stale.go`, "package main\n\n// stale marker\n")
			t.expect(livebuild.ensure(dir)).toBe("built")
			t.expect(read(`{bin}.id`) ~= id).toBe(true)
		end
	)

	it("with no Go, or no sources, nothing is built and nothing fails", function()
		local dir = checkout("f0424-runner-nogo")
		local shadow = `{dir}/shadow`
		fs.writeDir(shadow)
		if process.exec("sh", { "-c", "PATH=/usr/bin:/bin command -v go" }).ok then
			return -- a system Go in /usr/bin cannot be hidden here
		end
		local env = { PATH = `{shadow}:/usr/bin:/bin:/usr/sbin:/sbin` }
		t.expect(livebuild.ensure(dir, env)).toBe("unavailable")
		t.expect(fs.isFile(`{dir}/.cache/bin/znlive`)).toBe(false)
		-- with Go but no sources
		fs.removeDir(`{dir}/z-nile/go`)
		t.expect(livebuild.ensure(dir)).toBe("unavailable")
	end)
end)
