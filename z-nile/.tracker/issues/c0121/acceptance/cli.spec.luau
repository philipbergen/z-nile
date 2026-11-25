--!strict
-- c0121 AC4: `./zn board --serve [--port N]` in a fixture checkout: it refuses a bad port, `-O` and `--out`, a linked
-- worktree (it runs in the main checkout), and a taken port, each naming why and serving nothing; it is guarded
-- (refused where git's root is not the checkout) though `board` alone only reads; the usage names it. No case starts a
-- server that keeps running: the in-process server is AC2's. Fixture under .cache/c0121-cli; git through fixture.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local net = require("@lune/net")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end
local top = trim(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout)
-- fixtures live under the home's .cache, where the spec runs (the jail refuses the checkout top's when they differ)
local here = trim(process.exec("pwd", { "-P" }).stdout)
local REPO = `{here}/.cache/c0121-cli`
local WT = `{here}/.cache/c0121-cli-wt`

local function zn(dir: string, args: { string }): any
	local r = fixture.exec(dir, "./zn", args)
	return { ok = r.ok, out = r.stdout .. r.stderr }
end
-- A port this spec holds: a command that wrongly gets past its refusal fails on the taken port, never serves and hangs.
local function occupy(): (number, any)
	for _ = 1, 30 do
		local port = math.random(30000, 60000)
		local ok, h = pcall(net.serve :: any, port, {
			address = "http://127.0.0.1",
			handleRequest = function()
				return { status = 200, body = "someone else" }
			end,
		})
		if ok then
			return port, h
		end
	end
	error("no free port in 30 tries")
end
local function has(s: string, needle: string): boolean
	return string.find(s, needle, 1, true) ~= nil
end

return t.spec("c0121 board --serve command", function(it)
	it("sets up a fixture checkout with the engine and a linked worktree", function()
		for _, d in { REPO, WT } do
			if fs.isDir(d) then
				fs.removeDir(d)
			end
		end
		fs.writeDir(REPO)
		process.exec("git", { "init", "-q", "-b", "main", REPO }) -- raw: init to a named path
		fixture.git(REPO, { "config", "user.name", "c0121-cli" })
		fixture.git(REPO, { "config", "user.email", "c0121-cli@example.invalid" })
		engine.copy(top, REPO)
		engine.roots(REPO)
		fixture.git(REPO, { "add", "-A" })
		fixture.git(REPO, { "commit", "-q", "-m", "engine" })
		fixture.git(REPO, { "worktree", "add", "-q", "-b", "elsewhere", WT })
		fs.writeDir(`{REPO}/nogit`)
		engine.copy(top, `{REPO}/nogit`)
	end)

	it("refuses a port outside 1024 to 65535, or not a number", function()
		-- values that cannot bind come first: a regression fails on them before it could reach one that binds
		for _, p in { "70000", "abc", "1.5", "1023" } do
			local r = zn(REPO, { "board", "--serve", "--port", p })
			t.expect(r.ok).toBe(false)
			t.expect(has(r.out, `--port {p} is not a port from 1024 to 65535`)).toBe(true)
		end
	end)

	it("refuses -O, --out and --open with --serve, since it writes no file", function()
		for _, extra in { { "-O" }, { "--out", "x.html" }, { "--open" } } do
			local port, h = occupy()
			local args = { "board", "--serve", "--port", tostring(port) }
			for _, a in extra do
				table.insert(args, a)
			end
			local r = zn(REPO, args)
			h:stop()
			t.expect(r.ok).toBe(false)
			t.expect(has(r.out, "usage: board --serve [--port N]")).toBe(true)
		end
		t.expect(fs.isFile(`{REPO}/x.html`)).toBe(false)
	end)

	it("runs only in the main checkout", function()
		local port, h = occupy()
		local r = zn(WT, { "board", "--serve", "--port", tostring(port) })
		h:stop()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.out, "board --serve runs in the main checkout")).toBe(true)
	end)

	it("fails clearly when the port is taken, and serves nothing", function()
		local port, handle = occupy()
		local r = zn(REPO, { "board", "--serve", "--port", tostring(port) })
		handle:stop()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.out, `port {port} is taken`)).toBe(true)
		t.expect(has(r.out, "--port")).toBe(true)
	end)

	it("is guarded where git's root is not the checkout, while board alone only reads", function()
		-- run from the fixture's top (the helper checks it); ./zn changes into its own folder, nogit/, which git's root is not
		local function nogit(args: { string }): any
			local r = fixture.exec(REPO, "nogit/zn", args)
			return { ok = r.ok, out = r.stdout .. r.stderr }
		end
		local port, h = occupy()
		local served = nogit({ "board", "--serve", "--port", tostring(port) })
		h:stop()
		t.expect(served.ok).toBe(false)
		t.expect(has(served.out, "refusing to run: git's repository root is")).toBe(true)
		local page = nogit({ "board", "-O", "--out", ".cache/page.html" })
		t.expect(has(page.out, "refusing to run")).toBe(false)
	end)

	it("the usage line names board --serve", function()
		local r = zn(REPO, {})
		t.expect(has(r.out, "board --serve [--port N]")).toBe(true)
		-- board's own continuation line still follows board's line
		local after = string.match(r.out, "board %[%-%-out PATH%] %[%-O%][^\n]*\n([^\n]*)") or ""
		t.expect(has(after, "open it in the browser")).toBe(true)
	end)

	it("cleans up", function()
		fixture.git(REPO, { "worktree", "remove", "--force", WT })
		fs.removeDir(REPO)
	end)
end)
