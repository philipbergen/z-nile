--!strict
-- f0420 step 3: the light path. An easy ticket that is in no raft (or in the single raft `ready <issue>` made for it)
-- goes from designed to done in one pull request, with ONE review: the final review, which also reviews the code.
-- This is the one place that says what "light" means. Pure: facts in, an answer out. Reads are lightgit's.
--
-- A ticket is light when ALL of these hold:
--   - it is the only ticket of its raft (a raftless ticket is a raft of one in the making);
--   - its `risk:` is easy (absent means normal, so not light; a bad value is not light);
--   - its design is ready and it has no dependency that has not landed;
--   - its Regression guard says `Overrides: none` and nothing else about overrides (`light.overridesNone`: fail
--     closed, a change to a finished ticket's promoted spec needs the separate code review whatever the risk says);
--   - once built, its own diff (from the merge base, renames counted as add plus delete) touches none of the files
--     that protect the repository and the pipeline (`light.PROTECTED`), no promoted acceptance spec, and changes at
--     most `light.BOUND` lines outside specs, watch files and the tracker (the walk then asks for the code review as
--     for any raft, and says why).
-- Risk is set by the author's branch, so the last two are what keep "easy" honest.

local rounds = require("./rounds")

local light = {}

-- Changed lines (added plus removed) outside specs, watch files and the tracker above which an easy ticket is no
-- longer light. A guess made in the build (f0420 Design, G12): 150 is about a page of engine code, the size of the
-- easy tickets seen so far. Too low sends honest easy tickets to the code review they would have had anyway; too high
-- lets an easy label cover a large change with one review instead of two.
light.BOUND = 150

-- The files that protect the repository and the pipeline: a change to any of them is never light, whatever its size,
-- so it always gets the separate code review. `files` are whole paths, `folders` are path prefixes.
light.PROTECTED = {
	files = {
		"zn",
		".models.toml",
		".claude/settings.json",
		"scripts/check.sh",
		"z-nile/check.sh",
		"z-nile/affected.luau",
		"z-nile/specs.luau",
		"z-nile/lib/fence.sh",
		"z-nile/lib/ac.sh",
		"z-nile/lib/watch.luau",
		"z-nile/lib/bounded.pl",
		"z-nile/lib/cpu.sh",
		"z-nile/tests/run.luau",
		"z-nile/tests/lib/fence.luau",
		"z-nile/tests/lib/seal.luau",
		"z-nile/tests/tooling/repo-fence.spec.luau",
		"z-nile/engine/light.luau",
		"z-nile/engine/lightgit.luau",
		"z-nile/engine/lightready.luau",
		"z-nile/engine/publish.luau",
		"z-nile/engine/boundcmd.luau",
		"z-nile/engine/trackerstate.luau",
		"z-nile/engine/broker.luau",
		"z-nile/engine/closing.luau",
		"z-nile/engine/paths.luau",
		"z-nile/engine/ids.luau",
		"z-nile/engine/credential.luau",
		"z-nile/engine/agentenv.luau",
		"z-nile/engine/reap.luau",
		"z-nile/engine/approval.luau",
		"z-nile/engine/contract.luau",
		"z-nile/engine/approvewalk.luau",
		"z-nile/engine/approverun.luau",
		"z-nile/engine/approveplace.luau",
	},
	folders = {
		"z-nile/lib/git-hooks/",
		"scripts/hooks/",
		"z-nile/bin/",
		".github/workflows/",
		"z-nile/go/",
	},
}
-- Besides these, every registered project home's check.sh is protected (the homes come from origin/main's registry:
-- `judgeDiff`'s second argument, `lightgit.homesOf`).

export type Member = {
	risk: string?,
	doc: string, -- the ticket's document (for its raft: line and its Regression guard)
	designReady: boolean,
}

export type Facts = {
	members: { Member },
	depsMet: boolean,
	changed: number?, -- lines changed outside specs by the ticket's diff, once it is built. Nil: not built yet.
	diffWhy: string?, -- the protected or acceptance file its diff touches (light.judgeDiff), once it is built
}

local function trim(s: string): string
	return (string.gsub(string.gsub(s, "^%s+", ""), "%s+$", ""))
end

-- The lines of the Regression guard section at any heading level, to the next heading of the same or higher level
-- outside a code fence. Nil when there is no such section.
local function guardLines(doc: string): { string }?
	local out: { string } = {}
	local level = 0
	local sections = 0
	local done = false
	local fenced = false
	for line in string.gmatch(doc .. "\n", "([^\n]*)\n") do
		local fence = string.match(line, "^%s*```") ~= nil or string.match(line, "^%s*~~~") ~= nil
		if fence then
			fenced = not fenced
		end
		local hashes, title = string.match(line, "^(#+)%s+(.-)%s*$")
		if not fenced and hashes and string.lower(title or "") == "regression guard" then
			sections += 1
		end
		if level == 0 then
			if not fenced and hashes and string.lower(title or "") == "regression guard" then
				level = #hashes
			end
		else
			if not fenced and not fence and hashes and #hashes <= level then
				done = true
			end
			if not done then
				table.insert(out, line)
			end
		end
	end
	-- more than one Regression guard section is a document that says two things: not plain
	return if level == 0 or sections > 1 then nil else out
end

-- One `Overrides` entry of a line: its value, or nil when the line is not one. A leading list marker and `**`
-- emphasis around the word are allowed.
local function entryOf(line: string): string?
	local plain = trim(line)
	plain = string.gsub(plain, "^[-*+]%s+", "")
	plain = string.gsub(plain, "%*%*", "")
	plain = string.gsub(plain, "__", "")
	local value = string.match(plain, "^Overrides%s*:%s*(.-)%s*$")
	return value
end

local function indentOf(line: string): number
	return #(string.match(line, "^(%s*)") or "")
end

local function isListLine(line: string): boolean
	return string.match(line, "^%s*[-*+]%s") ~= nil or string.match(line, "^%s*%d+[.)]%s") ~= nil
end

-- True only when the document's Regression guard section is found and says, exactly once, `Overrides: none` (or
-- `none (...)`), with no list lines under it and no mention of `tests/acceptance/` anywhere in the section. Every
-- other shape (no section, no entry, several, an empty entry, a list, an emphasis form with another value) is false:
-- a ticket is light on this point only when it is plain.
function light.overridesNone(doc: string): boolean
	local lines = guardLines(doc)
	if not lines then
		return false
	end
	local entries = 0
	local value = ""
	local at = 0
	for i, line in lines do
		if string.find(line, "tests/acceptance/", 1, true) or string.find(line, ".spec.luau", 1, true) then
			return false
		end
		local v = entryOf(line)
		if v then
			entries += 1
			value = v
			at = i
		elseif string.find(string.lower(line), "overrid", 1, true) then
			return false -- another word for it (Override:, a table, prose): not the one plain entry
		end
	end
	if entries ~= 1 then
		return false
	end
	local bare = string.lower((string.gsub(trim(value), "%.$", "")))
	if bare ~= "none" and string.sub(bare, 1, 6) ~= "none (" then
		return false
	end
	-- list lines that belong to the entry: right under it, indented below a list entry, or any list line directly under
	-- a plain `Overrides:` line
	local entryLine = lines[at]
	local entryIsList = string.match(entryLine, "^%s*[-*+]%s") ~= nil
	for i = at + 1, #lines do
		local line = lines[i]
		if trim(line) == "" then
			break
		end
		if entryIsList then
			if indentOf(line) > indentOf(entryLine) then
				return false
			end
			break
		end
		if isListLine(line) or indentOf(line) > 0 then
			return false
		end
		break
	end
	return true
