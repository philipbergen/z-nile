--!strict
-- c0189 AC3: `./zn hooks` makes no temporary name of its own. It replaces the hook through z-nile/lib/replace-file.pl,
-- which gained one option, `--mode=<octal>`: the file is complete and has that mode before the rename puts it in place
-- (a hook git must find executable), and the default stays 0644. c0194 (temporary trees live in .cache/.tmp/) scans the
-- tooling for `mktemp`, so the install may not use it. Every path is a stand-in under this home's .cache; nothing real
-- is linked to or written.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local process = require("@lune/process")
local sh = require("@znile/lib/sh")
local t = require("@tests/lib/t")

type Result = { ok: boolean, code: number, stdout: string, stderr: string }

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local home = fixture.physical(".") or error("the working directory is not readable")
local base = `{home}/.cache/c0189-replace-mode`
local REPLACE = `{root}/z-nile/lib/replace-file.pl`

local function has(text: string, part: string): boolean
	return string.find(text, part, 1, true) ~= nil
end

-- the file's permission bits as four octal digits
local function modeOf(path: string): string
	local r = process.exec("perl", { "-e", 'printf "%04o", (stat $ARGV[0])[2] & 07777', path })
	return r.stdout
end

-- replace-file.pl with `umask 077` (a restrictive caller): the mode must not depend on it. It runs with the case's
-- folder as its working directory: an option the helper fails to consume would be read as a path, and must land in the
-- fixture (where `strays` sees it), never in the checkout.
local function replace(dir: string, args: { string }, stdin: string): Result
	local argv = { "-c", 'umask 077; exec perl "$@"', "sh", REPLACE }
	for _, a in args do
		table.insert(argv, a)
	end
	return process.exec("sh", argv, { cwd = dir, stdio = { stdin = stdin } })
end

local function leftovers(dir: string): { string }
	local out: { string } = {}
	for _, name in fs.readDir(dir) do
		if has(name, ".pickman-tmp.") then
			table.insert(out, name)
		end
	end
	return out
end

-- entries named like the option: a helper that did not consume `--mode=...` made a file called that
local function strays(dir: string): { string }
	local out: { string } = {}
	for _, name in fs.readDir(dir) do
		if string.sub(name, 1, 6) == "--mode" then
			table.insert(out, name)
		end
	end
	return out
end

local function fresh(name: string): string
	local dir = `{base}/{name}`
	process.exec("rm", { "-rf", dir })
	fs.writeDir(dir)
	return dir
end

return t.spec("c0189 replace-file.pl --mode", function(it)
	it("the default mode is still 0644, whatever the umask", function()
		local dir = fresh("default")
		local r = replace(dir, { `{dir}/f` }, "one")
		t.expect(r.ok).toBe(true)
		t.expect(modeOf(`{dir}/f`)).toBe("0644")
		t.expect(fs.readFile(`{dir}/f`)).toBe("one")
	end)

	it("--mode=0755 leaves a complete, executable file in place, whatever the umask", function()
		local dir = fresh("exec")
		fs.writeFile(`{dir}/f`, "old")
		process.exec("chmod", { "600", `{dir}/f` })
		local r = replace(dir, { "--mode=0755", `{dir}/f` }, "#!/bin/sh\nexit 0\n")
		t.expect(r.ok).toBe(true)
		t.expect(modeOf(`{dir}/f`)).toBe("0755")
		t.expect(fs.readFile(`{dir}/f`)).toBe("#!/bin/sh\nexit 0\n")
		t.expect(process.exec(`{dir}/f`, {}).ok).toBe(true) -- git can run it
		t.expect(#leftovers(dir)).toBe(0)
		t.expect(#strays(dir)).toBe(0)
		-- a three-digit mode works too, and the source-file form takes the option the same way
		fs.writeFile(`{dir}/src`, "from a file")
		t.expect(replace(dir, { "--mode=755", `{dir}/g`, `{dir}/src` }, "").ok).toBe(true)
		t.expect(modeOf(`{dir}/g`)).toBe("0755")
		t.expect(fs.readFile(`{dir}/g`)).toBe("from a file")
		t.expect(#strays(dir)).toBe(0)
		-- four digits are accepted (0644 is the default's own spelling)
		t.expect(replace(dir, { "--mode=0644", `{dir}/h` }, "h").ok).toBe(true)
		t.expect(modeOf(`{dir}/h`)).toBe("0644")
	end)

	it("with a mode, whatever is at the path is still replaced, never written through", function()
		local dir = fresh("link")
		fs.writeFile(`{dir}/victim`, "keep")
		t.expect(process.exec("ln", { "-s", `{dir}/victim`, `{dir}/dest` }).ok).toBe(true)
		t.expect(replace(dir, { "--mode=0755", `{dir}/dest` }, "new").ok).toBe(true)
		t.expect(fs.readFile(`{dir}/victim`)).toBe("keep")
		t.expect(process.exec("test", { "-L", `{dir}/dest` }).ok).toBe(false)
		t.expect(modeOf(`{dir}/dest`)).toBe("0755")
		-- and a real folder there is still refused
		fs.writeDir(`{dir}/folder`)
		local r = replace(dir, { "--mode=0755", `{dir}/folder` }, "x")
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stderr, "is a directory")).toBe(true)
	end)

	it("a mode that is not octal is refused before anything is written", function()
		local dir = fresh("bad")
		fs.writeFile(`{dir}/f`, "keep")
		for _, bad in { "abc", "0999", "", "7", "75", "75555", "-1", "7 5", "0755x" } do
			local r = replace(dir, { `--mode={bad}`, `{dir}/f` }, "new")
			t.expect(`{bad} {r.ok}`).toBe(`{bad} false`)
			t.expect(`{bad} {has(r.stderr, "--mode must be octal")}`).toBe(`{bad} true`)
		end
		t.expect(fs.readFile(`{dir}/f`)).toBe("keep")
		t.expect(#leftovers(dir)).toBe(0)
		t.expect(#strays(dir)).toBe(0)
		t.expect(modeOf(`{dir}/f`)).toBe("0644")
	end)

	it("sh.writeReplacing passes the mode on, and without one writes 0644", function()
		local dir = fresh("sh")
		sh.writeReplacing(`{dir}/plain`, "p")
		sh.writeReplacing(`{dir}/exec`, "e", "0755")
		t.expect(modeOf(`{dir}/plain`)).toBe("0644")
		t.expect(modeOf(`{dir}/exec`)).toBe("0755")
		t.expect(fs.readFile(`{dir}/exec`)).toBe("e")
		local ok = pcall(sh.writeReplacing, `{dir}/never`, "x", "9")
		t.expect(ok).toBe(false)
		t.expect(fs.isFile(`{dir}/never`)).toBe(false)
	end)
end)
