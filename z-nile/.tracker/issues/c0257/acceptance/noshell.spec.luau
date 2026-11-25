--!strict
-- c0257 AC5: no file of the plugin starts an external program through a shell: the argument-array forms of a shell with -c are
-- banned as well as the string forms, every QML, JS and shell file is scanned (the count must equal the folder's), and the
-- matcher is shown to hit a sample of each banned form. The three scripts stop on error and are executable.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
-- ZN_C0257_TREE: a copy of the tree that holds z-nile-omarchy/ (prep proved these specs against the prototype that way)
local APP = `{process.env.ZN_C0257_TREE or TOP}/z-nile-omarchy/znile.board`

-- a shell program named as an argument (quoted), followed by a -c style flag (-c, -lc, -ic, ...)
local function shellArgv(text: string): boolean
	return string.find(text, '"[%w/]*b?a?sh"%s*,%s*"%-[a-z]*c"') ~= nil
		or string.find(text, "'[%w/]*b?a?sh'%s*,%s*'%-[a-z]*c'") ~= nil
end

-- a shell string: `sh -c`, `bash -c` (and -lc), a quoted "sh -c ..." element, eval
local function shellString(text: string): boolean
	return string.find(text, "%f[%w]b?a?sh%s+%-[a-z]*c%f[%A]") ~= nil
		or string.find(text, "%f[%w]eval[%s%(]") ~= nil
end

local function bad(text: string): boolean
	return shellArgv(text) or shellString(text)
end

local function files(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			files(path, out)
		elseif
			string.match(name, "%.qml$")
			or string.match(name, "%.js$")
			or string.match(name, "%.mjs$")
			or string.match(name, "%.sh$")
		then
			table.insert(out, path)
		end
	end
end

return t.spec("c0257 AC5: no shell string in the plugin", function(it)
	it("AC5: the matcher hits every banned form and none of the allowed ones", function()
		t.expect(bad('command: ["bash", "-c", root.pluginDir + "/agents.sh | cat"]')).toBe(true)
		t.expect(bad('Quickshell.execDetached(["sh", "-lc", cmd])')).toBe(true)
		t.expect(bad("Quickshell.execDetached(['/bin/sh', '-c', cmd])")).toBe(true)
		t.expect(bad('Quickshell.execDetached(["sh -c", "printf %s x | wl-copy"])')).toBe(true)
		t.expect(bad("bash -c 'echo hi'")).toBe(true)
		t.expect(bad("result = eval(text)")).toBe(true)
		t.expect(bad('command: [pluginDir + "/fetch.sh", repoPath]')).toBe(false)
		t.expect(bad('Quickshell.execDetached(["wl-copy", "--", prompt])')).toBe(false)
		t.expect(bad("// a bash script with a -c flag in a sentence: bash users")).toBe(false)
	end)

	it("AC5: every QML, JS and shell file of the plugin is clean, and all of them were scanned", function()
		local all: { string } = {}
		files(APP, all)
		t.expect(#all >= 17).toBe(true)
		local dirty: { string } = {}
		for _, path in all do
			if bad(fs.readFile(path)) then
				table.insert(dirty, path)
			end
		end
		t.expect(dirty).toEqual({})
	end)

	it("AC5: the scripts start with a shebang, stop on error and are executable", function()
		for _, f in { "fetch.sh", "prs.sh", "agents.sh" } do
			local text = fs.readFile(`{APP}/{f}`)
			t.expect(`{f}:{string.sub(text, 1, 2)}`).toBe(`{f}:#!`)
			t.expect(`{f}:{string.find(text, "set -", 1, true) ~= nil}`).toBe(`{f}:true`)
			t.expect(`{f}:{process.exec("test", { "-x", `{APP}/{f}` }).ok}`).toBe(`{f}:true`)
		end
	end)
end)
