--!strict
-- Conflict markers (c0163): a tracked text file holding a line that git writes around a conflict fails the gate, in
-- every mode. Pure over texts: main.luau's `markers` command lists and reads the files and origin/main's exemption
-- list, and this module says which lines are markers and which exemptions are well formed.
--
-- A marker line starts with seven `<`, `>` or `|` followed by a space or the end of the line (git's
-- `<<<<<<< HEAD`, `>>>>>>> origin/main` and, with the diff3 and zdiff3 styles, `||||||| base`), or is exactly
-- seven `=` (a trailing carriage return is ignored, so a CRLF file is read the same).
local markers = {}

-- The exemption list: one repository-relative path per line; blank lines and `#` comments allowed. Read from
-- origin/main (zz-arch rule 7: configuration that widens a guard never comes from the working tree).
markers.EXEMPTIONS = "z-nile/marker-exemptions.txt"

export type Hit = { path: string, line: number }

local OPENERS = { "<<<<<<<", ">>>>>>>", "|||||||" }

-- Whether one line (without its newline) is a conflict marker.
function markers.isMarker(line: string): boolean
	local l = if string.sub(line, -1) == "\r" then string.sub(line, 1, -2) else line
	if l == "=======" then
		return true
	end
	local head = string.sub(l, 1, 7)
	for _, o in OPENERS do
		if head == o then
			local after = string.sub(l, 8, 8)
			return after == "" or after == " "
		end
	end
	return false
end

-- Whether a file's text is binary: git's own rule, a NUL byte in its first 8000 bytes.
function markers.isBinary(text: string): boolean
	return string.find(string.sub(text, 1, 8000), "\0", 1, true) ~= nil
end

-- Every marker line of one file, in order, with its 1-based line number. A binary text has none.
function markers.scan(path: string, text: string): { Hit }
	local out: { Hit } = {}
	if markers.isBinary(text) then
		return out
	end
	local n = 0
	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		if markers.isMarker(line) then
			table.insert(out, { path = path, line = n })
		end
	end
	return out
end

-- The exemption list's paths, and a problem for each line that is not one plain repository-relative path: a glob
-- (`*`, `?`, `[`), an absolute path, a `..` step, a backslash or a path named twice. Every problem names the line.
function markers.parseExemptions(text: string): ({ [string]: boolean }, { string })
	local paths: { [string]: boolean } = {}
	local problems: { string } = {}
	local n = 0
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n += 1
		local line = string.match(raw, "^%s*(.-)%s*$") :: string
		if line ~= "" and string.sub(line, 1, 1) ~= "#" then
			local why: string? = nil
			if string.find(line, "[%*%?%[]") then
				why = "a pattern; name one file"
			elseif string.sub(line, 1, 1) == "/" then
				why = "an absolute path; name it from the repository root"
			elseif string.find(line, "\\", 1, true) then
				why = "a backslash; use /"
			elseif line == ".." or string.find("/" .. line .. "/", "/../", 1, true) then
				why = "a .. step"
			elseif paths[line] then
				why = "named twice"
			end
			if why then
				table.insert(problems, `{markers.EXEMPTIONS}:{n}: {line} is {why}`)
			else
				paths[line] = true
			end
		end
	end
	return paths, problems
end

-- The gate's verdict over the files to scan (path and text): one problem per marker line outside an exempted file,
-- as `<path>:<line>: conflict marker`, and one per exemption that names no file in `tracked` (every tracked text
-- file's path). Sorted by path.
function markers.check(
	files: { { path: string, text: string } },
	exempt: { [string]: boolean },
	tracked: { [string]: boolean }
): { string }
	local problems: { string } = {}
	local sorted = table.clone(files)
	table.sort(sorted, function(a, b)
		return a.path < b.path
	end)
	for _, f in sorted do
		if not exempt[f.path] then
			for _, h in markers.scan(f.path, f.text) do
				table.insert(problems, `{h.path}:{h.line}: conflict marker`)
			end
		end
	end
	local stale: { string } = {}
	for p in exempt do
		if not tracked[p] then
			table.insert(stale, `{markers.EXEMPTIONS}: {p} is exempted but is not a tracked text file`)
		end
	end
	table.sort(stale)
	for _, s in stale do
		table.insert(problems, s)
	end
	return problems
end

return markers