end

-- Whether a front-matter block of the document has a `raft:` line (an empty one is fine).
function light.hasRaftLine(doc: string): boolean
	local block = string.match(doc, "^%-%-%-\n(.-)\n%-%-%-")
	return block ~= nil and string.find("\n" .. block .. "\n", "\nraft:[^\n]*\n") ~= nil
end

local function protectedFile(path: string, homes: { string }?): boolean
	if table.find(light.PROTECTED.files, path) then
		return true
	end
	for _, home in homes or {} :: { string } do
		if path == `{home}/check.sh` then
			return true
		end
	end
	for _, folder in light.PROTECTED.folders do
		if string.sub(path, 1, #folder) == folder then
			return true
		end
	end
	return false
end

-- A path whose lines do not count toward the bound: a spec outside any tests/acceptance/ folder, a watch file, or
-- tracker text. Everything else counts, tests/lib helpers and the spec runner included.
local function exempt(path: string): boolean
	if string.find(path, "/.tracker/", 1, true) or string.sub(path, 1, 9) == ".tracker/" then
		return true
	end
	if string.match(path, "%.watch%.txt$") then
		return true
	end
	-- a spec counts as zero only under a tests/ folder (never tests/acceptance/): a spec anywhere else is code
	local underTests = string.sub(path, 1, 6) == "tests/" or string.find(path, "/tests/", 1, true) ~= nil
	return string.match(path, "%.spec%.luau$") ~= nil
		and underTests
		and not string.find(path, "tests/acceptance/", 1, true)
end

-- The diff of a ticket (`git diff --numstat --no-renames <merge-base>...<tip>`): the changed lines (added plus
-- removed) outside the exempt files, and the reason it is never light, naming the path: a file under a
-- tests/acceptance/ folder (a promoted spec of a finished ticket), or one of the protected files. A binary file
-- counts as the bound plus one.
function light.judgeDiff(numstat: string, homes: { string }?): (number, string?)
	local total = 0
	local why: string? = nil
	for line in string.gmatch(numstat, "[^\n]+") do
		local added, removed, path = string.match(line, "^(%S+)\t(%S+)\t(.+)$")
		if added and removed and path then
			if why == nil and not string.find(path, "/.tracker/", 1, true) then
				if string.find(path, "tests/acceptance/", 1, true) then
					why =
						`its diff changes {path}, a promoted acceptance spec (the separate code review covers that)`
				elseif protectedFile(path, homes) then
					why =
						`its diff changes {path}, a file that protects the repository and the pipeline (the separate code review covers that)`
				end
			end
			if not exempt(path) then
				total += (tonumber(added) or light.BOUND + 1) + (tonumber(removed) or 0)
			end
		end
	end
	return total, why
end

-- nil when the ticket is light, else the first reason it is not.
function light.reason(f: Facts): string?
	if #f.members ~= 1 then
		return "its raft has more than one ticket"
	end
	local m = f.members[1]
	local level, problem = rounds.level(m.risk)
	if not level then
		return problem :: string
	end
	if level ~= "easy" then
		return `its risk is {level}, not easy`
	end
	if not m.designReady then
		return "its design is not ready"
	end
	if not f.depsMet then
		return "a dependency has not landed"
	end
	if not light.hasRaftLine(m.doc) then
		return "its document has no raft: line: add an empty one"
	end
	if not light.overridesNone(m.doc) then
		return "its Regression guard does not say Overrides: none"
	end
	if f.diffWhy ~= nil then
		return f.diffWhy
	end
	if f.changed ~= nil and (f.changed :: number) > light.BOUND then
		return `its diff changes {f.changed} lines outside specs, over the bound of {light.BOUND}`
	end
	return nil
end

return light
