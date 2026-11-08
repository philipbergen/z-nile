--!strict
-- c0262 AC6: `./zn final-view <issue> --out <folder> [--base <ref>]` builds the limited view for real, from this
-- checkout: the captured ask, the design without the execution's words, the check and the diff. It reads the
-- repository and writes only its new --out folder, which this spec puts under the home's .cache; it refuses a folder
-- that already holds files, and an issue it can't find.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HOME = (string.gsub(process.exec("pwd", { "-P" }).stdout, "%s+$", ""))
local OUT = `{HOME}/.cache/c0262-final-view`

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end
local function view(args: { string }): process.ExecResult
	return process.exec(`{TOP}/zn`, args, { cwd = TOP })
end

return t.spec("c0262 AC6 ./zn final-view builds the limited view", function(it)
	it("builds ask.md, design.md, check.sh and an implementation.patch (empty against HEAD) in a new folder", function()
		if fs.isDir(OUT) then
			fs.removeDir(OUT)
		end
		local r = view({ "final-view", "c0262", "--out", OUT, "--base", "HEAD" })
		t.expect(r.ok).toBe(true)
		t.expect(fs.isFile(`{OUT}/README.md`)).toBe(true)
		t.expect(fs.isFile(`{OUT}/check.sh`)).toBe(true)
		t.expect(fs.isFile(`{OUT}/implementation.patch`)).toBe(true)
		-- the ask is the captured version: the Problem as the user's capture left it
		t.expect(has(fs.readFile(`{OUT}/ask.md`), "A final limited-view review per ticket")).toBe(true)
		local design = fs.readFile(`{OUT}/design.md`)
		t.expect(has(design, "## Design")).toBe(true)
		t.expect(has(design, "## Verification log")).toBe(false)
		t.expect(has(design, "\nstatus:")).toBe(false)
		-- nothing of the execution or of earlier reviews is in the folder
		for _, name in fs.readDir(OUT) do
			t.expect(string.find(name, "review", 1, true) == nil).toBe(true)
			t.expect(string.find(name, "refute", 1, true) == nil).toBe(true)
			t.expect(string.find(name, "harvest", 1, true) == nil).toBe(true)
			t.expect(string.find(name, "spend", 1, true) == nil).toBe(true)
		end
		t.expect(fs.isDir(`{OUT}/acceptance`)).toBe(true)
		fs.removeDir(OUT)
	end)

	it("refuses a folder that already holds files, and an unknown issue", function()
		fs.writeDir(OUT)
		fs.writeFile(`{OUT}/keep.txt`, "mine")
		local busy = view({ "final-view", "c0262", "--out", OUT, "--base", "HEAD" })
		t.expect(busy.ok).toBe(false)
		t.expect(fs.readFile(`{OUT}/keep.txt`)).toBe("mine")
		fs.removeDir(OUT)
		local missing = view({ "final-view", "c9999", "--out", OUT, "--base", "HEAD" })
		t.expect(missing.ok).toBe(false)
		t.expect(fs.isDir(OUT)).toBe(false)
	end)
end)
