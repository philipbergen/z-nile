--!strict
-- c0163 AC2: `./zn markers` scans the tree being gated. In a fixture repository (tests/lib/trackerfix, under
-- .cache/c0163-markers) it passes on a clean tree and fails, naming `<file>:<line>: conflict marker` for each, on a
-- committed marker and on a staged one (the merge `land` makes is staged before it is committed); an untracked
-- file, a binary file and a symbolic link are not scanned. An exemption takes effect only from origin/main's
-- z-nile/marker-exemptions.txt (zz-arch rule 7): one in the working tree alone exempts nothing, and a malformed
-- working-tree list fails, naming its line. It is read-only, so it runs in the main checkout.
local fixture = require("@tests/lib/fixture")
local fs = require("@lune/fs")
local t = require("@tests/lib/t")
local trackerfix = require("@tests/lib/trackerfix")

local LT, GT, EQ = string.rep("<", 7), string.rep(">", 7), string.rep("=", 7)
local CONFLICT =
	table.concat({ "intro", LT .. " HEAD", "ours", EQ, "theirs", GT .. " origin/main", "" }, "\n")
local LIST = "z-nile/marker-exemptions.txt"

local function has(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local f: trackerfix.Fixture
local function markers(): fixture.Result
	return trackerfix.tr(f, f.main, { "markers" })
end
local function commit(files: { [string]: string })
	for path, text in files do
		local parent = string.match(path, "^(.*)/[^/]+$")
		if parent then
			fs.writeDir(`{f.main}/{parent}`)
		end
		fs.writeFile(`{f.main}/{path}`, text)
	end
	fixture.git(f.main, { "add", "-A" })
	fixture.git(f.main, { "commit", "-q", "-m", "c" })
end
local function reset()
	f = trackerfix.new("c0163-markers", { ["docs/clean.md"] = "nothing to see\n" })
end

return t.spec("c0163 ./zn markers", function(it)
	it("passes on a clean tree, in the main checkout", function()
		reset()
		local r = markers()
		if not r.ok then
			error(`clean tree failed: {r.stdout}{r.stderr}`, 0)
		end
	end)

	it("a committed conflict fails, naming each marker's file and line", function()
		reset()
		commit({ ["docs/merged.md"] = CONFLICT })
		local r = markers()
		t.expect(r.ok).toBe(false)
		local out = r.stdout .. r.stderr
		for _, line in { 2, 4, 6 } do
			t.expect(has(out, `docs/merged.md:{line}: conflict marker`)).toBe(true)
		end
		t.expect(has(out, "docs/clean.md")).toBe(false)
	end)

	it("a staged, uncommitted conflict fails; an untracked one does not", function()
		reset()
		fs.writeFile(`{f.main}/loose.md`, CONFLICT)
		t.expect(markers().ok).toBe(true)
		fixture.git(f.main, { "add", "loose.md" })
		local r = markers()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "loose.md:2: conflict marker")).toBe(true)
	end)

	it("a binary file and a symbolic link are not scanned", function()
		reset()
		commit({ ["img/blob.bin"] = "\0\1" .. CONFLICT })
		fs.writeFile(`{f.base}/outside.md`, CONFLICT)
		fixture.exec(f.main, "ln", { "-s", `{f.base}/outside.md`, "link.md" })
		fixture.git(f.main, { "add", "link.md" })
		fixture.git(f.main, { "commit", "-q", "-m", "link" })
		local r = markers()
		if not r.ok then
			error(`binary or link scanned: {r.stdout}{r.stderr}`, 0)
		end
	end)

	it("an exemption only in the working tree exempts nothing; once on origin/main it does", function()
		reset()
		commit({ ["docs/markers.md"] = CONFLICT, [LIST] = "# exemptions\ndocs/markers.md\n" })
		local r = markers()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, "docs/markers.md:2: conflict marker")).toBe(true)
		trackerfix.elsewhere(
			f,
			{ [LIST] = "# exemptions\ndocs/markers.md\n" },
			"exempt the documented markers"
		)
		fixture.git(f.main, { "fetch", "-q", "origin" })
		local after = markers()
		if not after.ok then
			error(`exemption on origin/main not applied: {after.stdout}{after.stderr}`, 0)
		end
	end)

	it("a malformed working-tree list fails, naming its line", function()
		reset()
		commit({ [LIST] = "# exemptions\ndocs/*.md\n" })
		local r = markers()
		t.expect(r.ok).toBe(false)
		t.expect(has(r.stdout .. r.stderr, `{LIST}:2:`)).toBe(true)
	end)
end)
