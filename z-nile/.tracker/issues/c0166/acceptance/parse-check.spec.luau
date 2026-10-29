--!strict
-- c0166 AC3: paths: parse, unlisted tags, a check that repeats the title, and the real tree.
local fs = require("@lune/fs")
local lessonareas = require("@znile/engine/lessonareas")
local lessons = require("@znile/engine/lessons")
local process = require("@lune/process")
local t = require("@tests/lib/t")

local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local areas = lessonareas :: any

local function has(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local function front(tags: string, check: string, title: string, extra: string?): string
	return `---\ntitle: {title}\nwhen: build\ntags: [{tags}]\ncheck: {check}\n`
		.. (extra or "")
		.. "from: user 2026-10-26: said so\n---\nBody.\n"
end

local SMALL = "core: review\nwiring: @skill\nacceptance: @item\n"

local function tree(text: string, folders: { [string]: string }?): any
	return {
		lessons = { ["zz-test/pin"] = text },
		found = {},
		skills = { ["zz-test"] = true },
		folders = folders,
		areas = if folders then areas.parse(SMALL) else nil,
		items = {},
		problems = {},
	}
end

return t.spec("c0166 parse and check", function(it)
	it("a legal paths list parses and an absent key stays nil", function()
		local l, err = lessons.parse(
			"zz-test/pin",
			front("wiring", "Is it pinned?", "T", "paths: [z-nile/lib/fence.sh, pickman/src/shared]\n")
		)
		t.expect(err).toBe(nil)
		t.expect((l :: any).paths).toEqual({ "z-nile/lib/fence.sh", "pickman/src/shared" })
		local plain, plainErr = lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T"))
		t.expect(plainErr).toBe(nil)
		t.expect((plain :: any).paths).toBe(nil)
	end)

	it("dotdot", function()
		local _, err = lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T", "paths: [../x]\n"))
		t.expect(err ~= nil).toBe(true)
		t.expect(string.find(err :: string, "zz-test/pin", 1, true) ~= nil).toBe(true)
		t.expect(string.find(err :: string, "not a repository path", 1, true) ~= nil).toBe(true)
		local _, abs =
			lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T", "paths: [/tmp/x]\n"))
		t.expect(string.find(abs :: string, "not a repository path", 1, true) ~= nil).toBe(true)
		local _, slash =
			lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T", "paths: [z-nile/engine/]\n"))
		t.expect(string.find(slash :: string, "not a repository path", 1, true) ~= nil).toBe(true)
	end)

	it("an empty paths list and an unknown key are refused", function()
		local _, empty = lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T", "paths: []\n"))
		t.expect(string.find(empty :: string, "paths needs at least one path", 1, true) ~= nil).toBe(true)
		local _, bare = lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T", "paths: zn\n"))
		t.expect(string.find(bare :: string, "paths must be a [p, q] list", 1, true) ~= nil).toBe(true)
		local _, owner =
			lessons.parse("zz-test/pin", front("wiring", "Is it pinned?", "T", "owner: someone\n"))
		t.expect(string.find(owner :: string, "unknown key owner", 1, true) ~= nil).toBe(true)
	end)

	it("unlisted tag", function()
		local withFolders =
			tree(front("not-a-tag", "Is it pinned?", "T"), { ["zz-test"] = "z-nile/skills/zz-test" })
		local problems = lessons.check(withFolders)
		t.expect(has(problems, "zz-test/pin: unlisted tag not-a-tag")).toBe(true)
		local bare = lessons.check(tree(front("not-a-tag", "Is it pinned?", "T")))
		t.expect(has(bare, "unlisted")).toBe(false)
		local noAreas =
			tree(front("not-a-tag", "Is the pin specific?", "T"), { ["zz-test"] = "z-nile/skills/zz-test" })
		noAreas.areas = nil
		t.expect(has(lessons.check(noAreas), "unlisted")).toBe(false)
		local listed = lessons.check(
			tree(front("wiring", "Is the pin specific?", "T"), { ["zz-test"] = "z-nile/skills/zz-test" })
		)
		t.expect(listed).toEqual({})
	end)

	it("three words are not concrete", function()
		local short = lessons.check(
			tree(front("wiring", "Is it pinned?", "T"), { ["zz-test"] = "z-nile/skills/zz-test" })
		)
		t.expect(has(short, "zz-test/pin: check is not concrete")).toBe(true)
		t.expect(has(short, "scope")).toBe(false)
		local four = lessons.check(
			tree(front("wiring", "Is the pin specific?", "T"), { ["zz-test"] = "z-nile/skills/zz-test" })
		)
		t.expect(has(four, "concrete")).toBe(false)
		local bare = lessons.check(tree(front("wiring", "Is it pinned?", "T")))
		t.expect(has(bare, "concrete")).toBe(false)
	end)

	it("check repeats the title", function()
		local problems = lessons.check(tree(front("wiring", "Is it pinned?", "Is it pinned")))
		t.expect(has(problems, "zz-test/pin: check repeats the title")).toBe(true)
		t.expect(has(problems, "scope")).toBe(false)
	end)

	it("the real tree lists every tag and has no scope problem", function()
		local path = `{TOP}/z-nile/lesson-areas.md`
		t.expect(fs.isFile(path)).toBe(true)
		local parsed = areas.parse(fs.readFile(path))
		t.expect(#parsed.core > 0).toBe(true)
		t.expect(#parsed.problems).toBe(0)
		for _, tag in parsed.core do
			t.expect(parsed.areas[tag] ~= nil).toBe(true)
		end
		local function legal(prefix: string): boolean
			if prefix == "@skill" or prefix == "@item" then
				return true
			end
			return areas.legalPath(prefix)
		end
		local loaded = lessons.load(TOP)
		t.expect(lessons.check(loaded)).toEqual({})
		for id, text in loaded.lessons do
			local l, err = lessons.parse(id, text)
			t.expect(err).toBe(nil)
			for _, tag in (l :: any).tags do
				local got = parsed.areas[tag]
				t.expect(got ~= nil).toBe(true)
				for _, prefix in got do
					t.expect(legal(prefix)).toBe(true)
				end
			end
		end
		for _, prefixes in parsed.areas do
			for _, prefix in prefixes do
				t.expect(legal(prefix)).toBe(true)
			end
		end
		t.expect(has(lessons.check(loaded), "scope")).toBe(false)
	end)

	it("a repeated core line", function()
		local function problems(text: string): { string }
			return areas.parse(text).problems
		end
		t.expect(has(problems("core: review\ncore: process\n"), "core is repeated")).toBe(true)
		t.expect(has(problems("mode design: z-design\nmode design: zz-review\n"), "mode design is repeated"))
			.toBe(true)
		t.expect(has(problems("fence: z-nile/lib/fence.sh\nfence: pickman/src\n"), "fence is repeated"))
			.toBe(true)
		t.expect(has(problems("mode: @skill\n"), "mode is reserved")).toBe(true)
		local reserved = lessons.check(
			tree(front("core", "Is the pin specific?", "T"), { ["zz-test"] = "z-nile/skills/zz-test" })
		)
		t.expect(has(reserved, "zz-test/pin: reserved tag core")).toBe(true)
	end)
end)
