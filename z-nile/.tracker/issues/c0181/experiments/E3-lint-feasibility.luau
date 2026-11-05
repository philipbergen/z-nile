--!strict
-- c0181 E3: can a lesson's rule be a text lint over the real tree, and what does one cost and find? Reads every tracked
-- text file once (the static stage's whole read) and scans four lessons' rules the way a lint would. Reads only.
--   perl -e 'alarm shift; exec @ARGV' 60 lune run z-nile/.tracker/issues/c0181/experiments/E3-lint-feasibility
local fs = require("@lune/fs")
local process = require("@lune/process")

local started = os.clock()
local texts: { [string]: string } = {}
local bytes = 0
for path in string.gmatch(process.exec("git", { "ls-files" }).stdout, "[^\n]+") do
	if string.match(path, "%.luau$") or string.match(path, "%.sh$") or string.match(path, "%.md$") then
		if fs.isFile(path) then
			local text = fs.readFile(path)
			texts[path] = text
			bytes += #text
		end
	end
end
print(string.format("read %d bytes in %.2f s", bytes, os.clock() - started))

local function lines(text: string): { string }
	local out = {}
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(out, line)
	end
	return out
end

-- zz-rules/grep-markers-before-merge-commit: a conflict marker line in a tracked file
local markers = 0
for _, text in texts do
	for _, line in lines(text) do
		if string.match(line, "^<<<<<<< ") or string.match(line, "^>>>>>>> ") or line == "=======" then
			markers += 1
		end
	end
end
print("conflict markers:", markers)

-- zz-test/plain-find-for-literals: a hyphen or dot literal passed to find/match/gsub as a pattern. Every hit is an
-- intended pattern (`.-`), which is why this lint is "part": it needs `lint-ok` marks.
local plain = 0
for path, text in texts do
	if string.match(path, "%.luau$") and not string.find(path, "/done/", 1, true) then
		for _, line in lines(text) do
			for lit in string.gmatch(line, 'string%.%a+%([^,"]+,%s*"([^"]*)"%s*%)') do
				if string.find(lit, "[%-%.]") and not string.find(lit, "[%%%^%$%(%)%[%]%*%+%?]") then
					plain += 1
				end
			end
		end
	end
end
print("hyphen/dot literal used as a pattern (two-argument call):", plain)

-- zz-test/pipe-filter-keeps-the-failure: `cmd | filter || true` in a check.sh outside done/
local pipes = 0
for path, text in texts do
	if string.match(path, "check%.sh$") and not string.find(path, "/done/", 1, true) then
		for _, line in lines(text) do
			if string.find(line, "|| true", 1, true) and string.match(line, "[^|]|[^|]") then
				pipes += 1
			end
		end
	end
end
print("`| ... || true` lines in check.sh outside done/:", pipes)

-- z-design/touched-paths-exist: every Touched modules path, or its parent folder, exists, in open issues that are
-- designed (design: reviewed or ready)
local checked, missing, items = 0, 0, 0
for path, text in texts do
	if string.match(path, "/issues/[cfd]%d+/[cfd]%d+%.md$") and not string.find(path, "/done/", 1, true) then
		local design = string.match(text, "\ndesign:%s*(%a+)")
		local section = string.match(text, "### Touched modules(.-)\n### ")
		if design ~= "draft" and section then
			items += 1
			for p in string.gmatch(section, "\n%- `([^`]+)`") do
				checked += 1
				local bare = string.gsub(p, "/$", "")
				local parent = string.match(bare, "^(.*)/[^/]+$") or "."
				if not (fs.isFile(bare) or fs.isDir(bare) or fs.isDir(parent)) then
					missing += 1
				end
			end
		end
	end
end
print(`designed open issues {items}: Touched paths {checked}, naming no file or folder {missing}`)
print(string.format("scan total %.2f s", os.clock() - started))
