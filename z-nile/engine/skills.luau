--!strict
-- Skill folders and their links (c0115). z-nile's skills live in z-nile/skills/<name>/SKILL.md and a project's own
-- in <project>/skills/<name>/SKILL.md (the project's name in z-nile/projects.toml); the harnesses find each through
-- .claude/skills/<name>, a committed relative link to the real folder (../../<folder>/<name>). `plan` and `diff` are
-- pure; `load` only reads, and `apply` writes the links. The one reader of the skill folders (lesson
-- zz-arch/one-reader-per-format): lessons.luau and the prompt take their folders from `skills.folders`.
local fs = require("@lune/fs")
local process = require("@lune/process")
local projects = require("./projects")

local skills = {}

skills.LINKS = ".claude/skills"
skills.ZNILE = "z-nile"
-- The skills a raft's prompt inlines from z-nile, in this order; the raft's project's own skills follow (c0115).
skills.INLINED = { "zz-execute", "zz-rules", "zz-arch", "zz-test", "zz-review" }

-- One folder of skills: the project it belongs to and its repo-relative path ("z-nile/skills").
export type Folder = { project: string, path: string }
-- One entry found in a folder: its folder name and its SKILL.md text (nil when it has none).
export type Entry = { name: string, text: string? }
export type Found = { folder: Folder, entries: { Entry } }
-- A skill: its name, its project and its real folder ("z-nile/skills/zz-test").
export type Skill = { name: string, project: string, dir: string }
-- What .claude/skills holds: per entry name, the link's target, or false for anything that is not a link.
export type Present = { [string]: string | false }

-- Every project's skills folder, z-nile's first: "<home>/skills" for each project of the registry, its home being the
-- folder that holds its root (`pickman/` for `pickman/.tracker`, c0120), and z-nile's even when the registry does not
-- list it.
function skills.folders(reg: projects.Registry): { Folder }
	local out: { Folder } = { { project = skills.ZNILE, path = `{skills.ZNILE}/skills` } }
	for _, p in reg.projects do
		if p.name ~= skills.ZNILE then
			-- a parsed registry's roots are all `<name>/.tracker` (projects.parse), so every project has a folder
			table.insert(out, { project = p.name, path = `{projects.folderOf(p.root) or p.name}/skills` })
		end
	end
	return out
end

-- The `name:` of a SKILL.md's frontmatter, or nil.
function skills.frontName(text: string): string?
	local front = string.match(text, "^%-%-%-\n(.-)\n%-%-%-")
	if not front then
		return nil
	end
	for line in string.gmatch(front, "[^\n]+") do
		local v = string.match(line, "^name:%s*(.-)%s*$")
		if v then
			return v
		end
	end
	return nil
end

local function starts(s: string, prefix: string): boolean
	return string.sub(s, 1, #prefix) == prefix
end

-- The skills of the folders found, and every problem with them. Pure. A skill with a problem is left out.
function skills.plan(found: { Found }): ({ Skill }, { string })
	local out: { Skill } = {}
	local problems: { string } = {}
	local where: { [string]: string } = {}
	for _, f in found do
		for _, e in f.entries do
			local dir = `{f.folder.path}/{e.name}`
			if not e.text then
				table.insert(problems, `{dir}: no SKILL.md`)
				continue
			end
			local front = skills.frontName(e.text :: string)
			if front ~= e.name then
				table.insert(
					problems,
					`{dir}/SKILL.md: its name: is {front or "missing"}, not its folder's name {e.name}`
				)
				continue
			end
			local zn = starts(e.name, "z-") or starts(e.name, "zz-")
			if f.folder.project == skills.ZNILE and not zn then
				table.insert(
					problems,
					`{dir}: a z-nile skill is named z-… (the pipeline) or zz-… (inside a step)`
				)
				continue
			elseif f.folder.project ~= skills.ZNILE and zn then
				table.insert(
					problems,
					`{dir}: the z- and zz- prefixes are z-nile's; a {f.folder.project} skill is named {f.folder.project}-…`
				)
				continue
			elseif f.folder.project ~= skills.ZNILE and not starts(e.name, f.folder.project .. "-") then
				table.insert(problems, `{dir}: a {f.folder.project} skill is named {f.folder.project}-…`)
				continue
			end
			if where[e.name] then
				table.insert(problems, `skill {e.name} is in two folders: {where[e.name]} and {dir}`)
				continue
			end
			where[e.name] = dir
			table.insert(out, { name = e.name, project = f.folder.project, dir = dir })
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out, problems
end

-- The relative target of a skill's link in .claude/skills.
function skills.target(s: Skill): string
	return `../../{s.dir}`
end

-- What is wrong with .claude/skills for these skills. Pure; an empty list means it is exactly one link per skill.
function skills.diff(list: { Skill }, present: Present): { string }
	local problems: { string } = {}
	local want: { [string]: string } = {}
	for _, s in list do
		want[s.name] = skills.target(s)
	end
	local names: { string } = {}
	for name in want do
		table.insert(names, name)
	end
	for name in present do
		if not want[name] then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in names do
		local path = `{skills.LINKS}/{name}`
		local have, target = present[name], want[name]
		if have == false then
			table.insert(
				problems,
				if target
					then `{path}: not a link (it must be a link to {target})`
					else `{path}: not a link, and no skill folder has that name (move what it holds, then remove it)`
			)
		elseif not target then
			table.insert(problems, `{path}: no skill folder of that name (remove it)`)
		elseif have == nil then
			table.insert(problems, `{path}: missing (a link to {target})`)
		elseif have ~= target then
			table.insert(problems, `{path}: links to {have}, not {target}`)
		end
	end
	return problems
end

local function readlink(path: string): string | false
	local r = process.exec("readlink", { path })
	if not r.ok then
		return false
	end
	return (string.gsub(r.stdout, "\n$", ""))
end

-- `.claude` and `.claude/skills` must be real folders of the repository: a link there (to ~/.claude, say) would make
-- `skills` remove and write links outside it. fs.isDir follows links, so this asks readlink. Only reads.
function skills.linkedParents(root: string): { string }
	local out: { string } = {}
	for _, rel in { ".claude", skills.LINKS } do
		local target = readlink(`{root}/{rel}`)
		if target then
			table.insert(
				out,
				`{rel}: a link (to {target}), not a folder of this repository; make it a real folder`
			)
		end
	end
	return out
end

-- Reads every skills folder of `root`'s registry and what `root`/.claude/skills holds. Only reads.
function skills.load(root: string): ({ Found }, Present)
	local ok, reg = pcall(projects.load, root)
	if not ok then
		error(`skills: {reg}`, 0) -- a missing or bad registry refuses (c0114): never guess the skills folders
	end
	local registry: projects.Registry = reg :: projects.Registry
	local found: { Found } = {}
	for _, folder in skills.folders(registry) do
		local base = `{root}/{folder.path}`
		local entries: { Entry } = {}
		if fs.isDir(base) then
			local names = fs.readDir(base)
			table.sort(names)
			for _, name in names do
				if string.sub(name, 1, 1) ~= "." and fs.isDir(`{base}/{name}`) then
					local file = `{base}/{name}/SKILL.md`
					table.insert(
						entries,
						{ name = name, text = if fs.isFile(file) then fs.readFile(file) else nil }
					)
				end
			end
		end
		table.insert(found, { folder = folder, entries = entries })
	end
	local present: Present = {}
	local links = `{root}/{skills.LINKS}`
	if fs.isDir(links) then
		for _, name in fs.readDir(links) do
			present[name] = readlink(`{links}/{name}`)
		end
	end
	return found, present
end

-- Every tracked path under .claude/skills that is not a plain link one level deep: a real folder committed there, a
-- link deeper than .claude/skills/<name>, or `.claude` or `.claude/skills` itself tracked (as a link, say).
function skills.trackedNonLinks(root: string): { string }
	local r = process.exec("git", { "-C", root, "ls-files", "-s", "--", ".claude", skills.LINKS })
	local out: { string } = {}
	if not r.ok then
		return out
	end
	for line in string.gmatch(r.stdout, "[^\n]+") do
		local mode, path = string.match(line, "^(%d+) %x+ %d+\t(.+)$")
		if not mode or not path then
			continue
		end
		if path == ".claude" or path == skills.LINKS then
			table.insert(out, `{path}: tracked itself (mode {mode}); it must be a real folder`)
		elseif string.sub(path, 1, #skills.LINKS + 1) == skills.LINKS .. "/" then
			local rest = string.sub(path, #skills.LINKS + 2)
			if mode ~= "120000" then
				table.insert(out, `{path}: tracked as a file (mode {mode}), not a link`)
			elseif string.find(rest, "/", 1, true) then
				table.insert(
					out,
					`{path}: a link inside a skill's entry; only one link per skill, at {skills.LINKS}/<name>`
				)
			end
		end
	end
	return out
end

-- Writes .claude/skills under `root` as one link per skill: removes every link that is wrong or extra and makes
-- every missing one. Refuses (returns the problems, writing nothing) when an entry there is not a link.
function skills.apply(root: string, list: { Skill }, present: Present): ({ string }, { string })
	local links = `{root}/{skills.LINKS}`
	local refused: { string } = skills.linkedParents(root)
	if #refused > 0 then
		return {}, refused
	end
	for name, have in present do
		if have == false then
			table.insert(
				refused,
				`{skills.LINKS}/{name}: not a link; move what it holds into the skill's real folder and remove it`
			)
		end
	end
	if #refused > 0 then
		table.sort(refused)
		return {}, refused
	end
	local want: { [string]: string } = {}
	for _, s in list do
		want[s.name] = skills.target(s)
	end
	local done: { string } = {}
	for name, have in present do
		if want[name] ~= have then
			local r = process.exec("rm", { "-f", `{links}/{name}` })
			if not r.ok then
				error(`could not remove {skills.LINKS}/{name}: {r.stderr}`)
			end
			table.insert(done, `removed {skills.LINKS}/{name}`)
		end
	end
	fs.writeDir(links)
	for _, s in list do
		if present[s.name] ~= want[s.name] then
			local r = process.exec("ln", { "-s", want[s.name], `{links}/{s.name}` })
			if not r.ok then
				error(`could not link {skills.LINKS}/{s.name}: {r.stderr}`)
			end
			table.insert(done, `linked {skills.LINKS}/{s.name} -> {want[s.name]}`)
		end
	end
	table.sort(done)
	return done, {}
end

-- c0115 rename map: begin (the one place old skill names stay; absence.spec leaves exactly this block out)
-- c0115: the old skill folders a lesson id's first segment may still name, and the skill each was renamed to. Every
-- architecture lesson was the tooling's, so it became zz-arch's.
skills.RENAMED = {
	["make-issue"] = "z-ticket",
	["ticket-prep"] = "z-design",
	["ready-raft"] = "z-ready",
	["launch-raft"] = "z-run",
	["execute-raft"] = "zz-execute",
	["stop-raft"] = "z-stop",
	review = "zz-review",
	tracker = "zz-rules",
	metrics = "zz-stats",
	testing = "zz-test",
	architecture = "zz-arch",
} :: { [string]: string }

-- c0115: the real folder each old skill's path became (`architecture` meant the game's rules: pickman-arch).
skills.RENAMED_PATH = {
	["make-issue"] = "z-nile/skills/z-ticket",
	["ticket-prep"] = "z-nile/skills/z-design",
	["ready-raft"] = "z-nile/skills/z-ready",
	["launch-raft"] = "z-nile/skills/z-run",
	["execute-raft"] = "z-nile/skills/zz-execute",
	["stop-raft"] = "z-nile/skills/z-stop",
	review = "z-nile/skills/zz-review",
	tracker = "z-nile/skills/zz-rules",
	metrics = "z-nile/skills/zz-stats",
	testing = "z-nile/skills/zz-test",
	architecture = "pickman/skills/pickman-arch",
} :: { [string]: string }
-- The six old names that are only ever skill names, and the five ordinary words that name one only as "<word> skill".
skills.HYPHENATED = { "make-issue", "ticket-prep", "ready-raft", "launch-raft", "execute-raft", "stop-raft" }
skills.WORDS = { "review", "tracker", "metrics", "testing", "architecture" }
-- c0115 rename map: end

-- One old lesson id found in prose: its span, its old and new skill, and its slug (its renamed lesson exists).
export type OldId = { from: number, to: number, old: string, new: string, slug: string }

-- Every lesson that exists in `root`'s skills folders, as "<skill>/<slug>". Only reads.
function skills.lessonIndex(root: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local ok, reg = pcall(projects.load, root)
	if not ok then
		error(`skills: {reg}`, 0)
	end
	for _, folder in skills.folders(reg :: projects.Registry) do
		local base = `{root}/{folder.path}`
		if fs.isDir(base) then
			for _, skill in fs.readDir(base) do
				local dir = `{base}/{skill}/lessons`
				if fs.isDir(dir) then
					for _, name in fs.readDir(dir) do
						local slug = string.match(name, "^(.+)%.md$")
						if slug and string.sub(name, 1, 1) ~= "." then
							out[`{skill}/{slug}`] = true
						end
					end
				end
			end
		end
	end
	return out
end

local function nameChar(c: string): boolean
	return c ~= "" and string.match(c, "[%w_%-]") ~= nil
end

-- The prose old-id rule (c0115 §5): a token `<old>/<slug>`, with <old> a key of RENAMED, not after a name character,
-- `/` or `.`, counts only where its renamed lesson `<new>/<slug>` exists, so look-alike paths (tracker/next,
-- scripts/tracker/x, review/x) never count. It covers all text but a ledger's parsed ids, which lessons.ledgerOldIds
-- reads through lessons.parseHarvest, the format's one reader (the rename script, AC4 and AC5 all call these). Pure.
function skills.oldLessonIds(text: string, existing: { [string]: boolean }): { OldId }
	local out: { OldId } = {}
	for old, new in skills.RENAMED do
		local pos = 1
		while true do
			local a, b = string.find(text, old .. "/", pos, true)
			if not a then
				break
			end
			pos = (b :: number) + 1
			local prev = string.sub(text, (a :: number) - 1, (a :: number) - 1)
			local slug = string.match(string.sub(text, (b :: number) + 1), "^([%w][%w%-]*)")
			if slug and not nameChar(prev) and prev ~= "/" and prev ~= "." then
				local known = existing[`{new}/{slug}`] == true
				if known then
					table.insert(out, {
						from = a :: number,
						to = (b :: number) + #slug,
						old = old,
						new = new,
						slug = slug,
					})
				end
			end
		end
	end
	table.sort(out, function(x, y)
		return x.from < y.from
	end)
	return out
end

-- `text` (prose) with every old id whose renamed lesson exists renamed, and the count.
function skills.renameLessonIds(text: string, existing: { [string]: boolean }): (string, number)
	local parts: { string } = {}
	local last, n = 1, 0
	for _, id in skills.oldLessonIds(text, existing) do
		table.insert(parts, string.sub(text, last, id.from - 1))
		table.insert(parts, `{id.new}/{id.slug}`)
		last = id.to + 1
		n += 1
	end
	table.insert(parts, string.sub(text, last))
	return table.concat(parts), n
end

-- One old skill name found in a text: its span, the form it takes, and what replaces it.
export type OldName = { from: number, to: number, form: string, new: string }

-- The one old-name rule (c0115 §8; AC4 checks with it and the rename script renames lesson bodies with it). The
-- forms: a path through `.claude/skills/<old>`; a hyphenated name, bare or as a /command (not after a name character
-- or `.`, and not a promoted spec's file name `<old>.spec…`); "`<word>` skill" and "<word> skill" for the ordinary
-- words. Overlaps keep the earliest, longest match. Pure; sorted by position.
function skills.oldNames(text: string): { OldName }
	local found: { OldName } = {}
	local function each(needle: string, ok: (number, number) -> boolean, new: string)
		local pos = 1
		while true do
			local a, b = string.find(text, needle, pos, true)
			if not a then
				return
			end
			pos = (b :: number) + 1
			if ok(a :: number, b :: number) then
				table.insert(found, { from = a :: number, to = b :: number, form = needle, new = new })
			end
		end
	end
	local function before(a: number): string
		return string.sub(text, a - 1, a - 1)
	end
	local function after(b: number): string
		return string.sub(text, b + 1, b + 1)
	end
	for old, path in skills.RENAMED_PATH do
		each(`.claude/skills/{old}`, function(_, b)
			return not nameChar(after(b))
		end, path)
	end
	for _, old in skills.HYPHENATED do
		each(old, function(a, b)
			local prev = before(a)
			return not nameChar(prev)
				and prev ~= "."
				and not nameChar(after(b))
				and string.sub(text, b + 1, b + 5) ~= ".spec"
		end, skills.RENAMED[old])
	end
	for _, old in skills.WORDS do
		local new = string.match(skills.RENAMED_PATH[old], "[^/]+$") :: string
		each(`\`{old}\` skill`, function()
			return true
		end, `\`{new}\` skill`)
		each(`{old} skill`, function(a)
			local prev = before(a)
			return not nameChar(prev) and prev ~= "`"
		end, `{new} skill`)
	end
	table.sort(found, function(x, y)
		if x.from ~= y.from then
			return x.from < y.from
		end
		return x.to > y.to
	end)
	local out: { OldName } = {}
	local last = 0
	for _, f in found do
		if f.from > last then
			table.insert(out, f)
			last = f.to
		end
	end
	return out
end

-- `text` with every old skill name replaced by its new one, and the count.
function skills.renameOldNames(text: string): (string, number)
	local parts: { string } = {}
	local last = 1
	local found = skills.oldNames(text)
	for _, f in found do
		table.insert(parts, string.sub(text, last, f.from - 1))
		table.insert(parts, f.new)
		last = f.to + 1
	end
	table.insert(parts, string.sub(text, last))
	return table.concat(parts), #found
end

return skills
