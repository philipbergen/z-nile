--!strict
-- c0178 code review 001 (F6, F7, F8): the clone helper's and the template's failure paths. A clone never removes a
-- destination another process made, a linked source is refused however it is spelled, any failure between the clone and the
-- remote check removes the fixture, two toolings never share a template, and a template missing a top-level entry refuses.
-- Private templates only (trackerfix.TOOLING at a copy made with engine.copy): the run's own templates are never written.
local engine = require("@tests/lib/engine")
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local fxclone = require("@tests/lib/fxclone")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local ROOT = fixture.physical(".") :: string
local BASE = `{ROOT}/.cache/fxclone-spec`

local function fresh(dir: string)
	if fs.isDir(dir) then
		fs.removeDir(dir)
	end
	fs.writeDir(dir)
end

local function source(): string
	local src = `{BASE}/src`
	if not fs.isDir(src) then
		fs.writeDir(`{src}/a`)
		fs.writeFile(`{src}/a/f`, "one\n")
	end
	return src
end

-- runs `body` with trackerfix.TOOLING at a private tooling at `dir`, made by `make` (default: engine.copy of the run's)
local function withTooling(dir: string, body: () -> ...any)
	local was = trackerfix.TOOLING
	trackerfix.TOOLING = dir
	trackerfix.forget()
	local ok, err = pcall(body)
	trackerfix.TOOLING = was
	trackerfix.forget()
	if not ok then
		error(err, 0)
	end
end

local function privateTooling(dir: string): string
	fresh(dir)
	engine.copy(fixture.physical(trackerfix.TOOLING) :: string, dir)
	return dir
end

return t.spec("c0178 fxclone and the template's failure paths", function(it)
	it("a destination another process made while the clone ran is left alone", function()
		if process.os ~= "macos" then
			return -- the seam stands for clonefileat, which only macOS calls
		end
		fresh(BASE)
		local dst = `{BASE}/raced`
		t.expect(function()
			fxclone.tree(source(), dst, { simulate = "EEXIST" })
		end).toThrow("EEXIST")
		t.expect(fs.readFile(`{dst}/theirs`)).toBe("made by another process\n")
	end)

	it("a clone that failed after making part of its destination removes that part", function()
		if process.os ~= "macos" then
			return
		end
		fresh(BASE)
		local dst = `{BASE}/partial`
		t.expect(function()
			fxclone.tree(source(), dst, { simulate = "ENOSPC" })
		end).toThrow("ENOSPC")
		t.expect(fs.isDir(dst)).toBe(false)
	end)

	it("ENOTSUP falls back to a copy, and says why", function()
		if process.os ~= "macos" then
			return
		end
		fresh(BASE)
		local how, reason = fxclone.tree(source(), `{BASE}/copied`, { simulate = "ENOTSUP" })
		t.expect(how).toBe("copy")
		t.expect(string.find(reason or "", "ENOTSUP", 1, true) ~= nil).toBe(true)
		t.expect(fs.readFile(`{BASE}/copied/a/f`)).toBe("one\n")
	end)

	it("a linked source is refused also when it is spelled with a trailing slash", function()
		fresh(BASE)
		local link = `{BASE}/link`
		t.expect(process.exec("ln", { "-s", source(), link }).ok).toBe(true)
		for _, spelled in { link, `{link}/`, `{link}//` } do
			t.expect(function()
				fxclone.tree(spelled, `{BASE}/through-link`)
			end).toThrow("link")
			t.expect(fs.isDir(`{BASE}/through-link`)).toBe(false)
		end
	end)

	it("a failure of the rewrite or of a checkout's config read removes the fixture", function()
		for _, step in { "rewrite", "config" } do
			trackerfix.FAIL_AT = step
			local ok, err = pcall(trackerfix.new, "fxclone-spec-fail", {})
			trackerfix.FAIL_AT = nil
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), step, 1, true) ~= nil).toBe(true)
			t.expect(fs.isDir(`{ROOT}/.cache/fxclone-spec-fail`)).toBe(false)
		end
	end)

	it("two toolings with the same content and times never share a template", function()
		local a = privateTooling(`{BASE}-tooling-a`)
		local b = `{BASE}-tooling-b`
		if fs.isDir(b) then
			fs.removeDir(b)
		end
		t.expect(process.exec("cp", { "-Rp", a, b }).ok).toBe(true)
		local ta, tb = "", ""
		withTooling(a, function()
			ta = trackerfix.template(false)
		end)
		withTooling(b, function()
			tb = trackerfix.template(false)
		end)
		t.expect(ta ~= tb).toBe(true)
	end)

	it("a template missing a top-level folder refuses the next clone and leaves no fixture", function()
		withTooling(privateTooling(`{BASE}-tooling-c`), function()
			local tpl = trackerfix.template(false)
			fs.removeDir(`{tpl}/other`)
			t.expect(function()
				trackerfix.new("fxclone-spec-missing", {})
			end).toThrow("template changed")
			t.expect(fs.isDir(`{ROOT}/.cache/fxclone-spec-missing`)).toBe(false)
		end)
	end)
end)
