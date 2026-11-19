--!strict
-- c0174 AC2: runs the edited text-read case of c0083's suites.spec against a model of the textAffected rule that
-- c0083's Design states (c0083.md, `suites.textAffected`), because the module itself does not exist until c0083
-- runs and the rest of that spec is written for the old layout. Two parts, each proven able to fail:
--   1. the workflow pair in the case's `cases` table holds on this tree: the changed file exists and the model selects
--      the named reader for it;
--   2. the case's folder block (the statements at its end), run with the model on this tree, selects c0001's
--      ci-workflow for the changed folder `.github/workflows`.
-- The model follows the Design's words: references are the string literals and the literal pieces of interpolated
-- strings (not the code between braces, strings in it included) after `graph.stripComments`, split at spaces; a leading
-- `/` or `./` and a trailing `/` are dropped; a changed path matches a reference equal to it, a folder above it, or an
-- existing reference inside it. It differs from c0083's module in not distinguishing the rule's two sets (existing
-- and absent references): the existence test is `fs.isFile or fs.isDir` on this tree. It also tests existence
-- from the checkout's top as well as z-nile's home, because the case's own paths mix the two (`.github/workflows` is at
-- the top, `tests/...` from the home): the re-prep, which re-homes every path in the spec, decides which one the real
-- module sees. It is read-only.
--   lune run folder-case.luau <suites.spec.luau>
local fs = require("@lune/fs")
local graph = require("@znile/lib/graph")
local luau = require("@lune/luau")
local process = require("@lune/process")

local path = process.args[1]
if path == nil then
	print("usage: folder-case.luau <suites.spec.luau>")
	process.exit(2)
end
local source = fs.readFile(path :: string)
local TOP = (string.gsub(process.exec("git", { "rev-parse", "--show-toplevel" }).stdout, "%s+$", ""))
local HOME = `{TOP}/z-nile` -- the specs are named from z-nile's home

type Options = { keepSlash: boolean, folderAboveOnly: boolean }

-- the literal pieces of the strings in `src` (comments already stripped); code between interpolation braces is skipped
local function pieces(src: string): { string }
	local out: { string } = {}
	local i, n = 1, #src
	local function quoted(q: string, from: number): (string, number)
		local j, buf = from, ""
		while j <= n do
			local ch = string.sub(src, j, j)
			if ch == "\\" then
				buf ..= string.sub(src, j, j + 1)
				j += 2
			elseif ch == q then
				return buf, j + 1
			else
				buf ..= ch
				j += 1
			end
		end
		return buf, j
	end
	while i <= n do
		local ch = string.sub(src, i, i)
		if ch == '"' or ch == "'" then
			local lit, nextAt = quoted(ch, i + 1)
			table.insert(out, lit)
			i = nextAt
		elseif ch == "`" then
			local j, cur, depth = i + 1, "", 0
			while j <= n do
				local c = string.sub(src, j, j)
				if depth == 0 and c == "`" then
					break
				elseif depth == 0 and c == "{" then
					if cur ~= "" then
						table.insert(out, cur)
					end
					cur = ""
					depth = 1
					j += 1
				elseif depth > 0 and c == "{" then
					depth += 1
					j += 1
				elseif depth > 0 and c == "}" then
					depth -= 1
					j += 1
				elseif depth > 0 and (c == '"' or c == "'") then
					local _, nextAt = quoted(c, j + 1)
					j = nextAt
				elseif depth == 0 then
					cur ..= c
					j += 1
				else
					j += 1
				end
			end
			if cur ~= "" then
				table.insert(out, cur)
			end
			i = j + 1
		else
			i += 1
		end
	end
	return out
end

