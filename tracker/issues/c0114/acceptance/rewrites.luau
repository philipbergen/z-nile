--!strict
-- c0114 AC14: the one rewrite finished items' check.sh files get (decided with the user, 2026-10-21: "Rewrite
-- finished files"). It is the user's exception to "sequestered files never change", for finished items only, in
-- c0114's PR: each moved path becomes its new location, and nothing else changes, apart from the few edits SPECIAL
-- lists, where a finished check reads a folder whose items now sit in two roots. Unfinished items' files never
-- change. Used by finished.spec.luau (no old path is left) and finished.luau (each file is its base text, rewritten).
local rewrites = {}

-- a path character: a token that follows one is part of a longer path, never the moved one
local function pathChar(c: string): boolean
	return string.match(c, "[%w_%.%-]") ~= nil
end

-- Every occurrence of `old` that does not follow a path character, replaced with new(prev) (prev: the character
-- before it, "" at the start).
local function replace(
	text: string,
	old: string,
	new: (prev: string) -> string,
	skip: ((before: string) -> boolean)?
): string
	local out: { string } = {}
	local i = 1
	while true do
		local s, e = string.find(text, old, i, true)
		if not s then
			table.insert(out, string.sub(text, i))
			return table.concat(out)
		end
		local prev = if s > 1 then string.sub(text, s - 1, s - 1) else ""
		table.insert(out, string.sub(text, i, s - 1))
		if pathChar(prev) or (skip and skip(string.sub(text, 1, s - 1))) then
			table.insert(out, old)
		else
			table.insert(out, new(prev))
		end
		i = (e :: number) + 1
	end
end

local function to(new: string): (string) -> string
	return function()
		return new
	end
end

-- the build's moved paths (c0114 §1); scripts/tracker.sh and bare tracker.sh are the command, ./zn (<dir>/zn
-- after a slash)
rewrites.SCRIPTS = {
	{ "scripts/tracker/", "z-nile/engine/" },
	{ "scripts/lib/ac.sh", "z-nile/lib/ac.sh" },
	{ "scripts/lib/fence.sh", "z-nile/lib/fence.sh" },
	{ "scripts/lib/par.sh", "z-nile/lib/par.sh" },
	{ "scripts/lib/replace-file.pl", "z-nile/lib/replace-file.pl" },
	{ "scripts/lib/git-hooks", "z-nile/lib/git-hooks" },
	{ "scripts/lib/sh.luau", "z-nile/lib/sh.luau" },
	{ "scripts/lib/graph.luau", "z-nile/lib/graph.luau" },
	{ "scripts/lib/changed.luau", "z-nile/lib/changed.luau" },
	{ "scripts/check.sh", "z-nile/check.sh" },
	{ "scripts/setup.sh", "z-nile/setup.sh" },
	{ "scripts/ci-verify.sh", "z-nile/ci-verify.sh" },
	{ "scripts/affected", "z-nile/affected" },
	{ "scripts/vendor", "z-nile/vendor" },
}
rewrites.TRACKER = {
	{ "tracker/templates", "z-nile/templates" },
	{ "tracker/compaction.txt", "z-nile/compaction.txt" },
}

-- `.claude/skills/tracker/...` is a skill, not the tracker's folder
local function inSkills(before: string): boolean
	return string.sub(before, -7) == "skills/"
end

-- `text` with every moved path rewritten. `moved`: the ids whose folders moved into z-nile/.tracker/; their item
-- paths (`tracker/issues/[active/|done/]<id>`, and rafts alike) move with them.
function rewrites.paths(text: string, moved: { [string]: boolean }): string
	text = replace(text, "scripts/tracker.sh", function(prev)
		return if prev == "/" then "zn" else "./zn"
	end)
	-- the command as a regular expression greps for it in a skill: `zn` matches `./zn`
	text = replace(text, "scripts/tracker\\.sh", to("zn"))
	text = replace(text, "tracker\\.sh", function(prev)
		return if prev == "/" then "tracker\\.sh" else "zn"
	end)
	-- the bare command name, as skills and messages wrote it
	text = replace(text, "tracker.sh", function(prev)
		return if prev == "/" then "tracker.sh" else "./zn"
	end)
	for _, r in rewrites.SCRIPTS do
		text = replace(text, r[1], to(r[2]))
	end
	for _, r in rewrites.TRACKER do
		text = replace(text, r[1], to(r[2]), inSkills)
	end
	for _, kind in { "issues", "rafts" } do
		local old = `tracker/{kind}/`
		local out: { string } = {}
		local i = 1
		while true do
			local s, e = string.find(text, old, i, true)
			if not s then
				table.insert(out, string.sub(text, i))
				break
			end
			table.insert(out, string.sub(text, i, s - 1))
			local prev = if s > 1 then string.sub(text, s - 1, s - 1) else ""
			local rest = string.sub(text, (e :: number) + 1)
			local id = string.match(rest, "^([fdcR]%d%d%d%d)")
				or string.match(rest, "^active/([fdcR]%d%d%d%d)")
				or string.match(rest, "^done/([fdcR]%d%d%d%d)")
			if id and moved[id] and not pathChar(prev) and not inSkills(string.sub(text, 1, s - 1)) then
				table.insert(out, "z-nile/." .. old)
			else
				table.insert(out, old)
			end
			i = (e :: number) + 1
		end
		text = table.concat(out)
	end
	return text
