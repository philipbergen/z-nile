--!strict
-- c0050 AC1-AC3: specs that clone the repository get a copy that shares no object file with it, so a
-- throwaway clone can never damage (or be damaged through) the real object store, and SETUP.md
-- warns against checkouts in cloud-synced folders.
local clone = require("@tests/lib/clone")
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local base = `{root}/.cache/c0050-clone`

local function linkedObjects(dir: string): string
	local r = process.exec("find", { `{dir}/.git/objects`, "-type", "f", "-links", "+1" })
	t.expect(r.ok).toBe(true)
	return (string.gsub(r.stdout, "%s+$", ""))
end

-- every .spec.luau under dir
local function specs(dir: string, out: { string })
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			specs(path, out)
		elseif string.match(name, "%.spec%.luau$") then
			table.insert(out, path)
		end
	end
end

local function git(args: { string }, cwd: string)
	local r = process.exec("git", args, { cwd = cwd })
	if not r.ok then
		error(`git {table.concat(args, " ")} failed: {r.stderr}`, 2)
	end
end

return t.spec("c0050 isolated clones", function(it)
	it("an isolated clone shares no object file with the repo", function()
		if fs.isDir(base) then
			fs.removeDir(base)
		end
		-- a throwaway source repository, so that this spec never hardlinks the real object store itself
		local source = `{base}/source`
		fs.writeDir(source)
		git({ "init", "-q" }, source)
		git({ "config", "user.name", "e2e" }, source)
		git({ "config", "user.email", "e2e@example.invalid" }, source)
		fs.writeFile(`{source}/file.txt`, "one\n")
		git({ "add", "-A" }, source)
		git({ "commit", "-qm", "one" }, source)
		-- the control: a plain local clone hardlinks, which is what this guards against
		t.expect(process.exec("git", { "clone", "-q", source, `{base}/plain` }).ok).toBe(true)
		t.expect(linkedObjects(`{base}/plain`) ~= "").toBe(true)
		clone.isolated(source, `{base}/isolated`)
		t.expect(linkedObjects(`{base}/isolated`)).toBe("")
		local head = process.exec("git", { "rev-parse", "HEAD" }, { cwd = `{base}/isolated` })
		local want = process.exec("git", { "rev-parse", "HEAD" }, { cwd = source })
		t.expect(head.stdout).toBe(want.stdout)
	end)

	it("a failed clone is an error that names the source", function()
		local ok, err = pcall(clone.isolated, `{base}/does-not-exist`, `{base}/never`)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "does-not-exist", 1, true) ~= nil).toBe(true)
	end)

	it("no spec clones the repository with a plain git clone", function()
		local files: { string } = {}
		specs(`{root}/tests`, files)
		specs(`{root}/tracker`, files)
		local offenders: { string } = {}
		for _, file in files do
			for literal in string.gmatch(fs.readFile(file), '{%s*"clone"[^}]*}') do
				local clonesRoot = string.find(literal, "[%s,{]root[%s,}]") ~= nil
				if clonesRoot and not string.find(literal, '"--no-hardlinks"', 1, true) then
					table.insert(offenders, file)
				end
			end
		end
		t.expect(offenders).toEqual({})
	end)

	it("SETUP.md warns against a checkout in a cloud-synced folder and names the symptom", function()
		local setup = fs.readFile(`{root}/SETUP.md`)
		for _, needle in { "iCloud", "No such file or directory" } do
			t.expect(string.find(setup, needle, 1, true) ~= nil).toBe(true)
		end
	end)

	it("cleans up", function()
		fs.removeDir(base)
	end)
end)