local function textAffected(
	files: { string },
	read: (string) -> string?,
	exists: (string) -> boolean,
	changed: { string },
	opt: Options
): { string }
	local hits: { string } = {}
	for _, spec in files do
		local text = read(spec)
		local hit = false
		if text ~= nil then
			for _, piece in pieces(graph.stripComments(text)) do
				for tok in string.gmatch(piece, "[^ ]+") do
					if not opt.keepSlash then
						tok = string.gsub(tok, "^/+", "")
						tok = string.gsub(tok, "^%./", "")
					end
					tok = string.gsub(tok, "/+$", "")
					for _, c in changed do
						c = string.gsub(c, "/+$", "")
						local equalOrAbove = tok == c or string.sub(c, 1, #tok + 1) == tok .. "/"
						local inside = not opt.folderAboveOnly
							and string.sub(tok, 1, #c + 1) == c .. "/"
							and exists(tok)
						if equalOrAbove or inside then
							hit = true
						end
					end
				end
			end
		end
		if hit then
			table.insert(hits, spec)
		end
	end
	return hits
end

-- the real tree
local function specsUnder(dir: string, rel: string, out: { string })
	for _, name in fs.readDir(`{dir}/{rel}`) do
		local r = `{rel}/{name}`
		if fs.isDir(`{dir}/{r}`) then
			specsUnder(dir, r, out)
		elseif string.sub(name, -10) == ".spec.luau" then
			table.insert(out, r)
		end
	end
end
local real: { string } = {}
specsUnder(HOME, "tests", real)
local function readReal(spec: string): string?
	return if fs.isFile(`{HOME}/{spec}`) then fs.readFile(`{HOME}/{spec}`) else nil
end
local function existsReal(p: string): boolean
	for _, base in { TOP, HOME } do
		if fs.isFile(`{base}/{p}`) or fs.isDir(`{base}/{p}`) then
			return true
		end
	end
	return false
end

local failed = 0
local function report(ok: boolean, what: string)
	if not ok then
		failed += 1
	end
	print(`{if ok then "ok  " else "FAIL"} {what}`)
end
local GOOD: Options = { keepSlash = false, folderAboveOnly = false }

-- part 1: the workflow pair
local changed, reader = string.match(source, '{ "(%.github/workflows/[^"]+)", "([^"]+)" }')
if changed == nil then
	print("no workflow pair in the case's cases table")
	process.exit(1)
end
local function pairHolds(opt: Options): boolean
	if not fs.isFile(`{TOP}/{changed}`) then
		return false
	end
	return table.find(textAffected(real, readReal, existsReal, { changed }, opt), reader) ~= nil
end
report(pairHolds(GOOD), `the pair {changed} -> {reader} holds on this tree`)
report(
	not pairHolds({ keepSlash = true, folderAboveOnly = false }),
	"  and fails if a leading slash were kept (the {TOP}/ form)"
)

-- part 2: the folder block, on the real tree
local from = string.find(
	source,
	"-- a changed folder selects the specs that name an existing file inside it.",
	1,
	true
)
if from == nil then
	print("no folder block in the case")
	process.exit(1)
end
local upto = string.find(source, "\n\t\tend\n\t)", from :: number, true)
if upto == nil then
	print("the case does not end with `end` and `)` at two tabs and one tab")
	process.exit(1)
end
local block = string.sub(source, from :: number, (upto :: number) - 1)
local function runBlock(opt: Options): string?
	local stubFs = {
		isDir = function(p: string): boolean
			return fs.isDir(`{TOP}/{p}`)
		end,
	}
	local suites = {
		textAffected = function(_: any, ch: { string }): { string }
			return textAffected(real, readReal, existsReal, ch, opt)
		end,
	}
	local t = {
		expect = function(actual: any)
			return {
				toBe = function(expected: any)
					if actual ~= expected then
						error(`expected {tostring(expected)}, got {tostring(actual)}`, 2)
					end
				end,
			}
		end,
	}
	local function set(list: { string }): { [string]: boolean }
		local s: { [string]: boolean } = {}
		for _, x in list do
			s[x] = true
		end
		return s
	end
	local ok, err = pcall(function()
		local chunk = luau.load(
			"local fs, t, suites, g, set = ...\nreturn function()\n" .. block .. "\nend",
			{ debugName = "block" }
		)
		chunk(stubFs, t, suites, { files = real }, set)()
	end)
	return if ok then nil else tostring(err)
end
local eg = runBlock(GOOD)
if eg then
	print(eg)
end
report(eg == nil, "the folder block selects ci-workflow for .github/workflows against the model")
local e = runBlock({ keepSlash = false, folderAboveOnly = true })
report(
	e ~= nil and string.match(e, '^%[string "block"%]:%d+: expected ') ~= nil,
	"  and fails on an assertion if a changed folder matched only tokens above it"
)

print(if failed == 0 then "all as expected" else `{failed} not as expected`)
process.exit(if failed == 0 then 0 else 1)
