--!strict
-- c0374 E6 (design review 001 F4): what the change stops reading. Runs the prototype's `singleQuoted` (copied from
-- prototype.patch by hand) with rewrites.literals over every check.sh of
-- every project's issues and rafts (finished or not: the unfinished ones are the finished files of tomorrow), and
-- prints each literal the change would mask (a bare name inside single quotes) and each file whose quotes do not balance.
-- Usage, from z-nile/: ./zn run --time 120 -- lune run <this file> -- <checkout top>
local fs = require("@lune/fs")
local process = require("@lune/process")
local rewrites = require("@tests/acceptance/c0120/rewrites")

-- c0374: the bytes of `text` inside single quotes, as `mask[line][column]` (a line and column are the scanner's: lines
-- split at "\n", columns are bytes in the line). rewrites.literals reads a word in single-quoted text as a path
-- (it tracks only double quotes), though a finished check passes such text to its own helpers (`vocabulary`, `cases`)
-- and to `bash -c`. The walk keeps a stack of quoting contexts, so `'"'"'`, an escaped quote, a comment and the quotes
-- inside `$( )` are read as the shell reads them; it returns nil when the text ends inside a quote or a `$(`, and the
-- caller then fails closed. One `for` over the bytes, so it always ends.
local function singleQuoted(text: string): { [number]: { [number]: boolean } }?
	local mask: { [number]: { [number]: boolean } } = {}
	local stack: { string } = { "normal" } -- "normal", "double", "single", or "paren" (a `$(`, closed by `)`)
	local line, col, skip, comment = 1, 0, false, false
	local prev = "\n"
	for i = 1, #text do
		local c = string.sub(text, i, i)
		col += 1
		if c == "\n" then
			line += 1
			col = 0
			comment = false
			skip = false
		elseif skip then
			skip = false
		elseif not comment then -- a comment runs to the end of its line
			local top = stack[#stack]
			if top == "single" then
				if c == "'" then
					table.remove(stack)
				else
					mask[line] = mask[line] or {}
					mask[line][col] = true
				end
			elseif c == "\\" then
				skip = true
			elseif c == "'" and top ~= "double" then
				table.insert(stack, "single")
			elseif c == '"' then
				if top == "double" then
					table.remove(stack)
				else
					table.insert(stack, "double")
				end
			elseif c == "(" and prev == "$" then
				table.insert(stack, "paren")
			elseif c == ")" and top == "paren" then
				table.remove(stack)
			elseif c == "#" and top ~= "double" and string.find(prev, "^[%s;|&(]$") then
				comment = true
			end
		end
		prev = c
	end
	if #stack ~= 1 then
		return nil
	end
	return mask
end

local top = process.args[#process.args] :: string
local files: { string } = {}
for _, root in { "z-nile", "pickman", "arcade", "portal", "snake", "invaders", "asteroids" } do
	for _, kind in { "issues", "rafts" } do
		for _, state in { "done", "active", "." } do
			local dir = if state == "."
				then `{top}/{root}/.tracker/{kind}`
				else `{top}/{root}/.tracker/{kind}/{state}`
			if fs.isDir(dir) then
				for _, id in fs.readDir(dir) do
					local f = `{dir}/{id}/check.sh`
					if fs.isDir(`{dir}/{id}`) and fs.isFile(f) then
						table.insert(files, f)
					end
				end
			end
		end
	end
end
table.sort(files)
local masked, unbalanced, heredoc = 0, 0, 0
for _, f in files do
	local text = fs.readFile(f)
	if string.find(text, "<<[^<]") then
		heredoc += 1
	end
	local single = singleQuoted(text)
	if not single then
		unbalanced += 1
		print(`UNBALANCED {string.sub(f, #top + 2)}`)
		continue
	end
	for _, l in rewrites.literals(text) do
		if not string.find(l.path, "/", 1, true) and (single[l.line] or {})[l.first] == true then
			masked += 1
			print(`MASKED {string.sub(f, #top + 2)}:{l.line} {l.word}`)
		end
	end
end
print(`{#files} check.sh files, {unbalanced} unbalanced, {masked} literals masked, {heredoc} with a heredoc`)
