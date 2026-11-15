--!strict
-- c0258 AC1: what `./zn <command> -h` prints (z-nile/engine/usage.luau), in process. The parser's structure is pinned on
-- a usage text written here (design review 001 F3: other items add and edit entries of the real one); against the
-- real usage text (main.luau's USAGE) only rules are pinned: every command the engine has has an entry, every entry
-- of a command is that command's, land's own entry, and the header names -h. The commands are read wherever they
-- live (F4: c0180 moves handlers into z-nile/engine/cmd/): every `function cmd.<n>(` and `cmd["<n>"] = function` in
-- any engine file, the files of engine/cmd/, and main.luau's `require("./cmd/<n>")`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local t = require("@tests/lib/t")
local usage = require("@znile/engine/usage")

local root = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local ENGINE = `{root}/z-nile/engine`
local main = fs.readFile(`{ENGINE}/main.luau`)
local OPEN = "local USAGE = [" .. "["
local at = string.find(main, OPEN, 1, true)
local USAGE = if at
	then string.sub(main, at + #OPEN + 1, (string.find(main, "]" .. "]", at, true) or #main + 1) - 1)
	else ""

-- a usage text with every shape the parser meets
local SAMPLE = table.concat({
	"usage: ./zn <command> ...",
	"  work [<R-id>]                                 the worker",
	"                                                (a continuation line)",
	"  work --resume                                 the worker, again",
	"  workstreams <R-id>                            plan the streams",
	"  worktree <name>                               make a worktree",
	"   oddly indented line after worktree's entry",
	"  stop <R-id>                                   give back a raft",
	"  lessons [<terms>...]                          search the lessons",
	"                                                also --tags and --check",
	"  skills [--check]                              the skill links",
	"",
}, "\n")

local function has(text: string?, needle: string): boolean
	return text ~= nil and string.find(text, needle, 1, true) ~= nil
end
-- the first words of the entries a printed usage holds
local function words(text: string?): { string }
	local out: { string } = {}
	for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
		local w = string.match(line, "^  (%S+)")
		if w then
			table.insert(out, w)
		end
	end
	return out
end
-- every engine Luau file, recursively
local function engineFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			engineFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end
-- the commands the engine defines, wherever they live
local function commands(): { string }
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	local function add(n: string)
		if not seen[n] then
			seen[n] = true
			table.insert(names, n)
		end
	end
	local files: { string } = {}
	engineFiles(ENGINE, files)
	for _, file in files do
		local text = "\n" .. fs.readFile(file)
		for n in string.gmatch(text, "\nfunction cmd%.([%w_]+)%(") do
			add(n)
		end
		for n in string.gmatch(text, '\ncmd%["([%w%-]+)"%] = function') do
			add(n)
		end
	end
	if fs.isDir(`{ENGINE}/cmd`) then
		for _, name in fs.readDir(`{ENGINE}/cmd`) do
			local n = string.match(name, "^([%w%-_]+)%.luau$")
			if n then
				add(n)
			end
		end
	end
	for n in string.gmatch(main, 'require%("%./cmd/([%w%-_]+)"%)') do
		add(n)
	end
	table.sort(names)
	return names
end

return t.spec("c0258 usage", function(it)
	it("AC1: a command's usage is its entries, with their continuation lines, under a usage line", function()
		local work = usage.of(SAMPLE, "work")
		t.expect(string.sub(work or "", 1, #"usage: ./zn work ...\n")).toBe("usage: ./zn work ...\n")
		t.expect(words(work)).toEqual({ "work", "work" })
		t.expect(has(work, "(a continuation line)")).toBe(true)
		t.expect(has(work, "the worker, again")).toBe(true)
		local lessons = usage.of(SAMPLE, "lessons")
		t.expect(has(lessons, "also --tags and --check")).toBe(true)
	end)

	it("AC1: a command is its whole first word, never a prefix of another", function()
		local work = usage.of(SAMPLE, "work")
		t.expect(has(work, "workstreams")).toBe(false)
		t.expect(has(work, "worktree")).toBe(false)
		t.expect(words(usage.of(SAMPLE, "worktree"))).toEqual({ "worktree" })
		t.expect(words(usage.of(SAMPLE, "workstreams"))).toEqual({ "workstreams" })
	end)

	it("AC1: the next entry ends one, and a line of three or more spaces continues it", function()
		local lessons = usage.of(SAMPLE, "lessons")
		t.expect(has(lessons, "skills [--check]")).toBe(false)
		local worktree = usage.of(SAMPLE, "worktree")
		t.expect(has(worktree, "oddly indented line after worktree's entry")).toBe(true)
		t.expect(has(worktree, "stop <R-id>")).toBe(false)
		t.expect(words(usage.of(SAMPLE, "stop"))).toEqual({ "stop" })
	end)

	it("AC1: a command the text does not have has no usage", function()
		t.expect(usage.of(SAMPLE, "nope")).toBe(nil)
		t.expect(usage.of(SAMPLE, "")).toBe(nil)
		t.expect(usage.of(SAMPLE, "usage:")).toBe(nil)
		t.expect(usage.of("", "work")).toBe(nil)
	end)

	it("AC1: -h and --help are help, and a value another option takes is not", function()
		t.expect(usage.wantsHelp({ ["-h"] = { "true" } })).toBe(true)
		t.expect(usage.wantsHelp({ ["--help"] = { "true" } })).toBe(true)
		t.expect(usage.wantsHelp({ ["-m"] = { "-h" } })).toBe(false)
		t.expect(usage.wantsHelp({ ["--desc"] = { "--help" } })).toBe(false)
		t.expect(usage.wantsHelp({})).toBe(false)
	end)

	it("AC1: the real usage text is main.luau's, has land's entry and names -h", function()
		t.expect(has(USAGE, "usage: ./zn <command> ...")).toBe(true)
		t.expect(has(USAGE, "./zn <command> -h")).toBe(true)
		local land = usage.of(USAGE, "land")
		t.expect(has(land, "  land [-m <message>]")).toBe(true)
		t.expect(has(land, "push the capture to main")).toBe(true)
	end)

	it("AC1: every command the engine has has an entry, and every entry printed for it is its own", function()
		local names = commands()
		t.expect(#names >= 40).toBe(true)
		local missing: { string } = {}
		local foreign: { string } = {}
		for _, n in names do
			local text = usage.of(USAGE, n)
			if not text then
				table.insert(missing, n)
			else
				for _, w in words(text) do
					if w ~= n then
						table.insert(foreign, `{n}: {w}`)
					end
				end
			end
		end
		t.expect(missing).toEqual({})
		t.expect(foreign).toEqual({})
	end)
end)