end

-- Finished checks whose meaning needs more than a path: a folder that held every item and now has two roots, a copy
-- of the runner's guards, a gate stage or spec case renamed with the move, and three spec case names the rewrite would
-- otherwise change. Keyed by item id: literal { old, new } edits applied after `paths`, in order.
rewrites.SPECIAL = {
	-- greps for a promoted spec's case name, which keeps its words: the rewrite left them as they are
	c0007 = { { "z-nile/affected takes its changed files", "scripts/affected takes its changed files" } },
	c0034 = { { "./zn check and done refuse to run", "tracker.sh check and done refuse to run" } },
	c0045 = { { '"./zn commit refuses', '"tracker.sh commit refuses' } },
	-- the gate's moved stage names and spec cases (c0114 renamed them with the move)
	c0049 = {
		{ "tests \\+ scripts with Lune definitions", "tests \\+ scripts \\+ z-nile with Lune definitions" },
	},
	c0077 = {
		{
			'"every .cache line in scripts/ is on the reviewed list"',
			'"every .cache line in scripts/ and z-nile/ is on the reviewed list"',
		},
	},
	-- copies of the runner and its guards: the guards now live in z-nile/lib/
	c0058 = {
		{ 'mkdir -p "$copy/scripts/lib"', 'mkdir -p "$copy/z-nile/lib"' },
		{ '"$copy/scripts/lib/"', '"$copy/z-nile/lib/"' },
	},
	c0076 = {
		{
			"tests/run.luau tests/lib scripts/lib .luaurc",
			"tests/run.luau tests/lib scripts/lib z-nile/lib .luaurc",
		},
		{
			"tests/run.luau tests/lib scripts/lib .luaurc",
			"tests/run.luau tests/lib scripts/lib z-nile/lib .luaurc",
		},
	},
	-- every item folder, in both roots
	c0044 = {
		{ 'find tracker -name "[fdcR]', 'find tracker z-nile/.tracker -name "[fdcR]' },
		{
			"find tracker/issues tracker/rafts -maxdepth",
			"find tracker/issues tracker/rafts z-nile/.tracker/issues z-nile/.tracker/rafts -maxdepth",
		},
	},
	-- five done tooling items, by brace list
	c0067 = { { "tracker/issues/done/{c0005,", "z-nile/.tracker/issues/done/{c0005," } },
	-- every finished check.sh, in both roots
	R0013 = {
		{
			"for f in tracker/issues/done/*/check.sh tracker/rafts/done/*/check.sh; do",
			"for f in {tracker,z-nile/.tracker}/{issues,rafts}/done/*/check.sh; do",
		},
	},
	-- its members, tooling items, by variable
	R0025 = {
		{
			'bash "tracker/issues/done/$id/check.sh" >/dev/null',
			'bash "z-nile/.tracker/issues/done/$id/check.sh" >/dev/null',
		},
		{
			'bash "tracker/issues/done/$id/check.sh" | grep',
			'bash "z-nile/.tracker/issues/done/$id/check.sh" | grep',
		},
	},
} :: { [string]: { { string } } }

-- What a finished item's file must be: its base text, paths rewritten, then its special edits.
function rewrites.expected(id: string, base: string, moved: { [string]: boolean }): string
	local text = rewrites.paths(base, moved)
	local edits: { { string } } = rewrites.SPECIAL[id] or {}
	for _, edit in edits do
		local s, e = string.find(text, edit[1], 1, true)
		if not s then
			error(`rewrites: {id}: {edit[1]} not found`, 0)
		end
		text = string.sub(text, 1, s - 1) .. edit[2] .. string.sub(text, (e :: number) + 1)
	end
	return text
end

return rewrites
